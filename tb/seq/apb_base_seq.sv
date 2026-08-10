// The base stimulus. Derive concrete sequences (write-then-read, random regs,
// back-to-back, error-injection) from this. Keep the base generic; put specific
// scenarios in subclasses.

class apb_base_seq extends uvm_sequence #(apb_seq_item);

  `uvm_object_utils(apb_base_seq)

  function new(string name = "apb_base_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item tr;
    // Write value. `uvm_do would re-randomize and clobber manually set fields,
    // so constrain them through `uvm_do_with instead.
    `uvm_do_with(tr, { addr == 32'h0000_0004;
                       data == 32'hDEAD_BEEF;
                       dir  == WRITE;
                       PSTRB == '1; })

    // Read value
    `uvm_do_with(tr, { addr == 32'h0000_0004;
                       dir  == READ; })

    `uvm_info(get_type_name(), $sformatf("Read back data: 0x%08h", tr.rdata), UVM_LOW)
  endtask

endclass : apb_base_seq

// -----------------------------------------------------------------------------
// apb_random_seq -- N fully randomized transfers. The seq_item's constraints
// keep addresses legal/aligned except for the ~10% force_decode_err transfers
// that provoke PSLVERR. Reads are checked by the scoreboard's reference model.
// -----------------------------------------------------------------------------
class apb_random_seq extends apb_base_seq;

  `uvm_object_utils(apb_random_seq)

  int unsigned num_trans = 200;

  function new(string name = "apb_random_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item tr;
    repeat (num_trans) begin
      `uvm_do(tr)
    end
    `uvm_info(get_type_name(), $sformatf("Completed %0d random transfers", num_trans), UVM_LOW)
  endtask

endclass : apb_random_seq
