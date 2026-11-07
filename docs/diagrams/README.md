# Bộ sơ đồ kiến trúc và lưu đồ vận hành

File `HRoT_SoC_Diagrams.drawio` gồm 21 trang, mở bằng [draw.io](https://app.diagrams.net) hoặc draw.io Desktop. Mỗi trang có một ảnh PNG (độ phân giải 2x) trong `png/` để chèn thẳng vào báo cáo. Tên khối và tên dây viết bằng tiếng Anh, mô tả bằng tiếng Việt khi cần.

## Danh sách trang

| Trang | Ảnh | Nội dung | Gợi ý dùng ở chương | Nguồn |
| --- | --- | --- | --- | --- |
| 01 | `01_system_overview.png` | Tổng quan SoC: Secure Zone, App Zone, bus, bộ nhớ, khối bảo mật, đường `Verified`, `App Reset` | Kiến trúc tổng thể | `rtl/top/SoC_Top.v` |
| 02 | `02_memory_map.png` | Bản đồ địa chỉ hai thế giới, 9 slot APB | Kiến trúc, bản đồ bộ nhớ | `docs/spec/SoC_Memory_Map.md` |
| 03 | `03_secure_bus_fabric.png` | Arbiter, AXI4-Lite Master, giải mã địa chỉ, 6 slave, cầu APB, bắt lỗi bus | Bus và kết nối | `SoC_Top.v`, `rtl/bus/` |
| 04 | `04_master_core.png` | Pipeline 5 tầng, Hazard, Forwarding, CSR_Unit, ngắt, `data_err` | Lõi RISC-V | `rtl/top/RISCV_Core.v`, `rtl/core/` |
| 05 | `05_secure_dma_firewall_sha_256.png` | Secure DMA, tường lửa, SHA-256 | Khối bảo mật phần cứng | `Secure_DMA.v`, `DMA_Firewall.v`, `rtl/crypto/` |
| 06 | `06_boot_verifier.png` | Boot_Verifier: CHECK, MIN_VER, KEY, STATUS | Khối bảo mật phần cứng | `rtl/periph/Boot_Verifier.v` |
| 07 | `07_syscsr_and_boot_guard.png` | SYSCSR: reset, RST_CAUSE, BUS_ERR, LOCK, Zeroization | Khối bảo mật phần cứng | `rtl/periph/SYSCSR.v` |
| 08 | `08_secure_peripherals_and_interrupts.png` | UART0, GPIO0, TIMER0, WDT, PLIC-lite, Mailbox và đường ngắt | Ngoại vi | `rtl/periph/`, `SoC_Top.v` |
| 09 | `09_app_world.png` | Thế giới App: lõi, ROM, RAM, bus APB riêng, ngắt | Cách ly hai lõi | `SoC_Top.v` |
| 10 | `10_security_architecture.png` | Chuỗi tin cậy và các lớp bảo vệ, gắn mã SR-01..11 | Mô hình bảo mật | `docs/spec/Security_Model.md` |
| 11 | `11_secure_boot_flow.png` | Lưu đồ Secure Boot, mọi nhánh lỗi và mã `SB_*` | Luồng khởi động an toàn | `fw/secure_boot/secure_boot.c` |
| 12 | `12_tamper_and_lockdown_flow.png` | Hash sai, Boot Guard khóa App, xóa RAM, reset nào mở được khóa | Luồng khi bị tấn công | `secure_boot.c`, `SYSCSR.v` |
| 13 | `13_boot_verifier_check_fsm.png` | FSM CHECK của Boot_Verifier | Khối bảo mật phần cứng | `Boot_Verifier.v` |
| 14 | `14_secure_dma_fsm_and_firewall_decision.png` | FSM của Secure DMA và quyết định của tường lửa | Khối bảo mật phần cứng | `Secure_DMA.v`, `DMA_Firewall.v` |
| 15 | `15_bus_transaction_and_error_flow.png` | Một giao dịch bus, OKAY, SLVERR, DECERR, `BUS_ERR`, trap | Bus, xử lý lỗi | `AXI4_Lite_Master.v`, `SoC_Top.v`, `SYSCSR.v` |
| 16 | `16_interrupt_and_trap_flow.png` | Ngắt và ngoại lệ, vào trap, `trap_handler`, MRET | Lõi, firmware | `CSR_Unit.v`, `fw/startup/crt0.S` |
| 17 | `17_reset_and_power_flow.png` | POR, WDT, SW_RESET: cái nào xóa gì | Reset và nguồn | `SYSCSR.v`, `Boot_Verifier.v` |
| 18 | `18_verification_flow.png` | `make test`, `regress.sh`, luồng FPGA và các điểm kiểm | Kiểm chứng | `sim/regress.sh`, `Makefile` |
| 19 | `19_kv260_pmod_j2.png` | Chân Pmod J2 của KV260: chân connector, net, chân FPGA, cổng SoC | FPGA, nạp board | sơ đồ AMD XTP682, `fpga/xilinx/kv260/kv260.xdc` |
| 20 | `20_vp_architecture.png` | Virtual Platform: initiator (C++ hoặc firmware `--fw`), `VP_Bus`, các target, phần chưa mô hình hóa | Virtual Platform | `vp/src/` |
| 21 | `21_fpga_testbed.png` | Testbed FPGA: top của DE2, KV260 và Artix-7, `SoC_Top`, nạp và kiểm | FPGA | `fpga/`, `docs/project/PPA_FPGA.md` |

## Quy ước hình

| Màu | Vai trò |
| --- | --- |
| Xanh lá | Lõi RISC-V |
| Tím | Bộ nhớ (ROM, RAM) |
| Cam | SHA-256, Secure DMA |
| Đỏ | Khối bảo mật (Boot_Verifier, tường lửa, đường lỗi) |
| Vàng | SYSCSR, Boot Guard, thế giới App |
| Xanh dương | Bus, ngoại vi |

Dây nét liền là đường dữ liệu hoặc điều khiển, nét đứt là ngắt, đường trả về hoặc chi tiết phụ. Trang 01 ghi "(Page NN)" dưới mỗi khối lớn để chỉ sang trang chi tiết.

## Tạo lại

Sơ đồ được sinh bằng script trong `gen/`, nên khi RTL đổi có thể sửa script rồi chạy lại:

```text
cd docs/diagrams/gen
python export.py            # ghi lại .drawio và 18 ảnh PNG (cần draw.io Desktop)
python export.py --no-png   # chỉ ghi .drawio
```

Biến môi trường `DRAWIO` đặt đường dẫn tới `draw.io.exe` nếu khác mặc định. Nếu sửa tay trong draw.io thì lần chạy `export.py` sau sẽ ghi đè, nên sửa trong script hoặc sao lưu bản sửa tay trước.

## Giới hạn

- Lưu đồ trang 11, 12, 16 bám `secure_boot.c` ở commit `dca8cbf` (Phát). Khi Phát đổi firmware cần đối chiếu lại.
- Số liệu trong sơ đồ (địa chỉ, mã `SB_*`, trạng thái FSM, 66 chu kỳ SHA) lấy từ file nguồn ở cột "Nguồn", không có số đo mới.
- Bố cục kiểm bằng ảnh xuất từ draw.io Desktop 29.6. Trang 03 và 15 có vài đường dây cắt nhau, chấp nhận được, kéo lại trong draw.io nếu cần.
