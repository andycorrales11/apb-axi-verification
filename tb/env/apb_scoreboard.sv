`uvm_analysis_imp_decl(_apb)

class apb_scoreboard extends uvm_scoreboard;

  uvm_analysis_imp_apb #(apb_seq_item, apb_scoreboard) ap_imp;

  bit [31:0] ref_mem [*];  // associative array, indexed by addr
  int unsigned read_count = 0;
  int unsigned write_count = 0;
  int unsigned error_count = 0;

  // Mirrors rtl/apb_slave.sv's current decode: 16 word-aligned registers at
  // 0x00-0x3F (PADDR[31:6] must be zero), no read-only registers. If the
  // RTL's map ever changes, this needs to be updated to match by hand.
  localparam bit [31:0] ADDR_DECODE_MASK = 32'hFFFF_FFC0;  // bits [31:6]

  `uvm_component_utils(apb_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_imp = new("ap_imp", this);
  endfunction

  virtual function void write_apb(apb_seq_item t);
    bit        expect_err;
    bit [31:0] cur;

    expect_err = |(t.addr & ADDR_DECODE_MASK);

    if (t.slverr !== expect_err) begin
      `uvm_error(get_type_name(),
        $sformatf("PSLVERR mismatch: addr=0x%0h expected=%0b actual=%0b",
                   t.addr, expect_err, t.slverr))
      error_count++;
    end

    if (t.dir == WRITE) begin
      write_count++;
      if (!expect_err) begin
        // Honor PSTRB byte enables -- only the enabled lanes update.
        cur = ref_mem.exists(t.addr) ? ref_mem[t.addr] : '0;
        foreach (t.PSTRB[i]) if (t.PSTRB[i]) cur[i*8+:8] = t.data[i*8+:8];
        ref_mem[t.addr] = cur;
      end
    end else begin
      read_count++;
      if (!expect_err) begin
        cur = ref_mem.exists(t.addr) ? ref_mem[t.addr] : '0;
        if (t.rdata !== cur) begin
          `uvm_error(get_type_name(),
            $sformatf("Read data mismatch: addr=0x%0h expected=0x%0h actual=0x%0h",
                       t.addr, cur, t.rdata))
          error_count++;
        end
      end
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
      $sformatf("Scoreboard results: %0d writes, %0d reads, %0d errors",
        write_count, read_count, error_count), UVM_NONE)
    if (error_count > 0) begin
      `uvm_error(get_type_name(), $sformatf("TEST FAILED"))
    end else begin
      `uvm_info(get_type_name(), $sformatf("TEST PASSED"), UVM_NONE)
    end
  endfunction

endclass : apb_scoreboard
