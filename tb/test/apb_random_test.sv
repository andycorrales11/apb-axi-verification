// =============================================================================
// apb_random_test.sv  --  constrained-random regression test.
// -----------------------------------------------------------------------------
// Runs apb_random_seq (N random read/write transfers, random PSTRB, ~10%
// decode-error addresses). Transfer count is overridable with +num_trans=<n>.
// =============================================================================

class apb_random_test extends apb_base_test;

  `uvm_component_utils(apb_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    apb_random_seq seq;
    int unsigned num_trans;
    phase.raise_objection(this);
    seq = apb_random_seq::type_id::create("seq");
    if ($value$plusargs("num_trans=%d", num_trans)) seq.num_trans = num_trans;
    seq.start(env.agent.sqr);
    phase.drop_objection(this);
  endtask

endclass : apb_random_test
