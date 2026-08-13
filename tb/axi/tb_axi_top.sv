// Top level for the AXI4-Lite environment. DUT stack:
//
//     axi_lite_if -> axi_lite_to_apb (third-party) -> apb_if -> apb_slave
//
// apb_if IS the wire between bridge and slave, not a copy of it, so the passive
// APB monitor observes the literal bus.

`include "axi/typedef.svh"

module tb_axi_top;

  import uvm_pkg::*;

  // No uvm_macros.svh include: the flattened UVM amalgamation predefines all
  // macros and ships no separate macros file.

  import apb_uvm_pkg::*;
  import axi_uvm_pkg::*;

  localparam int  ADDR_WIDTH = 32;
  localparam int  DATA_WIDTH = 32;
  localparam time CLK_PERIOD = 10ns;  // 100 MHz

  logic ACLK = 0;
  always #(CLK_PERIOD / 2) ACLK = ~ACLK;

  logic ARESETn;
  initial begin
    ARESETn = 0;
    repeat (5) @(posedge ACLK);
    ARESETn = 1;
  end

  // ---------------------------------------------------------------------------
  // Interfaces
  // ---------------------------------------------------------------------------
  axi_lite_if #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) axi (
      .ACLK   (ACLK),
      .ARESETn(ARESETn)
  );

  apb_if #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) apb (
      .PCLK   (ACLK),
      .PRESETn(ARESETn)
  );

  // ---------------------------------------------------------------------------
  // Struct types the bridge's ports demand
  // ---------------------------------------------------------------------------
  // The bridge takes struct-typed ports, so build those types with pulp's
  // typedef macros and pack/unpack the interface onto them.
  typedef logic [ADDR_WIDTH-1:0]   addr_t;
  typedef logic [DATA_WIDTH-1:0]   data_t;
  typedef logic [DATA_WIDTH/8-1:0] strb_t;

  `AXI_LITE_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t)
  `AXI_LITE_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t)
  `AXI_LITE_TYPEDEF_B_CHAN_T(b_chan_t)
  `AXI_LITE_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t)
  `AXI_LITE_TYPEDEF_R_CHAN_T(r_chan_t, data_t)
  `AXI_LITE_TYPEDEF_REQ_T(axi_lite_req_t, aw_chan_t, w_chan_t, ar_chan_t)
  `AXI_LITE_TYPEDEF_RESP_T(axi_lite_resp_t, b_chan_t, r_chan_t)

  // The bridge documents the exact APB struct layout it expects (see the header
  // comment in third_party/pulp/axi/src/axi_lite_to_apb.sv); these mirror it.
  typedef struct packed {
    addr_t          paddr;
    axi_pkg::prot_t pprot;
    logic           psel;
    logic           penable;
    logic           pwrite;
    data_t          pwdata;
    strb_t          pstrb;
  } apb_req_t;

  typedef struct packed {
    logic  pready;
    data_t prdata;
    logic  pslverr;
  } apb_resp_t;

  // addr_decode's rule format. NoApbSlaves == 1, so idx is a single bit.
  typedef struct packed {
    logic [0:0] idx;
    addr_t      start_addr;
    addr_t      end_addr;
  } rule_t;

  // One rule covering 0x0000-0x00FF (end_addr exclusive). At/above 0x100 misses
  // the map and the bridge answers DECERR itself, issuing no APB transfer.
  // Inside it, 0x00-0x3F are the slave's 16 registers; 0x40-0xFF raise PSLVERR.
  localparam rule_t [0:0] ADDR_MAP = '{
      '{idx: 1'b0, start_addr: 32'h0000_0000, end_addr: 32'h0000_0100}
  };

  axi_lite_req_t   axi_req;
  axi_lite_resp_t  axi_resp;
  apb_req_t  [0:0] apb_req;
  apb_resp_t [0:0] apb_resp;

  // ---- interface -> request struct (driven by the AXI agent) ----------------
  assign axi_req.aw.addr  = axi.AWADDR;
  assign axi_req.aw.prot  = axi.AWPROT;
  assign axi_req.aw_valid = axi.AWVALID;
  assign axi_req.w.data   = axi.WDATA;
  assign axi_req.w.strb   = axi.WSTRB;
  assign axi_req.w_valid  = axi.WVALID;
  assign axi_req.b_ready  = axi.BREADY;
  assign axi_req.ar.addr  = axi.ARADDR;
  assign axi_req.ar.prot  = axi.ARPROT;
  assign axi_req.ar_valid = axi.ARVALID;
  assign axi_req.r_ready  = axi.RREADY;

  // ---- response struct -> interface (sampled by driver + monitor) ----------
  assign axi.AWREADY = axi_resp.aw_ready;
  assign axi.WREADY  = axi_resp.w_ready;
  assign axi.BRESP   = axi_resp.b.resp;
  assign axi.BVALID  = axi_resp.b_valid;
  assign axi.ARREADY = axi_resp.ar_ready;
  assign axi.RDATA   = axi_resp.r.data;
  assign axi.RRESP   = axi_resp.r.resp;
  assign axi.RVALID  = axi_resp.r_valid;

  // ---- bridge APB request struct -> apb_if (the real bus) ------------------
  assign apb.PADDR   = apb_req[0].paddr;
  assign apb.PPROT   = apb_req[0].pprot;
  assign apb.PSEL    = apb_req[0].psel;
  assign apb.PENABLE = apb_req[0].penable;
  assign apb.PWRITE  = apb_req[0].pwrite;
  assign apb.PWDATA  = apb_req[0].pwdata;
  assign apb.PSTRB   = apb_req[0].pstrb;

  // ---- apb_if -> bridge APB response struct --------------------------------
  // apb.PREADY/PRDATA/PSLVERR are driven by the slave's output ports below.
  assign apb_resp[0].pready  = apb.PREADY;
  assign apb_resp[0].prdata  = apb.PRDATA;
  assign apb_resp[0].pslverr = apb.PSLVERR;

  // ---------------------------------------------------------------------------
  // DUT stack
  // ---------------------------------------------------------------------------
  axi_lite_to_apb #(
      .NoApbSlaves     (32'd1),
      .NoRules         (32'd1),
      .AddrWidth       (ADDR_WIDTH),
      .DataWidth       (DATA_WIDTH),
      .PipelineRequest (1'b0),
      .PipelineResponse(1'b0),
      .axi_lite_req_t  (axi_lite_req_t),
      .axi_lite_resp_t (axi_lite_resp_t),
      .apb_req_t       (apb_req_t),
      .apb_resp_t      (apb_resp_t),
      .rule_t          (rule_t)
  ) bridge (
      .clk_i          (ACLK),
      .rst_ni         (ARESETn),
      .axi_lite_req_i (axi_req),
      .axi_lite_resp_o(axi_resp),
      .apb_req_o      (apb_req),
      .apb_resp_i     (apb_resp),
      .addr_map_i     (ADDR_MAP)
  );

  apb_slave #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) slave (
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

  // ---------------------------------------------------------------------------
  // UVM entry
  // ---------------------------------------------------------------------------
  initial begin
    `uvm_info("TB_AXI_TOP", "Starting simulation", UVM_LOW)
    // Distinct field names. "vif" stays the APB one so the APB agent is reused
    // unmodified.
    uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb);
    uvm_config_db#(virtual axi_lite_if)::set(null, "*", "axi_vif", axi);
    run_test();
    `uvm_info("TB_AXI_TOP", "Simulation finished", UVM_LOW)
  end

  // Waves dumping is optional, controlled by +define+TRACE on the command line
`ifdef TRACE
  initial begin
    $dumpfile("build/waves.vcd");
    $dumpvars(0, tb_axi_top);
  end
`endif

  // Hard backstop so a hung handshake can't run forever
  initial begin
    #1ms;
    `uvm_fatal("TB_AXI_TOP", "Global watchdog timeout (1ms) -- simulation hung")
  end

endmodule : tb_axi_top
