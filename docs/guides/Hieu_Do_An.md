# Hiểu rõ đồ án HRoT_SoC

> Bản nháp 21/11/2026 (Nguyên). Người đọc: các bạn trong nhóm, để nắm mình đang làm gì và trả lời được khi thầy hỏi. Mỗi con số có ghi nguồn. Chỗ nào chưa kiểm thì ghi rõ ở mục 10.

## 0. Cách dùng

- Đọc mục 1 và mục 4 trước. Hai mục này kể cả câu chuyện từ lúc bật nguồn tới lúc App chạy.
- Mục 2 giải thích các khái niệm nền bằng ví dụ đời thường rồi mới tới kỹ thuật.
- Mục 3 trả lời cùng năm câu cho từng khối: Là gì. Để làm gì. Vì sao chọn nó. Thiếu nó thì sao. Chứng minh ở đâu.
- Mục 5 và 6 giải thích công cụ, đường găng, các con số.
- Mục 7 phân loại khối nào là lõi Secure, khối nào là mở rộng. Mục 8 là các câu thầy có thể hỏi.

## 1. Đồ án trong một trang

**Vấn đề.** Một chip chạy phần mềm của nhiều bên. Nếu ai đó thay phần mềm bằng bản độc hại, chip vẫn chạy bản đó. Muốn tin chip, phải kiểm phần mềm trước khi cho nó chạy.

**Giải pháp.** Chip có một phần nhỏ được tin vô điều kiện, gọi là Hardware Root of Trust. Phần này chạy đầu tiên, nằm trong ROM không sửa được và kiểm mọi thứ chạy sau nó.

**Đồ án làm gì.** Một SoC RISC-V hai lõi:

| Lõi | Vai trò | Có gì |
| --- | --- | --- |
| Master (thế giới Secure) | Chạy đầu tiên, kiểm ảnh của App | Boot ROM 4 KB, RAM 4 KB, bus AXI4-Lite, SHA-256, Secure DMA, Boot_Verifier, SYSCSR, ngoại vi |
| App (thế giới App) | Chạy phần mềm ứng dụng, bị giữ reset cho tới khi được kiểm | ROM 4 KB, RAM 4 KB, bus riêng, UART1, GPIO1, TIMER1, hộp thư |

Hai lõi là cùng một module `RISCV_Core` (`rtl/top/SoC_Top.v`, `master_core` và `app_core`). Khác nhau ở vai trò và chỗ nối, không phải ở lõi.

**Câu chuyện.**
1. Bật nguồn. Chỉ lõi Master chạy. Lõi App bị giữ trong reset bởi phần cứng.
2. Master băm toàn bộ 4 KB ROM của App bằng SHA-256, ra một vân tay dài 32 byte.
3. Master so vân tay đó với vân tay chuẩn cất trong Boot ROM.
4. Khối phần cứng Boot_Verifier tự so lại một lần nữa, không tin kết quả do firmware báo.
5. Đúng thì phần cứng mới cho phép nhả lõi App. Sai thì App bị khóa vĩnh viễn tới khi cấp nguồn lại, và RAM của App bị xóa sạch.

**Mục tiêu chứng minh** (`docs/project/Project_Plan.md`): lõi App chỉ chạy khi phần cứng xác thực firmware của nó bằng SHA-256, và lõi App không thể chạm vào thế giới Secure.

## 2. Khái niệm nền

