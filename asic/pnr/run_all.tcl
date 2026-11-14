# run_all.tcl - Innovus flow of ASIC_Top: init, floorplan, placement, CTS, route, checks, files (P-21).
# Run from the repo root on the school server with: make asic-innovus (after make asic-genus).
# Adapted from RV32i-SoC pnr/scripts/run_all.tcl (Innovus 21.19, GPDK45, ran in Nov 2026).
# NOT RUN on HRoT_SoC yet: it needs the SRAM wrappers first, because Innovus rejects the black
# box memories and the assign statements they leave in the netlist.
# Each step saves DBS/<step>.enc in the run folder, for restoreDesign when debugging.
#
# Environment: CORE_W, CORE_H (see floorplan.tcl), UTIL is set in floorplan.tcl.

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/asic/pnr/config.tcl

set TOP        ASIC_Top
set NETLIST    $REPO/asic/out_genus/${TOP}_netlist.v
set DESIGN_SDC $REPO/asic/out_genus/${TOP}_synth.sdc
set OUT        $REPO/asic/out_innovus
set RPT        $OUT/reports
set SKEW       0.080    ;# Target clock skew (ns), Lab 05 value
file mkdir $OUT $RPT DBS

# Report and check commands only warn on error, because options differ between Innovus versions.
# The main steps (init, floorplan, place, CTS, route, file output) still stop on error.
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}
# Mode options: try the Innovus 21.1 name first, then the Lab name
proc try_mode {new old} {
    if {[catch {uplevel 1 $new}]} { try_cmd $old }
}

foreach f [list $NETLIST $DESIGN_SDC] {
    if {![file exists $f]} { puts "ERROR: $f not found, run make asic-genus first" ; exit 1 }
}

# Init
set init_gnd_net    $GND_NET
set init_pwr_net    $PWR_NET
set init_verilog    $NETLIST
set init_top_cell   $TOP
set init_lef_file   [list $TECH_LEF $CELL_LEF $SRAM_LEF]
set init_mmmc_file  $REPO/asic/pnr/mmmc.view
init_design

globalNetConnect $PWR_NET -type pgpin -pin VDD -inst *
globalNetConnect $GND_NET -type pgpin -pin VSS -inst *
globalNetConnect $PWR_NET -type tiehi -inst *
globalNetConnect $GND_NET -type tielo -inst *

# Banned cells, before any optimization. Banning CLKBUFX2 only before CTS let place_opt_design
# insert 1220 of them as data buffers in RV32i-SoC (29/10)
foreach c $DONT_USE_CELLS { try_cmd {setDontUse $c true} }

# Floorplan, macros, pins, power plan
source $REPO/asic/pnr/floorplan.tcl
try_cmd {verifyGeometry -report $RPT/pdn_geometry.rpt}       ;# 0 violations
saveDesign DBS/floorplan.enc

# Placement
try_cmd  {setPlaceMode -fp false}
try_mode {setPlaceMode -place_global_cong_effort high}           {setPlaceMode -congestionEffort high}
try_mode {setPlaceMode -place_global_timing_effort medium}       {setPlaceMode -timingDriven true}
try_mode {setPlaceMode -place_detail_wire_length_opt_effort medium} {setPlaceMode -wireLenOptEffort medium}
place_opt_design
try_cmd {checkPlace $RPT/placement_check.rpt}                    ;# 0 unplaced, overlap, off-grid
try_cmd {reportCongestion -overflow > $RPT/placement_congestion.rpt}   ;# overflow < 0.5 %
try_cmd {timeDesign -preCTS -expandedViews -outDir $RPT/prects}
saveDesign DBS/placement.enc

# CTS
try_cmd {set_ccopt_property buffer_cells     $CTS_BUFFERS}
try_cmd {set_ccopt_property inverter_cells   $CTS_INVERTERS}
try_cmd {set_ccopt_property target_skew      $SKEW}
try_cmd {set_ccopt_property target_max_trans 0.150}
try_cmd {setAnalysisMode -analysisType onChipVariation -cppr both}
# Clock wires at double width and double spacing. Innovus 21.1 uses add_ndr and a CCOpt route type
try_mode {add_ndr -name CLK_2W2S -width_multiplier {Metal3:Metal7 2} -spacing_multiplier {Metal3:Metal7 2}} \
         {addNDR -name CLK_2W2S -width_multiplier {Metal3:Metal7 2} -spacing_multiplier {Metal3:Metal7 2}}
