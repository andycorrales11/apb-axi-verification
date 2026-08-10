// sim/filelist.f -- the static, relative-path part of the compile.
//
// What's NOT here (passed by the Makefile on the command line instead):
//   * the UVM amalgamation + DPI shim + its +incdir   ($(UVM_*) vars)
//   * the DUT, rtl/apb_slave.sv                        ($(RTL_SLAVE))
// The DUT is kept off this list so the mutant runner can swap in a mutated
// copy just by changing one make variable - no edits to this file.
//
// Verilator's -f files do NOT expand $(make variables), which is exactly why
// the variable bits live in the Makefile and only fixed relative paths live
// here.

// ---- include search paths for the package's `include directives ----
+incdir+tb
+incdir+tb/seq
+incdir+tb/agent
+incdir+tb/env
+incdir+tb/test

// ---- testbench (interface -> package -> top) ----
tb/apb_if.sv
tb/apb_uvm_pkg.sv
tb/tb_top.sv
