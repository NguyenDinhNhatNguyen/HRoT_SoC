/*
 * secure_boot.c -- Secure Boot of the Master Core (see secure_boot.h)
 *
 * 1. UART0 log on, SHA-256 self-test (NIST vectors, CPU through the HAL)
 * 2. Clear SYSCSR.BUS_ERR, hash the whole 4 KB App ROM through port B with the Secure DMA
 *    (SWAP and PAD, so the digest is sha256sum of the .bin, P-15). The DMA owns SHA-256 until DONE (R17)
 * 3. SYSCSR.BUS_ERR VALID: log it, keep the App in reset, clear it (N-36).
 *    DMA firewall error or timeout: log it, keep the App in reset
 * 4. Compare with the golden hash in the Boot ROM (constant time)
 *      match    -> APP_CTRL.APP_RUN = 1
 *      mismatch -> Boot Guard LOCK (App held until POR, App RAM cleared), wait for ZERO_DONE
 * 5. Result on the GPIO0 LEDs, UART drained
 * Every failure path leaves the App Core in reset (fail-safe).
 */
#include "secure_boot.h"
#include "sha256_hal.h"
#include "dma.h"
#include "uart.h"
#include "gpio.h"
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

/* Read the golden hash from the Boot ROM with word loads (works on the RTL, the VP and the host test) */
static void read_golden(uint8_t golden[SHA256_DIGEST_SIZE])
{
    uint32_t i;
    uint32_t w;

    for (i = 0u; i < SHA256_DIGEST_SIZE / 4u; i++) {
        w = HAL_RD32(SB_GOLDEN_ADDR, 4u * i);
        golden[4u * i]      = (uint8_t)w;
        golden[4u * i + 1u] = (uint8_t)(w >> 8);
        golden[4u * i + 2u] = (uint8_t)(w >> 16);
        golden[4u * i + 3u] = (uint8_t)(w >> 24);
    }
}

static sb_result_t finish(sb_result_t r)
{
    gpio_write(SOC_GPIO0_BASE, (uint8_t)r);
    (void)uart_flush(SOC_UART0_BASE);
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

sb_result_t secure_boot_run(void)
{
    uint8_t digest[SHA256_DIGEST_SIZE];
    uint8_t golden[SHA256_DIGEST_SIZE];
    dma_status_t st;
    uint32_t bus_err;
    uint32_t i;
    sb_result_t r;

    uart_init(SOC_UART0_BASE, UART_BAUD_DIV_DEFAULT);
    log_str("HRoT secure boot\n");

    if (sha256_selftest() != SHA256_OK) {
        log_str("SHA-256 self-test failed, App kept in reset\n");
        return finish(SB_SELFTEST_FAIL);
    }

    HAL_WR32(SOC_SYSCSR_BASE, SYSCSR_BUS_ERR, BUS_ERR_VALID);       /* start from a clean BUS_ERR */
    st = dma_sha256(SOC_APP_ROM_BASE, SB_APP_ROM_SIZE / 64u, 1, digest);

    bus_err = HAL_RD32(SOC_SYSCSR_BASE, SYSCSR_BUS_ERR);
    if (bus_err & BUS_ERR_VALID) {
        log_str("Bus error at ");
        log_hex(HAL_RD32(SOC_SYSCSR_BASE, SYSCSR_BUS_ERR_ADDR));
        log_str(", App kept in reset\n");
        HAL_WR32(SOC_SYSCSR_BASE, SYSCSR_BUS_ERR, BUS_ERR_VALID);
        return finish(SB_BUS_ERROR);
    }
    if (st == DMA_ERR_BUS) {
        log_str("DMA bus error, App kept in reset\n");
        return finish(SB_BUS_ERROR);
    }
    if (st == DMA_ERR_FW) {
        log_str("DMA blocked by the firewall, App kept in reset\n");
        return finish(SB_HW_ERROR);
    }
    if (st == DMA_ERR_TIMEOUT) {
        log_str("DMA timeout, App kept in reset\n");
        return finish(SB_HW_ERROR);
    }
    if (st != DMA_OK) {
        log_str("DMA error, App kept in reset\n");
        return finish(SB_HW_ERROR);
    }

    log_str("App ROM hash ");
    for (i = 0u; i < SHA256_DIGEST_SIZE; i += 4u)
        log_hex(load_be32(&digest[i]));
    log_str("\n");

    read_golden(golden);
    if (sha256_compare(digest, golden, SHA256_DIGEST_SIZE) == 0) {
        HAL_WR32(SOC_SYSCSR_BASE, SYSCSR_APP_CTRL, 1u);
        log_str("App released\n");
        return finish(SB_RELEASED);
    }

    r = lock_app();
    if (r == SB_LOCKED)
        log_str("Hash mismatch, App locked out\n");
    else
        log_str("Hash mismatch, LOCK did not finish, App kept in reset\n");
    return finish(r);
}
