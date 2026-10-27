/*
 * soc_irq_app.S -- P-14: interrupts of the App Core on the whole SoC (App ROM of SoC_Irq_tb)
 *
 *   1. TIMER1 -> irq_timer: mcause 0x80000007
 *   2. Mailbox from the Secure world (sent before the App was released) -> irq_ext, mcause 0x8000000B,
 *      word 0x1234, then the App answers 0x1235
 * Result on the GPIO1 LEDs: 0x01 = PASS, 0x80 | n = FAIL at step n.
 * The App APB bus answers in one cycle (no stall), so the handler waits a few cycles after clearing
 * the source before MRET.
 *
 * Rebuild the .hex (needs riscv64-unknown-elf-gcc):
 *   riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -nostdlib -Ttext=0 -o soc_irq_app.elf soc_irq_app.S
 *   riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=4 -j .text soc_irq_app.elf soc_irq_app.hex
 */
#define GPIO1  0x40001000
#define TIMER1 0x40002000
#define MBOX   0x40003000

.macro WAIT_NZ reg, n
    li   x30, \n
91: bnez \reg, 92f
    addi x30, x30, -1
    bnez x30, 91b
    j    fail
92:
.endm

    .text
    .globl _start
_start:
    li   x31, 0
    la   x5, handler
    csrw mtvec, x5
    li   x8, GPIO1
    li   x9, TIMER1
    li   x19, MBOX

    /* ---- 1. TIMER1 ---- */
    li   x31, 1
    li   x29, 0
    li   x30, -1
    sw   x30, 0xC(x9)
    lw   x30, 0(x9)
    addi x30, x30, 200
    sw   x30, 8(x9)
    lw   x30, 4(x9)
    sw   x30, 0xC(x9)
    li   x5, 0x80
    csrw mie, x5
    csrsi mstatus, 8
    WAIT_NZ x29, 5000
    li   x5, 0x80000007
    bne  x29, x5, fail

    /* ---- 2. Mailbox from the Secure world ---- */
    li   x31, 2
    csrci mstatus, 8
    li   x5, 1
    sw   x5, 0xC(x19)               /* App mailbox IRQ_EN */
    li   x5, 0x800
    csrw mie, x5
    li   x29, 0
    li   x22, 0
    csrsi mstatus, 8
    WAIT_NZ x29, 5000
    li   x5, 0x8000000B
    bne  x29, x5, fail
    li   x5, 0x1234
    bne  x22, x5, fail
    csrci mstatus, 8
    addi x5, x22, 1
    sw   x5, 0(x19)                 /* answer 0x1235 */

    li   x5, 1
    sw   x5, 0(x8)
1:  j    1b

fail:
    csrci mstatus, 8
    ori  x5, x31, 0x80
    sw   x5, 0(x8)
2:  j    2b

handler:
    csrr x28, mcause
    bgez x28, fail
    li   x27, 0x80000007
    beq  x28, x27, h_timer
    lw   x22, 4(x19)                /* IN: reading clears IN_FULL */
    j    h_done
h_timer:
    li   x27, -1
    sw   x27, 0xC(x9)               /* MTIMECMP_HI all ones: the line drops */
h_done:
    nop
    nop
    nop
    mv   x29, x28
    mret
