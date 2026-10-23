# Hướng dẫn phát triển — HRoT SoC

> Đọc file này trước khi sửa code. Trạng thái dự án và việc đang chờ: `doc/Project_Status.md`. Lộ trình: `doc/Project_Plan.md`.

## 1. Cấu trúc và phân công

| Thư mục | Nội dung | Phụ trách |
|---|---|---|
| `rtl/core/`, `rtl/top/RISCV_Core.v` | Lõi RV32I 5 tầng (forwarding, load-use stall, flush khi rẽ nhánh ở EX) | Phát |
| `rtl/uncore/`, `rtl/top/SoC_Top.v` | AXI4-Lite master/slave, SHA-256, Dual-Port ROM, Reset Controller, RAM | Nguyên |
| `dv/tb/` | TB đơn vị + TB lõi (`RISCV_Core_tb.sv`, `RISCV_Core_prog_tb.sv`) | Phát |
| `dv/agents`, `dv/env`, `dv/tests`, `dv/hrot_dv_pkg.sv` | Môi trường UVM AXI4-Lite | Phát |
| `dv/tests/asm/` | Chương trình assembly tự kiểm tra cho lõi | Phát |
| `fw/` | HAL SHA-256, crt0, linker script, Secure Boot | Phát |
| `vp/`, `syn/`, `pd/` | Virtual Platform (SystemC/TLM), Vivado, ASIC | Nguyên (ASIC: Phát) |

## 2. Giao kèo của `RISCV_Core` với bên ngoài

- `instr_rdata` phải có **trong cùng chu kỳ** với `instr_addr` (bộ nhớ đọc tổ hợp).
- `data_rdata` phải có trong cùng chu kỳ với `data_addr`; chưa có thì giữ `bus_stall = 1` (đóng băng toàn pipeline) đến khi có.
- Store: `data_wdata` đã lặp byte/half lên mọi lane, `data_wstrb[3:0]` chọn lane. Load: `data_rdata` là word căn lề, lõi tự dịch và mở rộng dấu/0.
- Truy cập lệch lề không được hỗ trợ (không trap). Chưa có CSR/ECALL/FENCE (giải mã thành NOP).
- Reset active-high, PC reset = `0x0`. Register file không reset (x1..x31 là X đến khi được ghi).

## 3. Bản đồ bộ nhớ (ĐỀ XUẤT, chờ Nguyên chốt)

| Địa chỉ | Vùng | Ghi chú |
|---|---|---|
| `0x0000_0000` 4 KB | ROM lệnh | `.text` → `firmware_imem.hex` |
| `0x1000_0000` 4 KB | RAM dữ liệu | `.rodata/.data` → `firmware_dmem.hex`; `.bss` + stack |
| `0x4000_0000` | Reset Controller | ghi `1` để nhả reset App Core |
| `0x5000_0000` | SHA-256 | map thanh ghi: `doc/SHA256_Register_Map.md`, `fw/hal/sha256_regs.h` |

Lõi là Harvard: lệnh load **không** đọc được ROM lệnh, nên mọi hằng số phải nằm trong RAM (nạp sẵn từ `firmware_dmem.hex`).

## 4. Chạy kiểm tra

Công cụ mã nguồn mở nằm trong image docker `hpretl/iic-osic-tools` (`/foss/tools/<tool>/bin`; iverilog cần `LD_LIBRARY_PATH=/foss/tools/iverilog/lib`). **Máy WSL dễ bị lag: luôn chạy job nặng với `docker run --cpus=2 --memory=4g` và `nice -n 19`.**

| Việc | Lệnh |
|---|---|
| Lõi trên Questa | `cd sim && vsim -c -do run_rtl.do` (mặc định `RISCV_Core_prog_tb`; `set TB RISCV_Core_tb` để đổi) |
| TB đơn vị (iverilog) | `iverilog -g2012 -o t rtl/core/*.v dv/tb/<Tên>_tb.v && vvp -n t` → dòng `SUMMARY <TÊN>: PASS = n \| FAIL = 0` |
| UVM trên Questa | `cd sim && vsim -c -do "set TEST axi4_lite_full_test; set SEED 7; do run_uvm.do"` |
| UVM trên Verilator | Cần thư viện `chipsalliance/uvm-verilator` và **z3 trong PATH** (thiếu z3 thì mọi `randomize()` thất bại). Build ~8 phút với `-j 2` |
| Reset giữa giao dịch | thêm `+RESET_AT_NS=<t>` khi chạy UVM |
| HAL trên host | `make -C fw/hal/test test` · `crosscheck` (so với `sha256sum`) · `rv32` |
| Build firmware | `cmake -S fw -B build && cmake --build build` → `firmware_imem.hex`, `firmware_dmem.hex`, `firmware.dis`, `firmware.map` |
| Tạo lại hex ISA test | lệnh ở đầu `dv/tests/asm/core_isa_test.S` |

## 5. Quy ước code

- RTL/TB Verilog: comment tiếng Việt không dấu; mỗi file có `` `timescale 1ns / 1ps ``; file kết thúc bằng newline.
- TB đơn vị tự kiểm tra, in `SUMMARY <TÊN>: PASS = x | FAIL = y` và gọi `$finish`.
- `*.svh` chỉ được `` `include `` vào `hrot_dv_pkg.sv`, không biên dịch riêng.
- RTL reset active-high; interface UVM `axi4_lite_if` reset active-low (`rst_n`), nối `~rst_n` khi ghép DUT.
- Firmware: C11 freestanding, rv32i (không M), không libc; nhân/chia lấy từ libgcc.
