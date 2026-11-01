# synth.tcl - Yosys synthesis to the Nangate 45 nm open cell library.
#
# Run:  TOP=<top> yosys -c syn/synth.tcl
#   top = cdc_top    (async FIFO with reset synchronizers)
#   top = mac_accel  (near-memory MAC accelerator, small scratchpad)
#
# Writes build/<top>_netlist.v and build/<top>_area.rpt

yosys -import

if {[info exists ::env(TOP)]} { set top $::env(TOP) } else { set top cdc_top }
set lib lib/NangateOpenCellLibrary_typical.lib
file mkdir build

# cell library as black boxes, so Yosys knows the pin directions
read_liberty -lib $lib

if {$top eq "cdc_top"} {
    read_verilog rtl/sync_2ff.v rtl/reset_sync.v rtl/async_fifo.v rtl/cdc_top.v
    hierarchy -check -top cdc_top
} elseif {$top eq "mac_accel"} {
    read_verilog rtl/mac_accel.v
    # no SRAM macro here, so the scratchpad becomes flops (only 64 words)
    chparam -set SPAD_WORDS 64 mac_accel
    hierarchy -check -top mac_accel
} else {
    error "unknown top: $top"
}

# generic synthesis, then map flops and logic to library cells
synth -top $top -flatten
dfflibmap -liberty $lib
# -D = target period in ps. Buffers up to fanout 12 and resizes cells.
# ABC can't buffer a flop output, see README.
if {[info exists ::env(PERIOD_PS)]} { set period $::env(PERIOD_PS) } else { set period 2000 }
set abc_script "+strash;ifraig;scorr;dc2;dretime;strash;&get,-n;&dch,-f;&nf,{D};&put;buffer,-N,12;upsize,{D};dnsize,{D};stime,-p"
abc -D $period -liberty $lib -script $abc_script
opt_clean -purge
hilomap -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z
setundef -zero
splitnets
opt_clean -purge
autoname

tee -o build/${top}_area.rpt stat -liberty $lib
check -assert
write_verilog -noattr -noexpr build/${top}_netlist.v
puts "Netlist written to build/${top}_netlist.v"
