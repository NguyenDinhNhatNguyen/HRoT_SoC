/*
 * boot_verifier.c -- Boot_Verifier driver (see boot_verifier.h)
 */
#include "boot_verifier.h"
#include "hal_io.h"

bv_status_t bv_check(uint32_t app_ver)
{
    uint32_t st;
    uint32_t n;

    if ((HAL_RD32(SOC_BV_BASE, BV_STATUS) & BV_ST_CHECKED) != 0u)
        return BV_ERR_USED;
    HAL_WR32(SOC_BV_BASE, BV_APP_VER, app_ver);
    HAL_WR32(SOC_BV_BASE, BV_CTRL, BV_CTRL_CHECK);

    /* CHECKED comes at once, VERIFIED or FAIL once the 8 words are compared */
    for (n = BV_POLL_LIMIT; n != 0u; n--) {
        st = HAL_RD32(SOC_BV_BASE, BV_STATUS);
        if ((st & BV_ST_BUSY) == 0u && (st & (BV_ST_VERIFIED | BV_ST_FAIL)) != 0u)
            return (st & BV_ST_VERIFIED) != 0u && (st & BV_ST_FAIL) == 0u ? BV_OK : BV_ERR_FAIL;
    }
    return BV_ERR_TIMEOUT;
}

void bv_key_lock(void)
{
    HAL_WR32(SOC_BV_BASE, BV_CTRL, BV_CTRL_KEY_LOCK);
}
