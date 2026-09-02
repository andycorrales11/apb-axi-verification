# AXI4-Lite → APB Bridge — Verification Test Plan

DUT: `third_party/pulp/axi/src/axi_lite_to_apb.sv` (pulp-platform) with
`rtl/apb_slave.sv` behind it · Environment: `tb/axi/` (`axi_uvm_pkg`) ·
Simulator: Verilator 5.048 + UVM 2020.3.1

Companion to [`apb_test_plan.md`](apb_test_plan.md). The APB plan verifies RTL I
wrote; this one verifies third-party RTL I did not, which is the point — a
testbench and a DUT written by the same person can share the same wrong
assumption. As before, the gap rows are part of the plan.

---

## 1. DUT summary

An AXI4-Lite slave port converted to a single APB4 master port, driving the same
16 × 32-bit register file used in the APB phase.

| Property | Value |
|---|---|
| Bridge config | `NoApbSlaves=1`, `NoRules=1`, `PipelineRequest=0`, `PipelineResponse=0` |
| Bridge address map | one rule, `0x0000_0000`–`0x0000_0100` **exclusive** (`tb_axi_top.sv:98`) |
| Slave decode | `\|PADDR[31:6]` → `PSLVERR`, so `0x40`–`0xFF` is mapped but errors |
| AW/W acceptance | request gated on `AWVALID & WVALID`; `AWREADY`/`WREADY` are the same expression (`:129-132`) |
| Arbitration | `rr_arb_tree` between read and write, `LockIn`, one request in flight |
| Zero-strobe write | no APB transfer, answered `OKAY` (`:299`, `:319`) |
| Off-map access | no APB transfer, answered `DECERR` |
| Off-map read data | `0x DEA110C8` fill pattern (`:291`) |
| `PPROT` | passed through unmodified; the slave ignores it |

### Response classes

| AXI address | `WSTRB` | APB transfer | Response |
|---|---|---|---|
| `0x00`–`0x3F` | ≠ 0 | yes | `OKAY` |
| `0x40`–`0xFF` | ≠ 0 | yes | `SLVERR` (from `PSLVERR`) |
| ≥ `0x100` | ≠ 0 | none | `DECERR` |
| any | 0 (write) | **none** | **`OKAY`** |

That last row is the bridge's most surprising behavior: the zero-strobe check
sits in the same branch as the decode check and is evaluated first, so a
zero-strobe write to an unmapped address is answered `OKAY` and the decode error
is masked. It is modelled deliberately rather than constrained away.

## 2. Strategy

- **Stimulus** — a directed sequence (`axi_lite_base_seq`: write/read-back,
  partial strobe, one address of each class, both zero-strobe corners) and a
  constrained-random one (`axi_lite_random_seq`, 200 transactions). Shaping
  lives in `axi_lite_seq_item`: word alignment forced, address class distributed
  7:2:2 across REG/SLVERR/DECERR, off-map addresses split between
  just-past-boundary and far out-of-range, and zero-strobe writes raised to 20 %
  of writes so the masked-`DECERR` corner is actually reached.
- **Selectors are drawn outside the constraint solver.** `dir`, `addr_class` and
  `zero_strb` are non-`rand` and chosen in `pre_randomize()`; the solver only
  fills in a payload inside the branch it is handed. This is not stylistic. A
  `dist` weight on a selector is not honored, because the solver samples the
  joint (selector, payload) space and a selector's frequency therefore tracks how
  many payload values its branch permits: `ADDR_REG` allows 16 addresses against
  `ADDR_DECERR`'s millions, and an intended 127/36/36 came out **42/79/79 —
  inverted**. `solve … before` does not fix it. Nor is the problem confined to
  one field: `c_strb` couples `dir` to `zero_strb`, so a 20 % zero-strobe draw
  reached coverage as 34 % *of writes*. Measured over six seeds after the change,
  the realized mix averages 122.8/38.2/39.0 against an intended 127.3/36.4/36.4,
  writes average 99.0 of 200, and zero-strobe writes are 121 of 594 (20.4 %).
- **Coverage reports the realized mix, not only bin hit/miss.** Every bin needs
  just one hit, so a badly skewed stimulus can reach 100 % while barely touching
  a real register. The mix line is what exposed the skew above; without it the
  environment looked fully covered and was not.
- **Timing stimulus** — the part that is genuinely new versus APB. Each
  transaction randomizes AW-vs-W ordering (`aw_w_skew` × `skew_cycles`) and how
  long the master withholds `BREADY`/`RREADY`. Withholding `BREADY` is real
  backpressure: a full write-response register stalls the bridge's APB FSM
  (`:298`).
- **Checking, two independent layers.**
  1. `axi_lite_scoreboard.write_axi` — a reference model at the AXI boundary:
     expected response per address class, reads return what was last written,
     `WSTRB` honored lane-by-lane.
  2. `axi_lite_scoreboard.write_apb` — the **cross-check**, fed by the APB agent
     reused passively on the bus behind the bridge. Every AXI transaction that
     should reach the slave must produce exactly one APB transfer with matching
     address, direction, data, strobe and `PPROT`; every one that should not must
     produce none.
  The address map is restated by hand in the scoreboard, not imported from the
  stimulus or from `tb_axi_top` — a checker that derives its expectations from
  the thing it is checking cannot fail.
