"""Item icons without running out of graphics memory.

The Mod Tool's icon generator builds the whole mod first, and Pacific Scrap
pulls in a large part of Survival (tiles, terrain, robots). On a 3 GB graphics
card it runs out of memory partway through, and the icons come out without
textures (and it takes about 20 minutes).

So the icons are made from a small local "Blocks and Parts" mod holding only
our parts: Mods/PacificScrap_Icons, next to this mod. It's never uploaded.

    python Tools/make_icon_mod.py          (1) make / refresh PacificScrap_Icons
    then open PacificScrap_Icons in the Mod Tool and click Create Icons
    python Tools/make_icon_mod.py collect  (2) copy its icons into Pacific Scrap

Icons are matched to items by uuid, so they work in Pacific Scrap as they are.
Clear Pacific Scrap's Cache folder afterwards.
"""
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
ICONS = os.path.join(os.path.dirname(MOD), "PacificScrap_Icons")
LOCAL_ID = "5b0e8f3a-6c2d-4e71-9a84-1d3f7c2b9e60"  # (its own id: not Pacific Scrap's)

# What the parts need: their shapes, models, scripts (the shapeset names
# them), and item names
COPY = ["Objects", "Scripts", os.path.join("Gui", "Language")]


def make():
    os.makedirs(ICONS, exist_ok=True)
    for rel in COPY:
        src, dst = os.path.join(MOD, rel), os.path.join(ICONS, rel)
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    # (no old cache: it would keep stale models)
    shutil.rmtree(os.path.join(ICONS, "Cache"), ignore_errors=True)
    with open(os.path.join(ICONS, "description.json"), "w", encoding="utf-8") as f:
        json.dump({
            "allow_add_mods": True,
            "custom_icons": False,
            "description": "Local helper for Pacific Scrap's item icons (Tools/make_icon_mod.py). Don't upload.",
            "localId": LOCAL_ID,
            "name": "Pacific Scrap Icons",
            "type": "Blocks and Parts",
            "version": 1,
        }, f, indent="\t")
    preview = os.path.join(MOD, "preview.jpg")
    if os.path.exists(preview):
        shutil.copy2(preview, os.path.join(ICONS, "preview.jpg"))
    print("Ready:", ICONS)
    print("Open 'Pacific Scrap Icons' in the Mod Tool, click Create Icons, then run:")
    print("    python Tools/make_icon_mod.py collect")


def collect():
    copied = 0
    for name in ("IconMap.png", "IconMap.xml"):
        src = os.path.join(ICONS, "Gui", name)
        if not os.path.exists(src):
            sys.exit("No " + name + " in " + os.path.join(ICONS, "Gui") + " yet: create the icons in the Mod Tool first.")
        shutil.copy2(src, os.path.join(MOD, "Gui", name))
        copied += 1
    print("Copied", copied, "icon files into Pacific Scrap's Gui folder. Clear its Cache folder before launching.")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "collect":
        collect()
    else:
        make()
