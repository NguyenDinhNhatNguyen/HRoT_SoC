/* ============================================================================
 * sha256_regs.h -- Register map của SHA-256 AXI4-Lite Slave (SHA256_Wrapper)
 *
 * Đây là NGUỒN SỰ THẬT DUY NHẤT về địa chỉ/bit của ngoại vi SHA-256 phía phần
 * mềm. Khi RTL (Nguyên) hoặc VP đổi map, chỉ sửa file này.
 *
 * Địa chỉ nền 0x5000_0000 và các offset 0x40 (CTRL) / 0x44 (STATUS) / 0x50
 * (HASH[0]) trùng với RTL hiện tại (SHA256_Wrapper.v) và VP
 * (SHA256_VP_Wrapper.h). Các offset còn lại là phần mở rộng ĐỀ XUẤT cho đủ
 * khối 512-bit và digest 256-bit -- cần Nguyên xác nhận (xem doc/SHA256_Register_Map.md).
 *
 *   Offset      Tên           Truy cập  Mô tả
 *   0x00-0x3C   BLOCK[0..15]  W         Khối message 512-bit. BLOCK[0] = W0 (word
 *                                       đầu, byte đầu của message ở bit [31:24]).
 *   0x40        CTRL          W         bit0 START (tự xóa), bit1 INIT
 *   0x44        STATUS        R         bit0 DONE (sticky), bit1 BUSY
 *   0x48-0x4C   (reserved)    -         Đọc 0, ghi bị bỏ qua
 *   0x50-0x6C   HASH[0..7]    R         Digest 256-bit. HASH[0] = H0 = bit [255:224]
 * ========================================================================== */
#ifndef SHA256_REGS_H
#define SHA256_REGS_H

#include <stdint.h>

#ifndef SHA256_BASE_ADDR
#define SHA256_BASE_ADDR     0x50000000u
#endif

#define SHA256_REG_BLOCK(i)  (0x00u + 4u * (uint32_t)(i))   /* i = 0..15 */
#define SHA256_REG_CTRL      0x40u
#define SHA256_REG_STATUS    0x44u
#define SHA256_REG_HASH(i)   (0x50u + 4u * (uint32_t)(i))   /* i = 0..7  */

#define SHA256_BLOCK_WORDS   16u
#define SHA256_HASH_WORDS    8u

/* CTRL */
#define SHA256_CTRL_START    (1u << 0)  /* Bắt đầu nén 1 khối (64 vòng)                */
#define SHA256_CTRL_INIT     (1u << 1)  /* Nạp IV H0..H7 trước khi nén (khối đầu tiên)  */

/* STATUS */
#define SHA256_STATUS_DONE   (1u << 0)  /* Đã xong, giữ đến khi có START kế tiếp       */
#define SHA256_STATUS_BUSY   (1u << 1)  /* Đang nén                                    */

/* ---- Truy cập thanh ghi ----------------------------------------------------
 * Trên SoC: truy cập MMIO volatile.
 * Trên máy host (-DHAL_HOST_MODEL): chuyển hướng vào mô hình ngoại vi giả lập
 * để chạy unit test trong WSL mà không cần phần cứng/VP.                      */
#ifdef HAL_HOST_MODEL
uint32_t hal_host_read32(uint32_t offset);
void     hal_host_write32(uint32_t offset, uint32_t value);
#define SHA256_RD(off)       hal_host_read32((uint32_t)(off))
#define SHA256_WR(off, val)  hal_host_write32((uint32_t)(off), (uint32_t)(val))
#else
#define SHA256_RD(off) \
    (*(volatile uint32_t *)((uintptr_t)SHA256_BASE_ADDR + (uintptr_t)(off)))
#define SHA256_WR(off, val) \
    (*(volatile uint32_t *)((uintptr_t)SHA256_BASE_ADDR + (uintptr_t)(off)) = (uint32_t)(val))
#endif

/* Đọc 1 word 32-bit từ vùng nhớ (ROM của App qua Dual-Port ROM). Luôn truy cập
 * 32-bit căn lề: bus AXI4-Lite không có truy cập byte. */
#ifdef HAL_HOST_MODEL
uint32_t hal_host_memread32(uintptr_t addr);   /* ghi nhận mọi lần đọc ROM để test */
#define HAL_MEM_RD32(addr)   hal_host_memread32((uintptr_t)(addr))
#else
#define HAL_MEM_RD32(addr)   (*(volatile const uint32_t *)(uintptr_t)(addr))
#endif
/* Lưu ý đọc ROM: sha256_update_mem() chỉ đọc word 32-bit CĂN LỀ, và chỉ những
 * word chứa ít nhất 1 byte của [addr, addr+len). Byte thừa trong word đầu/cuối
 * được đọc rồi bỏ, không đưa vào hash. Vì ranh giới vùng nhớ luôn chia hết cho 4
 * nên không bao giờ đọc ra ngoài vùng ánh xạ, miễn là base của ROM căn lề 4. */

#endif /* SHA256_REGS_H */