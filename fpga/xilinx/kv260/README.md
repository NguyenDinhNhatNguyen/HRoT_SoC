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

| Cổng | Net | Chân |
| --- | --- | --- |
| `uart_tx` | HDA11 | H12 |
| `uart_rx` | HDA12 | E10 |
| `led_app` | HDA13 | D10 |
| `led[0]` đến `led[4]` | HDA14 đến HDA18 | C11, B10, E12, D11, B11 |

Chỉ có 5 LED vì PMOD chỉ có 8 chân. Mã kết quả boot (8 bit) vẫn in đầy đủ trên UART. Tên net HDA là tên của carrier card, số chân vật lý trên PMOD khác với số HDA, nên đối chiếu với sơ đồ nguyên lý carrier card trước khi cắm module ngoài. UART cần module USB-UART mức 3,3 V, chọn chéo TX và RX theo module.

## Build và nạp

```text
make kv260        # trong WSL, ra fpga/xilinx/kv260/build/kv260.bit và báo cáo
```

Nạp theo cách của AMD cho firmware PL tùy biến (Linux Kria): chép `kv260.bit` vào `firmware/`, rồi trên board chạy `install_on_board.sh` (cần `sudo apt install bootgen-xlnx device-tree-compiler`). Script đổi `.bit` thành `.bit.bin` bằng `bootgen`, đổi `.dtsi` thành `.dtbo` bằng `dtc`, chép vào `/lib/firmware/xilinx/kv260-hrot/` và gọi `xmutil unloadapp`, `xmutil loadapp`. Clock PL0 do overlay đặt (`assigned-clock-rates`), không phải do bitstream.

## Chưa kiểm chứng trên board

- Overlay và script làm theo mẫu AMD nhưng chưa chạy trên board thật.
- ID clock 71 (PL0) lấy từ overlay `kv260-smartcam.dtsi` của AMD, chưa tự đối chiếu với tài liệu.
- Baud UART đúng 115200 chỉ khi PL0 thật sự là 50 MHz (bản dựng cho 50,000 MHz).
- Vị trí các chân PMOD trên connector vật lý.
