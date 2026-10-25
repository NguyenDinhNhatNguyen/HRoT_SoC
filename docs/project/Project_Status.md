# Trạng thái dự án — HRoT SoC

> Cập nhật: 25/10/2026 (cuối Tuần 7, sau khi thêm TIMER0/WDT và cấu trúc lại repo). Tiến độ chi tiết theo từng việc nằm ở [Google Sheet "HRoT_SoC — Tiến độ Đồ án 2"](https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4/edit) (tab Tổng hợp, Tiến độ, Mốc & Giao diện). Sheet là nguồn chính thức, khi lệch thì theo sheet. File này tóm tắt trạng thái kỹ thuật, sửa mỗi khi xong một mốc hoặc chốt một quyết định.

## 1. Tổng quan

- Toàn dự án 30/60 việc (50%): Nguyên 21/36, Phát 9/22. Ngày 25/10 thêm 6 việc phát sinh (N-32…N-36, P-22), danh sách rủi ro và hướng xử lý ở `Project_Plan.md` mục 8. RTL FREEZE: **22/11/2026** (mốc M2).
- SoC biên dịch và chạy được: Master boot từ Boot ROM riêng, dùng SHA-256 phần cứng, đọc ROM App qua cổng B, nhả reset App qua SYSCSR. Bus APB đã có SYSCSR, UART0, GPIO0, TIMER0 và WDT. `SoC_Top_tb` hiện chỉ băm chuỗi "abc" (firmware thử `dv/sw/mkhex.py`), **chưa băm image App và chưa có kịch bản image bị sửa trên RTL** (VP đã có cả hai kịch bản).
- FPGA (25/10, sau khi thêm TIMER0/WDT): DE2 7.885 LE (24%), 135 Kbit M4K, Fmax 55,17 MHz. Artix-7 xc7a35t 3.360 LUT, WNS +2,891 ns @ 50 MHz. Báo cáo ở `fpga/reports/`.
- Firmware Secure Boot thật **chưa có**: `SoC_Top_tb` đang chạy firmware thử viết tay (`dv/sw/mkhex.py`), còn `fw/secure_boot/main.c` là code giả (việc P-13).

Kết quả kiểm tra gần nhất trên Questa (`make test`, 25/10):

| Nhóm | Kết quả |
| --- | --- |
| Lõi: chương trình ISA, `RISCV_Core_tb`, hazard | PASS |
| HAL SHA-256 trên host | PASS |
| Ngoại vi APB (SYSCSR, UART, GPIO, TIMER, WDT) | PASS, 42/42 check |
| SoC secure boot | PASS |
| VP (image đúng và image bị sửa) | PASS |
| `sha256_alias_test` (chạy riêng) | PASS |
| 11 TB đơn vị | FAIL trên Questa, chỉ 1/11 TB chạy. Phát đã sửa 25/10 (P-22), chờ chạy lại trên Questa |
| 4 test UVM trong `make test` | FAIL trên Questa vì `PH_TIMEOUT`. Phát đã sửa 25/10 (P-22), chờ chạy lại trên Questa |

Trên Verilator (Phát chạy, 23–25/10): UVM AXI4-Lite 15/15 PASS. UVM SHA-256 trên DUT thật: KAT, CTL (khoảng 960 check), RAND 40 message × 3 seed (khoảng 4.300–4.900 check), FULL, reset giữa message × 3, tất cả PASS, 0 lỗi.

## 2. Phần của Phát

