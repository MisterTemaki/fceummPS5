// NES FCEUmm PS5 frontend: the core and its libretro callbacks (fe_emu.h).
//
// Frame pacing, as in Snes9x PS5:
//   - 60 Hz games (NTSC, 60.1 Hz): Present waits for the flip, so the console's vsync paces the emulation, and
//     the resampler (FCEUmm's 48 kHz -> the output's 48 kHz) stretches the sound by up to 0.5% to keep about 60 ms
//     queued.
//   - 50 Hz games (PAL, Dendy): the audio clock paces instead (wait while more than 60 ms is queued); the flips don't
//     wait (each frame still waits, before writing, for the buffer it last flipped).
//   - In any case, if more than 120 ms is queued (vsync not blocking for some reason), wait on audio.
//   - Fast forward (hold R2): several frames per flip, no sound.
//
// SPDX-License-Identifier: MIT

#include "fe_emu.h"

#include "ProsperoNotify.h"
#include "fe_games.h"
#include "fe_i18n.h"
#include "fe_nes.h"
#include "fe_nesdb.h"
#include "fe_palettes.h"
#include "fe_settings.h"
#include "fe_text.h"

#include "OrbisPaths.h"
#include "ProsperoAudio.h"
#include "ProsperoCrash.h"
#include "ProsperoInput.h"
#include "ProsperoSce.h"
#include "ProsperoVideo.h"

#include "libretro.h"

#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <deque>
#include <map>
#include <vector>

namespace emu
{
const Choice kAspects[] = {
	{"TV (8:7 pixels)", "8:7 PAR"},
	{"4:3", "4:3"},
	{"Square pixels", "PP"},
	{"16:9", ""},
};
const int kAspectCount = int(sizeof(kAspects) / sizeof(kAspects[0]));

const Palette kPalettes[] = {
	{"Mesen", "", 0},
	{"Nestopia RGB", "", 1},
	{"Original Hardware (FirebrandX)", "", 2},
	{"PVM Style (FirebrandX)", "", 3},
	{"Unsaturated v6 (FirebrandX)", "", 4},
	{"Nostalgia (FirebrandX)", "", 5},
	{"Hybrid (Nestopia)", "", 6},
	{"NTSC (Nestopia)", "", 7},
	{"FCEUX (FCEUmm's default)", "default", -1},
	{"Nintendo RGB PPU", "rgb", -1},
	{"Sony CXA2025AS US", "sony-cxa2025as-us", -1},
	{"NESCAP (RGBSource)", "nescap", -1},
	{"Wavebeam", "wavebeam", -1},
	{"Composite Direct (FirebrandX)", "composite-direct-fbx", -1},
	{"Smooth V2 (FirebrandX)", "smooth-v2-fbx", -1},
	{"NES Classic (FirebrandX)", "nes-classic-fbx", -1},
	{"PVM Style D93 (FirebrandX)", "pvm-style-d93-fbx", -1},
	{"NTSC Hardware (FirebrandX)", "ntsc-hardware-fbx", -1},
	{"Digital Prime (FirebrandX)", "digital-prime-fbx", -1},
	{"Magnum (FirebrandX)", "magnum-fbx", -1},
	{"YUV-V3 (FirebrandX)", "yuv-v3", -1},
	{"Unsaturated-Final (FirebrandX)", "unsaturated-final", -1},
	{"Real (AspiringSquire)", "asqrealc", -1},
	{"Restored Wii VC", "restored-wii-vc", -1},
	{"Wii Virtual Console", "wii-vc", -1},
	{"Royaltea (PVM-2530)", "royaltea", -1},
	{"Mugicha", "mugicha", -1},
	{"PAL", "pal", -1},
};
const int kPaletteCount = int(sizeof(kPalettes) / sizeof(kPalettes[0]));

const Choice kNtscFilters[] = {
	{"Off", "disabled"},
	{"Composite", "composite"},
	{"S-Video", "svideo"},
	{"RGB", "rgb"},
	{"Monochrome", "monochrome"},
};
const int kNtscFilterCount = int(sizeof(kNtscFilters) / sizeof(kNtscFilters[0]));

// value: lines hidden at the top and the bottom, pixels hidden at the left and the right
const Choice kBorders[] = {
	{"Hide 8 lines top and bottom (a TV)", "8,0"},
	{"Show everything", "0,0"},
	{"Hide 8 pixels on every edge", "8,8"},
};
const int kBorderCount = int(sizeof(kBorders) / sizeof(kBorders[0]));

const Choice kSoundQualities[] = {
	{"Low", "Low"},
	{"High", "High"},
	{"Very high (the most accurate)", "Very High"},
};
const int kSoundQualityCount = int(sizeof(kSoundQualities) / sizeof(kSoundQualities[0]));

const Choice kRegions[] = {
	{"Auto", "Auto"},
	{"NTSC (USA, Japan)", "NTSC"},
	{"PAL (Europe)", "PAL"},
	{"Dendy", "Dendy"},
};
const int kRegionCount = int(sizeof(kRegions) / sizeof(kRegions[0]));

const Choice kRamStates[] = {
	{"$FF (FCEUmm's)", "fill $ff"},
	{"$00", "fill $00"},
	{"Random", "random"},
};
const int kRamStateCount = int(sizeof(kRamStates) / sizeof(kRamStates[0]));

const Choice kTurboSpeeds[] = {
	{"30 presses a second", "1"},
	{"20 presses a second", "2"},
	{"15 presses a second", "3"},
	{"10 presses a second", "5"},
	{"6 presses a second", "10"},
	{"4 presses a second", "15"},
	{"2 presses a second", "30"},
	{"1 press a second", "60"},
};
const int kTurboSpeedCount = int(sizeof(kTurboSpeeds) / sizeof(kTurboSpeeds[0]));

const PadButton kPs5Buttons[] = {
	{"Cross", SCE_PAD_BUTTON_CROSS},
	{"Circle", SCE_PAD_BUTTON_CIRCLE},
	{"Square", SCE_PAD_BUTTON_SQUARE},
	{"Triangle", SCE_PAD_BUTTON_TRIANGLE},
	{"L1", SCE_PAD_BUTTON_L1},
	{"R1", SCE_PAD_BUTTON_R1},
	{"OPTIONS", SCE_PAD_BUTTON_OPTIONS},
	{"Touchpad", SCE_PAD_BUTTON_TOUCH_PAD},
	{"None", 0},
};
const int kPs5ButtonCount = int(sizeof(kPs5Buttons) / sizeof(kPs5Buttons[0]));

// FCEUmm's RetroPad (libretro.c): B / A, Y / X = turbo B / A, Start, Select. The disk drive and the coin slot are the
// frontend's (fe_nes.h): FCEUmm's own L / R / R2 for them press once a frame they are held.
const ConsoleButton kConsoleButtons[kConsoleButtonCount] = {
	{"A", "btn_a", RETRO_DEVICE_ID_JOYPAD_A, 1},
	{"B", "btn_b", RETRO_DEVICE_ID_JOYPAD_B, 0},
	{"Turbo A", "btn_turbo_a", RETRO_DEVICE_ID_JOYPAD_X, 3},
	{"Turbo B", "btn_turbo_b", RETRO_DEVICE_ID_JOYPAD_Y, 2},
	{"Start", "btn_start", RETRO_DEVICE_ID_JOYPAD_START, 6},
	{"Select", "btn_select", RETRO_DEVICE_ID_JOYPAD_SELECT, 7},
	{"Disk: next side (FDS)", "btn_disk_side", -1, 4},
	{"Disk: in / out (FDS)", "btn_disk_insert", -1, 5},
	{"Insert coin (VS. System)", "btn_coin", -1, 8},
};
} // namespace emu

