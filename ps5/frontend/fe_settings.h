// NES FCEUmm PS5 frontend: settings kept in /data/fceumm/fceumm-ps5.ini (key=value lines).
// SPDX-License-Identifier: MIT
#pragma once

#include <string>

namespace fe
{
struct Settings
{
	// video
	int scale = 0; // ps5video::Scale: fit, integer, stretch
	int shader = 1; // ps5crt::Shader: 0 off, 1 "CRT Easymode style" (the default for every game), ...
	int aspect = 0; // emu::kAspects: TV (8:7 pixels), 4:3, square pixels, 16:9
	int palette = 0; // emu::kPalettes: Mesen's (the default), Mesen's and Nestopia's others, FCEUmm's own
	int ntsc = 0; // emu::kNtscFilters: off, composite, S-Video, RGB, monochrome (Blargg's NTSC filter)
	int borders = 0; // emu::kBorders: hide 8 lines top and bottom (a TV's overscan), show everything, hide all edges
	bool hd_packs = true; // Mesen-format HD packs in bios/HdPacks/<game>/hires.txt
	bool smooth = false; // bilinear when the scale isn't whole
	bool scanlines = false;
	bool show_fps = false;
	// audio
	bool audio = true;
	int volume = 100; // 0..100
	int sound_quality = 2; // emu::kSoundQualities: low, high, very high (the most accurate)
	bool lowpass = false; // the core's low-pass audio filter
	// emulation
	int ff_speed = 300; // % while R2 is held; 0 = as fast as possible
	bool rewind = true; // L2 + R2 rewinds
	int region = 0; // emu::kRegions: auto, NTSC, PAL, Dendy
	bool no_sprite_limit = false; // the NES shows 8 sprites a line; more flicker less, but isn't what it did
	int ram_state = 0; // emu::kRamStates: the RAM at power-on: $FF, $00, random
	bool header_db = true; // correct headers with Mesen's database (fe_nesdb.h)
	int state_slot = 1; // 1..10
	// controls
	int turbo = 2; // emu::kTurboSpeeds: frames between turbo presses
	// the PS5 button (index in emu::kPs5Buttons) of each console button, in emu::kConsoleButtons' order:
	// A, B, turbo A, turbo B, Start, Select, disk side, disk in/out, coin. By position by default: Circle, Cross,
	// Triangle, Square, OPTIONS, touchpad, L1, R1, none.
	static constexpr int kButtons = 9;
	static constexpr int kDefaultButtons[kButtons] = {1, 0, 3, 2, 6, 7, 4, 5, 8};
	int buttons[kButtons] = {1, 0, 3, 2, 6, 7, 4, 5, 8};
	void DefaultButtons();
	// library
	bool covers_download = true; // fetch box art from libretro-thumbnails
	bool debug_logs = true;      // boot.log and the others in /data/fceumm/logs (OrbisLogSetEnabled)
	int shelf_family = 0; // fe::Family the shelf shows
	std::string last_rom; // the shelf puts the selection on this game

	void Load();
	void Save() const;
};

Settings& Config();
} // namespace fe
