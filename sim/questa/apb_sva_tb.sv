// Standalone directed harness for apb_protocol_checker under Questa Starter FPGA
// Edition, which licenses neither UVM's DPI nor randomize(). The checker rides
// in via tb/checker/apb_protocol_bind.sv.
module apb_sva_tb;

  localparam int  ADDR_WIDTH = 32;
  localparam int  DATA_WIDTH = 32;
  localparam time CLK_PERIOD = 10ns;

  logic PCLK = 0;
  always #(CLK_PERIOD / 2) PCLK = ~PCLK;
  logic PRESETn;

  apb_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) apb (
      .PCLK(PCLK), .PRESETn(PRESETn));

  apb_slave #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) dut (
      .PCLK(apb.PCLK), .PRESETn(apb.PRESETn),
      .PADDR(apb.PADDR), .PPROT(apb.PPROT), .PSEL(apb.PSEL), .PENABLE(apb.PENABLE),
      .PWRITE(apb.PWRITE), .PWDATA(apb.PWDATA), .PSTRB(apb.PSTRB),
      .PREADY(apb.PREADY), .PRDATA(apb.PRDATA), .PSLVERR(apb.PSLVERR));

  task automatic apb_xfer(input bit write, input logic [ADDR_WIDTH-1:0] addr,
                          input logic [DATA_WIDTH-1:0] data,
                          input logic [DATA_WIDTH/8-1:0] strb);
    @(posedge PCLK);
    apb.PSEL <= 1; apb.PENABLE <= 0;
    apb.PADDR <= addr; apb.PWRITE <= write; apb.PPROT <= 3'b000;
    apb.PWDATA <= data; apb.PSTRB <= strb;
    @(posedge PCLK);
    apb.PENABLE <= 1;
    do @(posedge PCLK); while (!apb.PREADY);
    apb.PSEL <= 0; apb.PENABLE <= 0;
  endtask

  // Gapless writes (PSEL held across transfers) to hit c_back_to_back.
  task automatic apb_b2b_writes(input logic [ADDR_WIDTH-1:0] base, input int n);
    @(posedge PCLK);
    for (int k = 0; k < n; k++) begin
      apb.PSEL <= 1; apb.PENABLE <= 0;
      apb.PADDR <= (base + (k << 2)) & 32'h3C; apb.PWRITE <= 1;
      apb.PWDATA <= $urandom; apb.PSTRB <= 4'hF; apb.PPROT <= 0;
      @(posedge PCLK);
      apb.PENABLE <= 1;
      do @(posedge PCLK); while (!apb.PREADY);
      apb.PENABLE <= 0;
    end
    apb.PSEL <= 0; apb.PENABLE <= 0;
  endtask

  // Illegal: moves PADDR during ACCESS -> trips a_addr_ctrl_stable.
  task automatic apb_xfer_addr_glitch(input logic [ADDR_WIDTH-1:0] addr);
    @(posedge PCLK);
    apb.PSEL <= 1; apb.PENABLE <= 0; apb.PADDR <= addr; apb.PWRITE <= 1;
    apb.PWDATA <= 32'hDEAD_BEEF; apb.PSTRB <= 4'hF; apb.PPROT <= 0;
    @(posedge PCLK);
    apb.PENABLE <= 1;
    apb.PADDR   <= addr ^ 32'h20;
    do @(posedge PCLK); while (!apb.PREADY);
    apb.PSEL <= 0; apb.PENABLE <= 0;
  endtask

  initial begin
    int bug;
    logic [ADDR_WIDTH-1:0] a;

    apb.PSEL = 0; apb.PENABLE = 0; apb.PADDR = 0; apb.PWRITE = 0;
    apb.PWDATA = 0; apb.PSTRB = 0; apb.PPROT = 0;

    PRESETn = 0;
    repeat (5) @(posedge PCLK);
    PRESETn = 1;
    @(posedge PCLK);

    for (int i = 0; i < 16; i++) begin
      a = (i % 4 == 0) ? (32'h100 + (i << 2))     // out of map -> DECERR
                       : ((i << 2) & 32'h3C);
      apb_xfer(1'b1, a, $urandom, $urandom_range(0, 15));
      apb_xfer(1'b0, a, '0, 4'h0);
    end

    apb_b2b_writes(32'h000, 4);

    if ($value$plusargs("BUG=%d", bug) && bug != 0) begin
      $display("[apb_sva_tb] injecting address-instability fault");
      apb_xfer_addr_glitch(32'h010);
    end

    repeat (5) @(posedge PCLK);
    $display("[apb_sva_tb] stimulus complete");
    $finish;
  end

  initial begin
    #1ms;
    $fatal(1, "[apb_sva_tb] watchdog timeout");
  end

endmodule : apb_sva_tb
