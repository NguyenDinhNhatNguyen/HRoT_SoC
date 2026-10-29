/* Secure Boot (P-13, P-15) unit test on the host: secure_boot_run() against models of the App ROM,
 * the Boot ROM golden slot, SYSCSR, UART0, GPIO0, the Secure DMA (sb_mock.c) and SHA-256 (sha256_mock.c).
 * Covers the paths that are hard to reach on the RTL: bus error while hashing, broken SHA core,
 * Boot Guard that never finishes, DMA firewall error, DMA that never finishes or is already busy,
 * and the relay of the App's Mailbox words to UART0 after a release (P-16).
 * Prints "SB RESULT: PASS|FAIL". */
#include "secure_boot.h"
#include "sb_mock.h"
#include "dma.h"
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
    g_sb.dma_busy_polls = 5;
    make_image();
}

/* The DMA path was used once, as Secure Boot needs it: whole App ROM, SWAP and PAD, no interrupt,
 * DONE cleared afterwards, the CPU neither read the App ROM nor used SHA-256 after the self-test */
static void check_dma_used(void)
{
    CHECK(g_sb.dma_starts == 1u, "DMA started %u times", g_sb.dma_starts);
    CHECK(g_sb.dma_src == SOC_APP_ROM_BASE && g_sb.dma_nblk == 64u, "SRC=%08x NBLK=%u", g_sb.dma_src, g_sb.dma_nblk);
    CHECK(g_sb.dma_ctrl == (DMA_CTRL_SWAP | DMA_CTRL_PAD), "CTRL options=%x", g_sb.dma_ctrl);
    CHECK(g_sb.dma_status == 0u, "DMA STATUS not cleared: %x", g_sb.dma_status);
    CHECK(g_sb.dma_polls > g_sb.dma_busy_polls, "DONE not waited for (%u polls)", g_sb.dma_polls);
    CHECK(g_sb.rom_reads == 0u, "CPU read the App ROM %u times", g_sb.rom_reads);
    CHECK(g_mock.n_start == 4u, "SHA-256 started %u times by the CPU (self-test only = 4)", g_mock.n_start);
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
    check_dma_used();
    CHECK(g_sb.hash_reads == 8u && g_sb.hash_read_early == 0u, "HASH reads %u, %u before DONE",
          g_sb.hash_reads, g_sb.hash_read_early);
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
    check_dma_used();
}

/* S3: SLVERR while the DMA reads the App ROM -> logged, App kept in reset, BUS_ERR cleared (N-36) */
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
    CHECK(g_sb.hash_read_early == 0u, "HASH read after a failed DMA run");
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
    CHECK(g_sb.rom_reads == 0u && g_sb.dma_starts == 0u, "App ROM hashed after a failed self-test");
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

/* S9: the DMA firewall blocks the transfer -> App kept in reset, no LOCK, no digest read */
static void t_dma_firewall(void)
{
    printf("[S9] DMA firewall error\n");
    reset_all();
    g_sb.dma_err_fw = 1;
    CHECK(secure_boot_run() == SB_HW_ERROR, "result");
    CHECK(g_sb.app_ctrl == 0u && g_sb.lock == 0u, "app_ctrl=%u lock=%u", g_sb.app_ctrl, g_sb.lock);
    CHECK(strstr(g_sb.log, "DMA blocked by the firewall, App kept in reset\r\n") != NULL, "log: %s", g_sb.log);
    CHECK(g_sb.dma_status == 0u, "DMA STATUS not cleared: %x", g_sb.dma_status);
    CHECK(g_sb.hash_reads == 0u, "HASH read %u times", g_sb.hash_reads);
    CHECK(g_sb.led == SB_HW_ERROR, "LED=%02x", g_sb.led);
}

