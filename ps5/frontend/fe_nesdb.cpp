// NES FCEUmm PS5: cartridge header corrections (fe_nesdb.h).
// SPDX-License-Identifier: MIT

#include "fe_nesdb.h"

#include <zlib.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unordered_map>

#define FCEUMM_NESDB_INCBIN(sym, path)                                                                           \
	__asm__(".section .rodata\n"                                                                               \
			".balign 16\n"                                                                                     \
			".global " #sym "_begin\n" #sym "_begin:\n"                                                        \
			".incbin \"" path "\"\n"                                                                           \
			".global " #sym "_end\n" #sym "_end:\n"                                                            \
			".previous\n");                                                                                    \
	extern "C" const char sym##_begin[];                                                                       \
	extern "C" const char sym##_end[];

FCEUMM_NESDB_INCBIN(fceumm_nesdb, NESDB_TSV)

namespace fe
{
namespace
{
struct Entry
{
	uint16_t mapper;
	uint8_t submapper;
	uint32_t prg_kib, chr_kib;
	char mirroring; // h, v, 4
	bool battery;
	uint32_t prg_ram, prg_nvram, chr_ram; // bytes
	uint8_t timing; // 0 NTSC, 1 PAL, 3 Dendy
};

struct Table
{
	std::unordered_map<uint32_t, Entry> map;
	Table()
	{
		const char* p = fceumm_nesdb_begin;
		const char* end = fceumm_nesdb_end;
		while (p < end)
		{
			const char* nl = static_cast<const char*>(memchr(p, '\n', size_t(end - p)));
			if (!nl)
				nl = end;
			const std::string line(p, size_t(nl - p));
			p = nl + 1;
			if (line.empty() || line[0] == '#')
				continue;
			unsigned crc = 0, mapper = 0, sub = 0, prg = 0, chr = 0, bat = 0, ram = 0, nvram = 0, chrram = 0, timing = 0;
			char mir = 'h';
			if (sscanf(line.c_str(), "%x %u %u %u %u %c %u %u %u %u %u", &crc, &mapper, &sub, &prg, &chr, &mir, &bat, &ram,
					&nvram, &chrram, &timing) != 11)
				continue;
			map[crc] = Entry{uint16_t(mapper), uint8_t(sub), prg, chr, mir, bat != 0, ram, nvram, chrram, uint8_t(timing)};
		}
	}
};

const Table& T()
{
	static const Table t;
	return t;
}

// NES 2.0's RAM size code: 64 << n bytes (0 = none).
uint8_t Shift(uint32_t bytes)
{
	if (bytes == 0)
		return 0;
	uint8_t n = 0;
	while ((64u << n) < bytes && n < 15)
		n++;
	return n;
}
} // namespace

size_t NesDbCount()
{
	return T().map.size();
}

bool FixNesHeader(std::vector<uint8_t>& rom, std::string* what)
{
	if (rom.size() < 16 + 16384 || memcmp(rom.data(), "NES\x1a", 4) != 0)
		return false;
	uint8_t* h = rom.data();
	if ((h[7] & 0x0C) == 0x08)
		return false; // NES 2.0: trusted
	// archaic headers (bytes 7-15 garbage, "DiskDude!") only count bytes 4-6
	const bool archaic = (h[7] & 0x0C) != 0 || h[12] || h[13] || h[14] || h[15];
	const size_t start = 16 + ((h[6] & 4) ? 512 : 0);
	const uint32_t prg = uint32_t(h[4]) * 16384, chr = uint32_t(h[5]) * 8192;
	if (prg == 0 || start + prg + chr > rom.size())
		return false;
	const uint32_t crc = uint32_t(crc32(0L, rom.data() + start, uInt(prg + chr)));
	auto it = T().map.find(crc);
	if (it == T().map.end())
		return false;
	const Entry& e = it->second;
	if (e.prg_kib * 1024 != prg || e.chr_kib * 1024 != chr)
		return false; // laid out differently from the dump the database describes
	const int old_mapper = (h[6] >> 4) | (archaic ? 0 : (h[7] & 0xF0));
	const bool old_battery = (h[6] & 2) != 0;
	const char old_mirroring = (h[6] & 8) ? '4' : ((h[6] & 1) ? 'v' : 'h');
	uint8_t n[16] = {'N', 'E', 'S', 0x1a};
	n[4] = h[4];
	n[5] = h[5];
	n[6] = uint8_t(((e.mapper & 0x0F) << 4) | (h[6] & 4) | (e.battery ? 2 : 0) | (e.mirroring == '4' ? 8 : 0) |
		(e.mirroring == 'v' ? 1 : 0));
	n[7] = uint8_t((e.mapper & 0xF0) | 0x08);
	n[8] = uint8_t((e.submapper << 4) | ((e.mapper >> 8) & 0x0F));
	n[9] = 0;
	n[10] = uint8_t((Shift(e.prg_nvram) << 4) | Shift(e.prg_ram));
	n[11] = uint8_t(Shift(e.chr_ram));
	n[12] = e.timing;
	memcpy(h, n, 16);
	if (what)
	{
		char buf[256];
		snprintf(buf, sizeof(buf), "mapper %d -> %u.%u, mirroring %c -> %c, battery %d -> %d, PRG-RAM %u + %u NV, CHR-RAM %u, %s",
			old_mapper, unsigned(e.mapper), unsigned(e.submapper), old_mirroring, e.mirroring, old_battery ? 1 : 0,
			e.battery ? 1 : 0, unsigned(e.prg_ram), unsigned(e.prg_nvram), unsigned(e.chr_ram),
			e.timing == 1 ? "PAL" : (e.timing == 3 ? "Dendy" : "NTSC"));
		*what = buf;
	}
	return true;
}
} // namespace fe
