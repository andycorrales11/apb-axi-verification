// Subscribes to the monitor's analysis port and samples covergroups on each
// observed transfer. Coverage is your "did I actually exercise it" number --
// but remember the project's headline is the MUTANT tally, not coverage %.

// Verilator (5.048) does not support covergroups (COVERIGN), so this
// collector implements the coverage model by hand with named bins + counters.
// Model (what a covergroup would express):
//   - dir x register: each of the 16 registers read AND written  (32 bins)
//   - decode-error address, per direction                        ( 2 bins)
//   - PSTRB pattern on writes: all 16 strobe values              (16 bins)
//   - PSLVERR observed 0 and 1                                   ( 2 bins)

class apb_coverage extends uvm_subscriber #(apb_seq_item);

  `uvm_component_utils(apb_coverage)

  int unsigned reg_access [2][16];  // [READ/WRITE][PADDR[5:2]] in-range accesses
  int unsigned err_access [2];      // [READ/WRITE] decode-error accesses
  int unsigned pstrb_seen [16];     // strobe patterns on writes
  int unsigned slverr_seen [2];     // PSLVERR value observed
  int unsigned num_sampled;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void write(apb_seq_item t);
    bit is_err = |t.addr[APB_ADDR_WIDTH-1:6];
    num_sampled++;
    if (is_err) err_access[t.dir]++;
    else        reg_access[t.dir][t.addr[5:2]]++;
    if (t.dir == WRITE) pstrb_seen[t.PSTRB]++;
    slverr_seen[t.slverr]++;
  endfunction

  virtual function void report_phase(uvm_phase phase);
    int unsigned hit, total;
    string       missing = "";

    foreach (reg_access[d, r]) begin
      total++;
      if (reg_access[d][r] > 0) hit++;
      else missing = {missing, $sformatf(" %s.reg[%0d]", d ? "WR" : "RD", r)};
    end
    foreach (err_access[d]) begin
      total++;
      if (err_access[d] > 0) hit++;
      else missing = {missing, $sformatf(" %s.decode_err", d ? "WR" : "RD")};
    end
    foreach (pstrb_seen[p]) begin
      total++;
      if (pstrb_seen[p] > 0) hit++;
      else missing = {missing, $sformatf(" pstrb[%04b]", p)};
    end
    foreach (slverr_seen[v]) begin
      total++;
      if (slverr_seen[v] > 0) hit++;
      else missing = {missing, $sformatf(" slverr==%0d", v)};
    end

    `uvm_info(get_type_name(),
      $sformatf("Functional coverage: %0d/%0d bins (%0.1f%%) over %0d samples",
                hit, total, total ? 100.0 * hit / total : 0.0, num_sampled), UVM_NONE)
    if (missing != "")
      `uvm_info(get_type_name(), {"Unhit bins:", missing}, UVM_LOW)
  endfunction

endclass : apb_coverage
