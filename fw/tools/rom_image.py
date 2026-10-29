#!/usr/bin/env python3
"""ROM images for the build (P-16, I-04). Called by fw/CMakeLists.txt after linking.

    rom_image.py pad <app.bin> <app_firmware.hex> <app_firmware.bin>
        Pad the App image to the whole 4 KB App ROM with zero words and write it as a
        $readmemh word file (1024 lines) and as a 4 KB .bin. sha256sum of that .bin is the
        golden hash (I-04), and every ROM word is defined, so simulation sees no X.

    rom_image.py put-golden <firmware_code.hex> <app_firmware.hex> <firmware_imem.hex>
        Hash the App ROM image like golden.py and write the Boot ROM image: the Master code
        plus the 8 golden words at SB_GOLDEN_ADDR (0xFE0, word 1016), as 1024 plain words.
        Fails if the code reaches that slot (linker.ld keeps it free).
"""
import os
import struct
import sys

sys.dont_write_bytecode = True        # no __pycache__ in the source tree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import golden  # noqa: E402  (read_hex and the digest rule live there)

ROM_BYTES = 4096
GOLD_WORD = 0xFE0 // 4


def write_hex(path, words):
    with open(path, "w") as f:
        for w in words:
            f.write("%08x\n" % w)


def pad(bin_in, hex_out, bin_out):
    with open(bin_in, "rb") as f:
        data = f.read()
    if len(data) > ROM_BYTES:
        sys.exit("%s: %d bytes, the App ROM holds %d" % (bin_in, len(data), ROM_BYTES))
    data += b"\0" * (ROM_BYTES - len(data))
    with open(bin_out, "wb") as f:
        f.write(data)
    write_hex(hex_out, struct.unpack("<%dI" % (ROM_BYTES // 4), data))
    print("App ROM image: %d bytes used of %d" % (len(data.rstrip(b"\0")), ROM_BYTES))


def put_golden(code_hex, app_hex, boot_hex):
    boot = golden.read_hex(code_hex)
    if any(boot[GOLD_WORD:]):
        sys.exit("%s: words %d..1023 are not free for the golden hash" % (code_hex, GOLD_WORD))
    image = b"".join(struct.pack("<I", w) for w in golden.read_hex(app_hex))
    digest = golden.hashlib.sha256(image).digest()
    boot[GOLD_WORD:] = struct.unpack("<8I", digest)
    write_hex(boot_hex, boot)
    print("golden %s written at 0xFE0 of %s" % (digest.hex(), os.path.basename(boot_hex)))


def main():
    if len(sys.argv) == 5 and sys.argv[1] == "pad":
        pad(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) == 5 and sys.argv[1] == "put-golden":
        put_golden(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
