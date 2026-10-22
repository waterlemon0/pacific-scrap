"""Route Planner map for Pacific Scrap.

Writes Gui/RouteMap.png and Scripts/map_sites.lua. The picture: a dark topographic map of the zone, loosely like
Pacific Drive's Olympic Exclusion Zone (water to the west and north), with the
zone tiers as rings around the core: Outer, Mid and Deep. The sites: every
place on the land a junction can be (spread out, each with its depth by how
close it is to the core). The game puts junctions on these as the map grows,
so the map is all there from the start and junctions only get revealed.
Plain Python, no extra libraries (takes a minute). Run it again after changing anything:

    python Gui/make_map.py

The map's coordinates must match JunctionMap.lua: MAP_BOUNDS (the picture's
corners, map units), MAP_CORE_RADIUS (garage to core) and MAP_DEPTH_STEP.
"""
import math, os, random, struct, zlib

HERE = os.path.dirname(os.path.abspath(__file__))

SIZE = 1024
X0, X1, Y0, Y1 = -1600.0, 1600.0, -2900.0, 300.0   # MAP_BOUNDS
CORE_RADIUS = 2300.0                              # garage (0, 0) to the core (0, -2300)
DEPTH_STEP = 220.0
CORE = (0.0, -CORE_RADIUS)
# Tier borders: halfway between the last junction of one tier and the first of the next
OUTER_MID = CORE_RADIUS - DEPTH_STEP * 3.5
MID_DEEP = CORE_RADIUS - DEPTH_STEP * 6.5

random.seed(7)
PERM = list(range(256))
random.shuffle(PERM)
PERM += PERM


def hash2(ix, iy, seed):
    return PERM[(PERM[(ix + seed) & 255] + iy) & 255] / 255.0


def value_noise(x, y, seed):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = hash2(ix, iy, seed)
    b = hash2(ix + 1, iy, seed)
    c = hash2(ix, iy + 1, seed)
    d = hash2(ix + 1, iy + 1, seed)
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy


def fbm(x, y, seed, octaves=5):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total += value_noise(x, y, seed + o * 31) * amp
        norm += amp
        x, y, amp = x * 2.03, y * 2.03, amp * 0.5
    return total / norm


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def clamp01(v):
    return max(0.0, min(1.0, v))


# Colours
PAPER = (0.10, 0.13, 0.16)
LAND_LOW = (0.16, 0.21, 0.20)
LAND_HIGH = (0.27, 0.30, 0.26)
WATER_DEEP = (0.05, 0.09, 0.14)
WATER_SHALLOW = (0.09, 0.16, 0.22)
CONTOUR = (0.42, 0.47, 0.42)
GRID = (0.30, 0.38, 0.44)
TIER_TINT = {"outer": (0.25, 0.65, 0.70), "mid": (0.95, 0.65, 0.20), "deep": (0.85, 0.20, 0.30)}
TIER_ALPHA = {"outer": 0.05, "mid": 0.10, "deep": 0.20}

def height_at(mx, my):
    return fbm(mx / 900.0, my / 900.0, 3)


def land_at(mx, my):
    """> 0 on land, < 0 in the sea"""
    u, v = mx / 900.0, my / 900.0
    h = height_at(mx, my)
    # A rounded peninsula with a ragged coast: sea all round, wider to the
    # west and north (the garage sits near the south shore)
    ex_, ey_ = (mx + 80) / 1380.0, (my + 1330) / 1560.0
    return (1.0 - math.sqrt(ex_ * ex_ + ey_ * ey_)) * 2.2 + (fbm(u * 1.7, v * 1.7, 41) - 0.5) * 1.6 + (h - 0.5) * 0.6


rows = []
for py in range(SIZE):
    my = Y0 + (Y1 - Y0) * (py + 0.5) / SIZE
    row = bytearray()
    for px in range(SIZE):
        mx = X0 + (X1 - X0) * (px + 0.5) / SIZE
        h = height_at(mx, my)
        land = land_at(mx, my)
        if land < 0:
            c = mix(WATER_SHALLOW, WATER_DEEP, clamp01(-land * 0.8))
            # Faint ripple lines in the water
            if (land * 6) % 1.0 < 0.06:
                c = mix(c, WATER_SHALLOW, 0.6)
        else:
            c = mix(LAND_LOW, LAND_HIGH, clamp01((h - 0.35) * 2.2))
            # Contour lines (every 1/14 of height), heavier every fifth
            k = h * 14.0
            f = k % 1.0
            if f < 0.07 or f > 0.93:
                c = mix(c, CONTOUR, 0.55 if int(round(k)) % 5 == 0 else 0.28)
            if land < 0.08:
                c = mix(c, (0.55, 0.55, 0.45), 0.35)   # shoreline
        # Zone tiers around the core
        dx, dy = mx - CORE[0], my - CORE[1]
        r = math.sqrt(dx * dx + dy * dy)
        tier = "deep" if r < MID_DEEP else ("mid" if r < OUTER_MID else "outer")
        c = mix(c, TIER_TINT[tier], TIER_ALPHA[tier] * (1.0 if land >= 0 else 0.35))
        # Dashed ring on each tier border
        angle = math.atan2(dy, dx)
        for border, colour in ((OUTER_MID, TIER_TINT["mid"]), (MID_DEEP, TIER_TINT["deep"])):
            if abs(r - border) < 5.0 and (angle * border / 40.0) % 1.0 < 0.6:
                c = mix(c, colour, 0.8)
        # The core: a glowing eye
        if r < 200:
            c = mix(c, (0.95, 0.35, 0.45), clamp01((200 - r) / 200) * 0.6)
        # Map grid every 200 units
        if abs((mx + 10000) % 200.0) < 3.2 or abs((my + 10000) % 200.0) < 3.2:
            c = mix(c, GRID, 0.18)
        # Vignette
        ex = min(px, SIZE - 1 - px) / (SIZE * 0.12)
        ey = min(py, SIZE - 1 - py) / (SIZE * 0.12)
        c = mix(PAPER, c, clamp01(min(ex, ey)) * 0.85 + 0.15)
        row += bytes(int(clamp01(ch) * 255 + 0.5) for ch in c) + b"\xff"
    rows.append(b"\x00" + bytes(row))