| ID | Việc | Hạn | Trạng thái |
| --- | --- | --- | --- |
| P-01…P-06 | Lõi 5 tầng, hazard + test ISA, khung UVM, HAL + test plan, toolchain, load/store byte/half | ≤ 25/10 | ✅ Xong |
| P-07 | Sơ đồ khối datapath 5 tầng trong `docs/` | 13/09 | ✅ Vẽ từ Tuần 1, đưa vào repo 25/10: `docs/spec/Core_Datapath.md` + hình, có bảng đối chiếu RTL và 5 điểm nên sửa khi vẽ lại cho báo cáo (commit `fb0b577`) |
| P-08 | UVM sequence ngẫu nhiên cho SHA-256 (corner case) | 25/10 | ✅ Xong 25/10 (commit `bb59f25`). `sha256_alias_test` PASS sau khi Nguyên sửa RTL 25/10 |
| **P-09** | Zicsr + trap máy + cổng `irq_timer`/`irq_ext` | 01/11 | Chưa làm, **chặn việc nối ngắt TIMER0 vào lõi và N-19**, thuộc mốc M1. Cổng đã chốt (I-01). Thêm sau đó: access fault qua trap (`mcause` 5/7) với cổng `data_err` |
| P-10 | Dọn `dv/tb` sang `dv/env`, `dv/agents` | 01/11 | Chưa làm. Testbench của Nguyên đã chuyển sang `dv/tb/soc/` |
| P-11 | Driver UART/GPIO theo `SoC_Memory_Map.md` | 01/11 | Chưa làm (ngoại vi đã có) |
| P-12 | Cập nhật tài liệu này + `Dev_Guide.md`, thêm test của Phát vào `make test` | 01/11 | ✅ Xong (làm 24/10, vào `main` cùng commit P-08 `bb59f25`), sheet đã cập nhật 25/10 |
| P-22 | Sửa 2 lỗi script trên Questa 10.2c (mục 4) | 01/11 | Đã sửa 25/10 (commit `fb0b577`), kiểm trên Verilator, **chờ chạy `make test` trên Questa để đóng** |
| P-13 | Firmware secure boot thật (HAL + UART + golden + LOCK), chạy VP rồi RTL | 08/11 | Chờ P-11, I-03. Sau khi băm ROM App đọc `SYSCSR.BUS_ERR`: `VALID = 1` thì in log qua UART và giữ App trong reset, xong ghi 1 vào bit0 để xóa (N-36) |
| P-14 | Test assembly ngắt timer/external | 08/11 | Chờ P-09 (TIMER0 đã có) |
| P-15…P-17 | FW dùng Secure DMA · FW App + `app_firmware.hex` + sinh golden hash · UVM agent APB + scoreboard SHA (DPI) | 15/11 | Chưa làm |
| P-18…P-21 | Test toàn SoC + regression UVM · coverage · Genus · Innovus + so sánh PPA | 22/11 → 13/12 | Chưa làm |

## 3. Giao diện Nguyên ↔ Phát

| ID | Nội dung | Hạn | Trạng thái |
| --- | --- | --- | --- |
| I-01 | Cổng ngắt của lõi: `irq_timer`, `irq_ext`: đầu vào mức cao, đồng bộ `clk`, giữ mức tới khi nguồn tự xóa (TIMER0: ghi `mtimecmp`, PLIC: claim/complete), lõi không bắt cạnh → `mip.MTIP` (bit 7) / `mip.MEIP` (bit 11), ưu tiên MEI > MTI. Dự trữ cho sau P-09: `data_err` mức cao cùng chu kỳ với `resp_valid` (nối `err_valid` của `AXI4_Lite_Master`) → access fault `mcause` 5 (load) / 7 (store), `mtval` = địa chỉ | 01/11 | ✅ **Đã chốt 25/10** (Phát). Phía SoC nối `timer0_irq` → `irq_timer` khi có P-09 |
| I-02 | Header địa chỉ firmware theo `SoC_Memory_Map.md`, đổi map phải báo trước | 01/11 | Nguyên |
| I-03 | Địa chỉ golden hash trong Boot ROM (cổng đọc dữ liệu) + đổi `linker.ld` đặt `.rodata` vào đó | 08/11 | Cả hai |
| I-04 | Target CMake `app_firmware.hex` + bước sinh golden hash (băm **cả 4 KB** ROM App) | 15/11 | Phát |
| I-05 | SHA-256: 66 chu kỳ START→DONE, offset trống OKAY/0, ngoài slave DECERR | — | ✅ Đã chốt, RTL đã khớp từ 25/10 |
| I-06 | UART `BAUD_DIV` mặc định 26 = 115200 baud @ 50 MHz | — | ✅ Đã chốt |
| I-07 | Chỉ commit trên `main`, chạy trong WSL, mô phỏng Questa, `make test` PASS trước khi push | — | ✅ Đã chốt |

Các lỗi SoC/uncore liệt kê ở bản trước (SoC không compile, Master fetch ROM App, ROM đọc đồng bộ, `bus_stall` trễ, thiếu WSTRB, SHA chưa băm, Reset Controller treo, VP thiếu `sc_main`…) **đều đã được Nguyên sửa** trong các commit `459f4fe`…`bb8288a`.

## 4. Điểm cần lưu ý

