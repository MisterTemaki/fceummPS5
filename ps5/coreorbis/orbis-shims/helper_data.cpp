// NES FCEUmm PS5: NESFCEUmmPS5-helper.elf built into the app (ProsperoJailbreak.h). Only the native eboot links
// this file; the Makefile passes HELPER_ELF, the helper payload's path.
//
// SPDX-License-Identifier: MIT

#include "ProsperoJailbreak.h"

__asm__(".section .rodata\n"
		".balign 16\n"
		".global fceumm_helper_elf_begin\n"
		"fceumm_helper_elf_begin:\n"
		".incbin \"" HELPER_ELF "\"\n"
		".global fceumm_helper_elf_end\n"
		"fceumm_helper_elf_end:\n"
		".previous\n");
extern "C" const unsigned char fceumm_helper_elf_begin[];
extern "C" const unsigned char fceumm_helper_elf_end[];

namespace jailbreak
{
Blob EmbeddedHelper()
{
	return {fceumm_helper_elf_begin, size_t(fceumm_helper_elf_end - fceumm_helper_elf_begin)};
}
} // namespace jailbreak