| Khái niệm | Hiểu đời thường | Hiểu kỹ thuật | Trong đồ án |
| --- | --- | --- | --- |
| Hàm băm | Vân tay của một tập tin. Cùng tập tin ra cùng vân tay. Sửa một chút là vân tay đổi hẳn | Biến dữ liệu dài bất kỳ thành chuỗi dài cố định. Hầu như không tìm được hai dữ liệu cùng chuỗi, và không suy ngược được dữ liệu từ chuỗi | Băm 4 KB ROM của App để phát hiện bị sửa |
| SHA-256 | Một loại hàm băm cụ thể, ra 256 bit (32 byte) | Chuẩn FIPS 180-4. Chia dữ liệu thành khối 64 byte, mỗi khối qua 64 vòng tính | Lõi `rtl/crypto/SHA256_Core.v` làm một vòng mỗi chu kỳ. Một khối: 65 chu kỳ bận (64 vòng và 1 chu kỳ cộng vào H), 66 chu kỳ tính từ chu kỳ nhận `start` tới khi `done` lên |
| Golden hash | Vân tay chuẩn cất trong két | Giá trị băm đúng của ảnh App, ghi sẵn lúc build | 8 từ 32 bit ở Boot ROM `0x0000_0FE0`, chỉ đọc |
| HMAC và khóa | Vân tay có khóa bí mật. Chỉ ai có khóa mới tạo được vân tay đúng | Hàm băm kết hợp khóa. Chứng minh ảnh đến từ chủ khóa, không chỉ là không bị sửa | Phần cứng có chế độ `MODE 1`. Firmware hiện dùng `MODE 0` (so hash). Khóa trong RTL là hằng demo (giới hạn L3) |
| Chống chạy lại ảnh cũ | Không cho cài lại phiên bản cũ có lỗi | `MIN_VER` là ngưỡng phiên bản, chỉ tăng, không giảm | `APP_VER < MIN_VER` thì bị từ chối (SR-06) |
| Root of Trust | Điểm xuất phát được tin vô điều kiện | Phần nhỏ, chạy đầu tiên, không sửa được | Boot ROM, Boot_Verifier, SYSCSR, SHA-256 |
| Chuỗi tin cậy | Mỗi mắt xích kiểm mắt xích sau | Mắt xích trước xác thực rồi mới trao quyền cho mắt xích sau | Boot ROM, firmware Master, kiểm ảnh App, rồi App chạy |
| POR | Bấm công tắc nguồn lên | Power-on reset. Xóa mọi thứ, kể cả cờ khóa | Chỉ POR mới mở khóa Boot Guard (SR-05) |
| Zeroization | Xóa sạch hiện trường | Ghi 0 vào toàn bộ RAM của App | Máy trạng thái xóa 1.024 từ, mỗi chu kỳ một từ (`secure_boot.c` dòng 33) |
| DMA | Nhân viên chuyển hàng, không cần giám đốc tự khiêng | Khối phần cứng tự chép dữ liệu giữa các vùng mà CPU không phải đọc từng từ | Chuyển 4 KB ROM của App vào SHA-256 |
| Tường lửa DMA | Nhân viên chuyển hàng chỉ được vào hai kho | Chặn mọi địa chỉ ngoài danh sách cho phép | Chỉ đọc ROM App và ghi thanh ghi SHA-256 (SR-08) |
| Bus AXI4-Lite | Đường trục chính nối các khối | Giao thức có 5 kênh (địa chỉ ghi, dữ liệu ghi, phản hồi ghi, địa chỉ đọc, dữ liệu đọc), mỗi kênh có bắt tay valid và ready | Bus của thế giới Secure |
| Bus APB | Đường nhánh chậm cho ngoại vi | Giao thức đơn giản, chậm, ít dây | Cầu AXI sang APB ra 9 ngoại vi |
| Đường ống 5 tầng | Dây chuyền 5 công đoạn | Mỗi lệnh đi qua IF, ID, EX, MEM, WB. Năm lệnh chạy chồng nhau | Lõi RISC-V ở `rtl/core/` |
| Hazard và forwarding | Công đoạn sau cần kết quả mà công đoạn trước chưa xong | Hazard là phụ thuộc dữ liệu. Forwarding chuyền kết quả tắt thay vì chờ ghi vào thanh ghi | `Forwarding_Unit.v`, `Hazard_Detection` trong `RISCV_Core` |
| Ngắt và trap | Chuông cửa và báo động | Ngắt do thiết bị gọi lõi. Trap do lõi tự gặp lỗi (lệnh lạ, truy cập lỗi) | `CSR_Unit.v`, PLIC-lite gom ngắt |
| Bản đồ địa chỉ | Số nhà của từng khối | Mỗi khối chiếm một dải địa chỉ | `docs/spec/SoC_Memory_Map.md` |
| Clock gating | Tắt điện phòng không có người | Ngắt xung nhịp tới nhóm flip-flop không đổi | Giảm khoảng 12% diện tích và 55% công suất (bản black box ở 20 ns, `asic/README.md`) |

## 3. Từng khối

