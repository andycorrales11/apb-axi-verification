`uvm_analysis_imp_decl(_apb)

class apb_scoreboard extends uvm_scoreboard;

  uvm_analysis_imp_apb #(apb_seq_item, apb_scoreboard) ap_imp;

  bit [31:0] ref_mem [*];  // associative array, indexed by addr
  int unsigned read_count = 0;
  int unsigned write_count = 0;
  int unsigned error_count = 0;

  `uvm_component_utils(apb_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_imp = new("ap_imp", this);
  endfunction

  virtual function void write_apb(apb_seq_item t);
    // TODO: if write -> update ref model;  if read -> compare & `uvm_error on miss.
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
      $sformatf("Scoreboard results: %0d writes, %0d reads, %0d errors",
        write_count, read_count, error_count), UVM_NONE)
    if (fail_count > 0) begin
      `uvm_error(get_type_name(), $sformatf("TEST FAILED"))
    end else begin
      `uvm_info(get_type_name(), $sformatf("TEST PASSED"), UVM_NONE)
    end
  endfunction

endclass : apb_scoreboard
