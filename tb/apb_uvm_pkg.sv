package apb_uvm_pkg;

  parameter int APB_ADDR_WIDTH = 32;
  parameter int APB_DATA_WIDTH = 32;

  import uvm_pkg::*;

  // 1. transaction
`include "apb_seq_item.sv"

endpackage : apb_uvm_pkg
