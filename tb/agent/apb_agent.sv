class apb_agent extends uvm_agent;

  apb_sequencer sqr;
  apb_driver    drv;
  apb_monitor   mon;

  `uvm_component_utils(apb_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // TODO: build_phase   -> create components per is_active.
  // TODO: connect_phase -> connect driver to sequencer.

endclass : apb_agent
