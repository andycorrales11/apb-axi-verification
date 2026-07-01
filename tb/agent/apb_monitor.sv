class apb_monitor extends uvm_monitor;
  `uvm_component_utils(apb_monitor)

  virtual apb_if vif;

  uvm_analysis_port #(apb_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "Virtual interface must be set for: " + get_full_name())
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    `uvm_info(get_type_name(), "Starting run phase", UVM_LOW)
    forever begin
      // TODO: wait for a transfer to complete, build an apb_seq_item, fill it, and call ap.write(tr).
    end
  endtask
endclass : apb_monitor
