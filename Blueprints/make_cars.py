"""Makes copies of Survival's abandoned vehicles (the garage's random car,
Survival's random_abandoned_vehicle prefab) with the scrap engine's tank full
(10 canisters). The scrap wheels and engine stay: the real ones are the first
Vehicle unlocks at the Fabricator.
Scripts/terrain.lua swaps the garage car's blueprint path for these copies
(the game won't take a blueprint handed over as JSON text).

Run:  python Blueprints/make_cars.py   (then clear the mod's Cache folder)
"""
import glob
import json
import os

SRC = r"D:\steam\steamapps\common\Scrap Mechanic\Survival\LocalBlueprints\GameplayBlueprints"
HERE = os.path.dirname(os.path.abspath(__file__))
SCRAP_ENGINE = "c96ab903-f238-4bae-a614-28a758716d00"
GAS = "d4d68946-aa03-4b8f-b1af-96b81ad4e305"
GAS_IN_TANK = 10


def fix(part):
    if part.get("shapeId") == SCRAP_ENGINE:
        for container in (part.get("controller") or {}).get("containers") or []:
            for slot in container.get("container") or []:
                slot["uuid"] = GAS
                slot["quantity"] = GAS_IN_TANK


def main():
    for path in glob.glob(os.path.join(SRC, "Roadside_AbandonedVehicle_*.blueprint")):
        blueprint = json.load(open(path))
        for body in blueprint.get("bodies", []):
            for part in body.get("childs", []):
                fix(part)
        for joint in blueprint.get("joints", []) or []:
            fix(joint)
        json.dump(blueprint, open(os.path.join(HERE, os.path.basename(path)), "w"))
        print(os.path.basename(path))


if __name__ == "__main__":
    main()
