# lzma7z: the LZMA SDK's C 7z decoder

NES FCEUmm PS5 1.1 reads NES games and Famicom Disk System disks inside `.7z` archives with these files
(`ps5/frontend/fe_7z.cpp`), as Beetle PCE PS5 1.1 does for HuCards.

- **Source:** the official 7-Zip repository, tag **26.05** (commit `b88c6bc`), folder `C/`: `7zArcIn.c 7zBuf.c 7zCrc.c
  7zCrcOpt.c 7zDec.c 7zStream.c Bcj2.c Bra.c Bra86.c BraIA64.c Delta.c Lzma2Dec.c LzmaDec.c Ppmd7.c Ppmd7Dec.c` and the
  headers they include (`7z.h 7zBuf.h 7zCrc.h 7zTypes.h Bcj2.h Bra.h Compiler.h CpuArch.h Delta.h Lzma2Dec.h LzmaDec.h
  Ppmd.h Ppmd7.h Precomp.h RotateDefs.h`). The files are **unchanged**.
- **Licence:** each of these files says "Igor Pavlov : Public domain" in its first lines, and 7-Zip's `DOC/License.txt`
  says that the files whose source states public-domain status are public domain (the rest of 7-Zip is under the GNU
  LGPL, BSD licences or the unRAR restriction; none of those files is here). So everything in this folder is **public
  domain**, except `fe7z_names.h`, which is ours (MIT, like the rest of `ps5/`).
- **Build** (`ps5/Makefile`): `-DZ7_ST` (no threads), `-DZ7_PPMD_SUPPORT`, `-DZ7_EXTRACT_ONLY`, no assembler (no
  `Z7_LZMA_DEC_OPT`), no AES (`7zAes.c` is not here: an encrypted archive is refused). The archive is read through the
  app's own stdio calls (fe_7z.cpp's `ISeekInStream` over `FILE*`, so a `.7z` on a network share is read through
  netfs), so `7zFile.c` is not used.
- **Names:** FCEUmm itself links no LZMA code (no other `LzmaDec_*`, `Delta_*`, `x86_Convert`... in the app; `nm` on
  the link shows each name defined once), but the copy is kept apart all the same: `fe7z_names.h` renames every external
  name of these files to `fce7z_<name>`; it is force-included into each of them (`-include fe7z_names.h`) and included
  by fe_7z.cpp before the SDK's headers, so another copy (a library added later) can't meet it in the link, or
  silently mix two versions. The Makefile's `lzma7z/names.ok` step fails the build when one of these objects defines a
  global name without the prefix (a name a newer SDK adds): add it to `fe7z_names.h` (the list is what
  `nm -g --defined-only` prints for these objects).

What is decoded: LZMA, LZMA2, PPMd (as 7-Zip writes it: 5 bytes of properties), BCJ, BCJ2, the ARM, ARM64, ARMT, PPC, SPARC, IA64 and RISC-V
filters, Delta, and stored files. Not: BZip2, Deflate, Deflate64, Zstandard and the other methods of 7-Zip's C++ code,
nor encrypted archives. fe_7z.cpp decodes a whole solid block to reach a file in it, and refuses a block over 64 MiB
(and a game over 32 MiB) before decoding anything.
