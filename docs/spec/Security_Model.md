# Mô hình bảo mật

Tài liệu này nêu tài sản cần bảo vệ, kẻ tấn công được giả định, các yêu cầu bảo mật (SR), cách mỗi yêu cầu được thực hiện trong RTL và kiểm bằng test nào, cùng những giới hạn đã biết. Địa chỉ và thanh ghi xem `SoC_Memory_Map.md`.

## Tài sản và ranh giới tin cậy

| Tài sản | Vị trí | Vì sao cần bảo vệ |
| --- | --- | --- |
| Golden hash của ảnh App | Boot ROM `0x0000_0FE0` (chỉ đọc) | Chuẩn để so, sửa được là qua mặt được secure boot |
| Mã secure boot | Boot ROM `0x0000_0000` | Gốc tin cậy, chạy trước mọi mã khác |
| Ảnh firmware App | ROM App `0x6000_0000` | Thứ cần được xác minh trước khi chạy |
| Khóa HMAC | Boot_Verifier `KEY0..7` | Xác thực nguồn gốc ảnh, không chỉ toàn vẹn |
| Ngưỡng phiên bản | Boot_Verifier `MIN_VER` | Chống chạy lại ảnh cũ có lỗi |
| RAM Secure | `0x1000_0000` | Chứa trạng thái của thế giới Secure |
| Cờ khóa Boot Guard | SYSCSR `GUARD.LOCK` | Giữ App bị cô lập sau khi phát hiện ảnh xấu |

Hai thế giới: **Secure** (lõi Master, bus AXI, ngoại vi APB, Secure DMA, SHA-256) là vùng tin cậy. **App** (lõi App, RAM và ngoại vi riêng) là vùng không tin cậy cho tới khi ảnh của nó được xác minh. Lõi App không có đường tới bus Secure.

## Kẻ tấn công giả định

| Mã | Khả năng | Ngoài phạm vi |
| --- | --- | --- |
| A1 | Cung cấp ảnh App bị sửa hoặc ảnh cũ có lỗi | |
| A2 | Mã App đã bị chiếm, cố truy cập tài nguyên Secure | |
| A3 | Lỗi hoặc glitch phần mềm trong firmware Secure khiến bỏ qua nhánh so hash | Glitch điện áp hoặc xung nhịp ở mức vật lý |
| A4 | Cấu hình DMA sai để đọc hoặc ghi ngoài vùng cho phép | |
| | | Tấn công kênh phụ, đọc khóa bằng thăm dò vật lý, JTAG (không có cổng debug) |

## Yêu cầu bảo mật và truy vết

| Mã | Yêu cầu | Thực hiện trong RTL | Kiểm bằng |
| --- | --- | --- | --- |
| SR-01 | Lõi App giữ trong reset cho tới khi ảnh được xác minh | `SYSCSR.v`: `app_run` reset về 0, `app_rst = sys_rst_q \| ~app_run \| lock_q` | `SoC_Top_tb` (App chỉ chạy sau secure boot), `APB_Periph_tb` |
| SR-02 | Phần mềm không tự nhả được App khi chưa có kết quả phần cứng | `SYSCSR.v`: `app_run <= PWDATA[0] && (verified \|\| !VERIFY_GATE)` | `Boot_Verifier_tb` ("APP_RUN ignored before CHECK", "ignored after FAIL"), `SoC_Top_tb` (ghi `APP_RUN` sớm bị từ chối), VP |
| SR-03 | Kết quả xác minh do phần cứng tự tính, không do firmware khai | `Boot_Verifier.v`: tự đọc 8 từ golden từ Boot ROM (mượn cổng B khi `CHECK`) và so với digest SHA-256 | `Boot_Verifier_tb` (sai bit ở từ 0 và từ 7, SHA chưa xong, SHA bận) |
| SR-04 | Golden hash không sửa được | `Dual_Port_ROM.v` không có đường ghi, ghi vào ROM trả `SLVERR` | `SoC_Top_tb` (ghi ROM App và Boot ROM trả `SLVERR`) |
| SR-05 | Ảnh xấu bị khóa vĩnh viễn tới khi cấp nguồn lại, RAM App bị xóa | `SYSCSR.v`: `lock_q` chỉ xóa bởi `por_rst`, FSM zeroization xóa RAM App | `APB_Periph_tb` (LOCK, quét RAM, giữ qua SW reset), `SoC_Top_tb +TAMPER` |
| SR-06 | Chống chạy lại ảnh cũ | `Boot_Verifier.v`: `APP_VER >= MIN_VER`, `MIN_VER` chỉ tăng | `Boot_Verifier_tb` (rollback 4 < 5 bị từ chối, MIN_VER không giảm) |
| SR-07 | Khóa không lộ sau khi dùng | `Boot_Verifier.v`: `KEY_LOCK` dính tới POR, đọc `KEY` ra 0 | `Boot_Verifier_tb` (KEY_LOCK qua SW reset, mở lại sau POR) |
| SR-08 | DMA chỉ chạm vùng cần thiết | `DMA_Firewall.v`: chỉ đọc ROM App và `SHA STATUS`, chỉ ghi thanh ghi khối và `CTRL` của SHA-256 | `SoC_Top_tb` (DMA trỏ vào RAM bị chặn, không có yêu cầu lạc), VP |
| SR-09 | Lõi App không chạm tài nguyên Secure | Bus App riêng (RAM, UART1, GPIO1, TIMER1, Mailbox), không nối vào AXI Secure | `SoC_App_tb`, đọc `SoC_Top.v` mục thế giới App |
| SR-10 | Địa chỉ ngoài vùng không bị lặp về bộ nhớ (không alias) | `SoC_Top.v`: Boot ROM, RAM, ROM App giải mã 4 KB, ngoài vùng `DECERR` | `SoC_Top_tb` (`DECERR_R=4`) |
| SR-11 | Lỗi bus được ghi lại cho firmware | `SYSCSR.BUS_ERR` (W1C) và `BUS_ERR_ADDR` | `APB_Periph_tb`, `SoC_Top_tb` |

