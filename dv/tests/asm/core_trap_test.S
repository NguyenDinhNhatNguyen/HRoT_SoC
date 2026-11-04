/*
 * core_trap_test.S -- Self-checking Zicsr and machine-mode trap program for RISCV_Core (P-09)
 *
 * Covers: CSRRW/CSRRS/CSRRC and the immediate forms, a CSR result used by the next instruction,
 * misa/mhartid/mstatus reset values, ECALL, EBREAK, illegal instructions (no side effects),
 * unknown CSR and write to a read-only CSR, MRET restoring mstatus.MIE, timer and external
 * interrupts (mie, mstatus.MIE, mip, MEI before MTI) and an interrupt in the middle of a loop
 * full of loads and stores (no store may run twice), and access faults through data_err (P-24): load
 * (mcause 5) and store (mcause 7) to the testbench's fault window at 0xF000_0000, mtval = address.
 * FENCE, FENCE.I and WFI run as NOPs, reserved encodings trap, ID CSRs, mcause/mtval writes, a pending
 * but disabled external interrupt (P-19, gaps found by coverage).
 *
 * ACC (0x3F4): the testbench counts every finished access to this word and shows the count at
 * ACC_CNT (0x3F0), so a load or store that runs twice, or runs when it should be cancelled, is caught.
 *
 * Result convention as in core_isa_test.S: TOHOST (0x3FC) = 1 -> PASS, (n << 1)|1 -> FAIL at CHECK n.
 * IRQ (0x3F8): the testbench drives irq_timer from bit0 and irq_ext from bit1 of this word, so a
 * line stays high until the trap handler clears its bit (level interrupts, I-01).
 *
 * Registers: x29 counts traps, x26..x28 belong to the trap handler, x30/x31 to CHECK.
 *
 * Rebuild the .hex (needs riscv64-unknown-elf-gcc):
 *   riscv64-unknown-elf-gcc -march=rv32i_zicsr_zifencei -mabi=ilp32 -nostdlib -Ttext=0 \
 *       -o core_trap_test.elf core_trap_test.S
 *   riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=4 -j .text \
 *       core_trap_test.elf core_trap_test.hex
 */
#define TOHOST 0x3FC
#define IRQ    0x3F8
#define ACC    0x3F4
#define ACC_CNT 0x3F0
#define LAST   0x200        /* handler writes mcause, mepc, mstatus, mtval here */
#define LOG    0x220        /* handler appends mcause at LOG + 4 * trap number */
#define CNT    0x180        /* counter of the memory loop */
#define SDST   0x100        /* target of the illegal store */

.macro CHECK reg, val
    addi x31, x31, 1
    li   x30, \val
    bne  \reg, x30, fail
.endm

.macro CHECK_ADDR reg, sym
    addi x31, x31, 1
    la   x30, \sym
    bne  \reg, x30, fail
.endm

    .text
    .globl _start
_start:
    li   x31, 0
    li   x29, 0
    la   x5, trap_handler
    csrw mtvec, x5
    csrr x6, mtvec
    CHECK_ADDR x6, trap_handler

    /* ---- 1. CSR instructions on mscratch ---- */
    li     x5, 0x12345678
    csrrw  x6, mscratch, x5
    CHECK  x6, 0
    csrr   x6, mscratch
    CHECK  x6, 0x12345678
    li     x5, 0xF0
    csrrs  x6, mscratch, x5
    CHECK  x6, 0x12345678
    csrr   x6, mscratch
    CHECK  x6, 0x123456F8
    csrrc  x6, mscratch, x5
    csrr   x6, mscratch
    CHECK  x6, 0x12345608
    csrrwi x6, mscratch, 0x15
    CHECK  x6, 0x12345608
    csrrsi x0, mscratch, 0x2
    csrrci x0, mscratch, 0x5
    csrrs  x6, mscratch, x0         /* read only, no write */
    CHECK  x6, 0x12
    csrr   x7, mscratch             /* result used right away: one-cycle stall */
    addi   x8, x7, 1
    CHECK  x8, 0x13
    addi   x5, x0, 0x55             /* write operand forwarded from the previous instruction */
    csrw   mscratch, x5
    csrr   x6, mscratch
    CHECK  x6, 0x55

    /* ---- 2. Reset values ---- */
    csrr  x6, misa
    CHECK x6, 0x40000100
    csrr  x6, mhartid
    CHECK x6, 0
    csrr  x6, mstatus
    CHECK x6, 0x1800                /* MPP = 11, MIE = MPIE = 0 */
    csrr  x6, mie
    CHECK x6, 0

    /* ---- 3. ECALL and EBREAK ---- */
ecall_at:
    ecall
    CHECK x29, 1
    lw    x6, LAST(x0)
    CHECK x6, 11
    lw    x6, LAST+4(x0)
    CHECK_ADDR x6, ecall_at
