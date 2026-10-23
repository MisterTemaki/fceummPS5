# NES FCEUmm PS5
#   make ps5    -> build/ps5/NESFCEUmmPS5.elf   the payload to send with the PS5 Payload Manager / ELF loader:
#                  it installs or updates the dashboard app /data/homebrew/$(TITLE_ID)/ (FCEUmm itself,
#                  icon included) and stays running as the helper that lets the app reach /data
#   make app    -> build/app/$(TITLE_ID)/     the app folder on its own (eboot.bin, sce_module/, sce_sys/)
#   make host   -> build/host/                Linux builds of the same code (PS5 calls faked by host/sce_host.cpp)
#   make test   -> host builds + tests/run-tests.sh
#   make dist   -> build/dist/NESFCEUmmPS5-v$(VERSION).elf + fceumm-ps5-v$(VERSION)-src.zip (release names)
#   make send   -> sends NESFCEUmmPS5.elf to $(PS5_HOST):$(PS5_PORT) with the SDK's prospero-deploy
#
# The layout is PS5SX2's (and Snes9x PS5's, Mesen2 PS5's): eboot.bin is the emulator, a native PS5 title (the
# console gives the controller to the title in front only), and the payload is its installer and helper:
#   1. build/ps5/NESFCEUmmPS5-helper.elf   the helper alone (payload); the app sends it to the ELF loader
#   2. build/app/$(TITLE_ID)/                   eboot.bin = FCEUmm's core (through its libretro port,
#                                               ../src/drivers/libretro/libretro.c) + the PS5 frontend + the helper from
#                                               step 1 (native title, signed); sce_module/libc.prx; sce_sys/
#   3. build/ps5/NESFCEUmmPS5.elf          installer + helper, with the app folder from step 2 built in
#
# FCEUmm's core (../src) is compiled as it is, with the flags of its own libretro build (Makefile.common,
# Makefile.libretro's unix platform): every one of its sources builds for the PS5 unchanged.
#
# Dependencies: the ps5-payload-dev SDK (v0.42 or newer, https://github.com/ps5-payload-dev/sdk) in
# $(PS5_PAYLOAD_SDK), with clang/lld 18 on the host.

PS5_PAYLOAD_SDK ?= /opt/ps5-payload-sdk
PS5_HOST ?= ps5
PS5_PORT ?= 9021
VERSION ?= 1.1
# the libretro-fceumm snapshot this port is built from (its master branch, October 2026)
CORE_VERSION := 2026.10
TITLE_ID ?= PPSA99013
APP_OUT := build/app/$(TITLE_ID)

ROOT := ..

