# Run from repo root:  vsim -c -do sim/questa/apb_sva.do
# Fault demo:          vsim -c -do "set BUG 1; do sim/questa/apb_sva.do"
onerror {quit -code 1}

if {![info exists BUG]} { set BUG 0 }

if {[file exists sim/questa/work]} { vdel -all -lib sim/questa/work }
vlib sim/questa/work
vmap work sim/questa/work

# -mfcu: one compilation unit so the free-standing bind elaborates.
vlog -sv -mfcu +cover +incdir+tb \
    tb/apb_if.sv \
    rtl/apb_slave.sv \
    tb/checker/apb_protocol_checker.sv \
    tb/checker/apb_protocol_bind.sv \
    sim/questa/apb_sva_tb.sv

# -onfinish stop: keep $finish from quitting before the reports run.
vsim -coverage -assertdebug -onfinish stop -voptargs=+acc work.apb_sva_tb +BUG=$BUG

run -all

echo "======================== assertion report ========================"
assertion report -r /*
echo "======================== directive (cover) report ================"
coverage report -details -directive
echo "======================== code coverage summary ==================="
coverage report -summary

coverage save sim/questa/apb_sva.ucdb
quit -code 0
