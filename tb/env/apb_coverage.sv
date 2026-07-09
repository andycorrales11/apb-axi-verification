class apb_coverage extends uvm_subscriber #(apb_seq_item);

  `uvm_component_utils(apb_coverage)

  covergroup apb_cg;
  endgroup : apb_cg

  function new(string name, uvm_component parent);
    super.new(name, parent);
    apb_cg = new("apb_cg", this);
  endfunction

  virtual function void write(apb_seq_item t);
    apb_cg.sample();
  endfunction

endclass : apb_coverage
