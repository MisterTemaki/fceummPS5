#!/usr/bin/env python3
"""Builds frontend/data/nes4p.tsv, the games made for four players that the 4-player adapter's Auto setting
recognises (Settings, CONTROLS), from FCEUmm's own lists and Mesen's game database.

  tools/make_nes4p.py <FCEUmm's src/drivers/libretro/libretro.c> <MesenNesDB.txt> frontend/data/nes4p.tsv

- FCEUmm's libretro port plugs a Four Score or the Famicom's 4-player adapter in by itself for the games of two
  lists (fourscore_db_list, famicom_4p_db_list; entries under "#if 0" are left out, as the compiler leaves them).
  Those come first, so a game FCEUmm knows gets what FCEUmm gives it.
- Mesen's database (MesenCE 2.2.1: NewRisingSun's NES 2.0 header database, NesCartDB and Nestopia's database)
  gives each cartridge its input device, NES 2.0's numbers: 2 for the NES Four Score (or Satellite), 3 for the
  Famicom's 4-player adapter (the "simple" protocol, the one FCEUmm emulates). Its games FCEUmm doesn't list are
  added.

Each line: CRC32 (of PRG + CHR, as FCEUmm and Mesen compute it), the adapter (F: NES Four Score, H: the Famicom's
4-player adapter, Hori's and the others), where it comes from (fceumm, mesen).
"""
import re
import sys


def fceumm_list(src, name):
    i = src.index("static const struct cartridge_db %s[]" % name)
    body = src[i:src.index("};", i)]
    body = re.sub(r"#if 0.*?#endif", "", body, flags=re.S)
    return [int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]{1,8})", body)]


def main():
    libretro, mesen, out = sys.argv[1:4]
    with open(libretro, encoding="utf-8", errors="replace") as f:
        src = f.read()
    table = {}
    counts = {"fceumm F": 0, "fceumm H": 0, "mesen F": 0, "mesen H": 0}
    # FCEUmm checks the Four Score list first and the Famicom list after it, and the second one wins (it plugs the
    # Famicom adapter in over the Four Score): the same order here
    for name, kind in (("fourscore_db_list", "F"), ("famicom_4p_db_list", "H")):
        for crc in fceumm_list(src, name):
            if crc in table:
                counts["fceumm " + table[crc][0]] -= 1
            table[crc] = (kind, "fceumm")
            counts["fceumm " + kind] += 1
    disagree = []
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
            if crc in seen:
                continue
            seen.add(crc)
            kind = {"2": "F", "3": "H"}.get(v[13])
            if not kind:
                continue
            if crc in table:
                if table[crc][0] != kind:
                    disagree.append("%08X (FCEUmm %s, Mesen %s)" % (crc, table[crc][0], kind))
                continue
            table[crc] = (kind, "mesen")
            counts["mesen " + kind] += 1
    header = [
        "# NES FCEUmm PS5: the games made for four players, by ROM CRC32 (PRG + CHR): the 4-player adapter's Auto",
        "#   fceumm: FCEUmm's lists (src/drivers/libretro/libretro.c): %d Four Score, %d Famicom adapter" % (
            counts["fceumm F"], counts["fceumm H"]),
        "#   mesen: Mesen's game database (MesenCE 2.2.1, MesenNesDB.txt, input type 2 / 3), the games FCEUmm doesn't "
        "list: %d Four Score, %d Famicom adapter" % (counts["mesen F"], counts["mesen H"]),
        "# crc32 adapter (F: NES Four Score, H: the Famicom's 4-player adapter) source",
    ]
    rows = ["%08X\t%s\t%s" % (crc, kind, source) for crc, (kind, source) in sorted(table.items())]
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(header + rows) + "\n")
    print("%s: %d games (%s)%s" % (out, len(rows), ", ".join("%s %d" % kv for kv in counts.items()),
                                   "; FCEUmm's kept where Mesen disagrees: " + ", ".join(disagree) if disagree else ""))


if __name__ == "__main__":
    main()
