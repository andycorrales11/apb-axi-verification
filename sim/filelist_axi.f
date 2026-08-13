// sim/filelist_axi.f -- the AXI4-Lite compile (make ... PROTO=axi).
//
// Both DUTs (rtl/apb_slave.sv, the vendored bridge) and the UVM amalgamation are
// passed by the Makefile instead, so mutate.py can swap in a mutated copy of
// either DUT by overriding one make variable. Verilator -f files do not expand
// make variables, hence the split.

// ---- include search paths ----
// The APB tree: this build reuses the APB agent passively.
+incdir+tb
+incdir+tb/seq
+incdir+tb/agent
+incdir+tb/env
+incdir+tb/test
// The AXI tree.
+incdir+tb/axi
+incdir+tb/axi/seq
+incdir+tb/axi/agent
+incdir+tb/axi/env
+incdir+tb/axi/test
// Third-party headers: pulp's struct typedef macros and `FF* register macros.
+incdir+third_party/pulp/axi/include
+incdir+third_party/pulp/common_cells/include

// ---- third-party RTL, in dependency order ----
third_party/pulp/common_cells/src/cf_math_pkg.sv
third_party/pulp/common_cells/src/lzc.sv
third_party/pulp/common_cells/src/fifo_v3.sv
third_party/pulp/common_cells/src/addr_decode_dync.sv
third_party/pulp/common_cells/src/addr_decode.sv
third_party/pulp/common_cells/src/spill_register_flushable.sv
third_party/pulp/common_cells/src/spill_register.sv
third_party/pulp/common_cells/src/fall_through_register.sv
third_party/pulp/common_cells/src/onehot_to_bin.sv
third_party/pulp/common_cells/src/rr_arb_tree.sv
third_party/pulp/axi/src/axi_pkg.sv
third_party/pulp/axi/src/axi_intf.sv

// ---- testbench (interfaces -> packages -> top) ----
// apb_uvm_pkg first: axi_uvm_pkg imports it to reuse the APB agent.
tb/apb_if.sv
tb/apb_uvm_pkg.sv
tb/axi/axi_lite_if.sv
tb/axi/axi_uvm_pkg.sv
tb/axi/tb_axi_top.sv
