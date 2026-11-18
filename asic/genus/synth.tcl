# synth.tcl - Genus synthesis of ASIC_Top with GPDK45 on the school server (P-20).
# Flow: pre-synthesis checks, syn_generic, syn_map, syn_opt, post-synthesis checks, reports.
# Run from the repo root on the server (MobaXterm): make asic-genus
# The order of the steps follows the Lab 01 Genus flow of the school (Genus 21.10 on the server).
# Environment:
#   PERIOD=<ns>    clock period, becomes CLK_PERIOD_NS of asic/ASIC_Top.sdc (default 20)
#   CG=0|1         clock gating (default 1, CG=0 for the baseline without it)
#   MEM_BB=unresolved|stub  how the four memories become black boxes (default unresolved):
#                  unresolved leaves them out, as in the 12/11 run. Genus then does not know the pin
#                  directions, reports multiple drivers on their nets and keeps 68 assign statements.
#                  stub reads asic/yosys/mem_bb.v (empty modules with port directions). It is a
#                  trial: accept it only if the flop count stays the same and the assigns are gone
#   SRAM=0|1       1 = the two RAMs are SRAM macro wrappers (rtl/mem/RAM_Macro_*.v, P-21) instead of
#                  black boxes. The macro sram_2k_macro stays a library cell (its .lib is read), the two
#                  ROMs stay black boxes unless ROM=1. Default 0 keeps the 12/11 flow
#   ROM=0|1        1 = the two ROMs are logic (rtl/mem/ROM_Logic.v and the image generated from the firmware
#                  hex by make rom-images) instead of black boxes. The firmware is fixed in the netlist.
#                  SRAM=1 ROM=1 leaves no black box, which Innovus needs
#   SYN_OUT=<dir>  output folder (default asic/out_genus, ignored by git)
#   PDK_DIR=<dir>  Lab PDK folder (default ~/PDK_GPDK45, see config.tcl)
#
# The four 4 KB memories (2 Data_Memory, 2 Dual_Port_ROM) are black boxes: rtl/mem is not read,
# so Genus leaves the four instances unresolved. Their RTL would map to about 131,000 flip-flops,
# which says nothing about the chip. The SRAM macro wrappers of the two RAMs exist since 16/11 (SRAM=1).
# Consequences, the same as in the Yosys run: no memory area, and paths through a memory are
# not timed. The netlist must hold exactly 4 memory instances, otherwise ERROR.
#
# Scan flops are forbidden: every scan cell of gsclib045 (SDFF*, SEDFF*, SMDFF*) gets dont_use, and
# any of them in the netlist is an ERROR. The 12/11 run only banned SDFF* and Genus picked SMDFFHQX1
# (a flop with a built-in mux) for 8 flops.

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/asic/genus/config.tcl

proc env_or {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $def
}

# Run a command and only warn on error, because names differ between Genus versions
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} {
        puts "WARNING: command \"$cmd\" failed: $msg"
    }
}

set TOP      ASIC_Top
set PERIOD   [env_or PERIOD 20.0]
set CG       [env_or CG 1]
set MEM_BB   [env_or MEM_BB unresolved]
set OUT      [file normalize [env_or SYN_OUT $REPO/asic/out_genus]]
set AUDIT    $OUT/reports/audit
set RPT      $OUT/reports/synthesis
set SRAM     [env_or SRAM 0]
set ROM      [env_or ROM 0]
set N_MEM    [expr {($SRAM ? 0 : 2) + ($ROM ? 0 : 2)}]   ;# black boxes left: 2 RAMs unless SRAM=1, 2 ROMs unless ROM=1
set N_MACRO  [expr {$SRAM ? 2 : 0}]      ;# sram_2k_macro instances expected
file mkdir $OUT $AUDIT $RPT

# Library: standard cells, slow corner
set_db init_lib_search_path [list $LIB_DIR]
set LIBS [list $LIB_SLOW]
if {$SRAM} { lappend LIBS $SRAM_LIB }
read_libs $LIBS

