module tb_top;

  import uvm_pkg::*;

  `include "uvm_macros.svh"

  import apb_uvm_pkg::*;

  localparam int ADDR_WIDTH = 32;
  localparam int DATA_WIDTH = 32;
  localparam time CLK_PERIOD = 10ns;  // 100 MHz

  logic PCLK = 0;
  always #(CLK_PERIOD / 2) PCLK = ~PCLK;

  logic PRESETn;
  initial begin
    PRESETn = 0;
    repeat (5) @(posedge PCLK);
    PRESETn = 1;
  end

  // Interface
  apb_if #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) apb (
      .PCLK   (PCLK),
      .PRESETn(PRESETn)
  );

  // DUT
  apb_slave #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) dut (
      .PCLK   (apb.PCLK),
      .PRESETn(apb.PRESETn),
      .PADDR  (apb.PADDR),
      .PPROT  (apb.PPROT),
      .PSEL   (apb.PSEL),
      .PENABLE(apb.PENABLE),
      .PWRITE (apb.PWRITE),
      .PWDATA (apb.PWDATA),
      .PSTRB  (apb.PSTRB),
      .PREADY (apb.PREADY),
      .PRDATA (apb.PRDATA),
      .PSLVERR(apb.PSLVERR)
  );

  initial begin
    `uvm_info("TB_TOP", "Starting simulation", UVM_LOW)
    uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb);
    run_test();
    `uvm_info("TB_TOP", "Simulation finished", UVM_LOW)
  end

  // Waves dumping is optional, controlled by +define+TRACE on the command line
`ifdef TRACE
  initial begin
    $dumpfile("build/waves.vcd");
    $dumpvars(0, tb_top);
  end
`endif

  // Hard backstop so a hung handshake can't run forever
  initial begin
    #1ms;
    `uvm_fatal("TB_TOP", "Global watchdog timeout (1ms) -- simulation hung")
  end

endmodule : tb_top
