// NES FCEUmm PS5 frontend: the game library -- every ROM under the ROM folders, with its system and official name.
//
// The system comes from the file extension (inside a .zip or .7z, from the ROM in it): .nes/.unf/.unif are NES games,
// .fds Famicom Disk System disks. A game is then named the way libretro names it:
//   1. its file name, when it is already a No-Intro name ("Super Mario Bros. (World).nes");
//   2. otherwise the CRC32 of the ROM (the whole file, then without its header: iNES/NES 2.0 and a trainer, or
//      fwNES's for a disk), looked up in the table built into the app (data/nointro.tsv: No-Intro; NES games come
//      in it with and without their header; tools/make_gamedb.py makes it);
//   3. otherwise the file name, loosely: "super mario bros.nes" -> the best entry with that title (USA first,
//      then World, Europe, Japan).
//
// SPDX-License-Identifier: MIT
#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace fe
{
enum class System : uint8_t
{
	Nes, // NES / Famicom (cartridges)
	Fds, // Famicom Disk System
	Count
};

// The shelf's tabs: every game, then the games by the first character of their title -- "#" (a digit or anything
// that isn't a letter) and A to Z. Only the tabs that have games are shown.
enum class Family : uint8_t
{
	All,
	Hash, // titles that start with a digit (or with a symbol)
	A, // ... up to Z: Family(int(Family::A) + letter)
	Count = 28,
};
const char* FamilyName(Family f); // "All games", "#", "A"... "Z"
Family FamilyOf(const std::string& title); // its letter's tab ("The Legend of Zelda" -> T, "1942" -> #)

struct SystemInfo
{
	const char* id; // "nes": the table's and the cover cache's tag
	const char* name; // "NES"
	const char* thumbs; // the libretro-thumbnails repository
	const char* folder; // "NES": its folder in roms/ and in covers/
};
const SystemInfo& Info(System s);

// Creates roms/<folder> and covers/<folder> for every system (NES, FDS).
void PrepareFolders();

// ".nes" -> System::Nes; false for anything that isn't a game we list.
bool SystemForExt(const std::string& ext, System* out);

struct GameInfo
{
	std::string path; // full path
	std::string file_base; // file name without extension
	std::string ext; // ".nes", ".zip", ".7z"... lower case
	System system = System::Nes;
	std::string nointro; // official name, "" until known (or unknown)
	std::string title; // what the shelf shows
	std::string region; // "USA", "Europe"... from the name's tags
	bool on_usb = false;
	bool on_network = false; // on a share (/smb/..., /nfs/...): named without reading the ROM (netfs)
	bool name_by_crc = false; // the name came from the CRC (not the file name)
	bool crc_pending = false; // on a share, named from its file name only so far: NetNaming reads its CRC
};

// The table built into the app.
namespace gamedb
{
size_t Count();
// "" when unknown. *found_in: the system whose table knew it.
std::string ByCrc(System s, uint32_t crc, System* found_in);
// Exact No-Intro name ("Super Mario Bros. (World)") -> itself, or "".
std::string Exact(System s, const std::string& name, System* found_in);
// Loose: title without tags, any case ("super mario bros") -> best regional entry, or "".
std::string Loose(System s, const std::string& file_base, System* found_in);
// "Super Mario Bros. (World)" -> "Super Mario Bros."; "Legend of Zelda, The (...)" -> "The Legend of Zelda"
std::string Title(const std::string& nointro);
std::string Region(const std::string& nointro);
} // namespace gamedb

// The ROM's CRC32s: of the whole file, and without its header (= whole when it has none). For a .zip or .7z, of the
// ROM inside (the CRC its directory keeps, when the game table knows it); *inner_ext gets that ROM's extension. False
// if it can't be read. cancel (when given): stops the read when it turns true (false is returned). certain (when
// given): false returned for a reason of the file's own, read without an error (a .7z with no game, encrypted, too
// big...): it may be remembered.
bool RomCrc32(const std::string& path, uint32_t* whole, uint32_t* body, std::string* inner_ext = nullptr,
	const std::atomic<bool>* cancel = nullptr, bool* certain = nullptr);

// The folders to look for games in: OrbisRomRoots() plus the network shares that are connected (in memory, no I/O).
std::vector<std::string> RomRoots();

// Names the games on shares by their ROM's CRC, in the background (Snes9x PS5's design, by thatboialex). A scan does
// not read network ROMs (it would make a big library crawl); this does, one at a time, only for the games with
// crc_pending (a zip or 7z: its directory, which also gives its system), and remembers each CRC in crc-cache.txt, so
// the next ScanGames names them. Add() starts or extends the pass; it stops by itself when a game starts
// (netfs_realtime) and when Stop() or the destructor is called (leaving the shelf).
class NetNaming
{
public:
	NetNaming();
	~NetNaming();
	void Add(const std::vector<GameInfo>& games);
	void Stop();
	int Resolved() const; // ROMs read so far (named or not)
	bool Busy() const;

private:
	struct Impl;
	std::unique_ptr<Impl> m_i;
};

// Archives of games: .zip and .7z (fe_7z.h). The first NES game or Famicom Disk System disk inside, in the archive's
// order, is the game; an archive with none in it is not listed.
bool IsArchiveExt(const std::string& ext);
// The system of a .zip or .7z: the extension of the first game inside. False if none.
// cancel: stops the read (a .7z's); certain: as for RomCrc32.
bool ArchiveSystem(const std::string& path, System* out, const std::atomic<bool>* cancel = nullptr, bool* certain = nullptr);
// The first game inside a .zip or .7z (its name in the archive) and its bytes (32 MiB at most). False if none can be
// read; *why (when given) then says why in a sentence for the player (English: T() it), for an archive that can't be
// read, or a .7z that is damaged, encrypted, packed with a method the app can't unpack, or too big. Left alone when
// there is simply no game inside.
bool ReadFromArchive(const std::string& path, std::string* inner, std::vector<uint8_t>* data, std::string* why = nullptr,
	const std::atomic<bool>* cancel = nullptr, bool* certain = nullptr);

// Every ROM under the ROM folders (sub-folders included, 4 levels), sorted by title. Names that need a
// CRC are resolved here too, with a cache (/data/fceumm/covers/crc-cache.txt) so each ROM is read once.
std::vector<GameInfo> ScanGames();
} // namespace fe
