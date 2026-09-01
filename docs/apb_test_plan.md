# APB4 Slave — Verification Test Plan

DUT: `rtl/apb_slave.sv` · Environment: `tb/` (`apb_uvm_pkg`) · Simulator: Verilator 5.048 + UVM 2020.3.1

This plan enumerates the DUT's features, states how each is stimulated and
checked, maps each to functional coverage bins and to seeded mutants, and —
importantly — records the features that are **not** verified. The gap rows are
part of the plan, not an omission from it.

---

## 1. DUT summary

A 16-entry × 32-bit register file behind an APB4 slave interface.

| Property | Value |
|---|---|
| Registers | 16 × 32-bit, all read/write, no reserved or read-only bits |
| Address map | `0x00`–`0x3F` valid; index = `PADDR[5:2]` |
| Decode error | `\|PADDR[31:6]` → `PSLVERR` asserted in ACCESS |
| Handshake | Fixed 2-cycle (SETUP → ACCESS), **no wait states** |
| Byte enables | `PSTRB` per-lane on writes |
| `PPROT` | Present on the port list, **unused by the RTL** |
| Reset | Active-low `PRESETn`, async; clears registers and outputs |

## 2. Strategy

- **Stimulus** — one directed sequence (`apb_base_seq`: write/read-back at
  `0x04`) and one constrained-random sequence (`apb_random_seq`, default 200
  transfers). Randomization is shaped in `apb_seq_item`: word alignment forced,
  ~10% of transfers forced to decode-error addresses, and those error addresses
  split 50/50 between just-past-boundary (`0x40`–`0x7C`) and far out-of-range so
  the solver cannot ignore the boundary cases that catch off-by-one decode bugs.
- **Checking** — `apb_scoreboard` runs an independent reference model
  (`ref_mem`) that restates the address map by hand rather than importing it
  from the stimulus, and honors `PSTRB` lane-by-lane. It checks `PSLVERR`
  against an independently computed expectation on every transfer, and read data
  against the model.
- **Coverage** — Verilator 5.048 has no covergroup support, so the model is
  hand-implemented as named bins with counters in `apb_coverage`, reported at
  `report_phase` with the unhit bins listed by name.
- **Checker validation** — `mutants/mutate.py` plants each seeded bug from
  `mutants/mutants.yaml` into a copy of the DUT, rebuilds, and scores
  `CAUGHT / (CAUGHT + ESCAPED)`. Coverage says what was exercised; the mutation
  score says whether the checkers would have noticed.
- **Hang detection** — 1 ms global watchdog (`tb/tb_top.sv:70`) raises
  `UVM_FATAL`; the runner classifies a timeout as CAUGHT.

---

## 3. Feature table

Status: **V** verified · **P** partial · **X** not verified

| # | Feature | Stimulus | Checker | Coverage bins | Mutants | |
|---|---|---|---|---|---|---|
| F1 | Full-word register write | directed + random | `ref_mem` update, proven by later read | `WR.reg[0..15]` | `wdata_lane0_everywhere`, `decode_off_by_one` | **V** |
| F2 | Register read | directed + random | read-data compare vs model | `RD.reg[0..15]` | `read_neighbor`, `decode_off_by_one` | **V** |
| F3 | Partial write via `PSTRB` | random `PSTRB` | model applies enabled lanes only | `pstrb[0000..1111]` (16) | `ignore_pstrb`, `wdata_lane0_everywhere` | **V** |
| F4 | Zero-strobe write is a no-op | random (`PSTRB==0`) | model leaves register unchanged | `pstrb[0000]` | `ignore_pstrb` | **V** |
| F5 | Address decode, in-range `0x00`–`0x3F` | `c_addr_range` | `expect_err == 0`, data path checked | register bins | `decode_mask_narrow` | **V** |
| F6 | Decode error → `PSLVERR` | 10% `force_decode_err`, boundary-split | independent `expect_err` compare | `RD/WR.decode_err`, `slverr==0/1` | `no_slverr_on_decode`, `decode_mask_narrow` | **V** |
| F7 | Write/read of every register | random over 16 indices | per-register model entries | 32 dir×reg bins | `decode_off_by_one` | **V** |
| F8 | APB FSM sequencing IDLE→SETUP→ACCESS | every transfer | monitor requires `PSEL && !PENABLE` then `PENABLE && PREADY`; watchdog | **none** | `setup_wrong_encoding`, `pready_early` | **P** |
| F9 | `PREADY` handshake / wait states | **none** — DUT is fixed 2-cycle | driver and monitor poll `PREADY`; watchdog catches a stuck-low | **none** | `pready_stuck_low`, `pready_early` | **P** |
| F10 | Reset clears registers and outputs | power-on reset only | reads of unwritten registers expect `0` | **none** | `reset_skip_registers` | **P** |
| F11 | `PPROT` transported and honored | randomized and driven | **none** | **none** | — | **X** |
| F12 | Unaligned address behavior | **constrained out** (`c_addr_aligned`) | — | — | — | **X** |
| F13 | Mid-transfer reset | **none** | — | — | — | **X** |
| F14 | Back-to-back transfers (`PSEL` held across transfers) | **none** — driver returns to IDLE each time | — | **none** | — | **X** |

---