### 3.1 Boot ROM và golden hash
- **Là gì.** Bộ nhớ 4 KB chỉ đọc ở `0x0000_0000`. Chứa mã khởi động của Master và golden hash ở `0xFE0`.
- **Để làm gì.** Giữ mã và vân tay chuẩn mà không ai sửa được. Đây là gốc tin cậy.
- **Vì sao chọn.** Gốc tin cậy phải nằm ở chỗ không ghi được, nên ghi vào ROM trả lỗi `SLVERR`.
- **Thiếu thì sao.** Nếu golden hash sửa được thì kẻ tấn công sửa luôn vân tay chuẩn và qua mặt kiểm tra (SR-04).
- **Chứng minh.** `rtl/mem/Dual_Port_ROM.v`, test `SoC_Top_tb` (ghi ROM trả `SLVERR`).

### 3.2 Lõi SHA-256
- **Là gì.** Khối phần cứng tính SHA-256. Có thanh ghi nhận 16 từ của một khối, thanh ghi điều khiển và 8 từ kết quả (`SHA256_Wrapper.v`).
- **Để làm gì.** Tạo vân tay của ảnh App.
- **Vì sao chọn.** Băm bằng phần mềm trên lõi RISC-V chậm và tốn thời gian CPU. Phần cứng làm một vòng mỗi chu kỳ.
- **Thiếu thì sao.** Vẫn băm được bằng phần mềm (thư viện HAL có bản phần mềm, `fw/hal/sha256_hal.c`), nhưng chậm hơn nhiều. Không có hàm băm thì không có cách phát hiện ảnh bị sửa.
- **Chứng minh.** Đúng vector NIST, UVM scoreboard so với chương trình tham chiếu, khớp `sha256sum` ở mọi độ dài (`docs/verification/SHA256_UVM_TestPlan.md`, sheet P-04, P-08).

### 3.3 Boot_Verifier
- **Là gì.** Khối phần cứng quyết định App có được chạy không (`rtl/periph/Boot_Verifier.v`). Tự lấy golden hash từ Boot ROM và so với digest SHA-256.
- **Để làm gì.** Tạo cờ `VERIFIED` do phần cứng tính. Chỉ khi cờ này lên thì SYSCSR mới nhả lõi App.
- **Vì sao chọn.** Trước đây firmware tự quyết định nhả App. Firmware lỗi hoặc bị glitch có thể bỏ qua bước so hash. Giờ firmware không giả được kết quả (SR-02, SR-03).
- **Thiếu thì sao.** Một dòng lệnh sai trong firmware là App chưa kiểm vẫn chạy.
- **Còn làm gì.** Từ chối nếu `APP_VER < MIN_VER` (SR-06). `KEY_LOCK` khóa khóa HMAC rồi đọc ra 0 (SR-07).
- **Chứng minh.** `Boot_Verifier_tb` 30/30: sai một bit ở từ 0 và từ 7, SHA chưa xong, SHA bận, rollback 4 nhỏ hơn 5.

### 3.4 SYSCSR: giữ reset App, Boot Guard, xóa RAM, ghi lỗi bus
- **Là gì.** Khối thanh ghi hệ thống ở `rtl/periph/SYSCSR.v`. Sinh reset của thế giới Secure và giữ lõi App trong reset.
- **Để làm gì.**
  - `app_rst = sys_rst_q | ~app_run | lock_q`: App chạy chỉ khi được nhả và chưa bị khóa (SR-01).
  - Ghi `APP_RUN` sớm bị bỏ qua nếu chưa `VERIFIED` (SR-02).
  - Boot Guard: ghi `GUARD.LOCK` thì App bị giữ reset vĩnh viễn và RAM App bị xóa (SR-05). Cờ `lock_q` chỉ POR mới xóa được.
  - `BUS_ERR` và `BUS_ERR_ADDR` ghi lại lỗi bus đầu tiên cho firmware đọc (SR-11).
- **Vì sao chọn.** Cần một nơi phần cứng nắm quyền reset, không để firmware tự thả.
- **Thiếu thì sao.** Không có Boot Guard thì ảnh xấu vẫn nằm đó và chạy lại sau reset mềm.
- **Chứng minh.** `APB_Periph_tb` (LOCK, quét RAM, giữ qua reset mềm), `SoC_Top_tb +TAMPER`.

