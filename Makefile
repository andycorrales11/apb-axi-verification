# =============================================================================
# Makefile -- UVM-on-Verilator flow for the APB/AXI verification project
# -----------------------------------------------------------------------------
# Targets:
#   make smoke    -- compile + run the upstream UVM "hello world" (proves toolchain)
#   make build    -- elaborate + compile the APB testbench into a binary
#   make run      -- build then run (TEST=<uvm test name>, default apb_base_test)
#   make waves    -- run with VCD tracing -> build/waves.vcd
#   make lint     -- Verilator lint-only pass over the TB + DUT
#   make mutants  -- run the bug-injection harness (mutants/mutate.py)
#   make clean    -- remove build artifacts
#
# Add PROTO=axi to any of the above to build the AXI4-Lite environment
# (tb_axi_top: AXI agent -> pulp-platform axi_lite_to_apb -> apb_slave) instead
# of the APB one:
#   make run PROTO=axi
#   make run PROTO=axi TEST=axi_random_test SEED=7
#
# Everything is overridable on the command line, e.g.:
#   make run TEST=apb_smoke_test
#   make build RTL_SLAVE=build/mut_3/apb_slave.sv OBJ_DIR=build/mut_3
# =============================================================================

# ---- Toolchain (PIN the 5.048 build; /usr/bin/verilator is 5.020 = too old) --
VERILATOR ?= /home/andy/tools/verilator-master/bin/verilator

# ---- Constrained-random solver ----------------------------------------------
# Verilator's randomize()-with-constraints shells out to an SMT solver at run
# time. No system z3; use the one in the z3venv. Exported so the sim binary
# (and mutate.py's `make run` children) inherit it.
export VERILATOR_SOLVER ?= /home/andy/tools/z3venv/bin/z3 --in

# ---- UVM (pre-flattened amalgamation -- see README "Why the flat UVM file") --
UVM_DIR  ?= /home/andy/tools/verilator-master/test_regress/t/uvm
UVM_FLAT ?= $(UVM_DIR)/uvm_pkg_all_v2020_3_1_dpi.svh
UVM_DPI  ?= $(UVM_DIR)/v2020_3_1/dpi/uvm_dpi.cc

# ---- Which protocol environment to build -------------------------------------
# PROTO=apb (default) -> tb_top: the APB agent drives rtl/apb_slave.sv directly.
# PROTO=axi           -> tb_axi_top: an AXI4-Lite agent drives the vendored
#                        axi_lite_to_apb bridge into the same slave, with the
#                        APB agent watching that bus passively.
# All `?=` so a command-line value always wins.
PROTO ?= apb

ifeq ($(PROTO),axi)
  FILELIST   ?= sim/filelist_axi.f
  TOP        ?= tb_axi_top
  TEST       ?= axi_base_test
  # Kept off filelist_axi.f for the same reason as RTL_SLAVE: mutate.py swaps in
  # a mutated copy of the bridge by overriding this one variable.
  AXI_BRIDGE ?= third_party/pulp/axi/src/axi_lite_to_apb.sv
else
  FILELIST   ?= sim/filelist.f
  TOP        ?= tb_top
  TEST       ?= apb_base_test
  AXI_BRIDGE ?=
endif

# ---- Project sources ---------------------------------------------------------
RTL_SLAVE ?= rtl/apb_slave.sv          # the APB DUT; mutate.py overrides this
SEED      ?= 1

# ---- Build locations ---------------------------------------------------------
# Per-protocol so an APB build and an AXI build don't stomp each other's Mdir.
OBJ_DIR ?= build/obj_dir_$(PROTO)
BIN      = $(OBJ_DIR)/V$(TOP)
SIM_LOG ?= build/sim_$(PROTO).log

# ---- Build parallelism / memory safety ---------------------------------------
# The UVM amalgamation generates a handful of huge C++ translation units; each
# g++ invocation compiling one can peak several GB of RAM. `-j 0` (Verilator's
# "use all cores") launches that many g++ processes at once, which is enough to
# exhaust RAM on a modest machine and lock up the whole system (not just the
# build) rather than cleanly OOM-killing the compile. JOBS caps parallelism;
# MEM_CAP puts a hard ceiling on the whole build via a systemd user scope so a
# runaway build gets killed instead of taking the machine down. Override both
# on the command line if your machine has more headroom, e.g. `make build JOBS=4`.
JOBS     ?= 2
MEM_CAP  ?= 5G
RUN_LIMITED ?= systemd-run --user --scope -p MemoryMax=$(MEM_CAP) --collect --

