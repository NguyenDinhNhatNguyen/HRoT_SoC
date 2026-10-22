# Plan Đồ án 2 — HRoT SoC

> Chuyển từ `Plan Đồ án 2.pdf`. Khi plan thay đổi, sửa trực tiếp file này.

## 1. Tên dự án

Thiết kế hệ thống SoC Đa lõi Bất đối xứng (AMP) tích hợp Cơ chế Cách ly Vật lý và Khởi động Bảo mật (Hardware Root of Trust & Secure Boot).

## 2. Kiến trúc hệ thống

- **Physical Isolation:** 2 lõi RISC-V 5-stage pipeline hoàn toàn độc lập, mỗi lõi có không gian bộ nhớ (ROM/RAM) và hệ thống Bus riêng biệt.
- **Giao thức Bus:** toàn hệ thống dùng chuẩn AMBA AXI4-Lite.
- **Master Core (Secure Core):** có lõi gia tốc phần cứng SHA-256 trên bus; nắm giữ tín hiệu Reset của App Core.
- **App Core:** lõi chạy ứng dụng, bị "đóng băng" khi cấp điện, chỉ được đánh thức khi Master xác nhận an toàn.
- **Cross-Memory Access:** ROM của App Core là Dual-Port ROM.
  - Port A nối với mạch Fetch của App Core.
  - Port B nối như một **Slave vào Bus AXI4-Lite của Master**.

## 3. Flow làm việc

| Việc | Công cụ |
|---|---|
| Code | VS Code trên Windows |
| Build Firmware | WSL2 (Ubuntu) + GCC RISC-V + Makefile (tự động dịch C/C++ sang Hex) |
| Simulation | QuestaSim (logic mạch + kiểm chứng Firmware Secure Boot) |
| Synthesis & PPA | Xilinx Vivado (Fmax, Area, Power theo Timing Constraints SDC) |
| ASIC PD (Tháng 4) | Cadence Genus/Innovus, 90nm/45nm |

## 4. Phân vai

**Nguyên — System Architect & PPA Lead**
- AXI4-Lite Interconnect (Master/Slave interfaces).
- Lõi SHA-256 bằng Verilog, tối ưu bằng chia nhỏ State Machine để giữ Fmax.
- System Integration: ghép Master Core, App Core, Dual-Port ROM, Reset Controller.
- Physical Design FPGA: báo cáo Vivado, Timing Constraints, tối ưu PPA.
- Virtual Platform (SystemC/TLM 2.0).

**Phát — Core RTL & Firmware Lead** (kiêm DV/UVM và ASIC PD)
- Lõi RISC-V 5-stage: Data Forwarding, Hazard Stalling, Control Hazard; chạy ổn định ở tần số cao.
- Toolchain & WSL2: Makefile tự động build C/C++.
- Secure Boot Firmware cho Master Core: đọc bộ nhớ App → đẩy vào SHA-256 phần cứng → đọc Hash → so với mã gốc → nhả Reset cho App.
- UVM (Tuần 5–11), ASIC PD (Tuần 13–14).

## 5. Lộ trình

### Tháng 1 — Nền móng Pipeline & Virtual Platform
Mục tiêu: lõi RISC-V 5-stage chống xung đột dữ liệu; môi trường SystemC/TLM 2.0.

| Tuần | Nguyên | Phát |
|---|---|---|
| 1 | Thiết lập WSL2, GCC RISC-V, Makefile, QuestaSim. Khởi tạo SystemC/TLM 2.0. Code Instruction_Memory, Data_Memory | Sơ đồ khối Datapath 5 tầng. Khai báo tín hiệu 4 thanh ghi trung gian (IF_ID, ID_EX, EX_MEM, MEM_WB) |
| 2 | TLM 2.0 Dummy Initiator giả lập CPU kiểm tra bus trên VP | RTL tầng IF (PC) và ID (Decoder, Control Unit, Register File) |
| 3 | Testbench SystemVerilog cơ bản trên QuestaSim; hỗ trợ debug | RTL tầng EX, MEM, WB. Ghép 5 tầng thành lõi thô |
| 4 | Forwarding Unit & Hazard Detection Unit | Tích hợp Hazard vào Datapath. Viết Assembly test. Cùng nghiệm thu lõi trên QuestaSim |