raw = b"".join(rows)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open(os.path.join(HERE, "RouteMap.png"), "wb").write(png)
print("wrote RouteMap.png (%dx%d)" % (SIZE, SIZE))

# ---------------------------------------------------------------- junction sites
SITE_SPACING = 290.0   # sites at least this far apart (map units): the whole map is these (about 45, like Pacific Drive's 43)
SITE_BAND = 100.0      # how far off its depth's ring a site may be


def ring_radius(depth):
    """MapRadius in JunctionMap.lua"""
    if depth <= 9:
        return CORE_RADIUS - DEPTH_STEP * depth
    return (CORE_RADIUS - DEPTH_STEP * 9) * 0.8 ** (depth - 9)


NL, TAB = chr(10), chr(9)
rng = random.Random(1234)
sites, grid = [], {}
cell = SITE_SPACING / math.sqrt(2)
for _ in range(120000):
    x = rng.uniform(X0 + 80, X1 - 80)
    y = rng.uniform(Y0 + 80, Y1 - 80)
    r = math.hypot(x - CORE[0], y - CORE[1])
    depth = min(range(1, 15), key=lambda d: abs(r - ring_radius(d)))
    if abs(r - ring_radius(depth)) > SITE_BAND * (1.0 if depth <= 9 else 0.5):
        continue
    if land_at(x, y) < 0.18:          # not in the sea or right on the shore
        continue
    if math.hypot(x, y) < 150:        # not on the garage
        continue
    gx, gy = int(x // cell), int(y // cell)
    near = False
    for ox in range(-2, 3):
        for oy in range(-2, 3):
            for (sx, sy, _) in grid.get((gx + ox, gy + oy), []):
                if (sx - x) ** 2 + (sy - y) ** 2 < SITE_SPACING ** 2:
                    near = True
    if near:
        continue
    grid.setdefault((gx, gy), []).append((x, y, depth))
    sites.append((x, y, depth))

sites.sort(key=lambda t: (t[2], math.atan2(t[1] - CORE[1], t[0] - CORE[0])))

# Codes like Pacific Drive's: a letter per region, numbered outward from home.
# Outer Zone (depth 1-3): G west, E middle, F east. Mid Zone (4-6): D west,
# C middle, B east. Deep Zone (7+): A.
def region(x, y, d):
    if d >= 7:
        return "A"
    third = "west" if x < -380 else ("east" if x > 380 else "middle")
    if d <= 3:
        return {"west": "G", "middle": "E", "east": "F"}[third]
    return {"west": "D", "middle": "C", "east": "B"}[third]

codes = {}
by_region = {}
for i, (x, y, d) in enumerate(sites):
    by_region.setdefault(region(x, y, d), []).append(i)
for letter, members in by_region.items():
    members.sort(key=lambda i: math.hypot(sites[i][0], sites[i][1]))
    for n, i in enumerate(members):
        codes[i] = "%s%d" % (letter, n + 1)
lines = ["-- Made by Gui/make_map.py: every place on the map a junction can be.",
         "-- x, y: map units (the garage at 0,0); d: the junction depth for it;",
         "-- code: its name on the map (a letter per region, numbered outward from home).",
         "MAP_SITES = {"]
for i, (x, y, d) in enumerate(sites):
    lines.append(TAB + "{ x = %d, y = %d, d = %d, code = \"%s\" }," % (round(x), round(y), d, codes[i]))
lines.append("}")
open(os.path.join(HERE, "..", "Scripts", "map_sites.lua"), "w", encoding="utf-8").write(NL.join(lines) + NL)
counts = {}
for (_, _, d) in sites:
    counts[d] = counts.get(d, 0) + 1
print("wrote map_sites.lua: %d sites, per depth %s" % (len(sites), dict(sorted(counts.items()))))
