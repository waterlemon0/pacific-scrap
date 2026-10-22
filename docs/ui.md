# Menus: Fabricator, Route Planner / junction map, Logbook key

Code: `Scripts/Fabricator.lua` (upgrade tree), `Scripts/JunctionMap.lua`
(bottom half: the map window), `Scripts/wide_gui.lua` (full-width layout),
`Scripts/survival_patches.lua` (Logbook key), layout file
`Gui/JsonGuis/Fabricator.gui`.

Both menus are the same idea: Survival's Hideout trader menu, stretched across
the screen, with its item grid replaced by a **canvas we draw ourselves** that
you can drag and zoom.

## How Scrap Mechanic menus work

A "JSON GUI" is a tree of widgets written as JSON (or the same thing as a Lua
table): each widget has a `Name`, `Type` (`Widget`, `Button`, `ImageBox`,
`TextBox`, ...), a `Skin`, a position and size (`x`, `y`, `width`, `height`,
in a 1280×720 layout), and `Childs`. Callbacks are function names on the
script, e.g. `onClick = "cl_selectUpgrade"`, `onMouseWheel`, `onPressed`,
`onDrag`, `onReleased`, plus `onClickData` that is passed along.

```lua
local json = DeepCopy( dofile( "$CONTENT_DATA/Gui/JsonGuis/Fabricator.gui" ) ) -- the layout as a Lua table
local gui = sm.jsonGui.createGui( { handleKeySetup = "Hideout", name = "Hideout" } )
-- ...change json (captions, children, sizes)...
gui:render( json )                                                              -- show it
```

We don't keep widgets around and update them. Every time something changes we
**rebuild the parts of the table that changed and call `render` again** (like
redrawing a picture). Each script has a "dirty" flag: anything that changes
the view sets it, and the per-frame update re-renders once:

- Fabricator: `self.cl.dirty` → `Fabricator.client_onUpdate` → `cl_updateGui` → `render`
  (also every 0.5 s, to notice inventory changes)
- Map: `self.cl.jmDirty` → `Game.cl_jmUpdate` (called from `Game.client_onUpdate`) → `cl_jmBuild` → `render`

Helpers from Survival's `util.lua`: `FindWidget( json, name )` finds a widget
by name, `DeepCopy` copies a table, `removeFromArray`.

## The base layout: Fabricator.gui

`Gui/JsonGuis/Fabricator.gui` is a copy of Survival's Hideout / mining hub
trader menu. Its parts and what we use them for:

| Widget | Trader | Fabricator | Map |
|---|---|---|---|
| `MainPanel` | left panel | the tree | the map |
| `ItemContentPanel` | item grid | replaced by the tree canvas | replaced by the map canvas |
| `TabsHolder` (tabs `Wheels`, `Power`, ...) | categories | upgrade tabs | MAP / QUESTS / BEACONS (view mode only) |
| `Currency` | your coins | anchor bank, split into 3 kinds (`SplitCurrency`) | hidden |
| `TradePanel` | item details | selected upgrade + cost + Unlock | selected junction's info + buttons |
| `TradeButton` | Trade | Unlock | Scan / Set Destination / Travel |
| `Title`, `Preview`, `DescriptionBox` | item name, 3D preview, text | same | junction name, biome icon, info |

Text colour is set inline with `#RRGGBB` in a caption (e.g. `"#F42B2BRequires: ..."`).
Item icons come from `sm.gui.getItemIconFromUuid( uuid )` (see `SetIcon`).

## Full width (`wide_gui.lua`)

The trader menu is narrow. `WidenHideoutGui( json, main, grow, shift )` makes
it fill the screen:

- JSON GUIs are laid out for 1280×720 and scaled to the screen's height, so the
  screen is `720 × width / height` units wide (1280 on 16:9, more on ultrawide).
- It widens the root and the main panel by the spare room (minus a margin),
  makes the `grow` widgets wider by the same amount (the scroll background and
  the canvas panel) and moves the `shift` widgets right (the currency box).
- It remembers the original sizes, so it can be called **every time the menu
  opens** and adapts if the window was resized.

## The drag-and-zoom canvas

