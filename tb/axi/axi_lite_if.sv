// AXI4-Lite: five independent VALID/READY channels.

interface axi_lite_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic ACLK,
    input logic ARESETn
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // ---- AW: write address ---------------------------------------------------
  logic [ADDR_WIDTH-1:0] AWADDR;
  logic [           2:0] AWPROT;
  logic                  AWVALID;
  logic                  AWREADY;

  // ---- W: write data -------------------------------------------------------
  logic [DATA_WIDTH-1:0] WDATA;
  logic [STRB_WIDTH-1:0] WSTRB;
  logic                  WVALID;
  logic                  WREADY;

  // ---- B: write response ---------------------------------------------------
  logic [           1:0] BRESP;
  logic                  BVALID;
  logic                  BREADY;

  // ---- AR: read address ----------------------------------------------------
  logic [ADDR_WIDTH-1:0] ARADDR;
  logic [           2:0] ARPROT;
  logic                  ARVALID;
  logic                  ARREADY;

  // ---- R: read data --------------------------------------------------------
  logic [DATA_WIDTH-1:0] RDATA;
  logic [           1:0] RRESP;
  logic                  RVALID;
  logic                  RREADY;

  // No clocking blocks, by design -- Verilator 5.048 fires @(cb) twice in one
  // timestep (see the NOTE in tb/agent/apb_driver.sv). Driver and monitor use
  // @(posedge ACLK) + NBA writes / raw reads instead. No modports either; the
  // driver/monitor split is by convention.

endinterface : axi_lite_if
