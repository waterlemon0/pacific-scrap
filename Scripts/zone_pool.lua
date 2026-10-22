-- Zone pool (ZONE_POOL in layouts.lua): zone worlds are used again instead of
-- a new one every trip, so the save stops growing.
--
-- Worlds are pooled by zone depth (NodeZoneDepth), the junctions of the first
-- zone depth getting the most (ZONE_POOL_SIZES). Until a pool is full, a trip
-- there makes a new world (CreateZone) and it joins the pool; after that the
-- world used longest ago is used again.
--
-- A world can't change its ground once made, so what's built into it (biome,
-- buildings, water, oil and chemicals) is kept with it, and a junction that
-- gets a pooled world takes those on when it's rolled (sv_zonePoolAssign), so
-- the Route Planner shows what you'll find. Everything else is new every trip
-- (ZoneWorld.sv_startTrip in DriveWorld.lua): anchors, conditions, robots,
-- mines, the collapse, whether the exits are locked.
--
-- saved.zonePool = { [key] = { record, ... } }, a record:
--   { id, world, biome, buildings, water, oil, chemicals, spawnCells, liquids, used }
-- node.poolId: the record a junction will use (false: a new world), set when
-- it's rolled. Loaded by Game.lua.

-- Which pool a zone goes in: its zone depth, and whether its ruins have the
-- starting area's loot (built into the world: START_LOOT_DEPTH)
function ZonePoolKey( depth, zoneDepth )
	local key = tostring( math.min( zoneDepth or depth or 1, #ZONE_POOL_SIZES ) )
	if ( depth or 1 ) <= START_LOOT_DEPTH then
		key = key .. "s"
	end
	return key
end

function ZonePoolSize( zoneDepth )
	return ZONE_POOL_SIZES[math.min( math.max( zoneDepth or 1, 1 ), #ZONE_POOL_SIZES )]
end

local function PoolIsFor( node )
	return ZONE_POOL and node ~= nil and node.depth ~= nil and node.depth > 0 and not node.landmark
end

-- (worlds compared by id: one read back from the save is a new copy)
local function SameWorld( a, b )
	return a ~= nil and b ~= nil and a.id == b.id
end

local function FindRecord( pool, id )
	for _, record in ipairs( pool or {} ) do
		if record.id == id then return record end
	end
	return nil
end

-- A junction takes on what's built into its pooled world
function ZonePoolAdopt( node, record )
	node.biome = record.biome or node.biome
	node.buildings = record.buildings or node.buildings
	node.water, node.oil, node.chemicals = record.water or 0, record.oil or 0, record.chemicals or 0
	node.wetland = record.wetland
end

-- Every junction rolled since (node.poolPicked cleared by RollJunction) picks
-- its world: a new one while its pool has room (counting the junctions
-- already planning a new one), else the pooled world used longest ago that no
-- other junction on the map has
function Game.sv_zonePoolAssign( self )
	if not ZONE_POOL then return end
	local map = self.sv.saved.map
	local pools = self.sv.saved.zonePool or {}
	local nodes, taken, planned = {}, {}, {}
	for _, node in pairs( map and map.nodes or {} ) do
		if PoolIsFor( node ) then
			local key = ZonePoolKey( node.depth, NodeZoneDepth( node ) )
			if node.poolPicked then
				if node.poolId then
					taken[node.poolId] = true
				else
					planned[key] = ( planned[key] or 0 ) + 1
				end
			else
				nodes[#nodes + 1] = node
			end
		end
	end
	table.sort( nodes, function( a, b ) return a.depth < b.depth or ( a.depth == b.depth and a.id < b.id ) end )
	for _, node in ipairs( nodes ) do
		local zoneDepth = NodeZoneDepth( node )
		local key = ZonePoolKey( node.depth, zoneDepth )
		local pool = pools[key] or {}
		node.poolPicked = true
		node.poolId = false
		if #pool + ( planned[key] or 0 ) < ZonePoolSize( zoneDepth ) then
			planned[key] = ( planned[key] or 0 ) + 1
		else
			-- (a biome picked by hand in the map editor: only worlds of that biome)
			local best
			for _, pass in ipairs( { "free", "any" } ) do
				for _, record in ipairs( pool ) do
					local fits = not node.handBiome or record.biome == node.biome
					if fits and ( pass == "any" or not taken[record.id] ) and ( not best or ( record.used or 0 ) < ( best.used or 0 ) ) then
						best = record
					end
				end
				if best then break end
			end
			if best then
				node.poolId = best.id
				taken[best.id] = true
				ZonePoolAdopt( node, best )
			end
		end
	end
end

-- The pooled world for a trip to this junction (CreateZone), or nil for a new
-- one. Never the zone being left (avoid). If the junction planned a new world
-- but its pool filled up since, the one used longest ago, and the junction
-- takes it on.
function ZonePoolTake( saved, node, avoid )
	if not PoolIsFor( node ) then return nil end
	local zoneDepth = NodeZoneDepth( node )
	local pool = saved.zonePool and saved.zonePool[ZonePoolKey( node.depth, zoneDepth )] or {}
	local record = node.poolId and FindRecord( pool, node.poolId )
	if record and SameWorld( record.world, avoid ) then
		record = nil
	end
	if not record and #pool >= ZonePoolSize( zoneDepth ) then
		for _, other in ipairs( pool ) do
			if not SameWorld( other.world, avoid ) and ( not record or ( other.used or 0 ) < ( record.used or 0 ) ) then
				record = other
			end
		end
	end
	if record then
		ZonePoolAdopt( node, record )
	end
	return record
end

-- A new zone world joins its pool
function ZonePoolAdd( saved, node, record )
	saved.zonePool = saved.zonePool or {}
	local key = ZonePoolKey( node.depth, NodeZoneDepth( node ) )
	saved.zonePool[key] = saved.zonePool[key] or {}
	saved.zonePoolNextId = ( saved.zonePoolNextId or 0 ) + 1
	record.id = saved.zonePoolNextId
	table.insert( saved.zonePool[key], record )
	node.poolId = record.id
	node.poolPicked = true
	local count = 0
	for _, list in pairs( saved.zonePool ) do count = count + #list end
	sm.log.info( "[PacificScrap] Zone pool: new world", record.world.id, "in pool", key, "(" .. #saved.zonePool[key] .. "/" .. ZonePoolSize( NodeZoneDepth( node ) ) .. ",", count, "pooled worlds in all)" )
end
