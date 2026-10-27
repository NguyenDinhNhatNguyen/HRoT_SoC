#include "sha256_mock.h"
#include "sha256_regs.h"
#include "sha256_ref.h"
#include <string.h>

sha256_mock_t g_mock;

void sha256_mock_reset(void)
{
    memset(&g_mock, 0, sizeof g_mock);
    memcpy(g_mock.h, SHA256_REF_IV, sizeof g_mock.h);
    g_mock.init_on_first_only_ok = 1;
}

void hal_host_write32(uint32_t off, uint32_t v)
{
    if (off < 0x40u) {
        g_mock.n_block_wr++;
        if (g_mock.busy) {                                           /* writes during BUSY are ignored */
            g_mock.block_wr_while_busy++;
            return;
        }
        g_mock.block[off >> 2] = v;
    } else if (off == SHA256_REG_CTRL) {
        g_mock.n_ctrl_wr++;
        if (v & SHA256_CTRL_START) {
            if (g_mock.busy)                                         /* START during BUSY is ignored */
                return;
            if (v & SHA256_CTRL_INIT) {
                if (g_mock.n_start != 0)
                    g_mock.init_on_first_only_ok = 0;
                memcpy(g_mock.h, SHA256_REF_IV, sizeof g_mock.h);
                g_mock.n_init++;
            } else if (g_mock.n_start == 0) {
                g_mock.init_on_first_only_ok = 0;                    /* the first block must carry INIT */
            }
            g_mock.n_start++;
            g_mock.done = 0;
            g_mock.busy = 1;
            g_mock.pending = g_mock.busy_polls;
            sha256_ref_compress(g_mock.h, g_mock.block);             /* result ready now, visible at DONE */
            memcpy(g_mock.digest, g_mock.h, sizeof g_mock.digest);
            if (g_mock.corrupt_hash)
                g_mock.digest[0] ^= 1u;
        }
    }
    /* Other offsets: ignored */
}

uint32_t hal_host_read32(uint32_t off)
{
    if (off == SHA256_REG_STATUS) {
        g_mock.n_status_rd++;
        if (g_mock.stuck_busy)
            return SHA256_STATUS_BUSY;
        if (g_mock.busy) {
            if (g_mock.never_done)
                return SHA256_STATUS_BUSY;
            if (g_mock.pending > 0) {
                g_mock.pending--;
                return SHA256_STATUS_BUSY;
            }
            g_mock.busy = 0;
            g_mock.done = 1;
        }
        return (g_mock.done ? SHA256_STATUS_DONE : 0u) | (g_mock.busy ? SHA256_STATUS_BUSY : 0u);
    }
    if (off >= 0x50u && off < 0x70u) {
        g_mock.n_hash_rd++;
        return g_mock.digest[(off - 0x50u) >> 2];
    }
    return 0u;
}

#ifndef SHA256_MOCK_NO_MEMREAD
/* ROM reads go straight to host memory (sb_host_test brings its own App ROM model instead) */
uint32_t hal_host_memread32(uintptr_t addr)
{
    if (addr & 3u)
        g_mock.rom_rd_misaligned++;
    if (g_mock.rom_rd_n == 0 || addr < g_mock.rom_rd_lo)
        g_mock.rom_rd_lo = addr;
    if (g_mock.rom_rd_n == 0 || addr + 4 > g_mock.rom_rd_hi)
        g_mock.rom_rd_hi = addr + 4;
    g_mock.rom_rd_n++;
    return *(volatile const uint32_t *)addr;
}
#endif
