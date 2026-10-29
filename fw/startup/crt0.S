/*
 * crt0.S -- start-up of the Master Core and the App Core (P-16): set the stack, clear .bss, call main().
 * Master: .rodata sits in the Boot ROM and .data is preloaded into RAM (linker.ld). App: no .rodata
 * or .data at all (app/app.ld). Either way there is nothing to copy.
 * If main() returns, stop in an endless loop.
 */
    .section .text.start, "ax"
    .globl _start
_start:
    la   sp, __stack_top

    la   t0, __bss_start
    la   t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b

2:  call main
3:  j    3b
