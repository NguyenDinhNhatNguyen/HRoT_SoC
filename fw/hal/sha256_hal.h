/*
 * sha256_hal.h -- Hardware Abstraction Layer for the SHA-256 accelerator
 *
 * Used by Secure Boot on the Master Core (RV32I, no multiply/divide, no libc).
 * init/update/final API, the hardware compresses one 64-byte block at a time.
 *
 * Typical Secure Boot flow:
 *     uint8_t h[32];
 *     if (sha256_digest_mem(APP_ROM_BASE, APP_ROM_SIZE, h) != SHA256_OK) halt();
 *     if (sha256_compare(h, golden_hash, 32) != 0) halt();
 *     release_app_reset();
 *
 * Constraints:
 *  - The hardware keeps the chaining state between blocks, so ONLY ONE hash
 *    session can be open at a time. sha256_init() returns SHA256_ERR_BUSY if
 *    another session is open (prevents silently corrupted hashes).
 *  - Session release rules:
 *      + One-shot functions (sha256_digest*): check parameters before opening the session
 *        and always abort it on failure -> after they return (OK or error) no session is open.
 *      + Streaming: hardware errors and length overflow abort the session. Parameter or
 *        state errors (ERR_PARAM/ERR_STATE) do NOT touch the hardware, so the session stays
 *        open for a retry. To give up, the caller must call sha256_abort(). Do not let ctx
 *        go out of scope while its session is open.
 *  - Not thread-safe, not for use in interrupt handlers.
 */
#ifndef SHA256_HAL_H
#define SHA256_HAL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SHA256_BLOCK_SIZE   64u
#define SHA256_DIGEST_SIZE  32u

/* Max STATUS reads while waiting for DONE (one block takes 66 cycles from START to DONE). */
#ifndef SHA256_POLL_LIMIT
#define SHA256_POLL_LIMIT   4096u
#endif

typedef enum {
    SHA256_OK           =  0,
    SHA256_ERR_TIMEOUT  = -1,  /* No DONE within SHA256_POLL_LIMIT reads                    */
    SHA256_ERR_BUSY     = -2,  /* Hardware busy, or another hash session is open          */
    SHA256_ERR_PARAM    = -3,  /* Bad parameter (NULL, length above 2^32-1 bytes)         */
    SHA256_ERR_STATE    = -4,  /* Wrong call order (update before init, after final/error) */
    SHA256_ERR_SELFTEST = -5   /* Digest differs from the reference vector                */
} sha256_status_t;

typedef struct {
    uint8_t  buf[SHA256_BLOCK_SIZE]; /* Block being collected                     */
    uint32_t buf_len;                /* Bytes currently in buf                    */
    uint32_t total_bytes;            /* Total bytes fed so far (max 2^32-1)       */
    uint32_t state;                  /* Internal: session state                   */
    uint32_t started;                /* Internal: first block sent (INIT flag)    */
} sha256_ctx_t;

/* Streaming API */
sha256_status_t sha256_init(sha256_ctx_t *ctx);
sha256_status_t sha256_update(sha256_ctx_t *ctx, const void *data, uint32_t len);

/* Like sha256_update but reads the source with aligned 32-bit accesses (for the App Core
 * ROM on the dual-port ROM). addr/len need not be aligned. */
sha256_status_t sha256_update_mem(sha256_ctx_t *ctx, uintptr_t addr, uint32_t len);

/* Add the padding, return the 32-byte digest (big-endian), close the session. */
sha256_status_t sha256_final(sha256_ctx_t *ctx, uint8_t out[SHA256_DIGEST_SIZE]);

/* Abort the open session (after an error midway). Safe to call more than once. */
void sha256_abort(sha256_ctx_t *ctx);

/* One-shot API */
sha256_status_t sha256_digest(const void *data, uint32_t len, uint8_t out[SHA256_DIGEST_SIZE]);
sha256_status_t sha256_digest_mem(uintptr_t addr, uint32_t len, uint8_t out[SHA256_DIGEST_SIZE]);

/* Utilities */
/* Constant-time compare (no timing leak). Returns 0 if equal, non-zero otherwise.
 * NULL a/b or len = 0 always returns non-zero (fail-safe for Secure Boot). */
int sha256_compare(const uint8_t *a, const uint8_t *b, uint32_t len);

/* Hardware self-test with NIST vectors (empty, "abc", 56 bytes in two blocks).
 * Call once at the start of Secure Boot to catch a broken or miswired SHA core. */
sha256_status_t sha256_selftest(void);

#ifdef __cplusplus
}
#endif
#endif /* SHA256_HAL_H */
