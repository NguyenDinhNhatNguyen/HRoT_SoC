#!/usr/bin/env bash
# macro_info.sh - prints the facts of the school SRAM macro needed for the area and timing budget
# (P-20, P-21). Run on the school server: make asic-macro-info
#   bash asic/macro_info.sh [macro name] [PDK folder]     (default sram_2k_macro, ~/PDK_GPDK45)
# It only reads the LEF and the .lib and copies nothing. The short summary (size, pins, area) goes
# to asic/reports/sram_macro_info.txt, timing values are printed on screen only.
set -u

macro=${1:-sram_2k_macro}
pdk=${2:-${PDK_DIR:-$HOME/PDK_GPDK45}}
lef=$pdk/lef/$macro.lef
lib=$pdk/lib/$macro.lib
out="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/reports/sram_macro_info.txt"
mkdir -p "$(dirname "$out")"

for f in "$lef" "$lib"; do
    [ -f "$f" ] || echo "WARNING: cannot find $f"
done

{
    echo "Macro $macro, read $(date '+%Y-%m-%d')"
    echo
    echo "LEF size and class:"
    awk -v m="$macro" '{sub(/\r$/, "")}
        $1 == "MACRO" && $2 == m {in_m = 1}
        in_m && $1 == "END" && $2 == m {in_m = 0}
        in_m && ($1 == "CLASS" || $1 == "SIZE" || $1 == "SYMMETRY") {print "  " $0}' "$lef" 2>/dev/null
    echo
    echo "LEF pins (bus bits counted), direction and metal layers:"
    awk -v m="$macro" '{sub(/\r$/, "")}
        $1 == "MACRO" && $2 == m {in_m = 1}
        in_m && $1 == "END" && $2 == m {in_m = 0}
        !in_m {next}
        $1 == "PIN" {pin = $2; base = pin; sub(/\[.*/, "", base); if (!(base in seen)) {order[++n] = base; seen[base] = 1}; cnt[base]++; in_p = 1; next}
        in_p && $1 == "DIRECTION" {dir[base] = $2}
        in_p && $1 == "LAYER" {if (index(" " lay[base] " ", " " $2 " ") == 0) lay[base] = lay[base] " " $2}
        in_p && $1 == "END" && $2 == pin {in_p = 0}
        END {for (i = 1; i <= n; i++) {b = order[i]; printf "  %s[%d] %s%s\n", b, cnt[b], dir[b], lay[b]}}' "$lef" 2>/dev/null
    echo
    echo ".lib area and corner:"
    grep -m1 -E '^\s*area\s*:' "$lib" 2>/dev/null | sed 's/^\s*/  /'
    grep -m3 -E 'nom_(voltage|temperature|process)' "$lib" 2>/dev/null | sed 's/^\s*/  /'
} | tee "$out"

echo
echo "Timing arcs of the .lib (screen only, not written to the repo):"
grep -E 'timing_type|related_pin' "$lib" 2>/dev/null | sed -E 's/^\s+//' | sort | uniq -c | sort -rn | head -n 12
echo
echo "Summary written to $out"
