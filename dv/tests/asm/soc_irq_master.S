/*
 * soc_irq_master.S -- P-14: interrupts of the Master Core on the whole SoC (Boot ROM of SoC_Irq_tb)
 *
 *   1. TIMER0 -> irq_timer: mtimecmp a little ahead, mcause 0x80000007, mip.MTIP gone after the handler
 *   2. GPIO0 pin 0 -> PLIC-lite source 1 -> irq_ext: the testbench raises the pin when the LEDs show 0xA1,
 *      mcause 0x8000000B, CLAIM = 2, PENDING cleared by the handler (GPIO IRQ_STAT W1C)
 *   3. Priority: timer and external pending together while mstatus.MIE = 0 (pin raised on LED 0xA2),
 *      then MIE = 1: MEI is taken first, MTI right after
 *   4. Mailbox: send 0x1234 to the App, release the App Core, the App answers 0x1235, which arrives
 *      through PLIC-lite source 3 (CLAIM = 4)
 * Result on the GPIO0 LEDs: 0x01 = PASS, 0x80 | n = FAIL at step n.
 *
 * Registers: x31 step, x29 last mcause, x25 last CLAIM, x24 interrupt count, x23 first mcause,
 * x22 mailbox word. x26..x28 belong to the handler.
 *
 * Rebuild the .hex (needs riscv64-unknown-elf-gcc):
 *   riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -nostdlib -Ttext=0 -o soc_irq_master.elf soc_irq_master.S
 *   riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=4 -j .text soc_irq_master.elf soc_irq_master.hex
 */
#define SYSCSR 0x40000000
#define GPIO0  0x40002000
#define TIMER0 0x40003000
#define PLIC   0x40005000
#define MBOX   0x40006000

/* Wait until reg != 0, at most n turns of the loop, else fail */
.macro WAIT_NZ reg, n
    li   x30, \n
91: bnez \reg, 92f
    addi x30, x30, -1
    bnez x30, 91b
    j    fail
92:
.endm

/* mtimecmp = mtime + d (HI all ones first, so no early interrupt) */
.macro TIMER_IN base, d
    li   x30, -1
    sw   x30, 0xC(\base)
    lw   x30, 0(\base)
    addi x30, x30, \d
    sw   x30, 8(\base)
    lw   x30, 4(\base)
    sw   x30, 0xC(\base)
.endm

    .text
    .globl _start
_start:
    li   x31, 0
    la   x5, handler
    csrw mtvec, x5
    li   x8, GPIO0
    li   x9, TIMER0
    li   x18, PLIC
    li   x19, MBOX

    /* ---- 1. TIMER0 ---- */
    li   x31, 1
    li   x24, 0
    li   x29, 0
    TIMER_IN x9, 300
    li   x5, 0x80
    csrw mie, x5
    csrsi mstatus, 8
    WAIT_NZ x29, 5000
    li   x5, 0x80000007
    bne  x29, x5, fail
    csrr x6, mip
    andi x6, x6, 0x80
    bnez x6, fail

    /* ---- 2. External: GPIO0 pin 0 through PLIC-lite source 1 ---- */
    li   x31, 2
    csrci mstatus, 8
    li   x5, 1
    sw   x5, 8(x8)                  /* GPIO0 IRQ_EN pin 0 */
    li   x5, 2
    sw   x5, 4(x18)                 /* PLIC ENABLE source 1 */
    li   x5, 0x800
    csrw mie, x5
    li   x29, 0
    li   x25, 0
    csrsi mstatus, 8
    li   x5, 0xA1
    sw   x5, 0(x8)                  /* LED 0xA1: the testbench raises gpio0_i[0] */
    WAIT_NZ x29, 20000
    li   x5, 0x8000000B
    bne  x29, x5, fail
    li   x5, 2
    bne  x25, x5, fail              /* CLAIM = 1 + source 1 */
    lw   x6, 0(x18)
    andi x6, x6, 2
    bnez x6, fail                   /* PENDING bit 1 cleared by the handler */

    /* ---- 3. Timer and external pending together: MEI first ---- */
    li   x31, 3
    csrci mstatus, 8
    li   x5, 0x880
    csrw mie, x5
    TIMER_IN x9, 50
    li   x5, 0xA2
    sw   x5, 0(x8)                  /* LED 0xA2: the testbench raises gpio0_i[0] again */
    li   x30, 20000
3:  csrr x6, mip
    li   x5, 0x880
    beq  x6, x5, 4f
    addi x30, x30, -1
    bnez x30, 3b
    j    fail
4:  li   x24, 0
    li   x23, 0
    csrsi mstatus, 8
    li   x30, 5000
5:  addi x6, x24, -2
    beqz x6, 6f
    addi x30, x30, -1
    bnez x30, 5b
    j    fail
6:  li   x5, 0x8000000B
    bne  x23, x5, fail              /* first taken: MEI */
    li   x5, 0x80000007
    bne  x29, x5, fail              /* then MTI */

    /* ---- 4. Mailbox both ways with the App Core ---- */
    li   x31, 4
    csrci mstatus, 8
    li   x5, 1
    sw   x5, 0xC(x19)               /* Secure mailbox IRQ_EN */
    li   x5, 8
    sw   x5, 4(x18)                 /* PLIC ENABLE source 3 only */
    li   x5, 0x800
    csrw mie, x5
    li   x29, 0
    li   x22, 0
    li   x5, 0x1234
    sw   x5, 0(x19)                 /* word for the App, waits in its IN */
    li   x6, SYSCSR
    li   x5, 1
    sw   x5, 0(x6)                  /* APP_CTRL: release the App Core */
    csrsi mstatus, 8
    WAIT_NZ x29, 200000
    li   x5, 0x8000000B
    bne  x29, x5, fail
    li   x5, 4
    bne  x25, x5, fail              /* CLAIM = 1 + source 3 */
    li   x5, 0x1235
    bne  x22, x5, fail

    /* ---- PASS ---- */
    csrci mstatus, 8
    li   x5, 1
    sw   x5, 0(x8)
7:  j    7b

fail:
    csrci mstatus, 8
    ori  x5, x31, 0x80
    sw   x5, 0(x8)
8:  j    8b

/* Handler: only interrupts are expected. Clears the source, reads a register back so the line
 * has dropped before MRET, records mcause */
handler:
    csrr x28, mcause
    bgez x28, fail                  /* an exception here is a failure */
    li   x27, 0x80000007
    beq  x28, x27, h_timer
    lw   x25, 8(x18)                /* CLAIM */
    li   x27, 2
    beq  x25, x27, h_gpio
    li   x27, 4
    beq  x25, x27, h_mbox
    j    fail
h_gpio:
    li   x27, 1
    sw   x27, 0xC(x8)               /* GPIO0 IRQ_STAT W1C pin 0 */
    j    h_done
h_mbox:
    lw   x22, 4(x19)                /* IN: reading clears IN_FULL */
    j    h_done
h_timer:
    li   x27, -1
    sw   x27, 0xC(x9)               /* MTIMECMP_HI all ones: the line drops */
h_done:
    lw   x27, 0(x18)                /* read back over the bus: the source has dropped by now */
    bnez x24, 9f
    mv   x23, x28
9:  addi x24, x24, 1
    mv   x29, x28
    mret
