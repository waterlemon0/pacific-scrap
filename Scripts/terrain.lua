dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util2.lua" )
dofile( "$CONTENT_DATA/Scripts/tilepack.lua" )
dofile( "$GAME_DATA/Scripts/terrain/terrain_prepare_cell_util.lua" )
dofile( "$CONTENT_DATA/Scripts/terrain_random_tables.lua" )

-- Tile based terrain built from a layout passed in as world data:
--   data.tiles = PackTiles( { { path = "...", x = cellX, y = cellY, size = cellsPerSide }, ... } )
-- A 128m tile has size 2 and covers cells (x..x+1, y..y+1).
-- The layout can arrive either as world creation data or as terrain script
-- data (survival's Overworld replaces the latter, so GarageWorld re-sends it).

function Init( world, generatorIndex, data )
	g_world = world
	g_generatorIndex = generatorIndex
	g_initData = data
end

function Create( xMin, xMax, yMin, yMax, seed, data )

	g_uuidToPath = {}
	g_cellData = {
		bounds = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax },
		seed = seed,
		-- Per Cell
		uid = {},
		xOffset = {},
		yOffset = {},
		rotation = {},
		groupId = {},
	}

	for cellY = yMin, yMax do
		g_cellData.uid[cellY] = {}
		g_cellData.xOffset[cellY] = {}
		g_cellData.yOffset[cellY] = {}
		g_cellData.rotation[cellY] = {}
		g_cellData.groupId[cellY] = {}

		for cellX = xMin, xMax do
			g_cellData.uid[cellY][cellX] = sm.uuid.getNil()
			g_cellData.xOffset[cellY][cellX] = 0
			g_cellData.yOffset[cellY][cellX] = 0
			g_cellData.rotation[cellY][cellX] = 0
			g_cellData.groupId[cellY][cellX] = 0
		end
	end

	local tiles = UnpackTiles( ( data and data.tiles ) or ( g_initData and g_initData.tiles ) )
	-- Optional gentle hills on top of the tiles: { amplitude = metres, scale = metres }
	g_cellData.elevation = ( data and data.elevation ) or ( g_initData and g_initData.elevation )
	-- Spots kept level under the hills (ponds, chemical lakes, oil pools), so
	-- their water planes sit flat: { x, y, r } in metres
	g_cellData.flats = ( data and data.flats ) or ( g_initData and g_initData.flats )
	-- Mountains beyond the map and a rim inside it (EdgeHeight)
	g_cellData.edge = ( data and data.edge ) or ( g_initData and g_initData.edge )
	-- The zone tier's ground paint (ZONE_TIERS paint in layouts.lua)
	g_cellData.paint = ( data and data.paint ) or ( g_initData and g_initData.paint )
	-- Shallow chemical pools (the Mid Zone): { x, y, r, depth } in metres
	g_cellData.pools = ( data and data.pools ) or ( g_initData and g_initData.pools )
	-- ...or (newer zones) the wetland: flooded cells (a bitmap, see WetAt)
	g_cellData.wet = ( data and data.wet ) or ( g_initData and g_initData.wet )
	-- ...and its plants (ZONE_TIERS foliage): grass swapped, leaves recoloured
	g_cellData.foliage = ( data and data.foliage ) or ( g_initData and g_initData.foliage )
	-- The first junctions use Survival's starting-area loot (GetTagsForCell)
	g_cellData.startLoot = ( data and data.startLoot ) or ( g_initData and g_initData.startLoot )
	for _, tile in ipairs( tiles ) do
		local uid = sm.terrainTile.getTileUuid( tile.path )
		g_uuidToPath[tostring( uid )] = tile.path
		local size = tile.size or sm.terrainTile.getSize( tile.path ) or 1
		-- Rotation (0-3) is only supported for single-cell tiles
		local rotation = size == 1 and ( tile.rotation or 0 ) or 0
		for dy = 0, size - 1 do
			for dx = 0, size - 1 do
				local cellX = tile.x + dx
				local cellY = tile.y + dy
				if cellX >= xMin and cellX <= xMax and cellY >= yMin and cellY <= yMax then
					g_cellData.uid[cellY][cellX] = uid
					g_cellData.xOffset[cellY][cellX] = dx
					g_cellData.yOffset[cellY][cellX] = dy
					g_cellData.rotation[cellY][cellX] = rotation
				end
			end
		end
	end

	sm.terrainData.save( { g_uuidToPath, g_cellData } )
	-- Per-cell tags/heights that survival managers (tornado, scannerbot) read
	CreateCellDataStorage()
end

function Load()
	if sm.terrainData.exists() then
		local data = sm.terrainData.load()
		g_uuidToPath = data[1]
		g_cellData = data[2]
		CreateCellDataStorage()
		return true
	end
	return false
end

-- Smooth rolling hills added on top of the tiles (zone only). Everything in a
-- tile (trees, rocks, decals...) is lifted by the same amount, the way the
-- survival overworld applies its elevation.
local FLAT_BLEND = 40 -- metres to ease from a flat spot back into the hills

local function RawElevation( e, x, y )
	local seed = ( g_cellData.seed or 0 ) % 10000
	-- Big smooth rolls plus a little detail, roughly within +-amplitude
	local u, v = x / e.scale, y / e.scale
	local h = sm.noise.perlinNoise2d( u, v, seed )
		+ sm.noise.perlinNoise2d( u * 2, v * 2, seed + 5527 ) * 0.35
		+ sm.noise.perlinNoise2d( u * 4, v * 4, seed + 8733 ) * 0.12
	return h * e.amplitude
