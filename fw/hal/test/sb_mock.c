#include "sb_mock.h"
#include "secure_boot.h"
#include "soc_map.h"
#include "sha256_regs.h"
#include "sha256_ref.h"
#include <string.h>

sb_mock_t g_sb;

void sb_mock_reset(void)
{
    memset(&g_sb, 0, sizeof g_sb);
    g_sb.bus_err_word = -1;
    g_sb.baud_div = 26;
    g_sb.dma_src = SOC_APP_ROM_BASE;
    g_sb.dma_nblk = 64u;
}

/* START: hash nblk blocks from src the way Secure_DMA does, the result is ready at once and
 * shows up after dma_busy_polls STATUS reads */
static void dma_run(uint32_t ctrl)
{
    static uint8_t msg[4096];
    uint8_t digest[32];
    uint32_t off = g_sb.dma_src - SOC_APP_ROM_BASE;
    uint32_t i;

    g_sb.dma_starts++;
    g_sb.dma_ctrl = ctrl & (DMA_CTRL_SWAP | DMA_CTRL_PAD | DMA_CTRL_IRQ_EN);
    g_sb.dma_status = 0u;
    g_sb.dma_ok = 0;
    g_sb.dma_pending = g_sb.dma_busy_polls;
    if (g_sb.dma_err_fw || g_sb.dma_src < SOC_APP_ROM_BASE || (off & 3u) != 0u || g_sb.dma_nblk == 0u
        || g_sb.dma_nblk > 64u || off + 64u * g_sb.dma_nblk > sizeof g_sb.app_rom) {
        g_sb.dma_status = DMA_ST_DONE | DMA_ST_ERR_FW;
        return;
    }
    for (i = 0u; i < 16u * g_sb.dma_nblk; i++) {
        const uint8_t *w = &g_sb.app_rom[off + 4u * i];
        if ((int)(off / 4u + i) == g_sb.bus_err_word) {
            if (!(g_sb.bus_err & BUS_ERR_VALID)) {
                g_sb.bus_err = BUS_ERR_VALID | (2u << 2);   /* SLVERR on a read */
                g_sb.bus_err_addr = SOC_APP_ROM_BASE + off + 4u * i;
            }
            g_sb.dma_status = DMA_ST_DONE | DMA_ST_ERR_BUS;
            return;
        }
        /* SWAP: message bytes in memory order (the .bin), otherwise the big-endian bytes of each word */
        if (ctrl & DMA_CTRL_SWAP) {
            memcpy(&msg[4u * i], w, 4);
        } else {
            msg[4u * i]      = w[3];
            msg[4u * i + 1u] = w[2];
            msg[4u * i + 2u] = w[1];
            msg[4u * i + 3u] = w[0];
        }
    }
    if (!(ctrl & DMA_CTRL_PAD))
        g_sb.bad_access++;                                  /* no padding: not a complete digest */
    sha256_ref(msg, 64u * g_sb.dma_nblk, digest);
    for (i = 0u; i < 8u; i++)
        g_sb.sha_hash[i] = ((uint32_t)digest[4u * i] << 24) | ((uint32_t)digest[4u * i + 1u] << 16)
                         | ((uint32_t)digest[4u * i + 2u] << 8) | (uint32_t)digest[4u * i + 3u];
    g_sb.dma_status = DMA_ST_DONE;
    g_sb.dma_ok = 1;
}

static int dma_is_busy(void)
{
    return g_sb.dma_busy || (g_sb.dma_starts != 0u && (g_sb.dma_never_done || g_sb.dma_pending != 0u));
}

/* App ROM port B read by the CPU: one aligned 32-bit word, little-endian like the RISC-V core sees it.
 * Since P-15 the DMA hashes the App ROM, so Secure Boot must not get here (rom_reads stays 0) */
uint32_t hal_host_memread32(uintptr_t addr)
{
    uint32_t off = (uint32_t)(addr - SOC_APP_ROM_BASE);
    uint32_t w;

    g_sb.rom_reads++;
    if (addr < SOC_APP_ROM_BASE || off >= sizeof g_sb.app_rom || (off & 3u) != 0u) {
        g_sb.bad_access++;
        return 0u;
    }
    if ((int)(off / 4u) == g_sb.bus_err_word && !(g_sb.bus_err & BUS_ERR_VALID)) {
        g_sb.bus_err = BUS_ERR_VALID | (2u << 2);           /* SLVERR on a read */
        g_sb.bus_err_addr = (uint32_t)addr;
    }
    memcpy(&w, &g_sb.app_rom[off], 4);
    return w;
}

