#!/bin/bash
# run_lec.sh - Conformal LEC of ASIC_Top: RTL (golden) against the Genus netlist (revised) (P-20).
# Runs on the school server (needs the lec command), from anywhere inside the repo:
#   make asic-lec
# The memories are still black boxes on both sides (asic/genus/synth.tcl does not read rtl/mem),
# so this run proves everything except the memories and their wrappers. When the SRAM wrappers
# exist, set MEM_RTL to their files (golden) and read them in synth.tcl, see asic/README.md.
# Commands and options follow RV32i-SoC lec/soc_rtl2gate.do.in (Conformal_Asic 24.1, ran on this
# server in Nov 2026). NOT RUN on HRoT_SoC yet.
#
# Environment (all optional):
#   SRC_DIR=asic/out_genus      where make asic-genus wrote the netlist
#   LEC_DIR=asic/out_lec        private copy of the netlist and the results, so a new
#                               make asic-genus cannot change the netlist during the run
#   SRAM=1                      the netlist was made with make asic-genus SRAM=1: the golden side defines
#                               SRAM_MACRO and reads rtl/mem/RAM_Macro_*.v. sram_2k_macro is a black box
#                               on both sides, like the two ROMs
#   ROM=1                       the netlist was made with ROM=1: the golden side defines ROM_LOGIC and reads
#                               rtl/mem/ROM_Logic.v and build/rom/rom_images.v (make rom-images, same
#                               firmware hex as the Genus run)
#   MEM_RTL="<files>"           extra golden RTL files, empty by default
#   DRY_RUN=1                   only check the inputs and write the dofile, do not start lec
#
# The copy of the netlist and the results stay in LEC_DIR (git ignores asic/out*).

set -u
cd "$(dirname "$0")/../.." || { echo "ERROR: cannot change to the repo root"; exit 1; }

SRC_DIR=${SRC_DIR:-asic/out_genus}
LEC_DIR=${LEC_DIR:-asic/out_lec}
MEM_RTL=${MEM_RTL:-}
SRAM=${SRAM:-0}
ROM=${ROM:-0}
DRY_RUN=${DRY_RUN:-0}
NETLIST_SRC=$SRC_DIR/ASIC_Top_netlist.v
LIB_V=${PDK_DIR:-$HOME/PDK_GPDK45}/lib/slow_vdd1v0_basiccells.v
DO=$LEC_DIR/asic_rtl2gate.do

die() { echo "ERROR: $*"; exit 1; }

[ -f "$NETLIST_SRC" ] || die "$NETLIST_SRC not found, run make asic-genus first (or set SRC_DIR)"
[ -f "$LIB_V" ] || die "$LIB_V not found, set PDK_DIR"
if [ "$DRY_RUN" != 1 ]; then
    command -v lec > /dev/null || die "lec (Conformal) not found, this runs on the school server"
fi

# Golden file list: the same set as asic/genus/synth.tcl (core bus periph crypto top, ASIC_Top.v)
files=""
for d in core bus periph crypto top; do
    for f in $(ls rtl/$d/*.v 2> /dev/null | sort); do files="$files $f"; done
done
files="$files asic/ASIC_Top.v $MEM_RTL"
if [ "$SRAM" = 1 ] || [ "$ROM" = 1 ]; then
    # A first file that holds the defines keeps them for the files after it, like in synth.tcl
    mkdir -p "$LEC_DIR"
    : > "$LEC_DIR/mem_define.v"
    [ "$SRAM" = 1 ] && echo '`define SRAM_MACRO' >> "$LEC_DIR/mem_define.v"
    [ "$ROM" = 1 ] && echo '`define ROM_LOGIC' >> "$LEC_DIR/mem_define.v"
    files="$LEC_DIR/mem_define.v $files"
fi
[ "$SRAM" = 1 ] && files="$files $(ls rtl/mem/RAM_Macro_*.v | sort | tr '\n' ' ')"
[ "$ROM" = 1 ] && files="$files rtl/mem/ROM_Logic.v build/rom/rom_images.v"
for f in $files; do [ -f "$f" ] || die "RTL file $f not found"; done

# RTL files newer than the netlist were changed after synthesis (for example by git pull)
newer=$(find rtl asic/ASIC_Top.v \( -name '*.v' -o -name '*.vh' \) -newer "$NETLIST_SRC" | sort)
if [ -n "$newer" ]; then
    echo "WARNING: these RTL files are newer than the netlist, run make asic-genus again:"
    echo "$newer" | sed 's/^/           /'
fi

mkdir -p "$LEC_DIR/reports"
cp "$NETLIST_SRC" "$LEC_DIR/ASIC_Top_netlist.v"
cp "$SRC_DIR/reports/summary.txt" "$LEC_DIR/synth_summary.txt" 2> /dev/null || true

{
    echo "// Written by asic/lec/run_lec.sh, do not edit. One run, one file."
    echo "// Skip any failing command (for example a missing license) and keep going"
    echo "set dofile abort off"
    echo "read library -both $LIB_V"
    echo "// Memories (and SRAM macros) are black boxes on both sides. This is declared BEFORE"
    echo "// read design (RV32i-SoC, 13/11). It hides ANY undefined module, so the black box"
    echo "// report below must list the memory instances and nothing else"
    echo "set undefined cell black_box -noascend -both"
    echo "read design -golden -verilog $files"
    echo "read design -revised -verilog $LEC_DIR/ASIC_Top_netlist.v"
    echo "set root module ASIC_Top -both"
    echo "report black box -both"
    echo "set flatten model -seq_constant"
    echo "set flatten model -seq_constant_x_to 0"
    echo "set flatten model -nodff_to_dlat_zero"
    echo "set flatten model -nodff_to_dlat_feedback"
    echo "set flatten model -hier_seq_merge"
    echo "// The netlist has clock gating cells (latch + AND): model them as flop enables"
    echo "set flatten model -gated_clock"
    echo "set system mode lec"
    echo "// analyze datapath needs Conformal_Ultra, which the school does not have"
    echo "set compare effort high"
    echo "add compared points -all"
    echo "compare"
    echo "report compare data -class nonequivalent -verbose > $LEC_DIR/reports/lec_noneq.rpt"
    echo "report compare data -class abort > $LEC_DIR/reports/lec_abort.rpt"
    echo "report verification > $LEC_DIR/reports/lec_verification.rpt"
    echo "report unmapped points > $LEC_DIR/reports/lec_unmapped.rpt"
    echo "report verification"
    echo "exit -force"
} > "$DO"
echo "== Dofile written: $DO ($(echo $files | wc -w) golden RTL files)"
[ "$DRY_RUN" = 1 ] && { echo "DRY_RUN=1: lec not started"; exit 0; }

# < /dev/null so lec exits if the dofile stops midway
echo "== Starting lec at $(date '+%H:%M:%S'), log: $LEC_DIR/lec.txt"
start=$(date +%s)
lec -nogui -dofile "$DO" < /dev/null > "$LEC_DIR/lec.txt" 2>&1 || true
echo "== lec finished after $(( ($(date +%s) - start) / 60 )) min"
echo "== Result lines (pass needs 0 non-equivalent, 0 abort)"
grep -E 'Compare Results|Non-equivalent|Equivalent|Abort|Unmapped|// Error' "$LEC_DIR/lec.txt" | tail -20
echo "== Black boxes"
grep -n -i 'black box' "$LEC_DIR/lec.txt" | head -12
echo "Done. Copy only the text reports in $LEC_DIR/reports with make asic-lec-save."
