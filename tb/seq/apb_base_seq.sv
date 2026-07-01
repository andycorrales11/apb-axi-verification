class apb_base_seq extends uvm_sequence #(apb_seq_item);

  `uvm_object_utils(apb_base_seq)

  function new(string name = "apb_base_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item tr;
    // Write value
    tr = apb_seq_item::type_id::create("tr");
    tr.addr = 32'h0000_0004;
    tr.data = 32'hDEAD_BEEF;
    tr.dir = WRITE;
    uvm_do(tr);

    // Read value
    tr = apb_seq_item::type_id::create("tr");
    tr.addr = 32'h0000_0004;
    tr.dir = READ;
    uvm_do(tr);

    `uvm_info(get_type_name(), $sformatf("Read back data: 0x%08h", tr.rdata), UVM_LOW)
  endtask

endclass : apb_base_seq