### 3.5 Secure DMA
- **Là gì.** Khối phần cứng chép dữ liệu (`rtl/bus/Secure_DMA.v`). Tự đọc 4 KB ROM của App qua bus và ghi vào thanh ghi SHA-256, từng khối 64 byte, rồi thêm khối đệm.
- **Để làm gì.** Băm cả ảnh App mà CPU không phải đọc từng từ.
- **Vì sao chọn.** Nhanh hơn: DMA băm 17.026 chu kỳ, CPU băm 34.143 chu kỳ (ghi chú P-15 trong sheet). Ngoài ra CPU của Master không phải đụng vào ảnh App.
- **Thiếu thì sao.** Vẫn secure boot được: CPU tự đọc ROM App rồi nạp vào SHA-256, chậm khoảng gấp đôi. **DMA là phần tối ưu hiệu năng, không bắt buộc cho tính đúng.** Xem mục 7.
- **Chứng minh.** `SoC_Fw_tb`: DMA chạy một lần, không lỗi firewall hay bus.

### 3.6 DMA_Firewall
- **Là gì.** Mạch tổ hợp ở cổng bus của DMA (`rtl/bus/DMA_Firewall.v`). Chỉ cho đọc ROM App (`0x6000_0000` rộng 4 KB) và thanh ghi `STATUS` của SHA-256. Chỉ cho ghi `0x5000_0000` tới `0x5000_0043`. Mọi thứ khác bị chặn.
- **Để làm gì.** Dù thanh ghi DMA bị cấu hình sai, nó cũng không đọc được RAM hay ngoại vi (SR-08, kẻ tấn công A4).
- **Vì sao chọn.** DMA là một master bus riêng, quyền rất rộng nếu không kiểm soát.
- **Thiếu thì sao.** Nếu không có DMA thì không cần tường lửa. Tường lửa tồn tại vì có DMA.
- **Chứng minh.** `SoC_Top_tb`: DMA trỏ vào RAM Master bị chặn (`ERR_FW`), không có yêu cầu nào lọt ra ngoài cửa sổ cho phép.

### 3.7 Bus Secure và default slave
- **Là gì.** Bus AXI4-Lite của thế giới Secure: một master dùng chung cho CPU và DMA (luân phiên), giải mã địa chỉ tới 6 slave, cầu AXI sang APB. Địa chỉ không ai nhận trả `DECERR` (`rtl/top/SoC_Top.v`).
- **Để làm gì.** Nối các khối lại. Bus không bao giờ treo vì mọi địa chỉ đều có người trả lời.
- **Thiếu thì sao.** Địa chỉ lạ có thể lặp lại về bộ nhớ thật (SR-10). Đã sửa lỗi này ở SHA-256 trong lúc kiểm chứng bằng UVM (sheet P-08).
- **Chứng minh.** `SoC_Top_tb` (`DECERR_R=4`).

### 3.8 Thế giới App
- **Là gì.** Lõi App, ROM, RAM và bus APB riêng (UART1, GPIO1, TIMER1, hộp thư). Không có đường nào tới bus Secure (SR-09).
- **Để làm gì.** Dù App bị chiếm, nó không chạm được tài nguyên Secure (kẻ tấn công A2). Hai thế giới chỉ nói chuyện qua cổng B chỉ đọc của ROM App và hộp thư.
- **Vì sao chọn.** Cách ly bằng cách không có dây nối an toàn hơn cách ly bằng cấp quyền, vì lõi chỉ có chế độ máy (giới hạn L7).
- **Chứng minh.** `SoC_App_tb`, đọc `SoC_Top.v`.

### 3.9 Lõi RISC-V
- **Là gì.** Lõi RV32I viết tay, đường ống 5 tầng IF, ID, EX, MEM, WB (`rtl/top/RISCV_Core.v`, `rtl/core/`). Có Zicsr, ngắt và bẫy lỗi máy, load và store byte hoặc nửa từ, forwarding, phát hiện hazard.
- **Để làm gì.** Chạy firmware: Master chạy secure boot, App chạy ứng dụng.
- **Vì sao chọn.** Tự viết để hiểu và kiểm soát được từng khối. RISC-V là tập lệnh mở.
- **Thiếu thì sao.** Không có lõi thì không có gì chạy secure boot.
- **Chứng minh.** 11 testbench đơn vị, chương trình ISA 37 lệnh, `RISCV_Core_tb` 44/44, hazard không cần NOP, trap (sheet P-02, P-09). Phần cứng không có dự đoán nhánh hay làm hiệu năng cao.

