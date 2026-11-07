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
`c12b74d` ignore file firmware KV260, `98df2fa` và `d862477` bảng chân Pmod trong README và `kv260.xdc`. Chỉ push khi Nguyên nói.

## Việc chờ kiểm (cần board hoặc cần người)
| Mục | Việc | Ở đâu |
| --- | --- | --- |
| M-1 | Kit mượn có đủ nguồn 12 V 3 A, thẻ microSD, cáp micro-USB | Sheet, tab Mua sắm & Mượn |
| M-2 | Đo J2: J2.9, J2.10 là GND, J2.11, J2.12 là 3,3 V, J2.1 và J2.3 đúng HDA11 và HDA12 | Sheet, K-03 |
| M-3 | Đối chiếu UG1089 v1.4: dung lượng thẻ SD, bảng chân Pmod J2 (trang v1.4 thử mở trả 404) | Sheet |
| M-4 | Boot thử, thẻ SD có ảnh Kria Linux, `sudo xmutil listapps` | Sheet |
| K-01 đến K-10 | Nạp và chạy trên KV260 (overlay, `install_on_board.sh`, UART 115200, LED) | Sheet, tab Hướng dẫn & Kiểm thử |
| D-01 đến D-07 | Nạp và chạy trên DE2, đối chiếu `de2_pins.tcl` với manual DE2 | Sheet, tab Hướng dẫn & Kiểm thử |
| F-02, F-03 | Chạy lại `make xilinx` và `make kv260`, so WNS và WHS với tiêu chí (build ngày 07/11 đang chạy nền, chưa đọc kết quả) | Log trong `fpga/*/build` |

## Điều đã biết nhưng chưa chắc
- Số Pmod pin và J2 khớp XDC của AMD (Kria-PYNQ) và XDC của ikwzm/Kv260-Pmod-gpio-emio, chưa khớp sơ đồ nguyên lý. GND và 3,3 V (J2.9 đến J2.12) suy từ chuẩn Digilent.
- Nhãn và ID overlay đã đối chiếu mã nguồn linux-xlnx, chưa chạy trên board.
- UG1089 v1.4 xác nhận nguồn 12 V 3 A và hộp kit không kèm nguồn hay thẻ SD.

## Liên kết
- Sheet: https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4
- Doc kế hoạch: https://docs.google.com/document/d/1d8gVmK7QJY6stRFjfauVdNv7vllKQLhibux6AV8KrY4
