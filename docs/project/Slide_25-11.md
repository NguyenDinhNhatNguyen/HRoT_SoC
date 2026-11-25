# Nội dung slide báo cáo 25/11/2026

> Bản nháp 21/11/2026 (Nguyên). Phạm vi theo ý Nguyên: RTL, PPA và các bài test đã đạt, kèm một slide ngắn về hướng tiếp theo. Đổ nội dung vào template khi có. Hình lấy từ `docs/diagrams/png/`. Mọi số có nguồn, giải thích chi tiết ở `docs/guides/Hieu_Do_An.md`.

## Slide 1. Đề tài và phạm vi báo cáo

- Thiết kế SoC RISC-V hai lõi bất đối xứng, có cách ly vật lý và khởi động an toàn (Hardware Root of Trust).
- Mục tiêu: lõi App chỉ chạy khi phần cứng xác thực firmware của nó bằng SHA-256, và lõi App không chạm được thế giới Secure.
- Hôm nay báo cáo ba phần: RTL, PPA, các bài test đã đạt.
- RTL đã freeze từ 13/11. Sau đó chỉ thêm hai phần bộ nhớ cho ASIC bằng công tắc mặc định tắt. Bản FPGA không đổi (10.982 LE trước và sau).

Lời nói: Đồ án làm một chip có thể tự kiểm phần mềm trước khi chạy. Hôm nay em báo cáo RTL, số đo PPA và các bài test đã đạt.

## Slide 2. RTL: kiến trúc tổng thể

- Hình: `01_system_overview.png`.
- Hai thế giới tách biệt: Secure (lõi Master) và App (lõi App). Hai lõi cùng là `RISCV_Core` RV32I, đường ống 5 tầng.
- Secure có Boot ROM 4 KB, RAM 4 KB, bus AXI4-Lite, SHA-256, Secure DMA, Boot_Verifier, SYSCSR, ngoại vi.
- App có ROM, RAM và bus riêng. Không có đường nào tới bus Secure.
- Hai thế giới chỉ nói chuyện qua cổng đọc của ROM App và hộp thư.

Lời nói: Hai lõi giống nhau, khác ở vai trò. Master kiểm, App bị kiểm. Chúng chỉ nối nhau qua hai cổng hẹp.

## Slide 3. RTL: các khối bảo mật

| Khối | Làm gì | Yêu cầu |
| --- | --- | --- |
| Boot ROM và golden hash | Giữ mã khởi động và vân tay chuẩn, không ghi được | SR-04 |
| SHA-256 | Tạo vân tay của 4 KB ROM App, 66 chu kỳ mỗi khối tính từ lệnh start | SR-03 |
| Boot_Verifier | Phần cứng tự so vân tay, từ chối ảnh cũ, khóa khóa HMAC | SR-02, 03, 06, 07 |
| SYSCSR | Giữ App trong reset, Boot Guard khóa và xóa RAM App, ghi lỗi bus | SR-01, 05, 11 |
| DMA và tường lửa | Chuyển ảnh App vào SHA-256, chỉ chạm hai vùng cho phép | SR-08 |

- Hình: `10_security_architecture.png` (gắn mã SR-01 đến SR-11).
- Nguồn: `docs/spec/Security_Model.md`.

Lời nói: Mỗi khối trả lời một yêu cầu bảo mật. Điểm chính là kết quả kiểm do phần cứng tính, firmware không giả được.

## Slide 4. RTL: luồng Secure Boot

- Hình: `11_secure_boot_flow.png`.
- Bật nguồn thì chỉ Master chạy. Master băm 4 KB ROM App bằng DMA, so với golden hash, rồi Boot_Verifier tự so lại.
- Đúng thì phần cứng nhả lõi App. Sai thì App bị khóa tới khi cấp nguồn lại và RAM App bị xóa.
- Mọi nhánh lỗi đều rơi về trạng thái khóa, không có lỗi nào mở App.

Lời nói: Nguyên tắc là mọi lỗi đều an toàn. Lỗi bus, DMA bị chặn, hash sai, hết giờ đều dẫn tới khóa.

## Slide 5. Các bài test đã đạt

`make test` đạt 32 mục (Questa, chạy 16/11):

| Nhóm | Số mục | Nội dung |
| --- | --- | --- |
| Lõi | 4 | 11 testbench đơn vị, chương trình ISA, `RISCV_Core_tb`, hazard |
| UVM và HAL | 6 | AXI4-Lite, SHA-256, APB, HAL SHA-256 trên máy |
| Ngoại vi, Boot_Verifier | 2 | Ngoại vi APB, cổng nhả App (30/30) |
| SoC | 2 | Secure boot ảnh đúng và ảnh bị sửa (App bị khóa, RAM xóa) |
| Firmware thật | 5 | Ảnh đúng, ảnh sửa, access fault, firmware App đúng và sửa |
| ASIC_Top và ngắt, VP | 3 | Reset đồng bộ và boot, ngắt hai lõi, mô hình SystemC |
| Bộ nhớ cho ASIC | 10 | Wrapper SRAM, ROM logic, các test SoC và firmware chạy lại trên bộ nhớ ASIC |

- Hình: `18_verification_flow.png`.
- Test được thử bằng cách cài lỗi vào RTL và thấy báo lỗi: lõi, trap, scoreboard SHA-256 (ghi trong sheet P-02, P-09, P-17) và wrapper bộ nhớ.

Lời nói: Bộ test chạy một lệnh, tất cả đều đạt. Em cũng thử phá thiết kế để chắc test thật sự bắt được lỗi.

## Slide 6. PPA trên FPGA

