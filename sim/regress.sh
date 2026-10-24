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
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_prog_tb; do run_rtl.do") > $LOG/core_prog.log 2>&1
check "Loi: chuong trinh ISA"   $LOG/core_prog.log "SUMMARY: PASS"
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_tb; do run_rtl.do")      > $LOG/core_tb.log 2>&1
check "Loi: RISCV_Core_tb"      $LOG/core_tb.log   "OVERALL: PASS"
(cd sim && "$QUESTA" -c -do run_ip.do)                                  > $LOG/ip.log 2>&1
check "Ngoai vi APB"            $LOG/ip.log        "FAIL = 0"
python3 dv/tests/mkhex.py sim > /dev/null
(cd sim && "$QUESTA" -c -do run_soc.do)                                 > $LOG/soc.log 2>&1
check "SoC secure boot"         $LOG/soc.log       "SOC RESULT: PASS"
(cd sim && bash run_vp.sh)                                              > $LOG/vp.log 2>&1
[ "$(grep -c 'VP RESULT: PASS' $LOG/vp.log)" = 2 ] && printf "  %-28s PASS\n" "VP (dung + bi sua)" \
    || { printf "  %-28s FAIL  (xem %s)\n" "VP (dung + bi sua)" $LOG/vp.log; fail=1; }

[ $fail = 0 ] && echo "== TAT CA PASS ==" || echo "== CO FAIL =="
exit $fail
