// NES FCEUmm PS5: the 7z reader (frontend/fe_7z.cpp) on the archives of tests/7z/ (tests/make_7z_fixtures.py made them
// from the test game): each method the decoder has, a solid block of several files, what the directory says, and every
// way an archive can be refused.
//   test-7z <tests/7z> <the test game, as make_test_rom.py makes it>
// SPDX-License-Identifier: MIT
#include "fe_7z.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <zlib.h>

using fe::sevenzip::Archive;
using fe::sevenzip::Status;

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, label)                                                     \
	do                                                                         \
	{                                                                          \
		if (cond)                                                              \
			g_pass++;                                                          \
		else                                                                   \
		{                                                                      \
			g_fail++;                                                          \
			printf("  FAIL: %s (test_7z.cpp:%d)\n", label, __LINE__);          \
		}                                                                      \
	} while (0)

static std::string g_dir;
static std::vector<uint8_t> g_card;

static std::string P(const char* name)
{
	return g_dir + "/" + name;
}

static uint32_t Crc(const std::vector<uint8_t>& d)
{
	return uint32_t(crc32(0, d.data(), uInt(d.size())));
}

// The archive's one file is the test card, decoded right, its CRC in the directory.
static void OneCard(const char* file)
{
	Archive a;
	const Status st = a.Open(P(file));
	std::string label = std::string(file) + ": opens";
	CHECK(st == Status::Ok, label.c_str());
	if (st != Status::Ok)
		return;
	label = std::string(file) + ": one file, Card (USA).nes, its size and CRC in the directory";
	CHECK(a.Entries().size() == 1 && a.Entries()[0].name == "Card (USA).nes" && a.Entries()[0].size == g_card.size() &&
			  a.Entries()[0].has_crc && a.Entries()[0].crc == Crc(g_card),
		label.c_str());
	std::vector<uint8_t> out;
	label = std::string(file) + ": decoded, the same bytes as the card";
	CHECK(a.Extract(0, &out, 32u << 20) == Status::Ok && out == g_card, label.c_str());
}

static Status OpenStatus(const char* file)
{
	Archive a;
	return a.Open(P(file));
}

static Status ExtractStatus(const char* file, size_t i, uint64_t max = 32u << 20)
{
	Archive a;
	const Status st = a.Open(P(file));
	if (st != Status::Ok)
		return st;
	std::vector<uint8_t> out;
	return a.Extract(i, &out, max);
}