Both views use the same technique. The game has no "canvas" widget, no way to
read the mouse position, and the wheel callback doesn't say where the mouse
is, so it's built from plain widgets:

### Camera

The view has a **camera**: the point (in tree or map units) shown in the
middle, and a **zoom**. Every widget's screen position is computed from it:

```lua
screenX = viewW / 2 + ( worldX - cam.x ) * zoom
screenY = viewH / 2 + ( worldY - cam.y ) * zoom
```

| | Fabricator | Map |
|---|---|---|
| camera | `self.cl.treeCam` | `self.cl.jmCam` |
| zoom | `self.cl.treeZoom` (`TREE_ZOOM_MIN/MAX`) | `self.cl.jmZoom` (`MAP_ZOOM_MIN/MAX`) |
| built in | `Fabricator.cl_buildTree` | `Game.cl_jmBuild` |

The camera is clamped so the middle of the view stays on the tree or map
picture. Only widgets on screen are added (anything further out is skipped),
which keeps re-rendering cheap.

### Zooming toward the mouse

The canvas is covered by an invisible **grid of buttons** (24 × 12:
`TreeCell_x_y` / `MapCell_x_y`), drawn first so everything else is on top.
Each has `onMouseWheel`. When the wheel turns, the callback gets the **name of
the widget under the mouse**: its cell number tells us where the mouse is (to
within a cell). If it was over a node, the node's name (`Node12`,
`MapNode5`) gives its position instead.

Then the zoom keeps that point under the mouse:

```lua
-- the map point under the mouse, before
local mx = cam.x + ( sx - view.w / 2 ) / oldZoom
-- choose the new camera so the same point is under the mouse after
cam.x = mx - ( sx - view.w / 2 ) / newZoom
```

(`cl_treeWheel`, `cl_jmWheel`)

### Dragging

The same grid buttons (and the nodes) have `onPressed` / `onDrag` /
`onReleased`, which do get mouse coordinates:

- press: remember where the mouse was and the camera (`cl_treeDragStart` / `cl_jmDragStart`)
- drag: camera = start camera − mouse movement ÷ zoom (`cl_treeDragMove` / `cl_jmDragMove`)
- moved more than 4 pixels → `DragMoved = true`, so letting go over a node
  isn't treated as a click on it

### Gliding to a selection

Clicking a node sets a camera **target**. Each frame the camera moves part of
the remaining way (`1 − e^(−dt × GLIDE)`, an exponential ease), until it's
within a unit. Dragging cancels it.

### Drawing shapes

There's no line or circle widget, so:

- **Rectangles**: a `Widget` with the `WhiteSkin` skin and a `Colour` (`Rect`, `MapRect`).
- **Tree lines**: three thin rectangles each (across, down/up, across).
- **Map roads**: a curve sampled along its length and drawn as evenly spaced
  dots. Each road tries a few bends and takes the one that passes furthest from
  other junctions (`MAP_ROAD_CLEARANCE`), plus a small wiggle, all from the ids
  so a road always looks the same.
- **Nodes**: in the Fabricator, Survival's item slot (`ItemSlotSchematic.gui`)
  with the item icon, on a coloured frame for its state, scaled with the zoom
  (`ScaleWidget` scales a widget and all its children). On the map, a dark
  tile with a **beacon icon** (`BeaconCompassIconMap`, `NodeBeaconIcon`: house,
  car, ?, !, X, drop, the landmark's icon) tinted by state, a white ring when
  selected, and an invisible button on top for clicks, drags and the wheel.
- **Map picture**: an `ImageBox` with `Gui/RouteMap.png`, positioned and sized
  by the camera. Its path is `$CONTENT_3c9f5e62-.../Gui/RouteMap.png`, since
  menus can't expand `$CONTENT_DATA`.

## Fabricator tree layout

`cl_buildTree` lays out the active tab's upgrades (`UPGRADES`, from
`Fabricator/upgrade_tree.json`; the Fabricator Tree Editor copies this layout):

1. **A grid, like Pacific Drive's fabrication station** (square cells,
   `TREE_COLUMN` = `TREE_ROW`). Each tree is laid out on its own from its root,
   breadth first: what an upgrade leads to goes in the free cell next to it,
   keeping the heading it came in on if it can (`AROUND`, `freeNear`), so
   branches carry on outward; roots head right.