### 3.10 Ngoại vi và ngắt
| Khối | Là gì | Dùng để | Thiếu thì sao |
| --- | --- | --- | --- |
| UART0 | Cổng nối tiếp | In nhật ký secure boot | Không thấy log, vẫn chạy |
| GPIO0 | Chân vào ra | Hiện mã kết quả trên LED | Không thấy kết quả trên board |
| TIMER0, WDT | Bộ đếm giờ và watchdog | WDT hết giờ sau 1 s nếu không được kick, firmware kick liên tục. Treo thì WDT reset và cờ khóa vẫn giữ (`secure_boot.c`) | Firmware treo thì chip đứng |
| PLIC-lite | Gom 8 nguồn ngắt thành `irq_ext` | Cho lõi nhận ngắt từ DMA, UART, GPIO | Phải dò thay vì ngắt |
| Hộp thư | Một từ mỗi chiều giữa hai thế giới | App gửi tin, Master in ra UART0 | App và Master không nói chuyện được |
| UART1, GPIO1, TIMER1 | Ngoại vi của App | App chạy demo (LED theo TIMER1) | App không có gì để chạy |

## 4. Secure Boot từng bước

Nguồn: `fw/secure_boot/secure_boot.c` (hàm `secure_boot_run`).

| Bước | Việc | Dòng | Nếu sai |
| --- | --- | --- | --- |
| 1 | Bật UART log, bật WDT 1 s, tự kiểm SHA-256 bằng vector NIST | 122 đến 127 | `fail` rồi khóa App |
| 2 | Xóa `BUS_ERR`, băm 4 KB ROM App bằng DMA | 129 đến 131 | Lỗi bus, DMA bị tường lửa chặn hoặc quá giờ thì `fail` |
| 3 | Đọc golden hash từ Boot ROM, kiểm lại `BUS_ERR` | 149 đến 151 | Lỗi bus thì `fail` |
| 4 | So hash với golden, so theo thời gian không đổi | 152 đến 153 | Lệch thì `fail` ("Hash mismatch") |
| 5 | Đọc `APP_VER`, gọi Boot_Verifier `CHECK` trên digest DMA để lại | 156 đến 166 | Không `VERIFIED` thì `fail` |
| 6 | `KEY_LOCK`, ghi `APP_RUN = 1`, đọc lại phải thấy 1 | 167 đến 173 | Cổng giữ App thì `fail` |
| 7 | Hiện kết quả trên LED, chờ UART xả | 173 | |

`fail` luôn làm theo thứ tự: kick WDT, khóa khóa HMAC, in lý do, ghi `GUARD.LOCK`, chờ máy trạng thái xóa RAM xong (`ZERO_DONE`). Nếu xóa không xong thì báo `SB_HW_ERROR` và App vẫn bị giữ reset. Nguyên tắc: **mọi lỗi đều rơi về trạng thái an toàn**, không có lỗi nào mở App.

Hình: `docs/diagrams/png/11_secure_boot_flow.png` (mọi nhánh) và `12_tamper_and_lockdown_flow.png`.

## 5. Công cụ và flow

| Công cụ | Làm gì | Câu hỏi nó trả lời | Lệnh |
| --- | --- | --- | --- |
| QuestaSim | Mô phỏng RTL | Thiết kế có chạy đúng không | `make test` |
| SystemC (VP) | Mô hình phần mềm của SoC | Firmware chạy được trước khi có RTL không | `make vp` |
| Quartus II 13.0sp1 | Tổng hợp, xếp chân, đo thời gian cho DE2 | Có vừa chip FPGA không, đạt 50 MHz không | `make de2` |
| Vivado 2025.2 | Như trên cho Artix-7 và KV260 | Như trên | `make xilinx`, `make kv260` |
| Genus | Tổng hợp ra cell chuẩn GPDK45 của ASIC | Diện tích, thời gian, công suất | `make asic-genus` |
| Conformal (LEC) | So netlist với RTL | Netlist có đúng bằng RTL không | `make asic-lec` |
| Xcelium (GLS) | Mô phỏng netlist | Netlist có boot đúng không | `make asic-gls` |
| Innovus | Đặt, đi dây, cây clock (layout) | Chip thật trông thế nào, có lỗi quy tắc không | `make asic-innovus` (chưa xong) |
| Tempus | Phân tích thời gian sau khi có dây thật | Thời gian có đạt khi có dây thật | `make asic-sta` |

