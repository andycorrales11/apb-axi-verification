# AMBA APB and AXI Verification Project

**GOAL**: Design and then verify a reusable UVM verification environment for AMBA bus protocols, and use a mutation-testing harness to plant known bugs into the DUT in order to check if bug catching really works.

**TOOLS** I will be using Verilator 5.048 with support for UVM. The UVM version I am using is 2020.3.1, as a pre flattened single-file amalgamation. This makes up for the lack of support for the uvm_core source tree.

**STATUS** Both environments are built end to end and passing. The APB testbench (agent, scoreboard, coverage) and the AXI4-Lite environment against third-party RTL (active AXI4-Lite agent, plus the APB agent reused in passive mode for a bridge-side cross-check) each run under a mutation-testing harness (`mutants/mutate.py`) that plants seeded bugs into the DUT and scores CAUGHT / (CAUGHT + ESCAPED).

**RESULTS (APB)**
- **Mutation score: 9 / 10 seeded bugs caught (90%)** — the single escapee, a missing register reset, is undetectable in 2-state simulation and was predicted in advance. Zero stillborn.
- **Functional coverage: 52 / 52 bins (100%)** at 200 constrained-random transfers. Verilator has no covergroup support, so the model is hand-implemented in `apb_coverage`.
- Test plan, feature-to-coverage mapping, and the known gaps: [`docs/apb_test_plan.md`](docs/apb_test_plan.md).

**RESULTS (AXI4-Lite → APB bridge)**
- **Mutation score: 11 / 11 seeded bugs caught (100%)** — zero escaped, zero stillborn. Two of the eleven (`pprot_dropped`, `zero_strb_issues_apb`) leave the AXI response correct and are caught only by the passive APB agent's bridge-side cross-check.
- **Functional coverage: 45 / 45 bins (100%)** at 200 constrained-random transactions (seeds 1/2/3/42/99; `SEED=7` reaches 44/45, a sample-size artifact — it draws only 82 writes).
- Test plan, coverage model, stimulus-shaping notes, and mutation table: [`docs/axi_lite_test_plan.md`](docs/axi_lite_test_plan.md).

**COMMANDS**
```bash
make build              # elaborate + compile the APB testbench
make run                # build + run (TEST=apb_base_test by default)
make run TEST=apb_random_test
make waves              # run with VCD tracing -> build/waves.vcd
make lint                # Verilator lint-only pass
make mutants             # run the bug-injection harness (APB)

# AXI4-Lite environment (JOBS=1 required -- JOBS=2 OOM-terminates the link step)
make run PROTO=axi JOBS=1                    # TEST=axi_base_test by default
make run PROTO=axi JOBS=1 TEST=axi_random_test SEED=7
make mutants-axi         # bug-injection harness against the bridge (~2.5 h)
make clean
```

** SOURCES **
- *AMBA APB Protocol Specification* - Arm Ltd: https://developer.arm.com/documentation/ihi0024/latest/
- *AMBA AXI Protocol Specification* - Arm Ltd: https://support.arm.com/documentation/ihi0022/latest 
- *Verilog Language and Application v29.0* Cadence Training
- *Essential SystemVerilog for UVM v1.2.5* Cadence Training
- *SystemVerilog Accelerated Verification using UVM v1.2.6* Cadence Training
- *Verilog Style Guide* - https://github.com/lowrisc/style-guides/blob/master/VerilogCodingStyle.md
- *UVM Cookbook* - Siemens Verification Academy