#!/usr/bin/env python3
"""Builds frontend/fe_palettes.h, the NES palettes NES FCEUmm PS5 adds to FCEUmm's own: Mesen's presets (MesenCE
2.2.1, UI/ViewModels/NesConfigViewModel.cs and the default palette in UI/Config/NesConfig.cs) and Nestopia's palette
files (nestopia/palettes/*.pal), those FCEUmm doesn't already have.

  tools/make_palettes.py <MesenCE source> <nestopia source> frontend/fe_palettes.h
"""
import re
import sys

# (name in the settings, source, entry): Mesen's by preset name, Nestopia's by file name
MESEN = [
    ("Mesen", "default"),
    ("Nestopia RGB", "Nestopia (RGB)"),
    ("Original Hardware (FirebrandX)", "Original Hardware (by FirebrandX)"),
    ("PVM Style (FirebrandX)", "PVM Style (by FirebrandX)"),
    ("Unsaturated v6 (FirebrandX)", "Unsaturated v6 (by FirebrandX)"),
]
NESTOPIA = [
    ("Nostalgia (FirebrandX)", "Nostalgia-FBX.pal"),
    ("Hybrid (Nestopia)", "hybrid.pal"),
    ("NTSC (Nestopia)", "ntsc.pal"),
]


def argb_list(text):
    return [int(x, 16) & 0xFFFFFF for x in re.findall(r"0x([0-9A-Fa-f]{8})", text)][:64]


def main():
    mesen, nestopia, out = sys.argv[1:4]
    vm = open(f"{mesen}/UI/ViewModels/NesConfigViewModel.cs", encoding="utf-8").read()
    cfg = open(f"{mesen}/UI/Config/NesConfig.cs", encoding="utf-8").read()
    palettes = []
    for name, preset in MESEN:
        if preset == "default":
            m = re.search(r"UserPalette \{ get; set; \} = new UInt32\[64\] \{([^}]*)\}", cfg)
        else:
            m = re.search(r'Name = "' + re.escape(preset) + r'", Palette = new UInt32\[\] \{([^}]*)\}', vm)
        colours = argb_list(m.group(1))
        assert len(colours) == 64, name
        palettes.append((name, "Mesen" if preset == "default" else "Mesen's presets", colours))
    for name, file in NESTOPIA:
        data = open(f"{nestopia}/palettes/{file}", "rb").read()[:192]
        assert len(data) == 192, file
        colours = [(data[i * 3] << 16) | (data[i * 3 + 1] << 8) | data[i * 3 + 2] for i in range(64)]
        palettes.append((name, "Nestopia's palettes/" + file, colours))
    lines = [
        "// NES FCEUmm PS5: palettes from Mesen and Nestopia (tools/make_palettes.py; do not edit).",
        "// SPDX-License-Identifier: GPL-3.0-or-later (Mesen's presets), GPL-2.0-or-later (Nestopia's files)",
        "#pragma once",
        "",
        "#include <cstdint>",
        "",
        "namespace fe",
        "{",
        "struct ExtraPalette",
        "{",
        "\tconst char* name;",
        "\tuint32_t rgb[64]; // 0xRRGGBB",
        "};",
        "",
        "constexpr ExtraPalette kExtraPalettes[] = {",
    ]
    for name, src, colours in palettes:
        lines.append("\t{\"%s\", // %s" % (name, src))
        lines.append("\t\t{")
        for row in range(0, 64, 8):
            lines.append("\t\t\t" + ", ".join("0x%06X" % c for c in colours[row:row + 8]) + ",")
        lines.append("\t\t}},")
    lines += ["};", "constexpr int kExtraPaletteCount = int(sizeof(kExtraPalettes) / sizeof(kExtraPalettes[0]));",
              "} // namespace fe", ""]
    open(out, "w", encoding="utf-8").write("\n".join(lines))
    print("%s: %d palettes" % (out, len(palettes)))


if __name__ == "__main__":
    main()
