# sta.tcl - Tempus STA of ASIC_Top, before layout (Genus netlist) or after route (SPEF) (P-21).
# Run from the repo root on the school server: make asic-sta (after make asic-genus).
# Adapted from RV32i-SoC sta/scripts/sta_soc.tcl (Tempus 23.14, ran in Nov 2026).
# NOT RUN on HRoT_SoC yet. Every report goes through try_cmd, so one wrong command only warns
# and the other reports are still written.
#
# Environment (all optional, paths absolute because Tempus runs in asic/run_sta):
#   NETLIST=<file>   default asic/out_genus/ASIC_Top_netlist.v (Genus)
#   SDC=<file>       default asic/out_genus/ASIC_Top_synth.sdc
#   SPEF=<file>      empty before layout. With a SPEF the clock is propagated (after CTS)
#   STA_OUT=<dir>    default asic/out_sta/pre, or asic/out_sta/spef when SPEF is set
#
# Corners come from asic/pnr/mmmc.view like in Innovus: slow library for setup and recovery,
# fast library for hold and removal. Before layout there is no SPEF, so wire delay is not
# counted and the numbers are optimistic. Genus checks setup only, so hold, recovery and
# removal of the reset tree are first checked here.

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/asic/pnr/config.tcl

proc env_or {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}

set TOP        ASIC_Top
set NETLIST    [file normalize [env_or NETLIST $REPO/asic/out_genus/${TOP}_netlist.v]]
set DESIGN_SDC [file normalize [env_or SDC     $REPO/asic/out_genus/${TOP}_synth.sdc]]
set SPEF       [env_or SPEF ""]
set STAGE      [expr {$SPEF eq "" ? "pre" : "spef"}]
set OUT        [file normalize [env_or STA_OUT $REPO/asic/out_sta/$STAGE]]
file mkdir $OUT

foreach f [list $NETLIST $DESIGN_SDC $SRAM_LIB_SLOW] {
    if {![file exists $f]} {
        puts "ERROR: $f not found (run make asic-genus first, SRAM_LIB_SLOW is set in config.tcl)"
        exit
    }
}

read_view_definition $REPO/asic/pnr/mmmc.view
read_verilog $NETLIST
set_top_module $TOP

if {$SPEF ne ""} {
    if {![file exists $SPEF]} {
        puts "ERROR: SPEF $SPEF not found"
        exit
    }
    read_spef -rc_corner rc_typ $SPEF
    set_interactive_constraint_modes [all_constraint_modes -active]
    set_propagated_clock [all_clocks]
}

update_timing -full

# One report per check type. Tempus 23.1 rejects -check_type together with -late or -early
# (TCLCMD-393 in RV32i-SoC), and -late alone mixes recovery paths into the setup report
try_cmd {check_timing -verbose                            > $OUT/check_timing.rpt}
try_cmd {report_analysis_coverage                         > $OUT/coverage.rpt}
try_cmd {report_timing -check_type setup    -max_paths 10 > $OUT/setup.rpt}
try_cmd {report_timing -check_type hold     -max_paths 10 > $OUT/hold.rpt}
try_cmd {report_timing -check_type recovery -max_paths 10 > $OUT/recovery.rpt}
try_cmd {report_timing -check_type removal  -max_paths 10 > $OUT/removal.rpt}
try_cmd {report_constraint -all_violators                 > $OUT/violators.rpt}
try_cmd {report_analysis_summary                          > $OUT/analysis_summary.rpt}

# Worst slack of each check (ns), n/a when the command is not available
proc worst_slack {args} {
    set s "n/a"
    catch {
        set p [report_timing {*}$args -max_paths 1 -collection]
        set s [get_property $p slack]
    }
    return $s
}
set fp [open $OUT/summary.txt w]
puts $fp "top=$TOP stage=$STAGE setup_ns=[worst_slack -check_type setup]\
hold_ns=[worst_slack -check_type hold] recovery_ns=[worst_slack -check_type recovery]\
removal_ns=[worst_slack -check_type removal]"
close $fp
puts "Tempus done: $OUT, see summary.txt"
exit