## 4. Coverage model — 52 bins

Implemented by hand in `tb/env/apb_coverage.sv` (no covergroup support).

| Group | Bins | Definition |
|---|---:|---|
| direction × register | 32 | each of 16 registers both read and written, in-range only |
| decode error × direction | 2 | out-of-range access seen on a read and on a write |
| `PSTRB` pattern | 16 | all 16 strobe values observed on writes |
| `PSLVERR` value | 2 | response seen both asserted and deasserted |
| **Total** | **52** | |

**Result:** 52/52 (100%) at 200 random transfers — `apb_random_test`, clean
scoreboard (`build/sim.log`). The directed smoke test alone reaches 4/52, which
is the intended split: the directed sequence proves the path works, the random
sequence closes the model.

**What this number does not include.** Every bin is transaction-level. There are
no protocol or temporal bins — nothing counts FSM state transitions, wait-state
depth, or back-to-back versus IDLE-separated transfers — and no bins for
`PPROT`. Closure at 52/52 means the transaction space was exercised, not that
the protocol space was.

---

## 5. Known gaps

Carried deliberately; each is a real hole, listed so the coverage number is not
read as more than it is.

1. **`PPROT` is stimulus without a checker** (F11). It is randomized
   (`apb_seq_item.sv:19`), driven (`apb_driver.sv:44`), and sampled by the
   monitor (`apb_monitor.sv:52`) — but the RTL never references it, the
   scoreboard never checks it, and no bin counts it. A mutant that corrupted
   `PPROT` would escape.
2. **No wait-state stimulus** (F9). The DUT always completes in 2 cycles, so the
   `PREADY` polling loops in both driver and monitor only ever see the fixed
   case. Adding random wait states to the RTL is the cheapest way to make those
   loops meaningful.
3. **No mid-test reset** (F13). The driver waits for `PRESETn` once at the top of
   `run_phase`; a reset dropping mid-transfer would hang it. Needs
   `fork`/`disable fork` and a decision on aborting versus finishing the
   in-flight item.
4. **No back-to-back transfers** (F14). The driver deasserts `PSEL` after every
   transfer, so the DUT is never exercised with a new SETUP immediately
   following an ACCESS.
5. **No protocol assertions.** Sequencing is enforced implicitly by the
   monitor's sampling structure rather than by explicit SVA.
6. **Unaligned addresses are constrained out** (F12). Deliberate: the RTL decodes
   `PADDR[5:2]` while the reference model keys on the full address, so unaligned
   accesses would alias in the DUT but not in the model. The DUT's intended
   behavior here is unspecified.
7. **2-state simulation limits reset checking** (F10). Verilator initializes
   state to zero, which is also the reset value, so a missing register reset is
   invisible without X-propagation or a preload-then-reset sequence. This is why
   `reset_skip_registers` is expected to escape.

---

## 6. Mutation results

Ten seeded bugs in `mutants/mutants.yaml`, run against `apb_random_test`.
Baseline (unmutated) must pass clean or the score is meaningless.

**Result: 9 / 10 caught — 90 % mutation score.** Baseline passed clean. Zero
stillborn: every mutant compiled, so none were excluded from the denominator.

| Mutant | Targets | Feature | Outcome |
|---|---|---|---|
| `decode_off_by_one` | index from `PADDR[6:3]` | F1/F2/F7 | CAUGHT |
| `decode_mask_narrow` | `0x40`–`0x7F` silently accepted | F6 | CAUGHT — the boundary split exists for this |
| `setup_wrong_encoding` | SETUP decoded as `2'b01` | F8 | CAUGHT |
| `ignore_pstrb` | writes ignore byte enables | F3 | CAUGHT |
| `wdata_lane0_everywhere` | byte-lane routing | F3 | CAUGHT |
| `read_neighbor` | read returns `index+1` | F2 | CAUGHT |
| `no_slverr_on_decode` | decode error never flagged | F6 | CAUGHT |
| `pready_stuck_low` | handshake hangs | F9 | CAUGHT via watchdog |
| `pready_early` | `PREADY` in SETUP | F8/F9 | CAUGHT |
| `reset_skip_registers` | registers not cleared | F10 | **ESCAPED — predicted, see gap 7** |

The single escapee is the one this plan predicted would escape, for the reason
it predicted: 2-state simulation cannot distinguish "reset to zero" from
"initialized to zero." Closing it needs a directed sequence that writes non-zero
to every register, asserts reset, then reads back — which is the concrete next
item, and a gap in **stimulus**, not in the checker.

`make mutants` exits non-zero whenever anything escapes (`mutate.py:236`), by
design, so the harness can gate CI later.

`setup_wrong_encoding` is not hypothetical: it is the real bug this environment
found during bring-up. The DUT decoded SETUP as `{PSEL,PENABLE} == 2'b01` — PSEL
low, PENABLE high, a state no legal APB transfer produces. Real SETUP fell
through to the `default` arm, so `index` and `decode_err` were never latched and
every access silently hit register 0. The directed write/read-back at `0x04`
still *passed*, because the write and the read aliased to the same wrong
register — only the scoreboard's independent reference model caught it. It was
kept as a mutant afterward.

Score is regenerated by `make mutants` into `build/mutants_report.log`.
