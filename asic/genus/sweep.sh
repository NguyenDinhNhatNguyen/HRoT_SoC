#!/usr/bin/env bash
# sweep.sh - Genus period sweep of ASIC_Top on the school server (P-20), one Genus run per period.
# Run from the repo root: make asic-genus-sweep      (or: bash asic/genus/sweep.sh)
#   PERIODS   clock periods in ns (default "20 12 10 8 7 6")
#   CG0       1 adds a run without clock gating at the first period, for the power comparison (default 1)
# Each run writes to asic/out_sweep/<label>/ and logs to asic/run_sweep/<label>/ (both ignored by git).
# A table goes to asic/out_sweep/summary.md. One run takes about 10 minutes, the runs are sequential
# so only one Genus runs at a time.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root" || exit 1
periods=${PERIODS:-"20 12 10 8 7 6"}
cg0=${CG0:-1}
out=asic/out_sweep
run=asic/run_sweep

command -v genus > /dev/null || { echo "ERROR: genus not found, the sweep runs on the school server"; exit 1; }
mkdir -p "$out" "$run"

one() {     # one <label> <period> <cg>
    local label=$1
    local period=$2
    local cg=$3
    mkdir -p "$run/$label"
    rm -f "$out/$label/ASIC_Top_netlist.v"
    (cd "$run/$label" && rm -f genus.log* genus.cmd* &&
        SYN_OUT="$root/$out/$label" PERIOD="$period" CG="$cg" \
        genus -batch -files ../../genus/synth.tcl -log genus.log > /dev/null 2>&1)
    if [ -f "$out/$label/ASIC_Top_netlist.v" ]; then
        echo "$label: $(grep -hE '^(Genus done|ERROR)' "$run/$label/genus.log" | tail -n 1)"
    else
        echo "$label: ERROR, no netlist, see $run/$label/genus.log"
    fi
}

labels=""
for p in $periods; do
    one "p$p" "$p" 1
    labels="$labels p$p"
done
if [ "$cg0" = 1 ]; then
    first=${periods%% *}
    one "p${first}_cg0" "$first" 0
    labels="$labels p${first}_cg0"
fi

# Table: slack and counts from summary.txt, area from qor.rpt, total power from power.rpt.
# F_max = 1 / (period - WNS), an estimate from the worst path only
{
    echo "| Run | Period (ns) | CG | WNS (ns) | F_max (MHz) | Cell area (um2) | Flops | Scan flops | Power (W) |"
    echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
    for l in $labels; do
        s=$out/$l/reports/summary.txt
        [ -f "$s" ] || { echo "| $l | no result | | | | | | | |"; continue; }
        get() { tr ' ' '\n' < "$s" | awk -F= -v k="$1" '$1 == k {print $2}'; }
        area=$(awk '$1 == "Cell" && $2 == "Area" {print $3; exit}' "$out/$l/reports/synthesis/qor.rpt" 2>/dev/null)
        power=$(awk '$1 == "Subtotal" {print $5; exit}' "$out/$l/reports/synthesis/power.rpt" 2>/dev/null)
        awk -v l="$l" -v p="$(get period_ns)" -v cg="$(get cg)" -v w="$(get wns_ps)" -v a="${area:-n/a}" \
            -v f="$(get flops)" -v sc="$(get scan_flops)" -v pw="${power:-n/a}" 'BEGIN {
                if (w ~ /^-?[0-9.]+$/) { wns = sprintf("%.3f", w / 1000); fmax = sprintf("%.1f", 1000 / (p - w / 1000)) }
                else { wns = "n/a"; fmax = "n/a" }
                printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", l, p, cg, wns, fmax, a, f, sc, pw }'
    done
} | tee "$out/summary.md"
echo "Table written to $out/summary.md. Save the text reports with: make asic-genus-save"
