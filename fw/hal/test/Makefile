# Firmware unit tests on the host (WSL2/Linux): SHA-256 HAL, UART/GPIO/Mailbox drivers (P-11, P-16),
# Secure Boot (P-13, P-15, P-16), ROM image and golden step (rom_image_test.py, P-16).
# No RISC-V toolchain needed except for the rv32 target.
HAL   := ..
CFLAGS := -std=c11 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
          -I$(HAL) -I. -DHAL_HOST_MODEL
SRC   := hal_host_test.c sha256_mock.c sha256_ref.c $(HAL)/sha256_hal.c

hal_host_test: $(SRC) $(wildcard *.h) $(HAL)/sha256_hal.h $(HAL)/sha256_regs.h
	$(CC) $(CFLAGS) $(SRC) -o $@

DRV_SRC := drv_host_test.c drv_mock.c $(HAL)/uart.c $(HAL)/gpio.c $(HAL)/mailbox.c

drv_host_test: $(DRV_SRC) drv_mock.h $(HAL)/uart.h $(HAL)/gpio.h $(HAL)/mailbox.h $(HAL)/hal_io.h $(HAL)/soc_map.h
	$(CC) $(CFLAGS) $(DRV_SRC) -o $@

SB_SRC := sb_host_test.c sb_mock.c sha256_mock.c sha256_ref.c $(HAL)/sha256_hal.c $(HAL)/uart.c $(HAL)/gpio.c $(HAL)/dma.c $(HAL)/mailbox.c \
          ../../secure_boot/secure_boot.c

sb_host_test: $(SB_SRC) sb_mock.h sha256_mock.h $(HAL)/uart.h $(HAL)/gpio.h $(HAL)/dma.h $(HAL)/hal_io.h $(HAL)/soc_map.h \
              ../../secure_boot/secure_boot.h
	$(CC) $(CFLAGS) -I../../secure_boot -DSHA256_MOCK_NO_MEMREAD $(SB_SRC) -o $@

# The driver, Secure Boot and ROM image tests run first: if one fails, make stops before hal_host_test prints
# the "==== PASSED" line that sim/regress.sh looks for
test: drv_host_test sb_host_test hal_host_test
	./drv_host_test
	./sb_host_test
	python3 rom_image_test.py
	./hal_host_test

# Independent cross-check against sha256sum on the edge lengths
crosscheck: hal_host_test
	@fail=0; for n in 0 1 55 56 57 63 64 65 119 120 128 1000 4096 100003; do \
	  head -c $$n /dev/urandom > /tmp/hal_xc.bin; \
	  a=$$(./hal_host_test --file /tmp/hal_xc.bin); b=$$(sha256sum /tmp/hal_xc.bin | cut -d' ' -f1); \
	  if [ "$$a" = "$$b" ]; then echo "OK   len=$$n"; else echo "FAIL len=$$n"; fail=1; fi; done; \
	  rm -f /tmp/hal_xc.bin; exit $$fail

# Check the HAL and the drivers build for RV32I and pull in no libc/libgcc
RV32_OBJ := /tmp/sha256_hal_rv32.o /tmp/uart_rv32.o /tmp/gpio_rv32.o /tmp/dma_rv32.o /tmp/mailbox_rv32.o
rv32:
	@for m in sha256_hal uart gpio dma mailbox; do \
	  riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib \
	    -fno-tree-loop-distribute-patterns -Wall -Wextra -Werror -c $(HAL)/$$m.c -o /tmp/$${m}_rv32.o || exit 1; \
	done
	@riscv64-unknown-elf-nm -u $(RV32_OBJ) | grep -v ':$$' | grep . && { echo "FAIL: undefined symbols"; exit 1; } || echo "OK: no undefined symbols"
	@riscv64-unknown-elf-size $(RV32_OBJ)

clean:
	rm -f hal_host_test drv_host_test sb_host_test $(RV32_OBJ)
.PHONY: test crosscheck rv32 clean
