# Storm, conditions, ARC Device and the way home

Code: `Scripts/Game.lua` (sections "Zone collapse", "Gateway", "Return"),
`Scripts/ArcDevice.lua`, `Scripts/conditions.lua`, visuals in
`Scripts/DriveWorld.lua` (`ZoneWorld`).

## The collapse timer

When you arrive in a zone (`Game.sv_finishDeparture`):

- **Perpetual Stability** (the `stable` condition): no timer. Only opening a gateway starts a storm.
  Until your first escape every zone gets this (see `CreateZone`).
- Otherwise `run.collapseTick` = now + calm time, where the calm time is:
  - the Route Planner's stability, converted by `StabilityToSeconds`; or, if there isn't one,
  - `STORM_STABLE_TIME` × a depth factor (`STORM_DEPTH_TIME_STEP` less per
    junction, down to `STORM_DEPTH_MIN_FACTOR`);
  - ± `STORM_TIME_VARIATION`, halved by **Elevated Instability**.
- `run.warnTick`: an alarm about `STORM_WARNING_TIME` before (no text, just
  the alarm sound, `ZoneWorld.sv_e_alarm`).

`Game.sv_updateStorm` (every tick while in the zone) checks the timer. When it
runs out the storm starts centred on the gateway (or the middle of the zone if
there isn't one), starting at the farthest corner so it covers everything.

## The storm wall

```lua
run.storm = { center, r0, speed, startTick, minRadius }
StormRadius( storm, tick ) = max( minRadius, r0 - speed * secondsSinceStart )
```

It's a circle shrinking at a constant speed toward its centre, all the way
(`STORM_MIN_RADIUS` 0): once it's closed in (under 2 m) the wall disappears and
the storm is everywhere. Speed comes
from `Game.sv_stormSpeed( base )`:
`base × (1 + STORM_DEPTH_SPEED_STEP × level)`, where level is the junction's
storm meter (or depth − 1), × `CONDITION_RAPID_SPEED_FACTOR` with Rapid Collapse.

| When | Base speed | Starts at |
|---|---|---|
| Timer runs out | `STORM_SPEED` (5 m/s) | farthest zone corner |
| Gateway opens | `STORM_GATEWAY_SPEED` (8 m/s) | farthest player + `STORM_GATEWAY_START_MARGIN` (80 m) |

If the storm was already running when the gateway opens, it re-centres on the
gateway at its current radius (at least 20 m beyond the farthest player).

Outside the wall, once a second (`sv_stormDamage`): `STORM_DAMAGE_PER_SECOND`
damage (as "scannerbot" damage, which doesn't throw you out of your seat), and
seeker missile volleys every `STORM_MISSILE_INTERVAL` s after a 2 s grace
(`sv_fireMissiles` creates Survival's missile scriptable object, no bot needed).

The game sends the storm to the zone (`sv_e_setStorm`); every client draws it:

- **Wall**: rings of flat glowing panels (`CreateRing` / `UpdateRing`), 48
  around × 6 rows. Panels far from the camera are pulled in and shrunk
  (`PANEL_DRAW_LIMIT`) because the game stops drawing past about 1 km.
- **Red screen** when you're outside (`cl_setStormScreen`, the seeker bot's red screen).
- Dark sky lighting (`STORM_DARK_SKY`), countdown HUD, tier storm music.

### Damage by tier

Outside the wall you take `ZONE_TIERS[*].stormDamage` a second (Outer 1, Mid 3,
Deep 5; `COLLAPSED_DAMAGE` in a collapsed zone).

### Missiles by tier

`ZONE_TIERS[*].missiles = { miss, volley, interval }`. The missile (Survival's
`Missile.lua`) aims `targetOffset` metres from you and its blast reaches 2 m,
so the Outer Zone's (5-9 m) always miss, the Mid Zone's (1.5-4 m) sometimes
hit and the Deep Zone's (0-1.5 m) hit.

### Supply pods

While a storm is on, `Game.sv_updateStorm` drops a pod every `POD_INTERVAL`
seconds (first after `POD_FIRST_DELAY`) somewhere `POD_DISTANCE` from a random
player (`sv_dropPod` -> `ZoneWorld.sv_e_dropPod`). The pod (`SupplyPod.lua`,
the Friendly Dumpster's chest model) is created `POD_DROP_HEIGHT` up and pushed
down; it trails the missile's smoke while falling, explodes (just the effect)
on landing, is replaced by an upright static copy on the ground
(`ZoneWorld.sv_e_placePod`), and a smoke column marks it until it's opened. Its chest is filled from `POD_LOOT` by the zone's tier (read from
`world.publicData.depth` / `collapsed`) when it's down; E opens a chest window.
`/supplypod` drops one.

## Conditions

`Scripts/conditions.lua`. Each junction rolls 0–4 (`ZONE_CONDITION_COUNTS` by
depth) from `ZONE_CONDITIONS`, by weight, respecting `minDepth` and `excludes`.
The effects live where they apply. Search for `HasCondition(` to find them:

| Condition | Where it acts |
|---|---|
| stable / unstable / rapid | `sv_finishDeparture`, `sv_stormSpeed` (Game.lua) |
| daylight / nightfall | `sv_updateStorm` holds the clock |
| rain / thunderstorm / acidRain | `sv_setZoneWeather` (Survival's WeatherManager); acid damage in `sv_updateStorm` |
| minefield | `ZoneWorld.sv_spawnMines` (red totebots per cell) |
| tornadoes | `ZoneTornadoes.lua` |
| anchorSurge / anchorDrought | anchor count in `RollJunction` / `CreateZone` |
| fog | zone render settings |

## The ARC Device

`Scripts/ArcDevice.lua`, a part you build onto your car.

1. **Insert anchors**: carry an energy anchor (Survival's carry system, like
   the battery) and click the device. The click hook is in
   `survival_patches.lua` (`PatchedTryInsert`). Anchors sit in its container.
2. **Activate**: wire a button or switch to it. When its parent turns on,
   `sv_activate` checks it holds at least the **gateway cost** (`GatewayCost(depth)`
   = `JUNCTION_COST_BASE + (depth−1) × JUNCTION_COST_STEP`).
3. It asks the game (`sv_e_arcRequestCharge`). `Game.sv_whyNoGateway` refuses
   if you're not in the zone, a gateway is already open, or the junction has no
   stable exits. The reason is shown next to the device.
4. If allowed, it charges for `ARC_CHARGE_SECONDS`, then blasts:
   `sv_e_arcOpenGateway` → `Game.sv_spawnGateway`. The anchors are **not** used up (as in Pacific Drive): they're banked at home (see [garage.md](garage.md)).

It also publishes `g_arcDevices` (on a vehicle? wired?) and `g_arcAnchorCounts`
for the quests.

## Opening the gateway

`Game.sv_spawnGateway( player, near, origin )`:

1. Tries 60 random spots `GATEWAY_MIN_DISTANCE`–`GATEWAY_MAX_DISTANCE` from the
   device, keeps the one farthest from the nearest player, avoids liquid cells,
   stays inside the zone edge and inside the storm if one is running.
   (`/gateway here` puts it 50 m ahead instead.)
2. `run.gateway = { x, y }`, then loads that cell with a handle
   (`sv_loadGatewayCell`). It stays loaded for the whole run.
3. Once loaded, `ZoneWorld.sv_e_spawnGateway` finds the ground, creates a tall
   **gateway trigger**, tells clients to draw the beam and marker.
4. `Game.sv_e_onGatewaySpawned` creates a placeholder return portal.
5. Starts the storm (above).

## Driving through: the return

This is the trickiest code in the mod, because a moving car must arrive whole,
in the right direction, keeping its speed.

1. `ZoneWorld.trigger_onGateway`: a player enters the gateway trigger →
   `Game.sv_e_onGatewayReached`.
2. It collects **what goes home**: every player within `RETURN_GATHER_RADIUS`
   of the gateway, and for each the **whole creation** they sit in
   (`getLockingInteractable` → `getCreationBodies`; a car is several bodies,
   and missing one splits it).
3. It measures them: the combined bounding box, and the average velocity.
4. It builds a **new return portal**:
   - box = that bounding box, stretched ahead by how far it will move in the
     12-tick delay (`lead`);
   - opening A rotated to face the direction of travel, opening B rotated to
     face down the garage road (`FacingRotation(exitDir)`), so you come out
     driving the right way;
   - B's height = garage exit floor + (box centre − box bottom) + 0.6 m, so the
     car's bottom lands just above the floor.
5. `RETURN_DELAY_TICKS` (12) later, `sv_finishReturn` transfers. A new portal
   needs a few ticks before it carries anything (see [gotchas.md](gotchas.md)).
6. 2 ticks after: if it was moving, `GarageWorld.sv_e_launchBodies` sets its
   velocity along the garage road at the same speed (capped at
   `RETURN_MAX_SPEED`); otherwise it's stopped. A teleport sound plays.
7. Failsafes:
   - `sv_rescueLeftBehind` (40 ticks later): any player still in the zone gets
     their own little portal home;
   - `GarageWorld.sv_e_rescueBelowFloor` (16 ticks later): anything more than
     1.5 m below the exit floor is lifted out, one portal per creation (several
     portals on the same thing duplicates it).
8. `sv_endRun()`: run over, trips + 1 (refills the dumpster and fuel pump),
   story counts the escape, `sv_jmReturnHome( true )` unlocks this junction's exits.

## When the run fails

`sv_updateStorm` checks every second: if every player has a character and none
are in the zone (everyone died and respawned, or used `/home`), the run ends
with `sv_endRun( true )`:

- `Game.sv_recoverVehicles`: the zone loads cells around each player's last
  position and car (`ZoneWorld.sv_trackSpots` remembers them), waits 2 s,
  finds every creation there (`sv_stepRecover`, which includes the loot bag of
  dropped items) and sends them to `Game.sv_e_recoverFound`, which portals them
  to the garage exit side by side (`RECOVER_SPACING`). No message: like Pacific
  Drive, your car just turns up at home.
  - The car spot follows the last car each player drove (`self.sv.lastCars`,
    not saved) while it's loaded, driver in it or not: a car carried off by a
    tornado after its driver was thrown out was once left behind.
  - With no car found it looks again every 2 s, up to 6 times: in a big save
    the cells load back in slowly ("save was paused for too long" in the log),
    and a player's tow once found only one stray body of a 20-body car.
  - Each tow portal waits until it has something in it (`Game.sv_towTransfer`,
    every second, up to 8 s): another player's tow found all 7 creations but
    moved nothing, seven empty portals, as they hadn't loaded in yet. The
    portals go one after another, so something inside two of the boxes only
    moves once (it was in two at once in a log: a copy risk).
  - Survival's lost-items marker isn't tied to a world: it shows the spot in
    whatever zone you're in, though the bag is in the zone you died in.
- No junction is unlocked.

## Resuming a saved run

The run (`gateway`, `collapseTick`, `storm`, `warned`) is saved in
`saved.run` (`sv_saveRun`). On load, `Game.server_onCreate` sets
`resumePending`; once the zone's script reports `sv_e_zoneReady`,
`sv_resumeRun` resends the gateway, storm, timer and weather (with a 10 s
fallback). Sending them earlier gets them lost (see [gotchas.md](gotchas.md)).