### Thời gian: slack, WNS, đường găng
- **Chu kỳ clock** là khoảng thời gian một nhịp. 20 ns là 50 MHz.
- **Đường găng** là đường tín hiệu dài nhất giữa hai flip-flop mà phải xong trong một chu kỳ. Nó quyết định tần số tối đa, giống đoạn chậm nhất trong một đoàn xe.
- **Slack** là thời gian còn dư: slack bằng thời gian yêu cầu trừ thời gian tín hiệu thật sự đến. Dương là đạt, âm là trượt.
- **WNS** là slack của đường xấu nhất. **TNS** là tổng các slack âm.
- **F_max** ước lượng bằng 1 chia (chu kỳ trừ WNS) (`asic/README.md`).

**Ví dụ thật** (`asic/reports/genus_macro/synthesis/timing.rpt`, bản `SRAM=1 ROM=1`, chu kỳ 20 ns, Genus 18/11):

| Mục | Giá trị |
| --- | --- |
| Điểm đầu | `master_core_u_EX_MEM_Reg/Rd_MEM_reg[1]`, thanh ghi chứa số thanh ghi đích của lệnh đang ở tầng MEM |
| Đi qua | `Forwarding_Unit` (quyết định có chuyền tắt không), rồi bộ so sánh nhỏ hơn của ALU |
| Điểm cuối | `PC[31]`, thanh ghi bộ đếm chương trình |
| Thời gian đường dữ liệu | 12,620 ns |
| Setup và độ bất định | 0,106 ns và 0,150 ns |
| Yêu cầu | 20 − 0,106 − 0,150 = 19,744 ns |
| Slack | 19,744 − 12,620 = **+7,124 ns** |

Hiểu: lệnh nhánh so sánh hai thanh ghi ở tầng EX, cần dữ liệu chuyền tắt từ tầng sau, nên đường qua forwarding và ALU rồi chọn PC mới là đường dài nhất của lõi. Đường này **không đi qua ROM**, nên ROM làm bằng logic không làm chậm tần số tối đa.

### PPA
- P là hiệu năng (tần số), P là công suất, A là diện tích. Ba thứ đánh đổi nhau.
- **FPGA** là mảng khối logic lập trình sẵn. Đo bằng LE hoặc LUT, bit bộ nhớ, MHz. **ASIC** là chip tự thiết kế bằng cell chuẩn. Đo bằng µm². Hai loại số không so trực tiếp được.
- Công suất Genus dùng hoạt động chuyển mạch mặc định, chỉ dùng để so giữa các lần chạy (`asic/README.md`).

### LEC và GLS
- **LEC** chứng minh toán học rằng netlist sau tổng hợp làm đúng như RTL. Kết quả cần là 0 điểm không tương đương.
- **GLS** chạy lại testbench trên netlist. Hai thứ bổ sung nhau: LEC chặt về logic, GLS thấy hành vi khi chạy.

### Bộ nhớ cho ASIC
- Bản FPGA dùng bộ nhớ trong chip FPGA, mô tả bằng RTL.
- Bản ASIC dùng macro SRAM của trường cho hai RAM. Macro không có nội dung sẵn lúc bật nguồn nên không làm ROM được. Hai ROM thành logic sinh từ file hex bằng `fw/tools/gen_rom_v.py`. Diện tích ROM logic 12.204 µm², nhỏ hơn 16.000 µm² nếu dùng hai macro cho ROM (`asic/README.md`).
- Macro đọc ở cạnh lên, trễ một chu kỳ, nên lõi App phải chờ bằng `bus_stall`. Đã mô phỏng đạt, và buổi chạy server 18/11 đạt LEC và GLS.

## 6. Các con số của đồ án