ebreak_at:
    ebreak
    CHECK x29, 2
    lw    x6, LAST(x0)
    CHECK x6, 3
    lw    x6, LAST+4(x0)
    CHECK_ADDR x6, ebreak_at

    /* A store right behind a trapping instruction runs once, after the handler, never before it */
    ecall
    sw    x0, ACC(x0)
    lw    x6, ACC_CNT(x0)
    CHECK x6, 1
    CHECK x29, 3

    /* ---- 4. Illegal instructions trap and change nothing ---- */
    li    x7, 0x77
    .word 0x00000000                /* all-zero word */
    .word 0x020003B3                /* mul x7, x0, x0 (no M extension) */
    .word 0x00003383                /* ld x7, 0(x0) (load funct3 = 011) */
    .word 0x10703023                /* sd x7, 0x100(x0) (store funct3 = 011) */
    csrr  x7, 0x7C0                 /* CSR that does not exist */
    csrw  mhartid, x0               /* write to a read-only CSR */
    CHECK x7, 0x77
    CHECK x29, 9
    lw    x6, LAST(x0)
    CHECK x6, 2
    lw    x6, SDST(x0)
    CHECK x6, 0

    /* ---- 5. Trap entry clears MIE into MPIE, MRET restores it ---- */
    csrsi mstatus, 8
    ecall
    lw    x6, LAST+8(x0)            /* mstatus seen by the handler */
    CHECK x6, 0x1880
    csrr  x6, mstatus
    CHECK x6, 0x1888
    csrci mstatus, 8

    /* ---- 6. Interrupts ---- */
    li    x5, 1
    sw    x5, IRQ(x0)               /* timer line high, but nothing enabled */
    nop
    nop
    nop
    CHECK x29, 10
    csrr  x6, mip
    CHECK x6, 0x80                  /* mip.MTIP */
    li    x5, 0x80
    csrw  mie, x5                   /* MTIE on, mstatus.MIE still off */
    nop
    nop
    nop
    CHECK x29, 10
    csrsi mstatus, 8                /* now the interrupt must be taken, but not on the load below */
    lw    x12, ACC(x0)
    nop
    nop
    nop
    nop
    CHECK x29, 11
    lw    x6, ACC_CNT(x0)
    CHECK x6, 2                     /* the load ran exactly once */
    lw    x6, LAST(x0)
    CHECK x6, 0x80000007
    lw    x6, IRQ(x0)
    CHECK x6, 0                     /* the handler cleared the line */

    li    x5, 0x880
    csrw  mie, x5                   /* MTIE and MEIE */
    li    x5, 3
    sw    x5, IRQ(x0)               /* both lines at once: MEI goes first */
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    CHECK x29, 13
    lw    x6, LOG+44(x0)            /* trap number 11 */
    CHECK x6, 0x8000000B
    lw    x6, LOG+48(x0)            /* trap number 12 */
    CHECK x6, 0x80000007

    /* Interrupt raised in the middle of a loop of loads and stores: every store runs exactly once */
    sw    x0, CNT(x0)
    li    x7, 20
    li    x9, 10
    li    x10, 1
mem_loop:
    lw    x8, CNT(x0)
    addi  x8, x8, 1
    sw    x8, CNT(x0)
    lw    x11, CNT(x0)
    sw    x11, CNT+4(x0)
    bne   x7, x9, 1f
    sw    x10, IRQ(x0)              /* raise the timer line at iteration 10 */
1:  addi  x7, x7, -1
    bnez  x7, mem_loop
    nop
    nop
    CHECK x29, 14
    lw    x6, CNT(x0)
    CHECK x6, 20
    lw    x6, CNT+4(x0)
    CHECK x6, 20
    csrci mstatus, 8
    csrw  mie, x0

    /* ---- 7. Access faults (P-24): the testbench gives data_err for any access at 0xF000_0000 and up ---- */
    li    x12, 0x5A
    li    x5, 0xF0000010
fault_ld:
    lw    x12, 0(x5)                /* load access fault: no register write */
    CHECK x29, 15
    CHECK x12, 0x5A
    lw    x6, LAST(x0)
    CHECK x6, 5
    lw    x6, LAST+4(x0)
    CHECK_ADDR x6, fault_ld
    lw    x6, LAST+12(x0)
    CHECK x6, 0xF0000010            /* mtval = the data address */
