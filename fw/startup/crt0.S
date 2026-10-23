/* ============================================================================
 * crt0.S -- Khởi động Master Core: đặt stack, xóa .bss, gọi main().
 * .rodata/.data đã được nạp sẵn vào RAM (xem linker.ld), không cần copy.
 * main() trả về thì dừng tại vòng lặp vô hạn.
 * ========================================================================== */
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
