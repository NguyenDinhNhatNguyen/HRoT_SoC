#!/usr/bin/env python3
"""Host test of fw/tools/rom_image.py (P-16, I-04): the padded App image (APP_VER in the last word)
and the golden hash written into the Boot ROM image (big-endian words H0..H7, I-03) must match
sha256sum of the 4 KB .bin. Prints "ROM RESULT: PASS|FAIL"."""
import hashlib
import os
import random
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "..", "tools", "rom_image.py")
fails = 0
passes = 0


def check(cond, msg):
    global fails, passes
    if cond:
        passes += 1
    else:
        fails += 1
        print("  FAIL " + msg)


def run(*args):
    return subprocess.run([sys.executable, TOOL] + list(args), capture_output=True, text=True)


def words(path):
    with open(path) as f:
        return [int(x, 16) for x in f.read().split()]


with tempfile.TemporaryDirectory() as d:
    p = lambda name: os.path.join(d, name)
    rng = random.Random(16)
    for n, ver in ((4, None), (510, 7), (4092, 0x10203)):
        print("[R1] pad %d bytes, APP_VER %s" % (n, ver))
        app = bytes(rng.randrange(256) for _ in range(n))
        with open(p("app.bin"), "wb") as f:
            f.write(app)
        args = ["pad", p("app.bin"), p("app.hex"), p("app_full.bin")] + ([str(ver)] if ver is not None else [])
        check(run(*args).returncode == 0, "pad failed")
        full = open(p("app_full.bin"), "rb").read()
        check(full == app + b"\0" * (4092 - n) + struct.pack("<I", 1 if ver is None else ver),
              "padded .bin differs (APP_VER must be the last word)")
        check(words(p("app.hex")) == list(struct.unpack("<1024I", full)), "hex is not the .bin as LE words")

        print("[R2] golden into the Boot ROM image")
        code = [rng.randrange(1 << 32) for _ in range(300)]
        with open(p("code.hex"), "w") as f:
            f.write("@00000000\n" + " ".join("%08X" % w for w in code) + "\n")
        check(run("put-golden", p("code.hex"), p("app.hex"), p("imem.hex")).returncode == 0, "put-golden failed")
        boot = words(p("imem.hex"))
        digest = hashlib.sha256(full).digest()
        check(len(boot) == 1024 and boot[:300] == code and not any(boot[300:1016]), "code or tag area changed")
        check(struct.pack(">8I", *boot[1016:]) == digest, "golden at 0xFE0 is not sha256 of the .bin as BE words")

    print("[R3] errors")
    with open(p("big.bin"), "wb") as f:
        f.write(b"\1" * 4093)
    check(run("pad", p("big.bin"), p("x.hex"), p("x.bin")).returncode != 0, "App image over the APP_VER word accepted")
    with open(p("long.hex"), "w") as f:
        f.write("@000003f0\n00000001\n")
    check(run("put-golden", p("long.hex"), p("app.hex"), p("y.hex")).returncode != 0, "code over the HMAC tag slot accepted")

print("\nSUMMARY ROM: PASS = %d | FAIL = %d" % (passes, fails))
print("ROM RESULT: %s" % ("FAIL" if fails else "PASS"))
sys.exit(1 if fails else 0)