- **Reconciliation** — the two queues are paired in FIFO order from whichever
  subscriber fires. They cannot be matched inline: with a short `b_ready_delay`
  the B handshake lands on the same edge the APB access completes, so both
  monitors emit in the same timestep and their order is a race.
- **Coverage** — hand-implemented bins (no covergroup support), sampled from the
  **driver**, because `aw_w_skew` and the ready-delays are choices the driver
  made and a monitor watching wires cannot recover them.
- **Checker validation** — `mutants/mutants_axi.yaml`, scored by the same
  runner as the APB set.
- **Hang detection** — 1 ms watchdog (`tb_axi_top.sv:210`) raises `UVM_FATAL`;
  the runner classifies a timeout as CAUGHT.

---

## 3. Feature table

Status: **V** verified · **P** partial · **X** not verified

| # | Feature | Stimulus | Checker | Coverage bins | Mutants | |
|---|---|---|---|---|---|---|
| F1 | Register write through the bridge | directed + random | reference model, proven by later read | `WR.addr[REG]` | `pstrb_forced_full`, `setup_asserts_penable` | **V** |
| F2 | Register read through the bridge | directed + random | read-data compare vs model | `RD.addr[REG]` | `setup_asserts_penable` | **V** |
| F3 | Partial write via `WSTRB` | directed + random | model applies enabled lanes only | `wstrb[0001..1111]` | `pstrb_forced_full` | **V** |
| F4 | Zero-strobe write issues no APB transfer | 20 % of writes | cross-check expects zero transfers | `wstrb[0000]` | `zero_strb_issues_apb` | **V** |
| F5 | Zero-strobe write off-map answers OKAY | directed + random | reference model expects `OKAY`, not `DECERR` | `zero_strb_off_map` | — | **V** |
| F6 | Off-map access → `DECERR`, no APB transfer | directed + 20 % random | response compare + cross-check expects none | `RD/WR.addr[DECERR]`, `resp[DECERR]` | `read_decerr_to_okay`, `write_decerr_to_slverr` | **V** |
| F7 | Mapped-but-past-registers → `SLVERR` | directed + 20 % random | response compare | `RD/WR.addr[SLVERR]`, `resp[SLVERR]` | `read_pslverr_ignored`, `write_pslverr_ignored` | **V** |
| F8 | Off-map read returns the `0xDEA110C8` fill | directed + random | explicit data compare | `RD.resp[DECERR]` | `decerr_rdata_changed` | **V** |
| F9 | AW/W accepted only when both are valid | `aw_w_skew` × `skew_cycles` | monitor pairs AW+W; watchdog on a stall | `AW_FIRST/W_FIRST/SAME_CYCLE × bdelay` | `aw_ready_without_w` | **V** |
| F10 | APB request fidelity (addr, dir, data, strobe) | every transfer | cross-check, field by field | — | `pstrb_forced_full` | **V** |
| F11 | `PPROT` transported to the APB bus | randomized and driven | **cross-check only** — the slave ignores `PPROT` | — | `pprot_dropped` | **V** |
| F12 | `BREADY`/`RREADY` backpressure | `b_ready_delay`, `r_ready_delay` 0–3 | responses still correct under stall | `bdelay[0..3]`, `rdelay[0..3]` | — | **V** |
| F13 | No spurious/duplicated response beats | every transfer | monitor errors on a B/R with nothing outstanding; `check_phase` flags unanswered requests | — | — | **V** |
| F14 | APB SETUP→ACCESS sequencing from the bridge | every transfer | passive APB monitor requires `PSEL && !PENABLE` then `PENABLE && PREADY` | — | `penable_stuck_low`, `setup_asserts_penable` | **P** |
| F15 | `SLVERR` read data | random | **none** — see gap 1 | — | — | **X** |
| F16 | Power-on reset | reset once at time 0 | reads of unwritten registers expect `0` | — | — | **P** |
| F17 | Mid-test reset | **none** | — | — | — | **X** |
| F18 | Multiple APB slaves / multi-rule decode | **none** — `NoApbSlaves=1` | — | — | — | **X** |
| F19 | `PipelineRequest`/`PipelineResponse=1` | **none** — both tied 0 | — | — | — | **X** |
| F20 | Outstanding / back-to-back transactions | **none** — driver is one-at-a-time | — | — | — | **X** |
| F21 | Unaligned addresses | **constrained out** (`c_addr_aligned`) | — | — | — | **X** |

---

## 4. Coverage model — 45 bins

Implemented by hand in `tb/axi/env/axi_lite_coverage.sv`, sampled from the
driver.

| Group | Bins | Definition |
|---|---:|---|
| address class × direction | 6 | REG / SLVERR / DECERR, each read and written |
| response × direction | 6 | OKAY / SLVERR / DECERR, each read and written |
| `WSTRB` pattern | 16 | all 16 strobe values observed on writes |
| AW/W skew × `BREADY` delay | 12 | 3 orderings × 4 delays, writes only |
| `RREADY` delay | 4 | 0–3 cycles, reads only |
| zero-strobe write off-map | 1 | the masked-`DECERR` corner |
| **Total** | **45** | |

