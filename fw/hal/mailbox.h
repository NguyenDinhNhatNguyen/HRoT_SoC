/*
 * mailbox.h -- Driver for the two-way Mailbox between the Secure and the App world (P-16)
 *
 * Register map: docs/spec/SoC_Memory_Map.md (offsets and bits in soc_map.h). Each side has a
 * one-word OUT slot towards the other side and reads the other side's word from IN.
 * Every function takes the base of this side's window: SOC_MAILBOX_BASE on the Master Core,
 * APP_MAILBOX_BASE on the App Core. Polling only.
 * No libc and no multiply/divide: runs on plain rv32i, and has no constant data, so it also
 * works on the App Core (no .rodata there, see fw/app/app.ld).
 */
#ifndef MAILBOX_H
#define MAILBOX_H

#include <stdint.h>
#include "soc_map.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Max STATUS reads while waiting for the other side to take the previous word */
#ifndef MBOX_POLL_LIMIT
#define MBOX_POLL_LIMIT  100000u
#endif

typedef enum {
    MBOX_OK          =  0,
    MBOX_ERR_TIMEOUT = -1,   /* the other side did not read the previous word within MBOX_POLL_LIMIT reads */
    MBOX_EMPTY       = -2    /* mbox_recv: no word waiting */
} mbox_status_t;

/* Send one word, waiting while the previous one is still unread (OUT_FULL) */
mbox_status_t mbox_send(uintptr_t base, uint32_t word);

/* Take the waiting word if there is one (does not wait) */
mbox_status_t mbox_recv(uintptr_t base, uint32_t *word);

#ifdef __cplusplus
}
#endif
#endif /* MAILBOX_H */