## Giới hạn đã biết

| # | Giới hạn | Hệ quả |
| --- | --- | --- |
| L1 | `VERIFY_GATE` mặc định 1 trong `SoC_Top` từ 07/11 (đã đóng giới hạn cũ). `SYSCSR` riêng lẻ vẫn mặc định 0 | `SoC_Irq_tb` đặt 0 vì chương trình assembly của nó nhả App không qua `CHECK`. Dùng `SoC_Top` với mặc định thì App chỉ chạy sau `VERIFIED` |
| L2 | `MIN_VER` và `KEY_LOCK` xóa bởi POR, FPGA không có bộ nhớ không mất dữ liệu | Mô hình OTP chỉ đúng trong một lần cấp nguồn. Bản ASIC cần OTP hoặc eFuse thật |
| L3 | Khóa HMAC là hằng trong RTL (tham số `KEY`) | Chỉ để demo, không phải khóa bí mật |
| L4 | Chỉ so hash hoặc HMAC, không có chữ ký bất đối xứng | Không có chuỗi chứng chỉ và không thu hồi khóa |
| L5 | `APP_VER` do firmware ghi trước `CHECK` | Firmware gian dối có thể khai phiên bản. Phiên bản nằm trong ảnh được băm nên sửa ảnh sẽ bị bắt, nhưng firmware khai sai số thì không |
| L6 | `master_data_err` nối cố định vào lõi Master trong `SoC_Top.v` từ 04/11 (P-24), lõi App vẫn nối 0 | Truy cập lỗi của Master gây trap (`mcause` 5/7) và vẫn ghi `BUS_ERR`. Lõi App không nhận access fault vì bus APB của App bỏ qua `PSLVERR` |
| L7 | Lõi chỉ có chế độ máy (M), không có PMP hay phân quyền | Bảo vệ dựa vào tách bus chứ không phải đặc quyền trong lõi |
| L8 | Không có cổng debug (JTAG) | Không có lỗ hổng debug, nhưng cũng không có đường debug an toàn |
| L9 | Không có bộ phát hiện glitch hay so sánh dư thừa | Chỉ chống glitch phần mềm (SR-02), không chống glitch vật lý |
| L10 | SHA-256 dùng chung giữa CPU và DMA, quy tắc "CPU không đụng khi DMA bận" chỉ là quy ước | Firmware sai có thể làm hỏng một lần băm, kết quả là `FAIL` chứ không phải nhả nhầm |
| L11 | Zeroization chỉ xóa RAM App | Mailbox và thanh ghi lõi không được xóa |
| L12a | Khi `CHECK` chạy (khoảng 9 chu kỳ) Boot_Verifier mượn cổng B của Boot ROM | Firmware không được `lw` từ Boot ROM lúc đó, quy ước chứ không có phần cứng chặn |
| L12 | Bộ nhớ dùng cạnh xuống của xung nhịp (suy ra M4K/BRAM) | Phù hợp FPGA, không phù hợp ASIC (R8) |
