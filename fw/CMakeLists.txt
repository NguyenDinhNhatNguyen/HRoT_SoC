cmake_minimum_required(VERSION 3.15)
project(HRoT_Firmware C ASM)

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv)

set(TOOLCHAIN_PREFIX "riscv64-unknown-elf-")
set(CMAKE_C_COMPILER "${TOOLCHAIN_PREFIX}gcc")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_PREFIX}gcc")
set(OBJCOPY "${TOOLCHAIN_PREFIX}objcopy")
set(OBJDUMP "${TOOLCHAIN_PREFIX}objdump")

set(RISCV_FLAGS "-march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${RISCV_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_ASM_FLAGS "${CMAKE_ASM_FLAGS} ${RISCV_FLAGS}" CACHE STRING "" FORCE)

# Target cho Master Core
set(SECURE_BOOT_SRC 
    secure_boot/main.c
)
add_executable(secure_boot.elf ${SECURE_BOOT_SRC})

# Ép Linker Script (Bỏ comment dòng dưới nếu bạn có file linker.ld định tuyến bộ nhớ)
# target_link_options(secure_boot.elf PRIVATE -T ${CMAKE_CURRENT_SOURCE_DIR}/linker.ld)

# Xuất file mã máy
add_custom_command(TARGET secure_boot.elf POST_BUILD
    # Create file Binary
    COMMAND ${OBJCOPY} -O binary $<TARGET_FILE:secure_boot.elf> ${CMAKE_CURRENT_BINARY_DIR}/firmware.bin
    # Create file Hex dang Verilog (dùng cho mô phỏng hoặc nạp vào FPGA) để readmemh trong Testbench/Vivado
    COMMAND ${OBJCOPY} -O verilog $<TARGET_FILE:secure_boot.elf> ${CMAKE_CURRENT_BINARY_DIR}/firmware.txt
    # Create file Disassembly để debug Assembly 
    COMMAND ${OBJDUMP} -d $<TARGET_FILE:secure_boot.elf> > ${CMAKE_CURRENT_BINARY_DIR}/firmware.dis
    COMMENT "Đang trích xuất firmware.bin, firmware.txt và firmware.dis..."
)