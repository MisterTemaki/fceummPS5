#!/usr/bin/env python3
"""Builds tiny NES test ROMs for the host tests (no game data needed).

The ROM (NROM: 16 KiB PRG, 8 KiB CHR of zeros) shows a red backdrop and plays a square-wave tone; while the pad's
A or B button is held -- Cross is B with the port's mapping -- the backdrop turns green. So a de-tiled flip shows
whether the whole chain works: the core's CPU, PPU and APU, the port's scaler and tiler, and the pad -> core
input mapping.

    make_test_rom.py out.nes [ntsc|pal|sram|ines1]
      ntsc   an NES 2.0 header, NTSC timing
      pal    an NES 2.0 header, PAL timing (byte 12 = 1)
      sram   battery RAM: the game writes $42 to $6000 every frame, $FF while A/B is held ("erases its save")
      ines1  an iNES 1.0 header saying mapper 0, horizontal mirroring, no battery (the header database test)
    make_test_rom.py out.unf        the same game as a UNIF file (board NROM)
    make_test_rom.py out.fds        a Famicom Disk System image (fwNES header, one side, an empty disk)
"""
import sys


def assemble(base, items):
    """items: bytes, ("label", name), (opcode_bytes, "label") for an 8-bit relative branch,
    or ("abs", opcode, name) for a 16-bit absolute operand."""
    labels = {}
    pc = base
    for it in items:
        if isinstance(it, tuple) and it[0] == "label":
            labels[it[1]] = pc
        elif isinstance(it, tuple) and it[0] == "abs":
            pc += 3
        elif isinstance(it, tuple):
            pc += len(it[0]) + 1
        else:
            pc += len(it)
    out = bytearray()
    pc = base
    for it in items:
        if isinstance(it, tuple) and it[0] == "label":
            continue
        if isinstance(it, tuple) and it[0] == "abs":
            t = labels[it[2]]
            out += bytes([it[1], t & 0xFF, t >> 8])
            pc += 3
        elif isinstance(it, tuple):
            op, name = it
            off = labels[name] - (pc + len(op) + 1)
            assert -128 <= off <= 127, (name, off)
            out += op + bytes([off & 0xFF])
            pc += len(op) + 1
        else:
            out += it
            pc += len(it)
    return bytes(out), labels


