package apb_uvm_pkg;

  parameter int APB_ADDR_WIDTH = 32;
  parameter int APB_DATA_WIDTH = 32;

  import uvm_pkg::*;

  // 1. transaction
`include "apb_seq_item.sv"

  // 2-5. agent guts
`include "apb_sequencer.sv"
`include "apb_driver.sv"
`include "apb_monitor.sv"
`include "apb_agent.sv"

  // 6-8. analysis + env
`include "apb_coverage.sv"
`include "apb_scoreboard.sv"
`include "apb_env.sv"

  // 9. stimulus
`include "apb_base_seq.sv"

  // 10. tests
`include "apb_base_test.sv"

endpackage : apb_uvm_pkg
