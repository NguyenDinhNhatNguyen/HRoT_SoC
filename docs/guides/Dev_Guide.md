# Hướng dẫn phát triển — HRoT SoC

> Đọc file này trước khi sửa code. Trạng thái và việc đang chờ: `docs/project/Project_Status.md`. Tiến độ, hạn và giao diện đã chốt (I-xx): [Google Sheet "HRoT_SoC — Tiến độ Đồ án 2"](https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4/edit) — **nguồn chính thức, đọc bản mới nhất trước khi làm**. Bản đồ địa chỉ/thanh ghi: `docs/spec/SoC_Memory_Map.md` (Nguyên giữ).

## 1. Cấu trúc và phân công

| Thư mục | Nội dung | Phụ trách |
| --- | --- | --- |
| `rtl/core/`, `rtl/top/RISCV_Core.v` | Lõi RV32I 5 tầng (forwarding, load-use stall, flush ở EX, load/store byte/half) | Phát |
| `rtl/bus/`, `rtl/periph/`, `rtl/mem/`, `rtl/crypto/`, `rtl/top/SoC_Top.v` | AXI4-Lite master dùng chung (CPU và Secure DMA) + interconnect, cầu AXI→APB, SYSCSR (BUS_ERR, Boot Guard), UART, GPIO, TIMER, WDT, PLIC-lite, Mailbox, Secure DMA + tường lửa, SHA-256, bộ nhớ, bus APB thế giới App | Nguyên |
| `dv/tb/` · `dv/tb/soc/` | TB đơn vị, TB lõi (`RISCV_Core_tb`, `RISCV_Core_prog_tb`, `RISCV_Core_hazard_tb`), chỉ TB trực tiếp · `APB_Periph_tb`, `SoC_Top_tb` | Phát (lõi) · Nguyên (IP, SoC) |
| `dv/agents`, `dv/env`, `dv/tests`, `dv/hrot_dv_pkg.sv` | Môi trường UVM AXI4-Lite và SHA-256. Từ 26/10 (P-10) slave mô hình nằm ở `dv/agents`, hai top UVM (`tb_top.sv`, `tb_sha256_top.sv`) nằm ở `dv/env` | Phát |
| `dv/tests/asm/` · `dv/sw/mkhex.py` | Chương trình tự kiểm tra cho lõi (`core_isa_test`, `core_trap_test`) · firmware thử viết tay cho `SoC_Top_tb` | Phát · Nguyên |
| `fw/` | HAL SHA-256, driver UART/GPIO (`uart.h`, `gpio.h`, P-11), crt0, linker script, Secure Boot | Phát |
| `vp/` | Virtual Platform SystemC/TLM-2.0 (chạy HAL thật) | Nguyên |
| `fpga/` (`intel_de2`, `xilinx`, `reports`) · `pd/` | Tổng hợp FPGA và báo cáo · luồng ASIC | Nguyên · Phát |

## 2. Giao kèo của `RISCV_Core` với bên ngoài

