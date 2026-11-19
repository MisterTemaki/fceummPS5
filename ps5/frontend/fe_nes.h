/* NES FCEUmm PS5: a few calls into FCEUmm's core that its libretro interface doesn't offer (fe_nes.c, built with
 * the core's headers): the Famicom Disk System's drive, the VS System's coin slot, a palette of 64 colours, and the
 * cartridge's CRC (the 4-player adapter's Auto).
 * SPDX-License-Identifier: MIT */
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum
{
	FE_NES_NONE = -1, /* no game */
	FE_NES_CART = 0,
	FE_NES_VS = 1, /* VS. System (coins) */
	FE_NES_FDS = 2, /* Famicom Disk System */
	FE_NES_NSF = 3 /* a music file */
};
int fe_nes_game_type(void);

/* The disk drive: eject (silently), select the next side (the core says which in a message: the drive must be
 * empty), insert the selected side -- or eject it, when one is in (the core's message says which). */
void fe_nes_fds_eject(void);
void fe_nes_fds_next_side(void);
void fe_nes_fds_insert_or_eject(void);

void fe_nes_vs_coin(void);

/* rgb: 64 colours, R G B each; the core derives the colour-emphasis ones from them, as for its own palettes. */
void fe_nes_set_palette(const uint8_t* rgb);

/* The PRG + CHR CRC32 of the cartridge FCEUmm just loaded, the one its own four-player lists and Mesen's database go
 * by: unif 0 for an iNES / NES 2.0 file, 1 for a UNIF file. 0 when no cartridge is loaded. */
uint32_t fe_nes_cart_crc(int unif);

#ifdef __cplusplus
}
#endif
