# rtl/

RTL Verilog-2001 (Quartus II 13.0sp1 đọc được), dùng chung cho mô phỏng, DE2 và Xilinx. Reset mức cao, đồng bộ.

| Thư mục | File | Ghi chú |
| --- | --- | --- |
| `core/` | 23 khối của lõi RV32I 5 tầng | Phát |
| `bus/` | `AXI4_Lite_Master`, `AXI4_Lite_Slave_Template`, `AXI4_Lite_to_APB`, `APB_Decoder` | Interconnect AXI 1 master – 5 slave nằm trong `SoC_Top.v` |
| `periph/` | `SYSCSR`, `UART`, `GPIO`, `TIMER`, `WDT`, `Sync_FIFO` | APB slave, 0 wait state |
| `mem/` | `Data_Memory` (RAM), `Dual_Port_ROM` (ROM App và Boot ROM) | Đọc/ghi ở cạnh xuống để suy ra M4K/BRAM |
| `crypto/` | `SHA256_Core`, `SHA256_Wrapper` | 66 chu kỳ mỗi block |
| `top/` | `RISCV_Core.v`, `SoC_Top.v` | `SoC_Top` dùng `` `default_nettype none `` |

Bản đồ địa chỉ: [docs/spec/SoC_Memory_Map.md](../docs/spec/SoC_Memory_Map.md). Thêm file mới vào một thư mục có sẵn thì không phải sửa script: `sim/*.do` và `fpga/*/build.tcl` lấy hết `*.v` trong `core`, `bus`, `periph`, `mem`, `crypto`.
