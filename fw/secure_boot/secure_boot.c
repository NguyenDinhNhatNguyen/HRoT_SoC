/*
 * secure_boot.c -- Secure Boot of the Master Core (see secure_boot.h)
 *
 * 1. UART0 log on, WDT on (1 s), SHA-256 self-test (NIST vectors, CPU through the HAL)
 * 2. Clear SYSCSR.BUS_ERR, hash the whole 4 KB App ROM through port B with the Secure DMA
 *    (SWAP and PAD, so the digest is sha256sum of the .bin, P-15). The DMA owns SHA-256 until DONE (R17)
 * 3. Read the golden hash from the Boot ROM, then check SYSCSR.BUS_ERR once more (N-36)
 * 4. Compare with the golden hash (constant time)
 * 5. Hardware verdict (I-08): APP_VER from the last App ROM word, Boot_Verifier CHECK on the digest the
 *    DMA left in SHA-256 (nothing touches SHA-256 in between). VERIFIED: KEY_LOCK, APP_CTRL.APP_RUN = 1,
 *    and APP_RUN must read back 1 (with VERIFY_GATE the gate would hold it otherwise)
 * 6. Result on the GPIO0 LEDs, UART drained
 * Every failure (self-test, bus error, DMA error, hash mismatch, Boot_Verifier) ends in Boot Guard LOCK
 * and KEY_LOCK: the App is
 * held until POR and its RAM is cleared (fail-safe, Nguyen's note on P-13, 04/11). If LOCK does not
 * finish the result is SB_HW_ERROR. A hang anywhere is caught by the WDT, and LOCK survives its reset.
 * A trap goes to secure_boot_trap() (P-24): logged, then the same LOCK as any failure.
 * After the boot, main() kicks the WDT for ever and, after a release, secure_boot_relay_app() logs
 * the App's Mailbox words on UART0 (P-16).
 */
#include "secure_boot.h"
#include "sha256_hal.h"
#include "dma.h"
#include "mailbox.h"
#include "uart.h"
#include "gpio.h"
#include "wdt.h"
#include "boot_verifier.h"
#include "hal_io.h"
#include "soc_map.h"

#ifndef SB_GUARD_POLL_LIMIT
#define SB_GUARD_POLL_LIMIT  100000u    /* zeroization clears 1024 words, one per cycle */
#endif

static void log_str(const char *s)
{
    (void)uart_puts(SOC_UART0_BASE, s);
}

static void log_hex(uint32_t v)
{
    (void)uart_put_hex32(SOC_UART0_BASE, v);
}

static uint32_t load_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

/* Read the golden hash from the Boot ROM with word loads (works on the RTL, the VP and the host test).
 * Word i is H_i, big-endian: its top byte is digest byte 4i (I-03, the form Boot_Verifier compares) */
static void read_golden(uint8_t golden[SHA256_DIGEST_SIZE])
{
    uint32_t i;
    uint32_t w;

    for (i = 0u; i < SHA256_DIGEST_SIZE / 4u; i++) {
        w = HAL_RD32(SB_GOLDEN_ADDR, 4u * i);
        golden[4u * i]      = (uint8_t)(w >> 24);
        golden[4u * i + 1u] = (uint8_t)(w >> 16);
        golden[4u * i + 2u] = (uint8_t)(w >> 8);
        golden[4u * i + 3u] = (uint8_t)w;
    }
}

static sb_result_t finish(sb_result_t r)
{
    gpio_write(SOC_GPIO0_BASE, (uint8_t)r);
    (void)uart_flush(SOC_UART0_BASE);
    wdt_kick();
    return r;
}

static sb_result_t lock_app(void)
{
    uint32_t n;

    HAL_WR32(SOC_SYSCSR_BASE, SYSCSR_GUARD, GUARD_LOCK);
    for (n = SB_GUARD_POLL_LIMIT; n != 0u; n--) {
        if (HAL_RD32(SOC_SYSCSR_BASE, SYSCSR_GUARD) & GUARD_ZERO_DONE)
            return SB_LOCKED;
    }
    return SB_HW_ERROR;
}

/* Every failure: lock the App out, log why, show r (or SB_HW_ERROR if LOCK did not finish) */
static sb_result_t fail(sb_result_t r, const char *why)
{
    wdt_kick();
    bv_key_lock();
    log_str(why);
    if (lock_app() != SB_LOCKED) {
        log_str(", LOCK did not finish, App kept in reset\n");
        return finish(SB_HW_ERROR);
    }
    log_str(", App locked out\n");
    return finish(r);
}

