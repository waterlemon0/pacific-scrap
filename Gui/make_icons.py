"""Placeholder item icons for Pacific Scrap.

Writes Gui/IconMap.png (96x96 icons in a grid) and Gui/IconMap.xml (which
item uuid uses which cell) in the format the game reads for mods. Plain
Python, no extra libraries. Run it again after changing the list below:

    python Gui/make_icons.py

To use proper rendered icons instead, generate them with the Scrap Mechanic
Mod Tool; it writes these same two files.
"""
import math, os, struct, zlib

SIZE = 96
SS = 3  # supersampling for smooth edges

HERE = os.path.dirname(os.path.abspath(__file__))


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


def over(dst, src):
    a = src[3]
    if a <= 0:
        return dst
    out_a = a + dst[3] * (1 - a)
    if out_a <= 0:
        return (0, 0, 0, 0)
    return tuple((src[i] * a + dst[i] * dst[3] * (1 - a)) / out_a for i in range(3)) + (out_a,)


def hexc(h, a=1.0):
    h = h.lstrip("#")
    return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)


# Each icon is a function (x, y) -> colour, with x, y in 0..1 (y down)

def rounded_rect(x, y, x0, y0, x1, y1, r):
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def anchor_icon(colour):
    glow = hexc(colour)
    def f(x, y):
        c = (0, 0, 0, 0)
        d = math.hypot(x - 0.5, y - 0.5)
        # soft glow behind
        if d < 0.48:
            c = over(c, glow[:3] + (0.35 * (1 - d / 0.48) ** 2,))
        # capsule body
        if rounded_rect(x, y, 0.33, 0.12, 0.67, 0.88, 0.12):
            shade = 0.22 + 0.25 * (1 - abs(x - 0.45) / 0.25)
            c = over(c, (shade, shade, shade + 0.03, 1))
            # glowing window
            if rounded_rect(x, y, 0.39, 0.28, 0.61, 0.72, 0.08):
                t = min(1, math.hypot(x - 0.5, (y - 0.5) * 0.6) / 0.16)
                c = over(c, mix((1, 1, 1, 1), glow, t * 0.8 + 0.2))
            # caps
            if y < 0.2 or y > 0.8:
                c = over(c, (0.12, 0.12, 0.13, 1))
        return c
    return f


def arc_icon(x, y):
    c = (0, 0, 0, 0)
    if rounded_rect(x, y, 0.14, 0.22, 0.86, 0.82, 0.08):
        c = (0.95, 0.64, 0.0, 1)
        if rounded_rect(x, y, 0.22, 0.30, 0.78, 0.74, 0.05):
            c = (0.15, 0.15, 0.17, 1)
            # lightning bolt
            pts = [(0.56, 0.32), (0.40, 0.54), (0.50, 0.54), (0.44, 0.72), (0.62, 0.48), (0.52, 0.48)]
            if point_in_poly(x, y, pts):
                c = (0.55, 0.9, 1.0, 1)
    if 0.40 < x < 0.60 and 0.12 < y < 0.22:
        c = (0.6, 0.6, 0.62, 1)
    return c


def fabricator_icon(x, y):
    c = (0, 0, 0, 0)
    teal = hexc("2a9d8f")
    if rounded_rect(x, y, 0.16, 0.18, 0.84, 0.70, 0.12):
        c = teal
        if rounded_rect(x, y, 0.24, 0.28, 0.76, 0.58, 0.08):
            c = (0.1, 0.12, 0.14, 1)
            for ex in (0.38, 0.62):
                if math.hypot(x - ex, y - 0.43) < 0.07:
                    c = (0.5, 1.0, 0.9, 1)
    if rounded_rect(x, y, 0.30, 0.70, 0.70, 0.86, 0.04):
        c = (0.3, 0.3, 0.32, 1)
    # antenna
    if abs(x - 0.5) < 0.025 and 0.08 < y < 0.18:
        c = (0.6, 0.6, 0.62, 1)
    if math.hypot(x - 0.5, y - 0.08) < 0.045:
        c = (1.0, 0.8, 0.2, 1)
    return c


def dumpster_icon(x, y):
    c = (0, 0, 0, 0)
    green = hexc("2e8b3a")
    if rounded_rect(x, y, 0.12, 0.34, 0.88, 0.86, 0.06):
        c = green
        # ribs
        if any(abs(x - rx) < 0.02 for rx in (0.30, 0.70)) and 0.40 < y < 0.80:
            c = mix(green, (0, 0, 0, 1), 0.3)
        # smile
        d = math.hypot(x - 0.5, y - 0.52)
        if 0.12 < d < 0.16 and y > 0.56:
            c = (1, 1, 1, 1)
        for ex in (0.40, 0.60):
            if math.hypot(x - ex, y - 0.50) < 0.035:
                c = (1, 1, 1, 1)
    # lid
    if rounded_rect(x, y, 0.08, 0.22, 0.92, 0.34, 0.04):
        c = mix(green, (0, 0, 0, 1), 0.35)
    return c


