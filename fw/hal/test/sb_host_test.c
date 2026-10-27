/* Secure Boot (P-13) unit test on the host: secure_boot_run() against models of the App ROM,
 * the Boot ROM golden slot, SYSCSR, UART0, GPIO0 (sb_mock.c) and SHA-256 (sha256_mock.c).
 * Covers the paths that are hard to reach on the RTL: bus error while hashing, broken SHA core,
 * Boot Guard that never finishes. Prints "SB RESULT: PASS|FAIL". */
#include "secure_boot.h"
#include "sb_mock.h"
#include "sha256_mock.h"
#include "sha256_ref.h"
#include "soc_map.h"
#include <stdio.h>
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

/* A 4 KB App image with some code-like words, the rest zero (like a real App ROM) */
static void make_image(void)
{
    static const uint32_t words[] = { 0x02a00093u, 0x00102023u, 0x0000006fu, 0x12345678u };
    uint32_t i;

    memset(g_sb.app_rom, 0, sizeof g_sb.app_rom);
    for (i = 0; i < 4; i++)
        memcpy(&g_sb.app_rom[4 * i], &words[i], 4);
    sha256_ref(g_sb.app_rom, sizeof g_sb.app_rom, g_sb.golden);     /* golden = sha256sum of the .bin */
}

static void reset_all(void)
{
    sha256_mock_reset();
    g_mock.busy_polls = 3;
    sb_mock_reset();
    make_image();
}

static void hex_of(const uint8_t *d, char *o)
{
    for (int i = 0; i < 32; i++)
        sprintf(o + 2 * i, "%02x", d[i]);
}

/* S1: good image -> App released, hash printed, nothing locked */
static void t_good(void)
{
    char hex[65];
    char line[96];
    printf("[S1] good image\n");
    reset_all();
    CHECK(secure_boot_run() == SB_RELEASED, "result");
    CHECK(g_sb.app_ctrl == 1u && g_sb.lock == 0u, "app_ctrl=%u lock=%u", g_sb.app_ctrl, g_sb.lock);
    CHECK(g_sb.led == SB_RELEASED, "LED=%02x", g_sb.led);
    CHECK(strstr(g_sb.log, "App released\r\n") != NULL, "log: %s", g_sb.log);
    hex_of(g_sb.golden, hex);
    snprintf(line, sizeof line, "App ROM hash %s\r\n", hex);
    CHECK(strstr(g_sb.log, line) != NULL, "hash line missing, log: %s", g_sb.log);
    CHECK(g_sb.rom_reads == 1024u, "App ROM words read: %u", g_sb.rom_reads);
    CHECK(g_sb.baud_div == 26u, "BAUD_DIV=%u", g_sb.baud_div);
    CHECK(g_sb.bad_access == 0u, "%u accesses outside the models", g_sb.bad_access);
}

/* S2: one bit flipped in the App ROM -> Boot Guard LOCK, App never released */
static void t_tamper(void)
{
    printf("[S2] tampered image\n");
    reset_all();
    g_sb.app_rom[4000] ^= 0x10u;
    CHECK(secure_boot_run() == SB_LOCKED, "result");
    CHECK(g_sb.app_ctrl == 0u && g_sb.lock == 1u, "app_ctrl=%u lock=%u", g_sb.app_ctrl, g_sb.lock);
    CHECK(g_sb.led == SB_LOCKED, "LED=%02x", g_sb.led);
    CHECK(strstr(g_sb.log, "Hash mismatch, App locked out\r\n") != NULL, "log: %s", g_sb.log);
    CHECK(g_sb.guard_polls >= 4u, "did not wait for ZERO_DONE");
}

