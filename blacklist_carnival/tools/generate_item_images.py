#!/usr/bin/env python3
"""Generate the original inventory item images for Carnival of the Damned.

All artwork is drawn procedurally (no third-party art or logos; owner content rules apply).
Output: 256x256 transparent PNGs named exactly after the item names, written to
  images/inventory/                              (resource copy)
  ../ox_inventory_additions/web/images/          (copy for ox_inventory/web/images)

Usage:  python3 tools/generate_item_images.py
Requires Pillow and numpy.
"""
import math
import os
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 256
SS = 4                      # supersampling factor
W = SIZE * SS
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'images', 'inventory')
OUT_OX = os.path.join(HERE, '..', '..', 'ox_inventory_additions', 'web', 'images')

GOLD = (214, 182, 104)
GOLD_DARK = (138, 106, 48)
INK = (16, 12, 14)

FONT_PATHS = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf',
]


def font(px):
    for p in FONT_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, px)
    return ImageFont.load_default()


def fit_font(d, text, max_width, start_px):
    px = start_px
    while px > 6:
        f = font(px)
        if d.textlength(text, font=f) <= max_width:
            return f
        px -= 2
    return font(px)


def s(v):
    return int(v * SS)


def canvas():
    return Image.new('RGBA', (W, W), (0, 0, 0, 0))


def linear_gradient(size, c1, c2, angle_deg=90):
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = math.radians(angle_deg)
    proj = (xx * math.cos(a) + yy * math.sin(a))
    proj = (proj - proj.min()) / max(1e-6, proj.max() - proj.min())
    c1 = np.array(c1, np.float32)
    c2 = np.array(c2, np.float32)
    rgb = c1[None, None, :] * (1 - proj[..., None]) + c2[None, None, :] * proj[..., None]
    alpha = np.full((h, w, 1), 255, np.float32)
    return Image.fromarray(np.concatenate([rgb, alpha], axis=2).astype(np.uint8), 'RGBA')


def radial_gradient(size, inner, outer, centre=(0.4, 0.35)):
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = centre[0] * w, centre[1] * h
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    d = np.clip(d / (0.85 * max(w, h)), 0, 1)
    inner = np.array(inner, np.float32)
    outer = np.array(outer, np.float32)
    rgb = inner[None, None, :] * (1 - d[..., None]) + outer[None, None, :] * d[..., None]
    alpha = np.full((h, w, 1), 255, np.float32)
    return Image.fromarray(np.concatenate([rgb, alpha], axis=2).astype(np.uint8), 'RGBA')


def paste_masked(base, fill, mask):
    base.alpha_composite(Image.composite(fill, Image.new('RGBA', base.size, (0, 0, 0, 0)), mask))


