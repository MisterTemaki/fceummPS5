// NES FCEUmm PS5: cartridge header corrections from Mesen's game database (data/nesdb.tsv, tools/make_nesdb.py), and
// the games made for four players (data/nes4p.tsv, tools/make_nes4p.py).
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

// ---- the games made for four players (data/nes4p.tsv, tools/make_nes4p.py): the 4-player adapter's Auto ----
// FCEUmm's own lists (the games its libretro port plugs an adapter in for) and, for the games those don't have,
// Mesen's database (NES 2.0's input device 2, the NES Four Score, or 3, the Famicom's 4-player adapter).
enum class FourPlayer : int
{
	None = 0,      // two players
	FourScore = 1, // the NES Four Score (or Satellite): players 3 and 4 after the first 8 bits of $4016 / $4017
	Famicom = 2,   // the Famicom's 4-player adapter (Hori's...): players 3 and 4 on bit 1 of $4016 / $4017
};
size_t NesFourPlayerCount();
// crc: the cartridge's PRG + CHR CRC32 (fe_nes_cart_crc). *source: "FCEUmm's list" or "Mesen's database".
FourPlayer NesFourPlayer(uint32_t crc, const char** source);
// rom: a whole .nes file. An NES 2.0 header's default expansion device (byte 15): 2 the Four Score, 3 the Famicom's
// adapter; None for anything else (and for older headers, which don't have it).
FourPlayer NesHeaderFourPlayer(const std::vector<uint8_t>& rom);
} // namespace fe
