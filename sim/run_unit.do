# sim/run_unit.do -- the 11 core unit testbenches. Run from sim/:
#   vsim -c -do "set UNIT ALU_tb; do run_unit.do"   one TB per vsim process (used by regress.sh)
#   vsim -c -do run_unit.do                          all 11 TBs in one vsim process
# Each TB prints "SUMMARY <NAME>: PASS = x | FAIL = y" and regress.sh counts 11 lines with FAIL = 0.
#
# Questa 10.2c pauses the macro at the "VSIM(paused)>" prompt when $finish stops a simulation that was
# started with -onfinish stop (P-22). regress.sh therefore runs one TB per vsim process, where $finish
# ends vsim the same way it does in run_rtl.do. The all-in-one mode resumes the macro through onbreak.
onbreak {resume}

# {TB file  top module}
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

if {[file exists work]} {vdel -all -lib work}
vlib work
vlog -sv ../rtl/core/*.v

if {[info exists UNIT]} {
    set top ""
    foreach tb $TBS {
        if {[lindex $tb 0] eq $UNIT} {
            set top [lindex $tb 1]
        }
    }
    if {$top eq ""} {
        echo "run_unit.do: unknown UNIT $UNIT"
        quit -f
    }
    vlog -sv ../dv/tb/$UNIT.v
    vsim work.$top
    run -all
} else {
    foreach tb $TBS {
        lassign $tb file top
        vlog -sv ../dv/tb/$file.v
        vsim -onfinish stop work.$top
        run -all
        quit -sim
    }
}

if {[batch_mode]} {quit -f}
