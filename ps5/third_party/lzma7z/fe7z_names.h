/* NES FCEUmm PS5: every external name of the vendored 7z decoder (LZMA SDK 26.05) gets the prefix fce7z_, so it can't
   meet another copy of the LZMA SDK in the link (FCEUmm links none today; Beetle PCE PS5, where this comes from, links
   the core's older one for libchdr): two copies would clash in the link or, worse, silently mix two versions.
   Force-included into each file of this folder (-include fe7z_names.h) and included by ps5/frontend/fe_7z.cpp before
   the SDK's headers. The Makefile checks after each build that these objects define no other global name
   (lzma7z/names.ok): a name a newer SDK adds goes here. The list is what `nm -g --defined-only` prints for the objects.
   SPDX-License-Identifier: MIT */
#ifndef FE7Z_NAMES_H
#define FE7Z_NAMES_H
#define Bcj2Dec_Decode fce7z_Bcj2Dec_Decode
#define Bcj2Dec_Init fce7z_Bcj2Dec_Init
#define Buf_Create fce7z_Buf_Create
#define Buf_Free fce7z_Buf_Free
#define Buf_Init fce7z_Buf_Init
#define CrcCalc fce7z_CrcCalc
#define CrcGenerateTable fce7z_CrcGenerateTable
#define CrcUpdate fce7z_CrcUpdate
#define CrcUpdateT12 fce7z_CrcUpdateT12
#define Delta_Decode fce7z_Delta_Decode
#define Delta_Encode fce7z_Delta_Encode
#define Delta_Init fce7z_Delta_Init
#define LookInStream_LookRead fce7z_LookInStream_LookRead
#define LookInStream_Read fce7z_LookInStream_Read
#define LookInStream_Read2 fce7z_LookInStream_Read2
#define LookInStream_SeekTo fce7z_LookInStream_SeekTo
#define LookToRead2_CreateVTable fce7z_LookToRead2_CreateVTable
#define Lzma2Dec_Allocate fce7z_Lzma2Dec_Allocate
#define Lzma2Dec_AllocateProbs fce7z_Lzma2Dec_AllocateProbs
#define Lzma2Dec_DecodeToBuf fce7z_Lzma2Dec_DecodeToBuf
#define Lzma2Dec_DecodeToDic fce7z_Lzma2Dec_DecodeToDic
#define Lzma2Dec_Init fce7z_Lzma2Dec_Init
#define Lzma2Dec_Parse fce7z_Lzma2Dec_Parse
#define Lzma2Decode fce7z_Lzma2Decode
#define LzmaDec_Allocate fce7z_LzmaDec_Allocate
#define LzmaDec_AllocateProbs fce7z_LzmaDec_AllocateProbs
#define LzmaDec_DecodeToBuf fce7z_LzmaDec_DecodeToBuf
#define LzmaDec_DecodeToDic fce7z_LzmaDec_DecodeToDic
#define LzmaDec_Free fce7z_LzmaDec_Free
#define LzmaDec_FreeProbs fce7z_LzmaDec_FreeProbs
#define LzmaDec_Init fce7z_LzmaDec_Init
#define LzmaDec_InitDicAndState fce7z_LzmaDec_InitDicAndState
#define LzmaDecode fce7z_LzmaDecode
#define LzmaProps_Decode fce7z_LzmaProps_Decode
#define Ppmd7_Alloc fce7z_Ppmd7_Alloc
#define Ppmd7_Construct fce7z_Ppmd7_Construct
#define Ppmd7_Free fce7z_Ppmd7_Free
#define Ppmd7_Init fce7z_Ppmd7_Init
#define Ppmd7_MakeEscFreq fce7z_Ppmd7_MakeEscFreq
#define Ppmd7_Update1 fce7z_Ppmd7_Update1
#define Ppmd7_Update1_0 fce7z_Ppmd7_Update1_0
#define Ppmd7_Update2 fce7z_Ppmd7_Update2
#define Ppmd7_UpdateModel fce7z_Ppmd7_UpdateModel
#define Ppmd7z_DecodeSymbol fce7z_Ppmd7z_DecodeSymbol
#define Ppmd7z_RangeDec_Init fce7z_Ppmd7z_RangeDec_Init
#define SecToLook_CreateVTable fce7z_SecToLook_CreateVTable
#define SecToRead_CreateVTable fce7z_SecToRead_CreateVTable
#define SeqInStream_ReadByte fce7z_SeqInStream_ReadByte
#define SeqInStream_ReadMax fce7z_SeqInStream_ReadMax
#define SzArEx_Extract fce7z_SzArEx_Extract
#define SzArEx_Free fce7z_SzArEx_Free
#define SzArEx_GetFileNameUtf16 fce7z_SzArEx_GetFileNameUtf16
#define SzArEx_Init fce7z_SzArEx_Init
#define SzArEx_Open fce7z_SzArEx_Open
#define SzAr_DecodeFolder fce7z_SzAr_DecodeFolder
#define SzAr_GetFolderUnpackSize fce7z_SzAr_GetFolderUnpackSize
#define SzGetNextFolderItem fce7z_SzGetNextFolderItem
#define g_CrcTable fce7z_g_CrcTable
#define k7zSignature fce7z_k7zSignature
#define z7_BranchConvSt_X86_Dec fce7z_z7_BranchConvSt_X86_Dec
#define z7_BranchConv_ARM64_Dec fce7z_z7_BranchConv_ARM64_Dec
#define z7_BranchConv_ARMT_Dec fce7z_z7_BranchConv_ARMT_Dec
#define z7_BranchConv_ARM_Dec fce7z_z7_BranchConv_ARM_Dec
#define z7_BranchConv_IA64_Dec fce7z_z7_BranchConv_IA64_Dec
#define z7_BranchConv_PPC_Dec fce7z_z7_BranchConv_PPC_Dec
#define z7_BranchConv_RISCV_Dec fce7z_z7_BranchConv_RISCV_Dec
#define z7_BranchConv_RISCV_Enc fce7z_z7_BranchConv_RISCV_Enc
#define z7_BranchConv_SPARC_Dec fce7z_z7_BranchConv_SPARC_Dec
#define z7_GetFunc_CrcUpdate fce7z_z7_GetFunc_CrcUpdate
#endif
