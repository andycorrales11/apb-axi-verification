// Directed pass over all three address classes plus both strobe corners.

class axi_lite_base_seq extends uvm_sequence #(axi_lite_seq_item);

  `uvm_object_utils(axi_lite_base_seq)

  axi_lite_seq_item last;  // the item do_axi() just completed

  function new(string name = "axi_lite_base_seq");
    super.new(name);
  endfunction

  // Directed payloads are assigned, not solved for. Asking the solver to hit an
  // exact strb while c_zero_strb_dist also constrains zero_strb makes
  // randomize() fail on Verilator 5.048 -- observed as RNDFLD on both
  // zero-strobe items, which then silently drove the wrong stimulus. Only the
  // timing knobs and prot are randomized here.
  task do_axi(axi_dir_e d, bit [31:0] a, bit [31:0] wd, bit [3:0] s);
    axi_lite_seq_item tr;
    tr = axi_lite_seq_item::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize()) `uvm_error(get_type_name(), "directed item: randomize() failed")
    tr.dir        = d;
    tr.addr       = a;
    tr.data       = wd;
    tr.strb       = s;
    tr.addr_class = axi_lite_seq_item::classify_addr(a);
    tr.zero_strb  = (d == AXI_WRITE) && (s == '0);
    finish_item(tr);
    last = tr;
  endtask

  virtual task body();
    // Write / read back a full word.
    do_axi(AXI_WRITE, 32'h0000_0004, 32'hDEAD_BEEF, 4'b1111);
    do_axi(AXI_READ, 32'h0000_0004, '0, 4'b0000);
    `uvm_info(get_type_name(), $sformatf("read back 0x%08h", last.rdata), UVM_LOW)

    // Partial strobe: only byte lane 1 may change.
    do_axi(AXI_WRITE, 32'h0000_0004, 32'hAABB_CCDD, 4'b0010);
    do_axi(AXI_READ, 32'h0000_0004, '0, 4'b0000);
    `uvm_info(get_type_name(), $sformatf("after partial write 0x%08h", last.rdata), UVM_LOW)

    // Mapped, but past the slave's 16 registers -> SLVERR.
    do_axi(AXI_WRITE, 32'h0000_0040, 32'h1234_5678, 4'b1111);
    do_axi(AXI_READ, 32'h0000_0040, '0, 4'b0000);

    // Off the bridge's map -> DECERR, no APB transfer.
    do_axi(AXI_WRITE, 32'h0000_0100, 32'h8765_4321, 4'b1111);
    do_axi(AXI_READ, 32'h0000_0100, '0, 4'b0000);
    `uvm_info(get_type_name(), $sformatf("off-map read returned 0x%08h %s", last.rdata,
                                         axi_lite_seq_item::resp_name(last.resp)), UVM_LOW)

    // Zero-strobe write: no APB transfer, OKAY, register untouched.
    do_axi(AXI_WRITE, 32'h0000_0008, 32'hFFFF_FFFF, 4'b0000);
    do_axi(AXI_READ, 32'h0000_0008, '0, 4'b0000);
    `uvm_info(get_type_name(), $sformatf("after zero-strobe write 0x%08h", last.rdata), UVM_LOW)

    // Same, but off the map: the strobe check runs first, so the answer is OKAY
    // and the decode error is masked.
    do_axi(AXI_WRITE, 32'h0000_0140, 32'hFFFF_FFFF, 4'b0000);
    `uvm_info(get_type_name(), $sformatf("zero-strobe off-map write answered %s",
                                         axi_lite_seq_item::resp_name(last.resp)), UVM_LOW)
  endtask

endclass : axi_lite_base_seq


class axi_lite_random_seq extends axi_lite_base_seq;

  `uvm_object_utils(axi_lite_random_seq)

  int unsigned num_trans = 200;

  function new(string name = "axi_lite_random_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_lite_seq_item tr;
    repeat (num_trans) begin
      `uvm_do(tr)
    end
    `uvm_info(get_type_name(), $sformatf("completed %0d random transactions", num_trans), UVM_LOW)
  endtask

endclass : axi_lite_random_seq
