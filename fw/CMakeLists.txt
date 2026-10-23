cmake_minimum_required(VERSION 3.15)

# Toolchain phải đặt TRƯỚC project(), nếu không CMake dò compiler của host
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv)

set(TOOLCHAIN_PREFIX "riscv64-unknown-elf-" CACHE STRING "Tiền tố toolchain RISC-V")
set(CMAKE_C_COMPILER   "${TOOLCHAIN_PREFIX}gcc")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_PREFIX}gcc")
# Không có libc/crt mặc định: chỉ thử biên dịch thư viện tĩnh khi dò compiler
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

project(HRoT_Firmware C ASM)

set(OBJCOPY "${TOOLCHAIN_PREFIX}objcopy")
set(OBJDUMP "${TOOLCHAIN_PREFIX}objdump")

set(LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/linker.ld)
set(RAM_BASE 0x10000000)   # phải khớp ORIGIN của RAM trong linker.ld

add_compile_options(-march=rv32i -mabi=ilp32 -O2 -ffreestanding
                    -fno-tree-loop-distribute-patterns
                    -ffunction-sections -fdata-sections -Wall -Wextra)
add_link_options(-march=rv32i -mabi=ilp32 -nostdlib -nostartfiles
                 -T ${LINKER_SCRIPT} -Wl,--gc-sections)

# HAL SHA-256: thư viện tĩnh dùng chung cho firmware Master Core
add_library(hal_sha256 STATIC hal/sha256_hal.c)
target_include_directories(hal_sha256 PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/hal)

# Firmware Secure Boot (Master Core)
add_executable(secure_boot.elf
    startup/crt0.S
    secure_boot/main.c
)
# libgcc cung cấp __mulsi3/__divsi3... nếu code C có nhân/chia (rv32i không có M)
target_link_libraries(secure_boot.elf PRIVATE hal_sha256 gcc)
target_link_options(secure_boot.elf PRIVATE -Wl,-Map=${CMAKE_CURRENT_BINARY_DIR}/firmware.map)
set_target_properties(secure_boot.elf PROPERTIES LINK_DEPENDS ${LINKER_SCRIPT})

# Xuất file cho mô phỏng / FPGA ($readmemh vào mảng word 32-bit):
#   firmware_imem.hex : .text, word 0 = địa chỉ 0x0
#   firmware_dmem.hex : .rodata/.data, word 0 = địa chỉ RAM_BASE
add_custom_command(TARGET secure_boot.elf POST_BUILD
    COMMAND ${OBJCOPY} -O binary -j .text $<TARGET_FILE:secure_boot.elf> ${CMAKE_CURRENT_BINARY_DIR}/firmware.bin
    COMMAND ${OBJCOPY} -O verilog --verilog-data-width=4 -j .text
            $<TARGET_FILE:secure_boot.elf> ${CMAKE_CURRENT_BINARY_DIR}/firmware_imem.hex
    COMMAND ${OBJCOPY} -O verilog --verilog-data-width=4 -j .rodata -j .data
            --change-addresses=-${RAM_BASE}
            $<TARGET_FILE:secure_boot.elf> ${CMAKE_CURRENT_BINARY_DIR}/firmware_dmem.hex
    COMMAND ${OBJDUMP} -d $<TARGET_FILE:secure_boot.elf> > ${CMAKE_CURRENT_BINARY_DIR}/firmware.dis
    COMMENT "Đang xuất firmware.bin, firmware_imem.hex, firmware_dmem.hex và firmware.dis..."
)
