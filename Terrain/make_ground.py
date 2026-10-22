"""Makes the Mid Zone's pink ground: recoloured copies of the game's grass
ground textures and a ground material set using them
(Terrain/Materials/zone_mid.json, Terrain/Textures/Ground/zone_mid_*.tga).

The ZoneWorldMid world class (Scripts/DriveWorld.lua) uses that set; the zone
tier picks the class (ZONE_TIERS worldClass in Scripts/layouts.lua). A world's
ground textures are fixed per class, which is why it's a class of its own.
(Ground paint doesn't show on the grass textures, so this is how the ground
gets its colour.)

Run:  python Terrain/make_ground.py   (then clear the mod's Cache folder)
No libraries needed: reads the game's RLE .tga files and writes plain ones.
"""
import colorsys
import json
import math
import os
import struct

GAME = r"D:\steam\steamapps\common\Scrap Mechanic"
HERE = os.path.dirname(os.path.abspath(__file__))
GROUND = os.path.join(GAME, "Data", "Terrain", "Textures", "Ground")
STANDARD_SET = os.path.join(GAME, "Data", "Terrain", "Materials", "gnd_standard_materialset.json")

# The standard set's ground materials, by index:
# 0 Concrete, 1 Sand, 2 Stone, 3 Dirt, 4 Weeds, 5 Rough Stone, 6 Hay, 7 Bright grass, 8 Grass
# Each look: material index -> recolour. hue: the colour to turn it to (0-1;
# 0.92: pink), keeping its own variation; sat / val:
# multipliers for saturation and brightness.
LOOKS = {
    "mid": {i: {"hue": 0.98, "sat": 0.62, "val": 1.2} for i in (4, 6, 7, 8)},
}


def read_tga(path):
    data = open(path, "rb").read()
    id_len, kind = data[0], data[2]
    width, height = struct.unpack("<HH", data[12:16])
    bpp, desc = data[16], data[17]
    size = bpp // 8
    pos = 18 + id_len
    count = width * height
    if kind == 2:
        pixels = bytearray(data[pos:pos + count * size])
    elif kind == 10:
        pixels = bytearray(count * size)
        out, end = 0, count * size
        while out < end:
            head = data[pos]
            pos += 1
            n = (head & 0x7F) + 1
            if head & 0x80:
                pixels[out:out + n * size] = data[pos:pos + size] * n
                pos += size
            else:
                pixels[out:out + n * size] = data[pos:pos + n * size]
                pos += n * size
            out += n * size
    else:
        raise ValueError("unsupported tga type %d in %s" % (kind, path))
    return width, height, size, desc, pixels


def write_tga(path, width, height, size, desc, pixels):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, size * 8, desc)
    with open(path, "wb") as f:
        f.write(header)
        f.write(pixels)


def mean_hue(pixels, size):
    sx = sy = 0.0
    for i in range(0, len(pixels), size * 97):
        b, g, r = pixels[i], pixels[i + 1], pixels[i + 2]
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        sx += math.cos(h * 2 * math.pi) * s * v
        sy += math.sin(h * 2 * math.pi) * s * v
    return (math.atan2(sy, sx) / (2 * math.pi)) % 1.0


def recolour(pixels, size, rule):
    shift = rule["hue"] - mean_hue(pixels, size) if "hue" in rule else None
    sat, val = rule.get("sat", 1.0), rule.get("val", 1.0)
    cache = {}
    for i in range(0, len(pixels), size):
        key = (pixels[i], pixels[i + 1], pixels[i + 2])
        out = cache.get(key)
        if out is None:
            b, g, r = key
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if shift is not None:
                h = (h + shift) % 1.0
            r2, g2, b2 = colorsys.hsv_to_rgb(h, min(s * sat, 1.0), min(v * val, 1.0))
            out = (int(b2 * 255 + 0.5), int(g2 * 255 + 0.5), int(r2 * 255 + 0.5))
            cache[key] = out
        pixels[i], pixels[i + 1], pixels[i + 2] = out


def main():
    textures_dir = os.path.join(HERE, "Textures", "Ground")
    materials_dir = os.path.join(HERE, "Materials")
    os.makedirs(textures_dir, exist_ok=True)
    os.makedirs(materials_dir, exist_ok=True)
    for look, rules in LOOKS.items():
        matset = json.load(open(STANDARD_SET))
        textures = matset["groundMaterials"]["textures"]
        for index, rule in rules.items():
            source = os.path.basename(textures[index]["diffuse"])
            name = "zone_%s_%s" % (look, source)
            width, height, size, desc, pixels = read_tga(os.path.join(GROUND, source))
            recolour(pixels, size, rule)
            write_tga(os.path.join(textures_dir, name), width, height, size, desc, pixels)
            textures[index]["diffuse"] = "$CONTENT_DATA/Terrain/Textures/Ground/" + name
            print(look, textures[index]["name"], "->", name)
        with open(os.path.join(materials_dir, "zone_%s.json" % look), "w") as f:
            json.dump(matset, f, indent="\t")


if __name__ == "__main__":
    main()
