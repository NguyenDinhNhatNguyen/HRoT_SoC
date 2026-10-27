#!/bin/bash
# Full regression. Run in WSL from the repo root: bash sim/regress.sh (or make test)
# RTL runs on QuestaSim (Windows, via WSL interop) and the VP builds and runs with SystemC inside WSL.
# Logs land in build/logs/. Exit code 0 means everything passed.
# Every vsim reads stdin from /dev/null so Questa can never wait at a VSIM(paused)> prompt (P-22).
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
: > $LOG/unit.log
for u in ALU_tb Branch_Unit_tb Control_Unit_tb Extend_tb Register_File_tb IF_Stage_tb IF_ID_tb \
         ID_Stage_tb EX_Stage_tb MEM_Stage_tb WB_Stage_tb; do
    (cd sim && "$QUESTA" -c -do "set UNIT $u; do run_unit.do" < /dev/null) >> $LOG/unit.log 2>&1
done
n_ok=$(grep -cE "SUMMARY [A-Z_]+: PASS = [0-9]+ \| FAIL = 0" $LOG/unit.log)
if [ "$n_ok" = 11 ] && ! grep -qE "\*\* (Error|Fatal)" $LOG/unit.log; then
    printf "  %-30s PASS\n" "Core: 11 unit testbenches"
else
    printf "  %-30s FAIL  (%s of 11 passed, see %s)\n" "Core: 11 unit testbenches" "$n_ok" $LOG/unit.log; fail=1
fi
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_prog_tb; do run_rtl.do" < /dev/null) > $LOG/core_prog.log 2>&1
check "Core: ISA program"           $LOG/core_prog.log "SUMMARY: PASS"
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_tb; do run_rtl.do" < /dev/null)      > $LOG/core_tb.log 2>&1
check "Core: RISCV_Core_tb"         $LOG/core_tb.log   "OVERALL: PASS"
(cd sim && "$QUESTA" -c -do "set TB RISCV_Core_hazard_tb; do run_rtl.do" < /dev/null) > $LOG/core_haz.log 2>&1
check "Core: hazards without NOPs"  $LOG/core_haz.log  "RESULT: PASS"
(cd sim && "$QUESTA" -c -do "set TEST axi4_lite_full_test; set SEED 1; set PLUSARGS {+NUM_TRANS=300}; do run_uvm.do" < /dev/null) > $LOG/uvm_full.log 2>&1
check "UVM: AXI4-Lite full"         $LOG/uvm_full.log  "TEST PASSED"
(cd sim && "$QUESTA" -c -do "set TEST axi4_lite_rand_test; set SEED 7; set PLUSARGS {+NUM_TRANS=300 +RESET_AT_NS=20000}; do run_uvm.do" < /dev/null) > $LOG/uvm_reset.log 2>&1
check "UVM: reset mid-transaction"  $LOG/uvm_reset.log "TEST PASSED"
(cd sim && "$QUESTA" -c -do "set DUT sha256; set TEST sha256_full_test; set SEED 1; do run_uvm.do" < /dev/null) > $LOG/uvm_sha.log 2>&1
check "UVM: SHA-256"                $LOG/uvm_sha.log   "TEST PASSED"
(cd sim && "$QUESTA" -c -do "set DUT sha256; set TEST sha256_rand_test; set SEED 3; set PLUSARGS {+NUM_MSGS=20 +RESET_AT_NS=30000}; do run_uvm.do" < /dev/null) > $LOG/uvm_sha_reset.log 2>&1
check "UVM: SHA-256 with reset"     $LOG/uvm_sha_reset.log "TEST PASSED"
if command -v gcc > /dev/null; then
    make -s -C fw/hal/test clean test                                   > $LOG/hal.log 2>&1
    check "HAL: SHA-256 on host"    $LOG/hal.log       "==== PASSED"
else
    printf "  %-30s SKIP  (no gcc in WSL)\n" "HAL: SHA-256 on host"
fi
(cd sim && "$QUESTA" -c -do run_ip.do < /dev/null)                                  > $LOG/ip.log 2>&1
check "APB peripherals"             $LOG/ip.log        "RESULT: PASS"
python3 dv/sw/mkhex.py sim > /dev/null
(cd sim && "$QUESTA" -c -do run_soc.do < /dev/null)                                 > $LOG/soc.log 2>&1
check "SoC: secure boot, good image" $LOG/soc.log      "RESULT: PASS"
(cd sim && "$QUESTA" -c -do "set PLUSARGS +TAMPER; do run_soc.do" < /dev/null)      > $LOG/soc_tamper.log 2>&1
check "SoC: tampered image locked"  $LOG/soc_tamper.log "RESULT: PASS"
# Real Secure Boot firmware on the SoC (P-13): needs the RISC-V toolchain for make fw
if command -v riscv64-unknown-elf-gcc > /dev/null && make -s fw            > $LOG/fw_build.log 2>&1; then
    python3 fw/tools/golden.py sim/app.hex sim/fw_golden.hex > /dev/null
    (cd sim && "$QUESTA" -c -do "set TB SoC_Fw_tb; do run_fw.do" < /dev/null)             > $LOG/fw.log 2>&1
    check "SoC: firmware, good image"   $LOG/fw.log        "SoC_Fw_tb RESULT: PASS"
    (cd sim && "$QUESTA" -c -do "set TB SoC_Fw_tb; set PLUSARGS +TAMPER; do run_fw.do" < /dev/null) > $LOG/fw_tamper.log 2>&1
    check "SoC: firmware, tampered"     $LOG/fw_tamper.log "SoC_Fw_tb RESULT: PASS"
else
    printf "  %-30s SKIP  (no RISC-V toolchain or make fw failed, see %s)\n" "SoC: firmware" $LOG/fw_build.log
fi
(cd sim && "$QUESTA" -c -do "set TB SoC_Irq_tb; do run_fw.do" < /dev/null)              > $LOG/irq.log 2>&1
check "SoC: interrupts, both cores" $LOG/irq.log       "SoC_Irq_tb RESULT: PASS"
(cd sim && bash run_vp.sh)                                              > $LOG/vp.log 2>&1
# 4 cases: good and tampered image, each with the built-in scenario and with the real firmware (P-13)
[ "$(grep -c 'VP RESULT: PASS' $LOG/vp.log)" = 4 ] && printf "  %-30s PASS\n" "VP: good and tampered image" \
    || { printf "  %-30s FAIL  (see %s)\n" "VP: good and tampered image" $LOG/vp.log; fail=1; }

[ $fail = 0 ] && echo "== All checks passed ==" || echo "== Some checks failed =="
exit $fail
