# Tài liệu HRoT_SoC

Tiến độ, hạn và các giao diện đã chốt (I-xx) nằm ở [Google Sheet "HRoT_SoC — Tiến độ Đồ án 2"](https://docs.google.com/spreadsheets/d/13jJj9UP1Cxr8ZNFqzQnNTaiulD2_HaKOWAONfCnZnU4/edit). Khi sheet và file ở đây lệch nhau thì theo sheet.

| Thư mục | File | Nội dung | Người giữ |
| --- | --- | --- | --- |
| `spec/` | [SoC_Memory_Map.md](spec/SoC_Memory_Map.md) | Bản đồ địa chỉ và thanh ghi của thế giới Secure (bus, SYSCSR, UART, GPIO, TIMER, WDT, ngắt) | Nguyên |
| `spec/` | [SHA256_Register_Map.md](spec/SHA256_Register_Map.md) | Thanh ghi và hợp đồng phần cứng–HAL của khối SHA-256 | Phát |
| `spec/` | [Core_Datapath.md](spec/Core_Datapath.md) | Sơ đồ khối datapath lõi RISC-V 5 tầng, đối chiếu module RTL và tín hiệu stall/flush/forward | Phát |
| `verification/` | [SHA256_UVM_TestPlan.md](verification/SHA256_UVM_TestPlan.md) | Kế hoạch kiểm chứng UVM cho SHA-256 | Phát |
| `guides/` | [Dev_Guide.md](guides/Dev_Guide.md) | Phân công, giao kèo của lõi, cách chạy kiểm tra, quy ước code | Phát |
| `project/` | [Project_Plan.md](project/Project_Plan.md) | Kế hoạch tổng thể, mốc, lộ trình theo tuần | Phát |
| `project/` | [Project_Status.md](project/Project_Status.md) | Trạng thái kỹ thuật hiện tại và các điểm cần lưu ý | Phát |

Đổi bản đồ địa chỉ hay giao diện giữa hai người: sửa file trong `spec/`, cập nhật tab "Mốc & Giao diện" trong sheet và báo người còn lại trước.