# FCEUmm: its libretro build's sources (Makefile.common, HAVE_NTSC=1, HAVE_HDPACK=1, 32-bit colour as its unix
# build), and zlib (third_party/zlib, also for minizip's .zip games).
FC := src
LRC := $(FC)/drivers/libretro/libretro-common
CORE_C_SRC := $(sort $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/$(FC)/boards/*.c $(ROOT)/$(FC)/input/*.c))) \
	$(addprefix $(FC)/,drivers/libretro/libretro.c drivers/libretro/libretro_dipswitch.c cart.c cheat.c crc32.c \
		fceu-endian.c fceu-memory.c fceu.c fds.c fds_apu.c file.c filter.c general.c input.c md5.c nsf.c palette.c \
		ppu.c sound.c state.c video.c vsuni.c ines.c unif.c x6502.c ntsc/nes_ntsc.c \
		hdpack/hdpack_load.c hdpack/hdpack_image.c hdpack/hdpack_ppu.c hdpack/hdpack_render.c \
		hdpack/hdpack_audio.c hdpack/hdpack_patch.c) \
	$(addprefix $(LRC)/,formats/png/rpng.c formats/dds/rdds.c formats/webp/rwebp.c formats/vp8/rvp8.c \
		formats/vorbis/rvorbis.c formats/wav/rwav.c streams/trans_stream.c streams/trans_stream_pipe.c \
		streams/trans_stream_deflate.c encodings/encoding_deflate.c streams/memory_stream.c \
		compat/compat_posix_string.c compat/compat_snprintf.c compat/compat_strcasestr.c compat/compat_strl.c \
		compat/fopen_utf8.c encodings/encoding_utf.c file/file_path.c file/file_path_io.c streams/file_stream.c \
		streams/file_stream_transforms.c string/stdstring.c time/rtime.c vfs/vfs_implementation.c) \
	$(sort $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/ps5/third_party/zlib/*.c)))
CORE_SRC :=
CORE_DEFS := -D__LIBRETRO__ -DPATH_MAX=1024 -DFCEU_VERSION_NUMERIC=9900 -DFRONTEND_SUPPORTS_RGB888 -DHAVE_NTSC_FILTER \
	-DHAVE_HDPACK -DHAVE_UNISTD_H '-DINLINE=inline'

# netfs: network shares as folders (SMB and NFS), from Beetle PCE PS5 1.1.1 (Genesis Plus GX PS5 2.1.1's, Snes9x PS5's:
# thatboialex's design; netfs/netfs_backend.h). backend_smb.cpp / backend_nfs.cpp are the protocols; the stubs (which
# fail with "not built in") stand in for them in the netfs unit test.
NETFS_CORE_SRC := netfs/netfs_share.cpp netfs/netfs_core.cpp netfs/netfs_cache.cpp netfs/netfs_vfs.cpp netfs/netfs_wrap.cpp netfs/netfs_edit.cpp netfs/netfs_shims_ps5.cpp
# the libc calls netfs answers for /smb/... and /nfs/... paths (netfs/netfs_wrap.cpp has a __wrap_ function for each).
# They go into both links as --wrap, so a call anywhere in the app (the frontend's game reads, minizip, the 7z reader,
# FCEUmm's libretro-common file streams, libc++'s file streams) lands in netfs first and is passed on to the real call
# when the path or handle is not netfs's. NES games are read whole when they start; nothing streams while one runs.
NETFS_WRAPPED := fopen fclose fread fseek fseeko ftell ftello rewind feof ferror clearerr \
	fileno fgetc getc ungetc fgets fflush setvbuf flockfile funlockfile open close read pread lseek fstat stat lstat \
	access realpath opendir readdir closedir
# glibc only: the console's libc has no 64-bit variants (off_t is 64 bits), and minizip maps its fopen64 calls to
# fopen on FreeBSD targets (third_party/ioapi.h), so a --wrap of these would leave __real_* undefined in the console link.
NETFS_WRAPPED_LFS64 := fopen64 fseeko64 ftello64 stat64 lstat64 fstat64 readdir64 open64 pread64 lseek64
# console only (netfs/netfs_shims_ps5.cpp): sockets made non-blocking (fcntl, then SO_NBIO), and a getaddrinfo that works
# in a native title
NETFS_WRAPPED_PS5 := fcntl getaddrinfo freeaddrinfo
NETFS_WRAP_LLD := $(foreach s,$(NETFS_WRAPPED) $(NETFS_WRAPPED_PS5),--wrap=$(s))
NETFS_WRAP_GCC := $(foreach s,$(NETFS_WRAPPED) $(NETFS_WRAPPED_LFS64),-Wl,--wrap=$(s))
NETFS_SRC := $(NETFS_CORE_SRC) netfs/backend_smb.cpp netfs/backend_nfs.cpp
# libsmb2 (57fea04) and libnfs (2d368ad), LGPL-2.1-or-later, vendored with their notices as Snes9x PS5, Genesis Plus GX
# PS5 and Beetle PCE PS5 have them (third_party/libsmb2/README.snes9xps5, third_party/libnfs/PATCHES.md). libsmb2 is
# built from a config.h of its folder (no CMake). It needs no PS4_PLATFORM: prospero-clang defines __FreeBSD__, which
# selects libsmb2's FreeBSD headers. Their fcntl and getaddrinfo calls reach the console shims through the --wrap list.
LIBSMB2 := third_party/libsmb2
LIBNFS := third_party/libnfs
LIBSMB2_SRC := $(sort $(wildcard $(LIBSMB2)/lib/*.c))
LIBNFS_SRC := $(sort $(foreach d,lib mount nfs nfs4 portmap nlm nsm rquota,$(wildcard $(LIBNFS)/$(d)/*.c)))
LIBSMB2_INC := -I$(LIBSMB2)/include -I$(LIBSMB2)/include/smb2 -I$(LIBSMB2)/lib
LIBSMB2_FLAGS := -I$(LIBSMB2) $(LIBSMB2_INC) -DHAVE_CONFIG_H -D_FILE_OFFSET_BITS=64 '-D_U_=__attribute__((unused))'
LIBNFS_FLAGS := -DHAVE_CONFIG_H -I$(LIBNFS) -I$(LIBNFS)/include -I$(LIBNFS)/include/nfsc \
	$(addprefix -I$(LIBNFS)/,mount nfs nfs4 nlm nsm portmap rquota)
# netfs/backend_smb.cpp includes libsmb2's headers as system headers (they are not ours to keep -Werror clean)
%/port/netfs/backend_smb.o: EXTRA_FLAGS = $(patsubst -I%,-isystem %,$(LIBSMB2_INC))
%/port/netfs/backend_nfs.o: EXTRA_FLAGS = $(LIBNFS_FLAGS)

# the app (eboot.bin): the PS5 layer and the frontend
EMU_SRC := coreorbis/main-boot.cpp \
	coreorbis/orbis-shims/orbis_paths.cpp coreorbis/orbis-shims/ProsperoNotify.cpp \
	coreorbis/orbis-shims/ProsperoVideo.cpp coreorbis/orbis-shims/ProsperoAudio.cpp \
	coreorbis/orbis-shims/ProsperoInput.cpp coreorbis/orbis-shims/ProsperoJailbreak.cpp \
	coreorbis/orbis-shims/ProsperoCrash.cpp coreorbis/orbis-shims/ProsperoCrt.cpp \
	frontend/fe_emu.cpp frontend/fe_menu.cpp frontend/fe_settings.cpp frontend/fe_i18n.cpp frontend/fe_text.cpp \
	frontend/fe_games.cpp frontend/fe_http.cpp frontend/fe_covers.cpp frontend/fe_shelf.cpp \
	frontend/fe_prefetch.cpp frontend/fe_coverfetch.cpp frontend/fe_coverworker.cpp frontend/fe_nesdb.cpp \
	frontend/fe_netscreen.cpp frontend/fe_osk.cpp frontend/fe_ui.cpp $(NETFS_SRC)
# 1.1: games inside a .7z (fe_7z.cpp), with the LZMA SDK 26.05's C 7z decoder (public domain; third_party/lzma7z/README.md):
# no threads, no AES (an encrypted archive is refused), no assembler. FCEUmm links no other LZMA copy, but every external
# name of this one is prefixed fce7z_ all the same (fe7z_names.h, force-included), so another can't meet it, and
# lzma7z/names.ok stops the build if an object defines a name without it.
EMU_SRC += frontend/fe_7z.cpp
LZMA7Z := third_party/lzma7z
LZMA7Z_SRC := $(sort $(wildcard $(LZMA7Z)/*.c))
LZMA7Z_DEFS := -DZ7_ST -DZ7_PPMD_SUPPORT -DZ7_EXTRACT_ONLY
LZMA7Z_FLAGS := $(LZMA7Z_DEFS) -include $(LZMA7Z)/fe7z_names.h -I$(LZMA7Z) -w
%/port/frontend/fe_7z.o: EXTRA_FLAGS = $(LZMA7Z_DEFS) -isystem $(LZMA7Z)
%/port/frontend/fe_7z.o: $(LZMA7Z)/fe7z_names.h
# every global name the decoder's objects define must carry the prefix (a newer SDK may add one: put it in fe7z_names.h)
define LZMA7Z_NAMES_CHECK
	@bad=$$($(1) -g --defined-only $(2) | awk 'NF==3 && $$3 !~ /^(fce7z_|__odr_asan\.fce7z_)/ {print $$3}'); \
	if [ -n "$$bad" ]; then echo "lzma7z: names without the fce7z_ prefix: $$bad (add them to $(LZMA7Z)/fe7z_names.h)"; exit 1; fi
	@touch $@
endef
# minizip (zlib licence) for games inside a .zip, built as C with the core's zlib
EMU_C_SRC := frontend/third_party/unzip.c frontend/third_party/ioapi.c
# a C bridge into the core (the disk drive, the coin slot, a palette: fe_nes.h), built with the core's defines and headers
BRIDGE_C_SRC := frontend/fe_nes.c
# the payloads: the helper, and the installer (= helper + install)
# (the helper also downloads the covers in the background: fe_coverworker.cpp, with the app's HTTPS code)
HELPER_SRC := coreorbis/orbis-shims/orbis_paths.cpp coreorbis/orbis-shims/ProsperoNotify.cpp \
	coreorbis/orbis-shims/ProsperoHelper.cpp coreorbis/orbis-shims/ProsperoCrash.cpp \
	frontend/fe_http.cpp frontend/fe_coverfetch.cpp frontend/fe_coverworker.cpp frontend/fe_tlshttp.cpp
# the helper's own HTTPS (fe_tlshttp.cpp): Mbed TLS 3.6 (Apache-2.0), with fe_mbedtls_config.h on its default settings
MBEDTLS := frontend/third_party/mbedtls
MBEDTLS_SRC := $(sort $(wildcard $(MBEDTLS)/library/*.c))
MBEDTLS_FLAGS := -I$(MBEDTLS)/include -Ifrontend '-DMBEDTLS_USER_CONFIG_FILE="fe_mbedtls_config.h"'
INSTALLER_SRC := installer/installer_main.cpp $(HELPER_SRC) coreorbis/orbis-shims/ProsperoInstall.cpp

CORE_INCS := -I$(ROOT)/$(FC)/drivers/libretro -I$(ROOT)/$(LRC)/include -I$(ROOT)/$(FC) -I$(ROOT)/$(FC)/input \
	-I$(ROOT)/$(FC)/boards -I$(ROOT)/$(FC)/ntsc -I$(ROOT)/ps5/third_party/zlib
INCS := -Inetfs -Icoreorbis/include-orbis -Icoreorbis/orbis-shims -Ifrontend -isystem $(ROOT)/$(LRC)/include \
	-isystem $(ROOT)/ps5/third_party/zlib
DEFS := -DFCEUMM_PS5_VERSION='"$(VERSION)"' -DFCEUMM_CORE_VERSION='"$(CORE_VERSION)"' -DFCEUMM_TITLE_ID='"$(TITLE_ID)"'
MINIZIP_FLAGS := -DNOUNCRYPT -I$(ROOT)/ps5/third_party/zlib -w
PORT_WARN := -Wall -Wextra -Werror -Wno-unused-parameter -Wno-missing-field-initializers

# the game-name table built into fe_games.o (tools/make_gamedb.py), the header corrections into fe_nesdb.o
# (tools/make_nesdb.py)
GAMEDB_DEFS := -DGAMEDB_TSV='"$(abspath frontend/data/nointro.tsv)"'
%/port/frontend/fe_games.o: EXTRA_FLAGS = $(GAMEDB_DEFS)
%/port/frontend/fe_games.o: frontend/data/nointro.tsv
%/port/frontend/fe_nesdb.o: EXTRA_FLAGS = -DNESDB_TSV='"$(abspath frontend/data/nesdb.tsv)"'
%/port/frontend/fe_nesdb.o: frontend/data/nesdb.tsv
# stb_image in fe_covers.o has warnings of its own
%/port/frontend/fe_covers.o: EXTRA_FLAGS = -Wno-error -Wno-sign-compare -Wno-unused-but-set-variable -Wno-implicit-fallthrough
# the UI fonts (PS5SX2's: PCSX2's Roboto Regular and PromptFont; Font Awesome's brands) built into fe_text.o
%/port/frontend/fe_text.o: EXTRA_FLAGS = -DFE_FONT_DIR='"$(abspath frontend/assets/fonts)"' -Wno-error -Wno-sign-compare -Wno-unused-function
%/port/frontend/fe_text.o: frontend/assets/fonts/Roboto-Regular.ttf frontend/assets/fonts/promptfont.otf \
	frontend/assets/fonts/fa-brands-400.otf
# the helper's HTTPS client: Mbed TLS's headers, and Mozilla's CA list built in
%/port/frontend/fe_tlshttp.o: EXTRA_FLAGS = $(MBEDTLS_FLAGS) -DCACERT_PEM='"$(abspath frontend/data/cacert.pem)"'
%/port/frontend/fe_tlshttp.o: frontend/data/cacert.pem frontend/fe_mbedtls_config.h
# the helper payload is installer_main.cpp without the install step
%/port/installer/helper_main.o: EXTRA_FLAGS = -DFCEUMM_HELPER_ONLY

# ---------------- PS5 ----------------
PS5_CC  := $(PS5_PAYLOAD_SDK)/bin/prospero-clang
PS5_CXX := $(PS5_PAYLOAD_SDK)/bin/prospero-clang++
PS5_OUT := build/ps5
# The PS5's CPU is Zen 2 (PS5SX2 builds with the same -march).
PS5_OPT := -O3 -fPIC -march=znver2 -fno-strict-aliasing
# the payloads: notifications, and the kernel access the helper needs (libkernel_sys: sceKernelGetAppInfo)
# the payload SDK's network libraries (its http2_get sample's), for the helper's cover downloads
PS5_PAYLOAD_LIBS := -lkernel_sys -lSceNet -lSceNetCtl -lSceSsl -lSceHttp2 -lpthread

PS5_CORE_OBJ := $(patsubst %.cpp,$(PS5_OUT)/core/%.o,$(CORE_SRC)) $(patsubst %.c,$(PS5_OUT)/core/%.o,$(CORE_C_SRC))
PS5_EMU_OBJ := $(patsubst %.cpp,$(PS5_OUT)/port/%.o,$(EMU_SRC)) $(patsubst %.c,$(PS5_OUT)/port/%.o,$(EMU_C_SRC)) \
	$(patsubst %.c,$(PS5_OUT)/bridge/%.o,$(BRIDGE_C_SRC))
PS5_MBEDTLS_OBJ := $(patsubst $(MBEDTLS)/library/%.c,$(PS5_OUT)/mbedtls/%.o,$(MBEDTLS_SRC))
PS5_HELPER_OBJ := $(PS5_OUT)/port/installer/helper_main.o $(patsubst %.cpp,$(PS5_OUT)/port/%.o,$(HELPER_SRC)) $(PS5_MBEDTLS_OBJ)
PS5_INSTALLER_OBJ := $(patsubst %.cpp,$(PS5_OUT)/port/%.o,$(INSTALLER_SRC)) $(PS5_MBEDTLS_OBJ)
PS5_LIBSMB2_OBJ := $(patsubst $(LIBSMB2)/%.c,$(PS5_OUT)/libsmb2/%.o,$(LIBSMB2_SRC))
PS5_LIBNFS_OBJ := $(patsubst $(LIBNFS)/%.c,$(PS5_OUT)/libnfs/%.o,$(LIBNFS_SRC))
PS5_LZMA7Z_OBJ := $(patsubst $(LZMA7Z)/%.c,$(PS5_OUT)/lzma7z/%.o,$(LZMA7Z_SRC))

ps5: $(PS5_OUT)/NESFCEUmmPS5.elf
# the core alone
ps5-core: $(PS5_CORE_OBJ)

# the core's own flags (Makefile.libretro), its warnings left to it
$(PS5_OUT)/core/%.o: $(ROOT)/%.c
	@mkdir -p $(dir $@)
	$(PS5_CC) $(PS5_OPT) $(CORE_DEFS) $(CORE_INCS) -w -c -o $@ $<

$(PS5_OUT)/mbedtls/%.o: $(MBEDTLS)/library/%.c frontend/fe_mbedtls_config.h
	@mkdir -p $(dir $@)
	$(PS5_CC) -Os -fPIC -march=znver2 $(MBEDTLS_FLAGS) -c -o $@ $<

$(PS5_OUT)/port/%.o: %.c
	@mkdir -p $(dir $@)
	$(PS5_CC) $(PS5_OPT) $(MINIZIP_FLAGS) -c -o $@ $<

$(PS5_OUT)/bridge/%.o: %.c frontend/fe_nes.h
	@mkdir -p $(dir $@)
	$(PS5_CC) $(PS5_OPT) $(CORE_DEFS) $(CORE_INCS) -Ifrontend -Wall -Werror -c -o $@ $<

$(PS5_OUT)/port/%.o: %.cpp coreorbis/include-orbis/*.h coreorbis/orbis-shims/*.h frontend/*.h netfs/*.h
	@mkdir -p $(dir $@)
	$(PS5_CXX) -std=c++17 $(PS5_OPT) $(DEFS) $(INCS) $(PORT_WARN) $(EXTRA_FLAGS) -c -o $@ $<

$(PS5_OUT)/libsmb2/%.o: $(LIBSMB2)/%.c
	@mkdir -p $(dir $@)
	$(PS5_CC) -O2 -fPIC -march=znver2 $(LIBSMB2_FLAGS) -w -c -o $@ $<

$(PS5_OUT)/libnfs/%.o: $(LIBNFS)/%.c
	@mkdir -p $(dir $@)
	$(PS5_CC) -O2 -fPIC -march=znver2 $(LIBNFS_FLAGS) -w -c -o $@ $<

$(PS5_OUT)/lzma7z/%.o: $(LZMA7Z)/%.c $(wildcard $(LZMA7Z)/*.h)
	@mkdir -p $(dir $@)
	$(PS5_CC) $(PS5_OPT) $(LZMA7Z_FLAGS) -c -o $@ $<
$(PS5_OUT)/lzma7z/names.ok: $(PS5_LZMA7Z_OBJ)
	$(call LZMA7Z_NAMES_CHECK,$(PS5_PAYLOAD_SDK)/bin/llvm-nm,$^)

$(PS5_OUT)/port/installer/helper_main.o: installer/installer_main.cpp coreorbis/include-orbis/*.h coreorbis/orbis-shims/*.h
	@mkdir -p $(dir $@)
	$(PS5_CXX) -std=c++17 $(PS5_OPT) $(DEFS) $(INCS) $(PORT_WARN) $(EXTRA_FLAGS) -c -o $@ $<

# 1. the helper payload (built into the app, which sends it to the ELF loader when no helper answers)
$(PS5_OUT)/NESFCEUmmPS5-helper.elf: $(PS5_HELPER_OBJ)
	$(PS5_CXX) -o $@ $^ $(PS5_PAYLOAD_LIBS)

$(PS5_OUT)/helper_data.o: coreorbis/orbis-shims/helper_data.cpp coreorbis/orbis-shims/ProsperoJailbreak.h $(PS5_OUT)/NESFCEUmmPS5-helper.elf
	$(PS5_CXX) -std=c++17 $(PS5_OPT) $(DEFS) $(INCS) $(PORT_WARN) -DHELPER_ELF='"$(abspath $(PS5_OUT)/NESFCEUmmPS5-helper.elf)"' -c -o $@ $<

# 3. the installer + helper, with the app folder built in
APP_FILES = $(APP_OUT)/eboot.bin $(APP_OUT)/sce_sys/param.json $(APP_OUT)/sce_sys/icon0.png $(APP_OUT)/sce_sys/pic0.dds \
	$(APP_OUT)/sce_sys/pic1.dds \
	$(APP_OUT)/sce_module/libc.prx
APP_DATA_DEFS = -DAPP_EBOOT='"$(abspath $(APP_OUT)/eboot.bin)"' -DAPP_PARAM='"$(abspath $(APP_OUT)/sce_sys/param.json)"' \
	-DAPP_ICON0='"$(abspath $(APP_OUT)/sce_sys/icon0.png)"' -DAPP_PIC0='"$(abspath $(APP_OUT)/sce_sys/pic0.dds)"' \
	-DAPP_PIC1='"$(abspath $(APP_OUT)/sce_sys/pic1.dds)"' \
	-DAPP_LIBC='"$(abspath $(APP_OUT)/sce_module/libc.prx)"'

$(PS5_OUT)/install_data.o: coreorbis/orbis-shims/install_data.cpp coreorbis/orbis-shims/ProsperoInstall.h $(APP_FILES)
	$(PS5_CXX) -std=c++17 $(PS5_OPT) $(DEFS) $(INCS) $(PORT_WARN) $(APP_DATA_DEFS) -c -o $@ $<

$(PS5_OUT)/NESFCEUmmPS5.elf: $(PS5_INSTALLER_OBJ) $(PS5_OUT)/install_data.o
	$(PS5_CXX) -o $@ $^ $(PS5_PAYLOAD_LIBS)
	@echo "built $@ ($$(stat -c %s $@) bytes)"

$(PS5_OUT)/NESFCEUmmPS5-stripped.elf: $(PS5_OUT)/NESFCEUmmPS5.elf
	$(PS5_PAYLOAD_SDK)/bin/prospero-strip -o $@ $<

strip: $(PS5_OUT)/NESFCEUmmPS5-stripped.elf

# the release files, named with the version: build/dist/NESFCEUmmPS5-v$(VERSION).elf and the sources zip
DIST := build/dist
dist: $(PS5_OUT)/NESFCEUmmPS5.elf
	@mkdir -p $(DIST)
	cp $< $(DIST)/NESFCEUmmPS5-v$(VERSION).elf
	cd ../.. && rm -f $(abspath $(DIST))/fceumm-ps5-v$(VERSION)-src.zip && \
		zip -qr $(abspath $(DIST))/fceumm-ps5-v$(VERSION)-src.zip $(notdir $(abspath ..)) \
		-x '*/ps5/build/*' '*/proto/native/build/*' '*.o' '*/.git/*'
	@ls -l $(DIST)

send: $(PS5_OUT)/NESFCEUmmPS5.elf
	$(PS5_PAYLOAD_SDK)/bin/prospero-deploy -h $(PS5_HOST) -p $(PS5_PORT) $<

# ---------------- the app (eboot.bin = FCEUmm) ----------------
# 2. A native PS5 title linked the way PS5SX2 links its eboot (ps5/coreorbis/link-vk.sh): the boilerplate's
# app_crt.cpp (_start -> _init_env -> main) and app_cpp_runtime.cpp, the emulator's objects (the same ones,
# compiled once), a PIE laid out by ps5-pie.ld (+ PS5SX2's ehframe.ld) against the SDK's system-module stubs
# and its static libc++/libc++abi/libunwind/libc, every defined symbol local (PS5SX2's genmap.py result:
# localize.map); then ps5-native-tool link (SCE dynamic tables, process parameters) and self --sign.
# The folder carries sce_module/libc.prx, the C runtime module a native title needs (without it the console
# stops the app with PRX_SCE_MODULE_LOAD_ERROR, 0xa0020102).
NATIVE := proto/native
NATIVE_TOOL := $(NATIVE)/build/host/ps5-native-tool
LIBC_BUILDER := $(NATIVE)/build/host/libc-builder
LLD ?= ld.lld
NATIVE_CLANG = PS5_PAYLOAD_SDK=$(PS5_PAYLOAD_SDK) sh $(NATIVE)/tooling/prospero-clang18
SDK_LIB := $(PS5_PAYLOAD_SDK)/target/lib
# every system-module stub but the two PS5SX2 leaves out (link-vk.sh)
APP_STUBS = $(filter-out %/libScePosixForWebKit.so %/libSceGLSlimVSH.so,$(sort $(wildcard $(SDK_LIB)/*.so)))

$(NATIVE_TOOL): $(NATIVE)/tooling/native/native_app_builder.cpp $(NATIVE)/tooling/native/elf_object.cpp \
		$(NATIVE)/tooling/native/self_container.cpp $(NATIVE)/tooling/native/sce_module_writer.cpp
	@mkdir -p $(dir $@)
	$(HOST_CXX_NATIVE) -std=c++20 -O2 -o $@ $^ -lz
HOST_CXX_NATIVE ?= clang++

$(LIBC_BUILDER): $(NATIVE)/tooling/native/libc_builder.cpp
	@mkdir -p $(dir $@)
	$(HOST_CXX_NATIVE) -std=c++20 -O2 -Wall -Wextra -Werror -o $@ $<

# sce_module/libc.prx, deterministic: it must match the published digest (proto/native/libc.prx.sha256)
build/app/libc.prx: $(LIBC_BUILDER) $(NATIVE_TOOL) $(wildcard $(NATIVE)/tooling/native/runtime/*.txt)
	@mkdir -p $(dir $@)
	$(LIBC_BUILDER) $(NATIVE)/tooling/native/runtime/api-surface.txt $(NATIVE)/tooling/native/runtime/imports.txt build/app/libc.raw.elf
	$(NATIVE_TOOL) self --sign --in build/app/libc.raw.elf --out $@
	cd build/app && sha256sum --check --strict $(abspath $(NATIVE)/libc.prx.sha256)

$(APP_OUT)/sce_module/libc.prx: build/app/libc.prx
	@mkdir -p $(dir $@)
	cp $< $@

app: $(APP_FILES)

build/app/app_crt.o build/app/app_cpp_runtime.o: build/app/%.o: $(NATIVE)/tooling/native/%.cpp
	@mkdir -p $(dir $@)
	$(NATIVE_CLANG) -std=c++20 -O2 -Wall -Wextra -fno-exceptions -fno-rtti -ffunction-sections -fdata-sections \
		-c -o $@ $<

EBOOT_OBJS = build/app/app_crt.o build/app/app_cpp_runtime.o $(PS5_CORE_OBJ) $(PS5_EMU_OBJ) $(PS5_LIBSMB2_OBJ) $(PS5_LIBNFS_OBJ) \
	$(PS5_LZMA7Z_OBJ) $(PS5_OUT)/helper_data.o
build/app/fceumm-pie.elf: $(EBOOT_OBJS) $(NATIVE)/tooling/native/ps5-pie.ld $(NATIVE)/tooling/native/ehframe.ld \
		$(NATIVE)/tooling/native/app-symbols.map $(NATIVE)/tooling/native/localize.map $(PS5_OUT)/lzma7z/names.ok
	$(LLD) -m elf_x86_64 -pie -z max-page-size=0x4000 --hash-style=gnu \
		-T $(NATIVE)/tooling/native/ps5-pie.ld -T $(NATIVE)/tooling/native/ehframe.ld --eh-frame-hdr \
		--version-script $(NATIVE)/tooling/native/app-symbols.map --version-script $(NATIVE)/tooling/native/localize.map \
		-e _start --no-dynamic-linker $(NETFS_WRAP_LLD) -o $@ $(EBOOT_OBJS) \
		--as-needed $(APP_STUBS) -L $(SDK_LIB) \
		$(SDK_LIB)/libc++.a $(SDK_LIB)/libc++abi.a $(SDK_LIB)/libunwind.a $(SDK_LIB)/libc.a -lpthread

build/app/eboot.elf: build/app/fceumm-pie.elf $(NATIVE_TOOL)
	$(NATIVE_TOOL) link --in $< --out $@ --stub-dir $(SDK_LIB) --module-sdk 0x02000009 \
		--companion-sdk 0x08050001 --file-name eboot.elf
	python3 tools/prepare_console_elf.py --input $@ --output build/app/eboot-console-ready.elf

$(APP_OUT)/eboot.bin: build/app/eboot.elf $(NATIVE_TOOL)
	@mkdir -p $(dir $@)
	$(NATIVE_TOOL) self --sign --in $< --out $@ --magic 0x1D3D154F
	$(NATIVE_TOOL) self --inspect --file $@

$(APP_OUT)/sce_sys/param.json: app/sce_sys/param.json
	@mkdir -p $(dir $@)
	sed 's/PPSA99013/$(TITLE_ID)/g' $< > $@

$(APP_OUT)/sce_sys/%.png: app/sce_sys/%.png
	@mkdir -p $(dir $@)
	cp $< $@

# pic0.dds (the home screen's background while the icon is selected) and pic1.dds (the launch background):
# 3840x2160 BC7_UNORM DX10 DDS without mipmaps, made from app/sce_sys/background-source.png with the
# ps5-native-app-boilerplate's tools/prepare-assets.sh --background (pinned bc7enc_rdo).
$(APP_OUT)/sce_sys/%.dds: app/sce_sys/%.dds
	@mkdir -p $(dir $@)
	cp $< $@

# ---------------- host ----------------
HOST_CC ?= gcc
HOST_CXX ?= g++
HOST_OUT := build/host
HOST_SAN ?= -fsanitize=address,undefined -fno-omit-frame-pointer
# The core under AddressSanitizer only (UBSan would report its deliberate shifts and unaligned reads).
HOST_CORE_SAN ?= -fsanitize=address -fno-omit-frame-pointer
# no _FORTIFY_SOURCE: it turns fread/fgets/read into __fread_chk/..., which --wrap (netfs) does not see
HOST_OPT := -O1 -g -mavx2 -fno-strict-aliasing -U_FORTIFY_SOURCE
HOST_CORE_OPT := -O2 -g1 -mavx2 -U_FORTIFY_SOURCE

HOST_CORE_OBJ := $(patsubst %.cpp,$(HOST_OUT)/core/%.o,$(CORE_SRC)) $(patsubst %.c,$(HOST_OUT)/core/%.o,$(CORE_C_SRC))
HOST_EMU_OBJ := $(patsubst %.cpp,$(HOST_OUT)/port/%.o,$(EMU_SRC) host/sce_host.cpp host/netfs_dirbackend.cpp) $(patsubst %.c,$(HOST_OUT)/port/%.o,$(EMU_C_SRC)) \
	$(patsubst %.c,$(HOST_OUT)/bridge/%.o,$(BRIDGE_C_SRC))
HOST_MBEDTLS_OBJ := $(patsubst $(MBEDTLS)/library/%.c,$(HOST_OUT)/mbedtls/%.o,$(MBEDTLS_SRC))
HOST_HELPER_OBJ := $(HOST_OUT)/port/installer/helper_main.o $(patsubst %.cpp,$(HOST_OUT)/port/%.o,$(HELPER_SRC) host/sce_host.cpp) \
	$(HOST_MBEDTLS_OBJ)
HOST_INSTALLER_OBJ := $(patsubst %.cpp,$(HOST_OUT)/port/%.o,$(INSTALLER_SRC) host/sce_host.cpp) $(HOST_MBEDTLS_OBJ)
HOST_LIBSMB2_OBJ := $(patsubst $(LIBSMB2)/%.c,$(HOST_OUT)/libsmb2/%.o,$(LIBSMB2_SRC))
HOST_LIBNFS_OBJ := $(patsubst $(LIBNFS)/%.c,$(HOST_OUT)/libnfs/%.o,$(LIBNFS_SRC))
HOST_LZMA7Z_OBJ := $(patsubst $(LZMA7Z)/%.c,$(HOST_OUT)/lzma7z/%.o,$(LZMA7Z_SRC))

host-core: $(HOST_CORE_OBJ)
host: $(HOST_OUT)/fceumm-ps5-host $(HOST_OUT)/fceumm-ps5-installer $(HOST_OUT)/fceumm-ps5-helper

$(HOST_OUT)/core/%.o: $(ROOT)/%.c
	@mkdir -p $(dir $@)
	$(HOST_CC) -fPIC $(HOST_CORE_OPT) $(HOST_CORE_SAN) $(CORE_DEFS) $(CORE_INCS) -w -c -o $@ $<

$(HOST_OUT)/mbedtls/%.o: $(MBEDTLS)/library/%.c frontend/fe_mbedtls_config.h
	@mkdir -p $(dir $@)
	$(HOST_CC) -O2 -g1 $(MBEDTLS_FLAGS) -c -o $@ $<

$(HOST_OUT)/port/%.o: %.c
	@mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_OPT) $(MINIZIP_FLAGS) -c -o $@ $<

$(HOST_OUT)/bridge/%.o: %.c frontend/fe_nes.h
	@mkdir -p $(dir $@)
	$(HOST_CC) -fPIC $(HOST_CORE_OPT) $(HOST_CORE_SAN) $(CORE_DEFS) $(CORE_INCS) -Ifrontend -Wall -Werror -c -o $@ $<

$(HOST_OUT)/port/%.o: %.cpp coreorbis/include-orbis/*.h coreorbis/orbis-shims/*.h frontend/*.h netfs/*.h
	@mkdir -p $(dir $@)
	$(HOST_CXX) -std=c++17 $(HOST_OPT) $(HOST_SAN) $(DEFS) $(INCS) $(PORT_WARN) $(EXTRA_FLAGS) -c -o $@ $<

$(HOST_OUT)/libsmb2/%.o: $(LIBSMB2)/%.c
	@mkdir -p $(dir $@)
	$(HOST_CC) -O2 -g1 -D_GNU_SOURCE $(LIBSMB2_FLAGS) -w -c -o $@ $<

$(HOST_OUT)/libnfs/%.o: $(LIBNFS)/%.c
	@mkdir -p $(dir $@)
	$(HOST_CC) -O2 -g1 $(LIBNFS_FLAGS) -w -c -o $@ $<

# the 7z decoder under AddressSanitizer too (it reads archives from anywhere; UBSan would report its unaligned reads)
$(HOST_OUT)/lzma7z/%.o: $(LZMA7Z)/%.c $(wildcard $(LZMA7Z)/*.h)
	@mkdir -p $(dir $@)
	$(HOST_CC) -fPIC $(HOST_OPT) $(HOST_CORE_SAN) $(LZMA7Z_FLAGS) -c -o $@ $<
$(HOST_OUT)/lzma7z/names.ok: $(HOST_LZMA7Z_OBJ)
	$(call LZMA7Z_NAMES_CHECK,nm,$^)

$(HOST_OUT)/port/installer/helper_main.o: installer/installer_main.cpp coreorbis/include-orbis/*.h coreorbis/orbis-shims/*.h
	@mkdir -p $(dir $@)
	$(HOST_CXX) -std=c++17 $(HOST_OPT) $(HOST_SAN) $(DEFS) $(INCS) $(PORT_WARN) $(EXTRA_FLAGS) -c -o $@ $<

# The host installer carries a stand-in app folder (tests/fake-eboot.bin, tests/fake-libc.prx + the real
# param/icon/pic); the host app carries the host helper, which it hands to a fake ELF loader in the tests.
HOST_APP_DEFS = -DAPP_EBOOT='"$(abspath tests/fake-eboot.bin)"' -DAPP_PARAM='"$(abspath app/sce_sys/param.json)"' \
	-DAPP_ICON0='"$(abspath app/sce_sys/icon0.png)"' -DAPP_PIC0='"$(abspath app/sce_sys/pic0.dds)"' \
	-DAPP_PIC1='"$(abspath app/sce_sys/pic1.dds)"' \
	-DAPP_LIBC='"$(abspath tests/fake-libc.prx)"'

$(HOST_OUT)/install_data.o: coreorbis/orbis-shims/install_data.cpp coreorbis/orbis-shims/ProsperoInstall.h \
		tests/fake-eboot.bin tests/fake-libc.prx app/sce_sys/param.json app/sce_sys/icon0.png app/sce_sys/pic0.dds app/sce_sys/pic1.dds
	@mkdir -p $(dir $@)
	$(HOST_CXX) -std=c++17 $(HOST_OPT) $(DEFS) $(INCS) $(PORT_WARN) $(HOST_APP_DEFS) -c -o $@ $<

$(HOST_OUT)/helper_data.o: coreorbis/orbis-shims/helper_data.cpp coreorbis/orbis-shims/ProsperoJailbreak.h $(HOST_OUT)/fceumm-ps5-helper
	@mkdir -p $(dir $@)
	$(HOST_CXX) -std=c++17 $(HOST_OPT) $(DEFS) $(INCS) $(PORT_WARN) -DHELPER_ELF='"$(abspath $(HOST_OUT)/fceumm-ps5-helper)"' -c -o $@ $<

$(HOST_OUT)/fceumm-ps5-helper: $(HOST_HELPER_OBJ)
	$(HOST_CXX) $(HOST_SAN) -o $@ $^ -lpthread

$(HOST_OUT)/fceumm-ps5-installer: $(HOST_INSTALLER_OBJ) $(HOST_OUT)/install_data.o
	$(HOST_CXX) $(HOST_SAN) -o $@ $^ -lpthread

$(HOST_OUT)/fceumm-ps5-host: $(HOST_CORE_OBJ) $(HOST_EMU_OBJ) $(HOST_LIBSMB2_OBJ) $(HOST_LIBNFS_OBJ) $(HOST_LZMA7Z_OBJ) \
		$(HOST_OUT)/helper_data.o | $(HOST_OUT)/lzma7z/names.ok
	$(HOST_CXX) $(HOST_SAN) -o $@ $^ $(NETFS_WRAP_GCC) -lpthread -lm

# netfs's own test: the netfs code, the stub backends and an in-memory share, linked with the same --wrap list
HOST_NETFS_TEST_OBJ := $(patsubst %.cpp,$(HOST_OUT)/port/%.o,$(NETFS_CORE_SRC) netfs/backend_smb_stub.cpp netfs/backend_nfs_stub.cpp \
	tests/test_netfs.cpp)
# minizip and a whole static zlib (the build machine's libz.a) go into it too: the test opens a .zip and a .gz on the
# fake share, through the --wrap list
HOST_ZLIB_A ?= $(firstword $(wildcard /usr/lib/x86_64-linux-gnu/libz.a /usr/lib64/libz.a /usr/lib/libz.a))
%/port/tests/test_netfs.o: EXTRA_FLAGS = -Inetfs -Ifrontend/third_party
HOST_NETFS_TEST_EXTRA := $(HOST_OUT)/port/frontend/third_party/unzip.o $(HOST_OUT)/port/frontend/third_party/ioapi.o
$(HOST_OUT)/test-netfs: $(HOST_NETFS_TEST_OBJ) $(HOST_NETFS_TEST_EXTRA) tests/netfs_fake.h
	$(HOST_CXX) $(HOST_SAN) -o $@ $(HOST_NETFS_TEST_OBJ) $(HOST_NETFS_TEST_EXTRA) $(HOST_ZLIB_A) $(NETFS_WRAP_GCC) -lpthread

test: host $(HOST_OUT)/test-netfs
	bash tests/run-tests.sh

# NFS backend unit test: backend_nfs.cpp against an in-memory libnfs (tests/libnfs_mock.cpp), no network
NFS_TEST := $(HOST_OUT)/nfs-backend-test
$(NFS_TEST): tests/nfs_backend_test.cpp tests/libnfs_mock.cpp tests/libnfs_mock.h netfs/backend_nfs.cpp netfs/backend_nfs.h netfs/netfs_backend.h
	@mkdir -p $(dir $@)
	$(HOST_CXX) -std=c++17 $(HOST_OPT) $(HOST_SAN) $(PORT_WARN) $(LIBNFS_FLAGS) -Inetfs -Itests -o $@ \
		tests/nfs_backend_test.cpp tests/libnfs_mock.cpp netfs/backend_nfs.cpp -lpthread

# the same backend on real libnfs (the objects of the host build), against loopback sockets that misbehave
NFS_LOOP_TEST := $(HOST_OUT)/nfs-loopback-test
$(NFS_LOOP_TEST): tests/nfs_loopback_test.cpp netfs/backend_nfs.cpp netfs/backend_nfs.h netfs/netfs_backend.h $(HOST_LIBNFS_OBJ)
	@mkdir -p $(dir $@)
	$(HOST_CXX) -std=c++17 $(HOST_OPT) $(HOST_SAN) $(PORT_WARN) $(LIBNFS_FLAGS) -Inetfs -o $@ \
		tests/nfs_loopback_test.cpp netfs/backend_nfs.cpp $(HOST_LIBNFS_OBJ) -lpthread

# the same backend against a real NFSv3 server (unfs3): not part of `make test`, needs rpcbind and unfsd
NFS_SERVER_TEST := $(HOST_OUT)/nfs-server-test
$(NFS_SERVER_TEST): tests/nfs_server_test.cpp netfs/backend_nfs.cpp netfs/backend_nfs.h netfs/netfs_backend.h $(HOST_LIBNFS_OBJ)
	@mkdir -p $(dir $@)
	$(HOST_CXX) -std=c++17 $(HOST_OPT) $(HOST_SAN) $(PORT_WARN) $(LIBNFS_FLAGS) -Inetfs -o $@ \
		tests/nfs_server_test.cpp netfs/backend_nfs.cpp $(HOST_LIBNFS_OBJ) -lpthread

test-nfs-server: $(NFS_SERVER_TEST)
	bash tests/nfs_server_test.sh $(NFS_SERVER_TEST)

test-nfs: $(NFS_TEST) $(NFS_LOOP_TEST)
	ASAN_OPTIONS=detect_leaks=1 $(NFS_TEST)
	ASAN_OPTIONS=detect_leaks=1 $(NFS_LOOP_TEST)

# the shelf's storage tabs (frontend/fe_tabs.h): header only, so no app code is linked
TABS_TEST := $(HOST_OUT)/tabs-test
$(TABS_TEST): tests/test_tabs.cpp frontend/fe_tabs.h frontend/fe_games.h
	@mkdir -p $(dir $@)
	$(HOST_CXX) -std=c++17 $(HOST_OPT) $(HOST_SAN) $(PORT_WARN) -Ifrontend -o $@ tests/test_tabs.cpp

test-tabs: $(TABS_TEST)
	$(TABS_TEST)

test: test-nfs test-tabs

# 1.1: the 7z reader (fe_7z.cpp and the decoder) on the archives in tests/7z/ (tests/make_7z_fixtures.py made them)
SEVENZIP_TEST := $(HOST_OUT)/test-7z
$(SEVENZIP_TEST): tests/test_7z.cpp $(HOST_OUT)/port/frontend/fe_7z.o $(HOST_LZMA7Z_OBJ) | $(HOST_OUT)/lzma7z/names.ok
	$(HOST_CXX) -std=c++17 $(HOST_OPT) $(HOST_SAN) $(PORT_WARN) -Ifrontend -o $@ tests/test_7z.cpp \
		$(HOST_OUT)/port/frontend/fe_7z.o $(HOST_LZMA7Z_OBJ) $(HOST_ZLIB_A) -lpthread

test-7z: $(SEVENZIP_TEST)
	python3 tests/make_test_rom.py $(HOST_OUT)/test-7z-card.nes >/dev/null
	ASAN_OPTIONS=detect_leaks=1 $(SEVENZIP_TEST) tests/7z $(HOST_OUT)/test-7z-card.nes

test: test-7z

clean:
	rm -rf build

# the SMB backend against a real Samba (adds `smb-test`, run before the other tests; skipped without smbd)
include tests/smb/smb.mk

.PHONY: ps5 ps5-core host-core host test test-nfs test-nfs-server test-tabs test-7z send strip app dist clean
.SECONDARY:
