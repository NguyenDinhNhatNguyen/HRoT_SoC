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
#   GLS_MACRO Verilog model of the SRAM macro, used only when the netlist holds sram_2k_macro
#             (default ~/PDK_GPDK45/lib/sram_2k_macro.v, else the home model dv/models/sram_macro_model.v)
# The memories that are black boxes in the netlist are the RTL models of rtl/mem here.
# A netlist of make asic-genus SRAM=1 ROM=1 has no black box: the two RAMs are sram_2k_macro
# instances and the two ROMs are gates, so only the macro model is added.
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
# What the netlist holds: memory black boxes (Data_Memory, Dual_Port_ROM) and SRAM macro instances
# A word boundary, not a space, after the name: Genus writes some instances as name#( or name on its own line
n_bb=$(grep -cE '^\s*(Data_Memory|Dual_Port_ROM)\w*\b' "$netlist")
n_macro=$(grep -cE '^\s*sram_2k_macro\w*\b' "$netlist")
macro=""
macro_note=""
if [ "$n_macro" -gt 0 ]; then
    macro=${GLS_MACRO:-${PDK_DIR:-$HOME/PDK_GPDK45}/lib/sram_2k_macro.v}
    macro_note="macro model: the school model"
    if [ ! -f "$macro" ]; then
        macro=$root/dv/models/sram_macro_model.v
        macro_note="macro model: the home model dv/models/sram_macro_model.v (the school model was not found)"
    fi
fi
if [ "$n_bb" -gt 0 ]; then
    for f in firmware_imem.hex firmware_dmem.hex app_firmware.hex; do
        [ -f "$hex/$f" ] || { echo "ERROR: $hex/$f not found, run make fw at home and copy the three hex files to $hex"; exit 1; }
    done
fi

case "$netlist" in
    /*) netlist_abs=$netlist ;;
    *)  netlist_abs=$root/$netlist ;;
esac
mkdir -p "$out"
# The netlist of ASIC_Top has no parameters left, the memories load these names from the run folder
for f in firmware_imem.hex firmware_dmem.hex app_firmware.hex; do
    [ -f "$hex/$f" ] && cp "$hex/$f" "$out/$f"
done

# Memory instances in the netlist: "<module name> <instance name> (" with or without "#(...)"
# The server's LD_LIBRARY_PATH (Xcelium, Calibre, XRT) loads a wrong libpython into /usr/bin/python3
# (undefined symbol _Py_LegacyLocaleDetected, 18/11), so Python runs without it
env -u LD_LIBRARY_PATH python3 - "$netlist" "$out/mem_shim.v" <<'PY' || { echo "ERROR: could not write the memory wrappers"; exit 1; }
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
n_macro = len(re.findall(r"^\s*sram_2k_macro\w*\s+\S+\s*\(", text, re.M))
insts = set(i.lstrip("\\") for _, _, i in found)
print("memory black boxes in the netlist: %d, SRAM macros: %d, wrappers written: %d, image names set from outside: %d"
      % (len(found), n_macro, len(seen), len(params)))
# Each RAM is a black box or a macro, never both. The ROMs are both black boxes or both logic
rams = len(insts & {"master_ram", "app_ram"})
roms = len(insts & {"boot_rom", "app_rom"})
if (rams, n_macro) not in ((2, 0), (0, 2)) or roms not in (0, 2) or len(found) != rams + roms:
    sys.exit("unexpected memories: %d RAM black boxes, %d ROM black boxes, %d SRAM macros" % (rams, roms, n_macro))
PY

(cd "$out" && rm -rf xcelium.d xrun.log &&
    "$xrun" -64bit -sv -define GLS -timescale 1ns/1ps -nospecify -notimingchecks \
        "$root/dv/tb/ASIC_Top_tb.sv" "$netlist_abs" mem_shim.v \
        "$root/rtl/mem/Data_Memory.v" "$root/rtl/mem/Dual_Port_ROM.v" $macro "$lib" \
        -top ASIC_Top_tb -top gls_mem_params -l xrun.log > /dev/null 2>&1)

{
    echo "netlist: $n_bb memory black boxes (RTL models), $n_macro SRAM macros${macro_note:+, $macro_note}"
    grep -E '^(ok  :|FAIL:|MACRO ERROR|Boot after|ASIC_Top_tb RESULT)|\*E,|\*F,' "$out/xrun.log" | head -n 30
} | tee "$out/gls_summary.txt"
grep -q 'ASIC_Top_tb RESULT: PASS' "$out/xrun.log" || { echo "GLS did not pass, see $out/xrun.log"; exit 1; }