end

-- The world's edge (data.edge): instead of flat grass beyond the map, mountains
-- rise outside it; inside, the ground climbs into a rim over the last stretch
-- (edge.rim metres high over edge.width metres), except around the junctions
-- (edge.clear: { x, y } spots kept at their own height), whose roads lead out
-- through the rim. Outside the map the mountains start from the rim's height.
--   edge = { rim = metres, width = metres, mountains = metres, clear = { { x, y }, ... } }
local EDGE_CLEAR_RADIUS = 90  -- metres around a junction kept clear of the rim...
local EDGE_CLEAR_BLEND = 70   -- ...easing back into it over this
local MOUNTAIN_RISE = 220     -- metres outside the map the mountains take to reach full height

-- (a cell with no tile, e.g. an older save's world grown by the forest ring)
function CellHasNoTile( cellX, cellY )
	local uid = GetCellTileUidAndOffset( cellX, cellY )
	return uid:isNil()
end

local function Smooth( t )
	t = math.max( math.min( t, 1 ), 0 )
	return t * t * ( 3 - 2 * t )
end

local function EdgeHeight( x, y )
	local edge = g_cellData and g_cellData.edge
	if not edge then
		return 0
	end
	-- (the playable area: edge.bounds in metres, else the world's cells)
	local x0, x1, y0, y1
	if edge.bounds then
		x0, x1, y0, y1 = edge.bounds.x0, edge.bounds.x1, edge.bounds.y0, edge.bounds.y1
	else
		local bounds = g_cellData.bounds
		x0, x1 = bounds.xMin * CELL_SIZE, ( bounds.xMax + 1 ) * CELL_SIZE
		y0, y1 = bounds.yMin * CELL_SIZE, ( bounds.yMax + 1 ) * CELL_SIZE
	end
	-- Signed distance to the map's edge: below 0 inside, above 0 outside
	local s
	if x >= x0 and x <= x1 and y >= y0 and y <= y1 then
		s = -math.min( x - x0, x1 - x, y - y0, y1 - y )
	else
		local dx = math.max( x0 - x, 0, x - x1 )
		local dy = math.max( y0 - y, 0, y - y1 )
		s = math.sqrt( dx * dx + dy * dy )
	end
	local seed = ( g_cellData.seed or 0 ) % 10000
	-- The rim (none near a junction)
	local rim = 0
	if edge.rim and edge.width then
		local clear = 1
		for _, spot in ipairs( edge.clear or {} ) do
			local dx, dy = x - spot.x, y - spot.y
			local d = math.sqrt( dx * dx + dy * dy )
			clear = math.min( clear, Smooth( ( d - EDGE_CLEAR_RADIUS ) / EDGE_CLEAR_BLEND ) )
		end
		local shape = 0.75 + 0.25 * sm.noise.perlinNoise2d( x / 90, y / 90, seed + 311 )
		rim = edge.rim * shape * clear * Smooth( ( s + edge.width ) / edge.width )
	end
	if s <= 0 or not edge.mountains then
		return rim
	end
	-- Beyond the map: ridges and peaks
	local rise = Smooth( s / MOUNTAIN_RISE )
	local peaks = 0.65 + 0.35 * sm.noise.perlinNoise2d( x / 260, y / 260, seed + 977 )
		+ 0.15 * sm.noise.perlinNoise2d( x / 70, y / 70, seed + 1201 )
	return rim + edge.mountains * rise * peaks
end

-- Where there's no tile (beyond the world's cells): the ground there is rock
local function OutsideMap( x, y )
	local cellX, cellY = GetCell( x, y )
	return not InsideCellBounds( cellX, cellY ) or g_cellData.uid[cellY][cellX]:isNil()
end

-- The ground's height above the tiles: hills (zone only) and the edge
local function BaseElevation( x, y )
	local e = g_cellData and g_cellData.elevation
	return ( e and RawElevation( e, x, y ) or 0 ) + EdgeHeight( x, y )
end

-- Shallow pools: the ground is level round each (it's in the flats) and dips
-- in a blobby patch inside it; the liquid's surface sits just under the level,
-- so it only shows where the ground dips (PoolLevel, AddPoolLiquids)
local POOL_SURFACE_BELOW = 0.2 -- metres the liquid sits under the level ground
local function PoolDip( x, y )
	local dip = 0
	for _, p in ipairs( g_cellData.pools or {} ) do
		local dx, dy = x - p.x, y - p.y
		if dx > -p.r and dx < p.r and dy > -p.r and dy < p.r then
			local d = math.sqrt( dx * dx + dy * dy )
			if d < p.r then
				local wobble = 0.65 + 0.35 * sm.noise.perlinNoise2d( x / 9, y / 9, 2287 )
				dip = math.max( dip, ( p.depth or 1 ) * Smooth( ( 1 - d / p.r ) * 1.8 * wobble ) )
			end
		end
	end
	return dip
end

-- Wetland (the Mid Zone, layouts.lua ZoneLayout): cells flooded with shallow
-- chemicals, as a bitmap: g_cellData.wet = { x0, y0, w, h, bits, depth, cover }
-- (bits: one "1" or "0" per cell, row by row from x0, y0). A wet cell is level
-- ground like a flat spot (all touching ones at one height, so the liquid sits
-- level across them); its ground dips in blobby patches (WetDip) and the liquid
-- surface sits just under the level, so it shows where the ground dips.
local WET_RADIUS = 46        -- a wet cell levels the ground like a flat spot this big
local WET_EDGE = 26          -- metres from a dry neighbour over which the dips shrink away
local WET_BOX = 2            -- metres: the liquid's box under its surface (deeper than the dips)
local function WetAt( cx, cy )
	local w = g_cellData and g_cellData.wet
	if not w then return false end
	local i, j = cx - w.x0, cy - w.y0
	if i < 0 or j < 0 or i >= w.w or j >= w.h then return false end
	local k = j * w.w + i + 1
	return w.bits:sub( k, k ) == "1"
end
local function WetKey( cx, cy )
	return ( cy + 4096 ) * 8192 + ( cx + 4096 )
end

-- The level ground's heights: flat spots and wet cells that touch (side-by-side
-- ruins, a ruin next to a junction, a whole flooded stretch) share one, the
-- average of their centres, so the ground is level across all of them instead
-- of sloping between them. Worked out once per layout.
-- Returns { flat = { [i] = height }, wet = { [key] = height }, wetGroup = { [key] = group },
-- groupCells = { [group] = { { cx, cy } } } }
local s_levelsFor, s_levelsWet, s_levels
local function LevelGroups()
	local flats = g_cellData.flats or {}
	local wet = g_cellData.wet
	if s_levelsFor == flats and s_levelsWet == wet and s_levels then
		return s_levels
	end
	-- Nodes: the flat spots (1..#flats), then the wet cells
	local nodes = {}
	for i, f in ipairs( flats ) do nodes[i] = { x = f.x, y = f.y, r = f.r } end
	local wetNode = {}
	if wet then
		for j = 0, wet.h - 1 do
			for i = 0, wet.w - 1 do
				local cx, cy = wet.x0 + i, wet.y0 + j
				if WetAt( cx, cy ) then
					nodes[#nodes + 1] = { x = ( cx + 0.5 ) * CELL_SIZE, y = ( cy + 0.5 ) * CELL_SIZE, r = WET_RADIUS, cx = cx, cy = cy }
					wetNode[WetKey( cx, cy )] = #nodes
				end
			end
		end
	end
	local group = {}
	local function find( i )
		while group[i] ~= i do i = group[i] end
		return i
	end
	local function join( a, b ) group[find( b )] = find( a ) end
	for i in ipairs( nodes ) do group[i] = i end
	-- flat spots with each other, and with the wet cells round them
	for i, a in ipairs( flats ) do
		for j = i + 1, #flats do
			local b = flats[j]
			local dx, dy = a.x - b.x, a.y - b.y
			if dx * dx + dy * dy < ( a.r + b.r ) ^ 2 then join( i, j ) end
		end
		if wet then
			local reach = math.ceil( ( a.r + WET_RADIUS ) / CELL_SIZE )
			local fx, fy = math.floor( a.x / CELL_SIZE ), math.floor( a.y / CELL_SIZE )
			for cy = fy - reach, fy + reach do
				for cx = fx - reach, fx + reach do
					local n = wetNode[WetKey( cx, cy )]
					if n then
						local dx, dy = a.x - nodes[n].x, a.y - nodes[n].y
						if dx * dx + dy * dy < ( a.r + WET_RADIUS ) ^ 2 then join( i, n ) end
					end
				end
			end
		end
	end
	-- wet cells with their neighbours (side by side and corner to corner)
	for key, n in pairs( wetNode ) do
		local node = nodes[n]
		for dy = -1, 1 do
			for dx = -1, 1 do
				local m = wetNode[WetKey( node.cx + dx, node.cy + dy )]
				if m then join( n, m ) end
			end
		end
	end
	local sum, count = {}, {}
	for i, node in ipairs( nodes ) do
		local g = find( i )
		sum[g] = ( sum[g] or 0 ) + BaseElevation( node.x, node.y )
		count[g] = ( count[g] or 0 ) + 1
	end
	local levels = { flat = {}, wet = {}, wetGroup = {}, groupCells = {} }
	for i in ipairs( flats ) do
		local g = find( i )
		levels.flat[i] = sum[g] / count[g]
	end
	for key, n in pairs( wetNode ) do
		local g = find( n )
		levels.wet[key] = sum[g] / count[g]
		levels.wetGroup[key] = g
		levels.groupCells[g] = levels.groupCells[g] or {}
		table.insert( levels.groupCells[g], { cx = nodes[n].cx, cy = nodes[n].cy } )
	end
	s_levelsFor, s_levelsWet, s_levels = flats, wet, levels
	return levels
end

-- How far the ground dips in a wet cell: blobby patches covering about
-- wet.cover of it, fading out towards dry neighbours (so the liquid never
-- shows at the edge of the flooded stretch)
local function WetDip( x, y )
	local w = g_cellData.wet
	if not w then return 0 end
	local cx, cy = math.floor( x / CELL_SIZE ), math.floor( y / CELL_SIZE )
	if not WetAt( cx, cy ) then return 0 end
	local lx, ly = x - cx * CELL_SIZE, y - cy * CELL_SIZE
	local edge = WET_EDGE
	-- (distance to the nearest dry neighbour, up to WET_EDGE)
	if not WetAt( cx - 1, cy ) then edge = math.min( edge, lx ) end
	if not WetAt( cx + 1, cy ) then edge = math.min( edge, CELL_SIZE - lx ) end
	if not WetAt( cx, cy - 1 ) then edge = math.min( edge, ly ) end
	if not WetAt( cx, cy + 1 ) then edge = math.min( edge, CELL_SIZE - ly ) end
	if not WetAt( cx - 1, cy - 1 ) then edge = math.min( edge, math.max( lx, ly ) ) end
	if not WetAt( cx + 1, cy - 1 ) then edge = math.min( edge, math.max( CELL_SIZE - lx, ly ) ) end
	if not WetAt( cx - 1, cy + 1 ) then edge = math.min( edge, math.max( lx, CELL_SIZE - ly ) ) end
	if not WetAt( cx + 1, cy + 1 ) then edge = math.min( edge, math.max( CELL_SIZE - lx, CELL_SIZE - ly ) ) end
	if edge <= 0 then return 0 end
	local seed = ( g_cellData.seed or 0 ) % 10000
	local n = 0.5 + 0.5 * sm.noise.perlinNoise2d( x / 26, y / 26, seed + 4411 )
		+ 0.12 * sm.noise.perlinNoise2d( x / 7, y / 7, seed + 4423 )
	-- How deep into the flooded stretch this is, smoothly: the cells' wet/dry
	-- blended between their centres (so the stretch's outline has diagonals
	-- and round corners, not the cells' squares), looked up a little off the
	-- spot (a wandering shore). Towards the dry side the patches shrink.
	local warp = 22
	local wx = x + warp * sm.noise.perlinNoise2d( x / 45, y / 45, seed + 4471 )
	local wy = y + warp * sm.noise.perlinNoise2d( x / 45, y / 45, seed + 4483 )
	local gx, gy = wx / CELL_SIZE - 0.5, wy / CELL_SIZE - 0.5
	local ix, iy = math.floor( gx ), math.floor( gy )
	local tx, ty = Smooth( gx - ix ), Smooth( gy - iy )
	local function wet01( a, b ) return WetAt( a, b ) and 1 or 0 end
	local field = ( wet01( ix, iy ) * ( 1 - tx ) + wet01( ix + 1, iy ) * tx ) * ( 1 - ty )
		+ ( wet01( ix, iy + 1 ) * ( 1 - tx ) + wet01( ix + 1, iy + 1 ) * tx ) * ty
	-- (how gently the ground slopes into a patch: wet.soft, WETLAND_SLOPE_SOFTNESS;
	-- older zones have none and keep their steep 0.12, with the same half-way line)
	local soft = w.soft or 0.12
	local blob = ( n - ( 1 - ( w.cover or 0.7 ) ) - 0.06 ) / soft + 0.5 - ( 1 - Smooth( ( field - 0.55 ) / 0.4 ) ) * 10
	-- (and right at a dry cell's edge never any: the liquid's box ends there)
	return ( w.depth or 0.6 ) * Smooth( blob ) * Smooth( edge / 3 )
end

function GetElevation( x, y )
	if not g_cellData or ( not g_cellData.elevation and not g_cellData.edge ) then
		return 0
	end
	local h = BaseElevation( x, y )
	local levels = LevelGroups()
	local flats = g_cellData.flats or {}
	-- Inside a flat spot or a wet cell: exactly its level (touching ones share it)
	local cx, cy = math.floor( x / CELL_SIZE ), math.floor( y / CELL_SIZE )
	local level = g_cellData.wet and levels.wet[WetKey( cx, cy )]
	if not level then
		for i, f in ipairs( flats ) do
			local dx, dy = x - f.x, y - f.y
			if dx > -f.r and dx < f.r and dy > -f.r and dy < f.r and dx * dx + dy * dy < f.r * f.r then
				level = levels.flat[i]
				break
			end
		end
	end
	if level then
		h = level
	else
		-- Near them: easing from their level back into the hills over FLAT_BLEND
		for i, f in ipairs( flats ) do
			local dx, dy = x - f.x, y - f.y
			local reach = f.r + FLAT_BLEND
			-- (most are far away: skip those before the square root)
			local d = ( dx > -reach and dx < reach and dy > -reach and dy < reach ) and math.sqrt( dx * dx + dy * dy ) or reach
			if d < reach then
				local t = Smooth( ( d - f.r ) / FLAT_BLEND )
				h = levels.flat[i] * ( 1 - t ) + h * t
			end
		end
		if g_cellData.wet then
			local cells = math.ceil( ( WET_RADIUS + FLAT_BLEND ) / CELL_SIZE )
			for ny = cy - cells, cy + cells do
				for nx = cx - cells, cx + cells do
					local wetLevel = levels.wet[WetKey( nx, ny )]
					if wetLevel then
						local dx, dy = x - ( nx + 0.5 ) * CELL_SIZE, y - ( ny + 0.5 ) * CELL_SIZE
						local d = math.sqrt( dx * dx + dy * dy )
						if d < WET_RADIUS + FLAT_BLEND then
							local t = Smooth( ( d - WET_RADIUS ) / FLAT_BLEND )
							h = wetLevel * ( 1 - t ) + h * t
						end
					end
				end
			end
		end
	end
	if g_cellData.pools then
		h = h - PoolDip( x, y )
	end
	if g_cellData.wet then
		h = h - WetDip( x, y )
	end
	return h
end

-- A flooded stretch's liquid level: its level ground plus the tiles' own
-- height (the average at its cells' centres), worked out once per stretch
local s_wetSurface = {}
local function WetSurface( cx, cy )
	local levels = LevelGroups()
	local key = WetKey( cx, cy )
	local g = levels.wetGroup[key]
	if not g then return nil end
	if s_wetSurface.levels ~= levels then
		s_wetSurface = { levels = levels }
	end
	if not s_wetSurface[g] then
		local sum, count = 0, 0
		for _, c in ipairs( levels.groupCells[g] ) do
			if not CellHasNoTile( c.cx, c.cy ) then
				local wx, wy = ( c.cx + 0.5 ) * CELL_SIZE, ( c.cy + 0.5 ) * CELL_SIZE
				sum = sum + sm.terrainTile.getHeightAt( GetTileLoadParamsFromWorldPos( wx, wy, 0 ) )
				count = count + 1
			end
		end
		s_wetSurface[g] = levels.wet[key] + ( count > 0 and sum / count or 0 )
	end
	return s_wetSurface[g]
end

local function ElevationInCell( cellX, cellY, rx, ry )
	return GetElevation( cellX * CELL_SIZE + rx, cellY * CELL_SIZE + ry )
end

-- Tiles can hold prefabs (ruin buildings, shacks...). Their contents are
-- loaded here once per cell and handed out by the Get*ForCell functions below,
-- the same way survival's overworld does it.
local randomizationTables = { prefabTable = prefabTable, blueprintTable = blueprintTable }

-- The garage's abandoned car spots always have a car: Survival's
-- random_abandoned_vehicle picks an empty spot (variant 01) about half the
-- time, so the garage's copy of the table leaves that one out. (The zones'
-- roadside wrecks keep Survival's odds.)
local ABANDONED_VEHICLE = "gameplay_prefabs/random_abandoned_vehicle"
local garagePrefabTable = {}
for key, list in pairs( prefabTable ) do garagePrefabTable[key] = list end
garagePrefabTable[ABANDONED_VEHICLE] = {}
for _, entry in ipairs( prefabTable[ABANDONED_VEHICLE] or {} ) do
	local path = type( entry ) == "table" and entry[1] or entry
	if not path:find( "random_abandoned_vehicle_01", 1, true ) then
		table.insert( garagePrefabTable[ABANDONED_VEHICLE], entry )
	end
end
local garageRandomizationTables = { prefabTable = garagePrefabTable, blueprintTable = blueprintTable }

local IsGarageWorld -- (below)

function PrepareCell( cellX, cellY, loadFlags, lodLevel )
	DefaultPrepareCell( cellX, cellY, loadFlags, IsGarageWorld() and garageRandomizationTables or randomizationTables )
end

function GetTilePath( uid )
	if not uid:isNil() then
		return g_uuidToPath[tostring(uid)]
	end
	return ""
end

function GetCellTileUidAndOffset( cellX, cellY )
	if InsideCellBounds( cellX, cellY ) then
		return	g_cellData.uid[cellY][cellX],
				g_cellData.xOffset[cellY][cellX],
				g_cellData.yOffset[cellY][cellX]
	end
	return sm.uuid.getNil(), 0, 0
end

function GetTileLoadParamsFromWorldPos( x, y, lod )
	local cellX, cellY = GetCell( x, y )
	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	local rx, ry = InverseRotateLocal( cellX, cellY, x - cellX * CELL_SIZE, y - cellY * CELL_SIZE )
	if lod then
		return  uid, tileCellOffsetX, tileCellOffsetY, lod, rx, ry
	else
		return  uid, tileCellOffsetX, tileCellOffsetY, rx, ry
	end
end

function GetTileLoadParamsFromCellPos( cellX, cellY, lod )
	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	if lod then
		return  uid, tileCellOffsetX, tileCellOffsetY, lod
	else
		return  uid, tileCellOffsetX, tileCellOffsetY
	end
end

-- Wetland: the ground is never lower than the liquid except in the dips. In a
-- flooded cell (and a step past its edges, so the edge of the liquid's box is
-- always under ground) a tile's low spots are raised to just over the liquid;
-- the dips then cut into that, so the liquid only shows in them, never as a
-- sheet floating over lower ground. Past that step the raised ground slopes
-- back into the natural ground over a distance that wanders, so it doesn't
-- show the square cells.
local WET_BERM_REACH = 1.5   -- metres past a flooded cell's edge the ground is fully kept up
local WET_BERM_SLOPE = { 6, 18 } -- metres it then takes to ease back down (varies along the edge)
local WET_BERM_OVER = 0.15   -- metres the ground stays above the liquid's top
local function WetBerm( x, y, h )
	local cx, cy = math.floor( x / CELL_SIZE ), math.floor( y / CELL_SIZE )
	local seed = ( g_cellData.seed or 0 ) % 10000
	local slope = WET_BERM_SLOPE[1] + ( WET_BERM_SLOPE[2] - WET_BERM_SLOPE[1] ) * ( 0.5 + 0.5 * sm.noise.perlinNoise2d( x / 30, y / 30, seed + 4457 ) )
	local dip = WetDip( x, y )
	local raised = h + dip
	local best = raised
	for ny = cy - 1, cy + 1 do
		for nx = cx - 1, cx + 1 do
			if WetAt( nx, ny ) then
				local surface = WetSurface( nx, ny )
				if surface then
					local level = surface - POOL_SURFACE_BELOW + WET_BERM_OVER
					if level > raised then
						-- how far outside that cell's square (0 inside it)
						local x0, y0 = nx * CELL_SIZE, ny * CELL_SIZE
						local dx = math.max( x0 - x, 0, x - ( x0 + CELL_SIZE ) )
						local dy = math.max( y0 - y, 0, y - ( y0 + CELL_SIZE ) )
						local d = math.sqrt( dx * dx + dy * dy )
						local weight = 1 - Smooth( ( d - WET_BERM_REACH ) / slope )
						if weight > 0 then
							best = math.max( best, raised + ( level - raised ) * weight )
						end
					end
				end
			end
		end
	end
	return best - dip
end

function GetHeightAt( x, y, lod )
	local h = sm.terrainTile.getHeightAt( GetTileLoadParamsFromWorldPos( x, y, lod ) ) + GetElevation( x, y )
	if g_cellData and g_cellData.wet then
		h = WetBerm( x, y, h )
	end
	return h
end

function GetColorAt( x, y, lod )
	if g_cellData and g_cellData.edge and OutsideMap( x, y ) then
		-- (the mountains: grey-brown rock, a little varied)
		local v = 0.62 + 0.12 * sm.noise.perlinNoise2d( x / 40, y / 40, 77 )
		return v, v * 0.97, v * 0.92
	end
	local r, g, b = sm.terrainTile.getColorAt( GetTileLoadParamsFromWorldPos( x, y, lod ) )
	-- The tier's paint, over the tile's own (white in Survival's nature tiles,
	-- so it shows as is; roads and buildings keep their shade underneath)
	local paint = g_cellData and g_cellData.paint
	if paint and r then
		local t = Smooth( 0.5 + 0.8 * sm.noise.perlinNoise2d( x / paint.scale, y / paint.scale, 4211 ) )
		local s, o = paint.strong, paint.soft
		return r * ( s[1] + ( o[1] - s[1] ) * t ), g * ( s[2] + ( o[2] - s[2] ) * t ), b * ( s[3] + ( o[3] - s[3] ) * t )
	end
	return r, g, b
end

function GetMaterialAt( x, y, lod )
	if g_cellData and g_cellData.edge and OutsideMap( x, y ) then
		-- (rock and dirt: the ground material set's stone, dirt and rough stone)
		local n = 0.5 + 0.5 * sm.noise.perlinNoise2d( x / 60, y / 60, 91 )
		return 0, 0.6 * n, 0.3, 0, 1 - 0.6 * n, 0, 0, 0
	end
	return sm.terrainTile.getMaterialAt( GetTileLoadParamsFromWorldPos( x, y, lod ) )
end

-- The tier's foliage (ZONE_TIERS foliage in layouts.lua) -----------------------
-- Grass-like clutter types (the game's clutter numbers: Data's clutter.json
-- list, then Survival's) that the foliage swaps; rocks, flowers, road bits stay
local GRASS_CLUTTER = {}
for _, i in ipairs( { 0, 1, 2, 3, 4, 10, 11, 13, 15, 17, 18, 19, 21, 22, 23, 24, 25, 26, 27, 28, 42 } ) do GRASS_CLUTTER[i] = true end -- (42: the green seaweed)
-- Survival's trees (their colour tints the leaves)
local TREE_UUIDS = {}
for _, id in ipairs( {
	"c4ea19d3-2469-4059-9f13-3ddb4f7e0b79", "711c3e72-7ba1-4424-ae70-c13d23afe818", "a7aa52af-4276-4b2d-af44-36bc41864e04",
	"91ec04ea-9bf7-4a9d-bb7f-3d0125ff78c7", "4d482999-98b7-4023-a149-d47be709b8f7", "3db0a60d-8668-4c8a-8dd2-f5ceb294977e",
	"8411caba-63db-4b93-ad67-7ae8e350d360", "1cb503a4-9306-412f-9e13-371bc634af60", "fa864e51-67db-4ac9-823b-cfbdf523375d",
	"73f968f0-d3a3-4334-86a8-a90203a3a56d", "86324c5b-e97a-41f6-aa2c-7c6462f1f2e7", "27aa53ea-1e09-4251-a284-437f93850409",
} ) do TREE_UUIDS[id] = true end

local function FoliageLeaves( seed )
	local leaves = g_cellData.foliage.leaves
	return sm.color.new( leaves[seed % #leaves + 1] )
end

-- Clutter (grass) uses a grid twice as fine as metres, so x/y are in half-metres
function GetClutterIdxAt( x, y )
	local cellX, cellY = GetCell( x * 0.5, y * 0.5 )
	if InsideCellBounds( cellX, cellY ) then
		local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
		local rx, ry = InverseRotateLocal( cellX, cellY, x - cellX * CELL_SIZE * 2, y - cellY * CELL_SIZE * 2, CELL_SIZE * 2 - 1 )
		local idx = sm.terrainTile.getClutterIdxAt( uid, tileCellOffsetX, tileCellOffsetY, rx, ry )
		-- The tier's plants instead of the grass, in patches (x, y: half-metres)
		local foliage = g_cellData.foliage
		if foliage and foliage.clutter and GRASS_CLUTTER[idx] then
			local n = 0.5 + 0.5 * sm.noise.perlinNoise2d( x / 30, y / 30, 5113 )
			return foliage.clutter[math.min( math.floor( n * #foliage.clutter ) + 1, #foliage.clutter )]
		end
		return idx
	end
	return -1
end

-- Footstep / impact sound material
function GetEffectMaterialAt( x, y )
	return "Grass"
end

-- Survival reads these when a cell loads: STARTAREA makes its ruin chests and
-- loot crates use the starting-area loot pools
function GetTagsForCell( cellX, cellY )
	if g_cellData and g_cellData.startLoot then
		return { "STARTAREA" }
	end
	return {}
end

-- The pools' liquid: a chemical surface (Survival's chemicals asset, modelled
-- Y-up, 1 m at scale 1) and a CHEMICALS node (the liquid itself, as in
-- Survival's Chemicals prefab), square, centred on each pool in this cell.
-- Positions are local to the cell.
local CHEMICALS_ASSET = sm.uuid.new( "f0f2db63-1f2e-4aae-8dc4-ab7cd6fe2658" )
-- The wetland's liquid (g_cellData.wet.liquid): Survival's surface asset and
-- the node tag its liquid manager makes the liquid from
local LIQUIDS = {
	water = { asset = sm.uuid.new( "990cce84-a683-4ea6-83cc-d0aee5e71e15" ), tag = "WATER" },
	chemicals = { asset = CHEMICALS_ASSET, tag = "CHEMICALS" },
	oil = { asset = sm.uuid.new( "40151920-f883-4d59-8f5d-c9d52222a6f8" ), tag = "OIL" },
}
local POOL_DEPTH_BOX = 4 -- metres: the liquid's box, its top at the surface
local function PoolsInCell( cellX, cellY )
	local list = {}
	for _, p in ipairs( g_cellData and g_cellData.pools or {} ) do
		if math.floor( p.x / CELL_SIZE ) == cellX and math.floor( p.y / CELL_SIZE ) == cellY then
			-- the level ground round it: the tile's height there plus the hills
			-- (its flat spot's height, shared with any flat spots it touches,
			-- without the dip)
			local level = sm.terrainTile.getHeightAt( GetTileLoadParamsFromWorldPos( p.x, p.y, 0 ) ) + GetElevation( p.x, p.y ) + PoolDip( p.x, p.y ) + WetDip( p.x, p.y )
			list[#list + 1] = {
				pos = sm.vec3.new( p.x - cellX * CELL_SIZE, p.y - cellY * CELL_SIZE, level - POOL_SURFACE_BELOW - POOL_DEPTH_BOX * 0.5 ),
				rot = sm.quat.angleAxis( math.rad( 90 ), sm.vec3.new( 1, 0, 0 ) ),
				scale = sm.vec3.new( p.r * 2, POOL_DEPTH_BOX, p.r * 2 ),
			}
		end
	end
	-- A wet cell (the Mid Zone wetland): a liquid box over the whole cell, its
	-- top just under the stretch's level ground
	if g_cellData and g_cellData.wet and WetAt( cellX, cellY ) then
		local surface = WetSurface( cellX, cellY )
		if surface then
			local liquid = LIQUIDS[g_cellData.wet.liquid or "chemicals"] or LIQUIDS.chemicals
			list[#list + 1] = {
				pos = sm.vec3.new( CELL_SIZE * 0.5, CELL_SIZE * 0.5, surface - POOL_SURFACE_BELOW - WET_BOX * 0.5 ),
				rot = sm.quat.angleAxis( math.rad( 90 ), sm.vec3.new( 1, 0, 0 ) ),
				scale = sm.vec3.new( CELL_SIZE, WET_BOX, CELL_SIZE ),
				asset = liquid.asset, tag = liquid.tag,
			}
		end
	end
	return list
end

function GetAssetsForCell( cellX, cellY, lod )
	if CellHasNoTile( cellX, cellY ) then g_prefabAssets = {} return {} end
	local assets = sm.terrainTile.getAssetsForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	concat( assets, g_prefabAssets or {} )
	g_prefabAssets = {}
	for _, asset in ipairs( assets ) do
		local rx, ry = RotateLocal( cellX, cellY, asset.pos.x, asset.pos.y )
		asset.pos = sm.vec3.new( rx, ry, asset.pos.z + ElevationInCell( cellX, cellY, rx, ry ) )
		asset.pos.z = WaterSurfaceGridOffset( asset, asset.pos.z )
		asset.rot = GetRotationQuat( cellX, cellY ) * asset.rot
	end
	-- The tier's foliage: bushes' leaves and bark recoloured
	local foliage = g_cellData.foliage
	if foliage then
		for i, asset in ipairs( assets ) do
			if type( asset.colors ) == "table" then
				if asset.colors.leaves and foliage.leaves then asset.colors.leaves = FoliageLeaves( cellX * 31 + cellY * 17 + i ) end
				if asset.colors.bark and foliage.bark then asset.colors.bark = sm.color.new( foliage.bark ) end
			end
		end
	end
	for _, pool in ipairs( PoolsInCell( cellX, cellY ) ) do
		assets[#assets + 1] = { uuid = pool.asset or CHEMICALS_ASSET, pos = pool.pos, rot = pool.rot, scale = pool.scale, colors = {}, tags = {} }
	end
	return assets
end

function GetNodesForCell( cellX, cellY )
	if CellHasNoTile( cellX, cellY ) then g_prefabNodes = {} return {} end
	local nodes = sm.terrainTile.getNodesForCell( GetTileLoadParamsFromCellPos( cellX, cellY ) )
	concat( nodes, g_prefabNodes or {} )
	g_prefabNodes = {}
	for _, node in ipairs( nodes ) do
		local rx, ry = RotateLocal( cellX, cellY, node.pos.x, node.pos.y )
		node.pos = sm.vec3.new( rx, ry, node.pos.z + ElevationInCell( cellX, cellY, rx, ry ) )
		node.pos.z = WaterNodeGridOffset( node, node.pos.z )
		node.rot = GetRotationQuat( cellX, cellY ) * node.rot
	end
	for _, pool in ipairs( PoolsInCell( cellX, cellY ) ) do
		nodes[#nodes + 1] = { pos = pool.pos, rot = pool.rot, scale = pool.scale, tags = { pool.tag or "CHEMICALS" } }
	end
	return nodes
end

-- The garage's abandoned cars (Survival's random_abandoned_vehicle prefab in
-- garage.tile) come from our copies of their blueprints
-- (Blueprints/make_cars.py: the scrap engine's tank full).
-- (The game only takes a blueprint path here, not the blueprint as JSON.)
function IsGarageWorld()
	for _, path in pairs( g_uuidToPath or {} ) do
		if path:find( "garage.tile", 1, true ) then return true end
	end
	return false
end

local function UpgradeCar( creation )
	local path = creation.pathOrJson
	if type( path ) == "string" and path:find( "Roadside_AbandonedVehicle", 1, true ) then
		local name = path:match( "([^/]+%.blueprint)$" )
		if name then
			creation.pathOrJson = "$CONTENT_DATA/Blueprints/" .. name
		end
	end
end

function GetCreationsForCell( cellX, cellY )
	local prefabCreations = g_prefabCreations or {}
	g_prefabCreations = {}
	local uid, tileCellOffsetX, tileCellOffsetY = GetCellTileUidAndOffset( cellX, cellY )
	if not uid:isNil() then
		local cellCreations = sm.terrainTile.getCreationsForCell( uid, tileCellOffsetX, tileCellOffsetY )
		concat( cellCreations, prefabCreations )
		for i,creation in ipairs( cellCreations ) do
			local rx, ry = RotateLocal( cellX, cellY, creation.pos.x, creation.pos.y )

			creation.pos = sm.vec3.new( rx, ry, creation.pos.z + ElevationInCell( cellX, cellY, rx, ry ) )
			creation.rot = GetRotationQuat( cellX, cellY ) * creation.rot
		end
		if IsGarageWorld() then
			for _, creation in ipairs( cellCreations ) do UpgradeCar( creation ) end
		end

		return cellCreations
	end

	return {}
end

function GetHarvestablesForCell( cellX, cellY, lod )
	if CellHasNoTile( cellX, cellY ) then g_prefabHarvestables = {} return {} end
	local harvestables = sm.terrainTile.getHarvestablesForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	concat( harvestables, g_prefabHarvestables or {} )
	g_prefabHarvestables = {}
	for _, harvestable in ipairs( harvestables ) do
		local rx, ry = RotateLocal( cellX, cellY, harvestable.pos.x, harvestable.pos.y )
		harvestable.pos = sm.vec3.new( rx, ry, harvestable.pos.z + ElevationInCell( cellX, cellY, rx, ry ) )
		harvestable.rot = GetRotationQuat( cellX, cellY ) * harvestable.rot
	end
	-- The tier's foliage: tree leaves recoloured
	local foliage = g_cellData.foliage
	if foliage and foliage.leaves then
		for i, harvestable in ipairs( harvestables ) do
			if harvestable.color and TREE_UUIDS[tostring( harvestable.uuid )] then
				harvestable.color = FoliageLeaves( cellX * 13 + cellY * 7 + i )
			end
		end
	end
	return harvestables
end

function GetKinematicsForCell( cellX, cellY, lod )
	if CellHasNoTile( cellX, cellY ) then g_prefabKinematics = {} return {} end
	local kinematics = sm.terrainTile.getKinematicsForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	concat( kinematics, g_prefabKinematics or {} )
	g_prefabKinematics = {}
	for _, kinematic in ipairs( kinematics ) do
		local rx, ry = RotateLocal( cellX, cellY, kinematic.pos.x, kinematic.pos.y )
		kinematic.pos = sm.vec3.new( rx, ry, kinematic.pos.z + ElevationInCell( cellX, cellY, rx, ry ) )
		kinematic.rot = GetRotationQuat( cellX, cellY ) * kinematic.rot
	end
	return kinematics
end

function GetDecalsForCell( cellX, cellY, lod )
	if CellHasNoTile( cellX, cellY ) then g_prefabDecals = {} return {} end
	local decals = sm.terrainTile.getDecalsForCell( GetTileLoadParamsFromCellPos( cellX, cellY, lod ) )
	concat( decals, g_prefabDecals or {} )
	g_prefabDecals = {}
	for _, decal in ipairs( decals ) do
		local rx, ry = RotateLocal( cellX, cellY, decal.pos.x, decal.pos.y )
		decal.pos = sm.vec3.new( rx, ry, decal.pos.z + ElevationInCell( cellX, cellY, rx, ry ) )
		decal.rot = GetRotationQuat( cellX, cellY ) * decal.rot
	end
	return decals
end
