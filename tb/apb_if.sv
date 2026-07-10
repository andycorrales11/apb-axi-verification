interface apb_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic PCLK,
    input logic PRESETn
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

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

  // ---- Clocking blocks -----------------------------------------------------
  // The driver acts as the APB *requester* (master): it drives the request
  // signals and samples the completion signals. Skews keep the testbench from
  // racing the DUT at the clock edge.
  clocking mst_cb @(posedge PCLK);
    default input #1step output #1;
    output PADDR, PPROT, PSEL, PENABLE, PWRITE, PWDATA, PSTRB;
    input  PREADY, PRDATA, PSLVERR;
  endclocking

  // The monitor is passive: everything is an input, sampled after the edge.
  clocking mon_cb @(posedge PCLK);
    default input #1step;
    input PADDR, PPROT, PSEL, PENABLE, PWRITE, PWDATA, PSTRB;
    input PREADY, PRDATA, PSLVERR;
  endclocking

  // ---- Modports ------------------------------------------------------------
  modport master  (clocking mst_cb, input PCLK, PRESETn);
  modport monitor (clocking mon_cb, input PCLK, PRESETn);

  // The DUT in this project is connected via discrete ports in tb_top (so the
  // same harness can later wrap third-party RTL like pulp-platform's), so the
  // slave does not consume a modport here.

endinterface : apb_if
