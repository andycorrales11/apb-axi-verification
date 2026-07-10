class apb_agent extends uvm_agent;

  apb_sequencer sqr;
  apb_driver    drv;
  apb_monitor   mon;

  uvm_active_passive_enum is_active = UVM_ACTIVE;  // default to active, override via config_db

  `uvm_component_utils(apb_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = apb_monitor::type_id::create("mon", this);
    if (is_active == UVM_ACTIVE) begin
      sqr = apb_sequencer::type_id::create("sqr", this);
      drv = apb_driver::type_id::create("drv", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    if (is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass : apb_agent
