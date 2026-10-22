# Story and quests

Code: `Scripts/Story.lua` (all the logic), `Scripts/StoryQuests.lua` (HUD
display), quest registration in `Game.lua` (`QUESTS`), quest objects in
`ScriptableObjects/ScriptableObjectSets/example.sobset`.

## The main quest chain

`STORY_QUESTS` in Story.lua, in order. `saved.story.chapter` is the index of the
current one.

| # | Quest | Done when |
|---|---|---|
| 1 | Getting Started | The battery is in the garage socket (`saved.garagePowered`) |
| 2 | Into the Zone | You've escaped through a gateway once (`story.escaped`) |
| 3 | The Outer Zone | Escaped at depth ≥ the Outer tier's last junction (3) |
| 4 | Raise the Antenna | The level 1 antenna is built on the garage's builder pad (`story.antennaBuilt`): Route Planner scans per trip go from 1 to 3 (`ScannerCharges`) |
| 5 | Distress Call | Once the antenna is up the farmers phone for help; the quest and the hideout on the map only appear when the call is over (`story.callsDone`, `g_hiddenLandmarks`). Done: reached the Farmers' Hideout landmark (depth 2) **and** talked to the farmer there (`story.talks.HideoutTalk`, once his conversation is over); he offers a key to the Mid Zone for food, and Roadside Picnic follows |
| 6 | Roadside Picnic | 3 crates delivered through the hideout's vacuum (`story.cratesDelivered`), then talk to the farmer (`HideoutKey`): he holds out the key to the Mid Zone (Survival's keycard, renamed); taking it (`story.midKeyTaken`, `sv_takeMidKey`) finishes it → **Mid Zone unlocks** |
| 7 | The Mid Zone | Escaped at depth ≥ 6 → **Deep Zone unlocks** |
| 8 | Boost the Signal | The old antenna comes down when it starts (`story.antennaBroken`: back to 1 scan) and the level 2 antenna is built on the same pad (`story.antenna2Built`): 5 scans per trip |
| 9 | The Deep Zone | Escaped at depth ≥ 9. The end; the Deep Zone goes on forever |

**Tiers** (`ZONE_TIERS` in layouts.lua): Outer = depth 1–3, Mid 4–6, Deep 7–9+.
`UnlockedTiers(chapter)` = 1 + number of finished quests marked `unlocks = true`
(Roadside Picnic, The Mid Zone).
`g_storyMaxDepth` = the last depth of the last unlocked tier. Junctions at that
depth have locked exits (`JunctionExitsOpen`), which is what stops you going
deeper before the story allows.

## How progress is checked

