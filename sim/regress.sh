#!/bin/bash
# Regression toan bo, chay trong WSL tu thu muc goc repo: bash sim/regress.sh (hoac make test)
# Mo phong bang QuestaSim (Windows, goi qua interop); VP bang SystemC trong WSL.
# Log luu o build/logs/. Ma thoat 0 = tat ca PASS.
cd "$(dirname "$0")/.." || exit 2
QUESTA="${QUESTA:-/mnt/c/questasim64_10.2c/win64/vsim.exe}"
LOG=build/logs
mkdir -p "$LOG"
fail=0

check() {   # check <ten> <log> <chuoi PASS>
    if grep -q "$3" "$2" && ! grep -qE "\*\* (Error|Fatal)" "$2"; then
        printf "  %-28s PASS\n" "$1"
    else
        printf "  %-28s FAIL  (xem %s)\n" "$1" "$2"; fail=1
    fi
}

echo "== Regression HRoT_SoC (QuestaSim + SystemC) =="
(cd sim && "$QUESTA" -c -do run_unit.do)                                > $LOG/unit.log 2>&1
n_ok=$(grep -cE "SUMMARY [A-Z_]+: PASS = [0-9]+ \| FAIL = 0" $LOG/unit.log)
if [ "$n_ok" = 11 ] && ! grep -qE "\*\* (Error|Fatal)" $LOG/unit.log; then
    printf "  %-28s PASS\n" "Loi: 11 TB don vi"
else
    printf "  %-28s FAIL  (%s/11 TB PASS, xem %s)\n" "Loi: 11 TB don vi" "$n_ok" $LOG/unit.log; fail=1
fi
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_prog_tb; do run_rtl.do") > $LOG/core_prog.log 2>&1
check "Loi: chuong trinh ISA"   $LOG/core_prog.log "SUMMARY: PASS"
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_tb; do run_rtl.do")      > $LOG/core_tb.log 2>&1
check "Loi: RISCV_Core_tb"      $LOG/core_tb.log   "OVERALL: PASS"
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_hazard_tb; do run_rtl.do") > $LOG/core_haz.log 2>&1
check "Loi: hazard (khong NOP)" $LOG/core_haz.log  "HAZ RESULT: 0 fail"
(cd sim && "$QUESTA" -c -do "set TEST axi4_lite_full_test; set SEED 1; set PLUSARGS {+NUM_TRANS=300}; do run_uvm.do") > $LOG/uvm_full.log 2>&1
check "UVM AXI4-Lite full"      $LOG/uvm_full.log  "TEST PASSED"
(cd sim && "$QUESTA" -c -do "set TEST axi4_lite_rand_test; set SEED 7; set PLUSARGS {+NUM_TRANS=300 +RESET_AT_NS=20000}; do run_uvm.do") > $LOG/uvm_reset.log 2>&1
check "UVM reset giua giao dich" $LOG/uvm_reset.log "TEST PASSED"
(cd sim && "$QUESTA" -c -do "set DUT sha256; set TEST sha256_full_test; set SEED 1; do run_uvm.do") > $LOG/uvm_sha.log 2>&1
check "UVM SHA-256 (P-08)"      $LOG/uvm_sha.log   "TEST PASSED"
(cd sim && "$QUESTA" -c -do "set DUT sha256; set TEST sha256_rand_test; set SEED 3; set PLUSARGS {+NUM_MSGS=20 +RESET_AT_NS=30000}; do run_uvm.do") > $LOG/uvm_sha_reset.log 2>&1
check "UVM SHA-256 reset"       $LOG/uvm_sha_reset.log "TEST PASSED"
if command -v gcc > /dev/null; then
    make -s -C fw/hal/test clean test                                   > $LOG/hal.log 2>&1
    check "HAL SHA-256 (host)"  $LOG/hal.log       "==== PASSED"
else
    printf "  %-28s SKIP  (WSL chua co gcc)\n" "HAL SHA-256 (host)"
fi
(cd sim && "$QUESTA" -c -do run_ip.do)                                  > $LOG/ip.log 2>&1
check "Ngoai vi APB"            $LOG/ip.log        "FAIL = 0"
python3 dv/sw/mkhex.py sim > /dev/null
(cd sim && "$QUESTA" -c -do run_soc.do)                                 > $LOG/soc.log 2>&1
check "SoC secure boot"         $LOG/soc.log       "SOC RESULT: PASS"
(cd sim && bash run_vp.sh)                                              > $LOG/vp.log 2>&1
[ "$(grep -c 'VP RESULT: PASS' $LOG/vp.log)" = 2 ] && printf "  %-28s PASS\n" "VP (dung + bi sua)" \
    || { printf "  %-28s FAIL  (xem %s)\n" "VP (dung + bi sua)" $LOG/vp.log; fail=1; }

[ $fail = 0 ] && echo "== TAT CA PASS ==" || echo "== CO FAIL =="
exit $fail
