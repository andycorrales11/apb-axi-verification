// Two subscribers, two jobs.
//
//   write_axi -- reference model at the AXI boundary: right response per
//                address class, reads return what was last written.
//   write_apb -- the cross-check: every AXI transaction that should reach the
//                slave produced exactly one matching APB transfer, and every
//                one that should not produced none. A bridge that duplicates a
//                transfer or corrupts PPROT is invisible to the reference model
//                and only shows up here.
//
// `uvm_analysis_imp_decl(_apb) is NOT repeated here -- apb_scoreboard.sv already
// declared it inside apb_uvm_pkg, which this package imports.

`uvm_analysis_imp_decl(_axi)

class axi_lite_scoreboard extends uvm_scoreboard;

  uvm_analysis_imp_axi #(axi_lite_seq_item, axi_lite_scoreboard) axi_imp;
  uvm_analysis_imp_apb #(apb_seq_item, axi_lite_scoreboard)      apb_imp;

  `uvm_component_utils(axi_lite_scoreboard)

  // The address map is restated by hand, NOT imported from axi_lite_seq_item or
  // tb_axi_top. A checker that derives its expectations from the thing it is
  // checking cannot fail.
  localparam bit [31:0] BRIDGE_MAP_END = 32'h0000_0100;  // >= this: off the bridge's map
  localparam bit [31:0] SLAVE_REG_END  = 32'h0000_0040;  // >= this: past the slave's 16 regs
  localparam bit [31:0] DECERR_RDATA   = 32'hDEA1_10C8;  // axi_lite_to_apb.sv:291

  bit [31:0] ref_mem[*];

  // Both sides are queued and reconciled in FIFO order from whichever
  // subscriber fires. They cannot be reconciled inline: with a short
  // b_ready_delay the B handshake lands on the same edge the APB access
  // completes, so the two monitors emit in the same timestep and their order is
  // a race.
  axi_lite_seq_item exp_q[$];
  apb_seq_item      apb_q[$];

  int unsigned axi_count;
  int unsigned apb_count;
  int unsigned error_count;
  int unsigned xcheck_count;  // AXI transactions matched against an APB transfer

  // One desync cascades into an error per remaining transaction; cap the noise.
  localparam int unsigned MAX_REPORTED = 20;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi_imp = new("axi_imp", this);
    apb_imp = new("apb_imp", this);
  endfunction

  function void flag(string msg);
    error_count++;
    if (error_count <= MAX_REPORTED) `uvm_error(get_type_name(), msg)
    else if (error_count == MAX_REPORTED + 1)
      `uvm_info(get_type_name(), "further mismatches suppressed", UVM_NONE)
  endfunction

  virtual function void write_apb(apb_seq_item t);
    apb_count++;
    apb_q.push_back(t);
    reconcile();
  endfunction

  // Exactly the transactions that reach the slave: an in-map access that is not
  // a zero-strobe write (axi_lite_to_apb.sv:299).
  function bit expects_apb(axi_lite_seq_item t);
    if (t.dir == AXI_WRITE && t.strb == '0) return 0;
    return t.addr < BRIDGE_MAP_END;
  endfunction

  virtual function void write_axi(axi_lite_seq_item t);
    bit          is_write = (t.dir == AXI_WRITE);
    bit          in_map = (t.addr < BRIDGE_MAP_END);
    bit          in_regs = (t.addr < SLAVE_REG_END);
    bit          zero_strb_wr = is_write && (t.strb == '0);
    logic [ 1:0] expect_resp;
    bit [  31:0] cur;

    axi_count++;

    // A zero-strobe write is answered OKAY out of Setup with no APB transfer,
    // and that check precedes the decode check -- so it masks what would
    // otherwise be a DECERR. See axi_lite_to_apb.sv:299 and :319.
    if (zero_strb_wr) expect_resp = AXI_OKAY;
    else if (!in_map) expect_resp = AXI_DECERR;
    else expect_resp = in_regs ? AXI_OKAY : AXI_SLVERR;

    if (t.resp !== expect_resp)
      flag($sformatf("%s addr=0x%0h strb=0x%0h: resp expected=%s actual=%s", is_write ? "WR" : "RD",
                     t.addr, t.strb, axi_lite_seq_item::resp_name(expect_resp),
                     axi_lite_seq_item::resp_name(t.resp)));

    // ---- reference model ----
    if (is_write) begin
      if (in_regs && !zero_strb_wr) begin
        cur = ref_mem.exists(t.addr) ? ref_mem[t.addr] : '0;
        foreach (t.strb[i]) if (t.strb[i]) cur[i*8+:8] = t.data[i*8+:8];
        ref_mem[t.addr] = cur;
      end
    end else begin
      if (in_regs) begin
        cur = ref_mem.exists(t.addr) ? ref_mem[t.addr] : '0;
        if (t.rdata !== cur)
          flag($sformatf("RD addr=0x%0h: data expected=0x%0h actual=0x%0h", t.addr, cur, t.rdata));
      end else if (!in_map) begin
        if (t.rdata !== DECERR_RDATA)
          flag($sformatf("RD addr=0x%0h: DECERR data expected=0x%0h actual=0x%0h", t.addr,
                         DECERR_RDATA, t.rdata));
      end
      // 0x40-0xFF reads are deliberately not data-checked: the slave leaves
      // PRDATA untouched on a decode error (apb_slave.sv:61 sits inside the
      // !decode_err branch), so the value is stale, not predictable.
    end

    exp_q.push_back(t);
    reconcile();
  endfunction

  // Pair each AXI transaction with the APB transfer it should have produced.
  // Stops as soon as an expecting transaction has no transfer to match yet, so
  // ordering between the two subscribers does not matter.
  function void reconcile();
    axi_lite_seq_item e;
    apb_seq_item      a;

    while (exp_q.size() > 0) begin
      if (!expects_apb(exp_q[0])) begin
        void'(exp_q.pop_front());
        continue;
      end
      if (apb_q.size() == 0) return;

      e = exp_q.pop_front();
      a = apb_q.pop_front();
      xcheck_count++;

      if (a.addr !== e.addr)
        flag($sformatf("cross-check addr: AXI=0x%0h APB=0x%0h", e.addr, a.addr));
      if ((a.dir == WRITE) !== (e.dir == AXI_WRITE))
        flag($sformatf("cross-check dir at addr=0x%0h: AXI=%s APB=%s", e.addr,
                       (e.dir == AXI_WRITE) ? "WR" : "RD", (a.dir == WRITE) ? "WR" : "RD"));
      // PPROT is passed through untouched and ignored by the slave, so nothing
      // but this check would notice it being corrupted.
      if (a.PPROT !== e.prot)
        flag($sformatf("cross-check PPROT at addr=0x%0h: AXI=0x%01h APB=0x%01h", e.addr, e.prot,
                       a.PPROT));

      if (e.dir == AXI_WRITE) begin
        if (a.data !== e.data)
          flag($sformatf("cross-check PWDATA at addr=0x%0h: AXI=0x%0h APB=0x%0h", e.addr, e.data,
                         a.data));
        if (a.PSTRB !== e.strb)
          flag($sformatf("cross-check PSTRB at addr=0x%0h: AXI=0x%0h APB=0x%0h", e.addr, e.strb,
                         a.PSTRB));
      end else begin
        // The bridge zeroes the write payload on the read path (:116-117).
        if (a.PSTRB !== '0)
          flag($sformatf("cross-check: read at addr=0x%0h drove PSTRB=0x%0h, expected 0", e.addr,
                         a.PSTRB));
      end
    end
  endfunction

  virtual function void check_phase(uvm_phase phase);
    if (apb_q.size() != 0)
      flag($sformatf("%0d APB transfer(s) with no AXI transaction to account for them",
                     apb_q.size()));
    if (exp_q.size() != 0)
      flag($sformatf("%0d AXI transaction(s) still waiting for an APB transfer", exp_q.size()));
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
              "Scoreboard: %0d AXI transactions, %0d APB transfers, %0d cross-checked, %0d errors",
              axi_count, apb_count, xcheck_count, error_count), UVM_NONE)
    if (error_count > 0) `uvm_error(get_type_name(), "TEST FAILED")
    else `uvm_info(get_type_name(), "TEST PASSED", UVM_NONE)
  endfunction

endclass : axi_lite_scoreboard
