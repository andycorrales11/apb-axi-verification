interface apb_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic PCLK,
    input logic PRESETn
);

  // ---- APB4 signals --------------------------------------------------------
  logic [ADDR_WIDTH-1:0] PADDR;
  logic [           2:0] PPROT;
  logic                  PSEL;
  logic                  PENABLE;
  logic                  PWRITE;
  logic [DATA_WIDTH-1:0] PWDATA;
  logic [STRB_WIDTH-1:0] PSTRB;
  logic                  PREADY;
  logic [DATA_WIDTH-1:0] PRDATA;
  logic                  PSLVERR;

endinterface : apb_if
