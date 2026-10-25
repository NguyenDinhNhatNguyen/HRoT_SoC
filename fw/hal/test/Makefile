# SHA-256 HAL unit test on the host (WSL2/Linux). No RISC-V toolchain needed.
HAL   := ..
CFLAGS := -std=c11 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
          -I$(HAL) -I. -DHAL_HOST_MODEL
SRC   := hal_host_test.c sha256_mock.c sha256_ref.c $(HAL)/sha256_hal.c

hal_host_test: $(SRC) $(wildcard *.h) $(HAL)/sha256_hal.h $(HAL)/sha256_regs.h
	$(CC) $(CFLAGS) $(SRC) -o $@

test: hal_host_test
	./hal_host_test

# Independent cross-check against sha256sum on the edge lengths
crosscheck: hal_host_test
	@fail=0; for n in 0 1 55 56 57 63 64 65 119 120 128 1000 4096 100003; do \
	  head -c $$n /dev/urandom > /tmp/hal_xc.bin; \
	  a=$$(./hal_host_test --file /tmp/hal_xc.bin); b=$$(sha256sum /tmp/hal_xc.bin | cut -d' ' -f1); \
	  if [ "$$a" = "$$b" ]; then echo "OK   len=$$n"; else echo "FAIL len=$$n"; fail=1; fi; done; \
	  rm -f /tmp/hal_xc.bin; exit $$fail

# Check the HAL builds for RV32I and pulls in no libc/libgcc
rv32:
	riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib \
	  -fno-tree-loop-distribute-patterns -Wall -Wextra -Werror -c $(HAL)/sha256_hal.c -o /tmp/sha256_hal_rv32.o
	@riscv64-unknown-elf-nm -u /tmp/sha256_hal_rv32.o | grep . && { echo "FAIL: undefined symbols"; exit 1; } || echo "OK: no undefined symbols"
	@riscv64-unknown-elf-size /tmp/sha256_hal_rv32.o

clean:
	rm -f hal_host_test /tmp/sha256_hal_rv32.o
.PHONY: test crosscheck rv32 clean
