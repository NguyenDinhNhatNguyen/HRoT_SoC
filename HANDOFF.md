# HANDOFF (cập nhật 07/11/2026)

Đọc file này khi Nguyên nói "tiếp tục".

## Đã xong
| Việc | Trạng thái |
| --- | --- |
| N-37 Boot_Verifier, `VERIFY_GATE` mặc định 1, đã đẩy lên repo | Xong |
| KV260: `make kv260` ra `kv260.bit`, PL0 50 MHz, WNS +5,517 ns, WHS +0,011 ns (07/11) | Xong |
| `fpga/` chia `intel/de2`, `xilinx/artix7`, `xilinx/kv260` | Xong |
| `make test` 07/11: All checks passed. `make de2`: 10.982 LE, 135.168 bit, Fmax 54,07 MHz | Xong |
| Sheet: tab "Hướng dẫn & Kiểm thử" và "Mua sắm & Mượn" | Xong |

## Commit chưa push
Không còn. `c12b74d`, `98df2fa`, `d862477` đã lên GitHub (07/11, tới `ce29a2e`).

## Việc chờ kiểm (cần board hoặc cần người)
| Mục | Việc | Ở đâu |
| --- | --- | --- |
| M-1 | Kit mượn có đủ nguồn 12 V 3 A, thẻ microSD, cáp micro-USB | Sheet, tab Mua sắm & Mượn |
| M-2 | Chạy `fpga/xilinx/kv260/pintest/build/pinwalk.bit` (đã build, chưa thử trên board), đo J2 xem từng chân sáng đúng thứ tự. Cần chuyển thành .bit.bin và .dtbo riêng để nạp | Sheet, K-03 |
| M-3 | Xong phần tài liệu: UG1089 v1.4 và sơ đồ nguyên lý AMD XTP682 (rev 1.0 và 2.0) đã đọc. Số J2 khớp README | Sheet |
| M-4 | Boot thử, thẻ SD có ảnh Kria Linux, `sudo xmutil listapps` | Sheet |
| K-01 đến K-10 | Nạp và chạy trên KV260 (overlay, `install_on_board.sh`, UART 115200, LED) | Sheet, tab Hướng dẫn & Kiểm thử |
| D-01 đến D-07 | Nạp và chạy trên DE2, đối chiếu `de2_pins.tcl` với manual DE2 | Sheet, tab Hướng dẫn & Kiểm thử |
| F-02, F-03 | Đã chạy lại 07/11, đạt: `make xilinx` WNS +3,228 ns, WHS +0,018 ns. `make kv260` WNS +5,517 ns, WHS +0,011 ns, clk_pl_0 50 MHz | Log trong `fpga/*/build` |

## Việc chờ người khác (không cần board)
| Việc | Chờ ai | Ghi chú |
| --- | --- | --- |
| N-30 SDC ASIC | Phát (P-20, P-21) | `asic/SoC_Top.sdc` là khung. Phát đề xuất 09/11 `CLK_PERIOD_NS = 20`, `IO_DELAY_NS = 4`, chốt khi chạy Genus trên server trường. Đầu vào bất đồng bộ đã kiểm 09/11, `reset_system` có bộ đồng bộ ở `asic/ASIC_Top.v` kèm `ASIC_Top.sdc` (`3a3a6e0`) |
| N-30 số sơ bộ ASIC | không cần chờ | `make asic-yosys` (WSL, docker `iic-osic-tools` phải chạy): 72.012 µm² logic, 7.004 flop, F_max 249 MHz với NanGate45, bộ nhớ là black box. Chỉ là xu hướng. Số chính thức chạy Genus trên server trường với GPDK45, không commit file PDK |
| N-31 khớp chương báo cáo | Dàn ý chương báo cáo | Sơ đồ và README đã xong, 21 trang sơ đồ |

## Điều đã biết nhưng chưa chắc
- Số J2 đã khớp sơ đồ nguyên lý AMD XTP682 (rev 1.0 và 2.0, trang 17). Chân FPGA (H12, E10...) lấy từ XDC của AMD (Kria-PYNQ), sơ đồ carrier card chỉ tới connector SOM. Chưa đo trên board.
- Nhãn và ID overlay đã đối chiếu mã nguồn linux-xlnx, chưa chạy trên board.
- UG1089 v1.4 xác nhận nguồn 12 V 3 A và hộp kit không kèm nguồn hay thẻ SD.

## Liên kết
- Sheet: https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4
- Doc kế hoạch: https://docs.google.com/document/d/1d8gVmK7QJY6stRFjfauVdNv7vllKQLhibux6AV8KrY4
