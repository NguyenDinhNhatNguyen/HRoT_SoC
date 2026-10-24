# HRoT_SoC

SoC RISC-V hai lõi bất đối xứng với cách ly vật lý và khởi động bảo mật (Hardware Root of Trust & Secure Boot).
Master Core băm firmware của App Core bằng SHA-256 phần cứng và App Core chỉ được nhả reset khi hash khớp.

## Chạy nhanh (trong WSL, tại thư mục gốc repo)

| Lệnh | Việc |
| --- | --- |
| `make test` | Regression toàn bộ bằng QuestaSim + SystemC (TB đơn vị, lõi, UVM, HAL, ngoại vi APB, SoC secure boot, VP) |
| `make sim-unit` | 11 testbench đơn vị của lõi |
| `make sim-core TB=RISCV_Core_tb` | Mô phỏng lõi (mặc định `RISCV_Core_prog_tb`) |
| `make sim-uvm TEST=<test> SEED=<n>` | UVM AXI4-Lite (mặc định `axi4_lite_full_test`) |
| `make sim-soc` / `make sim-ip` | Mô phỏng toàn SoC / ngoại vi APB (SYSCSR, UART, GPIO, TIMER, WDT) |
| `make vp` | Virtual Platform SystemC chạy HAL thật (image đúng và image bị sửa) |
| `make fw` | Build firmware Master (`fw/build/firmware_imem.hex`, `firmware_dmem.hex`) |
| `make de2` | Quartus II 13.0sp1 cho DE2 (Cyclone II), kết quả trong `fpga/intel_de2/build` |
| `make xilinx PART=<part>` | Vivado 2025.2 cho kit Xilinx, kết quả trong `fpga/xilinx/build` |

Quy ước: chỉ làm việc trên nhánh `main`, chạy `make test` trước khi push. Mô phỏng chỉ dùng QuestaSim
(Makefile gọi Questa/Quartus/Vivado trên Windows qua WSL interop, đường dẫn đặt ở đầu Makefile).
Mỗi testbench in một dòng tổng kết bằng tiếng Anh (`... RESULT: PASS|FAIL`, `SUMMARY ...`, `TEST PASSED`) để `sim/regress.sh` đọc.

## Cấu trúc

```text
HRoT_SoC/
├── rtl/            RTL dùng chung cho mô phỏng và FPGA (xem rtl/README.md)
│   ├── core/       lõi RV32I 5 tầng
│   ├── bus/        AXI4-Lite master/slave, cầu AXI→APB, bộ giải mã APB
│   ├── periph/     SYSCSR, UART, GPIO, TIMER, WDT, FIFO
│   ├── mem/        Boot ROM, RAM, ROM App hai cổng
│   ├── crypto/     lõi SHA-256 và vỏ AXI
│   └── top/        RISCV_Core.v, SoC_Top.v
├── dv/             kiểm chứng (xem dv/README.md)
│   ├── tb/         testbench lõi, tb/soc/ chứa testbench ngoại vi APB và toàn SoC
│   ├── agents/ env/ tests/   môi trường UVM AXI4-Lite và SHA-256
│   └── sw/         mkhex.py: firmware thử viết tay cho SoC_Top_tb và FPGA
├── fw/             firmware Master: HAL, crt0, linker script, secure boot
├── vp/             Virtual Platform SystemC/TLM-2.0 (xem vp/README.md)
├── sim/            script Questa, regress.sh, run_vp.sh
├── fpga/           top bọc chân, constraints, script build và báo cáo FPGA (xem fpga/README.md)
├── pd/             luồng ASIC (constraints, scripts, reports)
└── docs/           tài liệu (xem docs/README.md)
```

Tài liệu nên đọc trước: [docs/guides/Dev_Guide.md](docs/guides/Dev_Guide.md) (phân công, quy ước, cách chạy)
và [docs/spec/SoC_Memory_Map.md](docs/spec/SoC_Memory_Map.md) (bản đồ địa chỉ và thanh ghi).
