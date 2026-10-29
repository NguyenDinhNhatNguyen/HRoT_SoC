cmake_minimum_required(VERSION 3.15)

# The toolchain must be set BEFORE project(), otherwise CMake probes the host compiler
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv)

set(TOOLCHAIN_PREFIX "riscv64-unknown-elf-" CACHE STRING "RISC-V toolchain prefix")
set(CMAKE_C_COMPILER   "${TOOLCHAIN_PREFIX}gcc")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_PREFIX}gcc")
# No default libc/crt: only try-compile a static library when probing the compiler
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

project(HRoT_Firmware C ASM)

set(OBJCOPY "${TOOLCHAIN_PREFIX}objcopy")
set(OBJDUMP "${TOOLCHAIN_PREFIX}objdump")

set(LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/linker.ld)
set(RAM_BASE 0x10000000)   # must match the RAM ORIGIN in linker.ld

add_compile_options(-march=rv32i -mabi=ilp32 -Os -ffreestanding
                    -fno-tree-loop-distribute-patterns
                    -ffunction-sections -fdata-sections -Wall -Wextra)
add_link_options(-march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -Wl,--gc-sections)

# rom_image.py pads the App image and writes the golden hash into the Boot ROM image (I-04)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(ROM_IMAGE ${CMAKE_CURRENT_SOURCE_DIR}/tools/rom_image.py)

# SHA-256 HAL: static library shared by the Master Core firmware
add_library(hal_sha256 STATIC hal/sha256_hal.c)
target_include_directories(hal_sha256 PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/hal)

# UART and GPIO drivers (P-11): static library, works for the Secure and the App world blocks.
# Secure DMA driver (P-15): Secure world only. Mailbox driver (P-16): both worlds
add_library(hal_drivers STATIC hal/uart.c hal/gpio.c hal/dma.c hal/mailbox.c)
target_include_directories(hal_drivers PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/hal)

# Firmware Secure Boot (Master Core)
add_executable(secure_boot.elf
    startup/crt0.S
    secure_boot/main.c
    secure_boot/secure_boot.c
)
target_include_directories(secure_boot.elf PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/secure_boot)
# libgcc provides __mulsi3/__divsi3... when C code multiplies or divides (rv32i has no M)
target_link_libraries(secure_boot.elf PRIVATE hal_sha256 hal_drivers gcc)
target_link_options(secure_boot.elf PRIVATE -T ${LINKER_SCRIPT} -Wl,-Map=${CMAKE_CURRENT_BINARY_DIR}/firmware.map)
set_target_properties(secure_boot.elf PROPERTIES LINK_DEPENDS ${LINKER_SCRIPT})

# Output files for simulation / FPGA ($readmemh into a 32-bit word array):
#   firmware.bin      : .text and .rodata (the Boot ROM image without the golden hash)
#   firmware_code.hex : .text and .rodata, word 0 = address 0x0 (input of the golden step below)
#   firmware_imem.hex : the Boot ROM image, firmware_code.hex plus the golden hash of
#                       app_firmware.hex at 0xFE0 (target golden, P-16)
#   firmware_dmem.hex : .data, word 0 = address RAM_BASE (one zero word if .data is empty, so
#                       $readmemh and the FPGA tools always get a non-empty file)
add_custom_command(TARGET secure_boot.elf POST_BUILD
    COMMAND ${OBJCOPY} -O binary -j .text -j .rodata $<TARGET_FILE:secure_boot.elf> ${CMAKE_CURRENT_BINARY_DIR}/firmware.bin
    COMMAND ${OBJCOPY} -O verilog --verilog-data-width=4 -j .text -j .rodata
            $<TARGET_FILE:secure_boot.elf> ${CMAKE_CURRENT_BINARY_DIR}/firmware_code.hex
    COMMAND ${OBJCOPY} -O verilog --verilog-data-width=4 -j .data
            --change-addresses=-${RAM_BASE}
            $<TARGET_FILE:secure_boot.elf> ${CMAKE_CURRENT_BINARY_DIR}/firmware_dmem.hex
    COMMAND ${CMAKE_COMMAND} -DFILE=${CMAKE_CURRENT_BINARY_DIR}/firmware_dmem.hex -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/nonempty_hex.cmake
    COMMAND ${OBJDUMP} -d $<TARGET_FILE:secure_boot.elf> > ${CMAKE_CURRENT_BINARY_DIR}/firmware.dis
    COMMENT "Writing firmware.bin, firmware_code.hex, firmware_dmem.hex and firmware.dis..."
)

# App Core demo firmware (P-16). Text only: the App Core cannot read its ROM as data and its RAM
# is not preloaded, app/app.ld stops the build on any .rodata or .data.
#   app_firmware.bin : the whole 4 KB App ROM, zero padded. sha256sum of it = golden hash (I-04)
#   app_firmware.hex : the same 1024 words for $readmemh (APP_HEX of SoC_Top)
set(APP_LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/app/app.ld)
add_executable(app_firmware.elf
    startup/crt0.S
    app/main.c
)
target_include_directories(app_firmware.elf PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/app)
target_link_libraries(app_firmware.elf PRIVATE hal_drivers gcc)
target_link_options(app_firmware.elf PRIVATE -T ${APP_LINKER_SCRIPT} -Wl,-Map=${CMAKE_CURRENT_BINARY_DIR}/app_firmware.map)
set_target_properties(app_firmware.elf PROPERTIES LINK_DEPENDS ${APP_LINKER_SCRIPT})
add_custom_command(TARGET app_firmware.elf POST_BUILD
    COMMAND ${OBJCOPY} -O binary -j .text $<TARGET_FILE:app_firmware.elf> ${CMAKE_CURRENT_BINARY_DIR}/app_text.bin
    COMMAND ${Python3_EXECUTABLE} ${ROM_IMAGE} pad ${CMAKE_CURRENT_BINARY_DIR}/app_text.bin
            ${CMAKE_CURRENT_BINARY_DIR}/app_firmware.hex ${CMAKE_CURRENT_BINARY_DIR}/app_firmware.bin
    COMMAND ${OBJDUMP} -d $<TARGET_FILE:app_firmware.elf> > ${CMAKE_CURRENT_BINARY_DIR}/app_firmware.dis
    COMMENT "Writing app_firmware.bin, app_firmware.hex and app_firmware.dis..."
)

# Golden hash step (I-04): Boot ROM image = Master code + sha256 of the padded App ROM at 0xFE0.
# Runs on every build, so the golden always matches the App image built with it.
add_custom_target(golden ALL
    COMMAND ${Python3_EXECUTABLE} ${ROM_IMAGE} put-golden ${CMAKE_CURRENT_BINARY_DIR}/firmware_code.hex
            ${CMAKE_CURRENT_BINARY_DIR}/app_firmware.hex ${CMAKE_CURRENT_BINARY_DIR}/firmware_imem.hex
    DEPENDS secure_boot.elf app_firmware.elf ${ROM_IMAGE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/golden.py
    COMMENT "Writing firmware_imem.hex with the golden hash of app_firmware.hex..."
)
