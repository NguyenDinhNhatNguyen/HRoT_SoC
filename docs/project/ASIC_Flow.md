# Flow ASIC của HRoT_SoC

> Bản nháp 15/11/2026 (Nguyên). Người đọc: Nhóm trưởng và Phát, khi chạy và duyệt từng bước. Tiến độ từng bước theo tab "Flow ASIC" trong [Google Sheet](https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4/edit), khi hai nơi lệch nhau thì theo sheet.

## 1. Tóm tắt

- Flow gồm 11 bước, từ RTL tới báo cáo. Bước 1 tới 4 đã chạy và đạt (Genus, LEC, GLS trên server 18/11, kết quả ở `asic/README.md` mục "Kết quả buổi chạy 18/11/2026"). Bước 5 tới 11 có script nháp, chưa chạy lần nào trên server.
- Tất cả script nháp dựa trên flow đã chạy thật của RV32i-SoC (đồ án CE434, cùng nhóm, cùng server và PDK GPDK45). Chúng chưa được kiểm trên HRoT_SoC.
- LEC (bước 3) chạy được ngay trên netlist hiện tại, vì bộ nhớ là hộp đen ở cả hai phía.
- Hai RAM 4 KB có wrapper SRAM (phase 1) và hai ROM 4 KB là logic sinh từ file hex (phase 2), cả hai từ 16/11. Bật bằng `make asic-genus SRAM=1 ROM=1`. Chạy trên server 18/11: 2 macro, 0 hộp đen, 0 `assign`, 101.597 µm², LEC và GLS PASS. ROM logic 12.204 µm².
- Innovus (bước 5 tới 8) dùng netlist `SRAM=1 ROM=1` ở 11 ns, chu kỳ Phát chốt 18/11. Netlist trên server đang ở 20 ns, phải chạy lại Genus trước.
- Rủi ro chính: Số liệu ASIC hiện chưa có diện tích bộ nhớ, và `.gitignore` chặn mọi file tên bắt đầu bằng `sram_2k_macro` nên wrapper không được đặt tên như vậy.

## 2. Các bước

Công cụ trên server theo `docs/flow_notes.md` của RV32i-SoC: Genus và Innovus 21.1, Conformal_Asic 24.1 (không có Conformal_Ultra), Tempus và Voltus 23.1, Xcelium. Genus 21.10 theo `asic/README.md`.

| # | Bước | Lệnh | Đầu vào | Cổng nghiệm thu | Tình trạng |
| --- | --- | --- | --- | --- | --- |
| 1 | RTL, mô phỏng | `make test` | `rtl/`, `dv/` | `All checks passed`, 22/22 | Xong (13/11) |
| 2 | Tổng hợp | `make asic-genus` | `asic/ASIC_Top.v`, `asic/ASIC_Top.sdc` | Slack >= 0, 0 latch, 0 scan flop, 0 vi phạm design rule | Xong 18/11: 0 scan flop, đạt từ 20 tới 6 ns cho cả hai netlist, chốt 11 ns |
| 3 | LEC | `make asic-lec` | RTL, netlist Genus | 0 non-equivalent, 0 abort, hộp đen chỉ là bộ nhớ | Xong 18/11: PASS cả hai netlist, sau khi `synth.tcl` thêm `optimize_constant_feedback_seqs false` |
| 4 | Mô phỏng netlist | `make asic-gls` | Netlist, mô hình cell, 3 file hex của `make fw` | `ASIC_Top_tb RESULT: PASS`, giống mô phỏng RTL | Xong 18/11: PASS cả hai netlist, boot 535.898 chu kỳ như RTL, bản `SRAM=1 ROM=1` dùng mô hình macro của trường |
| 5 | Floorplan, nguồn | `make asic-innovus` | Netlist, SDC, LEF | `verifyGeometry` 0 lỗi | Script nháp |
| 6 | Placement | như trên | như trên | 0 cell chưa đặt, overflow dưới 0,5% | Script nháp |
| 7 | CTS | như trên | như trên | Skew <= 80 ps, hold >= 0 | Script nháp |
| 8 | Route, filler, kiểm tra | như trên | như trên | 0 DRC, 0 lỗi kết nối, 0 antenna | Script nháp |
| 9 | Signoff STA | `make asic-sta SPEF=... NETLIST=... SDC=...` | Netlist sau route, SPEF | Setup, hold, recovery, removal >= 0 | Script nháp |
| 10 | Công suất | Chưa có script | SPEF, activity | Số mW theo testcase | Voltus v23.14 có license (18/11), chưa có script |
| 11 | Lưu kết quả | `make asic-lec-save`, `asic-pnr-save`, `asic-sta-save` | Report văn bản | Chỉ file văn bản, không file dựng từ PDK | Script nháp |