namespace
{
// printf into a std::string (the translated formats)
std::string Fmt(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
std::string Fmt(const char* fmt, ...)
{
	char buf[512];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	return buf;
}

constexpr int kTargetQueued = ps5audio::kRate * 60 / 1000; // 60 ms of sound
constexpr int kRewindEvery = 3; // frames between rewind snapshots
constexpr size_t kRewindBytes = 192u * 1024 * 1024;

double Now()
{
	timespec ts = {};
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

std::string Lower(std::string s)
{
	for (char& c : s)
		c = char(tolower(uint8_t(c)));
	return s;
}

std::string ExtOf(const std::string& p)
{
	const size_t dot = p.find_last_of('.');
	const size_t slash = p.find_last_of('/');
	if (dot == std::string::npos || (slash != std::string::npos && dot < slash))
		return "";
	return Lower(p.substr(dot));
}

bool FileExists(const std::string& p)
{
	struct stat st = {};
	return stat(p.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

bool ReadFile(const std::string& path, std::vector<uint8_t>& out)
{
	FILE* f = fopen(path.c_str(), "rb");
	if (!f)
		return false;
	out.clear();
	uint8_t buf[65536];
	size_t n;
	while ((n = fread(buf, 1, sizeof(buf), f)) > 0)
		out.insert(out.end(), buf, buf + n);
	fclose(f);
	return true;
}

// data -> path.part, flushed to the disk (fsync) and closed without error, then renamed over path: the old file or
// the whole new one, never a cut one (a full disk or an I/O error shows up at fflush / fsync / fclose).
bool WriteFileAtomic(const std::string& path, const void* data, size_t size)
{
	const std::string tmp = path + ".part";
	FILE* f = fopen(tmp.c_str(), "wb");
	if (!f)
		return false;
	bool ok = fwrite(data, 1, size, f) == size;
	ok = fflush(f) == 0 && ok;
	ok = fsync(fileno(f)) == 0 && ok;
	ok = fclose(f) == 0 && ok;
	if (!ok || rename(tmp.c_str(), path.c_str()) != 0)
	{
		remove(tmp.c_str());
		return false;
	}
	return true;
}

uint64_t Fnv(const uint8_t* p, size_t n)
{
	uint64_t h = 1469598103934665603ull;
	for (size_t i = 0; i < n; i++)
		h = (h ^ p[i]) * 1099511628211ull;
	return h;
}

struct State
{
	bool inited = false;
	bool loaded = false;
	std::string path, name, dir, ext; // the game; ext without the dot
	fe::System system = fe::System::Nes;
	std::vector<uint8_t> rom; // the game's file (or the ROM in its .zip), its header corrected (fe_nesdb.h)
	retro_game_info_ext info_ext = {};
	std::string sys_dir, save_dir;

	// the core's options, as libretro variables
	std::map<std::string, std::string> opts;
	bool opts_changed = false;

	// video
	unsigned pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
	int palette_frames = 0; // frames left to set our palette again (after a start or an option change)
	std::vector<uint32_t> frame;
	int fw = 0, fh = 0;
	bool new_frame = false;
	double fps = 60.0, core_aspect = 4.0 / 3.0;
	double sample_rate = 44100.0;

	// sound: the core's samples of this frame, and the resampler's state
	std::vector<int16_t> in;
	bool mute = false; // fast forward, rewind: drop the sound
	double frac = 0;
	int16_t prev_l = 0, prev_r = 0;
	std::vector<int16_t> out;
	std::vector<int16_t> silence; // the zeros that refill a dry ring
	int pads_applied = -1; // the pad type / adapter last given to the core

	// pads
	ps5input::PadState pads[ps5input::kMaxPads];
	uint32_t prev_p1 = 0;
	bool wait_release = true;

	// the disk drive: the frame the next side goes in (0: none pending); the frontend's buttons last frame
	uint64_t disk_insert_at = 0;
	uint32_t prev_extra = 0;

	// fast forward, rewind
	bool turbo = false, rewinding = false;
	std::deque<std::vector<uint8_t>> rewind;
	size_t rewind_bytes = 0;
	int rewind_tick = 0;

	// saves
	uint64_t sram_hash = 0;
	size_t sram_size = 0; // the battery RAM's full size, taken before the core runs (then it reports a trimmed size)
	double next_sram_check = 0;

	// messages and the FPS counter
	std::string osd;
	double osd_until = 0;
	bool overlay_was_drawn = false;
	int fps_frames = 0;
	double fps_since = 0, fps_shown = 0;
	uint64_t frames = 0;
	double next_stats = 0;
	int stats_reports = 0;
};
State g;

// ---- libretro callbacks -------------------------------------------------------------------------------------
void CoreLog(enum retro_log_level level, const char* fmt, ...)
{
	char buf[1024];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	size_t n = strlen(buf);
	while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r'))
		buf[--n] = 0;
	static const char* const kLevel[] = {"debug", "info", "warn", "error"};
	if (level == RETRO_LOG_DEBUG)
		return;
	OrbisLog("[core] %s%s%s", level == RETRO_LOG_INFO ? "" : kLevel[level < 4 ? level : 3],
		level == RETRO_LOG_INFO ? "" : ": ", buf);
}

bool Environment(unsigned cmd, void* data)
{
	switch (cmd)
	{
		case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
			*static_cast<const char**>(data) = g.sys_dir.c_str();
			return true;
		case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
			*static_cast<const char**>(data) = g.save_dir.c_str();
			return true;
		case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
		{
			const unsigned f = *static_cast<const unsigned*>(data);
			if (f != RETRO_PIXEL_FORMAT_RGB565 && f != RETRO_PIXEL_FORMAT_0RGB1555 && f != RETRO_PIXEL_FORMAT_XRGB8888)
				return false;
			g.pixel_format = f;
			return true;
		}
		case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
			static_cast<retro_log_callback*>(data)->log = CoreLog;
			return true;
		case RETRO_ENVIRONMENT_GET_VARIABLE:
		{
			retro_variable* v = static_cast<retro_variable*>(data);
			auto it = v->key ? g.opts.find(v->key) : g.opts.end();
			if (it == g.opts.end())
			{
				v->value = nullptr;
				return false;
			}
			v->value = it->second.c_str();
			return true;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
			*static_cast<bool*>(data) = g.opts_changed;
			g.opts_changed = false;
			return true;
		case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
			*static_cast<unsigned*>(data) = 0; // the core then uses SET_VARIABLES (accepted below)
			return true;
		case RETRO_ENVIRONMENT_GET_CAN_DUPE:
			*static_cast<bool*>(data) = true;
			return true;
		case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
			return true;
		case RETRO_ENVIRONMENT_GET_GAME_INFO_EXT:
			if (!g.loaded && g.path.empty())
				return false;
			*static_cast<const retro_game_info_ext**>(data) = &g.info_ext;
			return true;
		case RETRO_ENVIRONMENT_SET_GEOMETRY:
		{
			const retro_game_geometry* geo = static_cast<const retro_game_geometry*>(data);
			if (geo->aspect_ratio > 0.1f)
				g.core_aspect = geo->aspect_ratio;
			return true;
		}
		case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
		{
			const retro_system_av_info* av = static_cast<const retro_system_av_info*>(data);
			if (av->geometry.aspect_ratio > 0.1f)
				g.core_aspect = av->geometry.aspect_ratio;
			if (av->timing.fps > 1)
				g.fps = av->timing.fps;
			if (av->timing.sample_rate > 1000)
				g.sample_rate = av->timing.sample_rate;
			OrbisLog("[emu] av info: %.3f fps, %.0f Hz", g.fps, g.sample_rate);
			return true;
		}
		case RETRO_ENVIRONMENT_SET_MESSAGE:
		{
			const retro_message* m = static_cast<const retro_message*>(data);
			if (m && m->msg)
			{
				// FCEUmm's disk messages ("Disk 1 of 2 Side A Inserted"): shown in the interface's language
				int disk = 0, disks = 0;
				char side[8] = {}, what[16] = {};
				if (sscanf(m->msg, "Disk %d of %d Side %7s %15s", &disk, &disks, side, what) == 4)
				{
					const char* f = !strcmp(what, "Inserted") ? "Disk %d of %d Side %s Inserted"
						: !strcmp(what, "Ejected")            ? "Disk %d of %d Side %s Ejected"
						: !strcmp(what, "Selected")           ? "Disk %d of %d Side %s Selected"
															  : nullptr;
					if (f)
					{
						emu::Osd(Fmt(fe::T(f), disk, disks, side));
						return true;
					}
				}
				emu::Osd(m->msg);
			}
			return true;
		}
		// accepted and ignored
		case RETRO_ENVIRONMENT_SET_VARIABLES:
		case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
		case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
		case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
		case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
		case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
		case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
		case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:
		case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
		case RETRO_ENVIRONMENT_SET_MINIMUM_AUDIO_LATENCY:
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
			return true;
		default:
			return false;
	}
}

inline uint32_t Expand565(uint16_t c)
{
	const uint32_t r = (c >> 11) & 31, gg = (c >> 5) & 63, b = c & 31;
	return 0xff000000u | (((r << 3) | (r >> 2)) << 16) | (((gg << 2) | (gg >> 4)) << 8) | ((b << 3) | (b >> 2));
}

inline uint32_t Expand555(uint16_t c)
{
	const uint32_t r = (c >> 10) & 31, gg = (c >> 5) & 31, b = c & 31;
	return 0xff000000u | (((r << 3) | (r >> 2)) << 16) | (((gg << 3) | (gg >> 2)) << 8) | ((b << 3) | (b >> 2));
}

void Video(const void* data, unsigned w, unsigned h, size_t pitch)
{
	if (!data || w == 0 || h == 0)
		return; // a duplicated frame: keep the last one
	g.fw = int(w);
	g.fh = int(h);
	g.frame.resize(size_t(w) * h);
	const uint8_t* src = static_cast<const uint8_t*>(data);
	for (unsigned y = 0; y < h; y++)
	{
		uint32_t* out = g.frame.data() + size_t(y) * w;
		if (g.pixel_format == RETRO_PIXEL_FORMAT_XRGB8888)
		{
			const uint32_t* in = reinterpret_cast<const uint32_t*>(src + y * pitch);
			for (unsigned x = 0; x < w; x++)
				out[x] = in[x] | 0xff000000u;
		}
		else
		{
			const uint16_t* in = reinterpret_cast<const uint16_t*>(src + y * pitch);
			if (g.pixel_format == RETRO_PIXEL_FORMAT_RGB565)
				for (unsigned x = 0; x < w; x++)
					out[x] = Expand565(in[x]);
			else
				for (unsigned x = 0; x < w; x++)
					out[x] = Expand555(in[x]);
		}
	}
	g.new_frame = true;
}

void AudioSample(int16_t l, int16_t r)
{
	if (g.mute)
		return;
	g.in.push_back(l);
	g.in.push_back(r);
}

size_t AudioBatch(const int16_t* data, size_t frames)
{
	if (!g.mute)
		g.in.insert(g.in.end(), data, data + frames * 2);
	return frames;
}

void InputPoll()
{
	ps5input::Poll();
	for (int p = 0; p < ps5input::kMaxPads; p++)
		g.pads[p] = ps5input::Snapshot(p);
}

// The RetroPad FCEUmm reads, from the player's button layout (Settings, CONTROLS; by position by default:
// Cross/Circle = B/A, Square/Triangle = turbo B/A, OPTIONS = Start, touchpad = Select).
uint16_t RetroPadBits(const ps5input::PadState& p, bool dpad_off)
{
	if (!p.connected)
		return 0;
	const fe::Settings& cfg = fe::Config();
	uint16_t bits = 0;
	for (int i = 0; i < emu::kConsoleButtonCount; i++)
	{
		const int b = cfg.buttons[i];
		const unsigned bit = b >= 0 && b < emu::kPs5ButtonCount ? emu::kPs5Buttons[b].bit : 0;
		if (bit && (p.raw_buttons & bit) && emu::kConsoleButtons[i].retro_id >= 0)
			bits |= uint16_t(1u << emu::kConsoleButtons[i].retro_id);
	}
	struct Dir
	{
		unsigned id;
		uint32_t bit;
	};
	static const Dir kDirs[] = {
		{RETRO_DEVICE_ID_JOYPAD_UP, SCE_PAD_BUTTON_UP},
		{RETRO_DEVICE_ID_JOYPAD_DOWN, SCE_PAD_BUTTON_DOWN},
		{RETRO_DEVICE_ID_JOYPAD_LEFT, SCE_PAD_BUTTON_LEFT},
		{RETRO_DEVICE_ID_JOYPAD_RIGHT, SCE_PAD_BUTTON_RIGHT},
	};
	if (!dpad_off)
		for (const Dir& d : kDirs)
			if (p.buttons & d.bit) // the D-pad includes the left stick
				bits |= uint16_t(1u << d.id);
	return bits;
}

int16_t InputState(unsigned port, unsigned device, unsigned index, unsigned id)
{
	if (port >= unsigned(ps5input::kMaxPads) || (device & RETRO_DEVICE_MASK) != RETRO_DEVICE_JOYPAD || index != 0)
		return 0;
	// L2 is the hot-key modifier for player 1: the D-pad stays with the hot keys while it is held.
	// While the buttons that closed a menu (Cross, Circle) or opened it (L3 + R3) are still held, player 1's pad
	// is not passed on: Resume with Cross must not press B in the game.
	if (port == 0 && g.wait_release)
		return 0;
	const bool l2 = port == 0 && (g.pads[0].raw_buttons & SCE_PAD_BUTTON_L2) != 0;
	const uint16_t bits = RetroPadBits(g.pads[port], l2);
	if (id == RETRO_DEVICE_ID_JOYPAD_MASK)
		return int16_t(bits);
	return id < 16 ? int16_t((bits >> id) & 1) : 0;
}

// ---- sound: the core's 44.1 kHz -> 48 kHz, the rate steered by the ring's fill ---------------------------------
void FlushAudio()
{
	const size_t frames = g.in.size() / 2;
	if (frames == 0)
		return;
	const fe::Settings& cfg = fe::Config();
	if (!cfg.audio || g.mute || !ps5audio::Available())
	{
		g.in.clear();
		return;
	}
	int queued = ps5audio::Queued();
	if (queued < kTargetQueued / 4)
	{
		// the ring ran (nearly) dry: a game just started, or came back from a menu, or the frame was late. Fill
		// it with silence up to the target at once; the rate control alone (0.5%) would take ~10 s to get there,
		// and play crackling meanwhile.
		g.silence.assign(size_t(kTargetQueued - queued) * 2, 0);
		ps5audio::Push(g.silence.data(), kTargetQueued - queued);
		queued = kTargetQueued;
	}
	double adj = double(kTargetQueued - queued) / kTargetQueued;
	adj = 1.0 + std::max(-1.0, std::min(1.0, adj)) * 0.005;
	const double step = g.sample_rate / (ps5audio::kRate * adj); // input frames per output frame
	const int vol = cfg.volume * 256 / 100;
	g.out.clear();
	double pos = g.frac; // position in [prev, in...]: 0 = prev, 1 = in[0]
	while (pos < double(frames))
	{
		const int i = int(pos);
		const int t = int((pos - i) * 256);
		const int16_t l0 = i == 0 ? g.prev_l : g.in[size_t(i - 1) * 2];
		const int16_t r0 = i == 0 ? g.prev_r : g.in[size_t(i - 1) * 2 + 1];
		const int16_t l1 = g.in[size_t(i) * 2];
		const int16_t r1 = g.in[size_t(i) * 2 + 1];
		const int l = (l0 * (256 - t) + l1 * t) >> 8;
		const int r = (r0 * (256 - t) + r1 * t) >> 8;
		g.out.push_back(int16_t(std::max(-32768, std::min(32767, l * vol >> 8))));
		g.out.push_back(int16_t(std::max(-32768, std::min(32767, r * vol >> 8))));
		pos += step;
	}
	g.frac = pos - double(frames);
	g.prev_l = g.in[(frames - 1) * 2];
	g.prev_r = g.in[(frames - 1) * 2 + 1];
	g.in.clear();
	ps5audio::Push(g.out.data(), int(g.out.size() / 2));
}

// ---- saves ------------------------------------------------------------------------------------------------
// Saves are kept per system (saves/NES/<game>.srm, states/FDS/<game>.state3...): a disk and a cartridge can share a
// name, and one game must never load the other's battery RAM or state.
std::string SaveDir(const char* kind)
{
	return OrbisDir(kind) + "/" + fe::Info(g.system).folder;
}

std::string SramPath()
{
	return SaveDir("saves") + "/" + g.name + ".srm";
}

std::string StatePath(int slot)
{
	return SaveDir("states") + "/" + g.name + ".state" + std::to_string(slot);
}

void MakeSaveDirs()
{
	OrbisMkdirs(SaveDir("saves"));
	OrbisMkdirs(SaveDir("states"));
}

void LoadSram()
{
	uint8_t* mem = static_cast<uint8_t*>(retro_get_memory_data(RETRO_MEMORY_SAVE_RAM));
	// the size the core reports before the first frame, kept for the whole game
	const size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
	g.sram_size = mem ? size : 0;
	g.sram_hash = mem && size ? Fnv(mem, size) : 0;
	if (!mem || !size)
		return;
	std::vector<uint8_t> data;
	if (ReadFile(SramPath(), data) && !data.empty())
	{
		memcpy(mem, data.data(), std::min(size, data.size()));
		g.sram_hash = Fnv(mem, size);
		OrbisLog("[emu] battery save loaded: %s (%zu bytes)", SramPath().c_str(), data.size());
	}
}

// Writes the battery save when it changed (or when `force`).
void SaveSram(bool force)
{
	uint8_t* mem = static_cast<uint8_t*>(retro_get_memory_data(RETRO_MEMORY_SAVE_RAM));
	const size_t size = g.sram_size;
	if (!mem || !size)
		return;
	const uint64_t h = Fnv(mem, size);
	if (h == g.sram_hash && !force)
		return;
	if (h == g.sram_hash && !FileExists(SramPath()))
	{
		// nothing written by the game yet: don't create a file of zeros
		bool blank = true;
		for (size_t i = 0; i < size && blank; i++)
			blank = mem[i] == 0x00 || mem[i] == 0xff;
		if (blank)
			return;
	}
	const bool ok = WriteFileAtomic(SramPath(), mem, size);
	if (ok)
		g.sram_hash = h; // a failed write is tried again 3 s later and when the game closes
	OrbisLog("[emu] battery save -> %s (%s)", SramPath().c_str(), ok ? "ok" : "failed");
}

// The Famicom Disk System's BIOS, checked before loading a disk (FCEUmm reads disksys.rom from the BIOS folder).
bool HaveFdsBios()
{
	return FileExists(g.sys_dir + "/disksys.rom");
}

// The palette chosen, when it is one of fe_palettes.h's (FCEUmm's own come through fceumm_palette): set again for a
// few frames after a start or an option change, since the core resets its palette when it reads its options.
void ApplyExtraPalette()
{
	const emu::Palette& p = emu::kPalettes[fe::Config().palette % emu::kPaletteCount];
	if (p.extra < 0 || p.extra >= fe::kExtraPaletteCount || fe_nes_game_type() == FE_NES_VS)
		return;
	uint8_t rgb[64 * 3];
	for (int i = 0; i < 64; i++)
	{
		const uint32_t c = fe::kExtraPalettes[p.extra].rgb[i];
		rgb[i * 3] = uint8_t(c >> 16);
		rgb[i * 3 + 1] = uint8_t(c >> 8);
		rgb[i * 3 + 2] = uint8_t(c);
	}
	fe_nes_set_palette(rgb);
}

void ShowOverlays(ps5video::Rect* damage)
{
	const fe::Settings& cfg = fe::Config();
	const double now = Now();
	bool drawn = false;
	if (cfg.show_fps)
	{
		char buf[32];
		snprintf(buf, sizeof(buf), "%.1f fps", g.fps_shown);
		const int w = fe::TextWidth(buf, 3);
		ps5video::FillRect(ps5video::kWidth - w - 60, 20, w + 40, 50, ps5video::Rgb(0, 0, 0));
		fe::DrawText(ps5video::kWidth - w - 40, 28, buf, 3, ps5video::Rgb(255, 255, 255));
		drawn = true;
	}
	if (!g.osd.empty() && now < g.osd_until)
	{
		const std::string text = fe::FitText(g.osd, 3, ps5video::kWidth - 160);
		const int w = fe::TextWidth(text.c_str(), 3);
		ps5video::DarkenRect(40, ps5video::kHeight - 100, w + 40, 60);
		fe::DrawText(60, ps5video::kHeight - 90, text.c_str(), 3, ps5video::Rgb(255, 255, 255));
		drawn = true;
	}
	if (drawn || g.overlay_was_drawn)
		*damage = ps5video::Rect{0, 0, ps5video::kWidth, ps5video::kHeight};
	if (!drawn && g.overlay_was_drawn)
		ps5video::InvalidateFrame(); // clear what the overlay left outside the picture
	g.overlay_was_drawn = drawn;
}

double FrameAspect()
{
	const fe::Settings& cfg = fe::Config();
	switch (cfg.aspect)
	{
		case 1: return 4.0 / 3.0;
		case 2: return g.fh > 0 ? double(g.fw) / g.fh : 4.0 / 3.0;
		case 3: return 16.0 / 9.0;
		default: return g.core_aspect;
	}
}

ps5video::Rect DrawLast()
{
	if (g.frame.empty())
		return ps5video::Rect{0, 0, 0, 0};
	const fe::Settings& cfg = fe::Config();
	return ps5video::DrawFrame(g.frame.data(), g.fw, g.fh, g.fh, FrameAspect(), ps5video::Scale(cfg.scale), cfg.smooth,
		cfg.scanlines, cfg.shader);
}

void RewindPush()
{
	const size_t size = retro_serialize_size();
	if (size == 0)
		return;
	std::vector<uint8_t> s(size);
	if (!retro_serialize(s.data(), size))
		return;
	g.rewind_bytes += size;
	g.rewind.push_back(std::move(s));
	while (g.rewind_bytes > kRewindBytes && !g.rewind.empty())
	{
		g.rewind_bytes -= g.rewind.front().size();
		g.rewind.pop_front();
	}
}

void RewindClear()
{
	g.rewind.clear();
	g.rewind_bytes = 0;
	g.rewind_tick = 0;
}
} // namespace

namespace emu
{
bool InitCore()
{
	if (g.inited)
		return true;
	FCEUMM_STAGE(Emu, "init");
	g.sys_dir = OrbisDir("bios");
	g.save_dir = OrbisDir("saves");
	ApplySettings();
	retro_set_environment(Environment);
	retro_set_video_refresh(Video);
	retro_set_audio_sample(AudioSample);
	retro_set_audio_sample_batch(AudioBatch);
	retro_set_input_poll(InputPoll);
	retro_set_input_state(InputState);
	retro_init();
	retro_system_info info = {};
	retro_get_system_info(&info);
	OrbisLog("[emu] %s %s ready (libretro API %u; BIOS folder %s)", info.library_name, info.library_version,
		retro_api_version(), g.sys_dir.c_str());
	g.inited = true;
	return true;
}

void DeinitCore()
{
	if (!g.inited)
		return;
	CloseGame();
	retro_deinit();
	g.inited = false;
}

// The pads: four RetroPads (FCEUmm plugs in a Four Score by itself for the games that use one, from its database).
void ApplyControllers()
{
	if (g.pads_applied == 1)
		return;
	g.pads_applied = 1;
	for (unsigned port = 0; port < 4; port++)
		retro_set_controller_port_device(port, RETRO_DEVICE_JOYPAD);
	OrbisLog("[emu] controllers: 4 pads (FCEUmm's auto: a Four Score for the games that use one)");
}

void ApplySettings()
{
	const fe::Settings& s = fe::Config();
	auto set = [](const char* key, const std::string& value) {
		auto it = g.opts.find(key);
		if (it == g.opts.end() || it->second != value)
		{
			g.opts[key] = value;
			g.opts_changed = true;
		}
	};
	const std::string borders = kBorders[s.borders % kBorderCount].value; // "v,h"
	const std::string v = borders.substr(0, borders.find(',')), h = borders.substr(borders.find(',') + 1);
	const Palette& pal = kPalettes[s.palette % kPaletteCount];
	set("fceumm_region", kRegions[s.region % kRegionCount].value);
	set("fceumm_aspect", "8:7 PAR");
	set("fceumm_overscan_v_top", v);
	set("fceumm_overscan_v_bottom", v);
	set("fceumm_overscan_h_left", h);
	set("fceumm_overscan_h_right", h);
	set("fceumm_palette", pal.extra >= 0 ? "default" : pal.value);
	set("fceumm_ntsc_filter", kNtscFilters[s.ntsc % kNtscFilterCount].value);
	set("fceumm_hdpacks", s.hd_packs ? "enabled" : "disabled");
	set("fceumm_sndquality", kSoundQualities[s.sound_quality % kSoundQualityCount].value);
	set("fceumm_sndlowpass", s.lowpass ? "enabled" : "disabled");
	set("fceumm_sndvolume", "7"); // FCEUmm's default (no clipping); the volume setting comes after
	set("fceumm_nospritelimit", s.no_sprite_limit ? "enabled" : "disabled");
	set("fceumm_ramstate", kRamStates[s.ram_state % kRamStateCount].value);
	set("fceumm_overclocking", "disabled");
	set("fceumm_turbo_enable", "Both");
	set("fceumm_turbo_delay", kTurboSpeeds[s.turbo % kTurboSpeedCount].value);
	set("fceumm_up_down_allowed", "disabled");
	set("fceumm_game_genie", "disabled");
	set("fceumm_show_crosshair", "disabled");
	g.palette_frames = 3;
	if (!s.rewind)
		RewindClear();
	if (g.loaded)
		ApplyControllers();
}

bool LoadGame(const std::string& path, std::string* error)
{
	if (!g.inited)
		return false;
	FCEUMM_STAGE(Emu, "load game");
	CloseGame();
	const std::string file = path.substr(path.find_last_of('/') + 1);
	if (path.size() >= 255)
	{
		// the core keeps the game's path and the paths it builds from it in 256-byte buffers
		OrbisLog("[emu] could not start %s: the path is %zu characters long", path.c_str(), path.size());
		if (error)
			*error = Fmt(fe::T("The path of %s is too long (over 254 characters): move it to a shorter folder."), file.c_str());
		return false;
	}
	std::string ext = ExtOf(path);
	g.path = path;
	g.dir = path.substr(0, path.find_last_of('/'));
	g.name = file.substr(0, file.size() - ext.size());
	g.rom.clear();
	g.info_ext = retro_game_info_ext();

	// the game is read here (from its .zip, or the file itself) and handed to FCEUmm in memory: its header can then be
	// corrected first (fe_nesdb.h)
	std::string inner;
	if (ext == ".zip")
	{
		if (!fe::ReadFromZip(path, &inner, &g.rom))
		{
			OrbisLog("[emu] could not start %s: no game inside the zip", path.c_str());
			if (error)
				*error = Fmt(fe::T("There is no NES or Famicom Disk System game inside %s."), file.c_str());
			g.path.clear();
			return false;
		}
		ext = ExtOf(inner);
	}
	else if (!ReadFile(path, g.rom) || g.rom.empty())
	{
		OrbisLog("[emu] could not start %s: can't read it", path.c_str());
		if (error)
			*error = Fmt(fe::T("NES FCEUmm PS5 could not read %s."), file.c_str());
		g.path.clear();
		return false;
	}
	if (!fe::SystemForExt(ext, &g.system))
		g.system = fe::System::Nes;
	g.ext = ext.empty() ? "" : ext.substr(1);

	if (g.system == fe::System::Fds && !HaveFdsBios())
	{
		OrbisLog("[emu] missing firmware: disksys.rom (checked before loading)");
		OrbisLog("[emu] could not start %s: missing the Famicom Disk System BIOS", path.c_str());
		if (error)
			*error = Fmt(fe::T("Famicom Disk System games need its BIOS: disksys.rom. Copy it to %s/ and try again."), g.sys_dir.c_str());
		g.path.clear();
		g.rom.clear();
		return false;
	}
	std::string fixed;
	if (fe::Config().header_db && ext == ".nes" && fe::FixNesHeader(g.rom, &fixed))
		OrbisLog("[emu] header corrected from Mesen's database: %s", fixed.c_str());

	g.info_ext.full_path = inner.empty() ? g.path.c_str() : nullptr; // the core reads the name for its region guess
	g.info_ext.archive_path = inner.empty() ? nullptr : g.path.c_str();
	g.info_ext.dir = g.dir.c_str();
	g.info_ext.name = g.name.c_str();
	g.info_ext.ext = g.ext.c_str();
	g.info_ext.data = g.rom.data();
	g.info_ext.size = g.rom.size();
	g.info_ext.file_in_archive = !inner.empty();
	g.info_ext.persistent_data = true; // kept until the game closes

	retro_game_info gi = {};
	gi.path = g.path.c_str();
	gi.data = g.rom.data();
	gi.size = g.rom.size();

	OrbisLog("[emu] loading %s%s%s", path.c_str(), inner.empty() ? "" : " -> ", inner.c_str());
	ApplySettings();
	g.opts_changed = true;
	g.frame.clear();
	g.fw = g.fh = 0;
	g.in.clear();
	g.mute = false;
	if (!retro_load_game(&gi))
	{
		OrbisLog("[emu] could not start %s", path.c_str());
		if (error)
			*error = Fmt(fe::T("FCEUmm could not load %s (a board it doesn't know, or a damaged file)."), file.c_str());
		g.path.clear();
		g.rom.clear();
		return false;
	}
	g.pads_applied = -1;
	ApplyControllers();
	retro_system_av_info av = {};
	retro_get_system_av_info(&av);
	g.fps = av.timing.fps > 1 ? av.timing.fps : 60.0;
	g.sample_rate = av.timing.sample_rate > 1000 ? av.timing.sample_rate : 44100.0;
	g.core_aspect = av.geometry.aspect_ratio > 0.1f ? av.geometry.aspect_ratio : 4.0 / 3.0;
	g.loaded = true;
	g.wait_release = true;
	g.prev_p1 = 0;
	g.turbo = g.rewinding = false;
	g.frac = 0;
	g.prev_l = g.prev_r = 0;
	g.frames = 0;
	g.fps_frames = 0;
	g.fps_since = Now();
	g.next_stats = Now() + 1.0;
	g.stats_reports = 0;
	g.next_sram_check = Now() + 3.0;
	g.overlay_was_drawn = false;
	RewindClear();
	ps5video::InvalidateFrame();
	MakeSaveDirs();
	LoadSram();
	g.palette_frames = 3;
	g.disk_insert_at = 0;
	g.prev_extra = 0;
	OrbisLog("[emu] running \"%s\" (%s), %.3f fps, %.0f Hz, aspect %.4f, state size %zu", g.name.c_str(),
		SystemName().c_str(), g.fps, g.sample_rate, g.core_aspect, retro_serialize_size());
	return true;
}

void CloseGame()
{
	if (!g.loaded)
		return;
	FCEUMM_STAGE(Emu, "close game");
	SaveSram(false);
	retro_unload_game(); // a disk's changes are its save RAM (saves/FDS/<game>.srm), written just above
	g.loaded = false;
	g.frame.clear();
	g.rom.clear();
	RewindClear();
	OrbisLog("[emu] game closed");
}

bool GameLoaded()
{
	return g.loaded;
}

std::string GameName()
{
	return g.name;
}

std::string SystemName()
{
	return g.loaded || !g.path.empty() ? fe::Info(g.system).name : "";
}

bool IsDiskGame()
{
	return g.loaded && fe_nes_game_type() == FE_NES_FDS;
}

bool IsVsGame()
{
	return g.loaded && fe_nes_game_type() == FE_NES_VS;
}

void DiskNextSide()
{
	if (!IsDiskGame())
		return;
	// as on the console: the disk out, turned over (or the next one), and in again a second later -- games check
	// that the drive was empty in between
	fe_nes_fds_eject();
	fe_nes_fds_next_side();
	g.disk_insert_at = g.frames + 60;
	OrbisLog("[emu] disk: next side");
}

void DiskInsertOrEject()
{
	if (!IsDiskGame())
		return;
	g.disk_insert_at = 0;
	fe_nes_fds_insert_or_eject();
	OrbisLog("[emu] disk: in / out");
}

void InsertCoin()
{
	if (!IsVsGame())
		return;
	fe_nes_vs_coin();
	Osd("Coin inserted");
	OrbisLog("[emu] VS. System: coin");
}

void Pause() {}

void Resume()
{
	ApplySettings();
	g.wait_release = true;
	ps5video::InvalidateFrame();
	g.new_frame = true;
}

void Osd(const std::string& text)
{
	g.osd = fe::T(text.c_str());
	g.osd_until = Now() + 2.5;
}

bool SaveState(int slot)
{
	if (!g.loaded)
		return false;
	const size_t size = retro_serialize_size();
	std::vector<uint8_t> data(size);
	bool ok = size > 0 && retro_serialize(data.data(), size) && WriteFileAtomic(StatePath(slot), data.data(), size);
	OrbisLog("[emu] save state %d: %s (%zu bytes)", slot, ok ? "ok" : "failed", size);
	if (ok)
		Osd(Fmt(fe::T("State saved to slot %d"), slot));
	else
		Osd("Could not save the state");
	return ok;
}

bool LoadState(int slot)
{
	if (!g.loaded)
		return false;
	std::vector<uint8_t> data;
	if (!ReadFile(StatePath(slot), data) || data.empty())
	{
		Osd(Fmt(fe::T("Slot %d is empty"), slot));
		return false;
	}
	const bool ok = retro_unserialize(data.data(), data.size());
	OrbisLog("[emu] load state %d: %s", slot, ok ? "ok" : "failed");
	if (ok)
		Osd(Fmt(fe::T("State loaded from slot %d"), slot));
	else
		Osd("Could not load the state");
	if (ok)
		RewindClear();
	return ok;
}

bool StateExists(int slot)
{
	return g.loaded && FileExists(StatePath(slot));
}

void Reset()
{
	if (!g.loaded)
		return;
	retro_reset();
	RewindClear();
	OrbisLog("[emu] reset");
}

void PowerCycle()
{
	if (!g.loaded)
		return;
	const std::string path = g.path;
	CloseGame();
	std::string error;
	if (!LoadGame(path, &error))
	{
		OrbisLog("[emu] power cycle: %s", error.c_str());
		ProsperoNotify(fe::T("NES FCEUmm PS5: the game could not be started again. %s"), error.c_str());
	}
}

void RedrawLastFrame()
{
	DrawLast();
}

FrameResult RunFrame()
{
	if (!g.loaded)
		return FrameResult::Stopped;
	fe::Settings& cfg = fe::Config();

	// -- hot keys (player 1)
	ps5input::Poll();
	const uint32_t raw = ps5input::Pad(0).raw_buttons;
	if (g.wait_release)
	{
		g.wait_release = (raw & (SCE_PAD_BUTTON_L3 | SCE_PAD_BUTTON_R3 | SCE_PAD_BUTTON_CROSS | SCE_PAD_BUTTON_CIRCLE)) != 0;
		g.prev_p1 = raw;
	}
	const uint32_t pressed = raw & ~g.prev_p1;
	g.prev_p1 = raw;
	const uint32_t menu_combo = SCE_PAD_BUTTON_L3 | SCE_PAD_BUTTON_R3;
	if ((raw & menu_combo) == menu_combo && (pressed & menu_combo))
		return FrameResult::OpenMenu;

	const bool l2 = (raw & SCE_PAD_BUTTON_L2) != 0;
	const bool r2 = (raw & SCE_PAD_BUTTON_R2) != 0;
	if (l2 && !r2)
	{
		if (pressed & SCE_PAD_BUTTON_UP)
			SaveState(cfg.state_slot);
		else if (pressed & SCE_PAD_BUTTON_DOWN)
			LoadState(cfg.state_slot);
		else if (pressed & (SCE_PAD_BUTTON_LEFT | SCE_PAD_BUTTON_RIGHT))
		{
			cfg.state_slot = (pressed & SCE_PAD_BUTTON_RIGHT) ? cfg.state_slot % 10 + 1 : (cfg.state_slot + 8) % 10 + 1;
			Osd(Fmt(fe::T(StateExists(cfg.state_slot) ? "State slot %d (used)" : "State slot %d (empty)"), cfg.state_slot));
			OrbisLog("[emu] state slot %d", cfg.state_slot);
			cfg.Save();
		}
	}
	// the frontend's buttons (player 1): the disk drive and the coin slot, once per press
	if (!g.wait_release)
	{
		uint32_t extra = 0;
		for (int i = 0; i < kConsoleButtonCount; i++)
		{
			const int b = cfg.buttons[i];
			const unsigned bit = b >= 0 && b < kPs5ButtonCount ? kPs5Buttons[b].bit : 0;
			if (kConsoleButtons[i].retro_id < 0 && bit && (raw & bit))
				extra |= 1u << i;
		}
		const uint32_t newly = extra & ~g.prev_extra;
		g.prev_extra = extra;
		if (newly & (1u << 6))
			DiskNextSide();
		if (newly & (1u << 7))
			DiskInsertOrEject();
		if (newly & (1u << 8))
			InsertCoin();
	}

	const bool want_rewind = cfg.rewind && l2 && r2;
	if (want_rewind != g.rewinding)
	{
		g.rewinding = want_rewind;
		OrbisLog("[emu] rewind %s (%zu snapshots, %zu MB)", want_rewind ? "on" : "off", g.rewind.size(),
			g.rewind_bytes >> 20);
	}
	const bool want_turbo = r2 && !l2;
	if (want_turbo != g.turbo)
	{
		g.turbo = want_turbo;
		OrbisLog("[emu] fast forward %s", want_turbo ? "on" : "off");
	}

	// -- emulate
	FCEUMM_STAGE(Emu, "retro_run");
	if (g.rewinding)
	{
		if (!g.rewind.empty())
		{
			const std::vector<uint8_t>& s = g.rewind.back();
			retro_unserialize(s.data(), s.size());
			g.rewind_bytes -= s.size();
			g.rewind.pop_back();
		}
		g.mute = true;
		retro_run();
		g.mute = false;
		g.in.clear();
	}
	else
	{
		const int runs = g.turbo ? (cfg.ff_speed == 0 ? 8 : std::max(2, (cfg.ff_speed + 50) / 100)) : 1;
		for (int i = 0; i < runs; i++)
		{
			g.mute = g.turbo;
			retro_run();
			g.frames++;
			g.fps_frames++;
			if (cfg.rewind && ++g.rewind_tick >= kRewindEvery)
			{
				g.rewind_tick = 0;
				RewindPush();
			}
		}
		g.mute = false;
	}
	if (g.palette_frames > 0)
	{
		ApplyExtraPalette(); // after the frame that read the options (the core resets its palette then)
		g.palette_frames--;
	}
	if (g.disk_insert_at && g.frames >= g.disk_insert_at)
	{
		g.disk_insert_at = 0;
		fe_nes_fds_insert_or_eject(); // the side selected a second ago goes in
	}
	FlushAudio();

	// -- picture
	const double now = Now();
	if (now - g.fps_since >= 1.0)
	{
		g.fps_shown = g.fps_frames / (now - g.fps_since);
		g.fps_frames = 0;
		g.fps_since = now;
	}
	const bool pal = g.fps < 55.0;
	if (g.new_frame || (!g.osd.empty() && now < g.osd_until + 0.1) || cfg.show_fps)
	{
		g.new_frame = false;
		ps5video::Rect r = DrawLast();
		ShowOverlays(&r);
		// 60 Hz games wait for the flip: the display paces them
		ps5video::Present(r.x, r.y, r.w, r.h, !pal && !g.turbo);
	}

	// -- pacing on the sound: 50 Hz games, or a ring filling up
	if (!g.turbo && !g.rewinding)
	{
		if (cfg.audio && ps5audio::Available())
		{
			// 50 Hz: the sound is the clock; 60 Hz: vsync is, and this only catches a display that doesn't block
			const int limit = pal ? kTargetQueued : kTargetQueued * 2;
			const double give_up = Now() + 0.1;
			while (ps5audio::Queued() > limit && Now() < give_up)
				usleep(1000);
		}
		else if (pal)
		{
			static double next = 0;
			if (next < now - 0.1)
				next = now;
			next += 1.0 / g.fps;
			if (next > Now())
				usleep(useconds_t((next - Now()) * 1e6));
		}
	}

	// -- battery save, every 3 s when it changed; the log, now and then
	if (now >= g.next_sram_check)
	{
		g.next_sram_check = now + 3.0;
		SaveSram(false);
	}
	if (now >= g.next_stats)
	{
		g.stats_reports++;
		g.next_stats = now + (g.stats_reports < 3 ? 5.0 : 60.0);
		const double shader_ms = ps5video::TakeShaderMs();
		OrbisLog("[emu] frame %llu, %.1f fps, audio queued %d (%.0f ms), underruns %llu, shader %.1f ms",
			(unsigned long long)g.frames, g.fps_shown, ps5audio::Queued(), ps5audio::Queued() * 1000.0 / ps5audio::kRate,
			(unsigned long long)ps5audio::Underruns(), shader_ms);
	}
	return FrameResult::Continue;
}
} // namespace emu
