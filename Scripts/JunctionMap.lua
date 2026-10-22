-- Junction map and Route Planner (Pacific Drive style). Two ways to see the
-- same map:
--   * the Route Planner (a console in the garage, RoutePlanner.lua): scan
--     junctions, re-stabilize them and set a destination. Garage only.
--   * the junction map: opens when you drive into a junction (the garage pad or
--     a zone exit) and is only for travelling: pick the next junction and go.
--     It shows what you've scanned. /junctionmap opens it to look at.
--
-- The garage is the root;
-- every junction leads on to 2-3 junctions one deeper.
--
-- Unlocking (as in Pacific Drive): a junction's exits are locked until you've
-- escaped it through a gateway once. So each trip can push one junction further
-- than before. Junctions with NO STABLE EXITS can't be escaped, so their exits
-- are always open (you pass through them). The map holds every junction you can
-- reach, the route to where you are, and what's behind the locked exits there.
--
-- Each junction has (rolled when it appears, conditions re-rolled every time
-- you're back at the garage):
--   * an ID (JCT B3), a biome and a map name (BACK ROADS, TOWN CENTER, ...)
--   * an anchor charge: what a gateway costs there
--   * NO STABLE EXITS (no gateway can open) or, rarely, DEAD END (no gateway
--     and no way on)
--   * stability: how long before the zone collapses (Pacific Drive's
--     f(x) = 16.2x + 150 seconds, scaled by STABILITY_TIME_SCALE)
--   * how many energy anchors, and the lowest grade
--   * conditions, and Route Analysis meters (Zone Storm speed, Anomaly density,
--     Atmospheric shifts, Building density)
-- Scanning: junctions you haven't been to are unknown until scanned. You get
-- SCANNER_CHARGES per trip home; scanning a junction also reveals the route
-- there. Re-stabilizer: at the garage, a charge re-rolls a scanned junction's
-- conditions (Rapid Collapse is always removed, it gains stability, corrupted
-- anchors become unstable).
-- Planning: pick any junction you can reach that has a gateway as your
-- destination; travel follows the route there one junction at a time.
--
-- With JUNCTION_MAP_ON_ENTRY (layouts.lua) the map opens when you drive into a
-- junction: the car is held, you pick where to go and off you go (closing it
-- cancels). /junctionmap opens it any time. Drawn like the Fabricator's tree
-- (same menu), bottom to top: the garage at the bottom.
--
-- Loaded by Game.lua; everything here is Game methods.

local MAP_CHILDREN = { 1, 2 }       -- junctions leading on from each junction (the garage: always 2)
-- The map is a fixed set of places (map_sites.lua, about 45, like Pacific
-- Drive's fixed map): a junction only appears on a free site, except a
-- junction's first way on, which always gets a spot. A map far bigger than
-- this (an older save, /revealmap) is cut back to your route.
local MAP_MAX_JUNCTIONS = 70
-- The map picture and where junctions go on it (must match Gui/make_map.py,
-- which also makes the sites, Scripts/map_sites.lua):
-- map units, the garage at 0,0, the zone's core MAP_CORE_RADIUS north of it.
-- A junction sits MAP_DEPTH_STEP closer to the core per depth, so the zone
-- tier rings on the picture line up with the tiers. The picture's path uses the
-- mod's own key ($CONTENT_ + localId from description.json): menus can't
-- expand $CONTENT_DATA.
MAP_IMAGE = "$CONTENT_3c9f5e62-8d1a-4b7e-9a35-6f2d0c4e8b71/Gui/RouteMap.png"
MAP_BOUNDS = { x0 = -1600, x1 = 1600, y0 = -2900, y1 = 300 }
MAP_CORE_RADIUS = 2300
MAP_DEPTH_STEP = 220
local MAP_SITE_REACH = 650          -- a junction takes a free site at most this far from the one before
local MAP_KEEP_APART = 110          -- no junction is put closer than this to another
local MAP_ROAD_CLEARANCE = 70       -- roads bend to pass at least this far from other junctions (map units)
local MAP_BIOME_SPREAD = 0.3        -- chance a junction uses the next depth's biome instead
SCANNER_CHARGES = 1                 -- scans / re-rolls per trip home (Pacific Drive starts you on 1)
ANTENNA_EXTRA_CHARGES = 2           -- more per level of garage antenna (Raise the Antenna, Boost the Signal): 1, 3, 5

-- Scans / re-rolls you get per trip home
function ScannerCharges()
	return SCANNER_CHARGES + ANTENNA_EXTRA_CHARGES * ( g_antennaLevel or 0 )
end
STABILITY_TIME_SCALE = 0.4          -- Pacific Drive's stability times are long; this shortens them
local NO_EXIT_CHANCE = 0.15         -- deeper than junction 1: chance of NO STABLE EXITS
local DEAD_END_CHANCE = 0.06        -- deeper than junction 2: chance of a DEAD END

-- Map names: some come with more (or fewer) buildings, i.e. ruins
local MAP_NAMES = {
	{ name = "BACK ROADS", buildings = 1, weight = 6 },
	{ name = "TOWN CENTER", buildings = 4, weight = 1 },
	{ name = "FARMS", buildings = 2, weight = 2 },
	{ name = "TRAILER PARK", buildings = 3, weight = 1 },
	{ name = "LOGGING CAMP", buildings = 2, weight = 1 },
	{ name = "RESERVOIR", buildings = 1, weight = 1 },
	{ name = "RAIL YARD", buildings = 3, weight = 1 },
	{ name = "QUARRY", buildings = 1, weight = 1 },
}
local LEVELS = { [0] = "NONE", "LOW", "MED", "HIGH", "MAX" }

-- Icons for the map nodes (item icons)
local BIOME_ICONS = {
	garage = "c1d2e3f4-a5b6-4c7d-8e9f-a0b1c2d3e4f5", -- Route Planner
	forest = "968de65c-75f3-471b-954e-6165a4b6d3d6", -- log
	autumn = "f99ebc34-4821-4b39-a625-b839c5802ed5", -- big log
	field = "47ece75a-bfca-4e8a-b618-4f609fcea0da",  -- carrot
	burnt = "267e0c93-62e3-45ad-9470-a14035cb9ca4",  -- ember
	desert = "c56700d9-bbe5-4b17-95ed-cef05bd8be1b", -- sand
}

local function Clamp( v, lo, hi ) return math.max( lo, math.min( hi, v ) ) end

local function Contains( list, value )
	for _, v in ipairs( list or {} ) do
		if v == value then return true end
	end
	return false
end

-- Every road into a junction: one, or more where roads merge on a hand-made
-- map (node.parents; node.parent is the first)
local function ParentsOf( node )
	return node.parents or ( node.parent and { node.parent } ) or {}
end

-- The shortest way along the roads from one junction to another: the ids after
-- `from`, ending with `to` (nil: no way there)
local function RouteTo( map, from, to )
	if from == to or not map.nodes[to] then return nil end
	local back, queue, head = { [from] = from }, { from }, 1
	while queue[head] and back[to] == nil do
		local id = queue[head]
		head = head + 1
		local node = map.nodes[id]
		for _, childId in ipairs( node and node.children or {} ) do
			if back[childId] == nil and map.nodes[childId] then
				back[childId] = id
				queue[#queue + 1] = childId
			end
		end
	end
	if back[to] == nil then return nil end
	local route, walk = {}, to
	while walk ~= from do
		table.insert( route, 1, walk )
		walk = back[walk]
	end
	return route
end

-- Distance from the core for a depth (past the Deep Zone's end it spirals in)
function MapRadius( depth )
	if depth <= 9 then
		return MAP_CORE_RADIUS - MAP_DEPTH_STEP * depth
	end
	return ( MAP_CORE_RADIUS - MAP_DEPTH_STEP * 9 ) * 0.8 ^ ( depth - 9 )
end

-- The depth of the ring nearest a map spot (MapRadius round the core): on a
-- hand-made map a junction's depth, and so its zone tier, is where it sits
function MapDepthAt( x, y )
	local r = math.sqrt( x * x + ( y + MAP_CORE_RADIUS ) ^ 2 )
	local best = 1
	for depth = 2, 14 do
		if math.abs( r - MapRadius( depth ) ) < math.abs( r - MapRadius( best ) ) then best = depth end
	end
	return best
end

-- A junction's number (node.depth, "JCT 3") is how many junctions along the
-- road from the garage it is: that's what difficulty and the quests go by.
-- Its zone (Outer / Mid / Deep: the look, liquids, robots, missiles, when it
-- unlocks) is the ring it sits in on the map: node.zoneDepth, a depth inside
-- that zone's range (ZoneTierOf works on it). NodeZoneDepth gives it.
function ZoneDepthFor( number, x, y )
	local ring = MapDepthAt( x, y )
	local index = #ZONE_TIERS
	for i, tier in ipairs( ZONE_TIERS ) do
		if ring <= tier.last then index = i break end
	end
	local tier = ZONE_TIERS[index]
	if number < tier.first then return tier.first end
	if number > tier.last and index < #ZONE_TIERS then return tier.last end
	return number
end

function NodeZoneDepth( node )
	return node.zoneDepth or node.depth
end


dofile( "$CONTENT_DATA/Scripts/map_sites.lua" )

-- Do segments a-b and c-d cross? (Touching at an end doesn't count)
local function SegmentsCross( a, b, c, d )
	local function side( p, q, r ) return ( q.x - p.x ) * ( r.y - p.y ) - ( q.y - p.y ) * ( r.x - p.x ) end
	return side( c, d, a ) * side( c, d, b ) < 0 and side( a, b, c ) * side( a, b, d ) < 0
end

-- A junction's spot on the map, kept for good. The map is premade: every place
-- a junction can be is a site (map_sites.lua, by depth). A new junction takes
-- the free site of its depth nearest the junction before it whose road there
-- doesn't cross another road. (No free site in reach: a spot towards the core.)
local function PlaceJunction( map, node )
	if node.id == 1 then
		node.mx, node.my = 0, 0
		return
	end
	local parent = map.nodes[node.parent]
	local from = { x = parent and parent.mx or 0, y = parent and parent.my or 0 }
	local used, roads, spots = {}, {}, {}
	for _, other in pairs( map.nodes ) do
		if other.site then used[other.site] = true end
		if other ~= node and other.mx then spots[#spots + 1] = { x = other.mx, y = other.my } end
		local p = other.parent and map.nodes[other.parent]
		if other ~= node and p and p.mx and other.mx then
			roads[#roads + 1] = { { x = p.mx, y = p.my }, { x = other.mx, y = other.my } }
		end
	end
	-- (taken: by its index, or by a junction already standing there; site lists
	-- made again keep old junctions where they were)
	local function crowded( x, y )
		for _, spot in ipairs( spots ) do
			if ( spot.x - x ) ^ 2 + ( spot.y - y ) ^ 2 < MAP_KEEP_APART ^ 2 then return true end
		end
		return false
	end
	local best, bestScore
	for i, site in ipairs( MAP_SITES ) do
		if site.d == node.depth and not used[i] and not crowded( site.x, site.y ) then
			local score = math.sqrt( ( site.x - from.x ) ^ 2 + ( site.y - from.y ) ^ 2 )
			if score <= MAP_SITE_REACH then
				for _, road in ipairs( roads ) do
					if SegmentsCross( from, site, road[1], road[2] ) then score = score + 5000 end
				end
				if not bestScore or score < bestScore then best, bestScore = i, score end
			end
		end
	end
	if best then
		node.site, node.mx, node.my = best, MAP_SITES[best].x, MAP_SITES[best].y
		-- (named after its place, like Pacific Drive's E3, G1...; landmarks keep theirs)
		if MAP_SITES[best].code and not node.landmark then node.code = MAP_SITES[best].code end
		return true
	end
	local dx, dy = 0 - from.x, -MAP_CORE_RADIUS - from.y
	local length = math.max( math.sqrt( dx * dx + dy * dy ), 1 )
	dx, dy = dx / length, dy / length
	-- (a few tries for a spot clear of the others)
	for try = 1, 12 do
		local side = math.random( -160, 160 ) * ( 1 + try * 0.15 )
		node.mx = math.floor( from.x + dx * MAP_DEPTH_STEP - dy * side )
		node.my = math.floor( from.y + dy * MAP_DEPTH_STEP + dx * side )
		if not crowded( node.mx, node.my ) then break end
	end
	return false
end

-- Does a road lead on from this junction into a zone the main quest has opened
-- (g_storyMaxDepth, see Story.lua)? Short of the last open zone depth, yes. At
-- it, only where a hand-made map has a road on to a junction still inside it
-- (the Farmers' Hideout, once the story shows it, sits at the Outer Zone's edge)
local function LeadsOnWithinTiers( node )
	local max = g_storyMaxDepth or math.huge
	if NodeZoneDepth( node ) < max then return true end
	local layout = node.layoutId and g_mapLayout
	for _, entry in ipairs( layout and layout.children[node.layoutId] or {} ) do
		local hidden = entry.landmark and g_hiddenLandmarks and g_hiddenLandmarks[entry.landmark]
		if not hidden and ZoneDepthFor( layout.hops[entry.id] or ( node.depth + 1 ), entry.x, entry.y ) <= max then
			return true
		end
	end
	return false
end

-- Can you drive on from this junction? (Not past the last zone tier the main
-- quest has unlocked: LeadsOnWithinTiers)
function JunctionExitsOpen( node )
	if node == nil then return false end
	if node.id == 1 then return true end
	if not LeadsOnWithinTiers( node ) then return false end
	return node.cleared == true or ( ( node.noExit == true or node.collapsed == true ) and not node.deadEnd )
end

-- No stable exits (no gateway) only where you can drive on: at the edge of the
-- open tiers a junction's exits are locked, so it gets a gateway after all
-- (else you'd be stuck there)
function JunctionNoExit( node )
	return node ~= nil and ( node.noExit == true or node.collapsed == true ) and JunctionExitsOpen( node )
end

-- Seconds of calm before the collapse for a stability percentage
function StabilityToSeconds( stability )
	return ( 16.2 * stability + 150 ) * STABILITY_TIME_SCALE
end


-- Server ------------------------------------------------------------------------

-- Water, oil and chemicals (0-4), one per zone tier (ZONE_TIERS liquid):
-- the Outer Zone has water (rarely more than low), the Mid Zone chemicals, the
-- Deep Zone oil
local function RollLiquids( node )
	local liquid = ZoneTierOf( NodeZoneDepth( node ) ).liquid
	node.water, node.oil, node.chemicals = 0, 0, 0
	if liquid == "water" then
		local r = math.random()
		node.water = ( r < 0.55 and 0 ) or ( r < 0.85 and 1 ) or ( r < 0.97 and 2 ) or 3
	elseif liquid == "chemicals" then
		node.chemicals = math.random( 1, 4 )
	elseif liquid == "oil" then
		node.oil = math.random( 1, 4 )
	end
	-- Flooded (the tier's wetland, now and then in the Outer and Deep Zones):
	-- decided here so the map shows it, as that liquid at MAX (CreateZone floods
	-- the zone for node.wetland)
	local wetland = ZoneTierOf( NodeZoneDepth( node ) ).wetland
	node.wetland = wetland ~= nil and math.random() < ( wetland.chance or 1 )
	if node.wetland then
		node[wetland.liquid or "chemicals"] = 4
	end
end

-- A landmark junction (layouts.lua LANDMARKS) is always the same: safe (the
-- zone never collapses), no gateway, a couple of stable anchors
local function ApplyLandmark( node )
	node.conditions = { "stable" }
	node.stability, node.storm, node.anomalies, node.atmosphere = 100, 0, 0, 0
	node.buildings = 4
	node.water, node.oil, node.chemicals = 0, 0, 0
	node.wetland = false
	node.noExit, node.deadEnd = true, false
	node.anchors = { "stable", "stable" }
end

local function MapHasLandmark( map, name )
	for _, node in pairs( map.nodes ) do
		if node.landmark == name then return true end
	end
	return false
end

-- Everything about a junction that can be re-rolled (and with the zone pool,
-- which world it gets: picked again by sv_zonePoolAssign, zone_pool.lua)
local function RollJunction( node )
	node.poolPicked, node.poolId = nil, nil
	RollLiquids( node )
	-- (conditions picked by hand in the map editor stay the same every time)
	node.conditions = node.fixedConditions and shallowcopy( node.fixedConditions ) or RollConditions( node.depth )
	local depth = node.depth
	node.stability = Clamp( math.floor( 90 - ( depth - 1 ) * 12 + math.random( -15, 10 ) ), 0, 100 )
	node.storm = Clamp( math.floor( depth * 0.6 + math.random( -1, 1 ) + 0.5 ), 0, 4 )
	node.anomalies = Clamp( math.floor( depth * 0.5 + math.random( 0, 1 ) )
		+ ( HasCondition( node.conditions, "minefield" ) and 2 or 0 ) + ( HasCondition( node.conditions, "tornadoes" ) and 2 or 0 ), 0, 4 )
	node.atmosphere = ( HasCondition( node.conditions, "thunderstorm" ) and 4 ) or ( HasCondition( node.conditions, "acidRain" ) and 3 )
		or ( HasCondition( node.conditions, "rain" ) and 2 ) or ( HasCondition( node.conditions, "fog" ) and 1 ) or 0
	if HasCondition( node.conditions, "rapid" ) then node.storm = 4 end
	-- Anchors (the zone spawns exactly these)
	local cost = GatewayCost( depth )
	local count = math.random( math.max( ZONE_ANCHORS_MIN, cost ), ZONE_ANCHORS_MAX )
	if HasCondition( node.conditions, "anchorSurge" ) then
		count = count + CONDITION_ANCHOR_SURGE
	elseif HasCondition( node.conditions, "anchorDrought" ) then
		count = cost
	end
	node.anchors = {}
	for i = 1, count do node.anchors[i] = RollAnchorKind( NodeZoneDepth( node ) ) end
	if node.landmark then
		ApplyLandmark( node )
	end
end

local function PickName()
	local total = 0
	for _, entry in ipairs( MAP_NAMES ) do total = total + entry.weight end
	local r = math.random() * total
	for _, entry in ipairs( MAP_NAMES ) do
		r = r - entry.weight
		if r <= 0 then return entry end
	end
	return MAP_NAMES[1]
end

-- A hand-made map (Tools/map_editor.html writes it): where every junction is
-- and which road leads to it, and anything picked by hand about it (kind,
-- biome, landmark, buildings, name, conditions); the rest is rolled as usual.
-- Only a new save uses it (map.layout); without the file the map is random.
-- Past the layout's last junctions (one with no roads on that isn't a dead
-- end) the map goes on as a random one.
--   { junctions = { { id, parent, also?, x, y, code?, name?, kind?, biome?,
--     landmark?, buildings?, conditions? }, ... } }   (the garage is id 1, at 0,0)
-- also: more junctions with a road into this one (roads merge). A junction
-- reached by several roads is one junction on the map: node.parents.
MAP_LAYOUT_FILE = "$CONTENT_DATA/Maps/map_layout.json"

-- The layout, loaded once: { byId = { [id] = entry }, children = { [parentId] = { entry, ... } } }
local function MapLayout()
	if g_mapLayout == nil then
		g_mapLayout = false
		if sm.json.fileExists( MAP_LAYOUT_FILE ) then
			local data = sm.json.open( MAP_LAYOUT_FILE )
			if type( data ) == "table" and type( data.junctions ) == "table" then
				local layout = { byId = {}, children = {} }
				for _, entry in ipairs( data.junctions ) do
					if entry.id and entry.parent and entry.x and entry.y then
						layout.byId[entry.id] = entry
						-- (its road in, and any more roads merging into it: also)
						local from = { entry.parent }
						for _, other in ipairs( type( entry.also ) == "table" and entry.also or {} ) do from[#from + 1] = other end
						for _, parent in ipairs( from ) do
							layout.children[parent] = layout.children[parent] or {}
							table.insert( layout.children[parent], entry )
						end
					end
				end
				-- How many junctions along the road from the garage each one is
				-- (the shortest way, where roads merge)
				layout.hops = { [1] = 0 }
				local queue, at = { 1 }, 1
				while queue[at] do
					local id = queue[at]
					at = at + 1
					for _, child in ipairs( layout.children[id] or {} ) do
						if layout.hops[child.id] == nil then
							layout.hops[child.id] = layout.hops[id] + 1
							queue[#queue + 1] = child.id
						end
					end
				end
				g_mapLayout = layout
				sm.log.info( "[PacificScrap] Hand-made map loaded:", #data.junctions, "junctions" )
			else
				sm.log.warning( "[PacificScrap] " .. MAP_LAYOUT_FILE .. " has no junctions: using a random map" )
			end
		end
	end
	return g_mapLayout or nil
end

-- The junctions leading on from this one in the hand-made map (nil: not on it,
-- or the layout ends here)
local function LayoutChildren( map, node )
	local layout = map.layout and node.layoutId and MapLayout()
	local list = layout and layout.children[node.layoutId]
	return list and #list > 0 and list or nil
end

-- Is this landmark somewhere in the hand-made map? (Then it only appears there)
local function LayoutHasLandmark( map, name )
	local layout = map.layout and MapLayout()
	for _, entry in pairs( layout and layout.byId or {} ) do
		if entry.landmark == name then return true end
	end
	return false
end

-- A new junction from the hand-made map, leading on from `node`. index: its
-- place among the ways on (the first is never a random dead end).
local function LayoutJunction( map, node, entry, index )
	local depth = MapLayout().hops[entry.id] or ( node.depth + 1 )
	local zoneDepth = ZoneDepthFor( depth, entry.x, entry.y )
	local name = PickName()
	local id = map.nextId
	map.nextId = id + 1
	local child = {
		id = id, depth = depth, zoneDepth = zoneDepth, parent = node.id, parents = { node.id }, children = {}, visited = false, scanned = false, layoutId = entry.id,
		mx = entry.x, my = entry.y,
		biome = ( entry.biome and ZONE_BIOMES[entry.biome] ) and entry.biome or ZoneBiomeForDepth( zoneDepth ),
		code = entry.code or ( string.char( 65 + math.random( 0, 6 ) ) .. depth ),
		mapName = entry.name or name.name,
		buildings = entry.buildings and Clamp( entry.buildings, 0, 4 ) or Clamp( name.buildings + math.random( -1, 1 ), MinBuildingsFor( depth ), 4 ),
	}
	-- (kept as picked: the map's fix-ups for older saves leave these alone)
	child.handBiome = child.biome == entry.biome or nil
	child.handBuildings = entry.buildings ~= nil or nil
	local landmark = entry.landmark and LandmarkByName( entry.landmark )
	if landmark then
		child.landmark = landmark.name
		child.code = entry.code or landmark.code
		child.mapName = entry.name or landmark.title:upper()
		child.scanned = true
	end
	if type( entry.conditions ) == "table" then
		child.fixedConditions = {}
		for _, condition in ipairs( entry.conditions ) do
			if ZONE_CONDITIONS[condition] then child.fixedConditions[#child.fixedConditions + 1] = condition end
		end
		table.sort( child.fixedConditions )
	end
	-- Its kind: picked by hand, or rolled as on a random map (but never a dead
	-- end where the layout goes on beyond it)
	local kind = entry.kind or "random"
	if kind == "random" then
		local goesOn = MapLayout().children[entry.id] ~= nil
		child.deadEnd = not goesOn and index > 1 and depth >= 3 and math.random() < DEAD_END_CHANCE
		child.noExit = child.deadEnd or ( depth >= 2 and math.random() < NO_EXIT_CHANCE )
	else
		child.deadEnd = kind == "deadEnd"
		child.noExit = kind ~= "normal"
		-- (picked as collapsed by hand: it always is; others take turns, see
		-- sv_jmRollCollapses)
		child.collapsed = kind == "collapsed" or nil
		child.handCollapsed = child.collapsed
	end
	RollJunction( child )
	return child
end

function Game.sv_jmMap( self )
	local map = self.sv.saved.map
	if not map then
		map = { nodes = {}, nextId = 2, current = 1 }
		map.nodes[1] = { id = 1, depth = 0, biome = "garage", conditions = {}, children = {}, visited = true, scanned = true }
		-- A new save: the hand-made map if there is one (MAP_LAYOUT_FILE)
		if MapLayout() then
			map.layout = true
			map.nodes[1].layoutId = 1
		end
		self.sv.saved.map = map
	end
	-- Hand-made map: junctions follow the layout file if it was moved about since
	-- (their spot, and the depth that goes with it)
	if map.layout and MapLayout() then
		for _, node in pairs( map.nodes ) do
			local entry = node.layoutId and node.layoutId ~= 1 and MapLayout().byId[node.layoutId]
			if entry then
				node.mx, node.my = entry.x, entry.y
				node.depth = MapLayout().hops[entry.id] or node.depth
				node.zoneDepth = ZoneDepthFor( node.depth, entry.x, entry.y )
			end
		end
	end
	map.charges = map.charges or ScannerCharges()
	-- Maps from before unlocking: junctions you'd been to count as escaped
	if not map.unlocking then
		map.unlocking = true
		for _, node in pairs( map.nodes ) do
			if node.depth > 0 and node.visited then node.cleared = true end
		end
	end
	-- Maps from when a junction rolled collapsed once, for good: those come
	-- back (their no-exit rolled again, collapsing forced it on); which ones are
	-- collapsed is now picked on every return home (sv_jmRollCollapses)
	if not map.collapseTurns then
		map.collapseTurns = true
		for _, node in pairs( map.nodes ) do
			local entry = map.layout and node.layoutId and MapLayout() and MapLayout().byId[node.layoutId]
			if entry and entry.kind == "collapsed" then
				node.handCollapsed = true
			elseif node.collapsed and node.id ~= map.current then
				node.collapsed = nil
				node.noExit = node.deadEnd or ( node.depth >= 2 and math.random() < NO_EXIT_CHANCE )
			end
		end
	end
	-- Older maps: spots on the map (shallowest first, so the ones before are placed)
	local unplaced = {}
	for _, node in pairs( map.nodes ) do
		if node.mx == nil then unplaced[#unplaced + 1] = node end
	end
	table.sort( unplaced, function( a, b ) return a.depth < b.depth or ( a.depth == b.depth and a.id < b.id ) end )
	for _, node in ipairs( unplaced ) do
		local keep = map.nodes[node.id]
		map.nodes[node.id] = nil -- (placed as if new)
		PlaceJunction( map, node )
		map.nodes[node.id] = keep
	end
	-- Far too many junctions (an older save, /revealmap): back to the garage and
	-- the route to where you are; the map grows again from there
	local total = 0
	for _ in pairs( map.nodes ) do total = total + 1 end
	if total > MAP_MAX_JUNCTIONS then
		local keep = {}
		local walk = map.nodes[map.current]
		while walk do
			keep[walk.id] = true
			walk = walk.parent and map.nodes[walk.parent]
		end
		keep[1] = true
		for id in pairs( map.nodes ) do
			if not keep[id] then map.nodes[id] = nil end
		end
		for _, node in pairs( map.nodes ) do
			local kept = {}
			for _, child in ipairs( node.children or {} ) do
				if map.nodes[child] then kept[#kept + 1] = child end
			end
			node.children = kept
		end
		map.destination = nil
		sm.log.info( "[PacificScrap] Map cut back from", total, "junctions" )
	end
	-- A landmark whose depth changed (layouts.lua): off the map with what's
	-- beyond it (unless you're on that branch); it comes back where it belongs
	local function removeBranch( id )
		local node = map.nodes[id]
		if not node then return end
		for _, child in ipairs( node.children or {} ) do removeBranch( child ) end
		map.nodes[id] = nil
		if map.destination == id then map.destination = nil end
	end
	local onRoute = {} -- (where you are and the junctions that led there)
	local walk = map.nodes[map.current]
	while walk do
		onRoute[walk.id] = true
		walk = walk.parent and map.nodes[walk.parent]
	end
	for id, node in pairs( map.nodes ) do
		local landmark = node.landmark and LandmarkByName( node.landmark )
		-- (on a hand-made map a landmark goes wherever it was put; one the story
		-- keeps hidden comes off until it's time: g_hiddenLandmarks, Story.lua)
		local hidden = landmark and g_hiddenLandmarks and g_hiddenLandmarks[landmark.name]
		if landmark and not onRoute[id] and ( hidden or ( node.depth ~= landmark.depth and not node.layoutId ) ) then
			local parent = map.nodes[node.parent or -1]
			if parent then
				for i, child in ipairs( parent.children ) do
					if child == id then table.remove( parent.children, i ) break end
				end
			end
			removeBranch( id )
		end
	end
	-- Older maps: fill in what's missing
	for _, node in pairs( map.nodes ) do
		-- (each tier has one biome now: junctions rolled under older rules follow it)
		if node.depth > 0 and not node.landmark and not node.handBiome and not ZoneBiomeAllowed( NodeZoneDepth( node ), node.biome ) then
			node.biome = ZoneBiomeForDepth( NodeZoneDepth( node ) )
		end
		-- (early junctions rolled before they got more buildings)
		if node.depth > 0 and not node.landmark and not node.handBuildings and node.buildings and node.buildings < MinBuildingsFor( node.depth ) then
			node.buildings = MinBuildingsFor( node.depth )
		end
		if node.depth > 0 and node.stability ~= nil and node.water == nil then
			RollLiquids( node )
		end
		if node.depth > 0 and node.stability == nil then
			node.code = node.code or ( string.char( 65 + math.random( 0, 6 ) ) .. node.depth )
			local entry = PickName()
			node.mapName, node.buildings = node.mapName or entry.name, node.buildings or entry.buildings
			RollJunction( node )
		end
	end
	self:sv_jmGrowOpen()
	return map
end

-- Make sure the map reaches `levels` junctions ahead of this one
function Game.sv_jmGrow( self, node, levels )
	if levels <= 0 or node.deadEnd then
		return
	end
	local map = self.sv.saved.map
	node.children = node.children or {}
	-- Hand-made map: the ways on are the layout's (any it doesn't have yet,
	-- e.g. trimmed off the map since: they come back the same)
	local planned = LayoutChildren( map, node )
	if planned then
		local have = {}
		for _, childId in ipairs( node.children ) do
			local child = map.nodes[childId]
			if child and child.layoutId then have[child.layoutId] = true end
		end
		for index, entry in ipairs( planned ) do
			-- (a landmark the story keeps hidden isn't on the map yet: g_hiddenLandmarks)
			local hidden = entry.landmark and g_hiddenLandmarks and g_hiddenLandmarks[entry.landmark]
			if not have[entry.id] and not hidden then
				-- (roads merge: already on the map from another road, it's the same junction)
				local child
				for _, other in pairs( map.nodes ) do
					if other.layoutId == entry.id then child = other break end
				end
				if child then
					child.parents = ParentsOf( child )
					if not Contains( child.parents, node.id ) then table.insert( child.parents, node.id ) end
				else
					child = LayoutJunction( map, node, entry, index )
					map.nodes[child.id] = child
				end
				table.insert( node.children, child.id )
			end
		end
	end
	-- (landmarks are extra: they don't count as the ways on)
	local ways = 0
	for _, childId in ipairs( node.children ) do
		local child = map.nodes[childId]
		if child and not child.landmark then ways = ways + 1 end
	end
	if ways < MAP_CHILDREN[1] and not planned then
		local depth = node.depth + 1
		local count = node.id == 1 and 2 or math.random( MAP_CHILDREN[1], MAP_CHILDREN[2] )
		for index = ways + 1, count do
			local biome = ZoneBiomeForDepth( depth )
			-- (sometimes the next depth's biome, but never another tier's)
			if math.random() < MAP_BIOME_SPREAD and ZoneTierOf( depth + 1 ) == ZoneTierOf( depth ) then
				biome = ZoneBiomeForDepth( depth + 1 )
			end
			local entry = PickName()
			local id = map.nextId
			map.nextId = id + 1
			local child = {
				id = id, depth = depth, biome = biome, parent = node.id, children = {}, visited = false, scanned = false,
				code = string.char( 65 + math.random( 0, 6 ) ) .. depth, mapName = entry.name,
				buildings = Clamp( entry.buildings + math.random( -1, 1 ), MinBuildingsFor( depth ), 4 ),
			}
			-- (the first way on is never a dead end, or you'd be stuck)
			child.deadEnd = index > 1 and depth >= 3 and math.random() < DEAD_END_CHANCE
			child.noExit = child.deadEnd or ( depth >= 2 and math.random() < NO_EXIT_CHANCE )
			-- (collapsed or not is decided each time you come home: sv_jmRollCollapses)
			RollJunction( child )
			local onSite = PlaceJunction( map, child )
			if onSite or index == 1 then
				map.nodes[id] = child
				table.insert( node.children, id )
			end
		end
	end
	-- Landmarks: one of each on the map, as an extra branch off a junction one
	-- shallower than the landmark
	for _, landmark in ipairs( LANDMARKS ) do
		-- (on a hand-made map that has it, only where it was put)
		local hidden = g_hiddenLandmarks and g_hiddenLandmarks[landmark.name]
		if landmark.depth == node.depth + 1 and not hidden and not MapHasLandmark( map, landmark.name ) and not LayoutHasLandmark( map, landmark.name ) then
			AddLandmarkJunction( map, node, landmark )
		end
	end
	for _, childId in ipairs( node.children ) do
		local child = map.nodes[childId]
		if child then self:sv_jmGrow( child, levels - 1 ) end
	end
end

-- A landmark junction leading off `node` (a random map's landmarks)
function AddLandmarkJunction( map, node, landmark )
	local id = map.nextId
	map.nextId = id + 1
	local child = {
		id = id, depth = landmark.depth, biome = ZoneBiomeForDepth( landmark.depth ), parent = node.id, children = {},
		visited = false, scanned = true, code = landmark.code, mapName = landmark.title:upper(), landmark = landmark.name,
	}
	RollJunction( child )
	PlaceJunction( map, child )
	map.nodes[id] = child
	table.insert( node.children, id )
	return child
end

-- A landmark the story has revealed is on the map straight away, even when the
-- junctions before it haven't been explored (shown locked until you can get
-- there): off a junction one shallower on a random map, or where it was put on
-- a hand-made one, with the junctions on the way to it
local function EnsureRevealedLandmarks( map )
	for _, landmark in ipairs( LANDMARKS ) do
		local hidden = g_hiddenLandmarks and g_hiddenLandmarks[landmark.name]
		if not hidden and not MapHasLandmark( map, landmark.name ) then
			local layout = map.layout and MapLayout()
			local entry
			for _, e in pairs( layout and layout.byId or {} ) do
				if e.landmark == landmark.name then entry = e break end
			end
			if entry then
				-- (the layout's chain from the garage to it; made from the last one on the map)
				local chain, walk = {}, entry
				while walk and walk.id ~= 1 do
					table.insert( chain, 1, walk )
					walk = layout.byId[walk.parent]
				end
				local onMap = {}
				for _, node in pairs( map.nodes ) do
					if node.layoutId then onMap[node.layoutId] = node end
				end
				local parent = map.nodes[1]
				for index, e in ipairs( chain ) do
					if onMap[e.id] then
						parent = onMap[e.id]
					else
						local child = LayoutJunction( map, parent, e, index )
						map.nodes[child.id] = child
						table.insert( parent.children, child.id )
						parent = child
					end
				end
			else
				-- (off a junction one shallower: the first ways out of the garage are always there)
				local from
				for _, node in pairs( map.nodes ) do
					if node.depth == landmark.depth - 1 and not node.landmark and not node.deadEnd
						and ( not from or node.id < from.id ) then
						from = node
					end
				end
				if from then AddLandmarkJunction( map, from, landmark ) end
			end
		end
	end
end

-- Is `id` somewhere ahead of `from` (within the map)?
local function IsAhead( map, from, id )
	return RouteTo( map, from, id ) ~= nil
end

-- Not past the zone tiers the main quest has opened (on a hand-made map a road
-- can lead straight into the next tier)
local function WithinTiers( node )
	return NodeZoneDepth( node ) <= ( g_storyMaxDepth or math.huge )
end

-- Can you get there: some way from the garage where every junction on the
-- way has open exits
local function Reachable( map, id )
	local node = map.nodes[id]
	if not node or not WithinTiers( node ) then return false end
	if id == 1 then return true end
	local seen, queue, head = { [1] = true }, { 1 }, 1
	while queue[head] do
		local here = map.nodes[queue[head]]
		head = head + 1
		if here and JunctionExitsOpen( here ) then
			for _, childId in ipairs( here.children or {} ) do
				if childId == id then return true end
				local child = map.nodes[childId]
				if child and not seen[childId] and WithinTiers( child ) then
					seen[childId] = true
					queue[#queue + 1] = childId
				end
			end
		end
	end
	return false
end

-- The junctions behind this one: every road back to the garage
local function Ancestors( map, id )
	local found, queue, head = { [id] = true }, { id }, 1
	while queue[head] do
		local node = map.nodes[queue[head]]
		head = head + 1
		for _, parent in ipairs( node and ParentsOf( node ) or {} ) do
			if not found[parent] then
				found[parent] = true
				queue[#queue + 1] = parent
			end
		end
	end
	return found
end

-- Revealed landmarks and every junction on the way to them (kept on the map)
local function RevealedLandmarkRoutes( map )
	local keep = {}
	for id, node in pairs( map.nodes ) do
		if node.landmark and not ( g_hiddenLandmarks and g_hiddenLandmarks[node.landmark] ) then
			for ancestor in pairs( Ancestors( map, id ) ) do keep[ancestor] = true end
		end
	end
	return keep
end

-- A landmark the story has told you about (the Farmers' Hideout, once the
-- farmers have called): the junction right before it counts as escaped, so
-- its exits are open (the ones before that you open as usual)
local function OpenRevealedLandmarkRoutes( map )
	for name in pairs( g_storyRevealedLandmarks or {} ) do
		local layout = map.layout and MapLayout()
		local entry
		for _, e in pairs( layout and layout.byId or {} ) do
			if e.landmark == name then entry = e break end
		end
		-- (the junctions with a road into it: the layout's, or the map's)
		local before = {}
		if entry then
			before[entry.parent] = true
			for _, other in ipairs( type( entry.also ) == "table" and entry.also or {} ) do before[other] = true end
		end
		for id, node in pairs( map.nodes ) do
			if not entry and node.landmark == name then
				for _, parent in ipairs( ParentsOf( node ) ) do
					local p = map.nodes[parent]
					if p and p.id ~= 1 and not p.cleared then
						p.cleared = true
						sm.log.info( "[PacificScrap] Junction", p.id, "opened: it's right before", name )
					end
				end
			elseif entry and node.layoutId and node.layoutId ~= 1 and before[node.layoutId] and not node.cleared then
				node.cleared = true
				sm.log.info( "[PacificScrap] Junction", id, "opened: it's right before", name )
			end
		end
	end
end

-- Every reachable junction with open exits leads on (one level), and so does
-- where you are (to show what's behind its locked exits). Pass-through
-- junctions that appear lead on too, so repeat until nothing new grows.
function Game.sv_jmGrowOpen( self )
	local map = self.sv.saved.map
	-- (the way to a landmark the story has shown you is open: put on the map first)
	EnsureRevealedLandmarks( map )
	OpenRevealedLandmarkRoutes( map )
	for _ = 1, 10 do
		local before = map.nextId
		local grow = {}
		for id, node in pairs( map.nodes ) do
			if id == map.current or ( JunctionExitsOpen( node ) and Reachable( map, id ) ) then
				grow[#grow + 1] = node
			end
		end
		for _, node in ipairs( grow ) do
			self:sv_jmGrow( node, 1 )
		end
		if map.nextId == before then break end
	end
	EnsureRevealedLandmarks( map )
	OpenRevealedLandmarkRoutes( map )
	-- (junctions rolled since pick their zone world: zone_pool.lua)
	self:sv_zonePoolAssign()
end

-- The next junction on the way to the destination (or the first one leading
-- on); nothing while this junction's exits are locked
function Game.sv_jmDestination( self )
	local map = self:sv_jmMap()
	local current = map.nodes[map.current]
	if not JunctionExitsOpen( current ) then
		return nil
	end
	local route = map.destination and map.nodes[map.destination] and WithinTiers( map.nodes[map.destination] )
		and RouteTo( map, map.current, map.destination )
	if route then
		return map.nodes[route[1]]
	end
	for _, childId in ipairs( current.children ) do
		local child = map.nodes[childId]
		if child and WithinTiers( child ) then return child end
	end
	return nil
end

-- Arrived at a junction: it's visited, the map grows from here
function Game.sv_jmArrive( self, id )
	local map = self:sv_jmMap()
	local node = map.nodes[id]
	if not node then return end
	map.current = id
	-- (the way you've actually come this trip: roads can merge, so it's kept)
	map.trail = map.trail or { 1 }
	if map.trail[#map.trail] ~= id then table.insert( map.trail, id ) end
	if map.destination == id or not IsAhead( map, id, map.destination or -1 ) then
		map.destination = nil
	end
	node.visited = true
	node.scanned = true
	if node.landmark then
		self:sv_storyOnLandmark( node.landmark )
	end
	self:sv_jmPrune()
	self:sv_jmGrowOpen()
	self:sv_saveGame()
end

-- Keep the garage, the route that led to where you are, what you can reach and
-- what's just behind the locked exits where you are; nothing else
function Game.sv_jmPrune( self )
	local map = self.sv.saved.map
	local route = Ancestors( map, map.current )
	local landmarks = RevealedLandmarkRoutes( map )
	local keep = {}
	for id, node in pairs( map.nodes ) do
		keep[id] = id == 1 or route[id] or landmarks[id] or Contains( ParentsOf( node ), map.current ) or Reachable( map, id )
	end
	for id, node in pairs( map.nodes ) do
		if not keep[id] then
			map.nodes[id] = nil
		end
	end
	for _, node in pairs( map.nodes ) do
		local kept = {}
		for _, child in ipairs( node.children or {} ) do
			if map.nodes[child] then kept[#kept + 1] = child end
		end
		node.children = kept
		if node.parents then
			local parents = {}
			for _, parent in ipairs( node.parents ) do
				if map.nodes[parent] then parents[#parents + 1] = parent end
			end
			node.parents = parents
			node.parent = parents[1] or node.parent
		end
	end
end

-- Back at the garage: start from the bottom, conditions re-roll, charges refill.
-- escaped: came home through a gateway, which unlocks that junction's exits
function Game.sv_jmReturnHome( self, escaped )
	local map = self:sv_jmMap()
	local from = map.nodes[map.current]
	if escaped and from and from.id ~= 1 and not from.cleared then
		from.cleared = true
		sm.log.info( "[PacificScrap] Junction", from.id, "escaped: its exits are open now" )
	end
	map.current = 1
	map.destination = nil
	map.trail = { 1 }
	map.charges = ScannerCharges()
	self:sv_jmPrune()
	for id, node in pairs( map.nodes ) do
		if id ~= 1 then
			RollJunction( node )
			node.scanned = node.landmark ~= nil -- conditions changed: scan again (landmarks are always known)
		end
	end
	-- After a failed run (towed home): one of the junctions out of the garage is
	-- a calm one, Perpetual Stability (already scanned, so you can see it), as
	-- for your very first trip
	if not escaped then
		local first = {}
		for _, childId in ipairs( map.nodes[1].children or {} ) do
			local child = map.nodes[childId]
			if child and not child.landmark then first[#first + 1] = child end
		end
		local calm = first[math.random( math.max( #first, 1 ) )]
		if calm then
			removeFromArray( calm.conditions, function( name ) return name == "unstable" or name == "rapid" end )
			if not HasCondition( calm.conditions, "stable" ) then
				table.insert( calm.conditions, "stable" )
				table.sort( calm.conditions )
			end
			calm.scanned = true
			sm.log.info( "[PacificScrap] After a failed run: junction", calm.id, "is calm" )
		end
	end
	self:sv_jmGrowOpen()
	self:sv_jmRollCollapses()
	self:sv_saveGame()
end

-- Every return home the zone shifts: the junctions that were collapsed come
-- back, and COLLAPSED_PER_RETURN others collapse, out of the furthest
-- COLLAPSED_FURTHEST rings on the map past the Outer Zone. The Outer Zone
-- mostly has none: only now and then (COLLAPSED_OUTER_CHANCE) one, out of its
-- furthest rings. Never junction 1, a landmark or a dead end; hand-picked
-- collapsed ones on a hand-made map always stay.
function Game.sv_jmRollCollapses( self )
	local map = self.sv.saved.map
	local function isOuter( node ) return ZoneTierOf( NodeZoneDepth( node ) ).name == "outer" end
	local deepest, deepestOuter = 0, 0
	for _, node in pairs( map.nodes ) do
		if not node.handCollapsed then node.collapsed = nil end
		if isOuter( node ) then
			deepestOuter = math.max( deepestOuter, node.depth )
		else
			deepest = math.max( deepest, node.depth )
		end
	end
	local candidates, outer = {}, {}
	for id, node in pairs( map.nodes ) do
		if id ~= 1 and id ~= map.current and node.depth >= 2 and not node.landmark and not node.deadEnd and not node.handCollapsed then
			if isOuter( node ) then
				if node.depth > deepestOuter - COLLAPSED_FURTHEST then outer[#outer + 1] = node end
			elseif node.depth > deepest - COLLAPSED_FURTHEST then
				candidates[#candidates + 1] = node
			end
		end
	end
	-- (same order every time, then shuffled)
	local function byId( a, b ) return a.id < b.id end
	table.sort( candidates, byId )
	table.sort( outer, byId )
	local function collapse( list, count )
		for i = 1, math.min( count, #list ) do
			local pick = math.random( i, #list )
			list[i], list[pick] = list[pick], list[i]
			list[i].collapsed = true
			sm.log.info( "[PacificScrap] Junction", list[i].id, "(JCT " .. list[i].depth .. ") has collapsed" )
		end
	end
	collapse( candidates, math.random( COLLAPSED_PER_RETURN[1], COLLAPSED_PER_RETURN[2] ) )
	if math.random() < COLLAPSED_OUTER_CHANCE then
		collapse( outer, 1 )
	end
end

-- The junction being travelled to, for the zone's settings
function Game.sv_jmNode( self, id )
	return self:sv_jmMap().nodes[id]
end

-- Drove into a junction: hold the car and let them pick on the map (no fade:
-- it would cover the map)
function Game.sv_jmBeginChoice( self, choice, world, position )
	if self.sv.jmChoice then
		return
	end
	choice.hold = { world = world, position = position }
	self.sv.jmChoice = choice
	self:sv_jmSend( choice.player, "travel" )
end

function Game.sv_n_jmTravel( self, params, player )
	local choice = self.sv.jmChoice
	if not choice or choice.player ~= player then
		return
	end
	local map = self:sv_jmMap()
	if not JunctionExitsOpen( map.nodes[map.current] ) then
		return
	end
	-- Keep a planned destination further along this way; otherwise this is it
	local onRoute = map.destination and ( map.destination == params.id or IsAhead( map, params.id, map.destination ) )
	if IsAhead( map, map.current, params.id ) and not onRoute then
		map.destination = params.id
	end
	self.sv.jmChoice = nil
	if choice.kind == "garage" then
		self:sv_e_garageJunction( { player = player, chosen = true } )
	else
		choice.params.chosen = true
		self:sv_e_zoneJunction( choice.params )
	end
end

function Game.sv_n_jmCancel( self, _, player )
	local choice = self.sv.jmChoice
	if choice and choice.player == player then
		self.sv.jmChoice = nil
		self.sv.junctionCooldownTick = sm.game.getCurrentTick() + 40 * 5 -- time to drive off
	end
end

-- Cheat (/revealmap): every junction on the map is scanned and its exits
-- unlocked (as if escaped), so the map grows a level; again for the next.
-- (The zone tiers still stop it where the main quest has got to: /skipquest)
function Game.sv_jmReveal( self, player )
	local map = self:sv_jmMap()
	for id, node in pairs( map.nodes ) do
		node.scanned = true
		if id ~= 1 and not node.deadEnd then node.cleared = true end
	end
	self:sv_jmGrowOpen()
	for _, node in pairs( map.nodes ) do node.scanned = true end
	self:sv_saveGame()
	local count = 0
	for _ in pairs( map.nodes ) do count = count + 1 end
	sm.log.info( "[PacificScrap] Cheat: map revealed,", count, "junctions" )
	self:sv_message( player, "Map revealed: " .. count .. " junctions. Again for another level." )
end

-- Scan a junction ahead (and the route to it)
function Game.sv_n_jmScan( self, params, player )
	local map = self:sv_jmMap()
	local node = map.nodes[params.id]
	if self:sv_jmAtGarage() and node and not node.scanned and map.charges > 0 and IsAhead( map, map.current, params.id ) and Reachable( map, params.id ) then
		map.charges = map.charges - 1
		for _, id in ipairs( RouteTo( map, map.current, params.id ) or {} ) do
			map.nodes[id].scanned = true
		end
		self:sv_saveGame()
	end
	self:sv_jmSend( player, "planner" )
end

-- Planning happens in the garage, between trips
function Game.sv_jmAtGarage( self )
	return self:sv_jmMap().current == 1 and self.sv.run.state == "idle"
end

function Game.sv_e_openRoutePlanner( self, params )
	self:sv_jmSend( params.player, "planner" )
end

-- Re-stabilizer (garage only): re-roll a scanned junction's conditions
function Game.sv_n_jmReroll( self, params, player )
	local map = self:sv_jmMap()
	local node = map.nodes[params.id]
	if self:sv_jmAtGarage() and node and node.scanned and not node.visited and map.charges > 0 then
		map.charges = map.charges - 1
		RollJunction( node )
		removeFromArray( node.conditions, function( name ) return name == "rapid" end )
		node.stability = Clamp( node.stability + 20, 0, 100 )
		node.storm = math.max( node.storm - 1, 0 )
		for i, kind in ipairs( node.anchors ) do
			if kind == "corrupted" then node.anchors[i] = "unstable" end
		end
		self:sv_zonePoolAssign()
		self:sv_saveGame()
	end
	self:sv_jmSend( player, "planner" )
end

-- mode: "planner" (Route Planner), "travel" (picking the next junction) or
-- "view" (/junctionmap)
function Game.sv_jmSend( self, player, mode )
	local map = self:sv_jmMap()
	local nodes = {}
	for _, node in pairs( map.nodes ) do
		local known = node.scanned
		nodes[#nodes + 1] = {
			id = node.id, depth = node.depth, biome = node.biome, parent = node.parent, parents = ParentsOf( node ), visited = node.visited,
			cleared = node.cleared, open = JunctionExitsOpen( node ), reachable = Reachable( map, node.id ),
			mx = node.mx, my = node.my, site = node.site, landmark = node.landmark,
			zone = NodeZoneDepth( node ),
			tierLocked = NodeZoneDepth( node ) > ( g_storyMaxDepth or math.huge ), tierEdge = NodeZoneDepth( node ) == g_storyMaxDepth,
			scanned = known, code = node.code, mapName = node.mapName,
			cost = node.depth > 0 and GatewayCost( node.depth ) or 0,
			noExit = known and JunctionNoExit( node ) or nil, deadEnd = known and node.deadEnd or nil,
			collapsed = node.collapsed or nil, -- (always shown, scanned or not: you never stumble into one)
			conditions = known and node.conditions or nil, stability = known and node.stability or nil,
			storm = known and node.storm or nil, anomalies = known and node.anomalies or nil,
			atmosphere = known and node.atmosphere or nil, buildings = known and node.buildings or nil,
			anchors = known and node.anchors or nil,
			water = known and node.water or nil, oil = known and node.oil or nil, chemicals = known and node.chemicals or nil,
		}
	end
	local state = self.sv.run.state
	local next = self:sv_jmDestination()
	-- The way you came (older saves: back along the first roads) and the way to the destination
	local trail = map.trail
	if not trail or trail[#trail] ~= map.current then
		trail = {}
		local walk = map.nodes[map.current]
		while walk do
			table.insert( trail, 1, walk.id )
			walk = walk.parent and map.nodes[walk.parent]
		end
	end
	local route = map.destination and RouteTo( map, map.current, map.destination ) or nil
	self.network:sendToClient( player, "cl_n_junctionMap", {
		nodes = nodes, current = map.current, destination = map.destination, trail = trail, route = route,
		nextHop = next and next.id, charges = map.charges, maxCharges = ScannerCharges(),
		atGarage = map.current == 1 and state == "idle", mode = mode or "view",
	} )
end

function Game.sv_n_requestJunctionMap( self, _, player )
	self:sv_jmSend( player, "view" )
end

function Game.sv_n_jmSetDestination( self, params, player )
	local map = self:sv_jmMap()
	local node = map.nodes[params.id]
	-- (any junction you can get to, gateway or not: you drive on through ones without)
	if self:sv_jmAtGarage() and node and IsAhead( map, map.current, params.id ) and Reachable( map, params.id ) then
		map.destination = params.id
		self:sv_saveGame()
		sm.log.info( "[PacificScrap] Destination: junction", params.id )
	end
	self:sv_jmSend( player, "planner" )
end


-- Client ------------------------------------------------------------------------

local MAP_PAD = 12
local MAP_ROW = 104       -- between depths
local MAP_COLUMN = 92     -- between neighbours
local MAP_NODE = 74
local MAP_LINE = 3
local MAP_ZOOM_MIN = 0.2  -- mouse wheel zoom range (1 = full size)
local MAP_ZOOM_START = 0.6
local MAP_ZOOM_CELLS_X = 24 -- the wheel zooms towards the mouse to within one of these cells
local MAP_ZOOM_CELLS_Y = 12
local MAP_GLIDE = 8.0     -- how fast the view glides to a picked junction
local MAP_ZOOM_MAX = 1.6
local MAP_ZOOM_STEP = 1.15
local METER_ROW = 15      -- Route Analysis bars: row height
local METER_COLUMN = 190  -- two columns of four rows in the map panel's header

local MapColours = {
	current = "1 1 1 1",              -- white: where you are
	destination = "1 0.83 0.29 1",    -- yellow: your destination / the route there
	choice = "0.96 0.45 0.17 1",      -- orange: ahead, scanned
	visited = "0.64 0.80 0.27 1",     -- green: been there
	unknown = "0.45 0.45 0.45 1",     -- grey: not scanned
	locked = "0.25 0.25 0.25 1",      -- dark: behind exits you haven't unlocked
	danger = "0.85 0.15 0.15 1",      -- red: dead end
	landmark = "0.35 0.85 0.75 1",    -- teal: a landmark (packing station, the hideout)
}

-- Landmark icons (item icons)
local LANDMARK_ICONS = {
	hideout = "cb7305b2-d8b5-4302-aff3-6cdd9212ca64", -- sunshake
	veg = "9cd8288c-5a19-479f-af47-9eb55230ade2",     -- carrot crate
	fruit = "0bc74539-df8a-47c7-aad8-d55d809a01e4",   -- banana crate
}
local function NodeIcon( n )
	return ( n.landmark and LANDMARK_ICONS[n.landmark] ) or BIOME_ICONS[n.biome] or BIOME_ICONS.forest
end

-- The junction's icon on the map: one of the beacon icons (the compass's,
-- BeaconCompassIconMap: 2 !, 3 ?, 4 car, 5 house, 22 drop, 23 X; landmarks use
-- their beaconIcon from LANDMARKS)
local MAP_ICON = { garage = 5, junction = 4, unknown = 3, noExit = 2, deadEnd = 23, collapsed = 22 }
function NodeBeaconIcon( n )
	if n.depth == 0 then return MAP_ICON.garage end
	local landmark = n.landmark and LandmarkByName( n.landmark )
	if landmark then return landmark.beaconIcon or MAP_ICON.junction end
	if not n.scanned then return MAP_ICON.unknown end
	if n.deadEnd then return MAP_ICON.deadEnd end
	if n.collapsed then return MAP_ICON.collapsed end
	if n.noExit then return MAP_ICON.noExit end
	return MAP_ICON.junction
end

local function MapRect( name, x, y, width, height, colour, alpha )
	return {
		Name = name, Type = "Widget", Skin = "WhiteSkin", Colour = colour, Alpha = alpha or 1,
		InheritsAlpha = false, NeedKey = false, NeedMouse = false, Childs = {},
		x = math.floor( x ), y = math.floor( y ), width = math.max( math.floor( width ), 1 ), height = math.max( math.floor( height ), 1 ),
	}
end

local function MapScale( widget, scale )
	if scale == 1 then return end
	for _, key in ipairs( { "x", "y", "width", "height" } ) do
		if type( widget[key] ) == "number" then
			widget[key] = math.floor( widget[key] * scale + 0.5 )
		end
	end
	for _, child in ipairs( widget.Childs or {} ) do
		MapScale( child, scale )
	end
end

local function RenameCallbacks( widget, names )
	for key, value in pairs( widget ) do
		if type( value ) == "string" and key:sub( 1, 2 ) == "on" then
			widget[key] = names[value] or "cl_jmNothing"
		end
	end
	for _, child in ipairs( widget.Childs or {} ) do
		RenameCallbacks( child, names )
	end
end

local function Meter( value, max )
	local filled = math.floor( ( value or 0 ) / max * 10 + 0.5 )
	return string.rep( "|", filled ) .. "#555555" .. string.rep( "|", 10 - filled )
end

-- The menu: the Fabricator's, retitled, without its tabs and currency
-- (files can only be loaded at the top level of a script, not inside functions)
dofile( "$CONTENT_DATA/Scripts/wide_gui.lua" )
local MapSlotFile = dofile( "$SURVIVAL_DATA/Gui/JsonGuis/ItemSlotSchematic.gui" )
local MapGuiFile = dofile( "$CONTENT_DATA/Gui/JsonGuis/Fabricator.gui" )
local MapSlot, MapSlotRoot, MapSlotImage
local MapGui
local function BuildMapGui()
	if MapGui then return MapGui end
	MapSlot = DeepCopy( MapSlotFile )
	MapSlotRoot = FindWidget( MapSlot, "Item" )
	MapSlotImage = FindWidget( MapSlot, "Image" )
	removeFromArray( MapSlot.Childs, function( widget ) return widget.Type == "EffectBox" or widget.Name == "KeyItem" end )
	MapSlot.onMouseWheel = "cl_jmWheel"
	for _, child in ipairs( MapSlot.Childs ) do child.onMouseWheel = "cl_jmWheel" end
	-- Dragging works from on top of a junction too (a click only selects it if
	-- the mouse didn't move, see cl_jmSelectNode)
	MapSlotRoot.onPressed = "cl_jmDragStart"
	MapSlotRoot.onDrag = "cl_jmDragMove"
	MapSlotRoot.onReleased = "cl_jmDragEnd"

	local gui = {}
	gui.json = DeepCopy( MapGuiFile )
	RenameCallbacks( gui.json, { cl_onTradeClick = "cl_jmMainButton", cl_onClose = "cl_jmOnClose", cl_selectTab = "cl_jmTab" } )
	gui.Main = FindWidget( gui.json, "MainPanel" )
	gui.Side = FindWidget( gui.json, "TradePanel" )
	gui.MainTitle = FindWidget( gui.Main, "Title" )
	FindWidget( gui.Main, "Currency" ).Visible = false
	-- Tabs (the Fabricator's tab bar): the map, and the logbook's beacon and
	-- quest lists (the Logbook key opens this map instead of the logbook)
	gui.Tabs = {}
	gui.TabsHolder = FindWidget( gui.Main, "TabsHolder" )
	gui.SmallButton = DeepCopy( FindWidget( gui.TabsHolder, "Body" ) ) -- (a track button for the lists)
	gui.SmallButton.Visible = true
	local tabNames = { Wheels = { "map", "MAP" }, Power = { "quests", "QUESTS" }, Control = { "beacons", "BEACONS" } }
	for _, tab in ipairs( FindWidget( gui.Main, "TabsHolder" ).Childs ) do
		local entry = tabNames[tab.Name]
		if entry then
			gui.Tabs[tab.Name] = { widget = tab, key = entry[1] }
			FindWidget( tab, "TabText" ).Caption = entry[2]
		else
			tab.Visible = false
		end
	end
	gui.Header = FindWidget( gui.Main, "Image" )
	local background = FindWidget( gui.Main, "ScrollBg" )
	gui.Panel = FindWidget( gui.Main, "ItemContentPanel" )
	gui.Panel.LayoutRule = "Vertical"
	gui.Panel.GridItemSize = nil
	-- Across the whole screen, like the Fabricator
	gui.Background = background

	gui.Preview = FindWidget( gui.Side, "Preview" )
	gui.Title = FindWidget( gui.Side, "Title" )
	gui.Description = FindWidget( gui.Side, "DescriptionBox" )
	-- The side panel is all description: the trader's cost box goes, and the
	-- Route Analysis bars sit in the map panel's header instead (lots of room
	-- there, see cl_jmMeters)
	gui.Preview.height = 96
	gui.Description.height = 280
	local trading = FindWidget( gui.Side, "Trading" )
	for i, widget in ipairs( gui.Side.Childs ) do
		if widget == trading then
			local divider = gui.Side.Childs[i + 1]
			for _, w in ipairs( { trading, divider } ) do
				if w then w.Visible = false; w.height = 0; w.y = 0 end
			end
			break
		end
	end
	local holder = FindWidget( gui.Side, "TradeHolder" )
	holder.Visible = false
	holder.height = 0
	gui.Meters = {
		Name = "Meters", Type = "Widget", Skin = "PanelEmpty", LayoutRule = "Absolute",
		NeedKey = false, NeedMouse = false, Childs = {}, x = 400, y = 22, width = 2 * METER_COLUMN, height = 16 + 4 * METER_ROW,
	}
	table.insert( gui.Main.Childs, gui.Meters )
	gui.Button = FindWidget( gui.Side, "TradeButton" )
	-- A second button under the first, for the Re-stabilizer
	local reroll = DeepCopy( gui.Button )
	reroll.Name = "RerollButton"
	reroll.onClick = "cl_jmReroll"
	reroll.y = 6
	for i, widget in ipairs( gui.Side.Childs ) do
		if widget == gui.Button then
			table.insert( gui.Side.Childs, i + 1, reroll )
			break
		end
	end
	gui.Reroll = reroll
	MapGui = gui
	return gui
end

local function SetItemIcon( widget, uuid )
	local resource, group, name = sm.gui.getItemIconFromUuid( uuid )
	widget.ImageTexture = nil -- a texture would win over the item icon
	widget.Type = "ImageBox"
	widget.Skin = "ImageBox"
	widget.ImageResource = resource
	widget.ImageGroup = group
	widget.ImageName = name
end

function Game.cl_jmOpen( self )
	self.network:sendToServer( "sv_n_requestJunctionMap" )
end

function Game.cl_n_junctionMap( self, data )
	self.cl.jm = data
	self.cl.jmChoosing = data.mode == "travel"
	self.cl.jmTravelled = false
	if not self.cl.jmGui or not sm.exists( self.cl.jmGui ) then
		BuildMapGui()
		-- Across the whole screen, like the Fabricator (worked out on every open:
		-- the window may have changed size)
		WidenHideoutGui( MapGui.json, MapGui.Main, { MapGui.Background, MapGui.Panel }, {} )
		-- Bars at the right of the header, clear of the title
		MapGui.Meters.x = math.max( MapGui.Main.width - 2 * METER_COLUMN - 30, 360 )
		self.cl.jmGui = sm.jsonGui.createGui( { handleKeySetup = "Hideout", name = "Hideout" } )
		self.cl.jmCam, self.cl.jmZoom, self.cl.jmCamTarget = nil, nil, nil -- (on where you are, see cl_jmBuild)
		-- Travelling a planned route: its next junction is picked already
		self.cl.jmSelected = ( data.mode == "travel" and data.destination and data.nextHop ) or data.destination or data.current
	end
	self.cl.jmDirty = true
end

function Game.cl_jmNothing( self ) end

function Game.cl_jmOnClose( self )
	g_pacificMapClosedByUser = true -- (a logbook held for the map is put away, survival_patches.lua)
	-- Closed without picking: stay put
	if self.cl.jmChoosing and not self.cl.jmTravelled then
		self.network:sendToServer( "sv_n_jmCancel" )
	end
	self.cl.jmChoosing = false
	if self.cl.jmGui and sm.exists( self.cl.jmGui ) then
		self.cl.jmGui:close()
	end
	self.cl.jmGui = nil
	self.cl.jmSelected = nil
end

-- Map view: drag the empty map to move it, mouse wheel to zoom (about the
-- middle of the view). The camera is the map point shown in the middle.
function Game.cl_jmWheel( self, widgetName, scrollValue )
	local old = self.cl.jmZoom or 1.0
	local zoom = ( scrollValue or 0 ) > 0 and old * MAP_ZOOM_STEP or old / MAP_ZOOM_STEP
	zoom = math.max( math.min( zoom, MAP_ZOOM_MAX ), MAP_ZOOM_MIN )
	-- Where the mouse is (in the view): the middle of the grid cell, or of the
	-- junction, the wheel turned over. That map point stays under the mouse.
	local view, cam = self.cl.jmView, self.cl.jmCam
	local sx, sy
	local cx, cy = tostring( widgetName or "" ):match( "^MapCell_(%d+)_(%d+)$" )
	if cx and view then
		sx, sy = ( tonumber( cx ) + 0.5 ) * view.cellW, ( tonumber( cy ) + 0.5 ) * view.cellH
	else
		local id = tonumber( tostring( widgetName or "" ):match( "^MapNode(%d+)$" ) or "" )
		local point = id and self.cl.jmPoints and self.cl.jmPoints[id]
		if point and view and cam then
			sx, sy = view.w * 0.5 + ( point.x - cam.x ) * old, view.h * 0.5 + ( point.y - cam.y ) * old
		end
	end
	if sx and view and cam then
		local mx = cam.x + ( sx - view.w * 0.5 ) / old
		local my = cam.y + ( sy - view.h * 0.5 ) / old
		self.cl.jmCam = { x = mx - ( sx - view.w * 0.5 ) / zoom, y = my - ( sy - view.h * 0.5 ) / zoom }
		self.cl.jmCamTarget = nil
	end
	self.cl.jmZoom = zoom
	self.cl.jmDirty = true
end

function Game.cl_jmDragStart( self, widgetName, x, y )
	self.cl.jmCamTarget = nil -- (dragging takes over from a glide)
	self.cl.jmDrag = { x = x, y = y, cam = self.cl.jmCam }
	self.cl.jmDragMoved = false
end

function Game.cl_jmDragMove( self, widgetName, x, y )
	local drag = self.cl.jmDrag
	if not drag or not drag.cam or not self.cl.jmScale then return end
	if math.abs( x - drag.x ) + math.abs( y - drag.y ) > 4 then
		self.cl.jmDragMoved = true -- (so letting go isn't a click)
	end
	self.cl.jmCam = { x = drag.cam.x - ( x - drag.x ) / self.cl.jmScale, y = drag.cam.y - ( y - drag.y ) / self.cl.jmScale }
	self.cl.jmDirty = true
end

function Game.cl_jmDragEnd( self )
	self.cl.jmDrag = nil
end

function Game.cl_jmTab( self, widgetName )
	local tab = MapGui and MapGui.Tabs[widgetName]
	if tab then
		self.cl.jmTab = tab.key
		self.cl.jmDirty = true
	end
end

function Game.cl_jmSelectNode( self, widgetName, data )
	if self.cl.jmDragMoved then
		self.cl.jmDragMoved = false
		return -- that was a drag, not a click
	end
	-- Glide the view over to it
	local point = self.cl.jmPoints and self.cl.jmPoints[data.id]
	if point then
		self.cl.jmCamTarget = { x = point.x, y = point.y }
	end
	self.cl.jmSelected = data.id
	self.cl.jmDirty = true
end

-- (no click sounds: effects need a world, and the game script has none)
function Game.cl_jmMainButton( self )
	local id = self.cl.jmSelected
	local node = id and self.cl.jmNodes and self.cl.jmNodes[id]
	if not node then return end
	local mode = self.cl.jm.mode
	if mode == "planner" then
		self.network:sendToServer( "sv_n_jmSetDestination", { id = id } )
	elseif mode == "travel" then
		self.cl.jmTravelled = true
		self.network:sendToServer( "sv_n_jmTravel", { id = id } )
		self:cl_jmOnClose()
	end
end

-- The second button: scan an unscanned junction, re-stabilize a scanned one
function Game.cl_jmReroll( self )
	local id = self.cl.jmSelected
	local node = id and self.cl.jmNodes and self.cl.jmNodes[id]
	if not node then return end
	if node.scanned then
		self.network:sendToServer( "sv_n_jmReroll", { id = id } )
	else
		self.network:sendToServer( "sv_n_jmScan", { id = id } )
	end
end

-- Route Analysis bars: a label, a dark bar and a filled part
local BarColours = {
	good = "0.64 0.80 0.27 1", bad = "0.96 0.45 0.17 1", info = "0.30 0.75 0.95 1", muted = "0.45 0.45 0.45 1",
}
local LabelTemplate = { Type = "TextBox", Skin = "TextBox", FontName = "SM_TextTiny", TextAlign = "Left",
	NeedKey = false, NeedMouse = false, Childs = {}, height = 15 }

function Game.cl_jmMeters( self, n, data )
	local rows = {}
	local known = n.depth > 0 and n.scanned
	local function row( label, value, max, colour, text )
		rows[#rows + 1] = { label = label, value = value, max = max, colour = colour, text = text }
	end
	if known then
		local minutes = math.floor( StabilityToSeconds( n.stability or 0 ) / 60 + 0.5 )
		row( "STABILITY", n.stability or 0, 100, BarColours.good, "~" .. minutes .. "M" )
		row( "ZONE STORM", n.storm or 0, 4, BarColours.bad, LEVELS[n.storm or 0] )
		row( "ANOMALIES", n.anomalies or 0, 4, BarColours.bad, LEVELS[n.anomalies or 0] )
		row( "BUILDINGS", n.buildings or 0, 4, BarColours.info, LEVELS[n.buildings or 0] )
		row( "WATER", n.water or 0, 4, "0.30 0.55 0.95 1", ( ( n.water or 0 ) * 25 ) .. "%" )
		row( "OIL", n.oil or 0, 4, "0.62 0.50 0.38 1", ( ( n.oil or 0 ) * 25 ) .. "%" )
		row( "CHEMICALS", n.chemicals or 0, 4, "0.60 0.30 0.85 1", ( ( n.chemicals or 0 ) * 25 ) .. "%" )
		local lowest = "stable"
		for _, kind in ipairs( n.anchors or {} ) do
			if kind == "corrupted" then lowest = "corrupted" elseif kind == "unstable" and lowest ~= "corrupted" then lowest = "unstable" end
		end
		local anchor = ENERGY_ANCHOR_BY_NAME[lowest]
		local r, g, b = tonumber( anchor.colour:sub( 2, 3 ), 16 ) / 255, tonumber( anchor.colour:sub( 4, 5 ), 16 ) / 255, tonumber( anchor.colour:sub( 6, 7 ), 16 ) / 255
		row( "ANCHORS", #( n.anchors or {} ), 10, r .. " " .. g .. " " .. b .. " 1", tostring( #( n.anchors or {} ) ) )
	elseif n.depth > 0 then
		for _, label in ipairs( { "STABILITY", "ZONE STORM", "ANOMALIES", "BUILDINGS", "WATER", "OIL", "CHEMICALS", "ANCHORS" } ) do
			row( label, 0, 1, BarColours.muted, "?" )
		end
	end

	local childs = {}
	if #rows > 0 then
		local header = DeepCopy( LabelTemplate )
		header.Name, header.Caption, header.x, header.y, header.width = "MeterHeader", "#FFFFFFROUTE ANALYSIS", 0, 0, 180
		childs[#childs + 1] = header
	end
	for i, r in ipairs( rows ) do
		local column = math.floor( ( i - 1 ) / 4 )
		local x0 = column * METER_COLUMN
		local y = 16 + ( ( i - 1 ) % 4 ) * METER_ROW
		local label = DeepCopy( LabelTemplate )
		label.Name, label.Caption, label.x, label.y, label.width = "MeterLabel" .. i, "#909292" .. r.label, x0, y, 76
		childs[#childs + 1] = label
		if r.split then
			for j, part in ipairs( r.split ) do
				local x = 76 + ( j - 1 ) * 19
				childs[#childs + 1] = MapRect( "MeterBack" .. i .. "_" .. j, x, y + 5, 18, 6, "0.15 0.15 0.15 1", 1 )
				local fill = math.floor( 18 * math.max( math.min( part.value / 4, 1 ), 0 ) + 0.5 )
				if fill > 0 then
					childs[#childs + 1] = MapRect( "MeterFill" .. i .. "_" .. j, x, y + 5, fill, 6, part.colour, 1 )
				end
			end
		else
			childs[#childs + 1] = MapRect( "MeterBack" .. i, x0 + 78, y + 4, 60, 6, "0.15 0.15 0.15 1", 1 )
			local fill = math.floor( 60 * math.max( math.min( r.value / r.max, 1 ), 0 ) + 0.5 )
			if fill > 0 then
				childs[#childs + 1] = MapRect( "MeterFill" .. i, x0 + 78, y + 4, fill, 6, r.colour, 1 )
			end
		end
		local value = DeepCopy( LabelTemplate )
		value.Name, value.Caption, value.x, value.y, value.width = "MeterValue" .. i, "#FFFFFF" .. r.text, x0 + 142, y, 46
		childs[#childs + 1] = value
	end
	MapGui.Meters.Childs = childs
	MapGui.Meters.height = 16 + 4 * METER_ROW
end

-- Beacon and quest lists (the logbook's), for the BEACONS and QUESTS tabs
local function ColourString( c )
	return string.format( "%.3f %.3f %.3f 1", c.r, c.g, c.b )
end

-- Track / untrack a beacon or quest, as the logbook does
function Game.cl_jmTrack( self, widgetName, data )
	if not data then return end
	if data.beacon and g_beaconManager then
		local settings = g_beaconManager:cl_getBeaconSettings( data.beacon )
		g_beaconManager:cl_setBeaconVisible( data.beacon, not settings.visible )
	elseif data.quest then
		if QuestManager.Cl_GetTrackedQuests()[data.quest] then
			QuestManager.Cl_UntrackQuest( data.quest )
		else
			QuestManager.Cl_TrackQuest( data.quest )
		end
	end
	self.cl.jmDirty = true
end

function Game.cl_jmBuildList( self, tab, viewW, viewH )
	local canvas = {
		Name = "ListCanvas", Type = "Widget", Skin = "PanelEmpty", LayoutRule = "Absolute",
		NeedKey = false, NeedMouse = true, Childs = {}, x = 0, y = 0, width = viewW, height = viewH, -- (else its buttons get no clicks)
	}
	local y = 14
	local function line( text, x, colour )
		local label = DeepCopy( LabelTemplate )
		label.Name, label.Caption = "ListLine" .. #canvas.Childs, ( colour or "#FFFFFF" ) .. text
		label.x, label.y, label.width, label.height = x or 18, y, viewW - ( x or 18 ) - 160, 18
		table.insert( canvas.Childs, label )
		y = y + 20
	end
	-- A TRACK / UNTRACK button at the right of the line about to be written
	local function trackButton( tracked, data )
		local button = DeepCopy( MapGui.SmallButton )
		button.Name, button.x, button.y, button.width, button.height = "ListTrack" .. #canvas.Childs, viewW - 150, y - 4, 100, 24
		button.onClick, button.onClickData = "cl_jmTrack", data
		button.StateSelected = tracked
		local text = FindWidget( button, "TabText" )
		text.Caption, text.width, text.height = tracked and "UNTRACK" or "TRACK", 100, 24
		text.TextColour = tracked and "0 0 0 1" or "1 1 1 0.8"
		table.insert( canvas.Childs, button )
	end
	if tab == "beacons" then
		local character = sm.localPlayer.getPlayer().character
		local here = character and sm.exists( character ) and character:getWorld()
		local list = {}
		for id, beacon in pairs( g_beaconManager and g_beaconManager:cl_getBeacons() or {} ) do
			local distance
			if here and beacon.world == here and beacon.position then
				distance = ( beacon.position - character.worldPosition ):length()
			end
			list[#list + 1] = { id = id, beacon = beacon, distance = distance }
		end
		table.sort( list, function( a, b ) return ( a.distance or math.huge ) < ( b.distance or math.huge ) end )
		if #list == 0 then
			line( "No beacons placed.", nil, "#909292" )
			line( "Craft a Beacon and set it down to mark a spot; it shows up here and on your compass.", nil, "#909292" )
		end
		for i, entry in ipairs( list ) do
			local icon = entry.beacon.iconData or {}
			local colour = BEACON_COLORS and BEACON_COLORS[icon.colorIndex or 1]
			table.insert( canvas.Childs, {
				Name = "ListIcon" .. i, Type = "ImageBox", Skin = "ImageBox", NeedKey = false, NeedMouse = false, Childs = {},
				ImageResource = "BeaconCompassIconMap", ImageGroup = "BeaconCompassIconMap", ImageName = tostring( icon.iconIndex or 0 ),
				Colour = colour and ColourString( colour ) or "1 1 1 1", x = 18, y = y - 1, width = 18, height = 18,
			} )
			local where = entry.distance and ( math.floor( entry.distance + 0.5 ) .. " m away" ) or "somewhere else (another junction or the garage)"
			local visible = g_beaconManager:cl_getBeaconSettings( entry.id ).visible ~= false
			trackButton( visible, { beacon = entry.id } )
			line( "Beacon " .. i .. "  #909292" .. where, 44, visible and "#FFFFFF" or "#707272" )
			y = y + 6
		end
	else
		local quests = {}
		for name, quest in pairs( QuestManager.Cl_GetActiveQuests() ) do
			local ok, info = pcall( function() return quest:getData() end )
			info = ok and info or {}
			quests[#quests + 1] = { name = name, quest = quest, title = info.title or name, main = info.mainQuest == true }
		end
		table.sort( quests, function( a, b )
			if a.main ~= b.main then return a.main end
			return a.title < b.title
		end )
		if #quests == 0 then
			line( "No quests right now.", nil, "#909292" )
		end
		local tracked = QuestManager.Cl_GetTrackedQuests()
		for _, entry in ipairs( quests ) do
			trackButton( tracked[entry.name] ~= nil, { quest = entry.name } )
			line( ( entry.main and "MAIN  " or "SIDE  " ) .. entry.title, nil, entry.main and "#FFD44A" or "#4FC3F7" )
			y = y + 4
			local public = entry.quest.clientPublicData or {}
			local steps = public.trackerData or ( public.progressString and { { text = public.progressString } } ) or {}
			for _, step in ipairs( steps ) do
				for part in tostring( step.text or "" ):gmatch( "[^\n]+" ) do
					line( ( step.complete and "[x]  " or "[  ]  " ) .. part, 36, step.complete and "#707272" or "#D0D0D0" )
				end
			end
			y = y + 8
		end
	end
	return canvas
end

-- Called every frame by Game.client_onUpdate
function Game.cl_jmUpdate( self, dt )
	if not self.cl.jmGui or not sm.exists( self.cl.jmGui ) then
		return
	end
	-- Gliding to a picked junction
	local target, cam = self.cl.jmCamTarget, self.cl.jmCam
	if target and cam then
		local t = 1 - math.exp( -( dt or 0.016 ) * MAP_GLIDE )
		cam.x, cam.y = cam.x + ( target.x - cam.x ) * t, cam.y + ( target.y - cam.y ) * t
		if math.abs( target.x - cam.x ) + math.abs( target.y - cam.y ) < 1 then
			cam.x, cam.y = target.x, target.y
			self.cl.jmCamTarget = nil
		end
		self.cl.jmDirty = true
	end
	if not self.cl.jmDirty then
		return
	end
	self.cl.jmDirty = false
	self:cl_jmBuild()
	self.cl.jmGui:render( MapGui.json )
end

function Game.cl_jmBuild( self )
	local gui = MapGui
	local data = self.cl.jm
	SetItemIcon( gui.Header, sm.uuid.new( "c1d2e3f4-a5b6-4c7d-8e9f-a0b1c2d3e4f5" ) ) -- Route Planner

	local byId, children = {}, {}
	for _, node in ipairs( data.nodes ) do
		byId[node.id] = node
	end
	self.cl.jmNodes = byId
	for _, node in ipairs( data.nodes ) do
		for _, parent in ipairs( node.parents or { node.parent } ) do
			if byId[parent] then
				children[parent] = children[parent] or {}
				table.insert( children[parent], node.id )
			end
		end
	end
	for _, list in pairs( children ) do table.sort( list ) end

	-- Ahead of where you are (pickable), the route to the destination, and the
	-- route travelled this trip
	-- (roads can merge: ahead = somewhere along the roads from here)
	local ahead = {}
	local queue, head = { data.current }, 1
	while queue[head] do
		for _, kid in ipairs( children[queue[head]] or {} ) do
			if not ahead[kid] then
				ahead[kid] = true
				queue[#queue + 1] = kid
			end
		end
		head = head + 1
	end
	local function isAhead( id ) return ahead[id] == true end
	-- (junctions and the roads between them: "from_to")
	local planned, plannedRoad = {}, {}
	local last = data.current
	for _, id in ipairs( data.route or {} ) do
		planned[id] = true
		plannedRoad[last .. "_" .. id] = true
		last = id
	end
	local travelled, travelledRoad = {}, {}
	for i, id in ipairs( data.trail or {} ) do
		travelled[id] = true
		if i > 1 then travelledRoad[data.trail[i - 1] .. "_" .. id] = true end
	end

	-- Where the junctions are on the map: their saved spot (map units: the
	-- garage at 0,0 near the south shore, the zone's core up north)
	self.cl.jmPoints = {}
	local usedSites = {}
	for _, n in ipairs( data.nodes ) do
		self.cl.jmPoints[n.id] = { x = n.mx or 0, y = n.my or 0 }
		if n.site then usedSites[n.site] = true end
	end
	local function mapPoint( id )
		local p = self.cl.jmPoints[id]
		return p and p.x or 0, p and p.y or 0
	end

	-- The view: map units around the camera, times the zoom
	local viewW, viewH = gui.Panel.width - 12, gui.Panel.height - 12
	if not self.cl.jmCam or not self.cl.jmZoom then
		-- Opened: on where you are, a little ahead
		local cx, cy = mapPoint( byId[data.current] and data.current or 1 )
		self.cl.jmCam = { x = cx, y = cy - 120 }
		self.cl.jmZoom = self.cl.jmZoom or MAP_ZOOM_START
	end
	-- The middle of the view stays on the map picture
	self.cl.jmCam.x = Clamp( self.cl.jmCam.x, MAP_BOUNDS.x0, MAP_BOUNDS.x1 )
	self.cl.jmCam.y = Clamp( self.cl.jmCam.y, MAP_BOUNDS.y0, MAP_BOUNDS.y1 )
	local scale = self.cl.jmZoom
	self.cl.jmScale = scale
	local cam = self.cl.jmCam
	local node = math.floor( MAP_NODE * scale )
	local function toScreen( mx, my )
		return viewW * 0.5 + ( mx - cam.x ) * scale, viewH * 0.5 + ( my - cam.y ) * scale
	end
	local canvas = {
		Name = "MapCanvas", Type = "Widget", Skin = "PanelEmpty", LayoutRule = "Absolute",
		NeedKey = false, NeedMouse = true, Childs = {}, x = 0, y = 0, width = viewW, height = viewH,
		onMouseWheel = "cl_jmWheel",
	}
	-- The map picture (Gui/RouteMap.png, made by Gui/make_map.py)
	local px, py = toScreen( MAP_BOUNDS.x0, MAP_BOUNDS.y0 )
	canvas.Childs[1] = {
		Name = "MapImage", Type = "ImageBox", Skin = "ImageBox", ImageTexture = MAP_IMAGE,
		NeedKey = false, NeedMouse = false, Childs = {},
		x = math.floor( px ), y = math.floor( py ),
		width = math.floor( ( MAP_BOUNDS.x1 - MAP_BOUNDS.x0 ) * scale ), height = math.floor( ( MAP_BOUNDS.y1 - MAP_BOUNDS.y0 ) * scale ),
	}
	-- Over it: invisible buttons in a grid over the whole view. They catch
	-- drags, and the wheel: which cell got it says where the mouse is, so the
	-- zoom goes towards the mouse (the game doesn't tell the wheel's position).
	-- The junctions on top still take clicks.
	local cellW, cellH = viewW / MAP_ZOOM_CELLS_X, viewH / MAP_ZOOM_CELLS_Y
	self.cl.jmView = { w = viewW, h = viewH, cellW = cellW, cellH = cellH }
	for cy = 0, MAP_ZOOM_CELLS_Y - 1 do
		for cx = 0, MAP_ZOOM_CELLS_X - 1 do
			local x, y = math.floor( cx * cellW ), math.floor( cy * cellH )
			canvas.Childs[#canvas.Childs + 1] = {
				Name = "MapCell_" .. cx .. "_" .. cy, Type = "Button", Skin = "PanelEmpty", NeedKey = false, NeedMouse = true, Childs = {},
				x = x, y = y, width = math.floor( ( cx + 1 ) * cellW ) - x, height = math.floor( ( cy + 1 ) * cellH ) - y,
				onPressed = "cl_jmDragStart", onDrag = "cl_jmDragMove", onReleased = "cl_jmDragEnd", onMouseWheel = "cl_jmWheel",
			}
		end
	end
	-- Zone tier names, on the map just inside each tier (south of the core)
	for i, tier in ipairs( ZONE_TIERS ) do
		local lx, ly = toScreen( 0, -MAP_CORE_RADIUS + MapRadius( tier.first ) + MAP_DEPTH_STEP * 0.15 )
		if lx > -200 and lx < viewW + 200 and ly > -20 and ly < viewH + 20 then
			local label = DeepCopy( LabelTemplate )
			label.Name, label.Caption, label.TextAlign = "MapTier" .. i, "#C8C8C8" .. tier.title:upper(), "Center"
			label.x, label.y, label.width = math.floor( lx - 100 ), math.floor( ly ), 200
			table.insert( canvas.Childs, label )
		end
	end
	local function at( id )
		local x, y = toScreen( mapPoint( id ) )
		return x - node * 0.5, y - node * 0.5
	end
	local function onScreen( x, y )
		return x > -node * 2 and x < viewW + node and y > -node * 2 and y < viewH + node
	end

	local function state( id )
		local n = byId[id]
		if id == data.current then return "current" end
		if planned[id] then return "destination" end
		if n.visited then return "visited" end
		if not n.reachable then return "locked" end
		if n.landmark then return "landmark" end
		if n.collapsed or n.deadEnd then return "danger" end
		if isAhead( id ) and n.scanned then return "choice" end
		return "unknown"
	end

	-- Places not explored yet: every free site, faint
	local mark = math.max( math.floor( 8 * scale + 0.5 ), 3 )
	for i, site in ipairs( MAP_SITES ) do
		if not usedSites[i] then
			local x, y = toScreen( site.x, site.y )
			if x > -mark and x < viewW and y > -mark and y < viewH then
				table.insert( canvas.Childs, MapRect( "MapSite" .. i, x - mark * 0.5, y - mark * 0.5, mark, mark, "0.85 0.85 0.80 1", 0.35 ) )
			end
		end
	end

	-- Roads: dotted lines from a junction to the ones it leads to. They bend a
	-- little like real roads: each tries a few bends and takes the one that
	-- keeps furthest from other junctions (a gentle one of its own if all are
	-- clear), plus a small wiggle. All in map units, so they stay put.
	local function hash( id, salt )
		local v = math.sin( id * 12.9898 + salt * 78.233 ) * 43758.5453
		return ( v - math.floor( v ) ) * 2 - 1
	end
	local function curvePoint( ax, ay, cx, cy, bx, by, t, wiggle, phase, px, py )
		local u = 1 - t
		local x = u * u * ax + 2 * u * t * cx + t * t * bx
		local y = u * u * ay + 2 * u * t * cy + t * t * by
		local w = math.sin( t * math.pi * 2 + phase ) * wiggle * 4 * t * u
		return x + px * w, y + py * w
	end
	local dot = math.max( math.floor( 4 * scale + 0.5 ), 2 )
	local gap = math.max( 12 * scale, 7 )
	for id, kids in pairs( children ) do
		local ax, ay = mapPoint( id )
		for _, kid in ipairs( kids ) do
			local bx, by = mapPoint( kid )
			local length = math.max( math.sqrt( ( bx - ax ) ^ 2 + ( by - ay ) ^ 2 ), 1 )
			local px, py = -( by - ay ) / length, ( bx - ax ) / length
			local mx, my = ( ax + bx ) * 0.5, ( ay + by ) * 0.5
			local wiggle, phase = length * 0.035, hash( kid, 3 ) * math.pi
			-- The bend: how close each option passes to the other junctions
			local preferred = hash( kid, 4 ) * 0.15
			local best, bestRoom, bestPick
			for _, bend in ipairs( { preferred, 0, 0.18, -0.18, 0.32, -0.32 } ) do
				local cx, cy = mx + px * bend * length, my + py * bend * length
				local room = math.huge
				for k = 1, 9 do
					local x, y = curvePoint( ax, ay, cx, cy, bx, by, k / 10, wiggle, phase, px, py )
					for otherId, p in pairs( self.cl.jmPoints ) do
						if otherId ~= id and otherId ~= kid then
							room = math.min( room, math.sqrt( ( p.x - x ) ^ 2 + ( p.y - y ) ^ 2 ) )
						end
					end
				end
				-- clear of everything: the first such option wins (the preferred bend comes first)
				local pick = room >= MAP_ROAD_CLEARANCE and 1e9 - math.abs( bend - preferred ) or room
				if not bestPick or pick > bestPick then best, bestRoom, bestPick = bend, room, pick end
			end
			local cx, cy = mx + px * best * length, my + py * best * length
			local road = id .. "_" .. kid
			-- (roads into a collapsed junction are red)
			local intoDanger = byId[kid] and byId[kid].collapsed
			local colour = ( travelledRoad[road] and MapColours.visited ) or ( plannedRoad[road] and MapColours.destination )
				or ( intoDanger and MapColours.danger ) or MapColours.unknown
			local alpha = ( travelledRoad[road] or plannedRoad[road] or intoDanger ) and 1 or 0.8
			-- Dots evenly along it on screen
			local clear = node * 0.65 -- (not under the junctions)
			local lastX, lastY = toScreen( ax, ay )
			local samples, points = 48, { [0] = { x = lastX, y = lastY, at = 0 } }
			local total = 0
			for k = 1, samples do
				local x, y = toScreen( curvePoint( ax, ay, cx, cy, bx, by, k / samples, wiggle, phase, px, py ) )
				total = total + math.sqrt( ( x - lastX ) ^ 2 + ( y - lastY ) ^ 2 )
				points[k] = { x = x, y = y, at = total }
				lastX, lastY = x, y
			end
			local count = math.floor( total / gap )
			local k = 1
			for i = 1, count - 1 do
				-- (exactly that far along: between the two samples around it)
				local at = total * i / count
				while points[k].at < at and k < samples do k = k + 1 end
				local p, q = points[k - 1], points[k]
				local f = ( q.at > p.at ) and ( at - p.at ) / ( q.at - p.at ) or 0
				local x, y = p.x + ( q.x - p.x ) * f, p.y + ( q.y - p.y ) * f
				if x > -dot and x < viewW and y > -dot and y < viewH and at > clear and total - at > clear then
					table.insert( canvas.Childs, MapRect( "MapDot" .. id .. "_" .. kid .. "_" .. i, x - dot * 0.5, y - dot * 0.5, dot, dot, colour, alpha ) )
				end
			end
		end
	end

	-- Junctions: a beacon icon (the compass's icons) on a dark tile with a frame
	-- in the junction's state colour; the selected one gets a bright outer ring.
	-- An invisible button on top takes clicks, drags and the wheel.
	for _, n in ipairs( data.nodes ) do
		local x, y = at( n.id )
		if not onScreen( x, y ) then goto continue end
		local s = state( n.id )
		local faded = s == "unknown" or s == "locked"
		local border = math.max( math.floor( 3 * scale + 0.5 ), 2 )
		if n.id == self.cl.jmSelected then
			local ring = border * 2
			table.insert( canvas.Childs, MapRect( "MapRing" .. n.id, x - border - ring, y - border - ring, node + ( border + ring ) * 2, node + ( border + ring ) * 2, "1 1 1 1", 0.9 ) )
		end
		-- A collapsed junction: a wide red warning ring, and DANGER under it
		if n.collapsed then
			local warn = border * 3
			table.insert( canvas.Childs, MapRect( "MapDanger" .. n.id, x - border - warn, y - border - warn, node + ( border + warn ) * 2, node + ( border + warn ) * 2, MapColours.danger, 0.45 ) )
			local label = DeepCopy( LabelTemplate )
			label.Name, label.Caption, label.TextAlign = "MapDangerText" .. n.id, "#FF3030DANGER", "Center"
			label.x, label.y, label.width = math.floor( x + node * 0.5 - 60 ), math.floor( y + node + border + warn + 2 ), 120
			table.insert( canvas.Childs, label )
			if scale >= 0.35 then
				local sub = DeepCopy( LabelTemplate )
				sub.Name, sub.Caption, sub.TextAlign = "MapDangerSub" .. n.id, "#F42B2BZONE COLLAPSED", "Center"
				sub.x, sub.y, sub.width = label.x - 20, label.y + 13, 160
				table.insert( canvas.Childs, sub )
			end
		end
		table.insert( canvas.Childs, MapRect( "MapFrame" .. n.id, x - border, y - border, node + border * 2, node + border * 2, MapColours[s], faded and 0.55 or 1 ) )
		table.insert( canvas.Childs, MapRect( "MapTile" .. n.id, x, y, node, node, "0.07 0.08 0.09 1", 0.92 ) )
		local icon = math.floor( node * 0.62 )
		table.insert( canvas.Childs, {
			Name = "MapIcon" .. n.id, Type = "ImageBox", Skin = "ImageBox", NeedKey = false, NeedMouse = false, Childs = {},
			ImageResource = "BeaconCompassIconMap", ImageGroup = "BeaconCompassIconMap", ImageName = tostring( NodeBeaconIcon( n ) ),
			Colour = s == "current" and "1 1 1 1" or MapColours[s], Alpha = ( not n.reachable and 0.35 ) or ( n.scanned and 1 ) or 0.6, InheritsAlpha = false,
			x = math.floor( x + ( node - icon ) * 0.5 ), y = math.floor( y + ( node - icon ) * 0.5 ), width = icon, height = icon,
		} )
		table.insert( canvas.Childs, {
			Name = "MapNode" .. n.id, Type = "Button", Skin = "PanelEmpty", NeedKey = false, NeedMouse = true, Childs = {},
			x = math.floor( x - border ), y = math.floor( y - border ), width = node + border * 2, height = node + border * 2,
			onClick = "cl_jmSelectNode", onClickData = { id = n.id },
			onPressed = "cl_jmDragStart", onDrag = "cl_jmDragMove", onReleased = "cl_jmDragEnd", onMouseWheel = "cl_jmWheel",
		} )
		::continue::
	end
	-- How to move it
	local hint = DeepCopy( LabelTemplate )
	hint.Name, hint.Caption, hint.x, hint.y, hint.width = "MapHint", "#707272Drag to move, scroll to zoom" ..
		( MAP_ON_LOGBOOK_KEY and ( ", " .. sm.gui.getKeyBinding( "Logbook", false ) .. " opens the map" ) or "" ), 8, viewH - 20, 420
	table.insert( canvas.Childs, hint )
	-- Tabs: the map, or the beacon / quest list in its place. Only the junction
	-- map (the Logbook key, /junctionmap) has them: the Route Planner and
	-- travelling are just the map.
	gui.TabsHolder.Visible = data.mode == "view"
	local tab = data.mode == "view" and self.cl.jmTab or "map"
	for _, t in pairs( gui.Tabs ) do
		local selected = t.key == tab
		t.widget.StateSelected = selected
		FindWidget( t.widget, "TabText" ).TextColour = selected and "0 0 0 1" or "1 1 1 0.5"
	end
	if tab ~= "map" then
		canvas = self:cl_jmBuildList( tab, viewW, viewH )
	end
	gui.Panel.Childs = { canvas }

	-- Side panel: the selected junction's scan information
	local n = byId[self.cl.jmSelected] or byId[data.current]
	self.cl.jmSelected = n.id
	local biome = n.biome == "garage" and { title = "Garage" } or ( ZONE_BIOMES[n.biome] or ZONE_BIOMES.forest )
	gui.Preview.ItemPreview = NodeIcon( n )
	local lines = {}
	if n.depth == 0 then
		gui.Title.Caption = "Garage"
		lines[#lines + 1] = "#909292Home. The junctions above lead into the zone. Scanner charges refill every time you're back."
	else
		gui.Title.Caption = "JCT " .. ( n.code or n.depth ) .. ": " .. ( n.scanned and n.mapName or "?" )
		-- (Pacific Drive style: a collapsed junction shouts about it)
		if n.collapsed then
			lines[#lines + 1] = "#FF3030/// DANGER /// DANGER /// DANGER ///"
			lines[#lines + 1] = "#F42B2BZONE COLLAPSED: the storm is everywhere from the moment you arrive"
			lines[#lines + 1] = ""
		end
		if not n.scanned then
			lines[#lines + 1] = "#909292" .. biome.title:upper()
			lines[#lines + 1] = ""
			if n.tierLocked then
				lines[#lines + 1] = "#909292Locked. The " .. ZoneTierOf( n.zone or n.depth ).title .. " opens as you follow the main quest."
			elseif n.reachable then
				lines[#lines + 1] = "#909292Not scanned. Scan it at the Route Planner in the garage to see its conditions (scanning also reveals the route to it)."
			else
				lines[#lines + 1] = "#909292Locked. Escape the junction before it through a gateway to unlock the way here."
			end
		else
			lines[#lines + 1] = "#FFFFFF" .. biome.title:upper() .. "  #909292" .. ( n.mapName or "" )
			lines[#lines + 1] = "#909292" .. ZoneTierOf( n.zone or n.depth ).title:upper()
			local landmark = n.landmark and LandmarkByName( n.landmark )
			if landmark then
				lines[#lines + 1] = "#59D9BF" .. landmark.text
			end
			if n.collapsed then
				lines[#lines + 1] = "#F42B2BCOLLAPSED - the storm is everywhere: drive through to the next junction"
				lines[#lines + 1] = "#FFD44ASupply pods with rare loot lie about"
			elseif n.deadEnd then
				lines[#lines + 1] = "#F42B2BDEAD END - no gateway, no way on"
			elseif n.noExit then
				lines[#lines + 1] = "#F07020NO STABLE EXITS - no gateway home here"
			else
				lines[#lines + 1] = "#909292Gateway: " .. n.cost .. " anchors"
			end
			lines[#lines + 1] = ""
			lines[#lines + 1] = "#FFFFFFConditions"
			if #( n.conditions or {} ) == 0 then
				lines[#lines + 1] = "#909292Nothing unusual"
			end
			for _, name in ipairs( n.conditions or {} ) do
				local condition = ZONE_CONDITIONS[name]
				if condition then
					lines[#lines + 1] = "#FFD44A" .. condition.title .. "#909292 - " .. condition.text
				end
			end
		end
		if n.reachable and not n.deadEnd then
			lines[#lines + 1] = ""
			if n.noExit then
				lines[#lines + 1] = "#909292Exits always open (no gateway to escape through)"
			elseif n.open then
				lines[#lines + 1] = "#A3CD46Exits unlocked"
			elseif n.tierEdge then
				lines[#lines + 1] = "#F07020Exits locked: the " .. ZoneTierOf( ( n.zone or n.depth ) + 1 ).title .. " opens as you follow the main quest"
			else
				lines[#lines + 1] = "#F07020Exits locked: escape through a gateway here to unlock what's beyond"
			end
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = ( n.id == data.current and "#FFFFFFYou are here" )
			or ( planned[n.id] and "#FFD44AOn your route" )
			or ( n.visited and "#A3CD46Visited" )
			or ( isAhead( n.id ) and "#F07020Ahead" ) or "#909292Behind you"
	end
	gui.Description.Caption = table.concat( lines, "\n" )
	self:cl_jmMeters( n, data )

	-- Buttons, by mode
	local ahead = isAhead( n.id )
	local next = Contains( n.parents or { n.parent }, data.current )
	gui.Button.Visible = true
	gui.Reroll.Visible = false
	if data.mode == "planner" then
		gui.MainTitle.Caption = "ROUTE PLANNER"
		-- (a destination can be set scanned or not; the second button scans it,
		-- or re-stabilizes it once scanned)
		gui.Button.Caption = n.id == data.destination and "Destination set" or "Set Destination"
		gui.Button.Enabled = data.atGarage and ahead and n.reachable and n.id ~= data.destination
		if ahead and not n.scanned then
			gui.Reroll.Visible = data.atGarage and n.reachable
			gui.Reroll.Caption = "Scan (" .. data.charges .. " left)"
		else
			gui.Reroll.Visible = data.atGarage and ahead and n.reachable and n.scanned == true and not n.visited
			gui.Reroll.Caption = "Re-stabilize (1 charge)"
		end
		gui.Reroll.Enabled = data.charges > 0
	elseif data.mode == "travel" then
		gui.MainTitle.Caption = "JUNCTION MAP"
		local here = byId[data.current]
		local open = here and here.open
		gui.Button.Caption = open and "Travel" or "Exits locked"
		gui.Button.Enabled = next and open -- only to a junction leading on from here
	else
		gui.MainTitle.Caption = "JUNCTION MAP"
		gui.Button.Visible = false
	end
end
