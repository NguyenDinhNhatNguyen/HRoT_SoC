/*
 * sha256_hal.c -- Cài đặt HAL SHA-256 (xem sha256_hal.h)
 *
 * Quy ước phần cứng (phải khớp RTL, xem doc/SHA256_Register_Map.md):
 *  - Ghi BLOCK[0..15] rồi ghi CTRL (START | INIT cho khối đầu).
 *  - START xóa DONE và đặt BUSY; xong thì DONE=1 (sticky), BUSY=0.
 *  - Khối không có INIT nén tiếp từ trạng thái H của khối trước.
 *  - HASH[0..7] hợp lệ khi DONE=1.
 *
 * Không dùng libc, nhân/chia hay số 64-bit: chạy được trên rv32i thuần.
 */
#include "sha256_hal.h"
#include "sha256_regs.h"

#define SESSION_IDLE      0u
#define SESSION_ACTIVE    0x5A5A0001u
#define SESSION_FINISHED  0x5A5A0002u

/* Chỉ một phiên mở tại một thời điểm vì phần cứng giữ trạng thái chuỗi. */
static uint32_t s_session_open = 0u;

/* ---------------------------------------------------------------- helpers */
static void wipe(void *p, uint32_t n)
{
    volatile uint8_t *q = (volatile uint8_t *)p;
    while (n--) *q++ = 0u;
}

static uint32_t load_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8)  |  (uint32_t)p[3];
}

static uint32_t bswap32(uint32_t x)
{
    return (x << 24) | ((x & 0x0000FF00u) << 8) |
           ((x >> 8) & 0x0000FF00u) | (x >> 24);
}

static void store_be32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

/* Lỗi giữa chừng: hủy phiên để firmware có thể thử lại từ đầu. */
static sha256_status_t fail(sha256_ctx_t *ctx, sha256_status_t err)
{
    sha256_abort(ctx);
    return err;
}

/* ------------------------------------------------------- hardware control */
static sha256_status_t hw_check_idle(void)
{
    return (SHA256_RD(SHA256_REG_STATUS) & SHA256_STATUS_BUSY) ? SHA256_ERR_BUSY : SHA256_OK;
}

/* Gửi START (kèm INIT cho khối đầu) rồi chờ DONE. BLOCK[] đã được ghi xong. */
static sha256_status_t hw_kick(sha256_ctx_t *ctx)
{
    uint32_t ctrl = SHA256_CTRL_START;
    uint32_t n;

    if (!ctx->started) ctrl |= SHA256_CTRL_INIT;
    SHA256_WR(SHA256_REG_CTRL, ctrl);
    ctx->started = 1u;

    for (n = SHA256_POLL_LIMIT; n != 0u; n--) {
        if (SHA256_RD(SHA256_REG_STATUS) & SHA256_STATUS_DONE) return SHA256_OK;
    }
    return SHA256_ERR_TIMEOUT;
}

static sha256_status_t hw_block_from_bytes(sha256_ctx_t *ctx, const uint8_t *blk)
{
    sha256_status_t st = hw_check_idle();
    uint32_t i;
    if (st != SHA256_OK) return st;
    for (i = 0u; i < SHA256_BLOCK_WORDS; i++)
        SHA256_WR(SHA256_REG_BLOCK(i), load_be32(blk + 4u * i));
    return hw_kick(ctx);
}

/* Đường nhanh: 64 byte căn lề 4 từ ROM -> thẳng vào BLOCK[], không qua buf. */
static sha256_status_t hw_block_from_mem(sha256_ctx_t *ctx, uintptr_t addr)
{
    sha256_status_t st = hw_check_idle();
    uint32_t i;
    if (st != SHA256_OK) return st;
    for (i = 0u; i < SHA256_BLOCK_WORDS; i++)
        /* RISC-V little-endian: word nạp từ bộ nhớ có byte đầu ở bit [7:0],
         * còn SHA-256 cần byte đầu ở bit [31:24] -> đảo byte. */
        SHA256_WR(SHA256_REG_BLOCK(i), bswap32(HAL_MEM_RD32(addr + 4u * i)));
    return hw_kick(ctx);
}

/* Đẩy 1 byte vào buf, đủ 64 byte thì nén. */
static sha256_status_t push_byte(sha256_ctx_t *ctx, uint8_t b)
{
    ctx->buf[ctx->buf_len++] = b;
    if (ctx->buf_len == SHA256_BLOCK_SIZE) {
        sha256_status_t st = hw_block_from_bytes(ctx, ctx->buf);
        ctx->buf_len = 0u;
        return st;
    }
    return SHA256_OK;
}

