#!/usr/bin/env bash
# save.sh - copies the text reports of the ASIC runs into asic/reports/ for the repo.
# Run from the repo root on the server: make asic-genus-save
# Copied: summary and .rpt files of asic/out_genus, of every sweep run in asic/out_sweep, and the
# GLS summary when it exists. LEC reports are saved by make asic-lec-save. Never copied: netlists, SDF, SDC written by the tool, logs,
# and gates.rpt (it lists every library cell with its area). The server host name is replaced.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root" || exit 1
dst=asic/reports
n=0

put() {     # put <source file> <destination folder>
    [ -f "$1" ] || return 0
    case "$(basename "$1")" in gates.rpt) return 0 ;; esac
    mkdir -p "$2"
    sed -E 's/^([[:space:]]*Hostname[[:space:]]+).*/\1server/' "$1" > "$2/$(basename "$1")"
    n=$((n + 1))
}

if [ -d asic/out_genus/reports ]; then
    put asic/out_genus/reports/summary.txt "$dst/genus"
    for f in asic/out_genus/reports/audit/*.rpt; do put "$f" "$dst/genus/audit"; done
    for f in asic/out_genus/reports/synthesis/*.rpt; do put "$f" "$dst/genus/synthesis"; done
fi
# Sweep runs: the summary and the synthesis reports only, the two lint reports are 1 MB each
if [ -d asic/out_sweep ]; then
    put asic/out_sweep/summary.md "$dst/genus_sweep"
    for d in asic/out_sweep/*/; do
        l=$(basename "$d")
        put "$d/reports/summary.txt" "$dst/genus_sweep/$l"
        for r in qor timing area power clock_gating design_rules; do
            put "$d/reports/synthesis/$r.rpt" "$dst/genus_sweep/$l"
        done
    done
fi
put asic/out_gls/gls_summary.txt "$dst/genus"

echo "Copied $n files to $dst."
# Last check before a commit: nothing with the user name, the home path or a PDK file type
pat="/home/"
user=$(id -un 2> /dev/null)
[ -n "$user" ] && pat="$pat|$user"
if grep -rlE "$pat" "$dst" 2> /dev/null | grep -q .; then
    echo "WARNING: these files still hold a user name or a home path, check before committing:"
    grep -rlE "$pat" "$dst" | head -n 5
fi
git status --short "$dst" | head -n 40
