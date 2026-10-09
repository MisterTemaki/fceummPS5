#!/usr/bin/env python3
"""forge_nes_crc.py file.nes CRC32HEX -- changes 4 unused PRG bytes (at PRG offset $3000) of a test ROM so the CRC32 of
its PRG + CHR (the file past the 16-byte header) becomes CRC32HEX: a test ROM the header database knows.
CRC32 is affine in those bits, so 32 single-bit probes and Gaussian elimination over GF(2) solve it."""
import sys
import zlib

path, target = sys.argv[1], int(sys.argv[2], 16)
data = bytearray(open(path, 'rb').read())
at = 16 + 0x3000
assert data[at:at + 4] == b'\0\0\0\0', "the bytes to change must be unused (zero)"


def crc_with(x):
    d = bytearray(data)
    d[at:at + 4] = x.to_bytes(4, 'little')
    return zlib.crc32(bytes(d[16:]))


base = crc_with(0)
cols = [crc_with(1 << bit) ^ base for bit in range(32)]
want = base ^ target
basis = {}
for i in range(32):
    v, mask = cols[i], 1 << i
    for b in range(31, -1, -1):
        if not (v >> b) & 1:
            continue
        if b in basis:
            v ^= basis[b][0]
            mask ^= basis[b][1]
        else:
            basis[b] = (v, mask)
            break
x, v = 0, want
for b in range(31, -1, -1):
    if (v >> b) & 1:
        v ^= basis[b][0]
        x ^= basis[b][1]
assert v == 0
assert crc_with(x) == target
data[at:at + 4] = x.to_bytes(4, 'little')
open(path, 'wb').write(bytes(data))
print("%s: PRG + CHR CRC32 %08X" % (path, target))