def shadow(img, offset=(0, 6), blur=10, opacity=150):
    a = img.split()[3]
    sh = Image.new('RGBA', img.size, (0, 0, 0, 0))
    sh.putalpha(a.point(lambda v: v * opacity // 255))
    sh = sh.filter(ImageFilter.GaussianBlur(s(blur) / 2))
    out = canvas()
    out.alpha_composite(sh, (s(offset[0]), s(offset[1])))
    out.alpha_composite(img)
    return out


def finish(img, name):
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + '.png')
    img.save(path, optimize=True)
    os.makedirs(OUT_OX, exist_ok=True)
    shutil.copyfile(path, os.path.join(OUT_OX, name + '.png'))
    print('wrote', name)


def darker(c, f):
    return tuple(max(0, int(v * f)) for v in c)


def lighter(c, f):
    return tuple(min(255, int(v + (255 - v) * f)) for v in c)


# ---------------------------------------------------------------------------
# Emblem: the "eye of fate" (diamond eye with radiating marks)
# ---------------------------------------------------------------------------
def draw_eye(d, cx, cy, r, colour, iris):
    pts = [(cx - r, cy), (cx, cy - r * 0.55), (cx + r, cy), (cx, cy + r * 0.55)]
    d.polygon(pts, fill=INK, outline=colour, width=s(3))
    d.ellipse([cx - r * 0.32, cy - r * 0.32, cx + r * 0.32, cy + r * 0.32], fill=iris, outline=colour, width=s(2))
    d.ellipse([cx - r * 0.12, cy - r * 0.12, cx + r * 0.12, cy + r * 0.12], fill=INK)
    for i in range(7):
        a = math.radians(-160 + i * (140 / 6))
        x0, y0 = cx + math.cos(a) * r * 0.75, cy + math.sin(a) * r * 0.75
        x1, y1 = cx + math.cos(a) * r * 1.05, cy + math.sin(a) * r * 1.05
        d.line([x0, y0, x1, y1], fill=colour, width=s(3))


# ---------------------------------------------------------------------------
# Tickets
# ---------------------------------------------------------------------------
TICKETS = {
    'red': (179, 18, 42),
    'blue': (36, 84, 200),
    'green': (31, 138, 60),
    'yellow': (226, 186, 30),
    'purple': (118, 46, 172),
    'orange': (222, 102, 26),
}


def ticket(colour_name, rgb):
    img = canvas()
    tw, th = s(212), s(124)
    t = Image.new('RGBA', (tw, th), (0, 0, 0, 0))
    mask = Image.new('L', (tw, th), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, tw - 1, th - 1], radius=s(10), fill=255)
    # notches on the short sides and perforation holes
    nr = s(14)
    md.ellipse([-nr, th / 2 - nr, nr, th / 2 + nr], fill=0)
    md.ellipse([tw - nr, th / 2 - nr, tw + nr, th / 2 + nr], fill=0)
    perf_x = s(58)
    for i in range(9):
        y = s(10) + i * (th - s(20)) / 8
        md.ellipse([perf_x - s(3), y - s(3), perf_x + s(3), y + s(3)], fill=0)
    fill = linear_gradient((tw, th), darker(rgb, 0.35), lighter(rgb, 0.12), angle_deg=20)
    t.paste(fill, (0, 0), mask)
    d = ImageDraw.Draw(t)
    # inner gold border
    inset = s(8)
    d.rounded_rectangle([inset, inset, tw - inset, th - inset], radius=s(6), outline=GOLD, width=s(3))
    d.rounded_rectangle([inset + s(5), inset + s(5), tw - inset - s(5), th - inset - s(5)], radius=s(4), outline=darker(GOLD, 0.7), width=s(1))
    # stub emblem
    draw_eye(d, s(31), th / 2, s(17), GOLD, lighter(rgb, 0.3))
    # text
    left, right = s(68), tw - s(20)
    cx = (left + right) / 2
    f1 = fit_font(d, 'ADMIT ONE', right - left, s(26))
    f2 = fit_font(d, 'CARNIVAL OF THE DAMNED', right - left, s(12))
    d.text((cx, th * 0.42), 'ADMIT ONE', font=f1, fill=GOLD, anchor='mm', stroke_width=s(1), stroke_fill=INK)
    d.text((cx, th * 0.70), 'CARNIVAL OF THE DAMNED', font=f2, fill=lighter(GOLD, 0.3), anchor='mm')
    # stars
    for (x, y) in [(s(80), s(24)), (tw - s(26), th - s(26)), (tw - s(26), s(24)), (s(80), th - s(26))]:
        star(d, x, y, s(5), GOLD)
    t = t.rotate(-12, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(t, ((W - t.width) // 2, (W - t.height) // 2))
    finish(shadow(img), f'carnival_ticket_{colour_name}')


def star(d, cx, cy, r, colour, points=5):
    pts = []
    for i in range(points * 2):
        a = math.pi / points * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=colour)


# ---------------------------------------------------------------------------
# Coins (horror tokens + trick/treat)
# ---------------------------------------------------------------------------
def coin_base(face_inner, face_outer, rim_light, rim_dark):
    img = canvas()
    c = W / 2
    R = s(104)
    mask = Image.new('L', (W, W), 0)
    ImageDraw.Draw(mask).ellipse([c - R, c - R, c + R, c + R], fill=255)
    rim = linear_gradient((W, W), rim_light, rim_dark, angle_deg=60)
    paste_masked(img, rim, mask)
    r2 = R - s(14)
    mask2 = Image.new('L', (W, W), 0)
    ImageDraw.Draw(mask2).ellipse([c - r2, c - r2, c + r2, c + r2], fill=255)
    face = radial_gradient((W, W), face_inner, face_outer)
    paste_masked(img, face, mask2)
    d = ImageDraw.Draw(img)
    # dotted ring
    for i in range(36):
        a = 2 * math.pi * i / 36
        x, y = c + math.cos(a) * (r2 - s(10)), c + math.sin(a) * (r2 - s(10))
        d.ellipse([x - s(2.5), y - s(2.5), x + s(2.5), y + s(2.5)], fill=darker(face_outer, 0.7))
    return img, d, c, r2


def skull(d, cx, cy, r, fill, hole):
    d.ellipse([cx - r, cy - r * 1.05, cx + r, cy + r * 0.75], fill=fill)
    d.rounded_rectangle([cx - r * 0.55, cy + r * 0.35, cx + r * 0.55, cy + r * 1.05], radius=r * 0.15, fill=fill)
    d.ellipse([cx - r * 0.62, cy - r * 0.25, cx - r * 0.14, cy + r * 0.25], fill=hole)
    d.ellipse([cx + r * 0.14, cy - r * 0.25, cx + r * 0.62, cy + r * 0.25], fill=hole)
    d.polygon([(cx, cy + r * 0.3), (cx - r * 0.12, cy + r * 0.52), (cx + r * 0.12, cy + r * 0.52)], fill=hole)
    for i in range(-2, 3):
        x = cx + i * r * 0.2
        d.line([x, cy + r * 0.72, x, cy + r * 1.02], fill=hole, width=max(1, int(r * 0.07)))


def token(kind, inner, outer, rim_l, rim_d, emboss, hole, label):
    img, d, c, r2 = coin_base(inner, outer, rim_l, rim_d)
    skull(d, c, c - s(10), s(42), emboss, hole)
    # crossed keys under the skull
    for sgn in (-1, 1):
        d.line([c - s(52) * sgn, c + s(58), c + s(52) * sgn, c + s(30)], fill=emboss, width=s(7))
    f = font(s(24))
    d.text((c, c + s(72)), label, font=f, fill=emboss, anchor='mm', stroke_width=s(1), stroke_fill=hole)
    if kind == 'gold':
        for (x, y, r) in [(c - s(62), c - s(58), s(9)), (c + s(64), c - s(44), s(7)), (c + s(54), c + s(66), s(6))]:
            star(d, x, y, r, (255, 246, 210), points=4)
    # specular highlight
    hl = Image.new('L', (W, W), 0)
    ImageDraw.Draw(hl).ellipse([c - r2 * 0.8, c - r2 * 0.95, c + r2 * 0.2, c - r2 * 0.1], fill=60)
    hl = hl.filter(ImageFilter.GaussianBlur(s(10)))
    white = Image.new('RGBA', (W, W), (255, 255, 255, 0))
    white.putalpha(hl)
    img.alpha_composite(white)
    finish(shadow(img), f'carnival_token_{kind}')


def bat(d, cx, cy, r, fill):
    pts = [
        (cx, cy - r * 0.2), (cx - r * 0.18, cy - r * 0.45), (cx - r * 0.22, cy - r * 0.15),
        (cx - r * 0.55, cy - r * 0.42), (cx - r * 1.0, cy - r * 0.2), (cx - r * 0.85, cy + r * 0.05),
        (cx - r * 0.6, cy - r * 0.02), (cx - r * 0.45, cy + r * 0.25), (cx - r * 0.25, cy + r * 0.12),
        (cx, cy + r * 0.45),
        (cx + r * 0.25, cy + r * 0.12), (cx + r * 0.45, cy + r * 0.25), (cx + r * 0.6, cy - r * 0.02),
        (cx + r * 0.85, cy + r * 0.05), (cx + r * 1.0, cy - r * 0.2), (cx + r * 0.55, cy - r * 0.42),
        (cx + r * 0.22, cy - r * 0.15), (cx + r * 0.18, cy - r * 0.45),
    ]
    d.polygon(pts, fill=fill)


def candy(d, cx, cy, r, body, wrap, stripe):
    d.polygon([(cx - r * 0.55, cy), (cx - r * 1.05, cy - r * 0.45), (cx - r * 1.05, cy + r * 0.45)], fill=wrap)
    d.polygon([(cx + r * 0.55, cy), (cx + r * 1.05, cy - r * 0.45), (cx + r * 1.05, cy + r * 0.45)], fill=wrap)
    d.ellipse([cx - r * 0.62, cy - r * 0.45, cx + r * 0.62, cy + r * 0.45], fill=body)
    for i in (-1, 0, 1):
        d.line([cx + i * r * 0.28 - r * 0.12, cy - r * 0.42, cx + i * r * 0.28 + r * 0.12, cy + r * 0.42], fill=stripe, width=max(1, int(r * 0.1)))


def trick_token():
    img, d, c, r2 = coin_base((96, 40, 140), (34, 10, 52), (170, 130, 220), (52, 20, 80))
    bat(d, c, c - s(12), s(64), (14, 8, 18))
    d.ellipse([c - s(30), c - s(78), c + s(30), c - s(30)], outline=GOLD, width=s(3))
    d.text((c, c + s(62)), 'TRICK', font=font(s(28)), fill=GOLD, anchor='mm', stroke_width=s(2), stroke_fill=INK)
    finish(shadow(img), 'carnival_trick_token')


def treat_token():
    img, d, c, r2 = coin_base((240, 140, 60), (120, 44, 10), (250, 200, 130), (110, 50, 16))
    candy(d, c, c - s(12), s(58), (170, 20, 40), (226, 196, 120), (250, 230, 200))
    d.text((c, c + s(62)), 'TREAT', font=font(s(28)), fill=(255, 236, 190), anchor='mm', stroke_width=s(2), stroke_fill=INK)
    finish(shadow(img), 'carnival_treat_token')


# ---------------------------------------------------------------------------
# Prize box
# ---------------------------------------------------------------------------
def prize_box():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    # box body (isometric-ish front face + side)
    front = [(c - s(80), c - s(6)), (c + s(30), c + s(20)), (c + s(30), c + s(104)), (c - s(80), c + s(78))]
    side = [(c + s(30), c + s(20)), (c + s(88), c - s(8)), (c + s(88), c + s(74)), (c + s(30), c + s(104))]
    lid_top = [(c - s(92), c - s(36)), (c + s(30), c - s(8)), (c + s(100), c - s(40)), (c - s(22), c - s(66))]
    lid_front = [(c - s(92), c - s(36)), (c + s(30), c - s(8)), (c + s(30), c + s(14)), (c - s(92), c - s(14))]
    lid_side = [(c + s(30), c - s(8)), (c + s(100), c - s(40)), (c + s(100), c - s(18)), (c + s(30), c + s(14))]
    d.polygon(front, fill=(34, 22, 28))
    d.polygon(side, fill=(20, 12, 16))
    d.polygon(lid_front, fill=(48, 30, 38))
    d.polygon(lid_side, fill=(28, 18, 22))
    d.polygon(lid_top, fill=(70, 44, 54))
    # gold trims
    for poly in (front, side, lid_front, lid_side, lid_top):
        d.line(poly + [poly[0]], fill=GOLD, width=s(3), joint='curve')
    # ribbon (blood red)
    red, red_d = (184, 26, 44), (110, 12, 24)
    d.polygon([(c - s(30), c + s(8)), (c - s(14), c + s(12)), (c - s(14), c + s(96)), (c - s(30), c + s(91))], fill=red)
    d.polygon([(c + s(56), c + s(6)), (c + s(66), c + s(1)), (c + s(66), c + s(83)), (c + s(56), c + s(88))], fill=red_d)
    d.polygon([(c - s(36), c - s(22)), (c - s(20), c - s(18)), (c - s(20), c + s(4)), (c - s(36), c)], fill=red)
    d.polygon([(c - s(36), c - s(22)), (c - s(20), c - s(18)), (c + s(62), c - s(52)), (c + s(48), c - s(56))], fill=red)
    # bow
    d.ellipse([c - s(64), c - s(92), c - s(16), c - s(52)], fill=red, outline=red_d, width=s(3))
    d.ellipse([c - s(20), c - s(96), c + s(32), c - s(54)], fill=red, outline=red_d, width=s(3))
    d.ellipse([c - s(30), c - s(78), c - s(6), c - s(56)], fill=red_d)
    # keyhole plate
    d.rounded_rectangle([c - s(60), c + s(28), c - s(38), c + s(56)], radius=s(4), fill=GOLD_DARK, outline=GOLD, width=s(2))
    d.ellipse([c - s(53), c + s(34), c - s(45), c + s(42)], fill=INK)
    d.polygon([(c - s(51), c + s(40)), (c - s(47), c + s(40)), (c - s(45), c + s(51)), (c - s(53), c + s(51))], fill=INK)
    # sparkles
    for (x, y, r) in [(c + s(78), c - s(80), s(9)), (c - s(96), c - s(70), s(6)), (c + s(96), c + s(40), s(5))]:
        star(d, x, y, r, (255, 236, 180), points=4)
    finish(shadow(img), 'carnival_prize_box')


def main():
    for name, rgb in TICKETS.items():
        ticket(name, rgb)
    token('bronze', (196, 128, 70), (92, 50, 22), (226, 160, 100), (80, 42, 18), (66, 34, 14), (196, 128, 70), 'BRONZE')
    token('silver', (232, 232, 240), (120, 122, 134), (250, 250, 255), (96, 98, 110), (70, 72, 84), (232, 232, 240), 'SILVER')
    token('gold', (255, 222, 120), (170, 118, 24), (255, 236, 160), (140, 96, 16), (110, 72, 10), (255, 222, 120), 'GOLD')
    trick_token()
    treat_token()
    prize_box()


if __name__ == '__main__':
    main()