/* S10: the DMA never finishes -> bounded wait, App kept in reset, SHA-256 left alone (R17) */
static void t_dma_timeout(void)
{
    printf("[S10] DMA never DONE\n");
    reset_all();
    g_sb.dma_never_done = 1;
    CHECK(secure_boot_run() == SB_HW_ERROR, "result");
    CHECK(g_sb.app_ctrl == 0u && g_sb.lock == 0u, "app_ctrl=%u lock=%u", g_sb.app_ctrl, g_sb.lock);
    CHECK(strstr(g_sb.log, "DMA timeout, App kept in reset\r\n") != NULL, "log: %s", g_sb.log);
    CHECK(g_sb.dma_polls == DMA_POLL_LIMIT, "%u STATUS polls, limit %u", g_sb.dma_polls, DMA_POLL_LIMIT);
    CHECK(g_sb.hash_reads == 0u && g_mock.n_start == 4u, "SHA-256 touched while the DMA owns it");
}

/* S11: the DMA or SHA-256 is already busy -> nothing started, App kept in reset */
static void t_dma_busy(void)
{
    printf("[S11] DMA or SHA-256 already busy\n");
    reset_all();
    g_sb.dma_busy = 1;
    CHECK(secure_boot_run() == SB_HW_ERROR, "result (DMA busy)");
    CHECK(g_sb.dma_starts == 0u && g_sb.app_ctrl == 0u, "starts=%u app_ctrl=%u", g_sb.dma_starts, g_sb.app_ctrl);
    CHECK(strstr(g_sb.log, "DMA error, App kept in reset\r\n") != NULL, "log: %s", g_sb.log);
    reset_all();
    g_sb.sha_busy = 1;
    CHECK(secure_boot_run() == SB_HW_ERROR, "result (SHA-256 busy)");
    CHECK(g_sb.dma_starts == 0u && g_sb.app_ctrl == 0u, "starts=%u app_ctrl=%u", g_sb.dma_starts, g_sb.app_ctrl);
}

/* S12: a DMA that finishes at once (DONE on the first poll) still works */
static void t_dma_fast(void)
{
    printf("[S12] DMA DONE on the first poll\n");
    reset_all();
    g_sb.dma_busy_polls = 0;
    CHECK(secure_boot_run() == SB_RELEASED, "result");
    CHECK(g_sb.dma_polls == 1u, "%u polls", g_sb.dma_polls);
}

/* S13: after a release the Master logs each Mailbox word of the App, and does nothing while IN is empty */
static void t_relay(void)
{
    uint32_t n;
    printf("[S13] App Mailbox words relayed to UART0\n");
    reset_all();
    CHECK(secure_boot_run() == SB_RELEASED, "result");
    n = g_sb.log_n;
    secure_boot_relay_app();
    CHECK(g_sb.log_n == n && g_sb.mbox_in_reads == 0u, "empty Mailbox must not log or read IN");
    g_sb.mbox_in = 0x41505031u;
    g_sb.mbox_in_full = 1;
    secure_boot_relay_app();
    CHECK(strstr(g_sb.log, "App says 41505031\r\n") != NULL, "log: %s", g_sb.log);
    CHECK(g_sb.mbox_in_full == 0 && g_sb.mbox_in_reads == 1u, "IN read %u times", g_sb.mbox_in_reads);
    g_sb.mbox_in = 0x53540002u;
    g_sb.mbox_in_full = 1;
    secure_boot_relay_app();
    CHECK(strstr(g_sb.log, "App says 53540002\r\n") != NULL, "second word, log: %s", g_sb.log);
    CHECK(g_sb.bad_access == 0u, "%u accesses outside the models", g_sb.bad_access);
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
    t_dma_firewall();
    t_dma_timeout();
    t_dma_busy();
    t_dma_fast();
    t_relay();
    printf("\nSUMMARY SB: PASS = %d | FAIL = %d\n", g_pass, g_fail);
    printf("SB RESULT: %s\n", g_fail ? "FAIL" : "PASS");
    return g_fail != 0;
}