# ---- Verilator flags ---------------------------------------------------------
# --binary  : elaborate + compile + link into a runnable executable
# --timing  : enable timing/coroutines (#delays, clocking blocks, fork-join)
# --vpi     : UVM's DPI/VPI layer needs this
# -Wno-...  : silence lint noise from the UVM amalgamation (not our code)
VFLAGS ?= --binary --timing --vpi \
          -j $(JOBS) \
          --top-module $(TOP) \
          --timescale 1ns/1ps \
          -Wno-lint -Wno-style \
          --Mdir $(OBJ_DIR) \
          +incdir+$(UVM_DIR)

UVM_SRCS = $(UVM_FLAT) $(UVM_DPI)

# Run-time plusargs
# +verilator+seed+N is Verilator's seed plusarg (+ntb_random_seed is a VCS
# convention and is silently ignored -- verified: it does not change the run).
RUN_FLAGS ?= +UVM_NO_RELNOTES +UVM_TESTNAME=$(TEST) +verilator+seed+$(SEED)

# =============================================================================
.PHONY: build run waves lint smoke mutants clean help

help:
	@grep -E '^#   make ' $(MAKEFILE_LIST) | sed 's/^#  //'

build: $(BIN)

# All tb sources are prerequisites: the class files are `include`d by the
# package, so editing them must retrigger elaboration. The third level of
# wildcard covers the AXI tree's tb/axi/<group>/*.sv depth.
TB_SRCS := $(wildcard tb/*.sv tb/*/*.sv tb/*/*/*.sv)

$(BIN): $(FILELIST) $(RTL_SLAVE) $(AXI_BRIDGE) $(TB_SRCS)
	@mkdir -p $(OBJ_DIR)
	# UVM amalgamation MUST come before our TB files: it defines the UVM macros
	# as global `define directives that the package + tb_top then rely on.
	$(RUN_LIMITED) $(VERILATOR) $(VFLAGS) $(UVM_SRCS) -f $(FILELIST) $(RTL_SLAVE) $(AXI_BRIDGE)

run: build
	@mkdir -p $(dir $(SIM_LOG))
	$(BIN) $(RUN_FLAGS) 2>&1 | tee $(SIM_LOG)

waves: VFLAGS += --trace -DTRACE
waves: clean build
	@mkdir -p build
	$(BIN) $(RUN_FLAGS) 2>&1 | tee $(SIM_LOG)
	@echo ">> wrote build/waves.vcd  (open with: gtkwave build/waves.vcd)"

lint:
	$(VERILATOR) --lint-only --timing -Wall \
	  -Wno-lint -Wno-style \
	  +incdir+$(UVM_DIR) \
	  $(UVM_SRCS) -f $(FILELIST) $(RTL_SLAVE) $(AXI_BRIDGE) --top-module $(TOP)

# ---- Toolchain smoke test: upstream UVM hello world -------------------------
SMOKE_HELLO ?= /home/andy/tools/verilator-master/test_regress/t/t_uvm_hello.v
smoke:
	@mkdir -p build/smoke
	$(RUN_LIMITED) $(VERILATOR) --binary --timing --vpi -j $(JOBS) -Wno-lint -Wno-style \
	  +incdir+$(UVM_DIR) $(UVM_SRCS) $(SMOKE_HELLO) \
	  --top-module t --Mdir build/smoke
	@echo "=== running UVM hello ===" ; \
	build/smoke/Vt +UVM_NO_RELNOTES +UVM_TESTNAME=test | grep -E "TEST PASSED|UVM_FATAL"

# ---- Mutant (bug-injection) harness -----------------------------------------
mutants:
	python3 mutants/mutate.py --config mutants/mutants.yaml --test apb_random_test

clean:
	rm -rf build/obj_dir* build/smoke build/mut_* build/baseline build/sim*.log build/waves.vcd