try_cmd {create_route_type -name clk_trunk -non_default_rule CLK_2W2S -bottom_preferred_layer Metal3 -top_preferred_layer Metal7}
try_cmd {set_ccopt_property route_type clk_trunk -net_type trunk}

create_ccopt_clock_tree_spec -file $OUT/ccopt.spec
source $OUT/ccopt.spec
ccopt_design
try_cmd {report_ccopt_clock_trees -file $RPT/cts_clock_trees.rpt}   ;# skew <= 80 ps, latency < 0.8 ns
try_cmd {report_ccopt_skew_groups -file $RPT/cts_skew_groups.rpt}
optDesign -postCTS
# Fix hold with a 20 ps margin instead of 0. Removal on the reset tree had only 6 ps left before
# layout in RV32i-SoC, and the reset of ASIC_Top is timed the same way (recovery and removal)
try_cmd {setOptMode -holdTargetSlack 0.020}
optDesign -postCTS -hold
try_cmd {timeDesign -postCTS       -outDir $RPT/postcts_setup}
try_cmd {timeDesign -postCTS -hold -outDir $RPT/postcts_hold}

# timeDesign does not list recovery and removal on their own. Hold and removal only report in
# hold analysis mode (TCLCMD-1045 in setup mode, RV32i-SoC 12/11)
proc worst_slack {type} {
    set s "n/a"
    set hold [expr {$type eq "hold" || $type eq "removal"}]
    if {$hold} { catch {setAnalysisMode -checkType hold} }
    catch {
        set p [report_timing -check_type $type -max_paths 1 -collection]
        set s [get_property $p slack]
    }
    if {$hold} { catch {setAnalysisMode -checkType setup} }
    return $s
}
proc slack_reports {rpt stage} {
    file mkdir $rpt/$stage
    catch {report_timing -check_type recovery -max_paths 10 > $rpt/$stage/recovery.rpt}
    catch {setAnalysisMode -checkType hold}
    catch {report_timing -check_type removal -max_paths 10 > $rpt/$stage/removal.rpt}
    catch {setAnalysisMode -checkType setup}
    set line "stage=$stage"
    foreach t {setup hold recovery removal} { append line " ${t}_ns=[worst_slack $t]" }
    set fp [open $rpt/slack_summary.txt a]
    puts $fp $line
    close $fp
    puts "PD: $line"
    if {[string first "n/a" $line] >= 0} { puts "WARNING: $stage has a slack that is n/a" }
}
file delete -force $RPT/slack_summary.txt
try_cmd {slack_reports $RPT postcts_async}
saveDesign DBS/cts.enc

# Route
try_mode {setNanoRouteMode -route_with_timing_driven true -route_with_si_driven true} {setNanoRouteMode -routeWithTimingDriven true -routeWithSiDriven true}
routeDesign
try_cmd {setDelayCalMode -SIAware true}
optDesign -postRoute -setup -hold

# Quick checks written to reports/pd_checks.rpt: banned cells must be 0, and the standard cell
# density outside the macros shows whether the core size is right
proc pd_checks {file banned} {
    set fp [open $file w]
    puts $fp "Core box (um): [dbGet top.fPlan.coreBox]"
    puts $fp "Die box (um) : [dbGet top.fPlan.box]"
    foreach c $banned {
        puts $fp "$c instances: [llength [dbGet -e top.insts.cell.name $c]] (must be 0)"
    }
    set mac_area 0.0
    set std_area 0.0
    foreach inst [dbGet top.insts] {
        set a [expr {[dbGet $inst.box_sizex] * [dbGet $inst.box_sizey]}]
        if {[dbGet $inst.cell.baseClass] eq "block"} {
            set mac_area [expr {$mac_area + $a}]
            puts $fp "Macro [dbGet $inst.name] at [dbGet $inst.pt] [dbGet $inst.orient]"
        } else {
            set std_area [expr {$std_area + $a}]
        }
    }
    lassign [lindex [dbGet top.fPlan.coreBox] 0] cx0 cy0 cx1 cy1
    set core_area [expr {($cx1 - $cx0) * ($cy1 - $cy0)}]
    puts $fp [format "Standard cell area %.0f um2, macro area %.0f um2, core %.0f um2" \
                  $std_area $mac_area $core_area]
    puts $fp [format "Standard cell density outside macros: %.1f%%" \
                  [expr {100.0 * $std_area / ($core_area - $mac_area)}]]
    close $fp
}
try_cmd {pd_checks $RPT/pd_checks.rpt $DONT_USE_CELLS}