def program(sram):
    items = [
        ("label", "reset"),
        bytes([0x78, 0xD8]),                          # SEI; CLD
        bytes([0xA2, 0xFF, 0x9A]),                    # LDX #$FF; TXS
        bytes([0xA9, 0x00, 0x8D, 0x00, 0x20, 0x8D, 0x01, 0x20]),  # PPUCTRL = PPUMASK = 0
        bytes([0x8D, 0x10, 0x40]),                    # no DMC IRQ
        bytes([0xA9, 0x40, 0x8D, 0x17, 0x40]),        # no frame IRQ
        bytes([0x2C, 0x02, 0x20]),                    # BIT $2002
        ("label", "vw1"), bytes([0x2C, 0x02, 0x20]), (bytes([0x10]), "vw1"),  # two vblanks: the PPU is warm
        ("label", "vw2"), bytes([0x2C, 0x02, 0x20]), (bytes([0x10]), "vw2"),
        # a tone: pulse 1, constant volume 15, duty 50 %, length counter halted, ~440 Hz
        bytes([0xA9, 0x01, 0x8D, 0x15, 0x40]),
        bytes([0xA9, 0xBF, 0x8D, 0x00, 0x40]),
        bytes([0xA9, 0xFD, 0x8D, 0x02, 0x40]),
        bytes([0xA9, 0x00, 0x8D, 0x03, 0x40]),
        ("label", "loop"),
        ("label", "vw"), bytes([0x2C, 0x02, 0x20]), (bytes([0x10]), "vw"),
        # pad 1: strobe, then A, then B
        bytes([0xA9, 0x01, 0x8D, 0x16, 0x40, 0xA9, 0x00, 0x8D, 0x16, 0x40]),
        bytes([0xAD, 0x16, 0x40, 0x0D, 0x16, 0x40, 0x29, 0x01]),  # LDA $4016; ORA $4016; AND #1
        bytes([0xAA]),                                # TAX (0 = released)
    ]
    if sram:
        items += [
            bytes([0xA9, 0x42]),                      # LDA #$42
            bytes([0xE0, 0x00]), (bytes([0xF0]), "keep"),  # CPX #0; BEQ keep
            bytes([0xA9, 0xFF]),                      # LDA #$FF
            ("label", "keep"),
            bytes([0x8D, 0x00, 0x60]),                # STA $6000
        ]
    items += [
        bytes([0xA9, 0x16]),                          # LDA #$16  red
        bytes([0xE0, 0x00]), (bytes([0xF0]), "write"),  # CPX #0; BEQ write
        bytes([0xA9, 0x2A]),                          # LDA #$2A  green
        ("label", "write"),
        bytes([0xA0, 0x3F, 0x8C, 0x06, 0x20, 0xA0, 0x00, 0x8C, 0x06, 0x20]),  # PPUADDR = $3F00
        bytes([0x8D, 0x07, 0x20]),                    # the backdrop colour
        bytes([0xA9, 0x00, 0x8D, 0x06, 0x20, 0x8D, 0x06, 0x20]),  # PPUADDR = 0
        bytes([0x8D, 0x05, 0x20, 0x8D, 0x05, 0x20]),  # scroll 0, 0
        bytes([0x8D, 0x00, 0x20]),                    # PPUCTRL = 0
        bytes([0xA9, 0x0A, 0x8D, 0x01, 0x20]),        # PPUMASK: background on (tile 0 of zeros: the backdrop)
        ("abs", 0x4C, "loop"),                        # JMP loop
        ("label", "nmi"),
        bytes([0x40]),                                # RTI
    ]
    return assemble(0xC000, items)


def nes(kind):
    code, labels = program(kind == "sram")
    prg = bytearray(16384)
    prg[0:len(code)] = code
    for vec, name in ((0x3FFA, "nmi"), (0x3FFC, "reset"), (0x3FFE, "nmi")):
        prg[vec] = labels[name] & 0xFF
        prg[vec + 1] = labels[name] >> 8
    chr_ = bytes(8192)
    h = bytearray(16)
    h[0:4] = b"NES\x1a"
    h[4], h[5] = 1, 1
    if kind == "ines1":
        h[6] = 0x00
    else:
        h[6] = 0x01 | (0x02 if kind == "sram" else 0)  # vertical mirroring, battery
        h[7] = 0x08                                     # NES 2.0
        h[10] = 0x70 if kind == "sram" else 0x00        # 8 KiB PRG-NVRAM (64 << 7)
        h[12] = 1 if kind == "pal" else 0
    return bytes(h + prg + chr_)


def unif():
    # UNIF: the same NROM program as chunks (board name, PRG, CHR, mirroring)
    code = nes("ntsc")
    prg, chr_ = code[16:16 + 16384], code[16 + 16384:]

    def chunk(tag, data):
        return tag + len(data).to_bytes(4, "little") + data

    return (b"UNIF" + (7).to_bytes(4, "little") + bytes(24) + chunk(b"MAPR", b"NROM\0") + chunk(b"PRG0", prg) +
            chunk(b"CHR0", chr_) + chunk(b"MIRR", b"\x01"))


def fds():
    side = bytearray(65500)
    side[0] = 0x01
    side[1:15] = b"*NINTENDO-HVC*"
    side[56] = 0x02  # file amount block
    side[57] = 0
    return b"FDS\x1a" + bytes([1]) + bytes(11) + bytes(side)


def main():
    out = sys.argv[1]
    kind = sys.argv[2] if len(sys.argv) > 2 else "ntsc"
    ext = out.rsplit(".", 1)[-1].lower()
    data = fds() if ext == "fds" else unif() if ext in ("unf", "unif") else nes(kind)
    with open(out, "wb") as f:
        f.write(data)
    print(f"wrote {out} ({ext}, {kind}, {len(data)} bytes)")


if __name__ == "__main__":
    main()