| Con số | Nghĩa | Nguồn |
| --- | --- | --- |
| 32 mục `make test` đạt | Bộ kiểm tự động: lõi, UVM, SoC, firmware thật, ASIC_Top, macro RAM, ROM logic, VP | `sim/regress.sh`, chạy 16/11 |
| DE2: 10.982 LE (33% của 33.216) | Logic chiếm một phần ba chip EP2C35 | `docs/project/PPA_FPGA.md` |
| DE2: 135.168 bit bộ nhớ (28% của 483.840) | Bốn bộ nhớ 4 KB nằm gọn trong M4K | như trên |
| DE2: Fmax 54,07 MHz, 52 chân | Đạt 50 MHz. 52/52 chân khớp sổ tay DE2 | như trên, sheet N-18 |
| Artix-7: WNS +3,228 ns, WHS +0,018 ns | Đạt setup và hold ở 50 MHz | `PPA_FPGA.md` |
| KV260: WNS +5,517 ns, WHS +0,011 ns | Như trên, clock 50 MHz từ PS | `PPA_FPGA.md` |
| ASIC bản `SRAM=1 ROM=1`: 101.597 µm² | Tổng gồm hai macro 16.000 µm², logic 85.597 µm² | `asic/README.md` |
| ASIC: 7.117 flip-flop, 98,3% được gate | Gần hết flip-flop dùng clock gating | như trên |
| ASIC: WNS +7,124 ns ở 20 ns | Dư nhiều. Genus còn đạt đến 6 ns | như trên |
| Chu kỳ chốt 11 ns (khoảng 91 MHz) | Nhỏ nhất mà WNS còn ít nhất 10% chu kỳ | `asic/README.md`, Phát chốt 18/11 |
| LEC PASS, 0 điểm không tương đương | Netlist bằng RTL | như trên |
| GLS PASS, boot 535.898 chu kỳ | Netlist boot ra LED 0x01 | như trên |

## 7. Khối nào là lõi, khối nào là mở rộng

Thầy nhận xét System đang quá rộng. Đây là phân loại của nhóm dựa vào bảng truy vết SR-01 đến SR-11 trong `Security_Model.md`. Khối nào có yêu cầu bảo mật riêng là lõi.

| Nhóm | Khối | Căn cứ |
| --- | --- | --- |
| Lõi Secure | Lõi Master, Boot ROM, SHA-256, Boot_Verifier, SYSCSR (giữ reset, khóa, xóa RAM, ghi lỗi bus), ROM và bus App tách biệt, `DECERR` | SR-01 tới SR-07, SR-09 tới SR-11 |
| Hỗ trợ demo | UART0, GPIO0, WDT, bus AXI4-Lite, lõi App và ROM, RAM của nó | Cần tối thiểu để thấy kết quả và có thứ để bảo vệ |
| Mở rộng System | Secure DMA và tường lửa, PLIC-lite, hộp thư, UART1, GPIO1, TIMER1, VP, bộ kiểm cho FPGA nhiều kit | Không có yêu cầu SR riêng. Tường lửa DMA (SR-08) chỉ tồn tại vì có DMA |

**Nói thẳng về DMA.** DMA không cần cho tính đúng của secure boot. Nó làm băm nhanh gấp đôi và đưa CPU ra khỏi việc đọc ảnh App. Nó cũng tạo thêm một master bus phải canh bằng tường lửa. Có thể trình bày DMA như một phần tối ưu đã làm và đã kiểm, không phải tính năng bảo mật cốt lõi. RTL không có tham số tắt DMA, tắt thì phải sửa RTL đã freeze.

**Về DE2.** Thiết kế đã tổng hợp, xếp chân và đạt thời gian trên DE2 bằng Quartus (mục 6). Thầy không yêu cầu nạp board.

## 8. Các câu thầy có thể hỏi

