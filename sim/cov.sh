#!/bin/bash
# Coverage run (P-19). Run in WSL from the repo root: bash sim/cov.sh (or make cov)
# Runs the core, SHA-256 and APB tests on QuestaSim with code coverage on their RTL and the covergroups
# compiled in (+define+HROT_COV), merges the databases and writes the reports to build/cov/:
#   merged.ucdb    all runs merged (open with vsim -viewcov or vcover)
#   cvg.txt        every covergroup, coverpoint and bin
#   code.txt       statement, branch, condition and FSM coverage per design unit
#   summary.txt    the table printed at the end
#   html/          the same in HTML (open html/index.html)
# Exit code 0 when every run passed and the targets of docs/verification/SHA256_UVM_TestPlan.md section 6
# are met: functional coverage 100%, SHA256_Wrapper statements and branches >= 95%, SHA256_Core >= 90%.
# make test is not changed by this script. QUESTA=<path to vsim.exe> as in sim/regress.sh.
cd "$(dirname "$0")/.." || exit 2
QUESTA="${QUESTA:-/mnt/c/questasim64_10.2c/win64/vsim.exe}"
VCOVER="$(dirname "$QUESTA")/vcover.exe"
OUT=build/cov
rm -rf "$OUT"
mkdir -p "$OUT"
fail=0

run() {     # run <name> <pass marker> <do script> <Tcl settings>
    local name=$1 marker=$2 script=$3 sets=$4
    (cd sim && "$QUESTA" -c -do "$sets; set COV ../$OUT/$name.ucdb; do $script" < /dev/null) > "$OUT/$name.log" 2>&1
    if grep -q "$marker" "$OUT/$name.log" && ! grep -qE "\*\* (Error|Fatal)" "$OUT/$name.log" && [ -f "$OUT/$name.ucdb" ]; then
        printf "  %-28s PASS\n" "$name"
    else
        printf "  %-28s FAIL  (see %s)\n" "$name" "$OUT/$name.log"; fail=1
    fi
}

echo "== HRoT_SoC coverage run (QuestaSim) =="
# Core: the two self-checking programs (with and without bus_stall), the directed TB and the hazard TB
run core_prog      "SUMMARY: PASS"   run_rtl.do "set TB RISCV_Core_prog_tb"
run core_tb        "OVERALL: PASS"   run_rtl.do "set TB RISCV_Core_tb"
run core_hazard    "RESULT: PASS"    run_rtl.do "set TB RISCV_Core_hazard_tb"
# SHA-256: full test on three seeds, random messages with a reset before the first START (IDLE) and then
# every 15-30 us, offsets >= 0x100
run sha_full_s1    "TEST PASSED"     run_uvm.do "set DUT sha256; set TEST sha256_full_test; set SEED 1"
run sha_full_s2    "TEST PASSED"     run_uvm.do "set DUT sha256; set TEST sha256_full_test; set SEED 2"
run sha_full_s3    "TEST PASSED"     run_uvm.do "set DUT sha256; set TEST sha256_full_test; set SEED 3"
run sha_reset      "TEST PASSED"     run_uvm.do "set DUT sha256; set TEST sha256_rand_test; set SEED 4; set PLUSARGS {+NUM_MSGS=160 +MAX_LEN=200 +RESET_AT_NS=200 +RESET_EVERY_NS=15000}"
run sha_alias      "TEST PASSED"     run_uvm.do "set DUT sha256; set TEST sha256_alias_test"
# APB: full test on three seeds with up to 6 wait states, register test with a reset in the middle
run apb_full_s1    "TEST PASSED"     run_uvm.do "set DUT apb; set TEST apb_full_test; set SEED 1; set PLUSARGS {+APB_MAX_WAIT=6}"
run apb_full_s2    "TEST PASSED"     run_uvm.do "set DUT apb; set TEST apb_full_test; set SEED 2; set PLUSARGS {+APB_MAX_WAIT=6}"
run apb_full_s3    "TEST PASSED"     run_uvm.do "set DUT apb; set TEST apb_full_test; set SEED 3; set PLUSARGS {+APB_MAX_WAIT=6}"
run apb_reg_reset  "TEST PASSED"     run_uvm.do "set DUT apb; set TEST apb_reg_test; set PLUSARGS {+NUM_TRANS=2000 +RESET_AT_NS=20000}"

# Merge and report
ucdbs=$(cd "$OUT" && ls ./*.ucdb | grep -v merged)
(cd "$OUT" && "$VCOVER" merge merged.ucdb $ucdbs) > "$OUT/merge.log" 2>&1
(cd "$OUT" && "$VCOVER" report -cvg -details merged.ucdb) > "$OUT/cvg.txt" 2>&1
(cd "$OUT" && "$VCOVER" report -code bcesf -byDU merged.ucdb) > "$OUT/code.txt" 2>&1
(cd "$OUT" && "$VCOVER" report -html -htmldir html -code bcesf -cvg merged.ucdb) > "$OUT/html.log" 2>&1
python3 sim/cov_summary.py "$OUT/cvg.txt" "$OUT/code.txt" > "$OUT/summary.txt" || fail=1
cat "$OUT/summary.txt"

if [ $fail = 0 ]; then
    echo "== Coverage: all runs PASS, targets met =="
else
    echo "== Coverage: a run failed or a target is not met =="
fi
exit $fail
