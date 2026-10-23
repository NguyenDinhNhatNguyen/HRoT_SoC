/* ============================================================================
 * sha256_hal.h -- Hardware Abstraction Layer cho lõi gia tốc SHA-256
 *
 * Dùng cho Secure Boot trên Master Core (RV32I, không có lệnh nhân/chia, không
 * libc). API kiểu init/update/final, phần cứng nén từng khối 64 byte.
 *
 * Luồng Secure Boot điển hình:
 *     uint8_t h[32];
 *     if (sha256_digest_mem(APP_ROM_BASE, APP_ROM_SIZE, h) != SHA256_OK) halt();
 *     if (sha256_compare(h, golden_hash, 32) != 0) halt();
 *     release_app_reset();
 *
 * Ràng buộc:
 *  - Phần cứng giữ trạng thái chuỗi (chaining) giữa các khối nên CHỈ MỘT phiên
 *    băm được mở tại một thời điểm. sha256_init() trả SHA256_ERR_BUSY nếu đã
 *    có phiên khác đang mở (tránh hỏng hash âm thầm).
 *  - Quy ước giải phóng phiên:
 *      + Hàm one-shot (sha256_digest*): kiểm tham số trước khi mở phiên và luôn
 *        tự hủy phiên khi thất bại -> sau khi trả về (dù OK hay lỗi) không còn phiên mở.
 *      + Streaming: lỗi phần cứng/tràn độ dài tự hủy phiên. Lỗi tham số hoặc sai
 *        trạng thái (ERR_PARAM/ERR_STATE) KHÔNG đụng phần cứng nên phiên còn nguyên
 *        để gọi lại; nếu bỏ cuộc, người gọi phải gọi sha256_abort(). Đừng để ctx
 *        ra khỏi phạm vi khi phiên còn mở.
 *  - Không thread-safe, không dùng trong ngắt.
 * ========================================================================== */
#ifndef SHA256_HAL_H
#define SHA256_HAL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SHA256_BLOCK_SIZE   64u
#define SHA256_DIGEST_SIZE  32u

/* Số lần đọc STATUS tối đa khi chờ DONE (mỗi khối cần ~64 chu kỳ lõi). */
#ifndef SHA256_POLL_LIMIT
#define SHA256_POLL_LIMIT   4096u
#endif

typedef enum {
    SHA256_OK           =  0,
    SHA256_ERR_TIMEOUT  = -1,  /* Phần cứng không báo DONE trong SHA256_POLL_LIMIT lần đọc */
    SHA256_ERR_BUSY     = -2,  /* Phần cứng đang bận, hoặc đã có phiên băm khác đang mở     */
    SHA256_ERR_PARAM    = -3,  /* Tham số sai (NULL, độ dài vượt 2^32-1 byte)               */
    SHA256_ERR_STATE    = -4,  /* Gọi sai thứ tự (update trước init, sau final/lỗi...)      */
    SHA256_ERR_SELFTEST = -5   /* Digest sai so với vector chuẩn                            */
} sha256_status_t;

typedef struct {
    uint8_t  buf[SHA256_BLOCK_SIZE]; /* Khối đang gom dở                          */
    uint32_t buf_len;                /* Số byte đang có trong buf                 */
    uint32_t total_bytes;            /* Tổng số byte đã nạp (tối đa 2^32-1)       */
    uint32_t state;                  /* Nội bộ: trạng thái phiên                  */
    uint32_t started;                /* Nội bộ: đã nén khối đầu (cờ INIT) chưa    */
} sha256_ctx_t;

/* ---- Streaming API ---- */
sha256_status_t sha256_init(sha256_ctx_t *ctx);
sha256_status_t sha256_update(sha256_ctx_t *ctx, const void *data, uint32_t len);

/* Như sha256_update nhưng đọc nguồn bằng truy cập 32-bit căn lề (dùng cho ROM
 * của App Core nối qua Dual-Port ROM). addr/len không cần căn lề. */
sha256_status_t sha256_update_mem(sha256_ctx_t *ctx, uintptr_t addr, uint32_t len);

/* Chốt padding, trả digest 32 byte (big-endian), kết thúc phiên. */
sha256_status_t sha256_final(sha256_ctx_t *ctx, uint8_t out[SHA256_DIGEST_SIZE]);

/* Hủy phiên đang mở (dùng khi gặp lỗi giữa chừng). An toàn khi gọi nhiều lần. */
void sha256_abort(sha256_ctx_t *ctx);

/* ---- One-shot API ---- */
sha256_status_t sha256_digest(const void *data, uint32_t len, uint8_t out[SHA256_DIGEST_SIZE]);
sha256_status_t sha256_digest_mem(uintptr_t addr, uint32_t len, uint8_t out[SHA256_DIGEST_SIZE]);

/* ---- Tiện ích ---- */
/* So sánh thời gian hằng (chống rò rỉ timing). Trả 0 nếu bằng nhau, khác 0 nếu khác.
 * a/b NULL hoặc len = 0 luôn trả khác 0 (fail-safe cho Secure Boot). */
int sha256_compare(const uint8_t *a, const uint8_t *b, uint32_t len);

/* Tự kiểm tra phần cứng bằng vector NIST (rỗng, "abc", 56 byte hai khối).
 * Nên gọi 1 lần đầu Secure Boot để phát hiện lõi SHA hỏng/đấu sai. */
sha256_status_t sha256_selftest(void);

#ifdef __cplusplus
}
#endif
#endif /* SHA256_HAL_H */