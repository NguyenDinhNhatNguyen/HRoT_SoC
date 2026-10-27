#!/usr/bin/env python3
"""Golden hash of an App ROM image for the Secure Boot firmware (P-13).

    golden.py <app.hex> <golden.hex>

app.hex    : $readmemh word file of the App ROM (one 32-bit word per line, '@' markers allowed)
golden.hex : 8 words for the Boot ROM slot at SB_GOLDEN_ADDR (0xFE0), word 0 first

The digest is SHA-256 over the whole 4 KB ROM as the core sees it (little-endian words, unused
words zero), i.e. sha256sum of the image as a .bin (I-04). Its bytes are stored in digest order,
so each output word is the little-endian packing of 4 digest bytes.
"""
import hashlib
import struct
import sys

ROM_WORDS = 1024


def read_hex(path):
    words = [0] * ROM_WORDS
    addr = 0
    with open(path) as f:
        for line in f:
            for tok in line.split("//")[0].split():
                if tok.startswith("@"):
                    addr = int(tok[1:], 16)
                    continue
                if addr >= ROM_WORDS:
                    sys.exit("%s: word %d is outside the 4 KB App ROM" % (path, addr))
                words[addr] = int(tok, 16)
                addr += 1
    return words


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    image = b"".join(struct.pack("<I", w) for w in read_hex(sys.argv[1]))
    digest = hashlib.sha256(image).digest()
    with open(sys.argv[2], "w") as f:
        for w in struct.unpack("<8I", digest):
            f.write("%08x\n" % w)
    print("golden %s" % digest.hex())


if __name__ == "__main__":
    main()