- `Game.sv_storyAdvance( quiet )` loops: while the current chapter's goal is
  met, show "Quest completed", move to the next chapter. It's called when
  something relevant happens:
  - `sv_storyOnEscape` (from `sv_endRun`), which records `story.deepest`
  - `sv_e_garagePowered` (GarageWorld saw the socket turn on)
  - `sv_e_craftbotMade` (`StoryCraftbotQuest` hears Survival's dispenser event)
  - `sv_storyOnLandmark` (from `sv_jmArrive`)
  - `sv_e_crateDelivered` (the hideout's vacuum took a crate; see the hideout
    shop in [zones.md](zones.md))
  - `sv_e_anchorsBanked` (GarageWorld banked anchors into the Fabricator; a Gearing Up step)
  - every second while on Gearing Up / Craftbot Online
- `Game.sv_storyUpdate` (every tick) keeps the current quest active in
  Survival's QuestManager and publishes the tracker lines.

**Save migrations**: `sv_storyState` has `STORY_VERSION` (10). When a quest is
added in the middle, old saves' `chapter` numbers are shifted so they don't
land on the wrong quest. If you add or reorder quests, bump the version and
add a migration step there.

## How quest text reaches the HUD

Survival's quest tracker shows quest objects (scriptable objects). Ours don't
think for themselves:

1. The game works out the lines (`sv_storySteps`) and stores them in the
   global `g_storyTracker` (main quest) or `g_questTrackers[name]` (side quests).
2. The quest object (`StoryQuests.lua`, one class per quest wrapping
   `StoryQuest`) reads that global and shows it.

The lines are laid out like Survival's quests: a line of context first (`Desc`:
`{ name, text, desc = true }`, sent without `complete`, so the tracker shows it
with no checkbox, like Survival's `*_desc` steps), then a short checklist
(`Step`: `{ name, text, complete }`). Names are yellow (`Name`, `#FFFFC0`),
and counters go in front the way Survival does them (`Count`: "2/3 Crates
delivered"). Into the Zone goes in three parts: getting ready in the garage
(just a line pointing to the Expedition Checklist, which has those steps),
powering the ARC Device (anchors found, put them in), and getting out (switch
it on, drive into the gateway). The zone parts follow the
live run, so after a failed run it goes back to getting ready.

## Adding a quest

1. Add a ScriptableObject entry in `example.sobset` (new uuid, script
   `StoryQuests.lua`, a class name).
2. Add a class in `StoryQuests.lua` (copy an existing one).
3. Add it to `QUESTS` in `Game.lua` (same uuid; `mainQuest = true` for the chain).
4. Add it to `STORY_QUESTS` with a flag for its goal, handle that flag in
   `sv_storyAdvance` and `sv_storySteps`, and bump `STORY_VERSION` with a migration.

## Side quests

- **Expedition Checklist** (`sv_checklistUpdate`): active in the garage once
  it's powered, between trips. Steps: ARC Device on a vehicle (a dynamic
  creation with more than one shape), wired to a button or switch, destination
  set, go into the zone. Completed when you depart.
- **Junction Conditions** (`quest_zone_conditions`): only during a run, shows
  `g_zoneConditionsText` ("JCT 3: Fields" + conditions).
- `quest_zone_run` and `quest_zone_anchors` are retired but stay registered so
  old saves don't break.

## Cheats

| Command | What |
|---|---|
| `/skipquest [n]` | Mark the current main quest (or n in a row) done. Getting Started also powers the garage |

## Phone calls (`Dialogs.lua`)

Like Survival's mysterious caller: Survival's `DialogManager` (one of its
managers, running in our game too) plays the call, with the caller portrait
and text bubbles. A quest with `call = "<entry>"` rings once you've been home
in the garage, powered, for `CALL_DELAY_SECONDS`; `story.calls[entry]` keeps it
from ringing twice. The quest itself (and its landmark, see
`sv_storyLandmarksHidden` / `g_hiddenLandmarks`, which `JunctionMap.lua` keeps
off the map) only shows once the call has left Survival's dialog queue
(`story.callsDone`).

- The lines live in `Gui/Language/English/Dialog/PacificDialogs.json`, in
  Survival's dialog format (`list` → `uuid`, `speaker`, `entries` → `name`,
  `audio`, `lines` with `duration` and `text`). Edit the text there.
- Survival's dialog manager only loads its own files, so every client copies
  ours into `g_dialogManagerSelf.cl.dialogSet` every tick (`cl_dialogsEnsure`;
  a language change empties it). It must be there before a call plays, or
  the manager errors.
- Survival only voices lines that have a recorded clip. Ours have none, so
  `cl_dialogsUpdate` plays the entry's `audio` effect (`Farmerbuilder - Talk`,
  the builder farmers' mumble) at each new bubble. The game script has no
  world, so it can't play positioned effects (and the mumble is a 3D sound:
  unpositioned it's silent): it sets `g_pacificDialogBubble`, and the world the
  local player is in plays it at their character (`PlayDialogBubble` in
  DriveWorld.lua).

## The antenna builder quests (Raise the Antenna, Boost the Signal)

