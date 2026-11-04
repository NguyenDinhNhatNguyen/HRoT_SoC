#!/usr/bin/env python3
"""Coverage summary for sim/cov.sh (P-19).

Usage: cov_summary.py <cvg.txt> <code.txt>
  cvg.txt   vcover report -cvg -details merged.ucdb
  code.txt  vcover report -code bcesf -byDU merged.ucdb

Prints one line per covergroup type and per design unit of the RTL under test, lists the bins that were
never hit, and checks the targets of docs/verification/SHA256_UVM_TestPlan.md section 6. Exit code 1
when a target is missed.
"""
import re
import sys

# Design units reported: the RTL compiled with +cover. Everything not listed here is counted as the core
OTHER_DUS = ["SHA256_Wrapper", "SHA256_Core", "AXI4_Lite_Slave_Template", "APB_Decoder", "GPIO", "TIMER",
             "Mailbox"]
# Code coverage targets (statements and branches, percent)
CODE_TARGETS = {"SHA256_Wrapper": 95.0, "SHA256_Core": 90.0}


def parse_code(path):
    """{du: {"Stmts": (active, hits, pct), "Branches": ..., ...}}"""
    dus = {}
    cur = None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\s*Design Unit: \w+\.(\w+)", line)
        if m:
            cur = dus.setdefault(m.group(1), {})
            continue
        m = re.match(r"\s*(Stmts|Branches|FEC Condition Terms|FEC Expression Terms)\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)",
                     line)
        if m and cur is not None:
            cur[m.group(1)] = (int(m.group(2)), int(m.group(3)), float(m.group(5)))
    return dus


def parse_cvg(path):
    """[(type path, pct)], [(covergroup, bin)] of bins never hit, total pct"""
    types = []
    zero = []
    total = None
    group = None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\s*TYPE\s+(\S+)\s+([\d.]+)%", line)
        if m:
            group = m.group(1).split("/")[-1]
            types.append((group, float(m.group(2))))
            continue
        if re.match(r"\s*Covergroup instance", line):
            group = None                  # bins are listed once, under the TYPE
            continue
        m = re.match(r"\s*bin\s+(.+?)\s+0\s+1\s+ZERO", line)
        if m and group is not None:
            zero.append((group, m.group(1)))
        m = re.match(r"\s*TOTAL COVERGROUP COVERAGE:\s+([\d.]+)%", line)
        if m:
            total = float(m.group(1))
    return types, zero, total


def pct(entry):
    return "   -  " if entry is None or entry[0] == 0 else "%5.1f%%" % entry[2]


def main():
    types, zero, total = parse_cvg(sys.argv[1])
    dus = parse_code(sys.argv[2])
    ok = True

    print("Functional coverage (covergroups, merged over every run)")
    for name, p in types:
        print("  %-28s %6.1f%%" % (name, p))
        if p < 100.0:
            ok = False
    print("  %-28s %6.1f%%" % ("TOTAL", total if total is not None else 0.0))
    if total is None:
        ok = False
    for group, b in zero:
        print("    not hit: %s %s" % (group, b))

    print("\nCode coverage (statements, branches, conditions, expressions)")
    print("  %-26s %7s %7s %7s %7s" % ("Design unit", "Stmt", "Branch", "Cond", "Expr"))
    core_dus = sorted(du for du in dus if du not in OTHER_DUS)
    for du in core_dus + [du for du in OTHER_DUS if du in dus]:
        d = dus[du]
        line = "  %-26s %7s %7s %7s %7s" % (du, pct(d.get("Stmts")), pct(d.get("Branches")),
                                             pct(d.get("FEC Condition Terms")), pct(d.get("FEC Expression Terms")))
        if du in CODE_TARGETS:
            target = CODE_TARGETS[du]
            met = all(d.get(k) is None or d[k][0] == 0 or d[k][2] >= target for k in ("Stmts", "Branches"))
            line += "   target %.0f%% %s" % (target, "met" if met else "NOT MET")
            ok = ok and met
        print(line)
    core = [dus[d] for d in core_dus]
    for key, label in (("Stmts", "statements"), ("Branches", "branches")):
        act = sum(d[key][0] for d in core if key in d)
        hit = sum(d[key][1] for d in core if key in d)
        if act:
            print("  Core total %-15s %5.1f%% (%d of %d)" % (label, 100.0 * hit / act, hit, act))
    for du in CODE_TARGETS:
        if du not in dus:
            print("  %s missing from the code coverage report" % du)
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