- **Việc mới của Nguyên (25/10):** N-33 VP băm cả 4 KB ROM App (I-04), N-34 header `fw/hal/soc_map.h` (I-02), N-32 VP thêm UART0/TIMER0/WDT cho firmware P-13, N-35 `SoC_Top_tb` băm image App và thêm kịch bản image bị sửa trên RTL, N-36 báo lỗi bus AXI cho firmware qua `SYSCSR.BUS_ERR`. N-33, N-34, N-36 đã xong 25/10 (N-36: commit `d2315b2`, APB 49/49, DE2 8.011 LE, 54,69 MHz). N-19, N-20, N-21 kéo lên làm từ 26/10. N-18 xong: 52/52 chân trong `fpga/intel_de2/de2_pins.tcl` khớp bảng chân của DE2 User Manual v1.3.
- **Cấu trúc repo đổi từ 25/10:** `doc/` thành `docs/` (chia `spec`, `verification`, `guides`, `project`), `rtl/uncore/` tách thành `rtl/bus`, `rtl/periph`, `rtl/mem`, `rtl/crypto`, `syn/` thành `fpga/` (thêm `fpga/reports`), `mkhex.py` sang `dv/sw/`. Phải `git pull` trước khi sửa tiếp.
- **Lỗi RTL SHA-256 (P-08 phát hiện), đã sửa 25/10:** `SHA256_Wrapper` chỉ giải mã `addr[7:0]` trong khi `SoC_Top` cấp cửa sổ 64 KB, nên offset ≥ `0x100` bị alias vào thanh ghi thật. Wrapper giờ giải mã `addr[15:8] == 0`, `sha256_alias_test` PASS trên Questa (chạy với `+TEST_TIMEOUT_US=100000000`, xem mục dưới).
- **Ba lỗi khi chạy trên Questa 10.2c (Nguyên phát hiện 25/10, trên Verilator không gặp). Lỗi 1 và 2 Phát đã sửa 25/10, chờ chạy lại trên Questa:**
  1. Timeout UVM tính bằng `time'(real'(tmo_us) * 1us)` trong `dv/tests/base_test.svh` ra 1,6 µs thay vì 1600 µs, do lệch timescale giữa package và `uvm_pkg`. 4 test UVM trong `make test` chết vì `PH_TIMEOUT`.
  2. `vsim -onfinish stop` trong `sim/run_unit.do` làm macro dừng sau `ALU_tb` ở chế độ `-c`, chỉ 1/11 TB chạy. Chạy `make test` trong terminal thì Questa đứng chờ ở dấu nhắc `VSIM(paused)>` và cả regression bị treo. Tạm thời chạy `make test < /dev/null`.
     Cách sửa (25/10): `base_test.svh` bỏ `uvm_top.set_timeout()` (đối số bị đọc theo đơn vị thời gian của `uvm_pkg`, trên Questa là 1 ps theo `-t 1ps`) và dùng watchdog `#(timeout_us * 1us)` ngay trong package của test nên luôn đúng đơn vị. `regress.sh` chạy mỗi TB đơn vị bằng một tiến trình `vsim` riêng (`set UNIT <tb>`, cùng kiểu với `run_rtl.do`) và mọi lệnh `vsim` đọc stdin từ `/dev/null` nên không còn treo ở `VSIM(paused)>`.
  3. (Đã sửa, phía Nguyên) `sim/run_vp.sh` trước đây chỉ tìm thư viện ở `$SYSTEMC_HOME/lib-linux64`, nên link lỗi khi `SYSTEMC_HOME` trỏ tới bản 2.3.4 (thư viện nằm trong `lib/`). Script giờ thử cả hai.
- **Comment và chuỗi in ra của testbench viết bằng tiếng Anh** từ 25/10. File của Nguyên đã đổi, file của Phát đổi hết ngày 25/10 (commit `fb0b577`).
- **VP băm cả 4 KB ROM App** theo I-04 từ 25/10 (N-33, commit `a946e2a`).
- **Bộ nhớ đọc ở cạnh xuống** chạy tốt trên FPGA nhưng không hợp với SRAM macro khi làm ASIC (P-20/P-21). Cần phương án: thêm 1 tầng chờ ở IF/MEM, hoặc dùng flip-flop cho bộ nhớ nhỏ.
- **Golden hash đang nằm trong RAM ghi được** cho tới khi có cổng đọc dữ liệu Boot ROM (N-21, I-03).
- **Xuống dòng:** `.gitattributes` ép LF cho `*.sh`, `Makefile`, `*.tcl`. Nên thêm `* text=auto eol=lf` để file `.v/.sv/.c/.md` không bị đổi qua lại LF↔CRLF giữa hai máy.
- **WSL của Phát** chưa có `make`, `gcc`, toolchain RISC-V: cần cài trước khi chạy `make test` / `make fw`.

## 5. Lỗ hổng so với lộ trình Tuần 16

- Kiểm chứng secure boot mức SoC với firmware thật: image đúng → nhả App, ROM bị sửa → giữ reset, lõi SHA hỏng → selftest bắt được. Hiện `SoC_Top_tb` mới kiểm image đúng, VP kiểm cả đúng và bị sửa.
- Hạ tầng coverage (P-19): covergroup, `+cover`, `vcover merge`, báo cáo. Monitor UVM cần ghi thời điểm và thứ tự AW–W.
- GLS (P-20): `RISCV_Core_prog_tb` dùng lại được (bọc phần dump thanh ghi bằng `ifndef GLS`), `RISCV_Core_tb` chỉ chạy RTL.
