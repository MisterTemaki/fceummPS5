#!/usr/bin/env python3
"""Builds frontend/data/nesdb.tsv, the cartridge header corrections built into the app, from Mesen's game database
(MesenNesDB.txt, MesenCE 2.2.1: NewRisingSun's NES 2.0 header database, NesCartDB and Nestopia's database).

  tools/make_nesdb.py <MesenNesDB.txt> <FCEUmm's src/ines-correct.h> <FCEUmm's src/ines.c> frontend/data/nesdb.tsv

FCEUmm corrects the headers of the games it knows (src/ines-correct.h). This table adds what Mesen's database
knows beyond that, and only its validated entries (those with a submapper: NES 2.0 data checked against the
cartridges), for mappers FCEUmm implements. VS System and PlayChoice entries are left to FCEUmm (vsuni.c).

Each line: CRC32 (of PRG + CHR, as FCEUmm and Mesen compute it), mapper, submapper, PRG KiB, CHR KiB, mirroring
(h, v, 4), battery (0/1), PRG-RAM bytes, PRG-NVRAM bytes, CHR-RAM bytes, timing (0 NTSC, 1 PAL, 3 Dendy).
"""
import re
import sys


def size(value):
    if not value:
        return 0
    if value[0] == "b":
        return int(value[1:])
    return int(value) * 1024


def main():
    mesen, correct, ines, out = sys.argv[1:5]
    known = set()
    with open(correct, encoding="utf-8", errors="replace") as f:
        for m in re.finditer(r"\{\s*0x([0-9a-fA-F]{1,8})\s*,", f.read()):
            known.add(int(m.group(1), 16))
    with open(ines, encoding="utf-8", errors="replace") as f:
        mappers = {int(n) for n in re.findall(r'INES_BOARD\(\s*"[^"]*"\s*,\s*(\d+)', f.read())}

    rows = []
    skipped = {"fceumm knows it": 0, "not validated": 0, "mapper": 0, "vs/pc10": 0}
    seen = set()
    with open(mesen, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            v = line.split(",")
            if len(v) < 16:
                continue
            crc = int(v[0], 16)
            system, mapper, sub = v[1], int(v[5] or 0), v[15]
            if crc in seen:
                continue
            seen.add(crc)
            if crc in known:
                skipped["fceumm knows it"] += 1
                continue
            if sub == "":
                skipped["not validated"] += 1
                continue
            if system in ("VsSystem", "Playchoice"):
                skipped["vs/pc10"] += 1
                continue
            if mapper not in mappers:
                skipped["mapper"] += 1
                continue
            mirroring = v[12] if v[12] in ("h", "v", "4") else "h"
            timing = {"NesPal": 1, "Dendy": 3}.get(system, 0)
            rows.append("%08X\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%d\t%d" % (
                crc, mapper, int(sub), size(v[6]) // 1024, size(v[7]) // 1024, mirroring, 1 if v[11] not in ("", "0") else 0,
                size(v[9]), size(v[10]), size(v[8]), timing))
    rows.sort()
    header = [
        "# NES FCEUmm PS5: cartridge header corrections from Mesen's game database (MesenCE 2.2.1, MesenNesDB.txt:",
        "# NewRisingSun's NES 2.0 database, NesCartDB, Nestopia's database), validated entries FCEUmm doesn't fix itself",
        "# crc32 mapper submapper prg_kib chr_kib mirroring battery prg_ram prg_nvram chr_ram timing",
    ]
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(header + rows) + "\n")
    print("%s: %d entries (skipped: %s)" % (out, len(rows), ", ".join("%s %d" % kv for kv in skipped.items())))


if __name__ == "__main__":
    main()
