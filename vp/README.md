# vp/

Virtual Platform SystemC 2.3.3 hoặc 2.3.4 / TLM-2.0 (loosely-timed) của thế giới Secure. CPU giả lập chạy đúng HAL SHA-256 của firmware (`fw/hal`, build với `-DHAL_HOST_MODEL`), mỗi lần HAL đọc/ghi thanh ghi là một giao dịch TLM trên bus.

| File | Nội dung |
| --- | --- |
| `src/main.cpp` | `sc_main`, nối bus và các khối, hook `hal_host_*` của HAL |
| `src/VP_Bus.h` | Bus 1 initiator – N target, giải mã địa chỉ giống `SoC_Top`, địa chỉ lạ → lỗi (DECERR) |
| `src/VP_Peripherals.h` | Bộ nhớ (ROM App và Boot ROM chỉ đọc), SYSCSR (kèm Boot Guard), UART0 (in ra console và giữ log), TIMER0 (mtime 50 MHz theo thời gian mô phỏng), WDT (đếm, không reset) |
| `src/SHA256_VP_Wrapper.h` | Mô hình thanh ghi SHA-256, 66 chu kỳ mỗi block như RTL |
| `src/CPU_Dummy_Initiator.h` | Kịch bản secure boot: đọc CHIP_ID và golden từ Boot ROM, bật WDT, băm ROM App, so golden, kiểm Secure DMA và tường lửa, nhả App hoặc khóa bằng Boot Guard, log qua UART0 |
| `src/DMA_VP.h` | Mô hình chức năng của Secure DMA: cùng thanh ghi và luật tường lửa với RTL, chạy hết lượt băm trong lệnh START |

Chạy: `make vp` (gọi `sim/run_vp.sh`), gồm 4 kịch bản: image đúng và image bị sửa 1 bit (`--tamper`), mỗi loại chạy với kịch bản C++ của `CPU_Dummy_Initiator` và với firmware Secure Boot thật (`--fw`, `fw/secure_boot/secure_boot.c`, P-13). Cả bốn phải in `VP RESULT: PASS`. Ở chế độ `--fw`, firmware ghi LED GPIO0 nên VP in một dòng lỗi bus ở `0x4000_2000` (VP chưa có mô hình GPIO), không ảnh hưởng kết quả.

Chưa mô hình hóa: GPIO, PLIC-lite, Mailbox, bus và ngoại vi của thế giới App, ngắt, reset do WDT.
