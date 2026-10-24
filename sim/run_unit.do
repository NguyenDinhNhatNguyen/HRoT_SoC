# sim/run_unit.do -- runs the 11 core unit testbenches one after another. Run from sim/:
#   vsim -c -do run_unit.do
# Each TB prints "SUMMARY <NAME>: PASS = x | FAIL = y" and regress.sh counts 11 lines with FAIL = 0.
if {[file exists work]} {vdel -all -lib work}
vlib work

vlog -sv ../rtl/core/*.v

# {file TB  module top}
set TBS {
    {ALU_tb           ALU_tb}
    {Branch_Unit_tb   Branch_Unit_tb}
    {Control_Unit_tb  Control_Unit_tb}
    {Extend_tb        Extend_tb}
    {Register_File_tb Register_File_tb}
    {IF_Stage_tb      IF_Stage_tb}
    {IF_ID_tb         IF_ID_Reg_tb}
    {ID_Stage_tb      ID_Stage_tb}
    {EX_Stage_tb      EX_Stage_tb}
    {MEM_Stage_tb     MEM_Stage_tb}
    {WB_Stage_tb      WB_Stage_tb}
}

foreach tb $TBS {
    lassign $tb file top
    vlog -sv ../dv/tb/$file.v
    # -onfinish stop: $finish only stops this simulation so the script can move on to the next TB
    vsim -onfinish stop work.$top
    run -all
    quit -sim
}

if {[batch_mode]} {quit -f}
