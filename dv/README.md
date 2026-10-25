# dv/

| Thư mục | Nội dung | Script chạy |
| --- | --- | --- |
| `tb/` | TB đơn vị của lõi, `RISCV_Core_tb`, `RISCV_Core_prog_tb`, `RISCV_Core_hazard_tb` | `sim/run_unit.do`, `sim/run_rtl.do` |
| `tb/` | Top UVM: `tb_top.sv` (slave mô hình), `tb_sha256_top.sv` (SHA-256 thật), `axi4_lite_slave_model.sv` | `sim/run_uvm.do` |
| `tb/soc/` | `APB_Periph_tb.sv` (SYSCSR gồm BUS_ERR và Boot Guard, UART, GPIO, TIMER, WDT, PLIC-lite, Mailbox), `SoC_Top_tb.sv` (toàn SoC, chạy ảnh đúng và `+TAMPER`) | `sim/run_ip.do`, `sim/run_soc.do` |
| `agents/`, `env/`, `tests/`, `hrot_dv_pkg.sv` | Môi trường UVM AXI4-Lite và SHA-256 | `sim/run_uvm.do` |
| `tests/asm/` | Chương trình ISA tự kiểm tra cho lõi | `sim/run_rtl.do` |
| `sw/mkhex.py` | Trình hợp dịch RV32I nhỏ, sinh `boot.hex` (firmware thử + hai golden hash ở `0x600`), `app.hex` (ảnh App 4 KB), `labels.vh` cho `SoC_Top_tb` và bản FPGA | `make sim-soc`, `make hex` |

Mỗi testbench tự kiểm tra và in một dòng tổng kết mà `sim/regress.sh` dò theo: `SUMMARY <NAME>: PASS = x | FAIL = y`, `<tb> RESULT: PASS|FAIL` hoặc `*** TEST PASSED ***` (UVM).