# ecoRoute -fix_drc without an area missed the errors in RV32i-SoC (13/11). Give it one box per
# error: the Bounds line of drc.rpt plus 1.5 um. Returns the number of boxes
proc fix_drc_boxes {rpt_in rpt_out} {
    set fp [open $rpt_in r]
    set txt [read $fp]
    close $fp
    set re {Bounds : \( *([0-9.]+), *([0-9.]+) *\) \( *([0-9.]+), *([0-9.]+) *\)}
    set n 0
    foreach {all x0 y0 x1 y1} [regexp -all -inline $re $txt] {
        if {$n >= 20} {
            puts "WARNING: more than 20 DRC errors, the rest is left as it is"
            break
        }
        incr n
        set box [list [expr {$x0 - 1.5}] [expr {$y0 - 1.5}] [expr {$x1 + 1.5}] [expr {$y1 + 1.5}]]
        try_cmd [list ecoRoute -fix_drc $box]
    }
    if {$n > 0} { try_cmd [list verify_drc -report $rpt_out] }
    return $n
}

try_cmd {addFiller -cell [dbGet [dbGet -p head.libCells.name FILL*].name] -prefix FILLER}
saveDesign DBS/route.enc

# Check and report
try_cmd {verify_drc -report $RPT/drc.rpt}
if {[catch {fix_drc_boxes $RPT/drc.rpt $RPT/drc_after_eco.rpt} nfix]} {
    puts "WARNING: fix_drc_boxes failed: $nfix"
} elseif {$nfix > 0} {
    puts "PD: ecoRoute on $nfix DRC box(es), see drc_after_eco.rpt"
    saveDesign DBS/route_drcfix.enc
}
try_cmd {verifyConnectivity -report $RPT/connectivity.rpt}
if {[catch {verifyProcessAntenna -reportfile $RPT/antenna.rpt}]} { try_cmd {verifyProcessAntenna -report $RPT/antenna.rpt} }
try_cmd {timeDesign -postRoute       -outDir $RPT/postroute_setup}
try_cmd {timeDesign -postRoute -hold -outDir $RPT/postroute_hold}
try_cmd {slack_reports $RPT postroute_async}
try_cmd {reportGateCount -outfile $RPT/area.rpt}
try_cmd {report_power -outfile $RPT/power.rpt}
try_cmd {summaryReport -outdir $RPT/summary}

# Output files for Tempus (SPEF), LEC and GLS (netlist, SDF). They stay in asic/out_innovus,
# which git ignores
saveNetlist $OUT/${TOP}_pnr.v
saveNetlist $OUT/${TOP}_pnr_pg.v -includePowerGround
extractRC
try_cmd {rcOut -spef $OUT/${TOP}.spef -rc_corner rc_typ}
try_cmd {write_sdf -view av_setup $OUT/${TOP}.sdf}
if {$GDS_MAP ne ""} {
    # No cell GDS on the server, so the GDS holds only what Innovus drew. Macro areas stay empty
    try_cmd {streamOut $OUT/${TOP}.gds -mapFile $GDS_MAP -units 2000 -mode ALL}
} else {
    puts "WARNING: GDS_MAP is empty or missing in config.tcl, no GDS was written"
}

puts "Innovus done. Copy only the text reports in $RPT with make asic-pnr-save,\
never the netlist, SPEF, SDF or GDS in $OUT."
exit
