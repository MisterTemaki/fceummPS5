// NES FCEUmm PS5 frontend: NES games and Famicom Disk System disks inside a .7z (fe_7z.h).
// SPDX-License-Identifier: MIT

#include "fe_7z.h"

// every external name of the SDK copy carries the prefix fce7z_ (as in the other ports: it could never meet another
// LZMA SDK copy linked in later)
#include "fe7z_names.h"

#include "7z.h"
#include "7zCrc.h"

#include <sys/types.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <atomic>
#include <mutex>

namespace fe
{
namespace sevenzip
{
namespace
{
// One budget for everything the decoder allocates for an archive, its main and its temporary allocations together:
// the solid block (kMaxBlock), the directory, an encoded header, PPMd's model (7-Zip gives it 16 MiB by default, up to
// 192 MiB at its "ultra" level, which is refused). A damaged or hostile archive asking for more gets SZ_ERROR_MEM.
constexpr size_t kBudget = size_t(kMaxBlock) + (72u << 20); // 136 MiB

struct Budget
{
	ISzAlloc vt;
	size_t used = 0;
};

// each allocation carries its size in front, so Free gives it back to the budget
constexpr size_t kHead = 16;

void* Alloc(ISzAllocPtr p, size_t size)
{
	Budget* b = Z7_CONTAINER_FROM_VTBL(p, Budget, vt);
	if (size == 0 || size > kBudget - b->used)
		return nullptr;
	uint8_t* m = static_cast<uint8_t*>(malloc(size + kHead));
	if (!m)
		return nullptr;
	memcpy(m, &size, sizeof size);
	b->used += size;
	return m + kHead;
}

void Free(ISzAllocPtr p, void* address)
{
	if (!address)
		return;
	Budget* b = Z7_CONTAINER_FROM_VTBL(p, Budget, vt);
	uint8_t* m = static_cast<uint8_t*>(address) - kHead;
	size_t size;
	memcpy(&size, m, sizeof size);
	b->used -= size;
	free(m);
}

// The most files an archive may list: a few bytes of a crafted header can declare millions, whose entries would be
// made outside the budget. No NES collection comes near it.
constexpr UInt32 kMaxFiles = 1u << 16;

// The SDK's seekable input over a FILE*: the app's stdio calls, so a share's file is read through netfs. A cancel flag
// (the network naming pass stopping) makes the next read fail, so a decode never holds it up.
struct FileIn
{
	ISeekInStream vt;
	FILE* f = nullptr;
	bool error = false;
	const std::atomic<bool>* cancel = nullptr;
};

SRes FileRead(ISeekInStreamPtr p, void* buf, size_t* size)
{
	FileIn* in = Z7_CONTAINER_FROM_VTBL(p, FileIn, vt);
	if (in->cancel && in->cancel->load())
	{
		*size = 0;
		in->error = true;
		return SZ_ERROR_READ;
	}
	if (*size == 0)
		return SZ_OK;
	const size_t got = fread(buf, 1, *size, in->f);
	*size = got;
	if (got == 0 && ferror(in->f))
	{
		in->error = true;
		return SZ_ERROR_READ;
	}
	return SZ_OK;
}

SRes FileSeek(ISeekInStreamPtr p, Int64* pos, ESzSeek origin)
{
	FileIn* in = Z7_CONTAINER_FROM_VTBL(p, FileIn, vt);
	const int whence = origin == SZ_SEEK_SET ? SEEK_SET : origin == SZ_SEEK_CUR ? SEEK_CUR : SEEK_END;
	if (fseeko(in->f, off_t(*pos), whence) != 0)
	{
		in->error = true;
		return SZ_ERROR_READ;
	}
	const off_t at = ftello(in->f);
	if (at < 0)
	{
		in->error = true;
		return SZ_ERROR_READ;
	}
	*pos = Int64(at);
	return SZ_OK;
}

void CrcTableOnce()
{
	static std::once_flag once;
	std::call_once(once, [] { CrcGenerateTable(); });
}

void AppendUtf8(std::string& out, uint32_t c)
{
	if (c < 0x80)
		out += char(c);
	else if (c < 0x800)
	{
		out += char(0xC0 | (c >> 6));
		out += char(0x80 | (c & 0x3F));
	}
	else if (c < 0x10000)
	{
		out += char(0xE0 | (c >> 12));
		out += char(0x80 | ((c >> 6) & 0x3F));
		out += char(0x80 | (c & 0x3F));
	}
	else
	{
		out += char(0xF0 | (c >> 18));
		out += char(0x80 | ((c >> 12) & 0x3F));
		out += char(0x80 | ((c >> 6) & 0x3F));
		out += char(0x80 | (c & 0x3F));
	}
}

std::string Utf16ToUtf8(const UInt16* s, size_t n)
{
	std::string out;
	for (size_t i = 0; i < n && s[i]; i++)
	{
		uint32_t c = s[i];
		if (c >= 0xD800 && c < 0xDC00 && i + 1 < n && s[i + 1] >= 0xDC00 && s[i + 1] < 0xE000)
		{
			c = 0x10000 + ((c - 0xD800) << 10) + (s[i + 1] - 0xDC00);
			i++;
		}
		else if (c >= 0xD800 && c < 0xE000)
			c = 0xFFFD; // a lone surrogate: not a character
		AppendUtf8(out, c);
	}
	return out;
}

Status FromSRes(SRes r, bool read_error)
{
	if (read_error)
		return Status::ReadError;
	switch (r)
	{
		case SZ_OK: return Status::Ok;
		case SZ_ERROR_MEM: return Status::NoMemory;
		case SZ_ERROR_UNSUPPORTED: return Status::Unsupported;
		case SZ_ERROR_READ: return Status::ReadError;
		default: return Status::Broken; // DATA, CRC, INPUT_EOF, ARCHIVE, NO_ARCHIVE, FAIL...
	}
}

constexpr UInt32 kMethodAes = 0x06F10701;

// Whether the archive's header is itself encrypted (7-Zip's "encrypt file names"): its next header is then an encoded
// header (0x17) whose coders, listed in the clear, include AES. Matched as a coder's method ID: after a coder's flags
// byte whose low 4 bits say a 4-byte ID. Read through the same FILE* (a share's file through netfs).
bool HeaderIsEncrypted(FILE* f)
{
	uint8_t start[32];
	if (fseeko(f, 0, SEEK_SET) != 0 || fread(start, 1, sizeof start, f) != sizeof start || memcmp(start, k7zSignature, 6) != 0)
		return false;
	uint64_t offset = 0, size = 0;
	for (int i = 7; i >= 0; i--)
	{
		offset = (offset << 8) | start[12 + i];
		size = (size << 8) | start[20 + i];
	}
	if (size < 2 || size > 4096)
		return false; // an encoded header's record is short
	std::vector<uint8_t> h(size_t(size), 0);
	if (fseeko(f, off_t(32 + offset), SEEK_SET) != 0 || fread(h.data(), 1, h.size(), f) != h.size() || h[0] != 0x17)
		return false;
	static const uint8_t kAes[4] = {0x06, 0xF1, 0x07, 0x01};
	for (size_t i = 1; i + 4 <= h.size(); i++)
		if ((h[i - 1] & 0x0F) == 4 && memcmp(h.data() + i, kAes, 4) == 0)
			return true;
	return false;
}
} // namespace

const char* StatusName(Status s)
{
	switch (s)
	{
		case Status::Ok: return "ok";
		case Status::NotFound: return "no such file";
		case Status::ReadError: return "read error";
		case Status::Broken: return "not a 7z archive, or a damaged one";
		case Status::Unsupported: return "a method this decoder doesn't have, or encrypted names";
		case Status::Encrypted: return "encrypted";
		case Status::TooBig: return "too big";
		case Status::NoMemory: return "out of memory";
	}
	return "?";
}

struct Archive::Impl
{
	Budget budget;
	FileIn in;
	CLookToRead2 look;
	std::vector<Byte> look_buf;
	CSzArEx db;
	bool open = false;
	std::vector<Entry> entries;

