// NES FCEUmm PS5: the dashboard app built into NESFCEUmmPS5.elf (ProsperoInstall.h).
//
// The Makefile passes the five files' paths: eboot.bin (the launcher, which itself carries the emulator),
// sce_sys/param.json, sce_sys/icon0.png (the NES FCEUmm PS5 icon, ps5/app/sce_sys/icon0.png),
// sce_sys/pic0.dds + pic1.dds (the home screen backgrounds) and sce_module/libc.prx (the C runtime module a native title carries, as PS5SX2's app folder). Only the final NESFCEUmmPS5.elf links this file.
//
// SPDX-License-Identifier: MIT

#include "ProsperoInstall.h"

#define FCEUMM_INCBIN(sym, path)                                                                                  \
	__asm__(".section .rodata\n"                                                                               \
			".balign 16\n"                                                                                     \
			".global " #sym "_begin\n" #sym "_begin:\n"                                                        \
			".incbin \"" path "\"\n"                                                                           \
			".global " #sym "_end\n" #sym "_end:\n"                                                            \
			".previous\n");                                                                                    \
	extern "C" const unsigned char sym##_begin[];                                                              \
	extern "C" const unsigned char sym##_end[];

FCEUMM_INCBIN(fceumm_app_eboot, APP_EBOOT)
FCEUMM_INCBIN(fceumm_app_param, APP_PARAM)
FCEUMM_INCBIN(fceumm_app_icon0, APP_ICON0)
FCEUMM_INCBIN(fceumm_app_pic0, APP_PIC0)
FCEUMM_INCBIN(fceumm_app_pic1, APP_PIC1)
FCEUMM_INCBIN(fceumm_app_libc, APP_LIBC)

const EmbeddedAppFile* EmbeddedAppFiles()
{
	static const EmbeddedAppFile files[] = {
		{"sce_sys/param.json", fceumm_app_param_begin, fceumm_app_param_end},
		{"sce_sys/icon0.png", fceumm_app_icon0_begin, fceumm_app_icon0_end},
		{"sce_sys/pic0.dds", fceumm_app_pic0_begin, fceumm_app_pic0_end},
		{"sce_sys/pic1.dds", fceumm_app_pic1_begin, fceumm_app_pic1_end},
		{"sce_module/libc.prx", fceumm_app_libc_begin, fceumm_app_libc_end},
		{"eboot.bin", fceumm_app_eboot_begin, fceumm_app_eboot_end},
		{nullptr, nullptr, nullptr},
	};
	return files;
}