- `instr_rdata` / `data_rdata` phải hợp lệ **trước cạnh lên kế tiếp** sau khi địa chỉ đổi. Bộ nhớ trong SoC đọc đồng bộ ở **cạnh xuống** (suy ra M4K/BRAM), nên lõi vẫn thấy dữ liệu trong cùng chu kỳ, đổi lại đường đọc chỉ còn nửa chu kỳ (10 ns @ 50 MHz).
- Truy cập qua bus chưa xong thì `bus_stall = 1` (đóng băng toàn pipeline). Trong `SoC_Top`: `bus_stall = (data_we | data_re) & ~resp_valid` (tổ hợp).
- Store: `data_wdata` đã lặp byte/half lên mọi lane, `data_wstrb[3:0]` chọn lane. Load: `data_rdata` là word căn lề, lõi tự dịch và mở rộng dấu/0.
- Truy cập lệch lề không được hỗ trợ (không trap).
- **Zicsr và trap máy (P-09, 26/10):** CSR `mstatus` (MIE, MPIE, MPP đọc 11), `misa` (RV32I), `mie` (MTIE, MEIE), `mip` (MTIP, MEIP, chỉ đọc), `mtvec` (chỉ chế độ direct), `mscratch`, `mepc`, `mcause`, `mtval`, `mvendorid`/`marchid`/`mimpid`/`mhartid` (đọc 0). CSR khác hoặc ghi vào CSR chỉ đọc là lệnh không hợp lệ. Trap: ngắt (`mcause` 0x8000000B / 0x80000007), lệnh không hợp lệ (2), EBREAK (3), ECALL (11), `mtval` = 0. MRET khôi phục MIE từ MPIE. FENCE, FENCE.I, WFI chạy như NOP. Trap xử lý ở tầng MEM: lệnh cũ hơn đã xong, lệnh mới hơn bị hủy. Ngắt chỉ nhận trên lệnh không truy cập bộ nhớ, nên một lệnh load/store không bao giờ bị cắt hay chạy lại. Sau reset `mstatus.MIE = 0` và `mie = 0`, nên firmware cũ chạy như trước.
- **Cổng ngắt (I-01, chốt 25/10, có trong lõi từ P-09):** `irq_timer`, `irq_ext`: đầu vào mức cao, đồng bộ `clk`, giữ mức tới khi nguồn tự xóa (TIMER0: ghi `mtimecmp`, PLIC: claim/complete), lõi không bắt cạnh → `mip.MTIP` (bit 7) / `mip.MEIP` (bit 11), ưu tiên MEI > MTI. Phía `SoC_Top` chưa nối hai cổng này (comment `TODO(P-09)`, việc của Nguyên theo R16), cổng để hở thì ngắt không bao giờ xảy ra. Dự trữ cho sau P-09, chưa có trong lõi: `data_err` mức cao cùng chu kỳ với `resp_valid` (nối `err_valid` của `AXI4_Lite_Master`) → access fault `mcause` 5 (load) / 7 (store), `mtval` = địa chỉ.
- **ASIC (R8, chốt trước Tuần 12):** khi Nguyên thêm bộ nhớ đọc cạnh lên, lõi cần tín hiệu chờ ở IF và MEM để chịu 1 chu kỳ trễ. Ở MEM dùng lại `bus_stall`, ở IF thêm cổng mới (tên chốt cùng P-09).
- Reset active-high, PC reset = `0x0`. Register file không reset (x1..x31 là X đến khi được ghi).

## 3. Bản đồ bộ nhớ Master (thế giới Secure)

Nguồn chính thức: `docs/spec/SoC_Memory_Map.md`. Tóm tắt:

| Địa chỉ | Vùng | Ghi chú |
| --- | --- | --- |
| `0x0000_0000` 4 KB | Boot ROM | cổng A fetch lệnh (`.text`), cổng B cho `lw` đọc dữ liệu chỉ-đọc (`.rodata`, golden hash). Ghi → `SLVERR`. Nạp `firmware_imem.hex` |
| `0x1000_0000` 4 KB | RAM Master | nạp `firmware_dmem.hex` (`.rodata/.data`), `.bss` + stack |
| `0x4000_0000` | Cầu AXI→APB | SYSCSR `0x4000_0000` (APP_CTRL ở offset 0), UART0 `+0x1000`, GPIO0 `+0x2000`, TIMER0 `+0x3000`, WDT `+0x4000`, PLIC-lite `+0x5000`, Mailbox `+0x6000`, Secure DMA `+0x7000` |
| `0x5000_0000` | SHA-256 | `docs/spec/SHA256_Register_Map.md`, `fw/hal/sha256_regs.h`, 66 chu kỳ START→DONE. Offset `0x100`–`0xFFFF` đọc 0 |
| `0x6000_0000` 4 KB | ROM App, cổng B | chỉ đọc (để băm), ghi → `SLVERR` |
| còn lại | default slave | `DECERR`, không treo bus |

Lõi là Harvard nhưng Boot ROM có cổng đọc dữ liệu: `lw` từ `0x0000_xxxx` đọc được ROM nên `.rodata` và golden hash đặt được trong ROM (N-21, I-03 còn việc đổi `linker.ld`). Thế giới App có bản đồ riêng (UART1, GPIO1, TIMER1, Mailbox ở `0x4000_xxxx`, địa chỉ khác là RAM App), xem `docs/spec/SoC_Memory_Map.md`.

## 4. Chạy kiểm tra

**Quy ước (I-07):** chỉ commit trên `main`, chạy trong WSL, mô phỏng bằng QuestaSim, `make test` PASS trước khi push. WSL cần `make`, `gcc`, `python3` (`sudo apt install build-essential python3`), toolchain `riscv64-unknown-elf-*` cho `make fw`, SystemC cho `make vp`.

