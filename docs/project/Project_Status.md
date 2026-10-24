# Trạng thái dự án — HRoT SoC

> Cập nhật: 2026-10-24 (Tuần 7, sau commit `bb8288a`). Tiến độ chi tiết theo từng việc nằm ở [Google Sheet "HRoT_SoC — Tiến độ Đồ án 2"](https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4/edit) (tab Tổng hợp / Tiến độ / Mốc & Giao diện) — sheet là nguồn chính thức, khi lệch thì theo sheet; file này tóm tắt trạng thái kỹ thuật. Sửa mỗi khi xong một mốc hoặc chốt một quyết định.

## 1. Tổng quan

- Toàn dự án 20/54 việc (37%): Nguyên 14/31, Phát 6/21. RTL FREEZE: **22/11/2026** (mốc M2).
- SoC biên dịch và chạy được: Master boot từ Boot ROM riêng, dùng SHA-256 phần cứng, đọc ROM App qua cổng B, nhả reset App qua SYSCSR. `SoC_Top_tb` hiện chỉ băm chuỗi "abc" (firmware thử `dv/tests/mkhex.py`), **chưa băm image App và chưa có kịch bản image bị sửa trên RTL** (VP đã có cả hai kịch bản). FPGA: DE2 7.453 LE, Fmax 54,9 MHz @ 50 MHz; Artix-7 WNS > +3 ns.
- Firmware Secure Boot thật **chưa có**: `SoC_Top_tb` đang chạy firmware thử viết tay (`dv/tests/mkhex.py`); `fw/secure_boot/main.c` là code giả (việc P-13).

Kết quả kiểm tra gần nhất (iverilog, 24/10): 11 TB đơn vị FAIL = 0 · `RISCV_Core_tb` 44/44 · chương trình ISA PASS (có/không stall) · hazard 0 lỗi · APB 28/28 · SoC secure boot PASS · HAL 9.692 PASS · build firmware OK. UVM 15/15 PASS trên Verilator (23/10). UVM SHA-256 trên DUT thật (25/10, Verilator): KAT, CTL (khoảng 960 check), RAND 40 message × 3 seed (khoảng 4.300–4.900 check), FULL, reset giữa message × 3 — tất cả PASS, 0 lỗi. VP: Nguyên báo PASS (cần SystemC).

## 2. Phần của Phát

| ID | Việc | Hạn | Trạng thái |
|---|---|---|---|
| P-01…P-06 | Lõi 5 tầng, hazard + test ISA, khung UVM, HAL + test plan, toolchain, load/store byte/half | ≤ 25/10 | ✅ Xong |
| **P-07** | Sơ đồ khối datapath 5 tầng trong `doc/` | 13/09 | ❌ **Quá hạn** |
| P-08 | UVM sequence ngẫu nhiên cho SHA-256 (corner case) | 25/10 | ✅ Xong 25/10 (chưa commit): `sha256_full_test` PASS, reset giữa message PASS (3 thời điểm). `sha256_alias_test` FAIL do lỗi RTL (mục 4) |
| **P-09** | Zicsr + trap máy + cổng `irq_timer`/`irq_ext` | 01/11 | Chưa làm — **chặn N-15, N-19**, thuộc mốc M1 |
| P-10 | Dọn `dv/tb` sang `dv/env`, `dv/agents` | 01/11 | Chưa làm |
| P-11 | Driver UART/GPIO theo `SoC_Memory_Map.md` | 01/11 | Chưa làm (ngoại vi đã có) |
| P-12 | Cập nhật tài liệu này + `Dev_Guide.md`; thêm test của Phát vào `make test` | 01/11 | ✅ Xong 24/10 |
| P-13 | Firmware secure boot thật (HAL + UART + golden + LOCK), chạy VP rồi RTL | 08/11 | Chờ P-11, I-03 |
| P-14 | Test assembly ngắt timer/external | 08/11 | Chờ P-09, N-15 |
| P-15…P-17 | FW dùng Secure DMA · FW App + `app_firmware.hex` + sinh golden hash · UVM agent APB + scoreboard SHA (DPI) | 15/11 | Chưa làm |
| P-18…P-21 | Test toàn SoC + regression UVM · coverage · Genus · Innovus + so sánh PPA | 22/11 → 13/12 | Chưa làm |

