# synth_nangate.tcl - trial Yosys synthesis of SoC_Top with the open NanGate45 library (home flow),
# FOR TRENDS ONLY. Not GPDK45 and not Genus. Official numbers come from Genus on the school server.
# The memories are black boxes (mem_bb.v).
# Run through asic/run_yosys.sh, parameters come from environment variables:
#   YS_TOP     top module (SoC_Top)
#   YS_SRCS    Verilog file list, mem_bb.v included
#   YS_OUT     output folder
#   YS_LIB     NanGate45 liberty file (never committed)
#   YS_ABC_D   abc delay target in ps (default 2000)
yosys -import

set top   $::env(YS_TOP)
set out   $::env(YS_OUT)
set lib   $::env(YS_LIB)
set abc_d [expr {[info exists ::env(YS_ABC_D)] ? $::env(YS_ABC_D) : 2000}]
file mkdir $out

foreach f $::env(YS_SRCS) {
    read_verilog -defer $f
}
hierarchy -check -top $top

# Like synth -flatten, except the fine step maps $lcu (the carry of add, subtract and compare)
# to Kogge-Stone instead of the default ripple, closer to the adders Genus picks.
set ks [file join [file dirname [info script]] lcu_kogge_stone.v]
synth -top $top -flatten -run :fine
opt -fast -full
memory_map
opt -full
techmap -autoproc -map +/techmap.v -map $ks
opt -fast
abc
opt -fast
synth -run check:
tee -o $out/stat_generic.txt stat

# Flops to NanGate45 cells, logic to standard cells for the delay target. The abc script adds
# buffer, upsize and dnsize because the default one leaves high-fanout nets with huge delays.
dfflibmap -liberty $lib
set abc_scr "+strash;&get,-n;&fraig,-x;&put;scorr;dc2;dretime;strash;&get,-n;&dch,-f;&nf,-D,$abc_d;&put;buffer,-p;upsize,-D,$abc_d;dnsize,-D,$abc_d;stime,-p"
abc -liberty $lib -D $abc_d -script $abc_scr
opt_clean -purge
hilomap -singleton -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z
setundef -zero
splitnets -ports
opt_clean -purge
tee -o $out/stat.txt stat -liberty $lib
write_verilog -noattr -noexpr -nohex -nodec $out/${top}_nangate.v
