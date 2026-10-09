// NES FCEUmm PS5 frontend: the FCEUmm core behind a small API.
//
// The core is driven through its libretro interface (src/drivers/libretro/libretro.c, the port FCEUmm is developed
// in): the frontend is the libretro "frontend" -- it answers the core's environment calls (folders, options, log),
// gets each frame (XRGB8888) and its sound (48 kHz) through callbacks, and reports the pads. One retro_run() is one
// frame, called from the frontend's thread, as Snes9x PS5 runs Snes9x. A few things the libretro interface doesn't
// offer (the disk drive, the coin slot, a palette of our own) go straight to the core (fe_nes.h).
//
// SPDX-License-Identifier: MIT
#pragma once

#include <string>

namespace emu
{
// The choices the settings menu offers.
struct Choice
{
	const char* name;
	const char* value; // the core option's value ("" where the frontend handles it)
};
extern const Choice kAspects[]; // fceumm_aspect: TV (8:7 pixels), 4:3, square pixels; 16:9 (stretched here)
extern const int kAspectCount;
// The palettes: Mesen's (the default) and the others Mesen and Nestopia have (fe_palettes.h, set through fe_nes.h),
// then FCEUmm's own (fceumm_palette). value "" = one of fe_palettes.h's (index in `extra`).
struct Palette
{
	const char* name;
	const char* value; // fceumm_palette, or "" for kExtraPalettes[extra]
	int extra;
};
extern const Palette kPalettes[];
extern const int kPaletteCount;
extern const Choice kNtscFilters[]; // fceumm_ntsc_filter
extern const int kNtscFilterCount;
extern const Choice kBorders[]; // the overscan: fceumm_overscan_v_* / _h_*
extern const int kBorderCount;
extern const Choice kSoundQualities[]; // fceumm_sndquality
extern const int kSoundQualityCount;
extern const Choice kRegions[]; // fceumm_region
extern const int kRegionCount;
extern const Choice kRamStates[]; // fceumm_ramstate
extern const int kRamStateCount;
extern const Choice kTurboSpeeds[]; // fceumm_turbo_delay
extern const int kTurboSpeedCount;

// The buttons of the console's pad the player can move, and the PS5 buttons they can go to.
struct PadButton
{
	const char* name; // "Square"
	unsigned bit; // SCE_PAD_BUTTON_*; 0 = not assigned
};
extern const PadButton kPs5Buttons[]; // Cross, Circle, Square, Triangle, L1, R1, OPTIONS, touchpad, (none)
extern const int kPs5ButtonCount;
struct ConsoleButton
{
	const char* name; // "A", "Turbo B", "Disk: next side"...
	const char* key; // its key in fceumm-ps5.ini: "btn_a"
	int retro_id; // the RetroPad button FCEUmm reads for it; -1: the frontend's (the disk drive, the coin slot)
	int default_ps5; // index in kPs5Buttons
};
constexpr int kConsoleButtonCount = 9; // A, B, turbo A, turbo B, Start, Select, disk side, disk in/out, coin
extern const ConsoleButton kConsoleButtons[kConsoleButtonCount];

bool InitCore();
void DeinitCore();

// Starts the game. On failure, *error says why (a disk without the Famicom Disk System's BIOS says where it goes).
bool LoadGame(const std::string& path, std::string* error);
void CloseGame(); // writes the battery save and ends the game
bool GameLoaded();
std::string GameName(); // the file name without its extension
std::string SystemName(); // "NES", "Famicom Disk System" of the running game

// The Famicom Disk System's drive and the VS. System's coin slot (the pause menu; buttons in the settings).
bool IsDiskGame();
bool IsVsGame();
void DiskNextSide(); // ejects the disk, selects the next side, and puts it in a second later
void DiskInsertOrEject();
void InsertCoin();

// Settings from fe::Config() -> the core's options and the frontend's picture/sound settings.
void ApplySettings();

enum class FrameResult
{
	Continue,
	OpenMenu, // L3 + R3 pressed together
	Stopped, // no game
};
// One frame: the pads and hot keys, retro_run(), the picture (and the messages) on the screen, the sound to
// the audio ring, paced by the display (60 Hz games) or by the sound (50 Hz games). Hot keys: L2 + Up / Down =
// save / load the state slot, L2 + Left / Right = change the slot, R2 held = fast forward, L2 + R2 held =
// rewind.
FrameResult RunFrame();

void Pause(); // nothing runs between frames; kept for the menus' symmetry
void Resume();

bool SaveState(int slot); // 1..10, /data/fceumm/states/<game>.state<slot>
bool LoadState(int slot);
bool StateExists(int slot);
void Reset();
void PowerCycle(); // the game loaded again, as switching the console off and on
void Osd(const std::string& text); // a message over the game for a few seconds

// Redraws the last frame into the surface (the pause menu draws over it).
void RedrawLastFrame();
} // namespace emu
