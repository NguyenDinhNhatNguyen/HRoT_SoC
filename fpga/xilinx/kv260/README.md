# Kria KV260

SoC trên kit Kria KV260 (K26 SOM, chip `xck26-sfvc784-2LV-c`). Phần PL của K26 không có dao động riêng nên clock và reset lấy từ PS qua block design. Lõi `rtl/` không đổi, `KV260_Top.v` gọi thẳng `SoC_Top` nên thư mục này tự đủ, không phụ thuộc `artix7/`.

| File | Việc |
| --- | --- |
| `kv260_bd.tcl` | Block design chỉ có Zynq UltraScale+ PS, `pl_clk0` 50 MHz từ IOPLL, `pl_resetn0` |
| `KV260_Top.v` | Top: nối `pl_clk0` và `pl_resetn0` vào `SoC_Top`, công tắc và boot strap tied 0 |
| `kv260.xdc` | Chân PMOD, false path |
| `build_kv260.tcl` | Tổng hợp, place, route, báo cáo, `kv260.bit` |
| `firmware/` | Overlay `.dtsi`, `shell.json`, `template.bif`, `install_on_board.sh` để nạp lên board |

## Chân (PMOD, 3,3 V)

KV260 chỉ có một header PL còn trống là PMOD (8 chân, các net `HDA11` đến `HDA18`). Chân lấy từ XDC của chính AMD (`Xilinx/kria-vitis-platforms`, `kv260/platforms/kv260_bist/xdc/pin.xdc`).

| Cổng | Net | Chân FPGA | Pmod pin | J2 |
| --- | --- | --- | --- | --- |
| `uart_tx` | HDA11 | H12 | 1 | J2.1 |
| `uart_rx` | HDA12 | E10 | 2 | J2.3 |
| `led_app` | HDA13 | D10 | 3 | J2.5 |
| `led[0]` | HDA14 | C11 | 4 | J2.7 |
| `led[1]` | HDA15 | B10 | 7 | J2.2 |
| `led[2]` | HDA16 | E12 | 8 | J2.4 |
| `led[3]` | HDA17 | D11 | 9 | J2.6 |
| `led[4]` | HDA18 | B11 | 10 | J2.8 |

Chỉ có 5 LED vì PMOD chỉ có 8 chân. Mã kết quả boot (8 bit) vẫn in đầy đủ trên UART. Pmod pin 5 và 11 là GND, pin 6 và 12 là 3,3 V. Cột Pmod pin và J2 đối chiếu từ hai nguồn bên thứ ba khớp nhau (sơ đồ chân của Tom Verbeure và ví dụ I2S của AMD), chưa đối chiếu với sơ đồ nguyên lý carrier card, nên đo lại trước khi cắm module ngoài. UART cần module USB-UART mức 3,3 V, chọn chéo TX và RX theo module.

## Build và nạp

```text
make kv260        # trong WSL, ra fpga/xilinx/kv260/build/kv260.bit và báo cáo
```

Chuyển đổi có thể làm ngay trên PC bằng `firmware/make_on_pc.ps1` (dùng `bootgen` và `dtc` của Vitis, đã chạy thử ra `.bit.bin` và `.dtbo`), khi đó board không cần mạng. Hoặc làm trên board: nạp theo cách của AMD cho firmware PL tùy biến (Linux Kria): chép `kv260.bit` vào `firmware/`, rồi trên board chạy `install_on_board.sh` (cần `sudo apt install bootgen-xlnx device-tree-compiler`). Script đổi `.bit` thành `.bit.bin` bằng `bootgen`, đổi `.dtsi` thành `.dtbo` bằng `dtc`, chép vào `/lib/firmware/xilinx/kv260-hrot/` và gọi `xmutil unloadapp`, `xmutil loadapp`. Clock PL0 do overlay đặt (`assigned-clock-rates`), không phải do bitstream.

## Chưa kiểm chứng trên board

- Overlay và script làm theo mẫu AMD nhưng chưa chạy trên board thật.
- Các nhãn overlay (`fpga_full`, `amba`, `zynqmp_clk`, `zynqmp_reset`), ID clock 71 (PL0) và reset 116 đến 119 đã đối chiếu với mã nguồn linux-xlnx, chưa thử trên board.
- Baud UART đúng 115200 chỉ khi PL0 thật sự là 50 MHz (bản dựng cho 50,000 MHz).
- Số chân vật lý của PMOD chưa đối chiếu với sơ đồ nguyên lý.
