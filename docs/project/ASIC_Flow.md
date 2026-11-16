# Flow ASIC của HRoT_SoC

> Bản nháp 15/11/2026 (Nguyên). Người đọc: Nhóm trưởng và Phát, khi chạy và duyệt từng bước. Tiến độ từng bước theo tab "Flow ASIC" trong [Google Sheet](https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4/edit), khi hai nơi lệch nhau thì theo sheet.

## 1. Tóm tắt

- Flow gồm 11 bước, từ RTL tới báo cáo. Bước 1 và 2 đã chạy. Bước 3 tới 9 đã có script nháp, chưa chạy lần nào trên server. Bước 4 (GLS) có `make asic-gls` từ 16/11 (Phát, `94b25fc`).
- Tất cả script nháp dựa trên flow đã chạy thật của RV32i-SoC (đồ án CE434, cùng nhóm, cùng server và PDK GPDK45). Chúng chưa được kiểm trên HRoT_SoC.
- LEC (bước 3) chạy được ngay trên netlist hiện tại, vì bộ nhớ là hộp đen ở cả hai phía.
- Innovus (bước 5 tới 8) chưa chạy được cho tới khi có wrapper SRAM. Innovus không nhận hộp đen, và netlist còn 68 lệnh `assign` do chúng.
- Rủi ro chính: Số liệu ASIC hiện chưa có diện tích bộ nhớ, và `.gitignore` chặn mọi file tên bắt đầu bằng `sram_2k_macro` nên wrapper không được đặt tên như vậy.

## 2. Các bước

Công cụ trên server theo `docs/flow_notes.md` của RV32i-SoC: Genus và Innovus 21.1, Conformal_Asic 24.1 (không có Conformal_Ultra), Tempus và Voltus 23.1, Xcelium. Genus 21.10 theo `asic/README.md`.

| # | Bước | Lệnh | Đầu vào | Cổng nghiệm thu | Tình trạng |
| --- | --- | --- | --- | --- | --- |
| 1 | RTL, mô phỏng | `make test` | `rtl/`, `dv/` | `All checks passed`, 22/22 | Xong (13/11) |
| 2 | Tổng hợp | `make asic-genus` | `asic/ASIC_Top.v`, `asic/ASIC_Top.sdc` | Slack >= 0, 0 latch, 0 scan flop, 0 vi phạm design rule | Chạy 12/11, đạt từ 20 tới 8 ns. Còn 8 cell scan `SMDFFHQX1`, `synth.tcl` đã sửa (`ac43bf1`), chạy lại cùng lượt quét 7 và 6 ns |
| 3 | LEC | `make asic-lec` | RTL, netlist Genus | 0 non-equivalent, 0 abort, hộp đen chỉ là bộ nhớ | Script nháp |
| 4 | Mô phỏng netlist | `make asic-gls` | Netlist, mô hình cell, 3 file hex của `make fw` | `ASIC_Top_tb RESULT: PASS`, giống mô phỏng RTL | Script có từ 16/11, chưa chạy. Bộ nhớ dùng mô hình RTL nên không cần wrapper SRAM |
| 5 | Floorplan, nguồn | `make asic-innovus` | Netlist, SDC, LEF | `verifyGeometry` 0 lỗi | Script nháp |
| 6 | Placement | như trên | như trên | 0 cell chưa đặt, overflow dưới 0,5% | Script nháp |
| 7 | CTS | như trên | như trên | Skew <= 80 ps, hold >= 0 | Script nháp |
| 8 | Route, filler, kiểm tra | như trên | như trên | 0 DRC, 0 lỗi kết nối, 0 antenna | Script nháp |
| 9 | Signoff STA | `make asic-sta SPEF=... NETLIST=... SDC=...` | Netlist sau route, SPEF | Setup, hold, recovery, removal >= 0 | Script nháp |
| 10 | Công suất | Chưa có script | SPEF, activity | Số mW theo testcase | Chưa xác nhận Voltus chạy được. Bước kiểm Voltus ở `asic/README.md` (bước 4b) |
| 11 | Lưu kết quả | `make asic-lec-save`, `asic-pnr-save`, `asic-sta-save` | Report văn bản | Chỉ file văn bản, không file dựng từ PDK | Script nháp |

