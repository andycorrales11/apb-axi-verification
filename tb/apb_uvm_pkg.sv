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

endpackage : apb_uvm_pkg