/* -------------------------------------------------------------- public API */
sha256_status_t sha256_init(sha256_ctx_t *ctx)
{
    if (ctx == NULL) return SHA256_ERR_PARAM;
    if (s_session_open != 0u) return SHA256_ERR_BUSY;

    wipe(ctx, (uint32_t)sizeof(*ctx));
    ctx->state = SESSION_ACTIVE;
    s_session_open = 1u;
    return SHA256_OK;
}

void sha256_abort(sha256_ctx_t *ctx)
{
    if (ctx == NULL) return;
    if (ctx->state == SESSION_ACTIVE) s_session_open = 0u;
    wipe(ctx, (uint32_t)sizeof(*ctx));
    ctx->state = SESSION_FINISHED;
}

sha256_status_t sha256_update(sha256_ctx_t *ctx, const void *data, uint32_t len)
{
    const uint8_t *p = (const uint8_t *)data;

    if (ctx == NULL || (data == NULL && len != 0u)) return SHA256_ERR_PARAM;
    if (ctx->state != SESSION_ACTIVE) return SHA256_ERR_STATE;
    if (len > 0xFFFFFFFFu - ctx->total_bytes) return fail(ctx, SHA256_ERR_PARAM);
    ctx->total_bytes += len;

    while (len != 0u) {
        sha256_status_t st;
        if (ctx->buf_len == 0u && len >= SHA256_BLOCK_SIZE) {
            st = hw_block_from_bytes(ctx, p);
            if (st != SHA256_OK) return fail(ctx, st);
            p += SHA256_BLOCK_SIZE;
            len -= SHA256_BLOCK_SIZE;
        } else {
            st = push_byte(ctx, *p++);
            if (st != SHA256_OK) return fail(ctx, st);
            len--;
        }
    }
    return SHA256_OK;
}

sha256_status_t sha256_update_mem(sha256_ctx_t *ctx, uintptr_t addr, uint32_t len)
{
    if (ctx == NULL || (addr == 0u && len != 0u)) return SHA256_ERR_PARAM;
    if (ctx->state != SESSION_ACTIVE) return SHA256_ERR_STATE;
    if (len > 0xFFFFFFFFu - ctx->total_bytes) return fail(ctx, SHA256_ERR_PARAM);
    ctx->total_bytes += len;

    while (len != 0u) {
        sha256_status_t st;

        if (ctx->buf_len == 0u && len >= SHA256_BLOCK_SIZE && (addr & 3u) == 0u) {
            st = hw_block_from_mem(ctx, addr);
            if (st != SHA256_OK) return fail(ctx, st);
            addr += SHA256_BLOCK_SIZE;
            len  -= SHA256_BLOCK_SIZE;
        } else {
            /* Đọc word căn lề chứa addr; lấy các byte cần (đầu/đuôi lệch lề hoặc
             * phần còn lại ngắn hơn 1 khối). Không đọc vượt quá word chứa dữ liệu. */
            uint32_t off = (uint32_t)(addr & 3u);
            uint32_t n   = 4u - off;
            uint32_t w, k;
            if (n > len) n = len;
            w = HAL_MEM_RD32(addr - off);
            for (k = 0u; k < n; k++) {
                st = push_byte(ctx, (uint8_t)(w >> (8u * (off + k))));
                if (st != SHA256_OK) return fail(ctx, st);
            }
            addr += n;
            len  -= n;
        }
    }
    return SHA256_OK;
}

sha256_status_t sha256_final(sha256_ctx_t *ctx, uint8_t out[SHA256_DIGEST_SIZE])
{
    uint32_t bits_hi, bits_lo, i;
    sha256_status_t st;

    if (ctx == NULL || out == NULL) return SHA256_ERR_PARAM;
    if (ctx->state != SESSION_ACTIVE) return SHA256_ERR_STATE;

    /* Độ dài tính bằng bit, 64-bit big-endian, tách 2 nửa 32-bit (không cần số 64-bit). */
    bits_hi = ctx->total_bytes >> 29;
    bits_lo = ctx->total_bytes << 3;

    ctx->buf[ctx->buf_len++] = 0x80u;
    if (ctx->buf_len > 56u) {               /* Không đủ chỗ cho trường độ dài -> thêm 1 khối */
        while (ctx->buf_len < SHA256_BLOCK_SIZE) ctx->buf[ctx->buf_len++] = 0u;
        st = hw_block_from_bytes(ctx, ctx->buf);
        if (st != SHA256_OK) return fail(ctx, st);
        ctx->buf_len = 0u;
    }
    while (ctx->buf_len < 56u) ctx->buf[ctx->buf_len++] = 0u;
    store_be32(&ctx->buf[56], bits_hi);
    store_be32(&ctx->buf[60], bits_lo);
    st = hw_block_from_bytes(ctx, ctx->buf);
    if (st != SHA256_OK) return fail(ctx, st);

    for (i = 0u; i < SHA256_HASH_WORDS; i++)
        store_be32(out + 4u * i, SHA256_RD(SHA256_REG_HASH(i)));

    wipe(ctx, (uint32_t)sizeof(*ctx));
    ctx->state = SESSION_FINISHED;
    s_session_open = 0u;
    return SHA256_OK;
}

