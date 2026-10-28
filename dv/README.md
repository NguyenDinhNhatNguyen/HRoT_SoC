# dv/

| Thư mục | Nội dung | Script chạy |
| --- | --- | --- |
| `tb/` | TB đơn vị của lõi, `RISCV_Core_tb`, `RISCV_Core_prog_tb` (chạy `core_isa_test` và `core_trap_test`), `RISCV_Core_hazard_tb`, `SoC_Fw_tb` (firmware Secure Boot thật trên SoC, P-13, băm bằng Secure DMA từ P-15), `SoC_Irq_tb` (ngắt hai lõi, P-14). Chỉ còn TB trực tiếp, không có file UVM | `sim/run_unit.do`, `sim/run_rtl.do`, `sim/run_fw.do` |
| `tb/soc/` | `APB_Periph_tb.sv` (SYSCSR gồm BUS_ERR và Boot Guard, UART, GPIO, TIMER, WDT, PLIC-lite, Mailbox), `SoC_Top_tb.sv` (toàn SoC, chạy ảnh đúng và `+TAMPER`) | `sim/run_ip.do`, `sim/run_soc.do` |
| `agents/` | Agent AXI4-Lite (interface + SVA, driver, monitor, sequencer) và `axi4_lite_slave_model.sv` (slave AXI4-Lite mô hình hành vi) | `sim/run_uvm.do` |
| `env/` | Env, scoreboard, mô hình SHA-256 và hai top UVM: `tb_top.sv` (slave mô hình), `tb_sha256_top.sv` (SHA-256 thật) | `sim/run_uvm.do` |
| `tests/`, `hrot_dv_pkg.sv` | Sequence, test UVM AXI4-Lite và SHA-256, package gom các lớp UVM | `sim/run_uvm.do` |
| `tests/asm/` | Chương trình tự kiểm tra: `core_isa_test` (RV32I), `core_trap_test` (Zicsr, trap, ngắt, P-09) cho lõi, `soc_irq_master`, `soc_irq_app` (ngắt trên SoC, P-14) | `sim/run_rtl.do`, `sim/run_fw.do` |
| `sw/mkhex.py` | Trình hợp dịch RV32I nhỏ, sinh `boot.hex` (firmware thử + hai golden hash ở `0x600`), `app.hex` (ảnh App 4 KB), `labels.vh` cho `SoC_Top_tb` và bản FPGA | `make sim-soc`, `make hex` |

Mỗi testbench tự kiểm tra và in một dòng tổng kết mà `sim/regress.sh` dò theo: `SUMMARY <NAME>: PASS = x | FAIL = y`, `<tb> RESULT: PASS|FAIL` hoặc `*** TEST PASSED ***` (UVM).