| Lệnh (thư mục gốc repo) | Việc |
| --- | --- |
| `make test` | Regression toàn bộ (`sim/regress.sh`): 11 TB đơn vị, chương trình ISA, `RISCV_Core_tb`, hazard, UVM (full + reset giữa giao dịch, SHA-256), HAL host, APB, SoC secure boot (ảnh đúng và ảnh bị sửa `+TAMPER`), VP. Log ở `build/logs/` |
| `make sim-unit` | 11 TB đơn vị (`sim/run_unit.do`), mỗi TB in `SUMMARY <TÊN>: PASS = x \| FAIL = y` |
| `make sim-core TB=<tb>` | `RISCV_Core_prog_tb` (mặc định, chạy `core_isa_test` và `core_trap_test`) \| `RISCV_Core_tb` \| `RISCV_Core_hazard_tb` |
| `make sim-uvm TEST=<test> SEED=<n>` | UVM: `base_test` \| `axi4_lite_wstrb_test` \| `axi4_lite_rand_test` \| `axi4_lite_full_test`, thêm `+RESET_AT_NS=<t>` qua `PLUSARGS` trong `run_uvm.do` |
| `make sim-ip` / `make sim-soc` / `make vp` | APB (SYSCSR, GPIO, UART, TIMER, WDT, PLIC-lite, Mailbox) / toàn SoC (thêm tham số `set PLUSARGS +TAMPER` trong `sim/run_soc.do` để chạy ảnh bị sửa) / Virtual Platform |
| `make fw` | `fw/build/firmware_imem.hex`, `firmware_dmem.hex`, `.dis`, `.map` |
| `make -C fw/hal/test test` · `crosscheck` · `rv32` | Driver UART/GPIO rồi HAL SHA-256 trên host · so với `sha256sum` · build rv32i cả HAL và driver |
| Tạo lại hex test lõi | lệnh ở đầu `dv/tests/asm/core_isa_test.S` và `core_trap_test.S` (test trap cần `-march=rv32i_zicsr`) |
| `make de2` / `make xilinx PART=<part>` | Quartus / Vivado, kết quả ở `fpga/*/build/`, báo cáo đã lưu ở `fpga/reports/` |

Trên Questa 10.2c, chạy `make test < /dev/null` cho tới khi `sim/run_unit.do` được sửa (xem `Project_Status.md` mục 4), nếu không Questa sẽ đứng chờ ở dấu nhắc `VSIM(paused)>`. `sim/run_vp.sh` nhận cả SystemC 2.3.3 (`lib-linux64/`) lẫn 2.3.4 (`lib/`) qua biến `SYSTEMC_HOME`.

**Ngoài Questa (công cụ mã nguồn mở, image docker `hpretl/iic-osic-tools`):** công cụ ở `/foss/tools/<tool>/bin`, iverilog cần `LD_LIBRARY_PATH=/foss/tools/iverilog/lib`. UVM trên Verilator cần thư viện `chipsalliance/uvm-verilator` và **z3 trong PATH** (thiếu z3 thì mọi `randomize()` thất bại), build mất khoảng 8 phút. **Máy WSL dễ lag: chạy job nặng với `docker run --cpus=2 --memory=4g` và `nice -n 19`.**

## 5. Quy ước code

- RTL/TB Verilog: comment và chuỗi in ra bằng tiếng Anh (từ 25/10/2026, toàn bộ file RTL core, DV và firmware của Phát đã chuyển sang ngày 25/10). Mỗi file có `` `timescale 1ns / 1ps ``, kết thúc bằng newline, xuống dòng LF.
- TB tự kiểm tra, in một dòng `SUMMARY <TÊN>: PASS = x | FAIL = y` (hoặc `<tb> RESULT: PASS|FAIL`) và gọi `$finish`. `regress.sh` dựa vào dòng này.
- `*.svh` chỉ được `` `include `` vào `hrot_dv_pkg.sv`, không biên dịch riêng.
- RTL reset active-high, còn interface UVM `axi4_lite_if` reset active-low (`rst_n`).
- Firmware: C11 freestanding, rv32i (không M), không libc, nhân/chia lấy từ libgcc. Địa chỉ ngoại vi lấy theo `docs/spec/SoC_Memory_Map.md` (I-02).
- Đổi bản đồ địa chỉ hay giao diện giữa hai người: cập nhật mục "Mốc & Giao diện" trong sheet và báo trước.
- Viết comment, tài liệu: không dùng dấu `;` trong câu, bảng Markdown dùng dòng phân cách `| --- | --- |`.
- Mỗi dòng code chỉ một lệnh kết thúc bằng `;`. Lệnh sau `if`, `else`, `else if`, `for`, `while` và sau nhãn `case` (kể cả `default:`) xuống dòng mới, thụt vào một mức (4 dấu cách). Trong C/C++, khối `{ ... }` có từ hai lệnh trở lên phải viết trên nhiều dòng. Riêng hàm một lệnh như `{ return x; }` được giữ trên một dòng.
