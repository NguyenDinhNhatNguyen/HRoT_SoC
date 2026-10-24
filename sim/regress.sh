#!/bin/bash
# Full regression. Run in WSL from the repo root: bash sim/regress.sh (or make test)
# RTL runs on QuestaSim (Windows, via WSL interop) and the VP builds and runs with SystemC inside WSL.
# Logs land in build/logs/. Exit code 0 means everything passed.
cd "$(dirname "$0")/.." || exit 2
QUESTA="${QUESTA:-/mnt/c/questasim64_10.2c/win64/vsim.exe}"
LOG=build/logs
mkdir -p "$LOG"
fail=0

check() {   # check <name> <log> <pass marker>
    if grep -q "$3" "$2" && ! grep -qE "\*\* (Error|Fatal)" "$2"; then
        printf "  %-30s PASS\n" "$1"
    else
        printf "  %-30s FAIL  (see %s)\n" "$1" "$2"; fail=1
    fi
}

echo "== HRoT_SoC regression (QuestaSim + SystemC) =="
(cd sim && "$QUESTA" -c -do run_unit.do)                                > $LOG/unit.log 2>&1
n_ok=$(grep -cE "SUMMARY [A-Z_]+: PASS = [0-9]+ \| FAIL = 0" $LOG/unit.log)
if [ "$n_ok" = 11 ] && ! grep -qE "\*\* (Error|Fatal)" $LOG/unit.log; then
    printf "  %-30s PASS\n" "Core: 11 unit testbenches"
else
    printf "  %-30s FAIL  (%s of 11 passed, see %s)\n" "Core: 11 unit testbenches" "$n_ok" $LOG/unit.log; fail=1
fi
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_prog_tb; do run_rtl.do") > $LOG/core_prog.log 2>&1
check "Core: ISA program"           $LOG/core_prog.log "SUMMARY: PASS"
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_tb; do run_rtl.do")      > $LOG/core_tb.log 2>&1
check "Core: RISCV_Core_tb"         $LOG/core_tb.log   "OVERALL: PASS"
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_hazard_tb; do run_rtl.do") > $LOG/core_haz.log 2>&1
check "Core: hazards without NOPs"  $LOG/core_haz.log  "RESULT: PASS"
(cd sim && "$QUESTA" -c -do "set TEST axi4_lite_full_test; set SEED 1; set PLUSARGS {+NUM_TRANS=300}; do run_uvm.do") > $LOG/uvm_full.log 2>&1
check "UVM: AXI4-Lite full"         $LOG/uvm_full.log  "TEST PASSED"
(cd sim && "$QUESTA" -c -do "set TEST axi4_lite_rand_test; set SEED 7; set PLUSARGS {+NUM_TRANS=300 +RESET_AT_NS=20000}; do run_uvm.do") > $LOG/uvm_reset.log 2>&1
check "UVM: reset mid-transaction"  $LOG/uvm_reset.log "TEST PASSED"
(cd sim && "$QUESTA" -c -do "set DUT sha256; set TEST sha256_full_test; set SEED 1; do run_uvm.do") > $LOG/uvm_sha.log 2>&1
check "UVM: SHA-256"                $LOG/uvm_sha.log   "TEST PASSED"
(cd sim && "$QUESTA" -c -do "set DUT sha256; set TEST sha256_rand_test; set SEED 3; set PLUSARGS {+NUM_MSGS=20 +RESET_AT_NS=30000}; do run_uvm.do") > $LOG/uvm_sha_reset.log 2>&1
check "UVM: SHA-256 with reset"     $LOG/uvm_sha_reset.log "TEST PASSED"
if command -v gcc > /dev/null; then
    make -s -C fw/hal/test clean test                                   > $LOG/hal.log 2>&1
    check "HAL: SHA-256 on host"    $LOG/hal.log       "==== PASSED"
else
    printf "  %-30s SKIP  (no gcc in WSL)\n" "HAL: SHA-256 on host"
fi
(cd sim && "$QUESTA" -c -do run_ip.do)                                  > $LOG/ip.log 2>&1
check "APB peripherals"             $LOG/ip.log        "RESULT: PASS"
python3 dv/sw/mkhex.py sim > /dev/null
(cd sim && "$QUESTA" -c -do run_soc.do)                                 > $LOG/soc.log 2>&1
check "SoC: secure boot"            $LOG/soc.log       "RESULT: PASS"
(cd sim && bash run_vp.sh)                                              > $LOG/vp.log 2>&1
[ "$(grep -c 'VP RESULT: PASS' $LOG/vp.log)" = 2 ] && printf "  %-30s PASS\n" "VP: good and tampered image" \
    || { printf "  %-30s FAIL  (see %s)\n" "VP: good and tampered image" $LOG/vp.log; fail=1; }

[ $fail = 0 ] && echo "== All checks passed ==" || echo "== Some checks failed =="
exit $fail