## 3. Giao diện Nguyên ↔ Phát

| ID | Nội dung | Hạn | Trạng thái |
|---|---|---|---|
| I-01 | Cổng ngắt của lõi (đề xuất `irq_timer`, `irq_ext` mức cao → `mip.MTIP`/`mip.MEIP`) | 01/11 | **Phát chủ trì**, chưa chốt |
| I-02 | Header địa chỉ firmware theo `SoC_Memory_Map.md`; đổi map phải báo trước | 01/11 | Nguyên |
| I-03 | Địa chỉ golden hash trong Boot ROM (cổng đọc dữ liệu) + đổi `linker.ld` đặt `.rodata` vào đó | 08/11 | Cả hai |
| I-04 | Target CMake `app_firmware.hex` + bước sinh golden hash (băm **cả 4 KB** ROM App) | 15/11 | Phát |
| I-05 | SHA-256: 66 chu kỳ START→DONE; offset trống OKAY/0; ngoài slave DECERR | — | ✅ Đã chốt |
| I-06 | UART `BAUD_DIV` mặc định 26 = 115200 baud @ 50 MHz | — | ✅ Đã chốt |
| I-07 | Chỉ commit trên `main`, chạy trong WSL, mô phỏng Questa, `make test` PASS trước khi push | — | ✅ Đã chốt |

Các lỗi SoC/uncore liệt kê ở bản trước (SoC không compile, Master fetch ROM App, ROM đọc đồng bộ, `bus_stall` trễ, thiếu WSTRB, SHA chưa băm, Reset Controller treo, VP thiếu `sc_main`…) **đều đã được Nguyên sửa** trong các commit `459f4fe`…`bb8288a`.

## 4. Điểm cần lưu ý

- **Lỗi RTL SHA-256 (P-08 phát hiện, chờ Nguyên):** `SHA256_Wrapper` chỉ giải mã `addr[7:0]` trong khi `SoC_Top` cấp cửa sổ 64 KB, nên offset ≥ `0x100` bị alias vào thanh ghi thật — đọc `0x144`/`0xFF44` ra STATUS, `0x150` ra HASH0, ghi `0x100+` làm hỏng BLOCK. Trái I-05 (offset trống OKAY/0). Tái hiện: `sha256_alias_test`.

- **VP băm theo độ dài image** (`cpu.app_len`), còn I-04 chốt băm cả 4 KB ROM App — cần thống nhất trước P-13/P-16.
- **Bộ nhớ đọc ở cạnh xuống** chạy tốt trên FPGA nhưng không hợp với SRAM macro khi làm ASIC (P-20/P-21): cần phương án (thêm 1 tầng chờ ở IF/MEM, hoặc dùng flip-flop cho bộ nhớ nhỏ).
- **Golden hash đang nằm trong RAM ghi được** cho tới khi có cổng đọc dữ liệu Boot ROM (N-21, I-03).
- **Xuống dòng:** `.gitattributes` mới ép LF cho `*.sh`, `Makefile`, `*.tcl`. Nên thêm `* text=auto eol=lf` để file `.v/.sv/.c/.md` không bị đổi qua lại LF↔CRLF giữa hai máy.
- **WSL của Phát** chưa có `make`, `gcc`, toolchain RISC-V: cần cài trước khi chạy `make test` / `make fw`.

## 5. Lỗ hổng so với lộ trình Tuần 16

- Kiểm chứng secure boot mức SoC với firmware thật: image đúng → nhả App; ROM bị sửa → giữ reset; lõi SHA hỏng → selftest bắt được (hiện `SoC_Top_tb` mới kiểm image đúng; VP kiểm cả đúng và bị sửa).
- Hạ tầng coverage (P-19): covergroup, `+cover`, `vcover merge`, báo cáo; monitor UVM cần ghi thời điểm/thứ tự AW–W.
- GLS (P-20): `RISCV_Core_prog_tb` dùng lại được (bọc phần dump thanh ghi bằng `ifndef GLS`); `RISCV_Core_tb` chỉ chạy RTL.
