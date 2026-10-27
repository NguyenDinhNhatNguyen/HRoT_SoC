#include "sb_mock.h"
#include "secure_boot.h"
#include "soc_map.h"
#include <string.h>

sb_mock_t g_sb;

void sb_mock_reset(void)
{
    memset(&g_sb, 0, sizeof g_sb);
    g_sb.bus_err_word = -1;
    g_sb.baud_div = 26;
}

/* App ROM port B: one aligned 32-bit word, little-endian like the RISC-V core sees it */
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
    switch (addr) {
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