Nguồn của các cổng nghiệm thu bước 5 tới 8: `docs/flow_notes.md` mục 3 của RV32i-SoC.

## 3. Việc cần làm trước khi chạy Innovus

| Việc | Người | Ghi chú |
| --- | --- | --- |
| Wrapper SRAM cho hai RAM (`master_ram`, `app_ram`) | Nguyên | Xong 16/11, phase 1. `rtl/mem/RAM_Macro_Axi.v` (sau AXI, không cần chờ) và `RAM_Macro_Core.v` (lõi App chờ bằng `bus_stall`, I-09). Chọn bằng `` `define SRAM_MACRO ``, mặc định tắt. Macro `sram_2k_macro` có 1 cổng đọc ghi, không ghi theo byte nên `SB`, `SH` đọc rồi ghi lại, `Q` ra sau 1 chu kỳ |
| Genus đọc wrapper, ROM logic và `.lib` của macro | Nguyên viết, Phát chạy | `make asic-genus SRAM=1 ROM=1`: không còn hộp đen, kiểm đúng 2 instance `sram_2k_macro`. Chưa chạy trên server. Cách đặt `` `define `` bằng file đầu tiên trong cùng một lệnh `read_hdl` chưa kiểm trên server. Bài trên diễn đàn Cadence báo cách này chạy được, và `read_hdl -define {tên}` cũng có (chưa thấy tài liệu chính thức), nên nếu lỗi thì thử `-define` sau khi xem `help read_hdl` |
| LEC với wrapper và ROM logic | Nguyên viết, Phát chạy | `make asic-lec SRAM=1 ROM=1` (cùng hex với lần chạy Genus), macro là hộp đen ở cả hai phía |
| Hai ROM 4 KB (`boot_rom`, `app_rom`) | Nguyên | Xong 16/11, phase 2. SRAM macro không có nội dung firmware, nên ROM là logic: `fw/tools/gen_rom_v.py` sinh `build/rom/rom_images.v` từ hex (`make rom-images`), `rtl/mem/ROM_Logic.v` thay `Dual_Port_ROM` bằng `` `define ROM_LOGIC ``. Mỗi cổng đọc là một bản tra cứu riêng, đọc tổ hợp. Firmware cố định trong netlist: đổi firmware thì chạy lại `make rom-images` và Genus |
| Chốt chu kỳ clock | Phát | Xong 18/11: 11 ns, mặc định của `synth.tcl`. Netlist trong `asic/out_genus/` trên server phải chạy lại `make asic-genus SRAM=1 ROM=1` ở 11 ns trước Innovus |
| Chốt kích thước lõi | Phát | Đặt `CORE_W` và `CORE_H`, hoặc để `UTIL` mặc định 0,60 trong `asic/pnr/floorplan.tcl` |

Lưu ý khi đặt tên file wrapper: `.gitignore` chặn `sram_2k_macro*`, `*.lib`, `*.lef`, `*_netlist.v` và `*_pnr.v`. Một file tên `sram_2k_macro_wrap.v` sẽ không lên repo mà không báo lỗi.

## 4. Điểm đã biết từ RV32i-SoC

| Điểm | Xử lý trong script |
| --- | --- |
| `BUFX2` cao gấp đôi, `CLKBUFX2` vi phạm khoảng cách chân. Cấm muộn thì `place_opt_design` chèn 1.220 cell `CLKBUFX2` | Cấm ngay sau `init_design` |
| Hold sau CTS sát 0 làm removal của cây reset chỉ dư 6 ps | `setOptMode -holdTargetSlack 0.020` |
| Hold và removal chỉ báo ở chế độ hold, nếu không thì ghi `n/a` | Hàm `slack_reports` đổi chế độ khi đo |
| `ecoRoute -fix_drc` không kèm vùng thì báo sai | Hàm `fix_drc_boxes` đọc `Bounds` từ `drc.rpt` |
| LEC với macro: hộp đen phải khai báo trước `read design`. Netlist có clock gating nên cần `set flatten model -gated_clock` | Có trong `asic/lec/run_lec.sh` |
| Tempus sau route cần đường dẫn tuyệt đối | Ghi trong `asic/sta/sta.tcl` |
| Macro chỉ có `.lib` corner typical | Cả hai view dùng chung file, report ghi đường qua macro hơi lạc quan |
| Không cần GDS và CDL của macro (giảng viên, 22/10) | GDS chỉ có phần Innovus vẽ, vùng macro để trống, phải ghi trong báo cáo |

## 5. Giới hạn của bản nháp

- Chưa chạy: Script bước 5 tới 11 chưa chạy trên server (bước 3 và 4 chạy 18/11). Mỗi lần chạy đầu có thể lộ lỗi tên lệnh, vì tên đổi giữa các bản tool. Các lệnh phụ đều bọc `try_cmd` để chỉ báo cảnh báo.
- Đã kiểm ở nhà: Cú pháp bash, cân bằng ngoặc Tcl, cây lệnh `make -n`, và dofile LEC sinh ra đúng (46 file RTL, cùng danh sách với `synth.tcl`).
- Chưa quyết: DFT. RV32i-SoC cũng cấm scan flop và không làm DFT. Đề xuất giữ ngoài phạm vi, ghi vào báo cáo như một giới hạn.
- Wrapper SRAM (16/11): `make sim-ram` kiểm hai wrapper với mảng tham chiếu (khoảng 15.600 phép kiểm, 0 lỗi, phá thử 5 kiểu lỗi trong wrapper đều bị bắt). `make test` chạy thêm `SoC_Top_tb` và `SoC_Fw_tb` (ảnh đúng, ảnh sửa, access fault) và `ASIC_Top_tb` với RAM là macro. Mô hình macro là của nhóm (`dv/models/sram_macro_model.v`), hành vi macro thật (thời gian truy cập, `Q` khi ghi) chưa biết, `make asic-macro-info` sẽ cho. Firmware thật của lõi App không đọc RAM, nên phá `stall` của `RAM_Macro_Core` thành 0 thì các test SoC vẫn PASS. Chỗ hở này đóng bằng `RAM_Core_ISA_tb`: lõi chạy `core_isa_test` (mọi lệnh load và store) trên `RAM_Macro_Core`, có và không có `bus_stall`, `instr_stall` ngẫu nhiên. Phá `stall` thì test này FAIL. ROM logic: `ROM_Logic_tb` so từng từ của hai ROM với file hex (khoảng 86.000 phép kiểm), và `ASIC_Top_tb` boot qua ROM logic. Sai 1 bit trong ảnh App ROM hoặc trong hash vàng của Boot ROM thì `ASIC_Top_tb` FAIL.
- Bước 10 chưa có script, Voltus v23.14 có license (18/11). Bước 4 (`make asic-gls`) chạy 18/11 cho cả hai netlist.

## 6. Cách chạy trên server

```bash
cd ~/HRoT_SoC && git pull --rebase
# fw/build/*.hex và build/rom/rom_images.v phải có sẵn (chép từ máy nhà, hoặc make rom-images)
make asic-genus SRAM=1 ROM=1   # bước 2, 11 ns mặc định, không còn hộp đen
make asic-lec SRAM=1 ROM=1     # bước 3
make asic-gls                  # bước 4
make asic-innovus        # bước 5 tới 8
make asic-sta            # bước 9 trước layout. Sau route: thêm SPEF=$PWD/asic/out_innovus/ASIC_Top.spef
make asic-lec-save asic-pnr-save asic-sta-save   # bước 11, rồi commit asic/reports
```

Trước khi commit, mở `asic/reports/lec/lec.txt` và kiểm đường dẫn: log có thể chứa tên người dùng trên server. Không dùng `git add -f`. Netlist, SPEF, SDF, GDS và cơ sở dữ liệu Innovus ở lại trong `asic/out_*`, git bỏ qua.

## 7. Danh sách TBD

| Mục | Ai quyết |
| --- | --- |
| Diện tích và thời gian của ROM logic (đường lấy lệnh dài hơn). Nếu quá lớn thì cân nhắc rút gọn firmware hoặc dùng lại macro cho ROM | Phát đo bằng Genus, Nguyên quyết |
| Chu kỳ clock chính thức | Phát |
| Kích thước lõi | Phát |
| Voltus chạy được trên server không | Phát |
| DFT có đưa vào hay không | Nhóm trưởng |

## Lịch sử

| Ngày | Người | Thay đổi |
| --- | --- | --- |
| 15/11/2026 | Nguyên | Bản nháp đầu |
| 16/11/2026 | Nguyên | Wrapper SRAM cho hai RAM (phase 1), `SRAM=1` cho Genus và LEC |
| 16/11/2026 | Nguyên | Hai ROM thành logic từ file hex (phase 2), `ROM=1`, test lõi chạy ISA trên RAM macro |
