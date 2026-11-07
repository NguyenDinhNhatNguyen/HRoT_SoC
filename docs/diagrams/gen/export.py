"""Rebuild docs/diagrams/HRoT_SoC_Diagrams.drawio and the PNG of every page.

Run from docs/diagrams/gen:   python export.py
Needs draw.io Desktop (path below) for the PNG export. Pass --no-png to write only the .drawio file.
"""
import importlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dlib import write  # noqa: E402

DRAWIO = os.environ.get("DRAWIO", "C:/Program Files/draw.io/draw.io.exe")
REGISTRY = [
    ("pg_arch1", "overview"), ("pg_arch2", "memory_map"), ("pg_arch1", "bus_fabric"), ("pg_arch2", "master_core"),
    ("pg_arch2", "dma_sha"), ("pg_arch3", "boot_verifier"), ("pg_arch3", "syscsr"), ("pg_arch3", "peripherals"),
    ("pg_arch3", "app_world"), ("pg_arch3", "security_arch"),
    ("pg_flow1", "secure_boot_flow"), ("pg_flow2", "tamper_flow"), ("pg_flow2", "check_fsm"), ("pg_flow3", "dma_fsm"),
    ("pg_flow2", "bus_flow"), ("pg_flow2", "irq_flow"), ("pg_flow2", "reset_flow"), ("pg_flow3", "verif_flow"),
    ("pg_arch4", "pmod_j2"), ("pg_arch4", "vp_arch"), ("pg_arch4", "fpga_testbed"),
]

pages = [getattr(importlib.import_module(m), f)() for m, f in REGISTRY]
out = os.path.dirname(HERE)
drawio = os.path.join(out, "HRoT_SoC_Diagrams.drawio")
write(pages, drawio)
print("wrote", drawio, len(pages), "pages")
if "--no-png" not in sys.argv:
    os.makedirs(os.path.join(out, "png"), exist_ok=True)
    for i, p in enumerate(pages, 1):
        slug = re.sub(r"[^a-z0-9]+", "_", p.name.lower()).strip("_")
        dst = os.path.join(out, "png", slug + ".png")
        subprocess.run([DRAWIO, "-x", "-f", "png", "-s", "2", "-b", "20", "-p", str(i), "-o", dst, drawio],
                       capture_output=True, timeout=240)
        print(i, slug)
