/* Mô hình hành vi ngoại vi SHA-256 (đúng "hợp đồng" ở sha256_regs.h) + chèn lỗi. */
#ifndef SHA256_MOCK_H
#define SHA256_MOCK_H
#include <stdint.h>
typedef struct {
    /* Cấu hình lỗi / độ trễ */
    uint32_t busy_polls;      /* Số lần đọc STATUS thấy BUSY trước khi DONE (mô phỏng 64 chu kỳ) */
    int      never_done;      /* 1: không bao giờ DONE (kiểm tra timeout)                        */
    int      stuck_busy;      /* 1: BUSY dính 1 (kiểm tra ERR_BUSY)                              */
    int      corrupt_hash;    /* 1: đảo 1 bit của HASH[0] (kiểm tra selftest bắt lỗi)            */
    /* Trạng thái nội bộ */
    uint32_t block[16], h[8], digest[8];
    uint32_t pending, done, busy;
    /* Thống kê để kiểm tra hành vi HAL */
    uint32_t n_start, n_init, n_block_wr, n_ctrl_wr, n_hash_rd, n_status_rd;
    uint32_t init_on_first_only_ok;  /* 1 nếu INIT chỉ xuất hiện ở START đầu tiên sau reset thống kê */
    uint32_t block_wr_while_busy;
    uint32_t rom_rd_n, rom_rd_misaligned;      /* ghi nhận đọc ROM */
    uintptr_t rom_rd_lo, rom_rd_hi;            /* [lo, hi) vùng đã đọc */
} sha256_mock_t;
extern sha256_mock_t g_mock;
void sha256_mock_reset(void);   /* Xóa toàn bộ, kể cả cấu hình lỗi */
#endif