/* SYSCSR.BUS_ERR VALID: log the address and clear it. Returns 1 when there was an error */
static int bus_error_seen(void)
{
    if ((HAL_RD32(SOC_SYSCSR_BASE, SYSCSR_BUS_ERR) & BUS_ERR_VALID) == 0u)
        return 0;
    log_str("Bus error at ");
    log_hex(HAL_RD32(SOC_SYSCSR_BASE, SYSCSR_BUS_ERR_ADDR));
    log_str("\n");
    HAL_WR32(SOC_SYSCSR_BASE, SYSCSR_BUS_ERR, BUS_ERR_VALID);
    return 1;
}

sb_result_t secure_boot_run(void)
{
    uint8_t digest[SHA256_DIGEST_SIZE];
    uint8_t golden[SHA256_DIGEST_SIZE];
    dma_status_t st;
    bv_status_t bv;
    uint32_t app_ver;
    uint32_t i;

    uart_init(SOC_UART0_BASE, UART_BAUD_DIV_DEFAULT);
    log_str("HRoT secure boot\n");
    wdt_start(SB_WDT_LOAD);

    if (sha256_selftest() != SHA256_OK)
        return fail(SB_SELFTEST_FAIL, "SHA-256 self-test failed");

    HAL_WR32(SOC_SYSCSR_BASE, SYSCSR_BUS_ERR, BUS_ERR_VALID);       /* start from a clean BUS_ERR */
    st = dma_sha256(SOC_APP_ROM_BASE, SB_APP_ROM_SIZE / 64u, 1, digest);
    wdt_kick();

    if (bus_error_seen())
        return fail(SB_BUS_ERROR, "Bus error while hashing");
    if (st == DMA_ERR_BUS)
        return fail(SB_BUS_ERROR, "DMA bus error");
    if (st == DMA_ERR_FW)
        return fail(SB_HW_ERROR, "DMA blocked by the firewall");
    if (st == DMA_ERR_TIMEOUT)
        return fail(SB_HW_ERROR, "DMA timeout");
    if (st != DMA_OK)
        return fail(SB_HW_ERROR, "DMA error");

    log_str("App ROM hash ");
    for (i = 0u; i < SHA256_DIGEST_SIZE; i += 4u)
        log_hex(load_be32(&digest[i]));
    log_str("\n");

    read_golden(golden);
    if (bus_error_seen())
        return fail(SB_BUS_ERROR, "Bus error while reading the golden hash");
    if (sha256_compare(digest, golden, SHA256_DIGEST_SIZE) != 0)
        return fail(SB_LOCKED, "Hash mismatch");

    /* Hardware verdict (I-08), on the digest the DMA left in SHA-256 */
    app_ver = HAL_RD32(SOC_APP_ROM_BASE, SB_APP_VER_OFF);
    if (bus_error_seen())
        return fail(SB_BUS_ERROR, "Bus error while reading APP_VER");
    log_str("App version ");
    log_hex(app_ver);
    log_str("\n");
    bv = bv_check(app_ver);
    if (bv == BV_ERR_TIMEOUT)
        return fail(SB_VERIFY_FAIL, "Boot_Verifier timeout");
    if (bv != BV_OK)
        return fail(SB_VERIFY_FAIL, "Boot_Verifier refused the image");
    bv_key_lock();

    HAL_WR32(SOC_SYSCSR_BASE, SYSCSR_APP_CTRL, 1u);
    if ((HAL_RD32(SOC_SYSCSR_BASE, SYSCSR_APP_CTRL) & 1u) == 0u)
        return fail(SB_VERIFY_FAIL, "Release gate held the App");
    log_str("App released\n");
    return finish(SB_RELEASED);
}

void secure_boot_relay_app(void)
{
    uint32_t w;

    if (mbox_recv(SOC_MAILBOX_BASE, &w) != MBOX_OK)
        return;
    log_str("App says ");
    log_hex(w);
    log_str("\n");
}

void secure_boot_trap(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    log_str("Trap mcause ");
    log_hex(mcause);
    log_str(" mepc ");
    log_hex(mepc);
    log_str(" mtval ");
    log_hex(mtval);
    log_str("\n");
    (void)fail(SB_TRAP, "Trap");
}