uint32_t hal_host_mmio_read32(uintptr_t addr)
{
    uint32_t w;

    if (addr >= SB_GOLDEN_ADDR && addr < SB_GOLDEN_ADDR + 32u) {
        memcpy(&w, &g_sb.golden[addr - SB_GOLDEN_ADDR], 4);
        return w;
    }
    if (addr >= SOC_SHA256_BASE + SHA256_REG_HASH(0) && addr <= SOC_SHA256_BASE + SHA256_REG_HASH(7)) {
        g_sb.hash_reads++;
        if (dma_is_busy() || !g_sb.dma_ok)
            g_sb.hash_read_early++;
        return g_sb.sha_hash[(addr - SOC_SHA256_BASE - SHA256_REG_HASH(0)) / 4u];
    }
    switch (addr) {
    case SOC_SHA256_BASE + SHA256_REG_STATUS:
        return g_sb.sha_busy ? SHA256_STATUS_BUSY : SHA256_STATUS_DONE;
    case SOC_DMA_BASE + DMA_SRC:
        return g_sb.dma_src;
    case SOC_DMA_BASE + DMA_NBLK:
        return g_sb.dma_nblk;
    case SOC_DMA_BASE + DMA_STATUS:
        if (g_sb.dma_starts != 0u)
            g_sb.dma_polls++;
        if (dma_is_busy()) {
            if (!g_sb.dma_busy && !g_sb.dma_never_done)
                g_sb.dma_pending--;
            return DMA_ST_BUSY;
        }
        return g_sb.dma_status;
    case SOC_SYSCSR_BASE + SYSCSR_APP_CTRL:
        return g_sb.app_ctrl;
    case SOC_SYSCSR_BASE + SYSCSR_BUS_ERR:
        return g_sb.bus_err;
    case SOC_SYSCSR_BASE + SYSCSR_BUS_ERR_ADDR:
        return g_sb.bus_err_addr;
    case SOC_SYSCSR_BASE + SYSCSR_GUARD:
        if (!g_sb.lock)
            return 0u;
        g_sb.guard_polls++;
        if (g_sb.zero_never_done || g_sb.guard_polls < 4u)
            return GUARD_LOCK | GUARD_ZERO_BUSY;
        return GUARD_LOCK | GUARD_ZERO_DONE;
    case SOC_UART0_BASE + UART_STATUS:
        return UART_ST_TX_IDLE;                             /* the line drains at once */
    case SOC_UART0_BASE + UART_BAUD_DIV:
        return g_sb.baud_div;
    case SOC_GPIO0_BASE + GPIO_DATA_OUT:
        return g_sb.led;
    default:
        g_sb.bad_access++;
        return 0u;
    }
}

void hal_host_mmio_write32(uintptr_t addr, uint32_t val)
{
    switch (addr) {
    case SOC_DMA_BASE + DMA_SRC:
        if (!dma_is_busy())
            g_sb.dma_src = val;
        return;
    case SOC_DMA_BASE + DMA_NBLK:
        if (!dma_is_busy())
            g_sb.dma_nblk = val;
        return;
    case SOC_DMA_BASE + DMA_CTRL:
        if (!dma_is_busy() && (val & DMA_CTRL_START))
            dma_run(val);
        return;
    case SOC_DMA_BASE + DMA_STATUS:
        g_sb.dma_status &= ~(val & (DMA_ST_DONE | DMA_ST_ERR_FW | DMA_ST_ERR_BUS));
        return;
    case SOC_SYSCSR_BASE + SYSCSR_APP_CTRL:
        g_sb.app_ctrl = val & 1u;
        return;
    case SOC_SYSCSR_BASE + SYSCSR_BUS_ERR:
        if (val & BUS_ERR_VALID) {
            g_sb.bus_err = 0u;
            g_sb.bus_err_addr = 0u;
        }
        return;
    case SOC_SYSCSR_BASE + SYSCSR_GUARD:
        if (val & GUARD_LOCK)
            g_sb.lock = 1u;
        return;
    case SOC_UART0_BASE + UART_TXDATA:
        if (g_sb.log_n < sizeof g_sb.log - 1u) {
            g_sb.log[g_sb.log_n] = (char)val;
            g_sb.log_n++;
        }
        return;
    case SOC_UART0_BASE + UART_STATUS:
    case SOC_UART0_BASE + UART_IRQ_EN:
        return;
    case SOC_UART0_BASE + UART_BAUD_DIV:
        g_sb.baud_div = val;
        return;
    case SOC_GPIO0_BASE + GPIO_DATA_OUT:
        g_sb.led = val & 0xFFu;
        return;
    default:
        g_sb.bad_access++;
        return;
    }
}