| | DE2 (Cyclone II) | Artix-7 | Kria KV260 |
| --- | --- | --- | --- |
| Công cụ | Quartus II 13.0sp1 | Vivado 2025.2 | Vivado 2025.2 |
| Clock | 50 MHz | 50 MHz | 50 MHz |
| Tốc độ | Fmax 54,07 MHz | WNS +3,228 ns | WNS +5,517 ns |
| Hold | +0,391 ns (đo 27/10) | WHS +0,018 ns | WHS +0,011 ns |
| Logic | 10.982 LE (33%) | 6.137 LUT | 6.045 LUT |
| Bộ nhớ | 135.168 bit (28%) | 2,5 BRAM | 2,5 BRAM |
| Chân | 52 (khớp sổ tay DE2) | 25 | 8 |

- Đã tổng hợp, xếp chân và đạt thời gian trên cả ba. Không yêu cầu nạp board.
- Công suất chỉ là ước tính, không đưa làm số đo.
- Nguồn: `docs/project/PPA_FPGA.md`, `fpga/reports/de2_fit_summary.txt`, `de2_fmax.txt`.

Lời nói: Thiết kế vừa chip DE2 với một phần ba tài nguyên và đạt 50 MHz. Hai kit Xilinx cũng đạt thời gian.

## Slide 7. PPA trên ASIC (Genus, GPDK45)

Server trường, buổi chạy 18/11, bản hai RAM dùng macro SRAM, hai ROM là logic:

| Chỉ số | Giá trị |
| --- | --- |
| Diện tích tổng | 101.597 µm², gồm hai macro 16.000 µm² |
| Diện tích ROM logic | 12.204 µm², nhỏ hơn hai macro ROM (16.000 µm²) |
| Flip-flop | 7.117, 98,3% được gate |
| Slack ở 20 ns | +7,124 ns, đạt tới 6 ns |
| Chu kỳ chốt | 11 ns, khoảng 91 MHz, dư biên 10% |
| LEC (Conformal) | Đạt, 0 điểm không tương đương |
| GLS (Xcelium) | Đạt, boot ra LED 0x01 |
| Clock gating | Giảm khoảng 12% diện tích và 55% công suất (bản black box ở 20 ns, chỉ bản này có lượt so `CG=0`) |

- Đường găng của lõi: từ thanh ghi đích tầng MEM qua forwarding và bộ so sánh ALU tới PC, 12,62 ns ở 20 ns. Không đi qua ROM.
- Layout bằng Innovus chạy 25/11 và đạt signoff ở 11 ns, xem slide 7b.
- Nguồn: `asic/README.md` mục kết quả 18/11, `asic/reports/genus_macro/`.

Lời nói: Tổng hợp đạt từ rất nhanh. Em chốt 11 ns để dư biên, và layout giữ được chu kỳ đó.

## Slide 7b. Layout ASIC (Innovus)

Chạy 25/11 trên server trường, Innovus 21.19 và Tempus.

- Hình (ảnh Phát chụp, không đưa vào repo): `13_innovus_floorplan.png` (hai macro SRAM, lưới nguồn, chân hai bên), `14_innovus_placement.png`, `15_innovus_cts.png`, `16_innovus_route.png`. Ảnh terminal của từng bước: `03` tới `12`.

| Chỉ số (netlist `SRAM=1 ROM=1`, 11 ns) | Giá trị | Nguồn |
| --- | --- | --- |
| Die, lõi | 443 × 440 µm, lõi 413 × 410 µm | `pd_checks.rpt` |
| Diện tích cell, mật độ ngoài macro | 110.357 µm² cell chuẩn và 16.000 µm² macro, mật độ 71,9% | như trên |
| DRC, antenna, connectivity | 0, 0, 0 (1 mẩu dây nguồn hở đã xoá bằng `editTrim`) | `drc_eco.rpt`, `antenna_eco.rpt`, `connectivity_eco.rpt` |
| Tempus signoff với SPEF | Setup +0,042 ns, hold +0,020 ns, recovery +8,912 ns, removal +0,173 ns | `asic/reports/sta/spef/summary.txt` |
| Cây clock | Độ trễ 0,38 tới 0,48 ns, skew 100 ps (mục tiêu 80 ps chưa đạt, timing vẫn đạt) | `cts_skew_groups.rpt` |
| Chu kỳ | 11 ns, khoảng 91 MHz, không phải lùi 12 ns | |

- Lần đầu Tempus báo setup −10 ps vì Innovus dừng ở +1 ps. Một lượt ECO đòi dư 50 ps đã sửa được, và script đã thêm bước này cho lần sau.

Lời nói: Đây là chip sau khi đặt và đi dây. Hai khối lớn là hai macro SRAM, phần còn lại là logic. Sau route không còn lỗi quy tắc, và kiểm thời gian bằng Tempus với điện dung dây thật vẫn đạt ở 11 ns.

## Slide 8. Hướng tiếp theo

- Trước mắt: Layout ASIC đã đạt (25/11). Còn GLS có SDF, LEC sau layout và công suất bằng Voltus.
- Tiếp theo: Tăng phần bảo mật gồm khóa HMAC thật, chữ ký bất đối xứng, chống glitch và thêm bài test tấn công. Thêm tính năng trong RTL phải mở lại phần đã freeze (13/11) và chạy lại bộ kiểm.
- Nhóm dừng thêm tính năng mới cho hệ thống. DMA, PLIC, hộp thư, ngoại vi App coi là phần mở rộng. Mong thầy góp ý thứ tự thực hiện.

Lời nói: Layout ASIC đã đạt, còn vài bước kiểm sau layout. Sau đó nhóm đào sâu bảo mật. Mong thầy góp ý thứ tự thực hiện.
