#!/bin/bash
# NES FCEUmm PS5 host tests: the real port code (main-boot, shims, frontend, FCEUmm's libretro core; the installer
# and the helper) on Linux, with the PS5 calls faked by host/sce_host.cpp. A scripted pad drives the app; flips are
# de-tiled to PPM and checked. The games are tiny test ROMs (tests/make_test_rom.py): red backdrop, green while
# Cross (NES B) is held.
set -u
cd "$(dirname "$0")/.."
BIN=$PWD/build/host/fceumm-ps5-host
INSTALLER=$PWD/build/host/fceumm-ps5-installer
HELPER=$PWD/build/host/fceumm-ps5-helper
# ports nobody listens on, so the app's ordinary runs find no helper and no ELF loader
export FCEUMM_HELPER_PORT=$((20000 + RANDOM % 10000)) FCEUMM_ELFLDR_PORT=$((30000 + RANDOM % 10000)) FCEUMM_JB_NO_OTHERS=1
# debug logs are off by default (1.0.1); the tests read boot.log, so they turn the default on (group 25 checks it off)
export FCEUMM_LOGS_DEFAULT=1
CHECK="python3 $PWD/tests/check_ppm.py"
RECT="python3 $PWD/tests/check_rect.py"
ROM="python3 $PWD/tests/make_test_rom.py"
WORK=${WORK:-$(mktemp -d)}
ONLY=${ONLY:-}
PASS=0
FAIL=0

# pad bits
CROSS=4000; CIRCLE=2000; TRIANGLE=1000; SQUARE=8000; UP=10; DOWN=40; RIGHT=20; L1=400; R1=800; L2=100; R2=200; L3R3=6; OPTIONS=8
L2UP=$(printf %x $((0x$L2 | 0x$UP))); L2DOWN=$(printf %x $((0x$L2 | 0x$DOWN))); L2R2=$(printf %x $((0x$L2 | 0x$R2)))
# pause menu: L3+R3, then Up from "Resume" wraps to "Quit NES FCEUmm PS5"
# the shelf: Options, then Cross on "Quit"
SHELFQUIT_AT() { echo "$1:$OPTIONS;$(($1 + 2)):0;$(($1 + 10)):$CROSS;$(($1 + 12)):0"; }
# buttons pressed one after the other from frame $1, 8 frames apart
SEQ() { local f=$1 out="" b; shift; for b in "$@"; do out="$out;$f:$b;$((f + 2)):0"; f=$((f + 8)); done; echo "${out#;}"; }
QUITAT() { echo "$1:$L3R3;$(($1 + 2)):0;$(($1 + 10)):$UP;$(($1 + 12)):0;$(($1 + 20)):$CROSS;$(($1 + 22)):0"; }

