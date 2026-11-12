#!/usr/bin/env bash
# run_yosys.sh - home synthesis of SoC_Top with Yosys and the open NanGate45 library, then OpenSTA.
# FOR TRENDS ONLY: not GPDK45, not Genus, memories are black boxes (asic/yosys/mem_bb.v).
# Run in WSL from the repo root:   bash asic/run_yosys.sh      (or: make asic-yosys)
# Needs the docker container with Yosys and OpenSTA (hpretl/iic-osic-tools) to be running.
#   YS_CONTAINER   container name (default iic-osic-tools_xvnc_uid_1000)
#   NG_LIB         NanGate45 liberty, must sit under ~/eda/designs (default: ~/eda/designs/nangate45)
#   STA_PERIOD     clock period in ns for OpenSTA (default 20)
#   YS_ABC_D       abc delay target in ps (default 2000)
# The RTL is copied to ~/eda/designs/hrot_ys (the folder the container mounts as /foss/designs).
# Text results come back to asic/out_yosys/ (ignored by git).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ctr=${YS_CONTAINER:-iic-osic-tools_xvnc_uid_1000}
share=$HOME/eda/designs
work=$share/hrot_ys
lib=${NG_LIB:-$share/nangate45/NangateOpenCellLibrary_typical.lib}
# sha256 of the copy used for the 07/11 numbers in asic/README.md
sum=8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1

case "$lib" in "$share"/*) ;; *) echo "ERROR: NG_LIB must be under $share, the container cannot see it" >&2; exit 1 ;; esac
[ -f "$lib" ] || { echo "ERROR: $lib not found, put NangateOpenCellLibrary_typical.lib there or set NG_LIB" >&2; exit 1; }
echo "$sum  $lib" | sha256sum -c --status || echo "WARNING: the sha256 of $lib differs from the copy used before, numbers may differ" >&2
docker inspect -f '{{.State.Running}}' "$ctr" 2>/dev/null | grep -q true || { echo "ERROR: container $ctr is not running" >&2; exit 1; }

# Copy the RTL without the memory modules, plus the black boxes
rm -rf "$work"
mkdir -p "$work/rtl" "$work/yosys" "$work/out"
for d in core bus periph crypto top; do cp -r "$root/rtl/$d" "$work/rtl/$d"; done
cp "$root"/asic/yosys/* "$work/yosys/"

cwork=/foss/designs/hrot_ys
clib=${lib/#$share//foss/designs}
srcs=$(cd "$work" && find rtl -name '*.v' | sort | sed "s|^|$cwork/|" | tr '\n' ' ')
srcs="$srcs$cwork/yosys/mem_bb.v"

run() { docker exec -e YS_TOP=SoC_Top -e YS_SRCS="$srcs" -e YS_OUT=$cwork/out -e YS_LIB="$clib" \
    -e YS_ABC_D="${YS_ABC_D:-2000}" -e STA_PERIOD="${STA_PERIOD:-20}" "$ctr" bash -c "export PATH=/foss/tools/bin:\$PATH; cd $cwork && $*"; }

run "yosys -q -l out/yosys.log -c yosys/synth_nangate.tcl" > /dev/null 2>&1 && [ -s "$work/out/stat.txt" ] || {
    echo "ERROR: yosys failed, last lines of $work/out/yosys.log:" >&2; tail -n 20 "$work/out/yosys.log" >&2; exit 1; }
# OpenSTA cannot parse the black box names Yosys writes for parametrized modules
# (\$paramod$<hash>\Dual_Port_ROM) nor their #(.INIT_FILE(...)) lines, so strip both for STA only
perl -0pe 's/\\\$paramod\$[0-9a-f]+\\(\w+)\s/$1 /g; s/\b(Dual_Port_ROM|Data_Memory)\s*#\(.*?\)\s*(\w+)\s*\(/$1 $2 (/gs' \
    "$work/out/SoC_Top_nangate.v" > "$work/out/SoC_Top_sta.v"
run "sta -no_splash -exit yosys/sta_nangate.tcl" > "$work/out/sta.log" 2>&1 || {
    echo "ERROR: OpenSTA failed, see $work/out/sta.log" >&2; tail -n 20 "$work/out/sta.log" >&2; exit 1; }

rm -rf "$root/asic/out_yosys"
mkdir -p "$root/asic/out_yosys"
cp "$work"/out/*.txt "$work"/out/*.log "$work"/out/SoC_Top_nangate.v "$root/asic/out_yosys/"

echo "== SoC_Top, Yosys + NanGate45 (trends only, memories are black boxes) =="
printf 'cells (incl. flip-flops and black boxes): %s\n' "$(awk '$3 == "cells" {print $1}' "$work/out/stat.txt" | tail -n 1)"
printf 'logic area (um2, black boxes excluded): %s\n' "$(awk -F"'" '/Chip area for module/ {gsub(/[^0-9.]/, "", $3); print $3}' "$work/out/stat.txt" | tail -n 1)"
printf 'flip-flops: %s\n' "$(awk '$3 ~ /^DFF/ {s+=$1} END {print s+0}' "$work/out/stat.txt")"
printf 'black boxes (memories): %s\n' "$(awk '$2 == "-" && $3 ~ /(Dual_Port_ROM|Data_Memory)$/ {s+=$1} END {print s+0}' "$work/out/stat.txt")"
cat "$work/out/sta.txt"