`EXOKAY` is excluded: nothing in this stack can produce it, and a denominator
containing impossible bins makes the number lie. The monitor raises an error if
one is ever observed.

At 200 transactions, five of six sampled seeds (1, 2, 3, 42, 99) reach **45/45**.
`SEED=7` reaches 44/45, missing `wstrb[1000]`: it happens to draw only 82 writes,
so 62 non-zero-strobe writes have to cover 15 patterns and one comes up empty.
That is a sample-size artifact, not a stimulus gap — raising `+num_trans` closes
it. It is recorded here rather than tuned away, because picking the seed or the
transaction count that reaches 100 % is how a coverage number stops meaning
anything.

---

## 5. Known gaps

1. **`SLVERR` read data is not checked** (F15). On a decode error the slave never
   updates `PRDATA` (`apb_slave.sv:61` sits inside the `!decode_err` branch), so
   what the bridge forwards is the previous read's data. It is stale, not
   predictable from the transaction, so the model deliberately checks only the
   response for `0x40`–`0xFF` reads.
2. **No mid-test reset** (F17). Same gap as the APB driver, and the same fix:
   `fork`/`disable fork` plus a decision on aborting versus finishing the
   in-flight item. The monitor already flushes its staging queues on reset.
3. **Single slave, single rule** (F18). The bridge's `addr_decode` and `PSELx`
   fan-out are the part of it most likely to have index bugs, and with
   `NoApbSlaves=1` none of that logic is exercised meaningfully.
4. **Both pipeline modes untested** (F19). `PipelineRequest`/`PipelineResponse`
   swap the `fall_through_register`s for `spill_register`s, which changes the
   timing relationship this environment's checkers rely on.
5. **No outstanding transactions** (F20). The driver completes each transaction
   before fetching the next, so the bridge's arbiter never sees a read and a
   write competing, and `rr_arb_tree`'s round-robin behavior is untested.
6. **No protocol assertions.** Channel sequencing is enforced implicitly by the
   monitor's staging structure rather than by explicit SVA. In particular
   nothing checks the AXI rule that `VALID` must not wait on `READY`.
7. **The APB slave is reused as-is**, so its own gaps carry over — no wait
   states, so the bridge's `PREADY` polling only ever sees the fixed 2-cycle
   case.

---

## 6. Mutation results

`make mutants-axi` plants one seeded bug at a time into the vendored bridge
(`third_party/pulp/axi/src/axi_lite_to_apb.sv`), rebuilds, and reruns the
`axi_random_test`. The baseline builds and runs clean first; each mutant is then
scored CAUGHT (a `UVM_ERROR`/`UVM_FATAL` fired), ESCAPED (passed anyway — a hole
in the testbench), or STILLBORN (did not compile, excluded from scoring).

**Score: 11 / 11 CAUGHT (100%). Zero escaped, zero stillborn.**

| # | Mutant | What it breaks | Result |
|---|--------|----------------|--------|
| 1 | `read_pslverr_ignored` | Read response ignores `PSLVERR` → 0x40–0xFF reads answer OKAY instead of SLVERR | CAUGHT |
| 2 | `write_pslverr_ignored` | Write response ignores `PSLVERR` → 0x40–0xFF writes answer OKAY instead of SLVERR | CAUGHT |
| 3 | `read_decerr_to_okay` | Off-map read answers OKAY instead of DECERR → illegal access silently accepted | CAUGHT |
| 4 | `write_decerr_to_slverr` | Off-map write answers SLVERR instead of DECERR → wrong error class | CAUGHT |
| 5 | `decerr_rdata_changed` | Off-map read returns 0x0 instead of the bridge's `0xDEA110C8` fill | CAUGHT |
| 6 | `pprot_dropped` | Bridge drops `PPROT` on the APB side — AXI result unchanged, **cross-check only** | CAUGHT |
| 7 | `zero_strb_issues_apb` | Zero-strobe write issues an APB transfer instead of none — AXI answers OKAY either way, **cross-check only** | CAUGHT |
| 8 | `pstrb_forced_full` | Bridge drives `PSTRB` all-ones → partial writes clobber the whole register | CAUGHT |
| 9 | `penable_stuck_low` | Access phase never asserts `PENABLE` → slave never completes, watchdog trips | CAUGHT |
| 10 | `setup_asserts_penable` | Setup phase asserts `PENABLE` → slave skips SETUP, uses a stale index/decode_err | CAUGHT |
| 11 | `aw_ready_without_w` | Write accepted on `AWVALID` alone → W data sampled before it is valid | CAUGHT |

Mutants **6 and 7 are the ones this environment was built to catch.** Both leave
the AXI-visible response correct — a dropped `PPROT` and a masked zero-strobe
write are invisible on the AXI side — and are caught *only* because the APB
agent runs in passive mode and the scoreboard cross-checks what the bridge
actually emitted on APB against what it should have. Without that cross-check
both would ESCAPE. Catching them is the direct payoff of the passive-APB-agent
design described in §2.