fault_st:
    sb    x12, 9(x5)                /* store access fault, byte store */
    CHECK x29, 16
    lw    x6, LAST(x0)
    CHECK x6, 7
    lw    x6, LAST+4(x0)
    CHECK_ADDR x6, fault_st
    lw    x6, LAST+12(x0)
    CHECK x6, 0xF0000019
    lw    x6, 0x018(x0)             /* the word 0xF000_0018 aliases in the testbench RAM: untouched */
    CHECK x6, 0
    lw    x13, 0x010(x0)            /* the next access works normally */
    addi  x13, x13, 1
    CHECK x13, 1
    ecall                           /* mtval is 0 for every other trap */
    CHECK x29, 17
    lw    x6, LAST+12(x0)
    CHECK x6, 0

    /* ---- 8. FENCE, FENCE.I and WFI run as NOPs (P-19): no trap, no register change, a store before them
       is seen by a load after them ---- */
    li    x13, 0x77
    sw    x13, 0x014(x0)
    fence
    fence.i
    wfi
    lw    x14, 0x014(x0)
    CHECK x14, 0x77
    CHECK x13, 0x77
    CHECK x29, 17

    /* ---- 9. Gaps found by the coverage of P-19 ---- */
    /* 9a. Reserved encodings must trap as illegal (mcause 2) with no side effect: a branch must not
       jump (it would skip the addi after it), JALR must not jump or write x16, the others must not
       write x17 or memory */
    li    x15, 0
    li    x16, 0x16
    li    x17, 0x17
    .word 0x00002463              /* branch, funct3 010, offset +8 */
    addi  x15, x15, 1
    .word 0x00003463              /* branch, funct3 011, offset +8 */
    addi  x15, x15, 1
    .word 0x00001867              /* jalr x16, 0(x0) with funct3 001 */
    .word 0x022088B3              /* mul x17, x1, x2 (funct7 0000001, no M extension) */
    .word 0x402098B3              /* sll x17 with funct7 0100000 */
    .word 0x40309893              /* slli x17 with funct7 0100000 */
    .word 0x0230D893              /* srli x17 with funct7 0000001 */
    .word 0x00003883              /* ld x17 (load funct3 011) */
    .word 0x00103023              /* sd x1 (store funct3 011) */
    .word 0x0000200F              /* fence with funct3 010 */
    .word 0x300048F3              /* SYSTEM funct3 100 */
    .word 0x00200073              /* uret: SYSTEM funct3 000 that is not ECALL/EBREAK/MRET/WFI */
    .word 0x10200073              /* sret */
    CHECK x15, 2
    CHECK x16, 0x16
    CHECK x17, 0x17
    CHECK x29, 30
    lw    x6, LAST(x0)
    CHECK x6, 2
    /* 9b. The other ID CSRs read 0, mcause and mtval are writable, misa and mip ignore writes */
    csrr  x6, mvendorid
    CHECK x6, 0
    csrr  x6, marchid
    CHECK x6, 0
    csrr  x6, mimpid
    CHECK x6, 0
    li    x7, 0x1234
    csrw  mcause, x7
    csrr  x6, mcause
    CHECK x6, 0x1234
    li    x7, 0xABCD
    csrw  mtval, x7
    csrr  x6, mtval
    CHECK x6, 0xABCD
    csrr  x8, misa
    csrw  misa, x0
    csrr  x6, misa
    sub   x6, x6, x8
    CHECK x6, 0
    csrw  mip, x7
    csrr  x6, mip
    CHECK x6, 0
    CHECK x29, 30
    /* 9c. irq_ext high while mie.MEIE = 0 and mstatus.MIE = 1: pending in mip, but no trap */
    csrw  mie, x0
    csrsi mstatus, 8
    li    x6, 2
    sw    x6, IRQ(x0)
    nop
    nop
    nop
    csrr  x7, mip
    CHECK x7, 0x800
    CHECK x29, 30
    sw    x0, IRQ(x0)
    csrci mstatus, 8

    /* ---- PASS ---- */
    li   x5, 1
    sw   x5, TOHOST(x0)
2:  j    2b

fail:
    slli x30, x31, 1
    ori  x30, x30, 1
    sw   x30, TOHOST(x0)
3:  j    3b

/* Trap handler: logs the trap, skips a synchronous trap, clears the line of an interrupt */
trap_handler:
    csrr x26, mcause
    sw   x26, LAST(x0)
    csrr x27, mepc
    sw   x27, LAST+4(x0)
    csrr x28, mstatus
    sw   x28, LAST+8(x0)
    csrr x28, mtval
    sw   x28, LAST+12(x0)
    slli x27, x29, 2
    sw   x26, LOG(x27)
    addi x29, x29, 1
    blt  x26, x0, irq_entry         /* mcause bit 31 = interrupt */
    csrr x27, mepc
    addi x27, x27, 4
    csrw mepc, x27
    mret
irq_entry:
    lw   x27, IRQ(x0)
    andi x28, x26, 8                /* cause 11 (external) has bit 3 set, cause 7 (timer) does not */
    beqz x28, 4f
    andi x27, x27, -3               /* clear bit1, irq_ext */
    j    5f
4:  andi x27, x27, -2               /* clear bit0, irq_timer */
5:  sw   x27, IRQ(x0)
    mret
