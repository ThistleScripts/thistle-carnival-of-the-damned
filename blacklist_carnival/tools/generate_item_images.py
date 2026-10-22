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


# ---------------------------------------------------------------------------
# Carnival food (prize counter)
# ---------------------------------------------------------------------------
def gloss(img, box, alpha=70, blur=8):
    hl = Image.new('L', (W, W), 0)
    ImageDraw.Draw(hl).ellipse(box, fill=alpha)
    hl = hl.filter(ImageFilter.GaussianBlur(s(blur)))
    hl = Image.fromarray((np.asarray(hl, np.float32) * np.asarray(img.split()[3], np.float32) / 255).astype(np.uint8), 'L')
    white = Image.new('RGBA', (W, W), (255, 255, 255, 0))
    white.putalpha(hl)
    img.alpha_composite(white)


def drip(d, x, y, w, length, colour):
    d.rectangle([x - w / 2, y, x + w / 2, y + length], fill=colour)
    d.ellipse([x - w * 0.75, y + length - w * 0.75, x + w * 0.75, y + length + w * 0.75], fill=colour)


def stick(d, x0, y0, x1, y1, w=8):
    d.line([x0, y0, x1, y1], fill=(222, 196, 150), width=s(w))
    d.line([x0 + s(2), y0, x1 + s(2), y1], fill=(170, 140, 96), width=s(2))


def eyeball(d, cx, cy, r, iris=(60, 150, 70)):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(246, 240, 228), outline=(180, 160, 150), width=max(1, int(r * 0.06)))
    for a in (0.3, 1.4, 2.6, 4.0, 5.2):
        x0, y0 = cx + math.cos(a) * r * 0.95, cy + math.sin(a) * r * 0.95
        x1, y1 = cx + math.cos(a + 0.25) * r * 0.55, cy + math.sin(a + 0.25) * r * 0.55
        d.line([x0, y0, x1, y1], fill=(196, 40, 50), width=max(1, int(r * 0.05)))
    d.ellipse([cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45], fill=iris)
    d.ellipse([cx - r * 0.2, cy - r * 0.2, cx + r * 0.2, cy + r * 0.2], fill=INK)
    d.ellipse([cx - r * 0.32, cy - r * 0.34, cx - r * 0.12, cy - r * 0.14], fill=(255, 255, 255))


def cup(d, c, top, bottom, top_w, bottom_w, body, band):
    d.polygon([(c - top_w, top), (c + top_w, top), (c + bottom_w, bottom), (c - bottom_w, bottom)], fill=body)
    mid = (top + bottom) / 2
    f = lambda y: top_w + (bottom_w - top_w) * (y - top) / (bottom - top)
    y0, y1 = mid - s(14), mid + s(14)
    d.polygon([(c - f(y0), y0), (c + f(y0), y0), (c + f(y1), y1), (c - f(y1), y1)], fill=band)
    return f


def candy_floss():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    stick(d, c, c + s(10), c + s(4), c + s(118), 10)
    blobs = [(0, -40, 64), (-44, -18, 46), (46, -16, 46), (-26, -74, 40), (30, -76, 42), (0, 6, 44), (-52, -52, 32), (54, -50, 32)]
    for i, (x, y, r) in enumerate(blobs):
        col = (170 - i * 6, 14, 34 + i * 2)
        d.ellipse([c + s(x - r), c + s(y - r), c + s(x + r), c + s(y + r)], fill=col)
    for i, (x, y, r) in enumerate(blobs):
        d.ellipse([c + s(x - r * 0.55), c + s(y - r * 0.7), c + s(x + r * 0.35), c + s(y - r * 0.05)], fill=(212, 46, 70))
    img = img.filter(ImageFilter.GaussianBlur(s(1.5)))
    d = ImageDraw.Draw(img)
    for x in (-30, 6, 38):
        drip(d, c + s(x), c + s(20), s(7), s(22 + (x % 13)), (120, 6, 20))
    for (x, y) in [(-50, -86), (60, -30), (-10, -100)]:
        star(d, c + s(x), c + s(y), s(5), (255, 210, 210), points=4)
    finish(shadow(img), 'carnival_bloodfloss')


