// Do NOT redeclare is_active here -- uvm_agent already has it, and a local
// field of the same name shadows what super.build_phase() sets from config_db.

class axi_lite_agent extends uvm_agent;

  axi_lite_sequencer sqr;
  axi_lite_driver    drv;
  axi_lite_monitor   mon;

  `uvm_component_utils(axi_lite_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axi_lite_monitor::type_id::create("mon", this);
    if (is_active == UVM_ACTIVE) begin
      sqr = axi_lite_sequencer::type_id::create("sqr", this);
      drv = axi_lite_driver::type_id::create("drv", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    if (is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass : axi_lite_agent
