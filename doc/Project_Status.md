# Trạng thái dự án — HRoT SoC

> Cập nhật: 2026-10-23 (cuối Tuần 6). Sửa file này mỗi khi xong một mốc hoặc chốt một quyết định.

## 1. Phần của Phát — Tuần 1–6

| Tuần | Việc | Trạng thái |
|---|---|---|
| 1 | Sơ đồ khối datapath 5 tầng | ❌ Chưa có trong `doc/` |
| 1–3 | 4 thanh ghi pipeline, RTL IF/ID/EX/MEM/WB, ghép lõi | ✅ TB đơn vị PASS hết |
| 4 | Forwarding + Hazard tích hợp, test assembly | ✅ `core_isa_test.S` (40 CHECK), chạy cả khi `bus_stall` ngẫu nhiên |
| 4 | Nghiệm thu lõi trên QuestaSim | ⚠️ Mới chạy iverilog, chưa chạy Questa |
| 5 | Khung UVM AXI4-Lite | ✅ 15/15 PASS trên Verilator (kể cả reset giữa giao dịch) |
| 6 | HAL SHA-256 + Test plan UVM | ✅ 9.692 test host PASS, khớp `sha256sum`, build rv32i sạch |
| — | Toolchain firmware (CMake, linker, crt0) | ✅ Chương trình C thật chạy đúng trên lõi |

Kết quả kiểm tra gần nhất: TB đơn vị ALU 25 · Branch 16 · Control 28 · EX 8 · Extend 14 · ID 26 · IF_ID 9 · IF 10 · MEM 23 · RegFile 38 · WB 108 — tất cả FAIL = 0; `RISCV_Core_tb` 44/44; chương trình ISA PASS (có/không stall).

## 2. Đang chờ Nguyên (SoC chưa compile được)

1. `SoC_Top.v`: thiếu `endmodule`; các wire `master_data_*`, `M_AXI_*` chưa khai báo (thành 1-bit ngầm); instantiate `SHA256_Core` thay vì `SHA256_Wrapper`; không có cổng output (Vivado sẽ tối ưu bỏ hết).
2. Master Core đang fetch lệnh từ cổng B của ROM App → Master chạy code của App. Cần ROM boot riêng cho Master; cổng B làm AXI slave (base ≠ 0, HAL từ chối địa chỉ 0).
3. `Dual_Port_ROM` đọc đồng bộ, lõi cần đọc tổ hợp (xem `Dev_Guide.md` mục 2).
4. `bus_stall = ~req_ready` trễ 1 chu kỳ → load nhận dữ liệu cũ. Cần stall tổ hợp: `(data_re | data_we) & ~resp_valid`.
5. AXI master chưa có WSTRB (lõi đã xuất `data_wstrb`); `Data_Memory` cần ghi theo byte và đang compile lỗi (`read_data` gán 2 nơi).
6. `SHA256_Core/Wrapper` mới là khung: chưa có vòng nén, `start` chỉ 1 xung, `DONE` không sticky, chỉ 1/16 word block và 1/8 word hash, thiếu kênh B và các READY. Danh sách chi tiết: `SHA256_Register_Map.md`.
7. Reset Controller không trả `AWREADY` → ghi vào `0x4000_0000` treo Master.
8. `AXI4_Lite_Slave_Template.v`: `S_AXI_BRESP/RRESP` chưa khai báo.
9. RTL đọc `../fw/firmware.txt` và `app_firmware.hex`; build hiện xuất `firmware_imem.hex` + `firmware_dmem.hex`.
10. VP: chỉ có 2 file `.h`, không có `sc_main` → `sim/run_vp.sh` không chạy được.

## 3. Quyết định cần chốt với Nguyên

- Bản đồ bộ nhớ (đề xuất ở `Dev_Guide.md` mục 3), đặc biệt RAM `0x1000_0000` và base của ROM App trên bus Master.
- Golden hash đặt ở đâu: hiện hằng số nằm trong RAM ghi được (lõi Harvard). Hướng: map boot ROM lên bus dữ liệu (chỉ đọc), hoặc nhúng hash vào lệnh.
- Băm toàn bộ 4 KB ROM App (khuyến nghị) hay chỉ độ dài image.
- Truy cập ngoài map SHA-256: `OKAY`+0 hay `SLVERR`; độ trễ một khối (64 hay 65–66 chu kỳ).
- Full SoC: UVM chỉ theo dõi thụ động bus nội bộ, hay thêm cổng master để bơm nhiễu (Tuần 10).

## 4. Tuần 7 — làm được ngay khi chờ RTL SHA-256

- [ ] Chạy `run_rtl.do` và `run_uvm.do` trên QuestaSim; vẽ sơ đồ datapath vào `doc/`.
- [ ] Golden model DPI bọc `fw/hal/test/sha256_ref.c`; tách vector KAT ra header dùng chung UVM + firmware.
- [ ] Slave SHA-256 mô hình hành vi đúng hợp đồng `SHA256_Register_Map.md` để chạy test trước khi có RTL.
- [ ] `sha256_reg_model`, `sha256_scoreboard`, `sha256_hash_seq`, `sha256_rand_seq` theo test plan.
- [ ] Monitor ghi thời điểm/thứ tự AW–W (cần cho coverage Tuần 11); script regression nhiều seed.

## 5. Lỗ hổng so với lộ trình Tuần 16 (chưa có trong plan)

- Kiểm chứng Secure Boot mức SoC: image đúng → nhả reset App; ROM bị sửa → App bị giữ reset; lõi SHA hỏng → selftest bắt được.
- Hạ tầng coverage: covergroup, `+cover`, `vcover merge`, báo cáo.
- Build firmware App + bước sinh golden hash tự động trước khi build Master; `soc_map.h` làm nguồn địa chỉ duy nhất.
- GLS (Tuần 13–14): `RISCV_Core_prog_tb` dùng lại được (bọc phần dump thanh ghi bằng `ifndef GLS`); `RISCV_Core_tb` chỉ chạy RTL.
