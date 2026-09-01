// Hand-rolled bins; Verilator 5.048 has no covergroups (see apb_coverage.sv).
// NOTE: comments must not *start* with the word "verilator" (parsed as a pragma).
//
// Subscribes to the DRIVER, not the monitor: aw_w_skew and the ready-delays are
// choices the driver made and a monitor watching wires cannot recover them.
//
// Model, 45 bins, all reachable:
//   addr class x dir                     ( 6)
//   response x dir                       ( 6)   EXOKAY has no producer, excluded
//   WSTRB pattern on writes              (16)
//   AW/W skew x BREADY delay on writes   (12)
//   RREADY delay on reads                ( 4)
//   zero-strobe write off the map        ( 1)   the masked-DECERR corner

class axi_lite_coverage extends uvm_subscriber #(axi_lite_seq_item);

  `uvm_component_utils(axi_lite_coverage)

  int unsigned class_dir[3][2];
  int unsigned resp_dir[3][2];
  int unsigned wstrb_seen[16];
  int unsigned skew_bdelay[3][4];
  int unsigned rdelay_seen[4];
  int unsigned zero_strb_off_map;
  int unsigned num_sampled;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // OKAY / SLVERR / DECERR -> 0 / 1 / 2. EXOKAY is not legal on AXI4-Lite here.
  function int resp_bin(logic [1:0] r);
    case (r)
      2'b00:   return 0;
      2'b10:   return 1;
      2'b11:   return 2;
      default: return -1;
    endcase
  endfunction

  virtual function void write(axi_lite_seq_item t);
    int rb = resp_bin(t.resp);
    int d  = (t.dir == AXI_WRITE) ? 1 : 0;

    num_sampled++;
    class_dir[t.addr_class][d]++;
    if (rb < 0) `uvm_error(get_type_name(), $sformatf("EXOKAY observed at addr=0x%0h", t.addr))
    else resp_dir[rb][d]++;

    if (t.dir == AXI_WRITE) begin
      wstrb_seen[t.strb]++;
      skew_bdelay[t.aw_w_skew][t.b_ready_delay]++;
      if (t.strb == '0 && t.addr_class == ADDR_DECERR) zero_strb_off_map++;
    end else begin
      rdelay_seen[t.r_ready_delay]++;
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    int unsigned hit, total;
    string       missing = "";
    string       dname[2] = '{"RD", "WR"};
    string       cname[3] = '{"REG", "SLVERR", "DECERR"};
    string       rname[3] = '{"OKAY", "SLVERR", "DECERR"};
    string       sname[3] = '{"AW_FIRST", "W_FIRST", "SAME_CYCLE"};

    foreach (class_dir[c, d]) begin
      total++;
      if (class_dir[c][d] > 0) hit++;
      else missing = {missing, $sformatf(" %s.addr[%s]", dname[d], cname[c])};
    end
    foreach (resp_dir[r, d]) begin
      total++;
      if (resp_dir[r][d] > 0) hit++;
      else missing = {missing, $sformatf(" %s.resp[%s]", dname[d], rname[r])};
    end
    foreach (wstrb_seen[s]) begin
      total++;
      if (wstrb_seen[s] > 0) hit++;
      else missing = {missing, $sformatf(" wstrb[%04b]", s)};
    end
    foreach (skew_bdelay[s, b]) begin
      total++;
      if (skew_bdelay[s][b] > 0) hit++;
      else missing = {missing, $sformatf(" %s.bdelay[%0d]", sname[s], b)};
    end
    foreach (rdelay_seen[r]) begin
      total++;
      if (rdelay_seen[r] > 0) hit++;
      else missing = {missing, $sformatf(" rdelay[%0d]", r)};
    end
    total++;
    if (zero_strb_off_map > 0) hit++;
    else missing = {missing, " zero_strb_off_map"};

    `uvm_info(get_type_name(), $sformatf(
              "Functional coverage: %0d/%0d bins (%0.1f%%) over %0d samples", hit, total,
              total ? 100.0 * hit / total : 0.0, num_sampled), UVM_NONE)
    if (missing != "") `uvm_info(get_type_name(), {"Unhit bins:", missing}, UVM_LOW)
  endfunction

endclass : axi_lite_coverage
