/*
 * crt0.S -- Master Core start-up: set the stack, clear .bss, call main().
 * .rodata sits in the Boot ROM and .data is preloaded into RAM (see linker.ld), no copy needed.
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
