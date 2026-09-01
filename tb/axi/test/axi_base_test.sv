// Builds the env and runs a sequence. Selected by +UVM_TESTNAME.

class axi_base_test extends uvm_test;

  axi_env env;

  `uvm_component_utils(axi_base_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_root::get().print_topology();
  endfunction

  task run_phase(uvm_phase phase);
    axi_lite_base_seq seq;
    phase.raise_objection(this);
    seq = axi_lite_base_seq::type_id::create("seq");
    seq.start(env.axi_agent.sqr);
    // Let the last response drain before check_phase runs.
    #100ns;
    phase.drop_objection(this);
  endtask

endclass : axi_base_test
