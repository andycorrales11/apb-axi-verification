// Directed pass over all three address classes plus the two strobe corners.
// `uvm_do_with, never `uvm_do -- the APB phase already got bitten by `uvm_do
// re-randomizing and clobbering manually set fields.

class axi_lite_base_seq extends uvm_sequence #(axi_lite_seq_item);

  `uvm_object_utils(axi_lite_base_seq)

  function new(string name = "axi_lite_base_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_lite_seq_item tr;

    // Write / read back a full word.
    `uvm_do_with(tr, {addr == 32'h0000_0004; addr_class == ADDR_REG;
                      dir == AXI_WRITE; data == 32'hDEAD_BEEF; strb == '1;})
    `uvm_do_with(tr, {addr == 32'h0000_0004; addr_class == ADDR_REG; dir == AXI_READ;})
    `uvm_info(get_type_name(), $sformatf("read back 0x%08h", tr.rdata), UVM_LOW)

    // Partial strobe: only byte lane 1 may change.
    `uvm_do_with(tr, {addr == 32'h0000_0004; addr_class == ADDR_REG;
                      dir == AXI_WRITE; data == 32'hAABB_CCDD; strb == 4'b0010;})
    `uvm_do_with(tr, {addr == 32'h0000_0004; addr_class == ADDR_REG; dir == AXI_READ;})
    `uvm_info(get_type_name(), $sformatf("after partial write 0x%08h", tr.rdata), UVM_LOW)

    // Mapped, but past the slave's 16 registers -> SLVERR.
    `uvm_do_with(tr, {addr == 32'h0000_0040; addr_class == ADDR_SLVERR;
                      dir == AXI_WRITE; strb == '1;})
    `uvm_do_with(tr, {addr == 32'h0000_0040; addr_class == ADDR_SLVERR; dir == AXI_READ;})

    // Off the bridge's map -> DECERR, no APB transfer.
    `uvm_do_with(tr, {addr == 32'h0000_0100; addr_class == ADDR_DECERR; err_near_boundary == 1;
                      dir == AXI_WRITE; strb == '1;})
    `uvm_do_with(tr, {addr == 32'h0000_0100; addr_class == ADDR_DECERR; err_near_boundary == 1;
                      dir == AXI_READ;})

    // Zero-strobe write: no APB transfer, OKAY, register untouched.
    `uvm_do_with(tr, {addr == 32'h0000_0008; addr_class == ADDR_REG;
                      dir == AXI_WRITE; data == 32'hFFFF_FFFF; strb == '0;})
    `uvm_do_with(tr, {addr == 32'h0000_0008; addr_class == ADDR_REG; dir == AXI_READ;})

    // Same, but off the map: the strobe check runs first and the answer is
    // OKAY, not DECERR.
    `uvm_do_with(tr, {addr == 32'h0000_0140; addr_class == ADDR_DECERR; err_near_boundary == 1;
                      dir == AXI_WRITE; strb == '0;})
    `uvm_info(get_type_name(), $sformatf("zero-strobe off-map write answered %s",
                                         axi_lite_seq_item::resp_name(tr.resp)), UVM_LOW)
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
      `uvm_do_with(tr, {})
    end
    `uvm_info(get_type_name(), $sformatf("completed %0d random transactions", num_trans), UVM_LOW)
  endtask

endclass : axi_lite_random_seq
