#!/usr/bin/env python3
"""Draws the app's home-screen background (original, made for NES FCEUmm PS5: a pixel wordmark over a retro
perspective grid). The icon is the project's art in app/sce_sys/icon-source.png, not made here.

  tools/make_art.py <dir>   -> background-source.png (1920x1080) and background-3840.png (for pic0.dds / pic1.dds)

pic0.dds and pic1.dds are background-3840.png encoded as BC7 with bc7enc_rdo (`bc7enc -q -g background-3840.png`),
with the DDS header of ps5-native-app-boilerplate's prepare-assets.sh (one mip level, straight alpha).
SPDX-License-Identifier: MIT
"""
import sys, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

out = sys.argv[1]
POP = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"
FONT5x7 = {
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "S": ["01110", "10001", "10000", "01110", "00001", "10001", "01110"],
}
RED = (228, 52, 44)
CREAM = (244, 236, 220)


def pixel_word(d, text, x, y, cell, color, shadow=None, gap=1):
    for ch in text:
        g = FONT5x7[ch]
        for r, row in enumerate(g):
            for c, bit in enumerate(row):
                if bit == "1":
                    px, py = x + c * cell, y + r * cell
                    if shadow:
                        d.rectangle([px + cell // 3, py + cell // 3, px + cell + cell // 3 - 1, py + cell + cell // 3 - 1], fill=shadow)
                    d.rectangle([px, py, px + cell - 2, py + cell - 2], fill=color)
        x += (5 + gap) * cell
    return x


def word_width(text, cell, gap=1):
    return len(text) * (5 + gap) * cell - gap * cell


def background(W, H):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    horizon = int(H * 0.62)
    for y in range(H):  # night sky to a warm horizon, then a dark floor
        if y < horizon:
            t = y / horizon
            c = (int(14 + 70 * t ** 2), int(12 + 18 * t ** 2), int(40 + 40 * t))
        else:
            t = (y - horizon) / (H - horizon)
            c = (int(30 - 18 * t), int(14 - 6 * t), int(44 - 20 * t))
        d.line([(0, y), (W, y)], fill=c)
    rnd = random.Random(8)
    for _ in range(260):  # stars, square like pixels
        sx, sy = rnd.randrange(W), rnd.randrange(int(horizon * 0.9))
        s = rnd.choice([2, 2, 3, 4]) * W // 1920
        v = rnd.randrange(120, 255)
        d.rectangle([sx, sy, sx + s, sy + s], fill=(v, v, min(255, v + 30)))
    # a big pixel sun on the horizon, cut by bands
    cx, r = W // 2, int(H * 0.30)
    sun = Image.new("RGB", (2 * r, 2 * r))
    sd = ImageDraw.Draw(sun)
    for yy in range(2 * r):
        t = yy / (2 * r)
        sd.line([(0, yy), (2 * r, yy)], fill=(255, int(210 - 150 * t), int(90 - 60 * t)))
    mask = Image.new("L", (2 * r, 2 * r))
    md = ImageDraw.Draw(mask)
    md.ellipse([0, 0, 2 * r - 1, 2 * r - 1], fill=255)
    for i in range(7):
        band_y = int(r * 1.05 + i * r * 0.14)
        md.rectangle([0, band_y, 2 * r, band_y + int(r * 0.02 + i * r * 0.012)], fill=0)
    sun_top = horizon - r - int(r * 0.15)
    img.paste(sun, (cx - r, sun_top), mask.crop((0, 0, 2 * r, 2 * r)))
    # cover the part of the sun under the horizon with the floor
    for y in range(horizon, H):
        t = (y - horizon) / (H - horizon)
        d.line([(0, y), (W, y)], fill=(int(30 - 18 * t), int(14 - 6 * t), int(44 - 20 * t)))
    # perspective grid on the floor
    lw = max(2, W // 900)
    for i in range(-24, 25):
        x0 = cx + i * W // 40
        x1 = cx + i * W // 5
        d.line([(x0, horizon), (x1, H)], fill=(220, 40, 90), width=lw)
    y, step = horizon, 6.0 * H / 1080
    while y < H:
        d.line([(0, int(y)), (W, int(y))], fill=(220, 40, 90), width=lw)
        step *= 1.32
        y += step
    glow = img.filter(ImageFilter.GaussianBlur(W / 400))
    img = Image.blend(img, glow, 0.35)
    # scanlines
    sl = ImageDraw.Draw(img)
    for yy in range(0, H, max(3, H // 360)):
        sl.line([(0, yy), (W, yy)], fill=(0, 0, 0), width=1)
    return img, horizon


def text_center(d, W, y, text, size, color, shadow=(0, 0, 0)):
    f = ImageFont.truetype(POP, size)
    w = d.textlength(text, font=f)
    off = max(2, size // 18)
    d.text(((W - w) / 2 + off, y + off), text, font=f, fill=shadow)
    d.text(((W - w) / 2, y), text, font=f, fill=color)


def bg_art(W, H):
    img, horizon = background(W, H)
    d = ImageDraw.Draw(img)
    cell = W // 64
    x = (W - word_width("NES", cell)) // 2
    pixel_word(d, "NES", x, int(H * 0.10), cell, RED, shadow=(20, 6, 18))
    text_center(d, W, int(H * 0.10) + 7 * cell + int(H * 0.03), "FCEUmm", int(H * 0.12), CREAM)
    text_center(d, W, int(H * 0.86), "for PS5", int(H * 0.06), CREAM, shadow=(60, 10, 40))
    return img


bg_art(1920, 1080).save(out + "/background-source.png")
bg_art(3840, 2160).save(out + "/background-3840.png")