ok() { echo "  ok: $*"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
expect() { if eval "$1"; then ok "$2"; else bad "$2"; fi; }
want() { [ -z "$ONLY" ] || [[ " $ONLY " == *" $1 "* ]]; }

newroot() {
	local t=$WORK/$1
	rm -rf "$t" && mkdir -p "$t/root/roms" "$t/dump"
	echo "shader=0" >"$t/root/fceumm-ps5.ini" # the plain picture: the colour checks expect it (group 21 tests the shaders)
	echo "$t"
}

run() { # dir pad dumps [args...]
	local t=$1 pad=$2 dumps=$3
	shift 3
	FCEUMM_HOST_OFFLINE=${OFFLINE-1} FCEUMM_COVER_URL=${COVER_URL-} \
	FCEUMM_PS5_ROOT=$t/root FCEUMM_PS5_HOMEBREW=$t/homebrew FCEUMM_HOST_DUMP_DIR=$t/dump FCEUMM_HOST_DUMP=$dumps \
		FCEUMM_HOST_MAX_FLIPS=${MAXFLIPS-5000} FCEUMM_HOST_PAD=$pad ASAN_OPTIONS=detect_leaks=0 timeout 180 "$BIN" "$@" >"$t/out.txt" 2>&1
	echo $?
}
nosan() { expect "! grep -q 'runtime error\|AddressSanitizer' $1/out.txt" "no sanitizer reports"; }

# A game in each format: picture where the log says, Cross -> green, quit from the pause menu.
system_test() { # name ext label [kind]
	local name=$1 ext=$2 label=$3
	local T
	T=$(newroot "$name")
	$ROM "$T/root/roms/test.$ext" ${4:-ntsc} >/dev/null
	local rc
	rc=$(run "$T" "0:0;100:$CROSS;140:0;$(QUITAT 200)" "90,130" "$T/root/roms/test.$ext")
	expect "[ $rc = 0 ]" "$label: exit code 0 (got $rc)"
	expect "grep -q 'running \"test\" (NES)' $T/root/logs/boot.log" "$label: FCEUmm runs it"
	expect "$RECT $T/dump/flip00090.ppm $T/root/logs/boot.log red >/dev/null" "$label: red picture where the log says, black around it"
	expect "$CHECK $T/dump/flip00130.ppm 960 540 green >/dev/null" "$label: Cross -> green"
	nosan "$T"
}

if want 1; then
echo "== 1. NES from the command line: picture, input, quick save (L2 + Up), quit from the pause menu"
T=$(newroot t1)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(run "$T" "0:0;100:$CROSS;140:0;200:$L2UP;205:0;$(QUITAT 220)" "90,130" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "$RECT $T/dump/flip00090.ppm $T/root/logs/boot.log red >/dev/null" "red picture where the log says, black around it"
expect "$CHECK $T/dump/flip00090.ppm 960 540 181 49 32 >/dev/null" "the backdrop is colour \$16 of Mesen's palette (the default), not FCEUmm's"
expect "$CHECK $T/dump/flip00130.ppm 960 540 green >/dev/null" "Cross -> NES B -> green"
expect "[ -f $T/root/states/NES/test.state1 ]" "L2 + Up wrote states/NES/test.state1"
expect "grep -q 'running \"test\" (NES), 60\.[01]' $T/root/logs/boot.log" "a 60 Hz NES game"
expect "grep -q 'save state 1: ok' $T/root/logs/boot.log" "logged the save"
expect "grep -q 'Fit to screen' $T/root/logs/boot.log" "fit to screen by default"
expect "grep -q '\[core\] ' $T/root/logs/boot.log" "the core's own log reaches boot.log"
expect "! grep -q 'header corrected' $T/root/logs/boot.log" "an NES 2.0 header is left as it is"
nosan "$T"
fi

if want 2; then
echo "== 2. the other formats: an iNES 1.0 header, UNIF"
system_test t2ines nes "iNES 1.0" ines1
system_test t2unf unf "UNIF"
fi

if want 3; then
echo "== 3. shelf -> game -> back to the shelf -> quit"
T=$(newroot t3)
$ROM "$T/root/roms/Test Game (USA).nes" >/dev/null
mkdir -p "$T/root/roms/Action"
rc=$(run "$T" "0:0;40:$CROSS;42:0;150:$L3R3;152:0;160:$UP;162:0;164:$UP;166:0;170:$CROSS;172:0;200:$OPTIONS;202:0;210:$CROSS;212:0" "20,35,120,190")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "[ -f $T/dump/flip00020.ppm ]" "the shelf was shown"
expect "$CHECK $T/dump/flip00120.ppm 960 540 red >/dev/null" "the game picked on the shelf runs"
expect "grep -q 'last_rom=.*Test Game (USA).nes' $T/root/fceumm-ps5.ini" "the shelf remembers the last game"
expect "grep -q 'game closed' $T/root/logs/boot.log" "back to the list closed the game"
nosan "$T"
fi

if want 4; then
echo "== 4. a 50 Hz (PAL) game runs at 50 frames a second"
T=$(newroot t4)
$ROM "$T/root/roms/pal.nes" pal >/dev/null
start=$(date +%s.%N)
rc=$(run "$T" "0:0;$(QUITAT 300)" "" "$T/root/roms/pal.nes")
end=$(date +%s.%N)
secs=$(python3 -c "print(round($end - $start, 2))")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "python3 -c 'import sys; sys.exit(0 if 5.0 <= $secs <= 9.5 else 1)'" "300 frames took ${secs}s (~6 s at 50 fps)"
expect "grep -q 'running \"pal\" (NES), 50.0' $T/root/logs/boot.log" "the core runs the PAL game (NES 2.0 timing byte) at 50 Hz"
fi

if want 5; then
echo "== 5. Famicom Disk System without its BIOS: the screen names the file; with it the disk runs and changes sides"
T=$(newroot t5)
mkdir -p "$T/root/roms/FDS" "$T/root/roms/NES"
$ROM "$T/root/roms/FDS/Game (Japan).fds" >/dev/null
$ROM "$T/root/roms/NES/Alpha (USA).nes" >/dev/null
# the shelf: Alpha, then Game; Right -> Game, Cross -> the BIOS message, Cross -> back, Options -> quit
rc=$(run "$T" "0:0;30:$RIGHT;32:0;50:$CROSS;52:0;90:$CROSS;92:0;110:$OPTIONS;112:0;120:$CROSS;122:0" "70")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q '\[games\] 2 ROM(s)' $T/root/logs/boot.log" "the shelf lists the disk and the cartridge"
expect "grep -q 'missing firmware: disksys.rom' $T/root/logs/boot.log" "logged: the BIOS is missing"
expect "grep -q 'could not start .*Game (Japan).fds: missing the Famicom Disk System BIOS' $T/root/logs/boot.log" "the game wasn't started"
expect "[ -f $T/dump/flip00070.ppm ]" "a message was on the screen"
mkdir -p "$T/root/bios" && head -c 8192 /dev/zero >"$T/root/bios/disksys.rom"
# L1: next side (eject, flip, insert a second later); R1: disk in / out; the pause menu has both
rc=$(run "$T" "0:0;100:$L1;104:0;150:$R1;154:0;$(QUITAT 220)" "" "$T/root/roms/FDS/Game (Japan).fds")
expect "[ $rc = 0 ]" "with the BIOS: exit code 0 (got $rc)"
expect "grep -q 'running \"Game (Japan)\" (Famicom Disk System)' $T/root/logs/boot.log && ! grep -q 'missing firmware' $T/root/logs/boot.log" "with bios/disksys.rom the disk goes to the core"
expect "grep -q 'disk: next side' $T/root/logs/boot.log && grep -q 'disk: in / out' $T/root/logs/boot.log" "L1 and R1 work the disk drive"
nosan "$T"
fi

if want 6; then
echo "== 6. integer scale and scanlines from the settings file; load state with L2 + Down"
T=$(newroot t6)
$ROM "$T/root/roms/test.nes" >/dev/null
printf 'scale=1\nscanlines=1\n' >>"$T/root/fceumm-ps5.ini"
rc=$(run "$T" "0:0;60:$L2UP;62:0;80:$L2DOWN;82:0;$(QUITAT 100)" "50" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'Integer scale, scanlines' $T/root/logs/boot.log" "integer scale with scanlines"
expect "$RECT $T/dump/flip00050.ppm $T/root/logs/boot.log red >/dev/null" "red picture where the log says"
expect "python3 - $T/dump/flip00050.ppm <<'PY'
import sys
d = open(sys.argv[1], 'rb').read().split(b'\n', 3)
w, h = map(int, d[1].split()); px = d[3]
reds = {px[(y * w + 960) * 3] for y in range(100, 980)}
top = max(reds)
sys.exit(0 if top >= 150 and any(0.35 * top <= r <= 0.65 * top for r in reds) else 1)
PY" "scanline rows are darker"
expect "grep -q 'load state 1: ok' $T/root/logs/boot.log" "L2 + Down loaded the state"
nosan "$T"
fi

if want 7; then
echo "== 7. a zipped game; the sound stays fed and near the 60 ms target"
T=$(newroot t7)
$ROM "$T/game.nes" >/dev/null
python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED); z.write(sys.argv[2],'game.nes'); z.close()" "$T/root/roms/game.zip" "$T/game.nes"
rc=$(FCEUMM_HOST_REALTIME=1 run "$T" "0:0;$(QUITAT 760)" "100" "$T/root/roms/game.zip")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'loading .*game.zip -> game.nes' $T/root/logs/boot.log" "the game inside the zip is loaded"
expect "$CHECK $T/dump/flip00100.ppm 960 540 red >/dev/null" "the zipped game runs"
u2=$(grep -o 'audio queued .*underruns [0-9]*' "$T/root/logs/boot.log" | sed -n 2p | grep -o '[0-9]*$')
u3=$(grep -o 'audio queued .*underruns [0-9]*' "$T/root/logs/boot.log" | sed -n 3p | grep -o '[0-9]*$')
lat=$(grep -o 'audio queued [0-9]* ([0-9]* ms)' "$T/root/logs/boot.log" | sed -n 3p | grep -o '([0-9]*' | tr -d '(')
under=$(( ${u3:-999} - ${u2:-0} ))
expect "[ $under -le 2 ]" "audio underruns over 5 s of play: $under"
# the floor is low: a slow test machine (ASan, 2 cores) runs a little under 60 fps and drains the ring toward it
expect "[ ${lat:-0} -ge 15 ] && [ ${lat:-0} -le 120 ]" "audio latency ${lat:-?} ms"
nosan "$T"
fi

if want 8; then
echo "== 8. little video memory: 720p scan-out; memory busy at first: retries"
T=$(newroot t8)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(FCEUMM_HOST_DIRECT_MAX_MIB=12 run "$T" "0:0;$(QUITAT 100)" "90" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'scan-out 1280x720' $T/root/logs/boot.log" "fell back to 1280x720"
expect "head -2 $T/dump/flip00090.ppm | grep -q '1280 720'" "the flips are 1280x720"
expect "$RECT $T/dump/flip00090.ppm $T/root/logs/boot.log red >/dev/null" "game picture in place (720p)"
T=$(newroot t8b)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(FCEUMM_HOST_DIRECT_FAIL_FIRST=9 run "$T" "0:0;$(QUITAT 100)" "" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'retrying (1)' $T/root/logs/boot.log && grep -q 'scan-out 1920x1080' $T/root/logs/boot.log" "retried, then got 1080p"
fi

if want 9; then
echo "== 9. NESFCEUmmPS5.elf installs the app (icon and libc.prx included), stays as the helper, repairs"
T=$(newroot t9)
APP=$T/homebrew/PPSA99013
inst() { # dir -> runs the installer; it stays running as the helper when the port is free
	FCEUMM_PS5_ROOT=$1/root FCEUMM_PS5_HOMEBREW=$1/homebrew FCEUMM_PS5_APPMETA=$1/appmeta ASAN_OPTIONS=detect_leaks=0 timeout 60 "$INSTALLER" >>"$1/inst.txt" 2>&1
}
waitfor() { for i in $(seq 1 50); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
stop_helpers() { pkill -f 'build/host/fceumm-ps5-(installer|helper)' 2>/dev/null; pkill -f 'received.elf' 2>/dev/null; sleep 0.3; }
stop_helpers
inst "$T" &
expect "waitfor $T/root/logs/installer.log 'listening on 127.0.0.1'" "the installer stays running as the helper"
expect "cmp -s $APP/sce_sys/icon0.png app/sce_sys/icon0.png" "icon0.png installed (the NES FCEUmm PS5 icon)"
expect "cmp -s $APP/sce_sys/pic0.dds app/sce_sys/pic0.dds && cmp -s $APP/sce_sys/pic1.dds app/sce_sys/pic1.dds && cmp -s $APP/sce_sys/param.json app/sce_sys/param.json" "pic0.dds/pic1.dds (background) and param.json installed"
expect "cmp -s $APP/eboot.bin tests/fake-eboot.bin" "eboot.bin installed"
expect "cmp -s $APP/sce_module/libc.prx tests/fake-libc.prx" "sce_module/libc.prx installed"
expect "grep -q 'NES FCEUmm PS5 [0-9.]* installed. Open it from the NES FCEUmm PS5 icon' $T/inst.txt" "install notification says to open the icon"
expect "! ls $APP/*.part $APP/sce_sys/*.part $APP/sce_module/*.part 2>/dev/null | grep -q ." "no .part files left"
inst "$T"
expect "grep -q 'is up to date' $T/root/logs/installer.log && ! grep -q 'wrote' $T/root/logs/installer.log" "sent again: nothing rewritten"
expect "grep -q 'a helper is already running' $T/root/logs/installer.log" "sent again: the second copy leaves the helper to the first"
echo broken > $APP/sce_sys/icon0.png
inst "$T"
expect "cmp -s $APP/sce_sys/icon0.png app/sce_sys/icon0.png" "a damaged icon is put back"
META=$T/appmeta/PPSA99013
mkdir -p "$META" && echo old > "$META/pic0.png" && echo old > "$META/icon0.png" && cp app/sce_sys/param.json "$META/"
echo old > "$APP/sce_sys/pic0.png"
inst "$T"
expect "cmp -s $META/pic0.dds app/sce_sys/pic0.dds && cmp -s $META/pic1.dds app/sce_sys/pic1.dds && cmp -s $META/icon0.png app/sce_sys/icon0.png" "appmeta gets the background (pic0/pic1.dds) and icon"
expect "[ ! -f $META/pic0.png ] && [ ! -f $APP/sce_sys/pic0.png ]" "an old pic0.png is removed"
expect "grep -q 'Home screen art updated' $T/inst.txt" "the notification says the home screen art changed"
stop_helpers
expect "[ \$(find $T -path '*PPSA99009*' -o -path '*PPSA99010*' -o -path '*PPSA99011*' -o -path '*PPSA99203*' | wc -l) = 0 ]" "nothing written for Snes9x PS5 (PPSA99009), Mesen2 PS5 (PPSA99010), Genesis Plus GX PS5 (PPSA99011) or PS5SX2 (PPSA99203)"
fi

if want 10; then
echo "== 10. covers per system: download, git-symlink, name by CRC, your own cover first, 404 remembered"
T=$(newroot t10)
NESREPO=Nintendo_-_Nintendo_Entertainment_System; FDSREPO=Nintendo_-_Family_Computer_Disk_System
mkdir -p "$T/srv/$NESREPO/Named_Boxarts" "$T/srv/$FDSREPO/Named_Boxarts" "$T/root/covers/NES" "$T/root/roms/NES" "$T/root/roms/FDS"
python3 - "$T/srv" "$T/root/covers" "$NESREPO" "$FDSREPO" <<'PY'
import sys
from PIL import Image
srv, covers, nes, fds = sys.argv[1:5]
m, s = f"{srv}/{nes}/Named_Boxarts", f"{srv}/{fds}/Named_Boxarts"
Image.new('RGB', (512, 357), (255, 0, 0)).save(m + '/Super Mario Bros. (World).png')
Image.new('RGB', (512, 357), (0, 255, 0)).save(m + '/Tetris (Europe).png')
open(m + '/Tetris (USA).png', 'w').write('Tetris (Europe).png')
Image.new('RGB', (512, 357), (255, 255, 0)).save(m + '/Excitebike (Japan, USA).png')
Image.new('RGB', (360, 512), (0, 0, 255)).save(covers + '/NES/Excitebike (Japan, USA).png')
Image.new('RGB', (360, 512), (255, 0, 255)).save(s + '/Akumajou Dracula (Japan).png')
PY
for n in "Super Mario Bros. (World)" "Balloon Fight (USA)" "Excitebike (Japan, USA)"; do $ROM "$T/root/roms/NES/$n.nes" >/dev/null; done
$ROM "$T/root/roms/FDS/Akumajou Dracula (Japan).fds" >/dev/null
$ROM "$T/root/roms/NES/tet.nes" >/dev/null
# the CRC of the ROM past its header (No-Intro's headerless CRC) names it
python3 tests/forge_nes_crc.py "$T/root/roms/NES/tet.nes" $(grep -P "^nes\t[0-9A-F]{8}\tTetris \(USA\)$" frontend/data/nointro.tsv | cut -f2 | head -1) >/dev/null
PORT=18080
(cd "$T/srv" && exec python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) &
SRVPID=$!
sleep 1
# shelf order: Akumajou Dracula, Balloon Fight, Excitebike, Super Mario Bros., Tetris
rc=$(OFFLINE= COVER_URL="http://127.0.0.1:$PORT/\${repo}/Named_Boxarts/\${name}.png" FCEUMM_HOST_REALTIME=1 run "$T" \
	"0:0;180:$RIGHT;182:0;230:$RIGHT;232:0;280:$RIGHT;282:0;330:$RIGHT;332:0;380:$OPTIONS;382:0;390:$CROSS;392:0" "170,220,270,320,370")
kill $SRVPID 2>/dev/null
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'tet.nes \[nes\] -> \"Tetris (USA)\" (by CRC)' $T/root/logs/boot.log" "tet.nes named by its CRC"
expect "[ -f '$T/root/covers/NES/Super Mario Bros. (World).png' ]" "an NES cover saved in covers/NES"
expect "[ -f '$T/root/covers/FDS/Akumajou Dracula (Japan).png' ]" "a Famicom Disk System cover from its repository, in covers/FDS"
expect "[ -f '$T/root/covers/NES/Balloon Fight (USA).missing' ]" "a 404 is remembered (.missing)"
expect "grep -q 'is a link to Tetris (Europe).png' $T/root/logs/boot.log" "a git-symlink cover is followed"
expect "! grep -q 'GET .*Excitebike' $T/root/logs/boot.log" "your own cover (covers/NES/<ROM name>.png): nothing downloaded for it"
expect "$CHECK $T/dump/flip00170.ppm 960 420 255 0 255 >/dev/null" "Akumajou Dracula shows the disk's (magenta) cover"
expect "! $CHECK $T/dump/flip00220.ppm 960 420 255 0 0 >/dev/null 2>&1 && ! $CHECK $T/dump/flip00220.ppm 960 420 0 255 0 >/dev/null 2>&1" "no cover online: a placeholder card"
# 1.1 (genplusgxPS5 issue #4): the card's emblem, top right, is the NES pad -- a light grey plate, Select and Start, the two
# red buttons (B, A) on a dark panel --, no longer the SNES pad's four coloured buttons (red, yellow, green, blue: sampled
# where they were)
P=$T/dump/flip00220.ppm
expect "! $CHECK $P 1201 227 225 60 70 40 >/dev/null && ! $CHECK $P 1238 195 240 200 60 40 >/dev/null && ! $CHECK $P 1275 227 70 180 90 40 >/dev/null && ! $CHECK $P 1238 258 70 110 230 40 >/dev/null" "the placeholder card no longer shows the SNES pad's four coloured buttons"
expect "$CHECK $P 1222 227 186 32 40 12 >/dev/null && $CHECK $P 1273 227 186 32 40 12 >/dev/null && $CHECK $P 1201 227 44 44 54 12 >/dev/null && $CHECK $P 1127 233 60 60 72 12 >/dev/null && $CHECK $P 1238 195 198 198 208 16 >/dev/null && $CHECK $P 1238 258 198 198 208 16 >/dev/null" "it shows the NES pad: B and A (red) on their dark panel, Select and Start, the grey plate"
expect "$CHECK $T/dump/flip00270.ppm 960 420 0 0 255 >/dev/null" "Excitebike shows your own (blue) cover, not the server's"
expect "$CHECK $T/dump/flip00320.ppm 960 420 255 0 0 >/dev/null" "Super Mario Bros. shows the downloaded (red) cover"
expect "$CHECK $T/dump/flip00370.ppm 960 420 0 255 0 >/dev/null" "Tetris shows the linked (green) cover"
nosan "$T"
# a title of four lines starts below the pad: no letter (white) on the plate's left part, where Select and Start are
T=$(newroot t10long)
$ROM "$T/root/roms/The Legend of the Mystical Ninja Starring Goemon and the Long Long Title Adventure (USA).nes" >/dev/null
rc=$(run "$T" "0:0;$(SHELFQUIT_AT 70)" "60")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "python3 - $T/dump/flip00060.ppm <<'PY'
import sys
from PIL import Image
a = Image.open(sys.argv[1]).convert('RGB')
white = sum(1 for y in range(192, 263) for x in range(1100, 1186) if min(a.getpixel((x, y))) >= 225)
sys.exit(0 if white == 0 else 1)
PY" "a long title is drawn below the NES pad, not over it"
nosan "$T"
fi

if want 11; then
echo "== 11. offline: no download is tried, the shelf still works"
T=$(newroot t11)
$ROM "$T/root/roms/Super Mario Bros. (World).nes" >/dev/null
rc=$(run "$T" "0:0;30:$OPTIONS;32:0;40:$CROSS;42:0" "20")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'not connected' $T/root/logs/boot.log && ! grep -q 'GET ' $T/root/logs/boot.log" "no request made without a network"
fi

if want 12; then
echo "== 12. the shelf's tabs: All, # and the letters that have games; Down/Up go through them; the game picked there runs"
T=$(newroot t12)
$ROM "$T/root/roms/Alpha (USA).nes" >/dev/null
$ROM "$T/root/roms/1942 (Japan, USA).nes" >/dev/null
$ROM "$T/root/roms/Beta (USA).nes" >/dev/null
$ROM "$T/root/roms/The Gamma (USA).unf" >/dev/null
# tabs: All, #, A, B, T. Down x5 -> back to All; Up -> T; Up x3 -> #; Cross -> 1942
P="0:0;30:$DOWN;32:0;36:$DOWN;38:0;42:$DOWN;44:0;48:$DOWN;50:0;54:$DOWN;56:0;60:$UP;62:0;66:$UP;68:0;72:$UP;74:0;78:$UP;80:0;100:$CROSS;102:0"
rc=$(run "$T" "$P;$(QUITAT 200)" "190")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q '\[shelf\] tab #: 1 game(s)' $T/root/logs/boot.log" "the # tab: the game whose name starts with a number"
expect "grep -q '\[shelf\] tab A: 1 game(s)' $T/root/logs/boot.log && grep -q '\[shelf\] tab B: 1 game(s)' $T/root/logs/boot.log && grep -q '\[shelf\] tab T: 1 game(s)' $T/root/logs/boot.log" "a tab per first letter: A, B, T"
expect "[ \$(grep -c '\[shelf\] tab All games: 4 game(s)' $T/root/logs/boot.log) = 1 ] && ! grep -q '\[shelf\] tab C:' $T/root/logs/boot.log" "no empty letters: Down five times is back at All games"
expect "grep -q 'loading .*1942 (Japan, USA).nes' $T/root/logs/boot.log" "the game was started from its tab"
expect "grep -q 'shelf_family=1$' $T/root/fceumm-ps5.ini" "the tab is remembered"
expect "$CHECK $T/dump/flip00190.ppm 960 540 red >/dev/null" "the game runs"
nosan "$T"
fi

if want 13; then
echo "== 13. settings from the shelf (Triangle); fast forward (R2) and rewind (L2 + R2); the pause menu saves a state"
T=$(newroot t13)
$ROM "$T/root/roms/Alpha (USA).nes" >/dev/null
# Triangle -> settings ("Shader" first, Down -> "Screen size"), Right -> integer scale, Circle -> back; Cross -> play
rc=$(FCEUMM_HOST_REALTIME=1 run "$T" "0:0;30:$TRIANGLE;32:0;36:$DOWN;38:0;40:$RIGHT;42:0;50:$CIRCLE;52:0;70:$CROSS;72:0;150:$R2;250:0;300:$L2R2;340:0;360:$L3R3;362:0;370:$DOWN;372:0;380:$CROSS;382:0;400:$CIRCLE;402:0;$(QUITAT 440)" "45")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'scale=1' $T/root/fceumm-ps5.ini" "the settings screen changed the screen size"
expect "grep -q 'fast forward on' $T/root/logs/boot.log && grep -q 'fast forward off' $T/root/logs/boot.log" "R2 held: fast forward"
expect "grep -q 'rewind on' $T/root/logs/boot.log && grep -q 'rewind off' $T/root/logs/boot.log" "L2 + R2 held: rewind"
expect "[ -f '$T/root/states/NES/Alpha (USA).state1' ]" "the pause menu's Save state wrote slot 1"
nosan "$T"
fi

if want 14; then
echo "== 14. the pad is shared with the system (handle 0x809b0081, as on the console)"
T=$(newroot t14)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(FCEUMM_HOST_PAD_SHARED=1 FCEUMM_HOST_REALTIME=1 run "$T" "0:0;100:$CROSS;140:0;$(QUITAT 300)" "130" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'using 809b0081 (shared with the system)' $T/root/logs/boot.log" "the system's handle is used"
expect "[ \$(grep -c 'scePadOpen' $T/root/logs/boot.log) = 1 ]" "opened once, not every 2 seconds"
expect "$CHECK $T/dump/flip00130.ppm 960 540 green >/dev/null" "its buttons reach the game (Cross -> green)"
fi

if want 15; then
echo "== 15. the app asks the helper to let it out of the sandbox"
waitfor() { for i in $(seq 1 50); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
stop_helpers() { pkill -f 'build/host/fceumm-ps5-(installer|helper)' 2>/dev/null; pkill -f 'received.elf' 2>/dev/null; sleep 0.3; }
T=$(newroot t15)
$ROM "$T/root/roms/test.nes" >/dev/null
QUIT=$(QUITAT 30)
FCEUMM_PS5_ROOT=$T/hroot ASAN_OPTIONS=detect_leaks=0 timeout 60 "$HELPER" >"$T/helper.txt" 2>&1 &
waitfor "$T/hroot/logs/helper.log" "listening" || sleep 1
rc=$(run "$T" "$QUIT" "" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'FCEUmm helper (port [0-9]*): ret 0' $T/root/logs/boot.log" "the helper said yes"
expect "grep -q 'jailbreak: FCEUmm helper' $T/root/logs/boot.log" "logged before /data was open, written to boot.log"
expect "grep -q 'letting it out' $T/hroot/logs/helper.log" "the helper let the app's process out"
stop_helpers
T=$(newroot t15b)
$ROM "$T/root/roms/test.nes" >/dev/null
FCEUMM_HOST_JB_TITLE=PPSA99009 FCEUMM_PS5_ROOT=$T/hroot ASAN_OPTIONS=detect_leaks=0 timeout 60 "$HELPER" >"$T/helper.txt" 2>&1 &
waitfor "$T/hroot/logs/helper.log" "listening" || sleep 1
rc=$(run "$T" "$QUIT" "" "$T/root/roms/test.nes")
expect "grep -q 'title PPSA99009 is not NES FCEUmm PS5' $T/hroot/logs/helper.log" "the helper lets out no other title (not even Snes9x PS5)"
stop_helpers

echo "== 16. no helper running: the app hands its own helper to the ELF loader, then asks it"
T=$(newroot t16)
$ROM "$T/root/roms/test.nes" >/dev/null
python3 - "$FCEUMM_ELFLDR_PORT" "$T" <<'PY' &
import os, socket, subprocess, sys
port, t = int(sys.argv[1]), sys.argv[2]
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', port)); s.listen(1); s.settimeout(60)
c, _ = s.accept()
data = b''
while True:
    d = c.recv(65536)
    if not d: break
    data += d
path = t + '/received.elf'
open(path, 'wb').write(data); os.chmod(path, 0o755)
env = dict(os.environ, FCEUMM_PS5_ROOT=t + '/hroot', ASAN_OPTIONS='detect_leaks=0')
p = subprocess.Popen(['timeout', '30', path], env=env, stdout=open(t + '/helper.txt', 'w'), stderr=subprocess.STDOUT)
open(t + '/helper.pid', 'w').write(str(p.pid))
PY
LPID=$!
sleep 0.5
rc=$(run "$T" "$QUIT" "" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "cmp -s $T/received.elf $HELPER" "the ELF loader got the helper built into the app"
expect "grep -q 'jailbreak: FCEUmm helper (started by the app)' $T/root/logs/boot.log" "then the helper it started let it out"
wait $LPID 2>/dev/null
stop_helpers
fi

if want 17; then
echo "== 17. no /data even so: the screen says what to do; the screen busy at first: retries"
T=$(newroot t17)
rm -rf "$T/root" && echo "not a folder" >"$T/root" # the app can't create its folders there
rc=$(run "$T" "0:0;30:$CROSS;32:0" "20")
expect "[ $rc = 2 ]" "exit code 2 (got $rc)"
expect "grep -q 'no access to /data' $T/out.txt" "logged: no access to /data"
expect "[ -f $T/dump/flip00020.ppm ]" "a message was on the screen"
T=$(newroot t17b)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(FCEUMM_HOST_VIDEO_BUSY=3 run "$T" "$(QUITAT 30)" "" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "[ \$(grep -c 'sceVideoOutOpen -> .*80290009' $T/root/logs/boot.log) = 3 ] && grep -q 'scan-out 1920x1080' $T/root/logs/boot.log" "VideoOut busy three times, then opened"
expect "grep -q 'splash screen hidden' $T/root/logs/boot.log" "the splash screen is hidden"
fi

if want 18; then
echo "== 18. covers in the background: the helper downloads them while the shelf runs; an older helper: the prefetch"
waitfor() { for i in $(seq 1 50); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
stop_helpers() { pkill -f 'build/host/fceumm-ps5-(installer|helper)' 2>/dev/null; pkill -f 'received.elf' 2>/dev/null; sleep 0.3; }
stop_helpers
T=$(newroot t18)
SRV=$T/srv/Nintendo_-_Nintendo_Entertainment_System/Named_Boxarts; mkdir -p "$SRV" "$T/root/covers"
COVER="Super Mario Bros. (World).png"
python3 -c "from PIL import Image; Image.new('RGB',(512,357),(255,0,0)).save('$SRV/$COVER')"
$ROM "$T/root/roms/Super Mario Bros. (World).nes" >/dev/null
PORT=18081
(cd "$T/srv" && exec python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) &
SRVPID=$!
FCEUMM_PS5_ROOT=$T/root ASAN_OPTIONS=detect_leaks=0 timeout 120 "$HELPER" >"$T/helper.txt" 2>&1 &
waitfor "$T/root/logs/helper.log" "listening" || sleep 1
URL="http://127.0.0.1:$PORT/\${repo}/Named_Boxarts/\${name}.png"
rc=$(OFFLINE= COVER_URL="$URL" FCEUMM_HOST_REALTIME=1 run "$T" "0:0;300:$OPTIONS;302:0;310:$CROSS;312:0" "20,280")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'the helper downloads the covers while the app runs: nothing to wait for' $T/root/logs/boot.log && ! grep -q 'restarting' $T/root/logs/boot*.log" "the app starts at once: no download before /data, no restart"
expect "grep -q 'NES/Super Mario Bros. (World).png' $T/root/covers/wanted.txt" "the missing cover goes to covers/wanted.txt"
expect "grep -q 'NES/Super Mario Bros. (World).png -> 200' $T/root/logs/helper.log && cmp -s '$T/root/covers/NES/$COVER' '$SRV/$COVER'" "the helper downloaded it into covers/NES"
expect "! $CHECK $T/dump/flip00020.ppm 960 420 255 0 0 >/dev/null 2>&1 && $CHECK $T/dump/flip00280.ppm 960 420 255 0 0 >/dev/null" "the shelf showed its card, then the cover once it landed"
expect "grep -q '^0 1 idle' $T/root/covers/progress.txt" "covers/progress.txt: nothing left, 1 fetched"
kill $SRVPID 2>/dev/null
stop_helpers
# an older helper (1.4's protocol: the list without "covers: background"): the prefetch before /data, as before
T=$(newroot t18b)
mkdir -p "$T/srv/Nintendo_-_Nintendo_Entertainment_System/Named_Boxarts" "$T/root/covers"
cp "$SRV/$COVER" "$T/srv/Nintendo_-_Nintendo_Entertainment_System/Named_Boxarts/"
$ROM "$T/root/roms/Super Mario Bros. (World).nes" >/dev/null
(cd "$T/srv" && exec python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) &
SRVPID=$!
printf 'NES/%s\thttp://127.0.0.1:%s/Nintendo_-_Nintendo_Entertainment_System/Named_Boxarts/Super%%20Mario%%20Bros.%%20%%28World%%29.png\n' "$COVER" $PORT >"$T/wanted.txt"
python3 - "$FCEUMM_HELPER_PORT" "$T/wanted.txt" <<'PY' &
import socket, struct, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', int(sys.argv[1]))); s.listen(4); s.settimeout(60)
text = open(sys.argv[2], 'rb').read()
end = time.time() + 60
while time.time() < end:
    try:
        c, _ = s.accept()
    except OSError:
        break
    req = b''
    while len(req) < 0xA10:
        d = c.recv(0xA10 - len(req))
        if not d: break
        req += d
    if len(req) == 0xA10:
        magic, cmd, pid, ret = struct.unpack_from('<IiiI', req, 0)
        out = bytearray(req)
        if cmd == 6:
            struct.pack_into('<i', out, 12, len(text)); c.sendall(bytes(out) + text)
        elif cmd == 5:
            struct.pack_into('<i', out, 12, 0); out[16:18] = b'ok'; c.sendall(bytes(out))
    c.close()
PY
OLDPID=$!
sleep 0.5
rc=$(OFFLINE= COVER_URL="$URL" run "$T" "0:0;30:$OPTIONS;32:0;40:$CROSS;42:0" "")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q '\[prefetch\] 1 of 1 fetched' $T/root/logs/boot.log && cmp -s '$T/root/covers/NES/$COVER' '$SRV/$COVER'" "an older helper: the cover is prefetched before /data and saved"
kill $OLDPID $SRVPID 2>/dev/null
stop_helpers
fi

if want 19; then
echo "== 19. the system folders: made in roms/ and covers/ at start"
T=$(newroot t19)
$ROM "$T/root/roms/Super Mario Bros. (World).nes" >/dev/null
rc=$(run "$T" "0:0;60:$OPTIONS;62:0;70:$CROSS;72:0" "50")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
for d in NES FDS; do
	expect "[ -d $T/root/roms/$d ] && [ -d $T/root/covers/$d ]" "roms/$d and covers/$d made"
done
expect "[ -f $T/dump/flip00050.ppm ]" "the shelf came up"
nosan "$T"
fi

if want 20; then
echo "== 20. controls: the button layout, turbo, the settings screen (CONTROLS)"
T=$(newroot t20)
$ROM "$T/root/roms/test.nes" >/dev/null
# B moved from Cross to Triangle: Cross does nothing, Triangle is B (green)
printf 'btn_b=3\n' >>"$T/root/fceumm-ps5.ini"
rc=$(run "$T" "0:0;100:$CROSS;140:0;160:$TRIANGLE;200:0;$(QUITAT 220)" "130,190" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "$CHECK $T/dump/flip00130.ppm 960 540 red >/dev/null" "B on Triangle: Cross no longer presses B"
expect "$CHECK $T/dump/flip00190.ppm 960 540 green >/dev/null" "B on Triangle: Triangle presses B"
expect "grep -q 'controllers: 4 pads' $T/root/logs/boot.log" "four pads plugged in (FCEUmm adds the Four Score for the games that use one)"
# Turbo B (Square by default): held, B goes on and off by itself
T=$(newroot t20b)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(run "$T" "0:0;150:$SQUARE;200:0;$(QUITAT 220)" "$(seq -s, 170 185)" "$T/root/roms/test.nes")
reds=0; greens=0
for f in $(seq 170 185); do
	$CHECK $T/dump/flip00$f.ppm 960 540 red >/dev/null 2>&1 && reds=$((reds + 1))
	$CHECK $T/dump/flip00$f.ppm 960 540 green >/dev/null 2>&1 && greens=$((greens + 1))
done
expect "[ $rc = 0 ] && [ $reds -ge 3 ] && [ $greens -ge 3 ]" "Square held: turbo B ($reds red, $greens green frames of 16)"
nosan "$T"
# the settings screen: Turbo speed is the first CONTROLS row (20 rows below Shader), then A
T=$(newroot t20d)
$ROM "$T/root/roms/Alpha (USA).nes" >/dev/null
rc=$(run "$T" "0:0;30:$TRIANGLE;32:0;40:$DOWN;42:0;46:$DOWN;48:0;52:$DOWN;54:0;58:$DOWN;60:0;64:$DOWN;66:0;70:$DOWN;72:0;76:$DOWN;78:0;82:$DOWN;84:0;88:$DOWN;90:0;94:$DOWN;96:0;100:$DOWN;102:0;106:$DOWN;108:0;112:$DOWN;114:0;118:$DOWN;120:0;124:$DOWN;126:0;130:$DOWN;132:0;136:$DOWN;138:0;142:$DOWN;144:0;148:$DOWN;150:0;154:$DOWN;156:0;166:$RIGHT;168:0;172:$DOWN;174:0;178:$RIGHT;180:0;188:$CIRCLE;190:0;198:$OPTIONS;200:0;206:$CROSS;208:0" "184")
expect "[ $rc = 0 ]" "settings screen: exit code 0 (got $rc)"
expect "grep -q '^turbo=3$' $T/root/fceumm-ps5.ini" "the settings screen changed the turbo speed"
expect "grep -q '^btn_a=2$' $T/root/fceumm-ps5.ini" "the settings screen moved A to Square"
nosan "$T"
fi

if want 21; then
echo "== 21. CRT shaders: CRT Easymode style by default, every shader draws, the choice is kept"
SHADERS=("Off" "CRT Easymode style" "crt-lottes" "crt-lottes-fast" "crt-1tap" "crt-2tap" "crt-hyllian-fast" "crt-nobody" "newpixie-mini" "crt-blurPi-sharp" "crt-blurPi-soft" "monoCRT")
T=$(newroot t21)
rm -f "$T/root/fceumm-ps5.ini" # a first start: no settings file yet
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(run "$T" "0:0;100:$CROSS;140:0;$(QUITAT 160)" "90,130" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'shader CRT Easymode style' $T/root/logs/boot.log" "a first start draws the game through CRT Easymode style"
expect "python3 - $T/dump/flip00090.ppm <<'PY'
import sys
d = open(sys.argv[1], 'rb').read().split(b'\n', 3)
w, h = map(int, d[1].split()); px = d[3]
R = lambda x, y: px[(y * w + x) * 3]
col = [R(960, y) for y in range(400, 460)] # down the middle: scanlines
row = [R(x, 540) for x in range(900, 960)] # across: the aperture grille
sys.exit(0 if max(col) > 150 and min(col) < 0.85 * max(col) and len(set(row)) > 1 else 1)
PY" "scanlines and a phosphor mask on the red picture"
expect "$CHECK $T/dump/flip00130.ppm 960 540 green >/dev/null || python3 -c \"import sys; d=open('$T/dump/flip00130.ppm','rb').read().split(b'\\n',3); w=int(d[1].split()[0]); p=d[3]; sys.exit(0 if max(p[(y*w+960)*3+1] for y in range(520,560)) > 150 else 1)\"" "Cross -> green through the shader"
expect "grep -q 'shader [0-9.]* ms' $T/root/logs/boot.log" "the shader's drawing time is logged"
nosan "$T"
for s in $(seq 1 11); do
	T=$(newroot t21s$s)
	echo "shader=$s" >>"$T/root/fceumm-ps5.ini"
	$ROM "$T/root/roms/test.nes" >/dev/null
	rc=$(run "$T" "0:0;$(QUITAT 100)" "90" "$T/root/roms/test.nes")
	expect "[ $rc = 0 ] && grep -q 'shader ${SHADERS[$s]})' $T/root/logs/boot.log && python3 -c \"import sys; d=open('$T/dump/flip00090.ppm','rb').read().split(b'\\n',3); w=int(d[1].split()[0]); p=d[3]; sys.exit(0 if max(p[(y*w+960)*3] for y in range(500,580)) > 60 else 1)\"" "${SHADERS[$s]} draws the picture"
	expect "! grep -q 'runtime error\|AddressSanitizer' $T/out.txt" "${SHADERS[$s]}: no sanitizer reports"
done
T=$(newroot t21m)
$ROM "$T/root/roms/Alpha (USA).nes" >/dev/null
# Triangle -> settings, the first row is Shader: Right twice -> crt-lottes-fast; Circle -> back; Options + Cross -> quit
rc=$(run "$T" "0:0;30:$TRIANGLE;32:0;40:$RIGHT;42:0;46:$RIGHT;48:0;52:$RIGHT;54:0;60:$CIRCLE;62:0;70:$OPTIONS;72:0;80:$CROSS;82:0" "50")
expect "grep -q '^shader=3$' $T/root/fceumm-ps5.ini" "the settings screen's Shader row is saved (shader=0 -> 3)"
fi

if want 22; then
echo "== 22. the helper: unknown titles refused, a slow client can't block it, wanted.txt must be a plain file"
waitfor() { for i in $(seq 1 50); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
stop_helpers() { pkill -f 'build/host/fceumm-ps5-(installer|helper)' 2>/dev/null; pkill -f 'received.elf' 2>/dev/null; sleep 0.3; }
stop_helpers
T=$(newroot t22)
$ROM "$T/root/roms/test.nes" >/dev/null
# a process whose title can't be read (here: the host reports none) is not let out
FCEUMM_HOST_JB_TITLE= FCEUMM_PS5_ROOT=$T/hroot ASAN_OPTIONS=detect_leaks=0 timeout 60 "$HELPER" >"$T/helper.txt" 2>&1 &
waitfor "$T/hroot/logs/helper.log" "listening" || sleep 1
rc=$(run "$T" "$(QUITAT 30)" "" "$T/root/roms/test.nes")
expect "grep -q 'title unknown: not NES FCEUmm PS5' $T/hroot/logs/helper.log && ! grep -q 'letting it out' $T/hroot/logs/helper.log" "a process of unknown title is refused (fail closed)"
stop_helpers
# a client that sends one byte a second doesn't hold the helper: the app's request still goes through
T=$(newroot t22b)
$ROM "$T/root/roms/test.nes" >/dev/null
FCEUMM_PS5_ROOT=$T/hroot ASAN_OPTIONS=detect_leaks=0 timeout 60 "$HELPER" >"$T/helper.txt" 2>&1 &
waitfor "$T/hroot/logs/helper.log" "listening" || sleep 1
python3 - "$FCEUMM_HELPER_PORT" <<'PY' &
import socket, sys, time
s = socket.create_connection(('127.0.0.1', int(sys.argv[1])))
try:
    for i in range(20):
        s.send(b'x'); time.sleep(1)
except OSError:
    pass
PY
DRIP=$!
sleep 0.5
start=$(date +%s)
rc=$(run "$T" "$(QUITAT 30)" "" "$T/root/roms/test.nes")
secs=$(( $(date +%s) - start ))
expect "grep -q 'FCEUmm helper (port [0-9]*): ret 0' $T/root/logs/boot.log" "with a slow client connected, the app is still let out"
expect "[ $secs -lt 15 ]" "and without waiting for the slow client (${secs}s)"
kill $DRIP 2>/dev/null
stop_helpers
# covers/wanted.txt as a symbolic link to another file: not read
T=$(newroot t22c)
mkdir -p "$T/hroot/covers"
echo "secret" >"$T/secret.txt"
ln -s "$T/secret.txt" "$T/hroot/covers/wanted.txt"
FCEUMM_PS5_ROOT=$T/hroot ASAN_OPTIONS=detect_leaks=0 timeout 60 "$HELPER" >"$T/helper.txt" 2>&1 &
waitfor "$T/hroot/logs/helper.log" "listening" || sleep 1
python3 - "$FCEUMM_HELPER_PORT" "$T/answer.bin" <<'PY'
import socket, struct, sys
s = socket.create_connection(('127.0.0.1', int(sys.argv[1])))
req = bytearray(0xA10)
struct.pack_into('<IiI', req, 0, 0xDEADBEEF, 6, 1234)
s.sendall(req)
data = b''
while True:
    d = s.recv(65536)
    if not d: break
    data += d
open(sys.argv[2], 'wb').write(data)
PY
expect "grep -q 'wanted-covers list, 0 bytes' $T/hroot/logs/helper.log && ! grep -q secret $T/answer.bin" "a wanted.txt that is a symbolic link is not followed"
stop_helpers
fi

if want 23; then
echo "== 23. saves: one folder per system, an erased battery save is written, unchanged ones aren't"
# a cartridge and a disk of the same name: each its own state
T=$(newroot t23)
$ROM "$T/root/roms/test.nes" >/dev/null
$ROM "$T/root/roms/test.fds" >/dev/null
mkdir -p "$T/root/bios" && head -c 8192 /dev/zero >"$T/root/bios/disksys.rom"
rc=$(run "$T" "0:0;100:$L2UP;105:0;$(QUITAT 140)" "" "$T/root/roms/test.nes")
rc2=$(run "$T" "0:0;100:$L2DOWN;105:0;$(QUITAT 140)" "" "$T/root/roms/test.fds")
expect "[ $rc = 0 ] && [ $rc2 = 0 ]" "exit codes 0 (got $rc, $rc2)"
expect "[ -f $T/root/states/NES/test.state1 ] && [ ! -e $T/root/states/FDS/test.state1 ]" "the cartridge's state went to states/NES/"
expect "! grep -q 'load state 1' $T/root/logs/boot.log" "the disk of the same name didn't load it"
nosan "$T"
# battery RAM: the game writes \$42; then erases it (\$FF while B is held) -- the erase must reach the file
T=$(newroot t23c)
$ROM "$T/root/roms/save.nes" sram >/dev/null
rc=$(run "$T" "0:0;$(QUITAT 100)" "" "$T/root/roms/save.nes")
S=$T/root/saves/NES/save.srm
expect "[ -f $S ] && python3 -c 'import sys; sys.exit(0 if 0x42 in open(\"$S\",\"rb\").read() else 1)'" "the battery save holds what the game wrote"
ino=$(stat -c %i "$S" 2>/dev/null)
rc=$(run "$T" "0:0;$(QUITAT 100)" "" "$T/root/roms/save.nes")
expect "[ \"$(stat -c %i "$S" 2>/dev/null)\" = '$ino' ]" "an unchanged battery save isn't written again"
rc=$(run "$T" "0:0;20:$CROSS;$(QUITAT 100)" "" "$T/root/roms/save.nes")
expect "[ -f $S ] && python3 -c 'import sys; sys.exit(1 if 0x42 in open(\"$S\",\"rb\").read() else 0)'" "the game's erase was saved"
nosan "$T"
fi

if want 24; then
echo "== 24. audit fixes: 720p picture edges, Resume doesn't press B, odd library files, long paths, covers kept, downloads after a tab change"
# 720p: the whole picture follows the game, its left edge included (the damage is mapped to 1280x720)
T=$(newroot t24)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(FCEUMM_HOST_DIRECT_MAX_MIB=12 run "$T" "0:0;100:$CROSS;140:0;$(QUITAT 200)" "130" "$T/root/roms/test.nes")
expect "grep -q 'scan-out 1280x720' $T/root/logs/boot.log" "720p scan-out"
expect "$CHECK $T/dump/flip00130.ppm 180 360 green >/dev/null && $CHECK $T/dump/flip00130.ppm 1100 360 green >/dev/null" "720p: Cross turns the picture green to its edges"
nosan "$T"
# Resume with Cross: while Cross is still held the game doesn't see B (the picture stays red)
T=$(newroot t24b)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(run "$T" "0:0;100:$L3R3;102:0;120:$CROSS;200:0;$(QUITAT 260)" "190" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "$CHECK $T/dump/flip00190.ppm 960 540 red >/dev/null" "Cross held after Resume doesn't reach the game"
nosan "$T"
# the library: a FIFO doesn't hang the scan; a zip entry with a 600-character name; a .nes that isn't one
T=$(newroot t24c)
mkdir -p "$T/root/roms/NES"
mkfifo "$T/root/roms/NES/pipe.nes"
$ROM "$T/root/roms/NES/a.nes" >/dev/null
$ROM "$T/root/roms/NES/b.nes" >/dev/null
echo "not a game" >"$T/root/roms/NES/notes.nes"
python3 - "$T/root/roms/NES/long.zip" "$T/root/roms/NES/a.nes" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('x' * 600 + '.nes', b'\0' * 1024)
    z.write(sys.argv[2], 'inner.nes')
PY
rc=$(MAXFLIPS=400 run "$T" "0:0;30:$OPTIONS;32:0;40:$CROSS;42:0" "")
expect "[ $rc = 0 ]" "the shelf came up and quit (got $rc)"
expect "! grep -q 'pipe.nes' $T/root/logs/boot.log" "a FIFO is not listed (nor read)"
expect "grep -q 'long.zip \[nes\]' $T/root/logs/boot.log" "a zip with a 600-character entry name still lists its game"
expect "grep -q 'NES/b.nes' $T/root/covers/crc-cache.txt" "the CRC cache holds b.nes"
rm -f "$T/root/roms/NES/b.nes"
rc=$(MAXFLIPS=400 run "$T" "0:0;30:$OPTIONS;32:0;40:$CROSS;42:0" "")
expect "! grep -q 'NES/b.nes' $T/root/covers/crc-cache.txt" "a deleted ROM leaves the CRC cache"
rc=$(MAXFLIPS=300 run "$T" "0:0" "" "$T/root/roms/NES/notes.nes")
expect "grep -q 'could not start .*notes.nes' $T/root/logs/boot.log" "a file that isn't a game: refused, nothing breaks"
nosan "$T"
# a path of 255 characters or more: refused with a message, nothing overflows
T=$(newroot t24d)
D="$T/root/roms/$(printf 'd%.0s' $(seq 1 120))/$(printf 'e%.0s' $(seq 1 120))"
mkdir -p "$D"
$ROM "$D/test.nes" >/dev/null
rc=$(MAXFLIPS=300 run "$T" "0:0;100:$CROSS;102:0" "" "$D/test.nes")
expect "grep -q 'the path is [0-9]* characters long' $T/root/logs/boot.log" "a too-long path is refused"
nosan "$T"
# Square (fetch the cover again) while offline: the cover it has is kept
T=$(newroot t24e)
mkdir -p "$T/root/roms/NES" "$T/root/covers/NES"
$ROM "$T/root/roms/NES/Super Mario Bros. (World).nes" >/dev/null
python3 -c "from PIL import Image; Image.new('RGB',(512,357),(255,0,0)).save('$T/root/covers/NES/Super Mario Bros. (World).png')"
rc=$(run "$T" "0:0;40:$SQUARE;42:0;80:$OPTIONS;82:0;90:$CROSS;92:0" "")
expect "[ -s '$T/root/covers/NES/Super Mario Bros. (World).png' ]" "offline, Square doesn't delete the cover"
nosan "$T"
# online, Square on a ROM named as its official name (its downloaded cover is also "the cover named after the ROM"):
# the server has none (404) -> the cover stays; the server has it -> the new one replaces it
cp "$T/root/covers/NES/Super Mario Bros. (World).png" "$T/old.png"
SRV=$T/srv/Nintendo_-_Nintendo_Entertainment_System/Named_Boxarts; mkdir -p "$SRV"
PORT=18094
(cd "$T/srv" && exec python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) &
SRVPID=$!
sleep 1
URL="http://127.0.0.1:$PORT/\${repo}/Named_Boxarts/\${name}.png"
SQ="0:0;40:$SQUARE;42:0;200:$OPTIONS;202:0;210:$CROSS;212:0"
rc=$(OFFLINE= COVER_URL="$URL" FCEUMM_HOST_REALTIME=1 run "$T" "$SQ" "")
expect "cmp -s '$T/root/covers/NES/Super Mario Bros. (World).png' $T/old.png && [ ! -e '$T/root/covers/NES/Super Mario Bros. (World).refetch' ]" "the server has none (404): the cover stays"
python3 -c "from PIL import Image; Image.new('RGB',(512,357),(0,255,0)).save('$SRV/Super Mario Bros. (World).png')"
rm -f "$T/root/covers/NES/"*.missing
rc=$(OFFLINE= COVER_URL="$URL" FCEUMM_HOST_REALTIME=1 run "$T" "$SQ" "")
kill $SRVPID 2>/dev/null
expect "cmp -s '$T/root/covers/NES/Super Mario Bros. (World).png' '$SRV/Super Mario Bros. (World).png'" "the server has it: the new cover replaces the old one"
nosan "$T"
# as on the console (a helper answers, so the shelf downloads nothing): Square puts the cover on the wanted list
# and the helper fetches it in the background (1.5; no restart); the old cover stays until the new one lands
T2=$(newroot t24g)
mkdir -p "$T2/root/roms/NES" "$T2/root/covers/NES"
$ROM "$T2/root/roms/NES/Super Mario Bros. (World).nes" >/dev/null
cp "$T/old.png" "$T2/root/covers/NES/Super Mario Bros. (World).png"
(cd "$T/srv" && exec python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) &
SRVPID=$!
FCEUMM_PS5_ROOT=$T2/root ASAN_OPTIONS=detect_leaks=0 timeout 60 "$HELPER" >"$T2/helper.txt" 2>&1 &
for i in $(seq 1 50); do grep -q listening "$T2/root/logs/helper.log" 2>/dev/null && break; sleep 0.1; done
rc=$(OFFLINE= COVER_URL="$URL" FCEUMM_HOST_REALTIME=1 run "$T2" "0:0;40:$SQUARE;42:0;300:$OPTIONS;302:0;310:$CROSS;312:0" "")
expect "grep -q 'NES/Super Mario Bros. (World).png' $T2/root/covers/wanted.txt && ! grep -q 'restarting' $T2/root/logs/boot*.log" "console: Square lists the cover for the helper, no restart"
expect "grep -q 'NES/Super Mario Bros. (World).png -> 200' $T2/root/logs/helper.log && cmp -s '$T2/root/covers/NES/Super Mario Bros. (World).png' '$SRV/Super Mario Bros. (World).png' && [ ! -e '$T2/root/covers/NES/Super Mario Bros. (World).refetch' ]" "the helper fetched the new cover over the old one"
kill $SRVPID 2>/dev/null
pkill -f "$HELPER" 2>/dev/null; sleep 0.3
# downloads still work after the shelf restarted its cover worker (another tab)
T=$(newroot t24f)
SRV=$T/srv/Nintendo_-_Nintendo_Entertainment_System/Named_Boxarts; mkdir -p "$SRV" "$T/root/roms/NES" "$T/root/roms/FDS" "$T/root/covers/FDS"
python3 -c "from PIL import Image; Image.new('RGB',(512,357),(255,0,0)).save('$SRV/Super Mario Bros. (World).png'); Image.new('RGB',(360,512),(0,0,255)).save('$T/root/covers/FDS/Akumajou Dracula (Japan).png')"
$ROM "$T/root/roms/NES/Super Mario Bros. (World).nes" >/dev/null
$ROM "$T/root/roms/FDS/Akumajou Dracula (Japan).fds" >/dev/null
echo "shelf_family=2" >>"$T/root/fceumm-ps5.ini" # the A tab: Akumajou Dracula only; Up -> All games
PORT=18082
(cd "$T/srv" && exec python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) &
SRVPID=$!
sleep 1
rc=$(OFFLINE= COVER_URL="http://127.0.0.1:$PORT/\${repo}/Named_Boxarts/\${name}.png" FCEUMM_HOST_REALTIME=1 run "$T" \
	"0:0;60:$UP;62:0;300:$OPTIONS;302:0;310:$CROSS;312:0" "")
kill $SRVPID 2>/dev/null
expect "grep -q 'tab All games' $T/root/logs/boot.log" "moved to another tab (the cover worker restarted)"
expect "cmp -s '$T/root/covers/NES/Super Mario Bros. (World).png' '$SRV/Super Mario Bros. (World).png'" "the new tab's cover was downloaded"
nosan "$T"
fi

if want 25; then
echo "== 25. debug logs off: nothing written (app and helper), earlier logs kept; the setting switches them at once"
SHELFQUIT_AT() { echo "$1:$OPTIONS;$(($1 + 2)):0;$(($1 + 10)):$CROSS;$(($1 + 12)):0"; }
# off in the ini: the game runs, no line anywhere, the previous run's boot.log untouched
T=$(newroot t25)
$ROM "$T/root/roms/test.nes" >/dev/null
echo "debug_logs=0" >>"$T/root/fceumm-ps5.ini"
mkdir -p "$T/root/logs" && echo "OLD RUN" >"$T/root/logs/boot.log"
rc=$(run "$T" "0:0;$(QUITAT 100)" "90" "$T/root/roms/test.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "$CHECK $T/dump/flip00090.ppm 960 540 red >/dev/null" "the game runs"
expect "[ \"\$(cat $T/root/logs/boot.log)\" = 'OLD RUN' ] && [ ! -e $T/root/logs/boot.prev.log ]" "the earlier boot.log is kept as it was, nothing new written"
expect "! grep -q '^\[fceumm-ps5' $T/out.txt" "nothing on stdout either"
expect "grep -q '^debug_logs=0' $T/root/fceumm-ps5.ini" "the setting stays off"
nosan "$T"
# the default (1.0.1): no debug_logs key and no test override -> nothing written, and the settings file says 0
T=$(newroot t25z)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(FCEUMM_LOGS_DEFAULT= run "$T" "0:0;$(QUITAT 100)" "90" "$T/root/roms/test.nes")
expect "[ $rc = 0 ] && [ ! -e $T/root/logs/boot.log ] && ! grep -q '^\[fceumm-ps5' $T/out.txt" "debug logs off by default: no boot.log"
expect "grep -q '^debug_logs=0' $T/root/fceumm-ps5.ini" "the default settings file has debug_logs=0"
nosan "$T"
# Settings (Triangle) -> Debug logs (Up twice from Shader: Back, then Debug logs) -> Off: that line is the last one
T=$(newroot t25b)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(run "$T" "0:0;30:$TRIANGLE;32:0;50:$UP;52:0;60:$UP;62:0;70:$CROSS;72:0;90:$CIRCLE;92:0;$(SHELFQUIT_AT 120)" "")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q '^debug_logs=0' $T/root/fceumm-ps5.ini" "Debug logs Off saved"
expect "tail -1 $T/root/logs/boot.log | grep -q 'debug logs turned off'" "the last line of boot.log says the logs were turned off"
nosan "$T"
# and back on: logging starts again in the same boot.log
T=$(newroot t25c)
$ROM "$T/root/roms/test.nes" >/dev/null
echo "debug_logs=0" >>"$T/root/fceumm-ps5.ini"
rc=$(run "$T" "0:0;30:$TRIANGLE;32:0;50:$UP;52:0;60:$UP;62:0;70:$CROSS;72:0;90:$CIRCLE;92:0;$(SHELFQUIT_AT 120)" "")
expect "grep -q '^debug_logs=1' $T/root/fceumm-ps5.ini" "Debug logs On saved"
expect "grep -q 'debug logs turned on' $T/root/logs/boot.log && ! grep -q 'NES FCEUmm PS5 1\.[0-9.]*, FCEUmm' $T/root/logs/boot.log" "boot.log starts at the switch (nothing from before it)"
nosan "$T"
# the helper follows the setting too
stop_helpers25() { pkill -f 'build/host/fceumm-ps5-(installer|helper)' 2>/dev/null; sleep 0.3; }
stop_helpers25
T=$(newroot t25d)
$ROM "$T/root/roms/test.nes" >/dev/null
mkdir -p "$T/hroot" && echo "debug_logs=0" >"$T/hroot/fceumm-ps5.ini"
FCEUMM_PS5_ROOT=$T/hroot ASAN_OPTIONS=detect_leaks=0 timeout 60 "$HELPER" >"$T/helper.txt" 2>&1 &
sleep 1.5
rc=$(run "$T" "$(QUITAT 30)" "" "$T/root/roms/test.nes")
expect "grep -q 'FCEUmm helper (port [0-9]*): ret 0' $T/root/logs/boot.log" "the helper still lets the app out"
expect "[ ! -e $T/hroot/logs/helper.log ] && ! grep -q 'helper\]' $T/helper.txt" "with debug logs off the helper writes no log"
stop_helpers25
fi

if want 26; then
echo "== 26. the helper's own HTTPS (Mbed TLS): certificate checked, kept connection, chunks, redirects, 404"
stop_helpers26() { pkill -f 'build/host/fceumm-ps5-(installer|helper)' 2>/dev/null; sleep 0.3; }
stop_helpers26
C=$WORK/t26-certs; rm -rf "$C"; mkdir -p "$C"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$C/ca.key" -out "$C/ca.pem" -days 30 -subj "/CN=FCEUmm Test CA" 2>/dev/null
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$C/srv.key" -out "$C/srv.csr" -subj "/CN=localhost" 2>/dev/null
printf 'subjectAltName=DNS:localhost\nbasicConstraints=CA:FALSE\n' >"$C/ext.cnf"
openssl x509 -req -in "$C/srv.csr" -CA "$C/ca.pem" -CAkey "$C/ca.key" -CAcreateserial -out "$C/srv.pem" -days 30 -extfile "$C/ext.cnf" 2>/dev/null
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$C/other.key" -out "$C/other.pem" -days 30 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost" 2>/dev/null
SRVROOT=$WORK/t26-srv; rm -rf "$SRVROOT"; mkdir -p "$SRVROOT/Repo/Named_Boxarts"
python3 -c "
from PIL import Image
for n,c in [('A b',(255,0,0)),('B',(0,255,0)),('C',(0,0,255))]: Image.new('RGB',(512,357),c).save('$SRVROOT/Repo/Named_Boxarts/'+n+'.png')"
PORT=18443
tls_case() { # name cert key mode host -> $T with the helper's run in it
	T=$(newroot "t26-$1")
	mkdir -p "$T/root/covers"
	python3 tests/https_server.py "$SRVROOT" $PORT "$2" "$3" "$4" 2>"$T/server.txt" &
	local sp=$!
	sleep 0.6
	local u="https://$5:$PORT"
	printf 'NES/A.png\t%s/Repo/Named_Boxarts/A%%20b.png\nNES/B.png\t%s/chunked/Repo/Named_Boxarts/B.png\nNES/C.png\t%s/moved/Repo/Named_Boxarts/C.png\nNES/D.png\t%s/Repo/Named_Boxarts/D.png\n' "$u" "$u" "$u" "$u" >"$T/root/covers/wanted.txt"
	FCEUMM_EXTRA_CA=$C/ca.pem FCEUMM_PS5_ROOT=$T/root ASAN_OPTIONS=detect_leaks=0 timeout ${6:-6} "$HELPER" >"$T/helper.txt" 2>&1
	kill $sp 2>/dev/null; wait $sp 2>/dev/null
	stop_helpers26
}
tls_case good "$C/srv.pem" "$C/srv.key" keep localhost
H="$T/root/logs/helper.log"; D="$T/root/covers/NES"; S="$SRVROOT/Repo/Named_Boxarts"
expect "grep -q '\[https\] Mbed TLS 3\.6\.[0-9]*: [0-9]* CA certificate(s), + the extra CA' $H" "Mbed TLS set up with Mozilla's CA list (+ the test CA)"
expect "cmp -s '$D/A.png' '$S/A b.png'" "a cover over HTTPS (Content-Length)"
expect "cmp -s '$D/B.png' '$S/B.png'" "a chunked answer"
expect "cmp -s '$D/C.png' '$S/C.png' && grep -q 'GET /moved/' $T/server.txt" "a redirect followed"
expect "[ -f '$D/D.missing' ] && [ ! -f '$D/D.png' ]" "a 404: marked missing"
expect "[ \$(grep -c 'kept connection' $H) = 3 ]" "one connection for the four requests"
expect "! grep -q '\[http\] ' $H" "the helper doesn't use libSceHttp2"
expect "! grep -q 'runtime error\|AddressSanitizer' $T/helper.txt" "no sanitizer reports"
tls_case untrusted "$C/other.pem" "$C/other.key" keep localhost 4
H="$T/root/logs/helper.log"; D="$T/root/covers/NES"
expect "grep -q 'Certificate verification failed' $H && [ -z \"\$(ls $D 2>/dev/null)\" ]" "a certificate from an unknown CA: refused, nothing saved, nothing marked missing"
tls_case wrongname "$C/srv.pem" "$C/srv.key" keep 127.0.0.1 4
H="$T/root/logs/helper.log"; D="$T/root/covers/NES"
expect "grep -q 'Certificate verification failed' $H && [ -z \"\$(ls $D 2>/dev/null)\" ]" "a certificate for another name: refused"
tls_case closing "$C/srv.pem" "$C/srv.key" drop localhost
D="$T/root/covers/NES"
expect "[ -f '$D/A.png' ] && [ -f '$D/B.png' ] && [ -f '$D/C.png' ]" "a server that closes kept connections: a new one each time"
fi

if want 27; then
echo "== 27. accuracy: header fixes from Mesen's database, the palettes, the console region"
# an iNES 1.0 dump with a wrong header (horizontal, NTSC) of a game the database knows (vertical, PAL)
T=$(newroot t27)
$ROM "$T/root/roms/hdr.nes" ines1 >/dev/null
python3 tests/forge_nes_crc.py "$T/root/roms/hdr.nes" 0C548E97 >/dev/null
cp "$T/root/roms/hdr.nes" "$T/hdr-before.nes"
rc=$(run "$T" "0:0;$(QUITAT 100)" "90" "$T/root/roms/hdr.nes")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'header corrected from Mesen.s database: mapper 0 -> 0.0, mirroring h -> v, .*PAL' $T/root/logs/boot.log" "the header is corrected (mirroring, PAL)"
expect "grep -q 'running \"hdr\" (NES), 50.0' $T/root/logs/boot.log" "the core runs it as the PAL game it is"
expect "cmp -s $T/root/roms/hdr.nes $T/hdr-before.nes" "the ROM file itself is not changed"
expect "$CHECK $T/dump/flip00090.ppm 960 540 red >/dev/null" "the game runs"
nosan "$T"
T=$(newroot t27b)
$ROM "$T/root/roms/hdr.nes" ines1 >/dev/null
python3 tests/forge_nes_crc.py "$T/root/roms/hdr.nes" 0C548E97 >/dev/null
echo "header_db=0" >>"$T/root/fceumm-ps5.ini"
rc=$(run "$T" "0:0;$(QUITAT 100)" "" "$T/root/roms/hdr.nes")
expect "! grep -q 'header corrected' $T/root/logs/boot.log && grep -q 'running \"hdr\" (NES), 60' $T/root/logs/boot.log" "Fix headers off: the header is used as it is"
# the same game with an NES 2.0 header: trusted, not corrected
T=$(newroot t27c)
$ROM "$T/root/roms/n2.nes" >/dev/null
python3 tests/forge_nes_crc.py "$T/root/roms/n2.nes" 0C548E97 >/dev/null
rc=$(FCEUMM_HOST_QUIT_AFTER=3 run "$T" "0:0" "" "$T/root/roms/n2.nes")
expect "! grep -q 'header corrected' $T/root/logs/boot.log && grep -q 'running \"n2\"' $T/root/logs/boot.log" "an NES 2.0 header is trusted"
# palettes: Mesen's by default (checked in group 1), another of the extras, one of FCEUmm's own
for pal in 1 8; do
	T=$(newroot t27p$pal)
	$ROM "$T/root/roms/test.nes" >/dev/null
	echo "palette=$pal" >>"$T/root/fceumm-ps5.ini"
	rc=$(run "$T" "0:0;$(QUITAT 100)" "90" "$T/root/roms/test.nes")
	expect "[ $rc = 0 ] && $CHECK $T/dump/flip00090.ppm 960 540 red >/dev/null && ! $CHECK $T/dump/flip00090.ppm 960 540 181 49 32 2 >/dev/null" "palette=$pal: still red, but not Mesen's red"
	nosan "$T"
done
# the region forced to PAL: an NTSC game runs at 50 Hz
T=$(newroot t27r)
$ROM "$T/root/roms/test.nes" >/dev/null
echo "region=2" >>"$T/root/fceumm-ps5.ini"
rc=$(FCEUMM_HOST_QUIT_AFTER=3 run "$T" "0:0" "" "$T/root/roms/test.nes")
expect "grep -q 'running \"test\" (NES), 50.0' $T/root/logs/boot.log" "Console region PAL: 50 Hz"
fi

if want 28; then
echo "== 28. languages: English by default; Spanish, Portuguese (Brazil), French and German translated"
expect "python3 $PWD/tests/check_i18n.py $PWD/frontend/fe_i18n.cpp >/dev/null" "every translation has its five languages and the English format specifiers"
L2RIGHT=$(printf %x $((0x$L2 | 0x$RIGHT)))
LEFT=80
for L in 1 2 3 4; do
	T=$(newroot t28_$L)
	echo "language=$L" >>"$T/root/fceumm-ps5.ini"
	mkdir -p "$T/root/roms/FDS" "$T/root/roms/NES"
	$ROM "$T/root/roms/NES/Alpha (USA).nes" >/dev/null
	$ROM "$T/root/roms/FDS/Game (Japan).fds" >/dev/null
	# the settings screen scrolled through; the disk without its BIOS (the error box); the game: a save, the next
	# slot, the pause menu walked down, back to the list; quit (the question)
	pad="0:0;20:$TRIANGLE;22:0"; f=30
	for i in $(seq 1 48); do pad="$pad;$f:$DOWN;$((f + 2)):0"; f=$((f + 6)); done
	pad="$pad;$((f + 4)):$CIRCLE;$((f + 6)):0;$((f + 20)):$RIGHT;$((f + 22)):0;$((f + 30)):$CROSS;$((f + 32)):0"; f=$((f + 70))
	pad="$pad;$f:$CROSS;$((f + 2)):0;$((f + 20)):$LEFT;$((f + 22)):0"; f=$((f + 40))
	pad="$pad;$f:$CROSS;$((f + 2)):0"; f=$((f + 100))
	pad="$pad;$f:$L2UP;$((f + 4)):0;$((f + 30)):$L2RIGHT;$((f + 34)):0"; f=$((f + 60))
	pad="$pad;$f:$L3R3;$((f + 2)):0"; f=$((f + 10))
	for i in $(seq 1 11); do pad="$pad;$f:$DOWN;$((f + 2)):0"; f=$((f + 8)); done
	pad="$pad;$((f + 10)):$UP;$((f + 12)):0;$((f + 20)):$CROSS;$((f + 22)):0"; f=$((f + 60))
	pad="$pad;$f:$OPTIONS;$((f + 2)):0;$((f + 10)):$CROSS;$((f + 12)):0"
	rm -f $T/missing.txt
	rc=$(FCEUMM_HOST_I18N_MISSING=$T/missing.txt run "$T" "$pad" "")
	# and the shelf with no games
	T2=$(newroot t28e_$L)
	echo "language=$L" >>"$T2/root/fceumm-ps5.ini"
	rc2=$(FCEUMM_HOST_I18N_MISSING=$T/missing.txt run "$T2" "0:0;40:$OPTIONS;42:0;50:$CROSS;52:0" "")
	# what was shown untranslated: only names (the games', the systems', the buttons') and texts already translated
	python3 - $T/missing.txt $PWD/frontend/fe_i18n.cpp > $T/untranslated.txt <<'PY'
import re, sys
src = open(sys.argv[2], encoding='utf-8').read()
translated = set(re.findall(r'"((?:[^"\\]|\\.)*)"', src))
spec = re.compile(r'%(?:%|[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|z)?[diouxXeEfgGcsp])')
# a text printed from a translated format: the format as a pattern
formats = [re.compile('^' + ''.join('.*' if spec.fullmatch(part) else re.escape(part)
                                    for part in re.split('(' + spec.pattern + ')', f)) + '$')
           for f in translated if '%' in f]
names = {'Alpha (USA)', 'Alpha', 'Game (Japan)', 'Game', 'NES', 'FDS', 'Famicom Disk System', 'L1', 'R1', 'OPTIONS',
         'English', 'Español', 'Português (Brasil)', 'Français', 'Deutsch', 'S-Video', 'RGB', '4:3', '16:9', 'Mesen',
         'Dendy'}
try:
    lines = open(sys.argv[1], encoding='utf-8').read().splitlines()
except FileNotFoundError:
    lines = []
for t in lines:
    if t in translated or t in names or not re.search('[A-Za-z]{2}', t) or re.fullmatch(r'[\d%. ]+', t):
        continue
    if any(f.match(t) for f in formats):
        continue
    if re.match(r'(NES|FDS|Famicom Disk System) {3}', t) or t.startswith('↣'):
        continue
    print(t)
PY
	expect "[ $rc = 0 ] && [ $rc2 = 0 ] && [ -s $T/missing.txt ] && [ ! -s $T/untranslated.txt ]" "language $L: every text shown is translated ($(head -c 200 $T/untranslated.txt | tr '\n' '|'))"
	expect "grep -q 'save state 1: ok' $T/root/logs/boot.log && grep -q 'missing the Famicom Disk System BIOS' $T/root/logs/boot.log && grep -q 'game closed' $T/root/logs/boot.log" "language $L: the walk went through the error box, the game and the pause menu"
	expect "grep -q '^language=$L$' $T/root/fceumm-ps5.ini" "language $L: kept in the settings file"
	nosan "$T"
	rm -rf "$T2"
done
# the network screens (1.1): Settings, Network shares with a share that does not connect, Add a share, the keyboard on
# Server (Circle closes it), the share type switched to NFS, Circle asks to discard (Up, Cross: discard), Connect again;
# back to the shelf: R1 to its Network tab (the share's state), Square scans again, L1 back, quit. Network shares is
# Up four times from Shader (Back, Debug logs, Language, Network shares).
for L in 1 2 3 4; do
	T=$(newroot t28net_$L)
	echo "language=$L" >>"$T/root/fceumm-ps5.ini"
	echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
	$ROM "$T/root/roms/Alpha (USA).nes" >/dev/null
	key() { pad="$pad;$f:$1;$((f + 2)):0"; f=$((f + ${2:-6})); } # one press, then the next one $2 flips later
	pad="0:0;20:$TRIANGLE;22:0"; f=30
	for i in $(seq 1 4); do key $UP; done
	key $CROSS 20; key $DOWN; key $CROSS 20; key $CROSS 20; key $CIRCLE 20
	key $UP; key $RIGHT 20; key $CIRCLE 20; key $UP; key $CROSS 20
	key $DOWN; key $CROSS 20; key $CIRCLE 20; key $CIRCLE 30
	key $R1 30; key $SQUARE 60; key $L1 30
	key $OPTIONS 10; key $CROSS 10
	rm -f $T/missing.txt
	rc=$(FCEUMM_HOST_REALTIME=1 FCEUMM_HOST_NETFS_DIR=$T/nothing FCEUMM_HOST_I18N_MISSING=$T/missing.txt run "$T" "$pad" "")
	python3 - $T/missing.txt $PWD/frontend/fe_i18n.cpp > $T/untranslated.txt <<'PY'
import os, re, sys
src = open(sys.argv[2], encoding='utf-8').read()
translated = set(re.findall(r'"((?:[^"\\]|\\.)*)"', src))
spec = re.compile(r'%(?:%|[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|z)?[diouxXeEfgGcsp])')
formats = [re.compile('^' + ''.join('.*' if spec.fullmatch(part) else re.escape(part)
                                    for part in re.split('(' + spec.pattern + ')', f)) + '$')
           for f in translated if '%' in f]
# (the first walk's names, and the network screens' names)
names = {'Alpha (USA)', 'Alpha', 'NES', 'FDS', 'Famicom Disk System', 'L1', 'R1', 'OPTIONS', 'English', 'Español',
         'Português (Brasil)', 'Français', 'Deutsch', 'S-Video', 'RGB', '4:3', '16:9', 'Mesen', 'Dendy',
         'SMB (Windows, Samba, NAS)', 'NFS', 'USB'}
for line in (open(sys.argv[1], encoding='utf-8') if os.path.exists(sys.argv[1]) else []):
    t = line.rstrip('\n')
    if t in translated or t in names or not re.search('[A-Za-z]{2}', t) or re.fullmatch(r'[\d%. ]+', t):
        continue
    if any(f.match(t) for f in formats):
        continue
    if t.startswith('↣') or re.match(r'(NES|FDS|Famicom Disk System) {3}', t):
        continue
    print(t)
PY
	expect "[ $rc = 0 ] && grep -q 'network tab: scan again' $T/root/logs/boot.log && [ -s $T/missing.txt ] && [ ! -s $T/untranslated.txt ]" "language $L: the network screens and the Network tab are translated ($(head -c 200 $T/untranslated.txt | tr '\n' '|'))"
	nosan "$T"
done
# Settings, Language (first row of SYSTEM: Up three times from Shader: Back, Debug logs, Language), Right: Spanish
T=$(newroot t28s)
rc=$(run "$T" "0:0;30:$TRIANGLE;32:0;50:$UP;52:0;60:$UP;62:0;70:$UP;72:0;80:$RIGHT;82:0;100:$CIRCLE;102:0;110:$OPTIONS;112:0;120:$CROSS;122:0" "")
expect "[ $rc = 0 ] && grep -q '^language=1$' $T/root/fceumm-ps5.ini" "Settings, Language, Right: Español saved"
# English stays the default: no setting, English on the screen (the texts pass through as they are)
T=$(newroot t28en)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(FCEUMM_HOST_I18N_MISSING=$T/missing.txt run "$T" "0:0;$(QUITAT 100)" "" "$T/root/roms/test.nes")
expect "[ $rc = 0 ] && [ ! -s $T/missing.txt ] && grep -q '^language=0$' $T/root/fceumm-ps5.ini" "English by default (language=0): nothing is looked up"
fi

# ---- network shares (1.1): netfs, games on a share, the Network shares screen, the shelf's storage tabs -------------
# From Beetle PCE PS5 1.1.1's groups 31-35 (Genesis Plus GX PS5 2.1.1's, thatboialex's design in Snes9x PS5). The host
# build's share backend (host/netfs_dirbackend.cpp) answers every smb:// and nfs:// address with the folder
# FCEUMM_HOST_NETFS_DIR names.

if want 29; then
echo "== 29. netfs: share addresses and redaction, routing, the libc --wrap layer, minizip and zlib on a share, the watchdog (in-memory share)"
NETFS_OUT=$(ASAN_OPTIONS=detect_leaks=1 timeout 120 "$PWD/build/host/test-netfs" 2>&1)
NETFS_RC=$?
echo "$NETFS_OUT" | tail -3 | sed 's/^/  /'
expect "[ $NETFS_RC = 0 ]" "netfs: every check passes"
expect "! echo \"\$NETFS_OUT\" | grep -q 'runtime error\|Sanitizer'" "no sanitizer reports"
fi

if want 30; then
echo "== 30. games on a share: on the shelf, an NES game and a disk started from it (read whole), saves and the BIOS on the console"
# a. an NES game on an SMB share: listed, started from the shelf (read whole), its save state on the console
T=$(newroot t30)
mkdir -p "$T/share/NES"
$ROM "$T/share/NES/Net Game (USA).nes" >/dev/null
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_REALTIME=1 MAXFLIPS=900 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0;150:$CROSS;152:0;280:$CROSS;320:0;340:$L2UP;345:0;$(QUITAT 400)" "300")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q '\[net\] 1 share(s) in shares.txt' $T/root/logs/boot.log" "shares.txt was read"
expect "grep -q '\[net\] Connected to smb://10.0.0.5/games' $T/root/logs/boot.log" "the share connected"
expect "grep -q 'loading /smb/10.0.0.5/games/NES/Net Game (USA).nes' $T/root/logs/boot.log && grep -q 'running \"Net Game (USA)\" (NES)' $T/root/logs/boot.log" "the game was started from the share"
expect "$CHECK $T/dump/flip00300.ppm 960 540 green >/dev/null" "it runs (Cross -> green)"
expect "[ -f '$T/root/states/NES/Net Game (USA).state1' ] && [ ! -e '$T/share/states' ] && [ \$(find $T/share -type f | wc -l) = 1 ]" "its state is on the console, nothing is written to the share"
expect "grep -q 'last_rom=/smb/10.0.0.5/games/NES/Net Game (USA).nes' $T/root/fceumm-ps5.ini" "the shelf remembers it"
nosan "$T"
# a power cycle (pause menu, Down nine times) starts the game again from memory: the share is not read again
rc=$(FCEUMM_HOST_REALTIME=1 MAXFLIPS=900 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0;150:$CROSS;152:0;$(SEQ 280 $L3R3 $DOWN $DOWN $DOWN $DOWN $DOWN $DOWN $DOWN $DOWN $DOWN $CROSS);420:$CROSS;460:0;$(QUITAT 500)" "450")
expect "[ $rc = 0 ] && grep -q 'power cycle: Net Game (USA).nes kept in memory, not read again' $T/root/logs/boot.log && [ \$(grep -c 'running \"Net Game (USA)\"' $T/root/logs/boot.log) = 2 ]" "a power cycle restarts the game from memory, not from the share"
expect "$CHECK $T/dump/flip00450.ppm 960 540 green >/dev/null" "and it runs (Cross -> green)"
nosan "$T"
# b. a Famicom Disk System disk on an NFS share, disksys.rom on the console: started from the share
T=$(newroot t30fds)
mkdir -p "$T/root/bios" "$T/share/FDS"
head -c 8192 /dev/zero >"$T/root/bios/disksys.rom"
$ROM "$T/share/FDS/Disk (Japan).fds" >/dev/null
echo "nfs://10.0.0.5/export/nes" >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_REALTIME=1 MAXFLIPS=600 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0;150:$CROSS;152:0;$(QUITAT 300)" "")
expect "[ $rc = 0 ] && grep -q 'loading /nfs/10.0.0.5/export/nes/FDS/Disk (Japan).fds' $T/root/logs/boot.log && grep -q 'running \"Disk (Japan)\" (Famicom Disk System)' $T/root/logs/boot.log" "a disk on a share starts as a Famicom Disk System game (its BIOS from the console)"
expect "[ \$(find $T/share -type f | wc -l) = 1 ]" "nothing is written to the share"
nosan "$T"
# the same with 200 ms on every read, as a slow link: the game is read whole before it starts, and runs
T=$(newroot t30slow)
mkdir -p "$T/share"
$ROM "$T/share/Slow (USA).nes" >/dev/null
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_NETFS_DELAY_MS=200 FCEUMM_HOST_REALTIME=1 MAXFLIPS=900 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0;200:$CROSS;202:0;400:$CROSS;440:0;$(QUITAT 500)" "420")
expect "[ $rc = 0 ] && grep -q 'running \"Slow (USA)\" (NES)' $T/root/logs/boot.log && $CHECK $T/dump/flip00420.ppm 960 540 green >/dev/null" "a slow link (200 ms a read): the game starts and runs"
expect "! grep -q 'in realtime' $T/root/logs/boot.log" "and the running game never waits for the share"
nosan "$T"
# c. a share that does not connect: the shelf still works and says why
T=$(newroot t30f)
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_REALTIME=1 FCEUMM_HOST_NETFS_DIR="$T/nothing" run "$T" "0:0;100:$OPTIONS;102:0;110:$CROSS;112:0" "")
expect "[ $rc = 0 ] && grep -q '\[games\] 0 ROM(s)' $T/root/logs/boot.log" "a share that does not connect leaves the shelf working"
expect "grep -q '\[net\] The folder games is not on 10.0.0.5' $T/root/logs/boot.log" "and says why"
nosan "$T"
# d. shares.txt: written with its comments when missing; a bad line is named in the log, never its text
T=$(newroot t30n)
rc=$(run "$T" "0:0;$(SHELFQUIT_AT 40)" "")
expect "[ $rc = 0 ] && grep -q '^# NES FCEUmm PS5 network shares' $T/root/shares.txt && ! grep -q '^smb://\|^nfs://' $T/root/shares.txt" "a commented shares.txt is written when there is none"
printf 'smb://bob@10.0.0.5/games?password=Hunter2x\nftp://10.0.0.5/x?password=Hunter2y\n' >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_NETFS_DIR="$T/nothing" run "$T" "0:0;$(SHELFQUIT_AT 40)" "")
expect "[ $rc = 0 ] && grep -q 'shares.txt line 2: ' $T/root/logs/boot.log" "a line that is not an address is named by its number"
expect "! grep -rq 'Hunter2' $T/root/logs $T/out.txt" "no password in a log or on stdout"
nosan "$T"
fi

if want 31; then
echo "== 31. a game on a share with a made-up file name is named by its CRC in the background, its cover follows; a zip's system too"
T=$(newroot t31)
NESREPO=Nintendo_-_Nintendo_Entertainment_System
mkdir -p "$T/srv/$NESREPO/Named_Boxarts" "$T/share/misc"
python3 - "$T/srv/$NESREPO/Named_Boxarts" <<'PY'
import sys
from PIL import Image
Image.new('RGB', (512, 357), (0, 255, 0)).save(sys.argv[1] + '/Tetris (USA).png')
PY
TETRIS=$(grep -P "^nes\t[0-9A-F]{8}\tTetris \(USA\)$" frontend/data/nointro.tsv | cut -f2 | head -1)
$ROM "$T/share/tet.nes" >/dev/null
python3 tests/forge_nes_crc.py "$T/share/tet.nes" $TETRIS >/dev/null
# a disk in a zip, in a folder whose name says nothing: listed as an NES game until its zip is read
$ROM "$T/disk.fds" >/dev/null
python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w'); z.write(sys.argv[2],'Disk.fds'); z.close()" "$T/share/misc/disk.zip" "$T/disk.fds"
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
PORT=18082
(cd "$T/srv" && exec python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) &
SRVPID=$!
sleep 1
rc=$(OFFLINE= COVER_URL="http://127.0.0.1:$PORT/\${repo}/Named_Boxarts/\${name}.png" FCEUMM_HOST_REALTIME=1 MAXFLIPS=420 FCEUMM_HOST_NETFS_DIR="$T/share" \
	run "$T" "0:0" "400")
kill $SRVPID 2>/dev/null
expect "grep -q '\[games\] naming 2 network ROM(s) by CRC' $T/root/logs/boot.log" "the pass was started for the two games the scan did not read"
expect "grep -q 'tet.nes \[nes\] -> \"Tetris (USA)\" (by CRC)' $T/root/logs/boot.log" "the next scan names the game by its CRC"
expect "grep -q 'misc/disk.zip \[nes\]' $T/root/logs/boot.log && grep -q 'misc/disk.zip \[fds\]' $T/root/logs/boot.log" "the zip moves to the Famicom Disk System once its directory was read"
expect "grep -q '/smb/10.0.0.5/games/tet.nes' $T/root/covers/crc-cache.txt && grep -q '^sys:/smb/10.0.0.5/games/misc/disk.zip' $T/root/covers/crc-cache.txt" "both are kept for the next start"
expect "[ -f '$T/root/covers/NES/Tetris (USA).png' ]" "the cover of the game named late was downloaded"
nosan "$T"
# the next start reads nothing over the network: the cache names both
rc=$(FCEUMM_HOST_REALTIME=1 MAXFLIPS=200 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0" "")
expect "[ \$(grep -c 'tet.nes \[nes\] -> \"Tetris (USA)\" (by CRC)' $T/root/logs/boot.log) -ge 1 ] && grep -q 'misc/disk.zip \[fds\]' $T/root/logs/boot.log && ! grep -q 'naming .* network ROM' $T/root/logs/boot.log" "the next start: named from the cache, no pass needed"
nosan "$T"
# a read error while the share stays connected (a link that drops, the watchdog, the shares connected again) is not the
# file's fault: nothing is remembered, the zip stays on the shelf, and the next start reads both again
T=$(newroot t31e)
mkdir -p "$T/share/misc"
$ROM "$T/share/tet.nes" >/dev/null
python3 tests/forge_nes_crc.py "$T/share/tet.nes" $TETRIS >/dev/null
$ROM "$T/disk.fds" >/dev/null
python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w'); z.write(sys.argv[2],'Disk.fds'); z.close()" "$T/share/misc/disk.zip" "$T/disk.fds"
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_NETFS_EIO=tet.nes,disk.zip FCEUMM_HOST_REALTIME=1 MAXFLIPS=400 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0" "")
expect "grep -q 'network CRC pass: 2 ROM(s) read\$' $T/root/logs/boot.log" "read errors: the pass tried both"
expect "! grep -q 'tet.nes.*fail' $T/root/covers/crc-cache.txt && ! grep -q '^sys:.*disk.zip' $T/root/covers/crc-cache.txt" "and remembered no failure"
expect "[ \$(grep -c 'misc/disk.zip \[nes\]' $T/root/logs/boot.log) -ge 2 ]" "the zip is still on the shelf after the pass"
nosan "$T"
rc=$(FCEUMM_HOST_REALTIME=1 MAXFLIPS=400 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0" "")
expect "grep -q 'tet.nes \[nes\] -> \"Tetris (USA)\" (by CRC)' $T/root/logs/boot.log && grep -q 'misc/disk.zip \[fds\]' $T/root/logs/boot.log" "the next start reads both again and names them"
nosan "$T"
# Settings (Triangle) while the pass reads a ROM (3 s a read): the pass stops first (Settings > Network shares may connect the
# shares again, which needs no other netfs call running); the ROM it was reading is read again once Settings is left
T=$(newroot t31s)
mkdir -p "$T/share"
$ROM "$T/share/tet.nes" >/dev/null
python3 tests/forge_nes_crc.py "$T/share/tet.nes" $TETRIS >/dev/null
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_NETFS_DELAY_MS=3000 FCEUMM_HOST_REALTIME=1 MAXFLIPS=900 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0;60:$TRIANGLE;62:0;90:$CIRCLE;92:0" "")
expect "grep -q 'network CRC pass: 0 ROM(s) read (stopped)' $T/root/logs/boot.log" "Settings stops the pass while it reads"
expect "grep -q 'tet.nes \[nes\] -> \"Tetris (USA)\" (by CRC)' $T/root/logs/boot.log" "and, once Settings is left, the ROM it was reading is read again and named"
nosan "$T"
fi

if want 32; then
echo "== 32. the Network shares screen: add, change, test and remove a share with the on-screen keyboard (Settings, Network shares)"
# tests/osk_pad.py turns the steps into a pad script (the keyboard's layout is its model). Settings is Triangle on the shelf; Up four
# times from Shader reaches Network shares (Back, Debug logs, Language, Network shares). Every run ends: Circle twice,
# OPTIONS, Cross.
net_pad() { python3 tests/osk_pad.py 2>/dev/null; }
net_quit='press CIRCLE 2
press OPTIONS
wait 8
press CROSS'
# a. a new share: server, share, folder with a space, user, a password that needs Shift and both kinds of symbols
T=$(newroot t32)
mkdir -p "$T/share"
PAD=$(net_pad <<STEPS
frame 40
press TRIANGLE
press UP 4
press CROSS
press CROSS
field 10.0.0.5
press DOWN
field games
press DOWN
field NES Games
press DOWN
field jason
press DOWN
field Zq9@pw&1
press DOWN 6
press CROSS
wait 20
$net_quit
STEPS
)
rc=$(FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "$PAD" "")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "[ \"\$(tail -n 1 $T/root/shares.txt)\" = 'smb://jason@10.0.0.5/games/NES%20Games?password=Zq9%40pw%261' ]" "the share is written as one escaped line"
expect "grep -q '^# NES FCEUmm PS5 network shares' $T/root/shares.txt" "after the comments the app wrote"
expect "grep -q '\[net\] shares.txt: saved smb://jason@10.0.0.5/games/NES%20Games' $T/root/logs/boot.log" "the log says what was saved"
expect "grep -q '\[net\] Connected to smb://jason@10.0.0.5/games/NES%20Games' $T/root/logs/boot.log" "and the share connects at once, without a restart"
expect "! grep -rqE 'Zq9|pw%26' $T/root/logs $T/out.txt" "the password is in no log and not on stdout"
nosan "$T"
# b. change one share (its note stays), test the connection, remove the other
T=$(newroot t32b)
mkdir -p "$T/share/Sub" && echo x >"$T/share/a.nes"
printf '# my shares\nsmb://old/x   # my note\nnfs://nas/export/nes\n' >"$T/root/shares.txt"
PAD=$(net_pad <<STEPS
frame 40
press TRIANGLE
press UP 4
press CROSS
press CROSS
press DOWN 3
field bob
press DOWN 6
press CROSS
wait 120
press DOWN
press CROSS
wait 20
press DOWN
press CROSS
press DOWN 7
press CROSS
wait 8
press UP
press CROSS
wait 20
$net_quit
STEPS
)
rc=$(FCEUMM_HOST_REALTIME=1 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "$PAD" "")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "[ \"\$(cat $T/root/shares.txt)\" = \"\$(printf '# my shares\nsmb://bob@old/x   # my note')\" ]" "one line changed (note kept), the other was removed, the comment stays"
expect "grep -q '\[net\] test of smb://bob@old/x: Connected. The folder has 1 file and 1 folder.' $T/root/logs/boot.log" "Test connection reports what is in the folder"
expect "grep -q '\[net\] shares.txt: removed nfs://nas/export/nes' $T/root/logs/boot.log" "the removal is logged"
nosan "$T"
# c. Save with nothing filled in changes nothing
T=$(newroot t32c)
PAD=$(net_pad <<STEPS
frame 40
press TRIANGLE
press UP 4
press CROSS
press CROSS
press DOWN 10
press CROSS
wait 8
press CIRCLE
$net_quit
STEPS
)
rc=$(run "$T" "$PAD" "")
expect "[ $rc = 0 ] && ! grep -q '^smb://\|^nfs://' $T/root/shares.txt" "an empty form is not saved (and Circle on a form with no changes leaves it at once)"
nosan "$T"
# d. over a game (Settings from the pause menu) the row is there but can't be chosen (the game may be reading from a share):
# the pause menu: Down seven times to Settings; there, Up four times from Shader passes Network shares and lands on
# Download covers, which Cross switches off; Circle, then Down four times to Quit
T=$(newroot t32d)
$ROM "$T/root/roms/test.nes" >/dev/null
rc=$(MAXFLIPS=900 run "$T" "0:0;$(SEQ 100 $L3R3 $DOWN $DOWN $DOWN $DOWN $DOWN $DOWN $DOWN $CROSS $UP $UP $UP $UP $CROSS $CIRCLE $DOWN $DOWN $DOWN $DOWN $CROSS)" "" "$T/root/roms/test.nes")
expect "[ $rc = 0 ] && grep -q '^covers_download=0' $T/root/fceumm-ps5.ini" "over a game: Network shares is skipped (Up four times reaches Download covers)"
nosan "$T"
fi

if want 33; then
echo "== 33. shelf tabs: Internal and Network apart, L1 / R1 between them, the last tab kept, Square on Network scans again; L2 / R2 skip 10"
# The tab bar sits at the top: the open tab's pill is the accent colour (78,62,170), the other one dark (32,30,58); (795,30) is
# inside the Internal pill and (1120,30) inside the Network pill (above their names). The share connects within a few seconds of wall time.
tab_pills() { # dump the active tab: Internal | Network
	local f=$1 on=$2
	if [ "$on" = Internal ]; then
		$CHECK "$f" 795 30 78 62 170 >/dev/null && $CHECK "$f" 1120 30 32 30 58 >/dev/null
	else
		$CHECK "$f" 795 30 32 30 58 >/dev/null && $CHECK "$f" 1120 30 78 62 170 >/dev/null
	fi
}
T=$(newroot t33)
mkdir -p "$T/share"
$ROM "$T/root/roms/Local Game (USA).nes" >/dev/null
$ROM "$T/share/Net Game (USA).nes" >/dev/null
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_REALTIME=1 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0;220:$R1;222:0;300:$SQUARE;302:0;380:$L1;382:0;420:$OPTIONS;422:0;430:$CROSS;432:0" "200,260,400")
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "tab_pills $T/dump/flip00200.ppm Internal" "the shelf opens on the Internal tab"
expect "tab_pills $T/dump/flip00260.ppm Network" "R1 goes to the Network tab"
expect "tab_pills $T/dump/flip00400.ppm Internal" "L1 comes back"
expect "grep -q '\[shelf\] tab Network: 1 game' $T/root/logs/boot.log" "the Network tab holds the game on the share"
expect "grep -q '\[shelf\] tab Internal: 1 game' $T/root/logs/boot.log" "and the Internal tab only the local one"
expect "grep -q '\[shelf\] network tab: scan again\$' $T/root/logs/boot.log" "Square on the Network tab scans again"
expect "[ \$(grep -c '\[games\] 2 ROM' $T/root/logs/boot.log) -ge 2 ]" "and the scan found both games again"
expect "awk '/network tab: scan again/{f=1;next} f&&/\[covers\]/{c++} f&&/\[shelf\] tab /{exit} END{exit !(f && c == 0)}' $T/root/logs/boot.log" "the same games after the scan: the covers are not loaded again"
expect "grep -q 'last_tab=0' $T/root/fceumm-ps5.ini" "the tab left on is kept (Internal)"
nosan "$T"
T=$(newroot t33b)
mkdir -p "$T/share"
$ROM "$T/root/roms/Local Game (USA).nes" >/dev/null
$ROM "$T/share/Net Game (USA).nes" >/dev/null
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
echo "last_tab=2" >>"$T/root/fceumm-ps5.ini"
rc=$(FCEUMM_HOST_REALTIME=1 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0;300:$OPTIONS;302:0;310:$CROSS;312:0" "40,250")
expect "[ $rc = 0 ] && tab_pills $T/dump/flip00040.ppm Network" "with last_tab=2 and a share set up the shelf opens on Network, before the share is up"
expect "tab_pills $T/dump/flip00250.ppm Network" "and stays there when its games arrive"
expect "grep -q 'last_tab=2' $T/root/fceumm-ps5.ini" "and keeps the tab on quit"
T=$(newroot t33c)
$ROM "$T/root/roms/Local Game (USA).nes" >/dev/null
echo "last_tab=2" >>"$T/root/fceumm-ps5.ini"
rc=$(run "$T" "0:0;60:$R1;62:0;70:$SQUARE;72:0;90:$L1;92:0;120:$OPTIONS;122:0;130:$CROSS;132:0" "40,80,110")
expect "[ $rc = 0 ] && tab_pills $T/dump/flip00040.ppm Internal" "last_tab=2 without a share set up opens on the games instead"
expect "tab_pills $T/dump/flip00080.ppm Network && grep -q '\[shelf\] tab Network: 0 game' $T/root/logs/boot.log" "R1 shows the empty Network tab"
expect "grep -q '\[shelf\] network tab: scan again\$' $T/root/logs/boot.log" "Square on it scans again, with no share to ask"
expect "tab_pills $T/dump/flip00110.ppm Internal && grep -q 'last_tab=0' $T/root/fceumm-ps5.ini" "L1 goes back and the tab is kept"
nosan "$T"
T=$(newroot t33d)
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_REALTIME=1 FCEUMM_HOST_NETFS_DIR="$T/nothing" run "$T" "0:0;150:$SQUARE;152:0;330:$OPTIONS;332:0;340:$CROSS;342:0" "100")
expect "[ $rc = 0 ] && tab_pills $T/dump/flip00100.ppm Network" "a share that is down leaves a shelf with no games on the Network tab"
expect "grep -q '\[shelf\] network tab: scan again, reconnecting' $T/root/logs/boot.log" "Square connects it again"
expect "[ \$(grep -c 'The folder games is not on 10.0.0.5' $T/root/logs/boot.log) -ge 2 ]" "and says why each time"
nosan "$T"
# the letter tabs (Up / Down) work inside the storage tab; L2 / R2 skip 10 games (L1 / R1 did before 1.1)
T=$(newroot t33e)
mkdir -p "$T/share"
for i in $(seq -w 1 12); do $ROM "$T/root/roms/Game $i (USA).nes" >/dev/null; done
$ROM "$T/root/roms/Zeta (USA).nes" >/dev/null
$ROM "$T/share/Net Game (USA).nes" >/dev/null
$ROM "$T/share/Zap (USA).nes" >/dev/null
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
# (back to the shelf from a game: the pause menu, Up twice, Cross)
rc=$(FCEUMM_HOST_REALTIME=1 MAXFLIPS=900 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0;150:$R2;152:0;170:$CROSS;172:0;$(SEQ 230 $L3R3 $UP $UP $CROSS);320:$R1;322:0;340:$DOWN;342:0;380:$CROSS;382:0;$(QUITAT 480)" "")
expect "[ $rc = 0 ] && grep -q 'loading .*/Game 11 (USA).nes' $T/root/logs/boot.log" "R2 skips 10 games (Game 01 -> Game 11)"
expect "grep -q '\[shelf\] tab N: 1 game' $T/root/logs/boot.log && grep -q 'loading /smb/10.0.0.5/games/Net Game (USA).nes' $T/root/logs/boot.log" "on the Network tab, Down shows its letter N, whose game runs"
nosan "$T"
fi

# ---- 7-Zip (1.1): NES games and disks inside a .7z (frontend/fe_7z.cpp, the LZMA SDK's C decoder); the archives are tests/7z/
if want 34; then
echo "== 34. 7z: the reader on every kind of archive; a .7z on the shelf named and covered as its .zip twin, started, run; a disk in a .7z; what is refused, and why; a .7z on a share"
SZ_OUT=$(ASAN_OPTIONS=detect_leaks=1 timeout 120 "$PWD/build/host/test-7z" "$PWD/tests/7z" "$PWD/build/host/test-7z-card.nes" 2>&1)
SZ_RC=$?
echo "$SZ_OUT" | tail -3 | sed 's/^/  /'
expect "[ $SZ_RC = 0 ]" "the 7z reader: LZMA, LZMA2, PPMd, BCJ, Delta, a solid block, the directory's CRCs; empty, truncated, corrupt, BZip2, AES, too big: every check passes"
expect "! echo \"\$SZ_OUT\" | grep -q 'runtime error\|Sanitizer'" "no sanitizer reports"
# a. the same game as a .7z and as a .zip: both named by the CRC their directory keeps, one cover for both; the .7z runs.
# A third, whose directory CRC the table doesn't know (its header differs), is unpacked and named by the CRC past its header
T=$(newroot t34)
NESREPO=Nintendo_-_Nintendo_Entertainment_System
mkdir -p "$T/srv/$NESREPO/Named_Boxarts" "$T/root/roms/NES"
python3 -c "from PIL import Image; import sys; Image.new('RGB', (512, 357), (0, 255, 0)).save(sys.argv[1])" "$T/srv/$NESREPO/Named_Boxarts/Tetris (USA).png"
cp tests/7z/named.7z "$T/root/roms/NES/seven.7z"
cp tests/7z/header.7z "$T/root/roms/NES/unpacked.7z"
$ROM "$T/splat.nes" >/dev/null
python3 tests/forge_crc.py "$T/splat.nes" $(grep -P "^nes\t[0-9A-F]{8}\tTetris \(USA\)$" frontend/data/nointro.tsv | cut -f2 | head -1) >/dev/null
python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED); z.write(sys.argv[2],'splat.nes'); z.close()" "$T/root/roms/NES/zipped.zip" "$T/splat.nes"
PORT=18083
(cd "$T/srv" && exec python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) &
SRVPID=$!
sleep 1
# the shelf: the three games (same title: by path, seven.7z first); the 7z is selected, Cross starts it
rc=$(OFFLINE= COVER_URL="http://127.0.0.1:$PORT/\${repo}/Named_Boxarts/\${name}.png" FCEUMM_HOST_REALTIME=1 MAXFLIPS=900 run "$T" \
	"0:0;150:$CROSS;152:0;280:$CROSS;320:0;$(QUITAT 400)" "140,300")
kill $SRVPID 2>/dev/null
expect "[ $rc = 0 ]" "exit code 0 (got $rc)"
expect "grep -q 'NES/seven.7z \[nes\] -> \"Tetris (USA)\" (by CRC)' $T/root/logs/boot.log && grep -q 'NES/zipped.zip \[nes\] -> \"Tetris (USA)\" (by CRC)' $T/root/logs/boot.log" "the .7z is named by its CRC, as its .zip twin"
expect "grep -q 'NES/unpacked.7z \[nes\] -> \"Tetris (USA)\" (by CRC)' $T/root/logs/boot.log" "a .7z whose directory CRC the table doesn't know: unpacked, named by the CRC past the header"
expect "[ -f '$T/root/covers/NES/Tetris (USA).png' ] && $CHECK $T/dump/flip00140.ppm 960 420 0 255 0 >/dev/null" "and shows the cover the .zip gets"
expect "grep -q 'loading .*seven.7z -> splat.nes' $T/root/logs/boot.log && grep -q 'running \"seven\" (NES)' $T/root/logs/boot.log" "the game inside the .7z is loaded"
expect "$CHECK $T/dump/flip00300.ppm 960 540 green >/dev/null" "and runs as the .zip's does (Cross -> green)"
expect "grep -q '^sys:.*seven.7z' $T/root/covers/crc-cache.txt" "the .7z's system is cached as a zip's"
nosan "$T"
# b. a Famicom Disk System disk after a text file in the archive: its system from the disk inside; started as one
T=$(newroot t34b)
mkdir -p "$T/root/bios" && head -c 8192 /dev/zero >"$T/root/bios/disksys.rom"
cp tests/7z/fds.7z "$T/root/roms/disk.7z"
rc=$(run "$T" "0:0;$(SHELFQUIT_AT 60)" "")
expect "[ $rc = 0 ] && grep -q 'disk.7z \[fds\]' $T/root/logs/boot.log" "a .fds in a .7z is listed as a Famicom Disk System game"
rc=$(run "$T" "0:0;$(QUITAT 200)" "" "$T/root/roms/disk.7z")
expect "[ $rc = 0 ] && grep -q 'loading .*disk.7z -> Disk (Japan).fds' $T/root/logs/boot.log && grep -q 'running \"disk\" (Famicom Disk System)' $T/root/logs/boot.log" "and starts as one"
nosan "$T"
# c. what the shelf leaves out (nothing it lists, no game, a broken directory) and what says why it can't start
T=$(newroot t34c)
for f in other nogame empty truncated bzip2 aes aeshdr big corrupt lzma; do cp tests/7z/$f.7z "$T/root/roms/$f.7z"; done
rc=$(run "$T" "0:0;$(SHELFQUIT_AT 60)" "")
expect "[ $rc = 0 ] && grep -q '\[games\] 5 ROM(s)' $T/root/logs/boot.log" "the shelf lists the five archives with a game in a readable directory"
expect "! grep -q 'other.7z \[\|nogame.7z \[\|empty.7z \[\|truncated.7z \[\|aeshdr.7z \[' $T/root/logs/boot.log" "an archive with nothing the app lists, with no game, a cut or name-encrypted one: not listed"
nosan "$T"
for f in bzip2:"can't unpack" aes:"is encrypted" big:"too big" corrupt:"damaged"; do
	n=${f%%:*}; why=${f#*:}
	rc=$(MAXFLIPS=300 run "$T" "0:0;60:$CROSS;62:0" "50" "$T/root/roms/$n.7z")
	expect "grep -q \"could not start .*$n.7z: .*$why\" $T/root/logs/boot.log && [ -f $T/dump/flip00050.ppm ]" "$n.7z: not started; the screen says why ($why)"
	nosan "$T"
done
# d. a .7z on a share: listed before it is opened (its folder's name), named by its CRC in the background, started from the share
T=$(newroot t34d)
mkdir -p "$T/share/NES"
cp tests/7z/named.7z "$T/share/NES/seven.7z"
echo "smb://10.0.0.5/games" >"$T/root/shares.txt"
rc=$(FCEUMM_HOST_REALTIME=1 MAXFLIPS=900 FCEUMM_HOST_NETFS_DIR="$T/share" run "$T" "0:0;300:$CROSS;302:0;430:$CROSS;470:0;$(QUITAT 520)" "450")
expect "[ $rc = 0 ] && grep -q '\[games\] naming 1 network ROM(s) by CRC' $T/root/logs/boot.log" "the .7z on the share is named in the background (the scan doesn't open it)"
expect "grep -q 'NES/seven.7z \[nes\] -> \"Tetris (USA)\" (by CRC)' $T/root/logs/boot.log" "by the CRC its directory keeps"
expect "grep -q 'loading /smb/10.0.0.5/games/NES/seven.7z -> splat.nes' $T/root/logs/boot.log && $CHECK $T/dump/flip00450.ppm 960 540 green >/dev/null" "it starts from the share and runs"
nosan "$T"
fi

echo
echo "passed $PASS, failed $FAIL  (work dir $WORK)"
[ $FAIL = 0 ]
