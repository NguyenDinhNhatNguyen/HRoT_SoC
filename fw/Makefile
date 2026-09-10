CC = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy

# Ep dich ra RISC-V 32-bit, ABI ILP32, toi uu hoa code, khong dung thu vien tieu chuan
CFLAGS = -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib

SRCS = main.c
TARGET = firmware

all: $(TARGET).txt

$(TARGET).elf: $(SRCS)
	$(CC) $(CFLAGS) -o $@ $^

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# Dich Bin thanh Hex van ban de Verilog doc vao ROM
$(TARGET).txt: $(TARGET).bin
	hexdump -v -e '1/4 "%08x\n"' $< > $@

clean:
	rm -f *.elf *.bin *.txt