Nguồn của các cổng nghiệm thu bước 5 tới 8: `docs/flow_notes.md` mục 3 của RV32i-SoC.

## 3. Việc cần làm trước khi chạy Innovus

| Việc | Người | Ghi chú |
| --- | --- | --- |
| Viết wrapper SRAM cho `Data_Memory` và `Dual_Port_ROM` | Nguyên | Macro `sram_2k_macro` có 1 cổng đọc ghi và không có ghi theo byte, nên `SB` và `SH` phải đọc, sửa, ghi. `Q` ra ở chu kỳ sau, bit chọn macro phải chốt từ chu kỳ trước |
| Đọc wrapper và `.lib` của macro trong `asic/genus/synth.tcl`, đổi số bộ nhớ cần kiểm | Nguyên, Phát chạy | Hiện `N_MEM = 4` và `rtl/mem` không được đọc |
| Thêm file wrapper vào `MEM_RTL` của `asic/lec/run_lec.sh` | Nguyên | Chạy lại LEC |
| Chốt chu kỳ clock | Phát | Chờ quét 7 và 6 ns (P-20) |
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

- Chưa chạy: Mọi script bước 3 tới 11 chưa chạy trên server. Mỗi lần chạy đầu có thể lộ lỗi tên lệnh, vì tên đổi giữa các bản tool. Các lệnh phụ đều bọc `try_cmd` để chỉ báo cảnh báo.
- Đã kiểm ở nhà: Cú pháp bash, cân bằng ngoặc Tcl, cây lệnh `make -n`, và dofile LEC sinh ra đúng (46 file RTL, cùng danh sách với `synth.tcl`).
- Chưa quyết: DFT. RV32i-SoC cũng cấm scan flop và không làm DFT. Đề xuất giữ ngoài phạm vi, ghi vào báo cáo như một giới hạn.
- Bước 10 chưa có script, Voltus chưa xác nhận. Bước 4 có `make asic-gls` từ 16/11, chạy với mô hình RTL của bộ nhớ (thay hộp đen), chưa chạy trên server.

## 6. Cách chạy trên server

```bash
cd ~/HRoT_SoC && git pull
make asic-genus          # bước 2, đã chạy được
make asic-lec            # bước 3, chạy được trên netlist hiện tại
# sau khi có wrapper SRAM:
make asic-innovus        # bước 5 tới 8
make asic-sta            # bước 9 trước layout. Sau route: thêm SPEF=$PWD/asic/out_innovus/ASIC_Top.spef
make asic-lec-save asic-pnr-save asic-sta-save   # bước 11, rồi commit asic/reports
```

Trước khi commit, mở `asic/reports/lec/lec.txt` và kiểm đường dẫn: log có thể chứa tên người dùng trên server. Không dùng `git add -f`. Netlist, SPEF, SDF, GDS và cơ sở dữ liệu Innovus ở lại trong `asic/out_*`, git bỏ qua.

## 7. Danh sách TBD

| Mục | Ai quyết |
| --- | --- |
| Số macro (RAM 4 KB x 2, ROM hai cổng x 2: 4 tới 6 macro) | Nguyên, khi viết wrapper |
| Chu kỳ clock chính thức | Phát |
| Kích thước lõi | Phát |
| Voltus chạy được trên server không | Phát |
| DFT có đưa vào hay không | Nhóm trưởng |

## Lịch sử

| Ngày | Người | Thay đổi |
| --- | --- | --- |
| 15/11/2026 | Nguyên | Bản nháp đầu |