/* Hàm one-shot: (1) kiểm tra tham số TRƯỚC khi mở phiên, (2) mọi đường thoát lỗi
 * đều hủy phiên. sha256_abort() idempotent (đã hủy rồi thì không làm gì thêm),
 * nên gọi thừa là an toàn và đảm bảo không bao giờ để rò phiên sau khi thất bại. */
sha256_status_t sha256_digest(const void *data, uint32_t len, uint8_t out[SHA256_DIGEST_SIZE])
{
    sha256_ctx_t ctx;
    sha256_status_t st;

    if (out == NULL || (data == NULL && len != 0u)) return SHA256_ERR_PARAM;

    st = sha256_init(&ctx);
    if (st != SHA256_OK) return st;          /* chưa mở phiên: không có gì để hủy */
    st = sha256_update(&ctx, data, len);
    if (st == SHA256_OK) st = sha256_final(&ctx, out);
    if (st != SHA256_OK) sha256_abort(&ctx);
    return st;
}

sha256_status_t sha256_digest_mem(uintptr_t addr, uint32_t len, uint8_t out[SHA256_DIGEST_SIZE])
{
    sha256_ctx_t ctx;
    sha256_status_t st;

    if (out == NULL || (addr == 0u && len != 0u)) return SHA256_ERR_PARAM;

    st = sha256_init(&ctx);
    if (st != SHA256_OK) return st;
    st = sha256_update_mem(&ctx, addr, len);
    if (st == SHA256_OK) st = sha256_final(&ctx, out);
    if (st != SHA256_OK) sha256_abort(&ctx);
    return st;
}

int sha256_compare(const uint8_t *a, const uint8_t *b, uint32_t len)
{
    uint8_t diff = 0u;
    uint32_t i;
    if (a == NULL || b == NULL || len == 0u) return 1;   /* so 0 byte không được coi là khớp */
    for (i = 0u; i < len; i++) diff |= (uint8_t)(a[i] ^ b[i]);
    return diff != 0u;
}

/* ------------------------------------------------------------- self-test */
static const uint8_t kat_empty[32] = {
    0xe3,0xb0,0xc4,0x42,0x98,0xfc,0x1c,0x14,0x9a,0xfb,0xf4,0xc8,0x99,0x6f,0xb9,0x24,
    0x27,0xae,0x41,0xe4,0x64,0x9b,0x93,0x4c,0xa4,0x95,0x99,0x1b,0x78,0x52,0xb8,0x55 };
static const uint8_t kat_abc[32] = {
    0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,
    0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad };
static const char kat_56_msg[] = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
static const uint8_t kat_56[32] = {
    0x24,0x8d,0x6a,0x61,0xd2,0x06,0x38,0xb8,0xe5,0xc0,0x26,0x93,0x0c,0x3e,0x60,0x39,
    0xa3,0x3c,0xe4,0x59,0x64,0xff,0x21,0x67,0xf6,0xec,0xed,0xd4,0x19,0xdb,0x06,0xc1 };

sha256_status_t sha256_selftest(void)
{
    uint8_t h[SHA256_DIGEST_SIZE];
    sha256_status_t st;

    st = sha256_digest("", 0u, h);                          /* 1 khối, chỉ padding */
    if (st != SHA256_OK) return st;
    if (sha256_compare(h, kat_empty, SHA256_DIGEST_SIZE)) return SHA256_ERR_SELFTEST;

    st = sha256_digest("abc", 3u, h);                       /* 1 khối */
    if (st != SHA256_OK) return st;
    if (sha256_compare(h, kat_abc, SHA256_DIGEST_SIZE)) return SHA256_ERR_SELFTEST;

    st = sha256_digest(kat_56_msg, 56u, h);                 /* 2 khối: kiểm tra chaining */
    if (st != SHA256_OK) return st;
    if (sha256_compare(h, kat_56, SHA256_DIGEST_SIZE)) return SHA256_ERR_SELFTEST;

    return SHA256_OK;
}