#!/usr/bin/env bash
# save_reports.sh - copies the text reports of an ASIC flow run into asic/reports/ for the repo.
# Usage (on the server, from the repo root):
#   bash asic/save_reports.sh asic/out_innovus/reports asic/reports/innovus
# Used by make asic-pnr-save, asic-lec-save and asic-sta-save.
# Only report files are copied (.rpt .txt .summary and their .gz). Netlists, SPEF, SDF, GDS, LEF,
# .lib and databases are skipped, because they are built from the school PDK and the repo is public.
# Adapted from RV32i-SoC scripts/save_reports.sh.

set -u
SRC=${1:?usage: save_reports.sh <reports folder> <asic/reports/... folder>}
DST=${2:?usage: save_reports.sh <reports folder> <asic/reports/... folder>}
[ -d "$SRC" ] || { echo "ERROR: $SRC not found, run the flow first"; exit 1; }
case "$DST" in
    asic/reports/*) ;;
    *) echo "ERROR: the destination must be inside asic/reports/"; exit 1 ;;
esac

n_copy=0
n_skip=0
while IFS= read -r -d '' f; do
    rel=${f#"$SRC"/}
    case "$f" in
        *.rpt|*.rpt.gz|*.txt|*.summary|*.summary.gz|*.tarpt|*.tarpt.gz)
            mkdir -p "$DST/$(dirname "$rel")"
            cp "$f" "$DST/$rel"
            n_copy=$((n_copy + 1)) ;;
        *)
            echo "Skipped: $rel"
            n_skip=$((n_skip + 1)) ;;
    esac
done < <(find "$SRC" -type f -print0)

echo "Copied $n_copy files to $DST, skipped $n_skip."
echo "Check before committing: git status --short $DST (no git add -f)"