1. **Vì sao cần hai lõi?** Cần một bên tin cậy để kiểm bên kia. Lõi Master chạy từ ROM không sửa được và quyết định khi nào lõi App được chạy. Cách ly bằng bus riêng chắc hơn cách ly bằng quyền, vì lõi chỉ có chế độ máy.
2. **Hàm băm dùng để làm gì ở đây?** Tạo vân tay của ảnh App. Sửa một bit thì vân tay đổi, nên so với vân tay chuẩn là biết có bị sửa không.
3. **Sao không để firmware tự so hash?** Firmware lỗi hoặc bị glitch có thể bỏ qua bước so. Boot_Verifier phần cứng tự so lại, và App chỉ được nhả khi phần cứng báo `VERIFIED`.
4. **DMA để làm gì, bỏ được không?** Để băm nhanh gấp đôi mà CPU không đọc ảnh. Bỏ được, secure boot vẫn đúng. Nhóm nhận DMA là phần tối ưu, không phải lõi bảo mật.
5. **Chạy được trên DE2 không?** Đã tổng hợp và đạt thời gian trên EP2C35: 33% logic, 28% bộ nhớ, 54,07 MHz, 52/52 chân khớp. Chưa nạp board vì không yêu cầu.
6. **Đường găng là gì, của mình ở đâu?** Đường chậm nhất trong một chu kỳ. Của lõi là từ thanh ghi đích tầng MEM qua forwarding và bộ so sánh ALU tới PC, 12,62 ns ở bản 20 ns.
7. **Tần số bao nhiêu?** FPGA đạt 50 MHz. ASIC tổng hợp đạt tới 6 ns, nhóm chốt 11 ns (khoảng 91 MHz) để dư biên 10%.
8. **ASIC khác FPGA chỗ nào?** FPGA là khối lập trình sẵn, ASIC là cell chuẩn đặt và đi dây. Đo bằng đơn vị khác nhau nên không so trực tiếp.
9. **Vì sao ROM thành logic?** Macro SRAM không giữ nội dung lúc bật nguồn. ROM logic sinh từ file hex, tốn 12.204 µm², ít hơn hai macro.
10. **Chống được kẻ tấn công nào?** A1 (ảnh sửa hoặc ảnh cũ), A2 (App bị chiếm), A3 (glitch phần mềm), A4 (DMA cấu hình sai). Không chống glitch điện áp, kênh phụ, thăm dò vật lý.
11. **Giới hạn lớn nhất?** Khóa HMAC là hằng trong RTL, không có chữ ký bất đối xứng, `MIN_VER` xóa khi cấp nguồn lại vì FPGA không có bộ nhớ không mất dữ liệu, lõi không có phân quyền.
12. **Test nào chứng minh?** `make test` 32 mục. Ảnh sửa bị khóa và RAM bị xóa (`SoC_Top_tb +TAMPER`), ghi `APP_RUN` sớm bị từ chối (`Boot_Verifier_tb`), DMA ra ngoài vùng bị chặn.
13. **Vì sao có PLIC, hộp thư, UART1, TIMER1?** Chúng là phần mở rộng của System, không có yêu cầu bảo mật riêng. Nhóm đồng ý dừng mở rộng.
14. **Thiết kế có phụ thuộc firmware không?** ROM logic cố định firmware trong netlist, đổi firmware thì chạy lại `make rom-images` và Genus.
15. **Hướng tiếp theo?** Trước mắt hoàn thiện ASIC tới layout (Innovus, Tempus). Sau đó đào sâu Secure (xử lý giới hạn L2 tới L12, thêm test tấn công). Dừng thêm tính năng System.

## 9. Giới hạn đã biết

Nguồn: `docs/spec/Security_Model.md`. Nói thật các giới hạn này tốt hơn để thầy tự phát hiện.

| Nhóm | Giới hạn |
| --- | --- |
| Khóa và xác thực | Khóa HMAC là hằng demo (L3). Chỉ so hash hoặc HMAC, không có chữ ký bất đối xứng (L4). `APP_VER` do firmware ghi trước `CHECK` (L5) |
| Lưu trữ | `MIN_VER` và `KEY_LOCK` xóa khi POR, FPGA không có bộ nhớ không mất dữ liệu (L2) |
| Lõi | Chỉ chế độ máy, không có PMP (L7). Không có cổng debug (L8) |
| Tấn công vật lý | Không chống glitch điện áp hay xung nhịp (L9) |
| Quy ước chưa có phần cứng chặn | CPU không đụng SHA-256 khi DMA bận (L10). Không `lw` Boot ROM lúc `CHECK` khoảng 9 chu kỳ (L12a) |
| Phạm vi xóa | Zeroization chỉ xóa RAM App, không xóa hộp thư và thanh ghi lõi (L11) |

## 10. Chỗ chưa chắc của tài liệu này

- Cột "thiếu thì sao" dựa vào mô tả và bảng truy vết, nhóm chưa chạy thử tắt từng khối.
- Phân loại "lõi", "hỗ trợ", "mở rộng" ở mục 7 là đánh giá của mình, chưa phải của thầy hay của đề cương.
- Số chu kỳ DMA và CPU (17.026 và 34.143) lấy từ ghi chú trong sheet, mình chưa chạy lại.
- SHA-256: đã đo bằng mô phỏng 22/11 (khối "abc", hash khớp FIPS 180-4). `busy` lên 65 chu kỳ như chú thích trong `SHA256_Core.v`, và `done` lên ở cạnh thứ 66 tính từ cạnh nhận `start`, khớp số 66 của sheet N-07. Hai số đều đúng, khác nhau ở chỗ có tính chu kỳ nhận lệnh hay không.
- Số liệu ASIC là của buổi chạy server 18/11 do Phát chạy, Innovus chưa chạy xong.
- Chưa có đề cương chính thức trong tay, nên chưa biết đề cương nói gì về SoC.
