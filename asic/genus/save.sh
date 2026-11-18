#!/usr/bin/env bash
# save.sh - copies the text reports of the ASIC runs into asic/reports/ for the repo.
# Run from the repo root on the server: make asic-genus-save
# Copied: summary and .rpt files of asic/out_genus, of every sweep run in asic/out_sweep, and the
# GLS summary when it exists. LEC reports are saved by make asic-lec-save. Never copied: netlists, SDF, SDC written by the tool, logs,
# and gates.rpt (it lists every library cell with its area). The server host name is replaced.
# The two check_design reports (*_design_lint.rpt) list every pin and instance they flag, up to
# 7 MB for the SRAM=1 ROM=1 netlist. Each run of list lines is cut to its first 50 lines with a note.
# Headings, every "Total number" line, the lib_cell list and the Summary table stay complete.
# The full reports stay in asic/out_genus/reports/audit on the server.
# A run with SRAM=1 or ROM=1 (fewer than 4 memory black boxes in summary.txt) goes to
# asic/reports/genus_macro, so it does not replace the reports of the black-box run in asic/reports/genus.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root" || exit 1
dst=asic/reports
n=0

# Keeps the first 50 lines of every run of list lines (inst:, hpin:, pin: ... or "Encountered an
# assign"), then one line that says how many were cut. lib_cell: lines are never cut
trim_lint() {
    awk -v keep=50 '
        function flush() {
            if (cut > 0)
                printf "... %d more lines cut by asic/genus/save.sh, the full report stays on the server\n", cut
            cut = 0
        }
        /^(inst|hinst|hpin|hport|pin|port|net|hnet):|^Encountered an assign/ {
            run++
            if (run <= keep) print
            else cut++
            next
        }
        { flush(); run = 0; print }
        END { flush() }'
}

put() {     # put <source file> <destination folder>
    [ -f "$1" ] || return 0
    case "$(basename "$1")" in gates.rpt) return 0 ;; esac
    mkdir -p "$2"
    case "$(basename "$1")" in
        *_design_lint.rpt)
            sed -E 's/^([[:space:]]*Hostname[[:space:]]+).*/\1server/' "$1" | trim_lint > "$2/$(basename "$1")" ;;
        *)
            sed -E 's/^([[:space:]]*Hostname[[:space:]]+).*/\1server/' "$1" > "$2/$(basename "$1")" ;;
    esac
    n=$((n + 1))
}

g=genus
if [ -f asic/out_genus/reports/summary.txt ] && ! grep -q 'memories_black_box=4' asic/out_genus/reports/summary.txt; then
    g=genus_macro
fi
if [ -d asic/out_genus/reports ]; then
    put asic/out_genus/reports/summary.txt "$dst/$g"
    for f in asic/out_genus/reports/audit/*.rpt; do put "$f" "$dst/$g/audit"; done
    for f in asic/out_genus/reports/synthesis/*.rpt; do put "$f" "$dst/$g/synthesis"; done
fi
# Sweep runs: the summary and the synthesis reports only, the two lint reports are 1 MB each
if [ -d asic/out_sweep ]; then
    for f in asic/out_sweep/summary*.md; do put "$f" "$dst/genus_sweep"; done
    for d in asic/out_sweep/*/; do
        l=$(basename "$d")
        put "$d/reports/summary.txt" "$dst/genus_sweep/$l"
        for r in qor timing area power clock_gating design_rules; do
            put "$d/reports/synthesis/$r.rpt" "$dst/genus_sweep/$l"
        done
    done
fi
# The GLS summary follows the netlist it ran on (its first line says how many black boxes it had)
if [ -f asic/out_gls/gls_summary.txt ] && ! grep -q '^netlist: 4 memory black boxes' asic/out_gls/gls_summary.txt; then
    put asic/out_gls/gls_summary.txt "$dst/genus_macro"
else
    put asic/out_gls/gls_summary.txt "$dst/genus"
fi

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