# Scan flop ban: no scan cell may be picked, and no scan flop replaces a normal flop
foreach pat {SDFF* SEDFF* SMDFF*} {
    foreach c [get_db lib_cells -if ".base_name == $pat"] {
        set_db $c .dont_use true
    }
}
try_cmd {set_db use_scan_seqs_for_non_dft false}
foreach n $DONT_USE_CELLS {
    foreach c [get_db lib_cells -if ".base_name == $n"] {
        set_db $c .dont_use true
    }
}

# Clock gating must be enabled before elaborate, otherwise Genus ignores it
if {$CG} {
    set_db lp_insert_clock_gating true
}

# RTL: everything except rtl/mem (black boxes), plus the chip-level wrapper
set RTL {}
foreach d {core bus periph crypto top} {
    set RTL [concat $RTL [lsort [glob -directory $REPO/rtl/$d *.v]]]
}
lappend RTL $REPO/asic/ASIC_Top.v
# SoC_Top picks the macro wrappers with `ifdef SRAM_MACRO and the ROM logic with `ifdef ROM_LOGIC.
# Genus 21.10 takes them with read_hdl -define (help read_hdl on the server, 18/11)
set DEFS {}
if {$SRAM} { lappend DEFS -define SRAM_MACRO }
if {$ROM}  { lappend DEFS -define ROM_LOGIC }
if {$SRAM} {
    set RTL [concat $RTL [lsort [glob -directory $REPO/rtl/mem RAM_Macro_*.v]]]
}
if {$ROM} {
    # The image is generated from the firmware hex: make rom-images (needs fw/build/*.hex)
    set rom_images $REPO/build/rom/rom_images.v
    if {![file exists $rom_images]} {
        puts "ERROR: $rom_images not found, run make rom-images first"
        quit
    }
    lappend RTL $REPO/rtl/mem/ROM_Logic.v $rom_images
}
if {$MEM_BB eq "stub"} {
    lappend RTL $REPO/asic/yosys/mem_bb.v
    # Keep the undriven outputs of the empty modules as they are, never tie them to a constant
    try_cmd {set_db hdl_undriven_output_port_value none}
    try_cmd {set_db hdl_undriven_signal_value none}
}
read_hdl -language v2001 {*}$DEFS $RTL
elaborate $TOP

if {$CG && [catch {set_db [get_db designs] .lp_clock_gating_min_flops 4} msg]} {
    puts "WARNING: could not set lp_clock_gating_min_flops ($msg), using the Genus default"
}

# Async set and reset pins are ideal by default, so Genus would ignore set_max_fanout on the
# reset net. Turn that off so the reset tree is buffered like any other high fanout net
if {[catch {set_db [get_db designs] .ideal_seq_async_pins false} msg]} {
    puts "WARNING: could not set ideal_seq_async_pins ($msg), the reset net may stay unbuffered"
}

if {$MEM_BB eq "stub"} {
    # No optimization may cross or remove the empty memory modules
    foreach m [get_db modules -if {.name == *Data_Memory* || .name == *Dual_Port_ROM*}] {
        try_cmd {set_db $m .preserve true}
    }
}

# Pre-synthesis checks. Expected: exactly the 4 memory instances unresolved, 0 latch, 0 loop
check_design -unresolved > $AUDIT/pre_syn_unresolved.rpt
check_design -all        > $AUDIT/pre_syn_design_lint.rpt

# SDC of this run: the period line, then asic/ASIC_Top.sdc. Kept with the reports
set fp [open $OUT/${TOP}_run.sdc w]
puts $fp "set CLK_PERIOD_NS $PERIOD"
set fin [open $REPO/asic/ASIC_Top.sdc r]
puts $fp [read $fin]
close $fin
close $fp
read_sdc $OUT/${TOP}_run.sdc
check_timing_intent -verbose > $AUDIT/pre_syn_timing_intent.rpt

set_db syn_generic_effort medium
set_db syn_map_effort     medium
set_db syn_opt_effort     medium
# assign statements in the netlist break Innovus (P-21)
try_cmd {set_db remove_assigns true}

