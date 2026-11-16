#!/usr/bin/env bash
# run.sh - gate-level simulation of the Genus netlist of ASIC_Top with Xcelium (P-20).
# Run from the repo root on the school server: make asic-gls (after make asic-genus)
# The testbench is dv/tb/ASIC_Top_tb.sv built with +define+GLS, the same 8 checks as in make test.
# Zero delay (no SDF): it checks the function of the netlist and backs up LEC.
#   NETLIST   netlist (default asic/out_genus/ASIC_Top_netlist.v)
#   GLS_LIB   Verilog model of the cells (default ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v)
#   HEX_DIR   firmware images from make fw (default fw/build): firmware_imem.hex, firmware_dmem.hex,
#             app_firmware.hex. The server has no RISC-V toolchain, so build them at home and copy
#             the three files into fw/build on the server (MobaXterm SFTP)
# The four memories are black boxes in the netlist. Here they are the RTL models of rtl/mem.
# Genus may write them under a longer module name (parameters in the name), so this script writes
# one small wrapper per memory module name it finds in the netlist (asic/out_gls/mem_shim.v). If the
# netlist keeps the plain names without parameters, the image names are set with defparam instead.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root" || exit 1
netlist=${NETLIST:-asic/out_genus/ASIC_Top_netlist.v}
lib=${GLS_LIB:-${PDK_DIR:-$HOME/PDK_GPDK45}/lib/slow_vdd1v0_basiccells.v}
hex=${HEX_DIR:-fw/build}
out=asic/out_gls
xrun=${XRUN:-xrun}

command -v "$xrun" > /dev/null || { echo "ERROR: $xrun not found, asic-gls runs on the school server"; exit 1; }
[ -f "$netlist" ] || { echo "ERROR: no netlist $netlist, run make asic-genus first"; exit 1; }
[ -f "$lib" ] || { echo "ERROR: cannot find the cell model $lib (set GLS_LIB or PDK_DIR)"; exit 1; }
for f in firmware_imem.hex firmware_dmem.hex app_firmware.hex; do
    [ -f "$hex/$f" ] || { echo "ERROR: $hex/$f not found, run make fw at home and copy the three hex files to $hex"; exit 1; }
done

mkdir -p "$out"
# The netlist of ASIC_Top has no parameters left, the memories load these names from the run folder
for f in firmware_imem.hex firmware_dmem.hex app_firmware.hex; do
    cp "$hex/$f" "$out/$f"
done

# Memory instances in the netlist: "<module name> <instance name> (" with or without "#(...)"
python3 - "$netlist" "$out/mem_shim.v" <<'PY' || { echo "ERROR: could not write the memory wrappers"; exit 1; }
import re
import sys

text = open(sys.argv[1]).read()
init = {"master_ram": "firmware_dmem.hex", "boot_rom": "firmware_imem.hex", "app_ram": "", "app_rom": "app_firmware.hex"}
found = re.findall(r"^\s*((?:Data_Memory|Dual_Port_ROM)\w*)\s*(#\s*\(.*?\)\s*)?(\\?\w+)\s*\(", text, re.M | re.S)
shim = ["// Written by asic/gls/run.sh: maps the memory module names of the netlist to the RTL models", "`timescale 1ns / 1ps"]
seen = set()
params = []
for mod, par, inst in found:
    inst = inst.lstrip("\\")
    if inst not in init:
        sys.exit("unknown memory instance %s of %s" % (inst, mod))
    if mod in ("Data_Memory", "Dual_Port_ROM"):
        # Plain module name: the RTL model is used directly. Without parameters in the netlist the
        # image name is set from outside
        if not par:
            params.append('    defparam ASIC_Top_tb.dut.soc.%s.INIT_FILE = "%s";' % (inst, init[inst]))
        continue
    if mod in seen:
        continue
    seen.add(mod)
    if mod.startswith("Data_Memory"):
        shim.append("module %s (input clk, input MemWrite, input MemRead, input [31:0] addr, input [31:0] write_data,"
                    " input [3:0] wstrb, output [31:0] read_data);" % mod)
        shim.append('    Data_Memory #(.INIT_FILE("%s")) m (.clk(clk), .MemWrite(MemWrite), .MemRead(MemRead), .addr(addr),'
                    " .write_data(write_data), .wstrb(wstrb), .read_data(read_data));" % init[inst])
    else:
        shim.append("module %s (input clk, input [31:0] addrA, output [31:0] dataOutA, input [31:0] addrB,"
                    " output [31:0] dataOutB);" % mod)
        shim.append('    Dual_Port_ROM #(.INIT_FILE("%s")) m (.clk(clk), .addrA(addrA), .dataOutA(dataOutA), .addrB(addrB),'
                    " .dataOutB(dataOutB));" % init[inst])
    shim.append("endmodule")
shim.append("module gls_mem_params;")
shim.extend(params)
shim.append("endmodule")
open(sys.argv[2], "w").write("\n".join(shim) + "\n")
print("memory instances in the netlist: %d, wrappers written: %d, image names set from outside: %d"
      % (len(found), len(seen), len(params)))
if len(found) != 4:
    sys.exit("expected 4 memory instances")
PY

(cd "$out" && rm -rf xcelium.d xrun.log &&
    "$xrun" -64bit -sv -define GLS -timescale 1ns/1ps -nospecify -notimingchecks \
        "$root/dv/tb/ASIC_Top_tb.sv" "$root/$netlist" mem_shim.v \
        "$root/rtl/mem/Data_Memory.v" "$root/rtl/mem/Dual_Port_ROM.v" "$lib" \
        -top ASIC_Top_tb -top gls_mem_params -l xrun.log > /dev/null 2>&1)

grep -E '^(ok  :|FAIL:|Boot after|ASIC_Top_tb RESULT)|\*E,|\*F,' "$out/xrun.log" | head -n 30 | tee "$out/gls_summary.txt"
grep -q 'ASIC_Top_tb RESULT: PASS' "$out/xrun.log" || { echo "GLS did not pass, see $out/xrun.log"; exit 1; }
