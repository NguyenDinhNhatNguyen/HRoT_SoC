/* SHA-256 HAL unit test on the host (WSL/Linux) -- no hardware or VP needed.
 *   make -C fw/hal/test test        # run everything
 *   make -C fw/hal/test crosscheck  # compare with the OS sha256sum
 *   ./hal_host_test --file <path>   # print the HAL digest of one file (used by crosscheck)  */
#include "sha256_hal.h"
#include "sha256_mock.h"
#include "sha256_ref.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_fail = 0;
static int g_pass = 0;

#define CHECK(cond, ...)                                    \
    do {                                                    \
        if (cond) {                                         \
            g_pass++;                                       \
        } else {                                            \
            g_fail++;                                       \
            printf("  FAIL %s:%d: ", __FILE__, __LINE__);   \
            printf(__VA_ARGS__);                            \
            printf("\n");                                   \
        }                                                   \
    } while (0)

static void hex(const uint8_t *d, char *o)
{
    for (int i = 0; i < 32; i++)
        sprintf(o + 2*i, "%02x", d[i]);
}

static uint32_t rnd(void)
{
    static uint32_t s = 0x1234567u;
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    return s;
}

/* T1: NIST vectors + self-test */
static void t_kat(void)
{
    uint8_t h[32];
    char a[65];
    uint8_t *m = malloc(1000000);
    sha256_ctx_t c;
    int upd_fail = 0;
    printf("[T1] KAT\n");
    sha256_mock_reset();
    CHECK(sha256_selftest() == SHA256_OK, "selftest");

    if (m == NULL) {
        CHECK(0, "malloc 1MB");
        return;
    }
    memset(m, 'a', 1000000);                          /* one million 'a', fed in 1000-byte pieces */
    CHECK(sha256_init(&c) == SHA256_OK, "init");
    for (int i = 0; i < 1000; i++)
        upd_fail += (sha256_update(&c, m + 1000*i, 1000) != SHA256_OK);
    CHECK(upd_fail == 0, "1000 updates: %d errors", upd_fail);
    CHECK(sha256_final(&c, h) == SHA256_OK, "final");
    hex(h, a);
    CHECK(!strcmp(a, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"), "1M 'a' = %s", a);
    free(m);
}

/* T2: every length 0..300 (around the 55/56/63/64/119/120 edges) matches the reference model */
static void t_lengths(void)
{
    uint8_t buf[300];
    uint8_t h[32];
    uint8_t r[32];
    printf("[T2] length sweep 0..300\n");
    for (int i = 0; i < 300; i++)
        buf[i] = (uint8_t)rnd();
    for (uint32_t n = 0; n <= 300; n++) {
        sha256_mock_reset();
        CHECK(sha256_digest(buf, n, h) == SHA256_OK, "digest n=%u", n);
        sha256_ref(buf, n, r);
        CHECK(!memcmp(h, r, 32), "mismatch n=%u", n);
    }
}

/* T3: random chunking gives the same digest */
static void t_chunking(void)
{
    enum { N = 1000 };
    uint8_t buf[N];
    uint8_t h[32];
    uint8_t r[32];
    printf("[T3] random chunking\n");
    for (int i = 0; i < N; i++)
        buf[i] = (uint8_t)rnd();
    sha256_ref(buf, N, r);
    for (int trial = 0; trial < 200; trial++) {
        sha256_ctx_t c;
        uint32_t pos = 0;
        sha256_mock_reset();
        CHECK(sha256_init(&c) == SHA256_OK, "init");
        while (pos < N) {
            uint32_t n = rnd() % 130;
            if (n > N - pos)
                n = N - pos;
            CHECK(sha256_update(&c, buf + pos, n) == SHA256_OK, "upd");
            pos += n;
        }
        CHECK(sha256_final(&c, h) == SHA256_OK, "final");
        CHECK(!memcmp(h, r, 32), "chunk trial %d", trial);
    }
}

/* T4: update_mem with misaligned address/length (the ROM is read 32 bits at a time) */
static void t_mem(void)
{
    static uint32_t rom[200];                           /* 4-byte aligned */
    uint8_t *bytes = (uint8_t *)rom;
    uint8_t h[32];
    uint8_t r[32];
    printf("[T4] update_mem alignment\n");
    for (int i = 0; i < 800; i++)
        bytes[i] = (uint8_t)rnd();
    for (uint32_t off = 0; off < 4; off++) {
        for (uint32_t n = 0; n < 400; n += (n < 140 ? 1 : 37)) {
            sha256_mock_reset();
            CHECK(sha256_digest_mem((uintptr_t)(bytes + off), n, h) == SHA256_OK, "mem off=%u n=%u", off, n);
            sha256_ref(bytes + off, n, r);
            CHECK(!memcmp(h, r, 32), "mem mismatch off=%u n=%u", off, n);
        }
    }
    /* Mix update and update_mem in one session */
    {
        sha256_ctx_t c;
        uint8_t all[300];
        memcpy(all, bytes + 1, 100);
        memcpy(all + 100, bytes + 10, 200);
        sha256_mock_reset();
        sha256_init(&c);
        CHECK(sha256_update(&c, bytes + 1, 100) == SHA256_OK, "mix a");
        CHECK(sha256_update_mem(&c, (uintptr_t)(bytes + 10), 200) == SHA256_OK, "mix b");
        CHECK(sha256_final(&c, h) == SHA256_OK, "mix final");
        sha256_ref(all, 300, r);
        CHECK(!memcmp(h, r, 32), "mix mismatch");
    }
}

/* T5: follows the hardware protocol */
static void t_protocol(void)
{
    uint8_t buf[200] = {0};
    uint8_t h[32];
    printf("[T5] protocol behaviour\n");
    sha256_mock_reset();
    g_mock.busy_polls = 64;                              /* the core needs many polls */
    CHECK(sha256_digest(buf, 200, h) == SHA256_OK, "digest w/ latency");
    CHECK(g_mock.n_start == 4, "200B -> 4 blocks, got %u", g_mock.n_start);   /* 3 full + 1 padding */
    CHECK(g_mock.n_init == 1 && g_mock.init_on_first_only_ok, "INIT on the first block only");
    CHECK(g_mock.n_block_wr == 16 * g_mock.n_start, "16 BLOCK words per block");
    CHECK(g_mock.n_ctrl_wr == g_mock.n_start, "1 CTRL write per block");
    CHECK(g_mock.n_hash_rd == 8, "reads exactly 8 HASH words, got %u", g_mock.n_hash_rd);
    CHECK(g_mock.block_wr_while_busy == 0, "no BLOCK write while BUSY");
    CHECK(sha256_selftest() == SHA256_OK, "selftest after use");
}

/* T6: error paths */
static void t_errors(void)
{
    uint8_t h[32];
    sha256_ctx_t c;
    sha256_ctx_t d;
    printf("[T6] error paths\n");

    sha256_mock_reset();
    g_mock.never_done = 1;
    CHECK(sha256_digest("abc", 3, h) == SHA256_ERR_TIMEOUT, "timeout");
    sha256_mock_reset();
    CHECK(sha256_digest("abc", 3, h) == SHA256_OK, "session released after the error -> retry OK");

    sha256_mock_reset();
    g_mock.stuck_busy = 1;
    CHECK(sha256_digest("abc", 3, h) == SHA256_ERR_BUSY, "hw busy");
    sha256_mock_reset();

    CHECK(sha256_init(NULL) == SHA256_ERR_PARAM, "init NULL");
    CHECK(sha256_init(&c) == SHA256_OK, "init");
    CHECK(sha256_init(&d) == SHA256_ERR_BUSY, "a second session is blocked");
    CHECK(sha256_update(&c, NULL, 5) == SHA256_ERR_PARAM, "update NULL,len>0");
    CHECK(sha256_update(&c, NULL, 0) == SHA256_OK, "update NULL,len=0 is valid");
    CHECK(sha256_final(&c, NULL) == SHA256_ERR_PARAM, "final out NULL");
    CHECK(sha256_final(&c, h) == SHA256_OK, "final (empty digest)");
    CHECK(sha256_update(&c, "x", 1) == SHA256_ERR_STATE, "update after final");
    CHECK(sha256_final(&c, h) == SHA256_ERR_STATE, "final twice");
    CHECK(sha256_update(&d, "x", 1) == SHA256_ERR_STATE, "update without init");

    CHECK(sha256_init(&c) == SHA256_OK, "init again");
    sha256_abort(&c);
    sha256_abort(&c);
    CHECK(sha256_init(&c) == SHA256_OK, "init after abort");
    sha256_abort(&c);

    sha256_mock_reset();
    g_mock.corrupt_hash = 1;
    CHECK(sha256_selftest() == SHA256_ERR_SELFTEST, "selftest catches a broken core");
    sha256_mock_reset();
}

/* T7: constant-time compare */
static void t_compare(void)
{
    uint8_t a[32];
    uint8_t b[32];
    printf("[T7] compare\n");
    memset(a, 7, 32);
    memset(b, 7, 32);
    CHECK(sha256_compare(a, b, 32) == 0, "equal");
    for (int i = 0; i < 32; i++) {
        b[i] ^= 0x80;
        CHECK(sha256_compare(a, b, 32) != 0, "differs at byte %d", i);
        b[i] ^= 0x80;
    }
    CHECK(sha256_compare(NULL, b, 32) != 0, "NULL -> differs");
    CHECK(sha256_compare(a, b, 0) != 0, "len = 0 -> differs (never a match)");
}

/* T8: bad parameters to the one-shot functions must not leak the session (regression) */
static void t_oneshot_param_leak(void)
{
    static uint32_t rom[32];
    uint8_t h[32];
    uint8_t r[32];
    const char *msg = "abc";
    printf("[T8] one-shot bad params must not leak session\n");
    for (int i = 0; i < 32; i++)
        rom[i] = rnd();
    sha256_ref((const uint8_t *)msg, 3, r);

    struct {
        const char *name;
        sha256_status_t st;
    } cases[4];
    sha256_mock_reset();
    cases[0].name = "digest(NULL,1,out)";
    cases[0].st = sha256_digest(NULL, 1u, h);
    CHECK(sha256_digest("abc", 3u, h) == SHA256_OK, "valid call right after %s", cases[0].name);
    cases[1].name = "digest(data,1,NULL out)";
    cases[1].st = sha256_digest("x", 1u, NULL);
    CHECK(sha256_digest("abc", 3u, h) == SHA256_OK, "valid call right after %s", cases[1].name);
    cases[2].name = "digest_mem(0,1,out)";
    cases[2].st = sha256_digest_mem(0u, 1u, h);
    CHECK(sha256_digest("abc", 3u, h) == SHA256_OK, "valid call right after %s", cases[2].name);
    cases[3].name = "digest_mem(rom,4,NULL)";
    cases[3].st = sha256_digest_mem((uintptr_t)rom, 4u, NULL);
    CHECK(sha256_digest("abc", 3u, h) == SHA256_OK, "valid call right after %s", cases[3].name);
    for (int i = 0; i < 4; i++)
        CHECK(cases[i].st == SHA256_ERR_PARAM, "%s must return ERR_PARAM, got %d", cases[i].name, cases[i].st);
    CHECK(!memcmp(h, r, 32), "correct digest after the parameter errors");
    CHECK(g_mock.n_start == 4, "parameter errors must not touch the hardware: n_start=%u", g_mock.n_start);

    /* Same error once more, then check the session with sha256_init directly */
    sha256_ctx_t c;
    (void)sha256_digest(NULL, 1u, h);
    CHECK(sha256_init(&c) == SHA256_OK, "sha256_init right after a one-shot error");
    sha256_abort(&c);
}

/* T9: the ROM is only read with aligned words, and only the words that hold data */
static void t_rom_bounds(void)
{
    static uint32_t rom[100];
    uint8_t h[32];
    uint8_t r[32];
    printf("[T9] ROM reads stay inside the words that hold the image\n");
    for (int i = 0; i < 100; i++)
        rom[i] = rnd();
    for (uint32_t off = 0; off < 4; off++) {
        for (uint32_t n = 1; n <= 200; n++) {
            uintptr_t a = (uintptr_t)rom + 40 + off;           /* "valid" area in the middle of the array */
            uintptr_t lo = a & ~(uintptr_t)3;
            uintptr_t hi = (a + n + 3) & ~(uintptr_t)3;
            sha256_mock_reset();
            CHECK(sha256_digest_mem(a, n, h) == SHA256_OK, "digest_mem off=%u n=%u", off, n);
            sha256_ref((const uint8_t *)a, n, r);
            CHECK(!memcmp(h, r, 32), "digest off=%u n=%u", off, n);
            CHECK(g_mock.rom_rd_misaligned == 0, "misaligned ROM read off=%u n=%u", off, n);
            CHECK(g_mock.rom_rd_lo >= lo && g_mock.rom_rd_hi <= hi,
                  "read outside the image off=%u n=%u: [%lu,%lu) vs [%lu,%lu)", off, n,
                  (unsigned long)(g_mock.rom_rd_lo - (uintptr_t)rom), (unsigned long)(g_mock.rom_rd_hi - (uintptr_t)rom),
                  (unsigned long)(lo - (uintptr_t)rom), (unsigned long)(hi - (uintptr_t)rom));
            CHECK(g_mock.rom_rd_n == (hi - lo) / 4, "each word read exactly once: %u vs %lu", g_mock.rom_rd_n, (unsigned long)((hi - lo) / 4));
        }
    }
}

/* --file mode: print the HAL digest of a file (cross-check with sha256sum) */
static int file_mode(const char *path)
{
    FILE *f = fopen(path, "rb");
    long n;
    uint8_t *d;
    uint8_t h[32];
    char s[65];
    int rc = 0;
    if (!f) {
        perror("open");
        return 2;
    }
    if (fseek(f, 0, SEEK_END) != 0 || (n = ftell(f)) < 0 || n > 0xFFFFFFFFL || fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return 2;
    }
    d = malloc(n ? (size_t)n : 1u);
    if (d == NULL || (n && fread(d, 1, (size_t)n, f) != (size_t)n))
        rc = 2;
    fclose(f);
    if (rc == 0) {
        sha256_mock_reset();
        if (sha256_digest(d, (uint32_t)n, h) != SHA256_OK) {
            rc = 3;
        } else {
            hex(h, s);
            printf("%s\n", s);
        }
    }
    free(d);
    return rc;
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "--file"))
        return file_mode(argv[2]);
    t_kat();
    t_lengths();
    t_chunking();
    t_mem();
    t_protocol();
    t_errors();
    t_compare();
    t_oneshot_param_leak();
    t_rom_bounds();
    printf("\n==== %s: %d passed, %d failed ====\n", g_fail ? "FAILED" : "PASSED", g_pass, g_fail);
    return g_fail != 0;
}
