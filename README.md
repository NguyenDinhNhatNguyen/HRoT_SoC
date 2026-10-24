# HRoT_SoC

SoC RISC-V hai lõi bất đối xứng với cách ly vật lý và khởi động bảo mật (Hardware Root of Trust & Secure Boot).
Master Core băm firmware của App Core bằng SHA-256 phần cứng; App Core chỉ được nhả reset khi hash khớp.

## Chạy nhanh (trong WSL, tại thư mục gốc repo)

| Lệnh | Việc |
| --- | --- |
| `make test` | Regression toàn bộ bằng QuestaSim + SystemC (lõi, ngoại vi APB, SoC secure boot, VP) |
| `make sim-core TB=RISCV_Core_tb` | Mô phỏng lõi (mặc định `RISCV_Core_prog_tb`) |
| `make sim-soc` / `make sim-ip` | Mô phỏng toàn SoC / ngoại vi APB |
| `make vp` | Virtual Platform SystemC chạy HAL thật (image đúng và image bị sửa) |
| `make fw` | Build firmware Master (`fw/build/firmware_imem.hex`, `firmware_dmem.hex`) |
| `make de2` | Quartus II 13.0sp1 cho DE2 (Cyclone II), kết quả trong `syn/intel_de2/build` |
| `make xilinx PART=<part>` | Vivado 2025.2 cho kit Xilinx, kết quả trong `syn/xilinx/build` |

Quy ước: chỉ làm việc trên nhánh `main`, chạy `make test` trước khi push. Mô phỏng chỉ dùng QuestaSim
(Makefile gọi Questa/Quartus/Vivado trên Windows qua WSL interop, đường dẫn đặt ở đầu Makefile).

## Cấu trúc

| Thư mục | Nội dung |
| --- | --- |
| `rtl/core`, `rtl/top/RISCV_Core.v` | Lõi RISC-V RV32I 5 tầng |
| `rtl/uncore`, `rtl/top/SoC_Top.v` | Bus AXI4-Lite/APB, ngoại vi, bộ nhớ, SHA-256, tích hợp SoC |
| `dv/` | Testbench, UVM, firmware thử (`dv/tests/mkhex.py`) |
| `fw/` | Firmware, HAL, linker, startup |
| `vp/` | Virtual Platform SystemC/TLM-2.0 |
| `sim/` | Script mô phỏng Questa, regression, VP |
| `syn/intel_de2`, `syn/xilinx` | Top bọc chân, constraints, script build cho từng hãng FPGA |
| `pd/reports` | Báo cáo PPA (FPGA, ASIC) |
| `doc/` | Bản đồ địa chỉ/thanh ghi (`SoC_Memory_Map.md`), tài liệu SHA-256, hướng dẫn |