def poison_apple():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    stick(d, c + s(6), c - s(116), c + s(2), c - s(30), 9)
    body = Image.new('L', (W, W), 0)
    bd = ImageDraw.Draw(body)
    bd.ellipse([c - s(84), c - s(56), c + s(4), c + s(84)], fill=255)
    bd.ellipse([c - s(4), c - s(56), c + s(84), c + s(84)], fill=255)
    paste_masked(img, radial_gradient((W, W), (40, 180, 70), (6, 40, 14), (0.38, 0.4)), body)
    d = ImageDraw.Draw(img)
    # black caramel coat with drips
    coat = [(c - s(82), c - s(6)), (c - s(60), c - s(54)), (c, c - s(62)), (c + s(60), c - s(54)), (c + s(82), c - s(6))]
    d.polygon(coat, fill=(18, 12, 16))
    for x, l in [(-70, 20), (-44, 42), (-14, 28), (18, 52), (46, 30), (70, 16)]:
        drip(d, c + s(x), c - s(10), s(12), s(l), (18, 12, 16))
    gloss(img, [c - s(66), c - s(54), c - s(20), c - s(30)], alpha=90, blur=4)
    d = ImageDraw.Draw(img)
    skull(d, c + s(34), c + s(44), s(16), (190, 255, 170), (10, 40, 14))
    finish(shadow(img), 'carnival_poison_apple')


def finger_dog():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    batter = (198, 128, 52)
    img2 = canvas()
    d2 = ImageDraw.Draw(img2)
    stick(d2, c, c + s(40), c, c + s(124), 10)
    d2.rounded_rectangle([c - s(34), c - s(90), c + s(34), c + s(62)], radius=s(34), fill=batter)
    # the finger poking from the top
    d2.rounded_rectangle([c - s(20), c - s(124), c + s(20), c - s(60)], radius=s(20), fill=(232, 196, 170))
    d2.rounded_rectangle([c - s(14), c - s(120), c + s(14), c - s(96)], radius=s(8), fill=(150, 160, 150))
    for y in (-80, -70):
        d2.arc([c - s(14), c + s(y - 6), c + s(14), c + s(y + 6)], 20, 160, fill=(170, 120, 100), width=s(2))
    for (x, y) in [(-18, -40), (12, -10), (-10, 20), (16, 40), (-20, 0)]:
        d2.ellipse([c + s(x - 6), c + s(y - 4), c + s(x + 6), c + s(y + 4)], fill=darker(batter, 0.75))
    # ketchup "blood" zigzag
    pts = [(c - s(30) + (s(60) if i % 2 else 0), c - s(70) + i * s(18)) for i in range(7)]
    d2.line(pts, fill=(170, 16, 28), width=s(7), joint='curve')
    drip(d2, c - s(30), c + s(38), s(8), s(26), (170, 16, 28))
    gloss(img2, [c - s(30), c - s(80), c - s(4), c + s(40)], alpha=60, blur=5)
    img2 = img2.rotate(-18, resample=Image.BICUBIC)
    img.alpha_composite(img2)
    finish(shadow(img), 'carnival_finger_dog')


def grave_popcorn():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    top, bottom = c - s(30), c + s(110)
    # kernels
    rnd = np.random.default_rng(13)
    for _ in range(46):
        x = c + s(rnd.uniform(-70, 70))
        y = c + s(rnd.uniform(-96, -24))
        r = s(rnd.uniform(11, 17))
        col = (250, 240, 214) if rnd.random() > 0.25 else (60, 54, 58)
        d.ellipse([x - r, y - r, x + r, y + r], fill=col, outline=darker(col, 0.8), width=s(1))
    # striped box (black and blood red)
    stripes = 6
    for i in range(stripes):
        xa = -80 + i * 160 / stripes
        xb = xa + 160 / stripes
        col = (20, 14, 18) if i % 2 == 0 else (150, 18, 34)
        d.polygon([(c + s(xa), top), (c + s(xb), top), (c + s(xb * 0.75), bottom), (c + s(xa * 0.75), bottom)], fill=col)
    d.polygon([(c - s(80), top), (c - s(60), bottom), (c + s(60), bottom), (c + s(80), top)], outline=GOLD, width=s(3))
    d.rounded_rectangle([c - s(40), c + s(14), c + s(40), c + s(68)], radius=s(12), fill=(232, 222, 204), outline=GOLD, width=s(2))
    skull(d, c, c + s(40), s(16), (20, 14, 18), (232, 222, 204))
    finish(shadow(img), 'carnival_grave_popcorn')


