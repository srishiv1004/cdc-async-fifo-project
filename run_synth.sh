#!/bin/bash
set -e

LIB="$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"

if [ ! -f "$LIB" ]; then
    echo "ERROR: sky130 liberty file not found at $LIB"
    echo "Check that PDK_ROOT is set correctly: echo \$PDK_ROOT"
    exit 1
fi

yosys -p "
read_verilog -sv top.sv async_fifo.sv uart_rx.sv write_ctrl.sv mem_model.sv
hierarchy -check -top top
synth -top top
dfflibmap -liberty $LIB
abc -liberty $LIB
clean
splitnets -ports
opt_clean
write_verilog synth_netlist.v
stat -liberty $LIB
" | tee synth_report.log

echo ""
echo "Done. Gate-level netlist: synth_netlist.v"
echo "Full synthesis report saved to: synth_report.log"