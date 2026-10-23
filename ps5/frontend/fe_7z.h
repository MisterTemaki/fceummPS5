// NES FCEUmm PS5 frontend: NES games and Famicom Disk System disks inside a .7z, read with the LZMA SDK's C 7z decoder
// (third_party/lzma7z).
//
// The archive is read through the app's own stdio calls (fopen, fread, fseeko...): a .7z on a network share goes
// through netfs like any file. Listing an archive decodes nothing but its directory, which carries each file's size
// and CRC32 (the shelf names a game and finds its cover from it, as from a zip's directory). Extracting decodes the
// "folder" (7-Zip's solid block) that holds the file, whole, into memory: a block bigger than kMaxBlock is refused,
// and so is a file bigger than the caller's limit, before anything is decoded.
// What is decoded: LZMA, LZMA2, PPMd, BCJ, BCJ2, ARM/ARM64/ARMT/PPC/SPARC/IA64/RISC-V filters, Delta, stored. Not:
// BZip2, Deflate, Zstandard... (7-Zip's C++ methods), nor encrypted archives (no AES).
// SPDX-License-Identifier: MIT
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace fe
{
namespace sevenzip
{
// The biggest solid block decoded (the whole block is decoded to reach any file in it).
constexpr uint64_t kMaxBlock = 64ull << 20;

enum class Status
{
	Ok,
	NotFound,     // no such file / no file the caller wants
	ReadError,    // the file could not be opened or read (a share that dropped...)
	Broken,       // not a 7z archive, or a damaged one (a CRC that doesn't match, a cut file)
	Unsupported,  // a method the decoder doesn't have (BZip2, Deflate...)
	Encrypted,    // the file's data, or the archive's names, are encrypted (AES)
	TooBig,       // the file is over the caller's limit, its block over kMaxBlock, or the archive lists too many files
	NoMemory,
};
// For the log: "ok", "broken archive"...
const char* StatusName(Status s);

struct Entry
{
	std::string name; // UTF-8, with its folders ("Games/Kirby.nes")
	uint64_t size = 0;
	bool has_crc = false;
	uint32_t crc = 0;
	bool is_dir = false;
};

class Archive
{
public:
	Archive();
	~Archive();
	Archive(const Archive&) = delete;
	Archive& operator=(const Archive&) = delete;

	// Opens the archive and reads its directory (nothing is decompressed but the directory itself). cancel (when
	// given): once it turns true every read of the archive fails (ReadError), so a decode stops at its next read.
	// An archive with encrypted names is Encrypted; one that lists more than 65,536 files, TooBig.
	Status Open(const std::string& path, const std::atomic<bool>* cancel = nullptr);
	const std::vector<Entry>& Entries() const;
	// Decodes entry i into out. max_size: the biggest file accepted. An encrypted file is Encrypted whatever its size.
	// Everything the decoder allocates for the archive comes out of one budget of 136 MiB (the block, the directory, an
	// encoded header, PPMd's model): more is NoMemory.
	Status Extract(size_t i, std::vector<uint8_t>* out, uint64_t max_size);

private:
	struct Impl;
	std::unique_ptr<Impl> m;
};
} // namespace sevenzip
} // namespace fe
