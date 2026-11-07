# rtl/

RTL Verilog-2001 (Quartus II 13.0sp1 đọc được), dùng chung cho mô phỏng, DE2 và Xilinx. Reset mức cao, đồng bộ.

| Thư mục | File | Ghi chú |
| --- | --- | --- |
| `core/` | 26 khối của lõi RV32I 5 tầng, có Zicsr và trap máy (`Sys_Decoder`, `CSR_Unit`, `Pipe_Reg`, P-09) | Phát |
| `bus/` | `AXI4_Lite_Master`, `AXI4_Lite_Slave_Template`, `AXI4_Lite_to_APB`, `APB_Decoder`, `Secure_DMA`, `DMA_Firewall` | Interconnect AXI 1 master (CPU và DMA dùng chung) – 6 slave nằm trong `SoC_Top.v`. DMA đi qua tường lửa |
| `periph/` | `SYSCSR`, `Boot_Verifier`, `UART`, `GPIO`, `TIMER`, `WDT`, `PLIC`, `Mailbox`, `Sync_FIFO` | APB slave, 0 wait state. Mailbox có hai cổng APB (Secure và App). `Boot_Verifier` (APB slot 8) tự so digest SHA-256 với golden hash trong Boot ROM, `SYSCSR` chỉ nhả App khi `VERIFY_GATE = 1` và `VERIFIED` |
| `mem/` | `Data_Memory` (RAM), `Dual_Port_ROM` (ROM App và Boot ROM, cổng B chỉ đọc qua AXI, Boot_Verifier mượn cổng B của Boot ROM khi `CHECK`). Không thêm cổng đọc thứ ba: Quartus khi đó không suy ra M4K và bỏ cả lõi Master | Đọc/ghi ở cạnh xuống để suy ra M4K/BRAM |
| `crypto/` | `SHA256_Core`, `SHA256_Wrapper` | 66 chu kỳ mỗi block |
| `top/` | `RISCV_Core.v`, `SoC_Top.v` | `SoC_Top` dùng `` `default_nettype none `` |

Bản đồ địa chỉ: [docs/spec/SoC_Memory_Map.md](../docs/spec/SoC_Memory_Map.md). Thêm file mới vào một thư mục có sẵn thì không phải sửa script: `sim/*.do` và `fpga/<hãng>/<kit>/build.tcl` lấy hết `*.v` trong `core`, `bus`, `periph`, `mem`, `crypto`.