### Tháng 2 — AXI4-Lite, lõi gia tốc & UVM
Mục tiêu: đưa hệ thống lên AXI4-Lite, tích hợp phần cứng mã hóa, thiết lập luồng DV.

| Tuần | Nguyên | Phát |
|---|---|---|
| 5 | AXI4-Lite Master/Slave Interface. Bọc ngoại vi bằng TLM Target Socket trên VP | Cấu trúc UVM trên QuestaSim (Agent, Sequencer, Driver, Monitor, Scoreboard) |
| 6 | RTL lõi SHA-256, State Machine 64 chu kỳ | HAL (C/C++) cho SHA-256. Test Plan cho UVM |
| 7 | Đóng gói SHA-256 thành AXI4-Lite Slave. Tổng hợp Vivado cục bộ kiểm Critical Path | UVM Sequence bơm giao dịch AXI4-Lite ngẫu nhiên vào SHA-256 ép corner case |
| 8 | Dual-Port ROM và Reset Controller | Dùng VP viết và chạy thử Firmware Secure Boot (C/C++) |

### Tháng 3 — Lắp ráp SoC, FPGA & UVM Coverage
Mục tiêu: SoC Top-level, Secure Boot chạy trên FPGA, chốt số liệu kiểm thử.

| Tuần | Nguyên | Phát |
|---|---|---|
| 9 | Lắp ráp `SoC_Top.v` cách ly hoàn toàn. Tổng hợp, Pin Planner, đổ xuống FPGA (DE2-115 / Kria KV260) | Tinh chỉnh Firmware Secure Boot, thêm địa chỉ UART in log ra Terminal |
| 10 | Tích hợp IP UART. Test thực tế trên FPGA, đo độ ổn định luồng khởi động | Bơm dữ liệu nhiễu vào UVM khi chạy Full SoC |
| 11 | Xử lý Negative Slack (chèn Pipeline Register), ép Fmax | Covergroup trong UVM, xuất báo cáo Functional Coverage |
| 12 | Clean RTL, Timing Constraints chuẩn SDC bàn giao luồng ASIC | Code Application cho App Core để demo |

### Tháng 4 — ASIC Physical Design, so sánh PPA & Mock Defense
Mục tiêu: RTL qua luồng ASIC back-end, PPA mức cổng, bảo vệ đồ án.

| Tuần | Nguyên | Phát |
|---|---|---|
| 13 | Báo cáo PPA cuối từ Vivado (Fmax, Total Power, LUTs, FFs) | RTL qua Cadence Genus/Innovus 90nm/45nm, Synthesis gate-level |
| 14 | Sơ đồ khối kiến trúc hệ thống, kiến trúc VP, sơ đồ testbed FPGA | Báo cáo PPA Cadence (Cell Area, Leakage, Dynamic Power). Bảng so sánh FPGA vs ASIC |
| 15 | Tài liệu hướng dẫn chạy VP và đổ FPGA | Push code sạch lên GitHub theo cấu trúc VP/RTL/DV/PD/FW/SYN. README chi tiết |
| 16 | **Chung:** Báo cáo tổng kết. Slide nhấn mạnh 4 luồng: HRoT/Isolation (RTL), TLM 2.0 (VP), UVM Coverage (DV), Gate-level PPA (PD). Mock Defense trước thầy hướng dẫn | |

## 6. Hỗ trợ từ Mentor

1. **Kiến trúc:** sơ đồ kết nối AXI4-Lite và Dual-Port ROM (cách Master "đọc trộm" bộ nhớ an toàn).
2. **RTL:** gửi code SHA-256 / Hazard Unit khi bị vướng để được chỉ điểm nghẽn logic.
3. **PPA:** hướng dẫn chia nhỏ State Machine (pipelining accelerator) hoặc chèn register khi Vivado âm slack.
4. **Bảo vệ:** bộ câu hỏi phản biện, ví dụ "Tại sao dùng Hardware SHA-256 thay vì Software Hash?", "Dual-Port ROM có thực sự cách ly vật lý không?".