/* S3: SLVERR while reading the App ROM -> logged, App kept in reset, BUS_ERR cleared (N-36) */
static void t_bus_error(void)
{
    printf("[S3] bus error while hashing\n");
    reset_all();
    g_sb.bus_err_word = 300;
    CHECK(secure_boot_run() == SB_BUS_ERROR, "result");
    CHECK(g_sb.app_ctrl == 0u && g_sb.lock == 0u, "app_ctrl=%u lock=%u", g_sb.app_ctrl, g_sb.lock);
    CHECK(g_sb.bus_err == 0u, "BUS_ERR not cleared: %x", g_sb.bus_err);
    CHECK(strstr(g_sb.log, "Bus error at 600004b0, App kept in reset\r\n") != NULL, "log: %s", g_sb.log);
    CHECK(g_sb.led == SB_BUS_ERROR, "LED=%02x", g_sb.led);
}

/* S4: an old BUS_ERR from before the boot is cleared first and does not block a good image */
static void t_stale_bus_error(void)
{
    printf("[S4] stale BUS_ERR before hashing\n");
    reset_all();
    g_sb.bus_err = BUS_ERR_VALID | (3u << 2);
    g_sb.bus_err_addr = 0x70000000u;
    CHECK(secure_boot_run() == SB_RELEASED, "result");
    CHECK(g_sb.app_ctrl == 1u, "app_ctrl=%u", g_sb.app_ctrl);
}

/* S5: SHA-256 core gives wrong digests -> self-test catches it, App kept in reset */
static void t_selftest(void)
{
    printf("[S5] broken SHA-256 core\n");
    reset_all();
    g_mock.corrupt_hash = 1;
    CHECK(secure_boot_run() == SB_SELFTEST_FAIL, "result");
    CHECK(g_sb.app_ctrl == 0u && g_sb.lock == 0u, "app_ctrl=%u lock=%u", g_sb.app_ctrl, g_sb.lock);
    CHECK(g_sb.rom_reads == 0u, "App ROM read %u times after a failed self-test", g_sb.rom_reads);
    CHECK(strstr(g_sb.log, "self-test failed") != NULL, "log: %s", g_sb.log);
}

/* S6: SHA-256 never finishes -> timeout in the self-test, App kept in reset */
static void t_sha_timeout(void)
{
    printf("[S6] SHA-256 never DONE\n");
    reset_all();
    g_mock.never_done = 1;
    CHECK(secure_boot_run() == SB_SELFTEST_FAIL, "result");
    CHECK(g_sb.app_ctrl == 0u, "app_ctrl=%u", g_sb.app_ctrl);
}

/* S7: Boot Guard zeroization never finishes -> reported, App still held (LOCK is set) */
static void t_guard_stuck(void)
{
    printf("[S7] zeroization never finishes\n");
    reset_all();
    g_sb.app_rom[0] ^= 1u;
    g_sb.zero_never_done = 1;
    CHECK(secure_boot_run() == SB_HW_ERROR, "result");
    CHECK(g_sb.app_ctrl == 0u && g_sb.lock == 1u, "app_ctrl=%u lock=%u", g_sb.app_ctrl, g_sb.lock);
    CHECK(strstr(g_sb.log, "LOCK did not finish") != NULL, "log: %s", g_sb.log);
}

/* S8: golden bytes in the wrong order (big-endian words) must not pass */
static void t_golden_order(void)
{
    uint8_t t;
    printf("[S8] golden stored in the wrong byte order\n");
    reset_all();
    for (int i = 0; i < 32; i += 4) {
        t = g_sb.golden[i];
        g_sb.golden[i] = g_sb.golden[i + 3];
        g_sb.golden[i + 3] = t;
        t = g_sb.golden[i + 1];
        g_sb.golden[i + 1] = g_sb.golden[i + 2];
        g_sb.golden[i + 2] = t;
    }
    CHECK(secure_boot_run() == SB_LOCKED, "result");
}

int main(void)
{
    t_good();
    t_tamper();
    t_bus_error();
    t_stale_bus_error();
    t_selftest();
    t_sha_timeout();
    t_guard_stuck();
    t_golden_order();
    printf("\nSUMMARY SB: PASS = %d | FAIL = %d\n", g_pass, g_fail);
    printf("SB RESULT: %s\n", g_fail ? "FAIL" : "PASS");
    return g_fail != 0;
}
