// NES FCEUmm PS5: cartridge header corrections from Mesen's game database (data/nesdb.tsv, tools/make_nesdb.py).
//
// Many NES dumps carry an old iNES header with a wrong mapper, mirroring, battery or region, or one that can't say
// what the board has (submapper, PRG-RAM, CHR-RAM). FCEUmm corrects the games it knows (src/ines-correct.h);
// Mesen's database -- NewRisingSun's NES 2.0 header database, NesCartDB and Nestopia's database -- knows about
// 9,000 more. Before the game starts, a ROM with an iNES 1.0 (or older) header whose PRG + CHR CRC32 is in the
// table gets an NES 2.0 header made from it, as Mesen uses its database over such headers; FCEUmm then reads the
// board as described. NES 2.0 headers are trusted as they are, and so are UNIF files and disks.
//
// SPDX-License-Identifier: MIT
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace fe
{
// The table's size (entries).
size_t NesDbCount();

// rom: a whole .nes file. True when its header was rewritten; *what says how ("mapper 4 -> 118, ...").
bool FixNesHeader(std::vector<uint8_t>& rom, std::string* what);
} // namespace fe
