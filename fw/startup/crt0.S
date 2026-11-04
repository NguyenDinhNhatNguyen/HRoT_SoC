/*
 * crt0.S -- start-up of the Master Core and the App Core (P-16): set the stack, clear .bss, call main().
 * Master: .rodata sits in the Boot ROM and .data is preloaded into RAM (linker.ld). App: no .rodata
 * or .data at all (app/app.ld). Either way there is nothing to copy.
 * If main() returns, stop in an endless loop.
 * Traps (P-24): mtvec points at trap_entry, which starts a fresh stack and calls
 * trap_handler(mcause, mepc, mtval). trap_handler is weak: a firmware without one (the App demo)
 * just stops there. The Master's handler (secure_boot/main.c) locks the App out.
 */
    .section .text.start, "ax"
    .globl _start
_start:
    la   sp, __stack_top
    .option push
    .option arch, +zicsr
    la   t0, trap_entry
    csrw mtvec, t0
    .option pop

    la   t0, __bss_start
    la   t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b

2:  call main
3:  j    3b

    .section .text.trap, "ax"
    .balign 4                       /* mtvec direct mode needs a word-aligned base */
trap_entry:
    la   sp, __stack_top            /* the trap may come with a broken stack: start a new one */
    .option push
    .option arch, +zicsr
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    .option pop
    call trap_handler
4:  j    4b

    .weak trap_handler
trap_handler:
5:  j    5b