Survival's builder quests (Hubert's watchtower) use a builder pad that shows a
ghost blueprint to build piece by piece (`sm.builderGuide`). The garage tile has
survival's watchtower pad (`BuilderQuest_Platform_Watchtower_01.blueprint`,
placed in the Tile Editor beside the mechanic station). `survival_patches.lua`
swaps four of `BuilderGuidePlatform`'s functions so *that* pad (by its shape
uuid, `ANTENNA_PAD_UUID`) uses the guide of whichever antenna quest is active
(`ANTENNA_GUIDES`). Finished: the pad is replaced by the guide blueprint,
locked, with `antennaLevel` in the pad's params, and the game hears
`sv_e_antennaBuilt { level }`.

- When Boost the Signal is active and an older antenna stands on the pad, it
  comes down: an explosion effect, a bare pad (`antenna_pad.json`) imported in
  its place and the old creation destroyed (`sv_e_antennaTornDown`). Then the
  level 2 guide builds on the new pad.
- It's built in stages like Survival's builder quests: the builder guide takes
  a part's colour as its stage, in paint-palette order (that's how Survival's
  guides are coloured). `make_antenna.py` cuts each antenna into 2 m bands of
  height (`STAGE_HEIGHT`), lowest first, one palette colour each, and writes the
  real colours to `antenna_lvN_complete.json`, which goes on the pad when it's
  done (`ANTENNA_COMPLETES`). The rusted metal blocks are swapped for scrap
  metal (level 1) and plain metal (level 2).
- The info panel beside the pad (survival's `BuilderGuideInfoPanel`) lists the
  parts still needed. Survival's panel only knows Hubert's quest, so the one
  within `ANTENNA_PANEL_RANGE` of the pad (`g_antennaPadShape`, noted by the
  pad on clients) shows the active antenna guide instead.
- When an antenna quest starts, every part in its guide gets its schematic
  unlocked (`RecipeManager.Sv_UnlockRecipe`, once: `story.antennaRecipes`).
- The guides come from the owner's blueprints: `BuilderGuides/make_antenna.py`
  shifts them onto the pad (feet at z 3, centred on the plate) and puts the
  pad's two parts first. Level 1 is `Blueprints/antenna_lvl2.blueprint` (the
  small one) and level 2 `Blueprints/antenna_lv1.blueprint` (the tall one): the
  file names are the other way round.
- Scans per trip: `ScannerCharges()` = `SCANNER_CHARGES` (1) +
  `ANTENNA_EXTRA_CHARGES` (2) × `g_antennaLevel` (`AntennaLevel(story)`).
- Any other builder pad would still behave like survival's.

## The hideout farmer (`HideoutFarmer.lua`)

A character of our own (`Characters/Database/CharacterSets/example.characterset`)
built on Survival's builder farmer: his look, greeting, eyes following you and
talk animations come from `GenericBuilderQuestCharacter` / `GenericBuilderQuestUnit`,
minus their builder quest. `ZoneWorld.sv_keepHideoutFarmer` puts him at
`HIDEOUT_FARMER_SPOT` (picked in game with /where) whenever someone's there and
he isn't, and points the hideout's marker at him. Finding him: each farmer's
unit adds itself to `g_hideoutFarmers` when it starts (listing the world's units
by character type never found him); extras, or one away from his spot, are
removed. The world's save remembers it placed him (`farmerPlaced`), so it never
places a second one even if he can't be found. Talking to him sends `sv_e_hideoutFarmerTalk`
(Story.lua), which plays an in-person dialog (`DIALOG_HIDEOUT` in
PacificDialogs.json): `HideoutTalk` on Distress Call (the offer; `quest.talk`),
`HideoutReminder` on Roadside Picnic before the crates are in, `HideoutKey` once they are, `HideoutThanks` after. After `HideoutKey` he holds the key out like Hubert does (`g_hideoutKeyReady` → the world → `sv_e_setGive`: Survival's `Questeffects - Quest_lootitem` with the key in his right hand, his reward gesture); Use then takes it. `self.sv.talking`
watches Survival's dialog queue and marks the talk done when it's over.

## Retired quests

Gearing Up and Craftbot Online were taken out of the chain (`RETIRED_QUESTS`:
dropped from saves that still have them; `STORY_VERSION` 10 moves the chapter).
