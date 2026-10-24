# vp/

Virtual Platform SystemC 2.3.3 / TLM-2.0 (loosely-timed) của thế giới Secure. CPU giả lập chạy đúng HAL SHA-256 của firmware (`fw/hal`, build với `-DHAL_HOST_MODEL`), mỗi lần HAL đọc/ghi thanh ghi là một giao dịch TLM trên bus.

| File | Nội dung |
| --- | --- |
| `src/main.cpp` | `sc_main`, nối bus và các khối, hook `hal_host_*` của HAL |
| `src/VP_Bus.h` | Bus 1 initiator – N target, giải mã địa chỉ giống `SoC_Top`, địa chỉ lạ → lỗi (DECERR) |
| `src/VP_Peripherals.h` | Bộ nhớ (ROM App chỉ đọc) và SYSCSR |
| `src/SHA256_VP_Wrapper.h` | Mô hình thanh ghi SHA-256, 66 chu kỳ mỗi block như RTL |
| `src/CPU_Dummy_Initiator.h` | Kịch bản secure boot: đọc CHIP_ID, băm ROM App, so golden, nhả hoặc giữ reset App |

Chạy: `make vp` (gọi `sim/run_vp.sh`), gồm 2 kịch bản: image đúng và image bị sửa 1 bit (`--tamper`). Cả hai phải in `VP RESULT: PASS`.

Chưa mô hình hóa: UART, GPIO, TIMER, WDT.
