// Constrained-random regression. This is the test the mutation harness runs.

class axi_random_test extends axi_base_test;

  `uvm_component_utils(axi_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_lite_random_seq seq;
    int unsigned        num_trans;
    phase.raise_objection(this);
    seq = axi_lite_random_seq::type_id::create("seq");
    if ($value$plusargs("num_trans=%d", num_trans)) seq.num_trans = num_trans;
    seq.start(env.axi_agent.sqr);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass : axi_random_test