def bone_pretzel():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    dough, edge = (178, 98, 36), (110, 56, 18)
    w = s(26)
    # bone shaft
    d.line([c - s(70), c + s(60), c + s(70), c - s(60)], fill=edge, width=w + s(8))
    d.line([c - s(70), c + s(60), c + s(70), c - s(60)], fill=dough, width=w)
    for (x, y) in [(-70, 60), (70, -60)]:
        for (ox, oy) in [(-14, -14), (14, 14)] if x < 0 else [(-14, -14), (14, 14)]:
            cx, cy = c + s(x + ox * (1 if x > 0 else -1)), c + s(y + oy)
            d.ellipse([cx - s(24), cy - s(24), cx + s(24), cy + s(24)], fill=edge)
    for (x, y) in [(-70, 60), (70, -60)]:
        for (ox, oy) in [(-14, -14), (14, 14)]:
            cx, cy = c + s(x + ox * (1 if x > 0 else -1)), c + s(y + oy)
            d.ellipse([cx - s(19), cy - s(19), cx + s(19), cy + s(19)], fill=dough)
    gloss(img, [c - s(40), c - s(40), c + s(50), c + s(10)], alpha=50, blur=6)
    d = ImageDraw.Draw(img)
    rnd = np.random.default_rng(7)
    for _ in range(40):
        t_ = rnd.uniform(-0.9, 0.9)
        x = c + s(70 * t_ + rnd.uniform(-8, 8))
        y = c - s(60 * t_ + rnd.uniform(-8, 8))
        d.rectangle([x - s(2.5), y - s(2), x + s(2.5), y + s(2)], fill=(250, 250, 246))
    finish(shadow(img), 'carnival_bone_pretzel')


def web_cake():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    # paper plate
    d.ellipse([c - s(110), c - s(64), c + s(110), c + s(98)], fill=(36, 26, 32), outline=GOLD, width=s(3))
    cake = (196, 126, 58)
    rnd = np.random.default_rng(3)
    for _ in range(32):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(10, 70)
        x, y = c + s(math.cos(a) * r), c + s(17 + math.sin(a) * r * 0.62)
        d.arc([x - s(26), y - s(16), x + s(26), y + s(16)], rnd.uniform(0, 360), rnd.uniform(0, 360) + 220, fill=darker(cake, 0.8), width=s(13))
        d.arc([x - s(26), y - s(16), x + s(26), y + s(16)], rnd.uniform(0, 360), rnd.uniform(0, 360) + 200, fill=cake, width=s(9))
    # powdered sugar cobweb
    cy = c + s(17)
    for i in range(8):
        a = i * math.pi / 4
        d.line([c, cy, c + math.cos(a) * s(84), cy + math.sin(a) * s(52)], fill=(250, 248, 244), width=s(2))
    for k in (0.3, 0.55, 0.8):
        pts = [(c + math.cos(i * math.pi / 4) * s(84) * k, cy + math.sin(i * math.pi / 4) * s(52) * k) for i in range(9)]
        d.line(pts, fill=(250, 248, 244), width=s(2))
    # little spider
    d.line([c + s(30), cy - s(36), c + s(30), cy - s(80)], fill=(240, 240, 240), width=s(1))
    d.ellipse([c + s(22), cy - s(42), c + s(38), cy - s(28)], fill=INK)
    for sx in (-1, 1):
        for k in range(4):
            d.line([c + s(30), cy - s(35), c + s(30 + sx * 14), cy - s(44 - k * 6)], fill=INK, width=s(2))
    finish(shadow(img), 'carnival_web_cake')


def eyeball_pop():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    stick(d, c, c + s(20), c, c + s(124), 9)
    eyeball(d, c, c - s(30), s(70), iris=(126, 40, 160))
    # blood glaze drips at the bottom
    for x, l in [(-40, 18), (-10, 30), (24, 22), (46, 12)]:
        drip(d, c + s(x), c + s(28), s(10), s(l), (160, 12, 26))
    gloss(img, [c - s(56), c - s(92), c - s(10), c - s(56)], alpha=110, blur=4)
    finish(shadow(img), 'carnival_eyeball_pop')


def witch_brew():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    top, bottom = c - s(66), c + s(112)
    f = cup(d, c, top, bottom, s(66), s(48), (24, 18, 26), (118, 46, 172))
    # bubbling green liquid over the brim
    d.ellipse([c - s(66), top - s(14), c + s(66), top + s(14)], fill=(70, 210, 70))
    for (x, y, r) in [(-40, -20, 16), (-10, -30, 20), (24, -24, 16), (48, -12, 11), (6, -52, 10), (-26, -46, 8)]:
        d.ellipse([c + s(x - r), top + s(y - r), c + s(x + r), top + s(y + r)], fill=(96, 230, 90), outline=(30, 120, 30), width=s(2))
    for x, l in [(-56, 30), (54, 44)]:
        drip(d, c + s(x), top, s(10), s(l), (70, 210, 70))
    # straw
    d.line([c + s(20), top - s(10), c + s(54), top - s(100)], fill=(20, 14, 18), width=s(10))
    d.line([c + s(20), top - s(10), c + s(54), top - s(100)], fill=(70, 210, 70), width=s(4))
    star(d, c, c + s(22), s(14), GOLD, points=5)
    d.text((c, c + s(72)), 'BREW', font=font(s(20)), fill=GOLD, anchor='mm')
    finish(shadow(img), 'carnival_witch_brew')


