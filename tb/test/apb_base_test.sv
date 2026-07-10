class apb_base_test extends uvm_test;

  apb_env env;

  `uvm_component_utils(apb_base_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = apb_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_root::get().print_topology();
  endfunction

  // TODO: run_phase   -> raise objection, start sequence, drop objection.
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    // seq.start(env.agent.sqr)
    phase.drop_objection(this);
  endtask

endclass : apb_base_test
