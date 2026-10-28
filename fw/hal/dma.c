/*
 * dma.c -- Secure DMA driver (see dma.h)
 */
#include "dma.h"
#include "hal_io.h"
#include "sha256_regs.h"

#define DMA_MAX_NBLK   0x007FFFFFu     /* the padding block holds the bit length in 32 bits */

static void pause(void)
{
    uint32_t i;

    for (i = DMA_POLL_PAUSE; i != 0u; i--)
        __asm__ volatile ("");
}

dma_status_t dma_sha256(uint32_t src, uint32_t nblk, int swap, uint8_t out[32])
{
    uint32_t st;
    uint32_t n;
    uint32_t w;
    uint32_t i;

    if (out == 0 || nblk == 0u || nblk > DMA_MAX_NBLK || (src & 3u) != 0u)
        return DMA_ERR_PARAM;
    if ((HAL_RD32(SOC_DMA_BASE, DMA_STATUS) & DMA_ST_BUSY) != 0u)
        return DMA_ERR_BUSY;
    if ((HAL_RD32(SOC_SHA256_BASE, SHA256_REG_STATUS) & SHA256_STATUS_BUSY) != 0u)
        return DMA_ERR_BUSY;

    HAL_WR32(SOC_DMA_BASE, DMA_SRC, src);
    HAL_WR32(SOC_DMA_BASE, DMA_NBLK, nblk);
    HAL_WR32(SOC_DMA_BASE, DMA_CTRL, DMA_CTRL_START | DMA_CTRL_PAD | (swap ? DMA_CTRL_SWAP : 0u));

    st = 0u;
    for (n = DMA_POLL_LIMIT; n != 0u; n--) {
        pause();
        st = HAL_RD32(SOC_DMA_BASE, DMA_STATUS);
        if ((st & DMA_ST_DONE) != 0u)
            break;
    }
    if ((st & DMA_ST_DONE) == 0u)
        return DMA_ERR_TIMEOUT;

    HAL_WR32(SOC_DMA_BASE, DMA_STATUS, DMA_ST_DONE | DMA_ST_ERR_FW | DMA_ST_ERR_BUS);
    if ((st & DMA_ST_ERR_FW) != 0u)
        return DMA_ERR_FW;
    if ((st & DMA_ST_ERR_BUS) != 0u)
        return DMA_ERR_BUS;

    /* HASH[0] = H0, first digest byte in bits [31:24] */
    for (i = 0u; i < SHA256_HASH_WORDS; i++) {
        w = HAL_RD32(SOC_SHA256_BASE, SHA256_REG_HASH(i));
        out[4u * i]      = (uint8_t)(w >> 24);
        out[4u * i + 1u] = (uint8_t)(w >> 16);
        out[4u * i + 2u] = (uint8_t)(w >> 8);
        out[4u * i + 3u] = (uint8_t)w;
    }
    return DMA_OK;
}
