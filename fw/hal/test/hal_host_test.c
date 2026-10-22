/* Unit test HAL SHA-256 trên máy host (WSL/Linux) -- không cần phần cứng hay VP.
 *   make -C fw/hal/test test        # chạy toàn bộ
 *   make -C fw/hal/test crosscheck  # đối chiếu với sha256sum của hệ điều hành
 *   ./hal_host_test --file <path>   # in digest HAL của 1 file (dùng cho crosscheck)  */
#include "sha256_hal.h"
#include "sha256_mock.h"
#include "sha256_ref.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_fail = 0, g_pass = 0;
#define CHECK(cond, ...) do { if (cond) g_pass++; else { g_fail++; \
    printf("  FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void hex(const uint8_t *d, char *o) { for (int i = 0; i < 32; i++) sprintf(o + 2*i, "%02x", d[i]); }
static uint32_t rnd(void) { static uint32_t s = 0x1234567u; s ^= s << 13; s ^= s >> 17; s ^= s << 5; return s; }

/* ---- T1: vector chuẩn NIST + self-test ---- */
static void t_kat(void)
{
    uint8_t h[32], e[32];
    char a[65], b[65];
    uint8_t *m = malloc(1000000);
    sha256_ctx_t c;
    printf("[T1] KAT\n");
    sha256_mock_reset();
    CHECK(sha256_selftest() == SHA256_OK, "selftest");

    memset(m, 'a', 1000000);                          /* 1 triệu chữ 'a', nạp theo mảnh 1000 byte */
    CHECK(sha256_init(&c) == SHA256_OK, "init");
    for (int i = 0; i < 1000; i++) CHECK(sha256_update(&c, m + 1000*i, 1000) == SHA256_OK, "upd");
    CHECK(sha256_final(&c, h) == SHA256_OK, "final");
    hex(h, a);
    CHECK(!strcmp(a, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"), "1M 'a' = %s", a);
    free(m);
    (void)e; (void)b;
}

/* ---- T2: mọi độ dài 0..300 (quanh các biên 55/56/63/64/119/120) khớp mô hình tham chiếu ---- */
static void t_lengths(void)
{
    uint8_t buf[300], h[32], r[32];
    printf("[T2] length sweep 0..300\n");
    for (int i = 0; i < 300; i++) buf[i] = (uint8_t)rnd();
    for (uint32_t n = 0; n <= 300; n++) {
        sha256_mock_reset();
        CHECK(sha256_digest(buf, n, h) == SHA256_OK, "digest n=%u", n);
        sha256_ref(buf, n, r);
        CHECK(!memcmp(h, r, 32), "mismatch n=%u", n);
    }
}

/* ---- T3: cắt mảnh ngẫu nhiên cho cùng digest ---- */
static void t_chunking(void)
{
    enum { N = 1000 };
    uint8_t buf[N], h[32], r[32];
    printf("[T3] random chunking\n");
    for (int i = 0; i < N; i++) buf[i] = (uint8_t)rnd();
    sha256_ref(buf, N, r);
    for (int trial = 0; trial < 200; trial++) {
        sha256_ctx_t c; uint32_t pos = 0;
        sha256_mock_reset();
        CHECK(sha256_init(&c) == SHA256_OK, "init");
        while (pos < N) {
            uint32_t n = rnd() % 130; if (n > N - pos) n = N - pos;
            CHECK(sha256_update(&c, buf + pos, n) == SHA256_OK, "upd");
            pos += n;
        }
        CHECK(sha256_final(&c, h) == SHA256_OK, "final");
        CHECK(!memcmp(h, r, 32), "chunk trial %d", trial);
    }
}

/* ---- T4: update_mem với địa chỉ/độ dài lệch lề (ROM chỉ đọc 32-bit) ---- */
static void t_mem(void)
{
    static uint32_t rom[200];                           /* căn lề 4 */
    uint8_t *bytes = (uint8_t *)rom, h[32], r[32];
    printf("[T4] update_mem alignment\n");
    for (int i = 0; i < 800; i++) bytes[i] = (uint8_t)rnd();
    for (uint32_t off = 0; off < 4; off++)
        for (uint32_t n = 0; n < 400; n += (n < 140 ? 1 : 37)) {
            sha256_mock_reset();
            CHECK(sha256_digest_mem((uintptr_t)(bytes + off), n, h) == SHA256_OK, "mem off=%u n=%u", off, n);
            sha256_ref(bytes + off, n, r);
            CHECK(!memcmp(h, r, 32), "mem mismatch off=%u n=%u", off, n);
        }
    /* Trộn update + update_mem trong cùng 1 phiên */
    { sha256_ctx_t c; uint8_t all[300];
      memcpy(all, bytes + 1, 100); memcpy(all + 100, bytes + 10, 200);
      sha256_mock_reset();
      sha256_init(&c);
      CHECK(sha256_update(&c, bytes + 1, 100) == SHA256_OK, "mix a");
      CHECK(sha256_update_mem(&c, (uintptr_t)(bytes + 10), 200) == SHA256_OK, "mix b");
      CHECK(sha256_final(&c, h) == SHA256_OK, "mix final");
      sha256_ref(all, 300, r); CHECK(!memcmp(h, r, 32), "mix mismatch"); }
}

/* ---- T5: hành vi đúng giao thức phần cứng ---- */
static void t_protocol(void)
{
    uint8_t buf[200] = {0}, h[32];
    printf("[T5] protocol behaviour\n");
    sha256_mock_reset();
    g_mock.busy_polls = 64;                              /* lõi cần nhiều lần poll */
    CHECK(sha256_digest(buf, 200, h) == SHA256_OK, "digest w/ latency");
    CHECK(g_mock.n_start == 4, "200B -> 4 khối, got %u", g_mock.n_start);   /* 3 đầy + 1 padding */
    CHECK(g_mock.n_init == 1 && g_mock.init_on_first_only_ok, "INIT chỉ ở khối đầu");
    CHECK(g_mock.n_block_wr == 16 * g_mock.n_start, "16 word BLOCK mỗi khối");
    CHECK(g_mock.n_ctrl_wr == g_mock.n_start, "1 ghi CTRL mỗi khối");
    CHECK(g_mock.n_hash_rd == 8, "đọc đúng 8 word HASH, got %u", g_mock.n_hash_rd);
    CHECK(g_mock.block_wr_while_busy == 0, "không ghi BLOCK khi BUSY");
    CHECK(sha256_selftest() == SHA256_OK, "selftest sau khi dùng");
}

/* ---- T6: đường lỗi ---- */
static void t_errors(void)
{
    uint8_t h[32]; sha256_ctx_t c, d;
    printf("[T6] error paths\n");

    sha256_mock_reset(); g_mock.never_done = 1;
    CHECK(sha256_digest("abc", 3, h) == SHA256_ERR_TIMEOUT, "timeout");
    sha256_mock_reset();
    CHECK(sha256_digest("abc", 3, h) == SHA256_OK, "phiên được giải phóng sau lỗi -> thử lại OK");

    sha256_mock_reset(); g_mock.stuck_busy = 1;
    CHECK(sha256_digest("abc", 3, h) == SHA256_ERR_BUSY, "hw busy");
    sha256_mock_reset();

    CHECK(sha256_init(NULL) == SHA256_ERR_PARAM, "init NULL");
    CHECK(sha256_init(&c) == SHA256_OK, "init");
    CHECK(sha256_init(&d) == SHA256_ERR_BUSY, "2 phiên cùng lúc bị chặn");
    CHECK(sha256_update(&c, NULL, 5) == SHA256_ERR_PARAM, "update NULL,len>0");
    CHECK(sha256_update(&c, NULL, 0) == SHA256_OK, "update NULL,len=0 hợp lệ");
    CHECK(sha256_final(&c, NULL) == SHA256_ERR_PARAM, "final out NULL");
    CHECK(sha256_final(&c, h) == SHA256_OK, "final (digest rỗng)");
    CHECK(sha256_update(&c, "x", 1) == SHA256_ERR_STATE, "update sau final");
    CHECK(sha256_final(&c, h) == SHA256_ERR_STATE, "final 2 lần");
    CHECK(sha256_update(&d, "x", 1) == SHA256_ERR_STATE, "update chưa init");

    CHECK(sha256_init(&c) == SHA256_OK, "init lại");
    sha256_abort(&c); sha256_abort(&c);
    CHECK(sha256_init(&c) == SHA256_OK, "init sau abort");
    sha256_abort(&c);

    sha256_mock_reset(); g_mock.corrupt_hash = 1;
    CHECK(sha256_selftest() == SHA256_ERR_SELFTEST, "selftest bắt được lõi hỏng");
    sha256_mock_reset();
}

/* ---- T7: so sánh thời gian hằng ---- */
static void t_compare(void)
{
    uint8_t a[32], b[32];
    printf("[T7] compare\n");
    memset(a, 7, 32); memset(b, 7, 32);
    CHECK(sha256_compare(a, b, 32) == 0, "bằng nhau");
    for (int i = 0; i < 32; i++) { b[i] ^= 0x80; CHECK(sha256_compare(a, b, 32) != 0, "khác ở byte %d", i); b[i] ^= 0x80; }
    CHECK(sha256_compare(NULL, b, 32) != 0, "NULL -> khác");
}

/* ---- T8: tham số sai ở hàm one-shot không được làm rò phiên (regression) ---- */
static void t_oneshot_param_leak(void)
{
    static uint32_t rom[32];
    uint8_t h[32], r[32];
    const char *msg = "abc";
    printf("[T8] one-shot bad params must not leak session\n");
    for (int i = 0; i < 32; i++) rom[i] = rnd();
    sha256_ref((const uint8_t *)msg, 3, r);

    struct { const char *name; sha256_status_t st; } cases[4];
    sha256_mock_reset();
    cases[0].name = "digest(NULL,1,out)";      cases[0].st = sha256_digest(NULL, 1u, h);
    CHECK(sha256_digest("abc", 3u, h) == SHA256_OK, "hợp lệ ngay sau %s", cases[0].name);
    cases[1].name = "digest(data,1,NULL out)"; cases[1].st = sha256_digest("x", 1u, NULL);
    CHECK(sha256_digest("abc", 3u, h) == SHA256_OK, "hợp lệ ngay sau %s", cases[1].name);
    cases[2].name = "digest_mem(0,1,out)";     cases[2].st = sha256_digest_mem(0u, 1u, h);
    CHECK(sha256_digest("abc", 3u, h) == SHA256_OK, "hợp lệ ngay sau %s", cases[2].name);
    cases[3].name = "digest_mem(rom,4,NULL)";  cases[3].st = sha256_digest_mem((uintptr_t)rom, 4u, NULL);
    CHECK(sha256_digest("abc", 3u, h) == SHA256_OK, "hợp lệ ngay sau %s", cases[3].name);
    for (int i = 0; i < 4; i++)
        CHECK(cases[i].st == SHA256_ERR_PARAM, "%s phải trả ERR_PARAM, got %d", cases[i].name, cases[i].st);
    CHECK(!memcmp(h, r, 32), "digest đúng sau chuỗi lỗi tham số");
    CHECK(g_mock.n_start == 4, "lỗi tham số không được chạm phần cứng: n_start=%u", g_mock.n_start);

    /* Cùng lỗi nhưng lần lượt, rồi kiểm session bằng sha256_init trực tiếp */
    sha256_ctx_t c;
    (void)sha256_digest(NULL, 1u, h);
    CHECK(sha256_init(&c) == SHA256_OK, "sha256_init ngay sau lỗi one-shot");
    sha256_abort(&c);
}

/* ---- T9: ROM chỉ bị đọc bằng word căn lề, và chỉ trong các word chứa dữ liệu ---- */
static void t_rom_bounds(void)
{
    static uint32_t rom[100];
    uint8_t h[32], r[32];
    printf("[T9] ROM reads stay inside the words that hold the image\n");
    for (int i = 0; i < 100; i++) rom[i] = rnd();
    for (uint32_t off = 0; off < 4; off++)
        for (uint32_t n = 1; n <= 200; n++) {
            uintptr_t a = (uintptr_t)rom + 40 + off;           /* vùng "hợp lệ" nằm giữa mảng */
            uintptr_t lo = a & ~(uintptr_t)3, hi = (a + n + 3) & ~(uintptr_t)3;
            sha256_mock_reset();
            CHECK(sha256_digest_mem(a, n, h) == SHA256_OK, "digest_mem off=%u n=%u", off, n);
            sha256_ref((const uint8_t *)a, n, r);
            CHECK(!memcmp(h, r, 32), "digest off=%u n=%u", off, n);
            CHECK(g_mock.rom_rd_misaligned == 0, "đọc ROM không căn lề off=%u n=%u", off, n);
            CHECK(g_mock.rom_rd_lo >= lo && g_mock.rom_rd_hi <= hi,
                  "đọc ngoài vùng off=%u n=%u: [%lu,%lu) vs [%lu,%lu)", off, n,
                  (unsigned long)(g_mock.rom_rd_lo - (uintptr_t)rom), (unsigned long)(g_mock.rom_rd_hi - (uintptr_t)rom),
                  (unsigned long)(lo - (uintptr_t)rom), (unsigned long)(hi - (uintptr_t)rom));
            CHECK(g_mock.rom_rd_n == (hi - lo) / 4, "mỗi word đọc đúng 1 lần: %u vs %lu", g_mock.rom_rd_n, (unsigned long)((hi - lo) / 4));
        }
}

/* Chế độ --file: in digest HAL của file (cross-check với sha256sum) */
static int file_mode(const char *path)
{
    FILE *f = fopen(path, "rb"); long n; uint8_t *d, h[32]; char s[65];
    if (!f) { perror("open"); return 2; }
    fseek(f, 0, SEEK_END); n = ftell(f); fseek(f, 0, SEEK_SET);
    d = malloc(n ? n : 1); if (n && fread(d, 1, n, f) != (size_t)n) return 2; fclose(f);
    sha256_mock_reset();
    if (sha256_digest(d, (uint32_t)n, h) != SHA256_OK) return 3;
    hex(h, s); printf("%s\n", s); free(d); return 0;
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "--file")) return file_mode(argv[2]);
    t_kat(); t_lengths(); t_chunking(); t_mem(); t_protocol(); t_errors(); t_compare(); t_oneshot_param_leak(); t_rom_bounds();
    printf("\n==== %s: %d passed, %d failed ====\n", g_fail ? "FAILED" : "PASSED", g_pass, g_fail);
    return g_fail != 0;
}