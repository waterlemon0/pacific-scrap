# Engine gotchas

Things Scrap Mechanic does that aren't obvious, which we found the hard way.
Read this before changing world, portal or save code.

## Worlds and saves

- **World creation data over 64KB corrupts the save.** The game stores it with
  a 16-bit length, so it gets cut off, and loading that save eats memory until
  the PC freezes. A zone's plain tile list is about 66KB, so tiles are packed
  (`tilepack.lua`) into a few KB. Keep anything passed to `sm.world.createWorld`
  small. Don't make the zone much bigger than about 56×56 cells.
- **Worlds can't be unloaded.** A world you've left stays in memory until the
  save is reloaded.
- **Don't `world:destroy()` a zone.** It leaves its contents in the save
  file, and loading a save with those leftovers hangs. We **retire** zones
  instead (stop their scripts and effects, never load them again). See [zones.md](zones.md).
- **Wiping a world doesn't shrink the save.** Removed trees and harvestables
  leave "removed" records. So we don't wipe; each zone world you've driven
  through costs about 2 MB (measured), and the zone pool keeps their number
  fixed ([zones.md](zones.md#the-zone-pool)).
- **A reused world never runs `server_onCellCreated` again** for cells that
  loaded before. Anything that must happen every visit goes in
  `server_onCellLoaded` too (`ZoneWorld.sv_tripCell`).
- Landmark worlds are created once and reused for the same reason.

## Events between scripts

- `sm.event.sendToWorld` to a world whose script isn't running yet is
  **silently lost**. On load the game script starts before the worlds. So a
  world says when it's ready (`sv_e_zoneReady`, `sv_e_garageReady`) and the
  game sends then. Resuming a run relies on this.
- The **game script can't create parts or effects** (they need a world). It
  asks a world script (`sv_e_placePart`). The map window has no click sounds for
  the same reason.
- **Tools can't use the game's network.** The logbook patch sets a global
  (`g_pacificMapRequest`) and `Game.client_onUpdate` acts on it.
- Server scripts share one Lua state, so globals work across the game, worlds
  and parts on the server (clients have their own state).

## Portals

- A new portal, or one whose openings just moved, needs **a few ticks** before
  `transferAToB()` carries anything. Always delay the transfer (we use 3–12 ticks).
- An opening can't be moved once set; make a fresh portal instead.
- Moving the **same thing through several portals at once duplicates it**
  (we got a second copy of the player). One portal per creation.
- A car is several bodies (bearings, suspension). Collect them all with
  `body:getCreationBodies()` or it arrives in pieces.
- The opening's rotation turns what comes through: we use `FacingRotation(dir)`
  on both ends so a car comes out facing down the garage road.
- Keep the destination cell loaded (`loadCellWithHandle`) or there's nothing to land on.

## Triggers

- `bindOnStay` fires every tick while someone's inside, so throttle it (we
  ignore repeats for 20–40 ticks).
- Junction and pad triggers are thin and very tall so ground height and roofs
  don't matter.

## Scripting sandbox

- `setmetatable` isn't allowed.
- `dofile` only works at the top level of a script, not inside functions.
- GUI paths can't use `$CONTENT_DATA`. Use `$CONTENT_3c9f5e62-8d1a-4b7e-9a35-6f2d0c4e8b71`
  (the mod's localId from `description.json`).
- Lua `local`s must be defined above where they're used. A function referring
  to a local defined further down the file gets nil.
- Survival's `RecipeManager.Sv_IsUnlocked` wants item ids as **strings**.
- Crafters show their recipes **straight from the recipe file** (`addGridItemsFromFile`),
  so changing a recipe in `g_craftingRecipeSets` alone shows the old one. Ship a
  changed copy of the file and load it instead (`Game.loadCraftingRecipes`).
- `survival_patches.lua` is also loaded by the world scripts, and
  `ApplySurvivalPatches()` runs as it loads. When a save loads, world scripts
  load early, and calling game functions then (we hit it with
  `sm.game.getRecipesEnabled()`) **crashes the game**. A new game doesn't show
  it. Only swap functions in patch code; call game functions inside the swapped
  functions, when they're used.
- Survival keeps some tables in locals, so to change behaviour we swap whole
  functions for patched copies (`survival_patches.lua`), re-applied every
  second in case Survival reloads its classes.

## Survival quirks we work around

- Survival only applies a world's own render settings indoors; the zone is
  outdoor, so `survival_patches.lua` layers our fog on top.
- Survival's weather effects are created in one "weatherworld"; we move it to
  whichever world you're in.
- The hideout traders normally need the "Feed the Farmers" quest. Patched to
  always trade. Raids are off (`g_disableRaids`).
- `/unlimited` (cheat inventory) completes Survival's crafting quests
  instantly, so Craftbot Online listens for the dispenser event instead.

- **Radios go silent under the zone music.** The zone tiers use Survival's
  warehouse music (`ZONE_TIERS` music / stormMusic), and radios stop playing
  once it starts; putting the radio down again brings it back. Restarting
  Survival's radio transmitter (`g_radioTransmitter`) when the music changes
  didn't help (tried, reverted). Other zone music might not do it.

## Recolouring Survival's tiles (tried, reverted)

- Grass blades (clutter) have one global set of textures; a mod can't recolour
  them per world, only swap grass types (and the numbering isn't the
  `clutter.json` order).
- Changing a tree's or rock's colour as tiles load is ignored; recoloured
  *copies* (own harvestables/assets with new uuids) swapped in do work.
- Per-world ground textures work (a ground material set per world class).
- Ground paint (`GetColorAt`) doesn't show on the grass ground textures, only on
  some others (hay). Grass blades take neither; swap clutter types instead
  (numbers: Data's `clutter.json` list, then Survival's).

## Terrain script

- A tile creation's `pathOrJson` must be a blueprint **path**; blueprint JSON
  text fails ("Failed to load Cached Const Data") and nothing spawns.
- `sm.terrainTile.getHeightAt` (and the other world-position getters) need the
  lod argument: `GetTileLoadParamsFromWorldPos( x, y, 0 )`.

## Models (FBX from Blender)

- **Identical materials get merged.** If two materials in an FBX are identical
  (Blender's blank export materials all are), every submesh gets the *first*
  material's name, so the whole model is drawn with one `.rend` texture while
  its UVs point at others: scrambled textures in game, fine in Blender.
  `Tools/blender/sm_export.py` gives every material its own colour to avoid it.
- **"Pose" materials crash the game** on load ("LOD has:0 poses but material
  needs:1") unless the model has pose meshes. Copying a vanilla `.rend` entry
  such as the radar beacon's `PoseAnimDifAsgNor_Metal` needs the plain version
  (`DifAsgNor_Metal`); `sm_export` does that.
- To see what the game actually built from a mesh: `Cache/Mesh/*.mco` is a
  24-byte header and then an LZ4 block from byte 36; decompressed, it lists the
  submesh names.

## Testing

- After **any** change, scripts included, **delete everything in `Cache/`**
  (`Bundle`, `Data`, `Raw`, `Textures`, `Impostor`) before launching, or the game uses old copies: `Cache/Raw` keeps old scripts and `Cache/Textures` old textures, and neither notices the files changed.
- Keep a copy of your save before testing world changes.
