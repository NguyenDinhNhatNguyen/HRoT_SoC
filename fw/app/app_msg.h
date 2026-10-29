/*
 * app_msg.h -- Mailbox words the App Core demo sends to the Secure world (P-16)
 *
 * Shared by fw/app (sender) and the tests. The Master Core logs every word it gets as
 * "App says <8 hex digits>" on UART0, so the App shows up on the board log although
 * UART1 has no pin on the DE2.
 */
#ifndef APP_MSG_H
#define APP_MSG_H

#define APP_MSG_HELLO   0x41505031u     /* "APP1": the App Core is running */
#define APP_MSG_STEP    0x53540000u     /* "ST" + 16-bit step count of the LED running light */

#endif /* APP_MSG_H */
