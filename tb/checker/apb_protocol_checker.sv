// Bind-able SVA checker for the APB4 handshake. Written to tolerate any number
// of ACCESS wait cycles, so it holds against the DUT's registered PREADY.
module apb_protocol_checker #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic                    PCLK,
    input logic                    PRESETn,
    input logic [ADDR_WIDTH-1:0]   PADDR,
    input logic [             2:0] PPROT,
    input logic                    PSEL,
    input logic                    PENABLE,
    input logic                    PWRITE,
    input logic [DATA_WIDTH-1:0]   PWDATA,
    input logic [DATA_WIDTH/8-1:0] PSTRB,
    input logic                    PREADY,
    input logic [DATA_WIDTH-1:0]   PRDATA,
    input logic                    PSLVERR
);

  default clocking cb @(posedge PCLK);
  endclocking
  default disable iff (!PRESETn);

  wire access_done = PSEL && PENABLE && PREADY;
  wire in_transfer = PSEL && !access_done;

  a_setup_to_access : assert property ((PSEL && !PENABLE) |=> (PSEL && PENABLE))
      else $error("APB: SETUP not followed by ACCESS");

  a_enable_low_on_start : assert property ($rose(PSEL) |-> !PENABLE)
      else $error("APB: PENABLE asserted in the SETUP cycle");

  a_psel_held : assert property (in_transfer |=> PSEL)
      else $error("APB: PSEL dropped before the transfer completed");

  a_penable_held : assert property ((PENABLE && !PREADY) |=> PENABLE)
      else $error("APB: PENABLE dropped before PREADY");

  a_addr_ctrl_stable : assert property (
      in_transfer |=> ($stable(PADDR) && $stable(PWRITE) && $stable(PPROT)))
      else $error("APB: PADDR/PWRITE/PPROT changed mid-transfer");

  a_wdata_stable : assert property (
      (in_transfer && PWRITE) |=> ($stable(PWDATA) && $stable(PSTRB)))
      else $error("APB: PWDATA/PSTRB changed mid write transfer");

  // Mirrors the slave's 0x00..0x3F decode: PSLVERR at completion iff out of map.
  a_decerr_map : assert property (
      access_done |-> (PSLVERR == (|PADDR[ADDR_WIDTH-1:6])))
      else $error("APB: PSLVERR=%0b disagrees with decode of PADDR=0x%0h", PSLVERR, PADDR);

  a_no_x_ctrl : assert property (!$isunknown({PSEL, PENABLE, PREADY}))
      else $error("APB: X/Z on PSEL/PENABLE/PREADY");
  a_no_x_rdata : assert property ((access_done && !PWRITE) |-> !$isunknown(PRDATA))
      else $error("APB: X/Z on PRDATA at read completion");

  c_write_done      : cover property (access_done &&  PWRITE);
  c_read_done       : cover property (access_done && !PWRITE);
  c_slverr          : cover property (access_done &&  PSLVERR);
  c_okay            : cover property (access_done && !PSLVERR);
  c_wait_state      : cover property (PSEL && PENABLE && !PREADY);
  c_back_to_back    : cover property (access_done ##1 (PSEL && !PENABLE));
  c_idle_gap        : cover property (access_done ##1 !PSEL);
  c_write_then_read : cover property ((access_done && PWRITE) ##[1:8] (access_done && !PWRITE));

endmodule : apb_protocol_checker
