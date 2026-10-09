/* NES FCEUmm PS5: calls into FCEUmm's core (fe_nes.h).
 * SPDX-License-Identifier: MIT */
#include "fe_nes.h"

#include "fceu-types.h"
#include "driver.h"
#include "fceu.h"
#include "fds.h"
#include "git.h"
#include "vsuni.h"

int fe_nes_game_type(void)
{
	return GameInfo ? GameInfo->type : FE_NES_NONE;
}

void fe_nes_fds_eject(void)
{
	if (GameInfo && GameInfo->type == GIT_FDS)
		FCEU_FDSEject();
}

void fe_nes_fds_next_side(void)
{
	if (GameInfo && GameInfo->type == GIT_FDS)
		FCEU_FDSSelect();
}

void fe_nes_fds_insert_or_eject(void)
{
	if (GameInfo && GameInfo->type == GIT_FDS)
		FCEU_FDSInsert(-1);
}

void fe_nes_vs_coin(void)
{
	if (GameInfo && GameInfo->type == GIT_VSUNI)
		FCEU_VSUniCoin();
}

void fe_nes_set_palette(const uint8_t* rgb)
{
	FCEUI_SetPaletteArray((uint8_t*)rgb, 64);
}
