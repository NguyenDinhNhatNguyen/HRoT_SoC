/*
 * mailbox.c -- Mailbox driver (see mailbox.h)
 */
#include "mailbox.h"
#include "hal_io.h"

mbox_status_t mbox_send(uintptr_t base, uint32_t word)
{
    uint32_t n;

    for (n = MBOX_POLL_LIMIT; n != 0u; n--) {
        if ((HAL_RD32(base, MBOX_STATUS) & MBOX_ST_OUT_FULL) == 0u) {
            HAL_WR32(base, MBOX_OUT, word);
            return MBOX_OK;
        }
    }
    return MBOX_ERR_TIMEOUT;
}

mbox_status_t mbox_recv(uintptr_t base, uint32_t *word)
{
    if ((HAL_RD32(base, MBOX_STATUS) & MBOX_ST_IN_FULL) == 0u)
        return MBOX_EMPTY;
    *word = HAL_RD32(base, MBOX_IN);
    return MBOX_OK;
}