# Keep every flop so that LEC maps 1:1 with the RTL
catch {set_db optimize_merge_flops false}
catch {set_db optimize_merge_latches false}
catch {set_db optimize_constant_0_flops false}
catch {set_db optimize_constant_1_flops false}
# Keep the data mux of a flop that only ever reloads its own reset value (synchronous reset, for example
# the stop bit of the UART shift register). Genus ties such a D pin to the constant, LEC cannot prove
# the flop constant before reset and reports it non-equivalent (46 flops on 18/11)
set_db optimize_constant_feedback_seqs false
catch {set_db delete_unloaded_seqs false}

syn_generic
syn_map
syn_opt

try_cmd {remove_assigns_without_optimization}
try_cmd {set_db write_vlog_unconnected_port_style none}

# Handoff files first, so a failing report still leaves a netlist
set netlist $OUT/${TOP}_netlist.v
write_hdl > $netlist
write_sdc > $OUT/${TOP}_synth.sdc
try_cmd {write_sdf -timescale ns > $OUT/${TOP}.sdf}

try_cmd {check_design -all            > $AUDIT/post_syn_design_lint.rpt}
try_cmd {report_qor                   > $RPT/qor.rpt}
try_cmd {report_timing -lint          > $RPT/timing_lint.rpt}
try_cmd {report_timing                > $RPT/timing.rpt}
try_cmd {report_timing -max_paths 10  > $RPT/timing_paths.rpt}
try_cmd {report_area                  > $RPT/area.rpt}
try_cmd {report_gates                 > $RPT/gates.rpt}
try_cmd {report_power                 > $RPT/power.rpt}
# Max transition, fanout and cap violations. Check here that the reset tree is buffered
try_cmd {report_design_rules          > $RPT/design_rules.rpt}
if {$CG} {
    try_cmd {report_clock_gating > $RPT/clock_gating.rpt}
}

# Count cell instances in the written netlist. An instance line starts with the cell name,
# then the instance name and an opening parenthesis
set fp [open $netlist r]
set text [read $fp]
close $fp
set n_scan  [regexp -all -line {^\s*S[EM]?DFF\w*\s+\S+\s*\(} $text]
# Every flop of gsclib045: DFF*, EDFF*, MDFF* and the scan cells above
set n_flop  [regexp -all -line {^\s*[SEM]*DFF\w*\s+\S+\s*\(} $text]
# Clock gating cells of gsclib045 are TLATNTSCA* or TLATNCA*, so they are not counted as latches
set n_icg   [regexp -all -line {^\s*(TLATNTSCA|TLATNCA)\w*\s+\S+\s*\(} $text]
set n_latch [expr {[regexp -all -line {^\s*TLAT\w*\s+\S+\s*\(} $text] - $n_icg}]
set n_assign [regexp -all -line {^\s*assign\s} $text]
set n_mem   [regexp -all -line {^\s*(Data_Memory|Dual_Port_ROM)\w*\s+\S+\s*\(} $text]
set n_macro [regexp -all -line {^\s*sram_2k_macro\w*\s+\S+\s*\(} $text]
set wns ""
catch {set wns [get_db [get_db designs] .slack]}
if {$wns eq ""} {
    set wns "n/a"
}

set fp [open $OUT/reports/summary.txt w]
puts $fp "top=$TOP period_ns=$PERIOD cg=$CG mem_bb=$MEM_BB sram=$SRAM rom=$ROM macros=$n_macro memories_black_box=$n_mem assigns=$n_assign\
scan_flops=$n_scan flops=$n_flop latches=$n_latch icg=$n_icg wns_ps=$wns"
close $fp

if {$n_scan > 0} {
    puts "ERROR: $n_scan scan flops (SDFF*, SEDFF*, SMDFF*) in $netlist"
} elseif {$n_mem != $N_MEM} {
    puts "ERROR: $n_mem memory instances in $netlist, expected $N_MEM black boxes"
} elseif {$n_macro != $N_MACRO} {
    puts "ERROR: $n_macro sram_2k_macro instances in $netlist, expected $N_MACRO"
} else {
    puts "Genus done: $netlist (PERIOD=$PERIOD, CG=$CG, $n_mem memory\
black boxes, 0 scan flops, $n_flop flops, $n_latch latches, WNS $wns ps)"
}
quit