	Impl()
	{
		in.vt.Read = FileRead;
		in.vt.Seek = FileSeek;
		budget.vt.Alloc = Alloc;
		budget.vt.Free = Free;
		SzArEx_Init(&db);
	}
	~Impl()
	{
		if (open)
			SzArEx_Free(&db, &budget.vt);
		if (in.f)
			fclose(in.f);
	}

	// Whether folder (solid block) `folder` is encrypted: one of its coders is 7-Zip's AES.
	bool FolderEncrypted(UInt32 folder) const
	{
		const CSzAr& ar = db.db;
		if (folder >= ar.NumFolders)
			return false;
		CSzData sd;
		sd.Data = ar.CodersData + ar.FoCodersOffsets[folder];
		sd.Size = ar.FoCodersOffsets[folder + 1] - ar.FoCodersOffsets[folder];
		CSzFolder f;
		if (SzGetNextFolderItem(&f, &sd) != SZ_OK)
			return false;
		for (UInt32 c = 0; c < f.NumCoders; c++)
			if (f.Coders[c].MethodID == kMethodAes)
				return true;
		return false;
	}
};

Archive::Archive() : m(new Impl) {}

Archive::~Archive() = default;

const std::vector<Entry>& Archive::Entries() const
{
	return m->entries;
}

Status Archive::Open(const std::string& path, const std::atomic<bool>* cancel)
{
	if (m->in.f)
		return Status::Broken; // one archive per object
	m->in.f = fopen(path.c_str(), "rb");
	if (!m->in.f)
		return errno == ENOENT ? Status::NotFound : Status::ReadError;
	m->in.cancel = cancel;
	CrcTableOnce();
	m->look_buf.resize(1 << 18);
	LookToRead2_CreateVTable(&m->look, False);
	m->look.realStream = &m->in.vt;
	m->look.buf = m->look_buf.data();
	m->look.bufSize = m->look_buf.size();
	LookToRead2_INIT(&m->look);
	const SRes r = SzArEx_Open(&m->db, &m->look.vt, &m->budget.vt, &m->budget.vt);
	if (r != SZ_OK)
	{
		SzArEx_Free(&m->db, &m->budget.vt);
		SzArEx_Init(&m->db);
		const Status st = FromSRes(r, m->in.error);
		if (st == Status::Unsupported && !(cancel && cancel->load()))
		{
			clearerr(m->in.f);
			if (HeaderIsEncrypted(m->in.f))
				return Status::Encrypted;
		}
		return st;
	}
	m->open = true;
	if (m->db.NumFiles > kMaxFiles)
		return Status::TooBig; // a list this long is no game's (and its entries would be outside the budget)
	std::vector<UInt16> name;
	for (UInt32 i = 0; i < m->db.NumFiles; i++)
	{
		Entry e;
		const size_t len = SzArEx_GetFileNameUtf16(&m->db, i, nullptr);
		name.assign(len + 1, 0);
		SzArEx_GetFileNameUtf16(&m->db, i, name.data());
		e.name = Utf16ToUtf8(name.data(), len);
		e.is_dir = SzArEx_IsDir(&m->db, i);
		e.size = SzArEx_GetFileSize(&m->db, i);
		e.has_crc = SzBitWithVals_Check(&m->db.CRCs, i);
		e.crc = e.has_crc ? m->db.CRCs.Vals[i] : 0;
		m->entries.push_back(std::move(e));
	}
	return Status::Ok;
}

Status Archive::Extract(size_t i, std::vector<uint8_t>* out, uint64_t max_size)
{
	if (!m->open || i >= m->entries.size() || m->entries[i].is_dir)
		return Status::NotFound;
	const Entry& e = m->entries[i];
	out->clear();
	const UInt32 folder = m->db.FileToFolder[i];
	if (folder != UInt32(-1) && m->FolderEncrypted(folder))
		return Status::Encrypted; // first: whatever its size, it can't be read
	if (e.size > max_size)
		return Status::TooBig;
	if (e.size == 0)
		return Status::Ok;
	if (folder == UInt32(-1))
		return Status::Broken;
	// the whole solid block is decoded: its size first
	if (SzAr_GetFolderUnpackSize(&m->db.db, folder) > kMaxBlock)
		return Status::TooBig;
	UInt32 block = UInt32(-1);
	Byte* buf = nullptr;
	size_t buf_size = 0, offset = 0, got = 0;
	m->in.error = false;
	const SRes r = SzArEx_Extract(&m->db, &m->look.vt, UInt32(i), &block, &buf, &buf_size, &offset, &got, &m->budget.vt,
		&m->budget.vt);
	Status st = FromSRes(r, m->in.error);
	if (st == Status::Ok && (got != e.size || offset + got > buf_size))
		st = Status::Broken;
	if (st == Status::Ok)
		out->assign(buf + offset, buf + offset + got);
	ISzAlloc_Free(&m->budget.vt, buf);
	return st;
}
} // namespace sevenzip
} // namespace fe