2. **Packing**: the trees (single upgrades too) are packed in rows like tiles,
   a cell apart, aiming for about twice as wide as tall.
3. **Lines** run straight from one item to the next, edge to edge: level or
   upright ones are one bar, diagonals a row of dots (widgets can't be turned).
4. Opened (or new tab): zoom so the whole tree fits, up to full size.
5. Node frame colour by state: unlocked / available / can't afford / locked;
   lines are lit once their requirement is unlocked.

Clicking a node selects it (side panel); the Unlock button sends
`sv_n_unlock`, which checks and spends the anchor bank on the server and
unlocks the recipe with Survival's `RecipeManager`.

## The junction map window

`Game.cl_n_junctionMap( data )` receives the map from the server
(`sv_jmSend`) and opens the window. **Modes**:

| Mode | Opened by | Title | Button |
|---|---|---|---|
| `planner` | Route Planner (garage) | ROUTE PLANNER | Scan / Set Destination, plus Re-stabilize |
| `travel` | driving into a junction | JUNCTION MAP | Travel (closing = stay) |
| `view` | Logbook key, `/junctionmap` | JUNCTION MAP | none; tabs shown |

`cl_jmBuild` draws: the picture, the tier names, faint squares on free sites,
the roads, the junctions (colour by state: current / destination / visited /
choice / landmark / danger / unknown / locked), and a hint line. The side panel
shows the selected junction's details; the Route Analysis meters are drawn in
the header (`cl_jmMeters`). `BuildMapGui` changes the Fabricator layout once:
retitles it, hides the currency, removes the trade cost box, adds the meters
and a second button for Re-stabilize.

### The QUESTS and BEACONS tabs

In view mode the tab bar shows MAP / QUESTS / BEACONS. The two lists
(`cl_jmBuildList`) replace the canvas and copy what the logbook shows:

- QUESTS: active quests from `QuestManager.Cl_GetActiveQuests()`, main quests
  first, with their tracker steps; TRACK / UNTRACK uses
  `QuestManager.Cl_TrackQuest / Cl_UntrackQuest`.
- BEACONS: beacons from `g_beaconManager`, nearest first; the button toggles
  their compass marker.

The track buttons are copies of a tab widget (`gui.SmallButton`).

## The Logbook key opens the map

Survival's Logbook key equips the logbook *tool*. With `MAP_ON_LOGBOOK_KEY`,
`survival_patches.lua` swaps three of the tool's functions:

- `PatchedLogBookEquip`: plays the normal take-out animation and model, but
  instead of the logbook window sets `g_pacificMapRequest = "open"`.
- `PatchedLogBookUnequip`: putting it away sets `g_pacificMapRequest = "close"`.
- `PatchedLogBookEquippedUpdate`: if the map was closed with Esc or its close
  button (`g_pacificMapClosedByUser`, set in `cl_jmOnClose`), puts the logbook away
  (`sm.tool.forceTool( nil )`).

A tool script can't talk to the game script directly, so it leaves the request
in a global; `Game.client_onUpdate` reads `g_pacificMapRequest` every frame
and opens or closes the map.

`ApplySurvivalPatches()` reapplies the swap every second, since Survival may
load (and redefine) the `LogBook` class after us, and keeps the original
functions so it can fall back to them.

## The hideout shop

`Scripts/hideout_shop.lua` builds the same menu for the Farmers' Hideout:
crate counters (the currency box split in 8), trades as item slots with a
quantity in the grid, the selected trade's cost and the Trade button on the
right. See [zones.md](zones.md).

## Gotchas

- `dofile` only works at the top of a script, so the `.gui` files are loaded
  there and copied (`DeepCopy`) when building.
- Click sounds need a world, and the game script has none, so the map has no click sounds.
- A canvas widget needs `NeedMouse = true` or the buttons inside get no clicks.
- Don't put Lua-only keys into the json table: the game reads every key
  (`wide_gui.lua` keeps its saved sizes in a separate table for that reason).
