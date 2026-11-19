#!/usr/bin/env python3
# NES FCEUmm PS5 1.2 (FBNeo PS5 2.2's, its final review): the app's PIE must not call any function of the SDK's
# libc.a(syscalls.o). That member
# is the payload SDK's own system calls -- each one a bare "mov $n, %rax; syscall; ret" -- for payloads; a title's code
# goes through libkernel's exports (the stubs), and a raw system call from the eboot's own code may be refused by the
# console (SIGSYS) and never sets errno. FBNeo PS5 2.2's first build took link() from it (libkernel.so's stub has no
# link, only libkernel_sys has, which the app may not load): tools/check_imports.py can't see that, the code is static.
#
# The Makefile links the PIE with "-y <symbol>" for every symbol syscalls.o defines (lld then prints who defines and who
# references each one) and gives this the trace:
#
#   check_syscalls.py rsp <libc.a> <out.rsp>      writes the "-y <symbol>" lines (a response file for the link)
#   check_syscalls.py check <trace>               exit 1 when an object other than syscalls.o references a symbol
#                                                 that syscalls.o ends up defining (the member was linked in for it)
#
# A symbol syscalls.o defines but a stub defines too (and wins) has no "definition" line from syscalls.o unless the
# member was pulled in; only "lazy definition" lines, which are fine.
import os
import re
import subprocess
import sys
import tempfile


def rsp(libc, out):
    with tempfile.TemporaryDirectory() as d:
        member = os.path.join(d, "syscalls.o")
        with open(member, "wb") as f:
            f.write(subprocess.run(["ar", "p", libc, "syscalls.o"], check=True, capture_output=True).stdout)
        nm = subprocess.run(["nm", "-g", "--defined-only", member], check=True, capture_output=True, text=True).stdout
    syms = sorted({line.split()[-1] for line in nm.splitlines() if len(line.split()) >= 3})
    if not syms:
        print("check_syscalls: no symbols in %s(syscalls.o)" % libc, file=sys.stderr)
        return 1
    tmp = out + ".part"
    with open(tmp, "w") as f:
        for s in syms:
            f.write("-y %s\n" % s)
    os.replace(tmp, out)
    return 0


# lld 18: "<file>: reference to <sym>", "<file>: definition of <sym>", "lazy definition of", "shared definition of"...
LINE = re.compile(r"^(?P<file>.*): (?:(?P<ref>reference to)|(?P<what>lazy definition|definition|shared definition|common definition) of) (?P<sym>\S+)$")


def check(trace):
    defined_here = set()
    refs = {}
    with open(trace, errors="replace") as f:
        for line in f:
            m = LINE.match(line.rstrip("\n"))
            if not m:
                continue
            file, sym = m.group("file"), m.group("sym")
            what = "reference" if m.group("ref") else m.group("what")
            from_syscalls = file.endswith("(syscalls.o)")
            if what == "definition" and from_syscalls:
                defined_here.add(sym)
            elif what == "reference" and not from_syscalls:
                refs.setdefault(sym, []).append(file)
    bad = sorted(s for s in refs if s in defined_here)
    for s in bad:
        for who in refs[s]:
            print("check_syscalls: %s calls %s: a raw system call from libc.a(syscalls.o), not a libkernel export" % (who, s))
    if bad:
        print("check_syscalls: FAILED (%d symbol(s))" % len(bad))
        return 1
    print("check_syscalls: ok (no function of libc.a(syscalls.o) in the app)")
    return 0


def main(argv):
    if len(argv) == 4 and argv[1] == "rsp":
        return rsp(argv[2], argv[3])
    if len(argv) == 3 and argv[1] == "check":
        return check(argv[2])
    print(__doc__ if __doc__ else "usage: check_syscalls.py rsp <libc.a> <out.rsp> | check <trace>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
