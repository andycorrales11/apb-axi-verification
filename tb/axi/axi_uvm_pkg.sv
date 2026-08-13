// Same load-bearing rule as apb_uvm_pkg.sv: include order IS the dependency
// graph. New components go in the matching slot, and their directory into the
// +incdir+ list in sim/filelist_axi.f.

package axi_uvm_pkg;

  parameter int AXI_ADDR_WIDTH = 32;
  parameter int AXI_DATA_WIDTH = 32;

  import uvm_pkg::*;

  // The APB agent is reused on the far side of the bridge, configured PASSIVE.
  import apb_uvm_pkg::*;

  // Spelled out rather than imported from axi_pkg: the checker must not share a
  // definition of DECERR with the DUT it is checking.
  typedef enum logic [1:0] {
    AXI_OKAY   = 2'b00,
    AXI_SLVERR = 2'b10,
    AXI_DECERR = 2'b11
  } axi_resp_e;

  // 1. transaction
`include "axi_lite_seq_item.sv"

  // 2-5. agent guts
`include "axi_lite_sequencer.sv"
`include "axi_lite_driver.sv"
`include "axi_lite_monitor.sv"
`include "axi_lite_agent.sv"

  // 6-8. analysis + env
`include "axi_lite_coverage.sv"
`include "axi_lite_scoreboard.sv"
`include "axi_env.sv"

  // 9. stimulus
`include "axi_lite_base_seq.sv"

  // 10. tests
`include "axi_base_test.sv"
`include "axi_random_test.sv"

endpackage : axi_uvm_pkg