int main(int argc, char** argv)
{
	if (argc != 3)
	{
		fprintf(stderr, "usage: test-7z <tests/7z> <card.nes>\n");
		return 2;
	}
	g_dir = argv[1];
	if (FILE* f = fopen(argv[2], "rb"))
	{
		uint8_t b[4096];
		size_t n;
		while ((n = fread(b, 1, sizeof b, f)) > 0)
			g_card.insert(g_card.end(), b, b + n);
		fclose(f);
	}
	CHECK(g_card.size() == 24592, "the test game is there");

	for (const char* f : {"lzma.7z", "lzma2.7z", "ppmd.7z", "bcj.7z", "delta.7z"})
		OneCard(f);

	// a solid block of three files: each one out of the same block, in the archive's order
	{
		Archive a;
		CHECK(a.Open(P("solid.7z")) == Status::Ok && a.Entries().size() == 3, "solid.7z: three files");
		if (a.Entries().size() == 3)
		{
			CHECK(a.Entries()[0].name == "readme.txt" && a.Entries()[1].name == "Alpha (USA).nes" &&
					  a.Entries()[2].name == "Beta (Japan).fds",
				"solid.7z: the names in the archive's order");
			std::vector<uint8_t> one, two, text;
			CHECK(a.Extract(2, &two, 32u << 20) == Status::Ok && two.size() == a.Entries()[2].size && Crc(two) == a.Entries()[2].crc &&
					  memcmp(two.data(), "FDS\x1a", 4) == 0,
				"solid.7z: the last file (the disk) first");
			CHECK(a.Extract(1, &one, 32u << 20) == Status::Ok && one == g_card, "solid.7z: then the middle one");
			CHECK(a.Extract(0, &text, 32u << 20) == Status::Ok && text.size() == a.Entries()[0].size &&
					  memcmp(text.data(), "A test archive", 14) == 0,
				"solid.7z: and the text file");
		}
	}
	{
		Archive a;
		CHECK(a.Open(P("fds.7z")) == Status::Ok && a.Entries().size() == 2 && a.Entries()[0].name == "notes/readme.txt" &&
				  a.Entries()[1].name == "Disk (Japan).fds",
			"fds.7z: a name with its folder (UTF-8, '/')");
	}
	{
		Archive a;
		CHECK(a.Open(P("empty.7z")) == Status::Ok && a.Entries().empty(), "empty.7z: opens, no files");
		std::vector<uint8_t> out;
		CHECK(a.Extract(0, &out, 1u << 20) == Status::NotFound, "empty.7z: nothing to extract");
	}
	{
		Archive a;
		CHECK(a.Open(P("other.7z")) == Status::Ok && a.Entries().size() == 2, "other.7z: lists its .sfc and .txt (the shelf skips them)");
	}

	// refused, each with its reason, and nothing crashes
	CHECK(OpenStatus("missing.7z") == Status::NotFound, "a file that isn't there: not found");
	CHECK(OpenStatus("../make_7z_fixtures.py") == Status::Broken, "not a 7z archive (a text file): broken");
	CHECK(OpenStatus("truncated.7z") == Status::Broken, "truncated.7z (cut in half): broken");
	CHECK(ExtractStatus("corrupt.7z", 0) == Status::Broken, "corrupt.7z (its data changed): broken (CRC or data error)");
	CHECK(ExtractStatus("bzip2.7z", 0) == Status::Unsupported, "bzip2.7z: a method the decoder doesn't have");
	CHECK(ExtractStatus("aes.7z", 0) == Status::Encrypted, "aes.7z: encrypted data, refused as such");
	{
		Archive a;
		CHECK(a.Open(P("aes.7z")) == Status::Ok && a.Entries().size() == 1 && a.Entries()[0].name == "Card (USA).nes",
			"aes.7z: its names are readable");
	}
	CHECK(OpenStatus("aeshdr.7z") == Status::Encrypted, "aeshdr.7z (names encrypted): refused at open, as encrypted");
	CHECK(ExtractStatus("aesbig.7z", 0) == Status::Encrypted, "aesbig.7z: an encrypted file over the limit says encrypted, not too big");
	CHECK(ExtractStatus("ppmdbig.7z", 0) == Status::NoMemory, "ppmdbig.7z: a 256 MiB PPMd model, over the decoder's budget: refused");
	CHECK(OpenStatus("many.7z") == Status::TooBig, "many.7z: 70,000 files, more than an archive may list: refused at open");
	{
		std::atomic<bool> cancel{true};
		Archive a;
		CHECK(a.Open(P("lzma2.7z"), &cancel) == Status::ReadError, "a cancel set before the open: every read fails, nothing is decoded");
		std::atomic<bool> go{false};
		Archive b;
		CHECK(b.Open(P("lzma2.7z"), &go) == Status::Ok, "the same archive with the cancel flag down opens");
		go = true;
		std::vector<uint8_t> out;
		CHECK(b.Extract(0, &out, 32u << 20) == Status::ReadError && out.empty(), "a cancel set after the open: the decode stops at its next read");
	}
	CHECK(ExtractStatus("big.7z", 0) == Status::TooBig, "big.7z: a 33 MiB file over the 32 MiB limit, refused before decoding");
	CHECK(ExtractStatus("big.7z", 0, 34u << 20) == Status::Ok, "big.7z: decoded when the limit allows it");
	CHECK(ExtractStatus("bigblock.7z", 0) == Status::TooBig, "bigblock.7z: a small file in a 65 MiB solid block: refused");
	CHECK(ExtractStatus("lzma2.7z", 5) == Status::NotFound, "an index past the last file: not found");

	printf("7z: passed %d, failed %d\n", g_pass, g_fail);
	return g_fail ? 1 : 0;
}