def blood_slushie():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    top, bottom = c - s(40), c + s(114)
    # dome of red ice
    d.pieslice([c - s(64), top - s(70), c + s(64), top + s(60)], 180, 360, fill=(176, 12, 32))
    rnd = np.random.default_rng(5)
    for _ in range(60):
        x = c + s(rnd.uniform(-56, 56))
        y = top - s(rnd.uniform(2, 54)) * (1 - abs(x - c) / s(80))
        d.ellipse([x - s(3), y - s(3), x + s(3), y + s(3)], fill=(232, 80, 96))
    # clear cup showing the slush
    d.polygon([(c - s(64), top), (c + s(64), top), (c + s(46), bottom), (c - s(46), bottom)], fill=(150, 10, 28))
    d.polygon([(c - s(64), top), (c + s(64), top), (c + s(46), bottom), (c - s(46), bottom)], outline=(230, 220, 230), width=s(3))
    gloss(img, [c - s(56), top, c - s(30), bottom - s(10)], alpha=80, blur=4)
    d = ImageDraw.Draw(img)
    # moon label
    d.ellipse([c - s(26), c + s(30), c + s(26), c + s(82)], fill=(240, 220, 160))
    d.ellipse([c - s(14), c + s(24), c + s(34), c + s(74)], fill=(150, 10, 28))
    # spoon straw
    d.line([c - s(10), top - s(40), c - s(40), top - s(110)], fill=(250, 246, 240), width=s(8))
    finish(shadow(img), 'carnival_blood_slushie')


def grave_shake():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = W / 2
    top, bottom = c - s(40), c + s(114)
    f = cup(d, c, top, bottom, s(60), s(42), (226, 216, 200), (96, 60, 40))
    # chocolate "dirt" mound
    d.pieslice([c - s(62), top - s(54), c + s(62), top + s(40)], 180, 360, fill=(70, 40, 26))
    rnd = np.random.default_rng(11)
    for _ in range(70):
        x = c + s(rnd.uniform(-54, 54))
        y = top - s(rnd.uniform(0, 40)) * (1 - abs(x - c) / s(70))
        d.ellipse([x - s(3), y - s(3), x + s(3), y + s(3)], fill=(40, 22, 14))
    # gummy worms
    for (x0, col) in [(-30, (240, 120, 40)), (20, (150, 70, 200))]:
        pts = [(c + s(x0 + 8 * math.sin(i * 0.9)), top - s(30) + s(i * 7)) for i in range(7)]
        d.line(pts, fill=col, width=s(10), joint='curve')
    # tombstone
    d.rounded_rectangle([c - s(18), top - s(70), c + s(18), top - s(24)], radius=s(14), fill=(150, 150, 160), outline=(80, 80, 90), width=s(2))
    d.text((c, top - s(48)), 'RIP', font=font(s(12)), fill=(60, 60, 70), anchor='mm')
    d.text((c, c + s(48)), 'GRAVE', font=font(s(18)), fill=(226, 216, 200), anchor='mm')
    finish(shadow(img), 'carnival_grave_shake')


FOOD = [candy_floss, poison_apple, finger_dog, grave_popcorn, bone_pretzel, web_cake, eyeball_pop, witch_brew, blood_slushie, grave_shake]


def main():
    for name, rgb in TICKETS.items():
        ticket(name, rgb)
    token('bronze', (196, 128, 70), (92, 50, 22), (226, 160, 100), (80, 42, 18), (66, 34, 14), (196, 128, 70), 'BRONZE')
    token('silver', (232, 232, 240), (120, 122, 134), (250, 250, 255), (96, 98, 110), (70, 72, 84), (232, 232, 240), 'SILVER')
    token('gold', (255, 222, 120), (170, 118, 24), (255, 236, 160), (140, 96, 16), (110, 72, 10), (255, 222, 120), 'GOLD')
    trick_token()
    treat_token()
    prize_box()
    for draw in FOOD:
        draw()


if __name__ == '__main__':
    main()
