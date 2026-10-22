"""Builder guides for the garage antenna (Raise the Antenna, Boost the Signal).

Writes, from the owner's blueprints in Blueprints/:
  antenna_lv1_guide.json     level 1 (Blueprints/antenna_lvl2.blueprint, the small one)
  antenna_lv1_complete.json  the same, finished (its real colours)
  antenna_lv2_guide.json     level 2 (Blueprints/antenna_lv1.blueprint, the tall one)
  antenna_lv2_complete.json  the same, finished
  antenna_pad.json           just the pad (put back when the old antenna comes down)
(The blueprint files' names are the other way round from their levels.)

A guide is the antenna standing on survival's builder quest pad (the watchtower
platform placed in Terrain/Tiles/garage.tile). The game shows it as a ghost on
the pad to build piece by piece, in stages like survival's builder quests, and
swaps the pad for the finished one, locked, once it's done (survival_patches.lua).

Stages: the builder guide takes a part's colour as its stage, in the order of
the paint tool's palette (survival's guides are coloured that way; the real
colours are in a separate finished blueprint). So the guide is the antenna cut
into bands of height (STAGE_HEIGHT), lowest first, each band one palette colour.

Positions are in blocks (0.25 m) from the pad's own part; the pad's 6x6 plate
is z 1-2, so the antenna's feet go at z 3, in the middle of the plate. Both
antennas were built in the same spot, so one shift fits both.

    python BuilderGuides/make_antenna.py
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
BLUEPRINTS = os.path.join(HERE, "..", "Blueprints")

# The pad itself, exactly as in survival's watchtower guide
PAD = [
    {"color": "CA372D", "controller": {"active": False, "controllers": None, "data": "gExVQQAAAAEFBQDwAQIAAAAEAGNvbXBsZXRlAgA", "id": 114, "joints": None},
     "pos": {"x": 0, "y": 0, "z": 0}, "shapeId": "c3065683-98ff-4ef6-9862-ed0443ec71c2", "xaxis": 1, "zaxis": 3},
    {"color": "5196D6", "pos": {"x": -11, "y": 13, "z": 1}, "shapeId": "5627aa08-8bc4-4cf3-a6b6-101ae59e6fc6", "xaxis": 1, "zaxis": -2},
]
PAD_IDS = {p["shapeId"] for p in PAD}

# The blueprints' rusted metal blocks become an easier block: scrap metal for
# level 1, plain metal for level 2
RUSTED_METAL = "220b201e-aa40-4995-96c8-e6007af160de"  # blk_metalbricks, "Rusted Metal Block"
SCRAP_METAL = "1f7ac0bb-ad45-4246-9817-59bdf7f7ab39"   # blk_scrapmetal
METAL = "8aedf6c2-94e1-4506-89d4-a0227c552f1e"         # blk_metal1, "Metal Block Level 1"

# Stages: bands of this many blocks (2 m), each one colour of the paint palette in order
STAGE_HEIGHT = 8
PALETTE = [
    "EEEEEE", "F5F071", "CBF66F", "68FF88", "7EEDED", "4C6FE3", "AE79F0", "EE7BF0", "F06767", "EEAF5C",
    "7F7F7F", "E2DB13", "A0EA00", "19E753", "2CE6E6", "0A3EE2", "7514ED", "CF11D2", "D02525", "DF7F00",
    "4A4A4A", "817C00", "577D07", "0E8031", "118787", "0F2E91", "500AA6", "720A74", "7C0000", "673B00",
    "222222", "323000", "375000", "064023", "0A4444", "0A1D5A", "35086C", "520653", "560202", "472800",
]

# Where the antennas were built (the middle of their four legs) -> the middle of the plate
SHIFT_X, SHIFT_Y = 6, 26
FEET_Z = 3


def write(name, parts):
    blueprint = {"bodies": [{"childs": PAD + parts, "type": 1}], "joints": None,
                 "multiShapes": [{"childs": [0, 1], "root": 0}], "version": 4}
    json.dump(blueprint, open(os.path.join(HERE, name), "w"), indent=1)


def guide_from(blueprint_name, out_name, metal_block):
    data = json.load(open(os.path.join(BLUEPRINTS, blueprint_name), encoding="utf-8"))
    parts = [child for body in data["bodies"] for child in body["childs"] if child["shapeId"] not in PAD_IDS]
    for p in parts:
        if p["shapeId"] == RUSTED_METAL:
            p["shapeId"] = metal_block
    lowest = min(p["pos"]["z"] for p in parts)
    for p in parts:
        p["pos"] = {"x": p["pos"]["x"] + SHIFT_X, "y": p["pos"]["y"] + SHIFT_Y, "z": p["pos"]["z"] - lowest + FEET_Z}
    # The finished antenna, its own colours
    write(out_name.replace("_guide", "_complete"), parts)
    # The guide: one palette colour per band of height (empty bands skipped)
    bands = sorted({(p["pos"]["z"] - FEET_Z) // STAGE_HEIGHT for p in parts})
    assert len(bands) <= len(PALETTE), "too many stages"
    stage_of = {band: i for i, band in enumerate(bands)}
    staged = []
    for p in parts:
        q = dict(p)
        q["color"] = PALETTE[stage_of[(p["pos"]["z"] - FEET_Z) // STAGE_HEIGHT]]
        staged.append(q)
    write(out_name, staged)
    print("wrote %s: %d pieces in %d stages, from %s" % (out_name, len(parts), len(bands), blueprint_name))


guide_from("antenna_lvl2.blueprint", "antenna_lv1_guide.json", SCRAP_METAL)
guide_from("antenna_lv1.blueprint", "antenna_lv2_guide.json", METAL)
json.dump({"bodies": [{"childs": PAD, "type": 1}], "joints": None,
           "multiShapes": [{"childs": [0, 1], "root": 0}], "version": 4},
          open(os.path.join(HERE, "antenna_pad.json"), "w"), indent=1)
print("wrote antenna_pad.json")
