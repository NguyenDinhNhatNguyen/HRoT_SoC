# Vivado build of the Pmod pin walk test, run from this folder:
#   vivado -mode batch -source build_pinwalk.tcl
# Output: build/pinwalk.bit. Convert and load it like the SoC (see ../firmware/make_on_pc.ps1).
set here [file normalize [file dirname [info script]]]
set part "xck26-sfvc784-2LV-c"

file mkdir "$here/build"
cd "$here/build"

create_project -in_memory -part $part
set_property target_language Verilog [current_project]
# kv260_bd.tcl reads the build directory from argv index 4
set argv [list $part x x x "$here/build"]
source $here/../kv260_bd.tcl

read_verilog $here/PinWalk_Top.v
read_xdc $here/pinwalk.xdc

synth_design -top PinWalk_Top -part $part
opt_design
place_design
route_design
write_bitstream -force pinwalk.bit