def planner_icon(x, y):
    c = (0, 0, 0, 0)
    if rounded_rect(x, y, 0.12, 0.16, 0.88, 0.70, 0.06):
        c = hexc("2a7fbf")
        if rounded_rect(x, y, 0.18, 0.22, 0.82, 0.62, 0.04):
            c = (0.08, 0.12, 0.10, 1)
            # little route: dots joined by lines
            pts = [(0.30, 0.54), (0.45, 0.40), (0.60, 0.48), (0.72, 0.30)]
            for i in range(len(pts) - 1):
                (ax, ay), (bx, by) = pts[i], pts[i + 1]
                t = max(0, min(1, ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / ((bx - ax) ** 2 + (by - ay) ** 2)))
                if math.hypot(x - (ax + t * (bx - ax)), y - (ay + t * (by - ay))) < 0.018:
                    c = (0.6, 1.0, 0.6, 1)
            for px, py in pts:
                if math.hypot(x - px, y - py) < 0.04:
                    c = (1.0, 0.83, 0.29, 1)
    if rounded_rect(x, y, 0.30, 0.70, 0.70, 0.86, 0.04):
        c = (0.3, 0.3, 0.32, 1)
    return c


def pedestal_icon(x, y):
    c = (0, 0, 0, 0)
    if rounded_rect(x, y, 0.20, 0.55, 0.80, 0.85, 0.05):
        c = (0.35, 0.35, 0.37, 1)
    if rounded_rect(x, y, 0.34, 0.40, 0.66, 0.56, 0.04):
        c = (0.25, 0.25, 0.27, 1)
    if math.hypot(x - 0.5, y - 0.36) < 0.08:
        c = hexc("f5b830")
    return c


def point_in_poly(x, y, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


# uuid -> icon
ICONS = [
    ("c243bb55-92f9-4f77-bb2a-b7c87b5a2be9", anchor_icon("f5b830")),  # stable energy anchor
    ("e7a1c3d2-5b6f-4a8e-9c1d-2f3b4a5c6d7e", anchor_icon("f27aa8")),  # unstable energy anchor
    ("9b8c7d6e-1f2a-4b3c-8d4e-5f6a7b8c9d0e", anchor_icon("4ed98c")),  # corrupted energy anchor
    ("a6258a75-ea2b-47f7-acec-a3ace313bbd9", arc_icon),               # ARC Device
    ("7ee97af5-72b9-4335-a3bd-e80d49dab105", fabricator_icon),        # Fabricator
    ("d0f1e2a3-b4c5-4d6e-8f70-81a2b3c4d5e6", dumpster_icon),          # Friendly Dumpster
    ("a6be2c12-f280-4d2b-b270-8e407813c28d", pedestal_icon),          # anchor pedestal
    ("c1d2e3f4-a5b6-4c7d-8e9f-a0b1c2d3e4f5", planner_icon),           # Route Planner
]

COLUMNS = 4
rows = (len(ICONS) + COLUMNS - 1) // COLUMNS
width, height = COLUMNS * SIZE, rows * SIZE
pixels = [[(0, 0, 0, 0)] * width for _ in range(height)]

for n, (_, icon) in enumerate(ICONS):
    ox, oy = (n % COLUMNS) * SIZE, (n // COLUMNS) * SIZE
    for py in range(SIZE):
        for px in range(SIZE):
            acc = [0, 0, 0, 0]
            for sy in range(SS):
                for sx in range(SS):
                    c = icon((px + (sx + 0.5) / SS) / SIZE, (py + (sy + 0.5) / SS) / SIZE)
                    acc[0] += c[0] * c[3]; acc[1] += c[1] * c[3]; acc[2] += c[2] * c[3]; acc[3] += c[3]
            a = acc[3] / (SS * SS)
            if a > 0:
                pixels[oy + py][ox + px] = (acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], a)

raw = b"".join(
    b"\x00" + bytes(int(max(0, min(1, v)) * 255 + 0.5) for p in row for v in p)
    for row in pixels
)
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open(os.path.join(HERE, "IconMap.png"), "wb").write(png)

lines = ['﻿<?xml version="1.0" encoding="UTF-8"?>',
         '<MyGUI type="Resource" version="1.1">',
         '    <Resource type="ResourceImageSet" name="ItemIconsSet0">',
         '        <Group name="ItemIcons" texture="IconMap.png" size="96 96">',
         '            <Index name="Empty">',
         '                <Frame point="0 0"/>',
         '            </Index>']
for n, (uuid, _) in enumerate(ICONS):
    lines += ['            <Index name="%s">' % uuid,
              '                <Frame point="%d %d"/>' % ((n % COLUMNS) * SIZE, (n // COLUMNS) * SIZE),
              '            </Index>']
lines += ['        </Group>', '    </Resource>', '</MyGUI>', '']
open(os.path.join(HERE, "IconMap.xml"), "w", encoding="utf-8").write("\n".join(lines))
print("wrote %d icons (%dx%d)" % (len(ICONS), width, height))
