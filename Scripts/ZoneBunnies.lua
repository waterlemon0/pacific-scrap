-- Bunnies in the zone (the bunnies themselves, and latched ones: Bunny.lua).
-- The zone puts a group down in some cells as they first load.

BUNNY_UNIT_UUID = sm.uuid.new( "5b7e2c91-3d4a-4f6e-a8b2-9c1d7e3f6a05" )

-- A group of bunnies around a spot on the ground (a little spread out)
function ZoneBunnies_SvSpawnGroup( self, ground )
	local count = math.random( BUNNY_GROUP_SIZE[1], BUNNY_GROUP_SIZE[2] )
	for i = 1, count do
		local angle = ( i / count ) * 2 * math.pi
		local spot = ground + sm.vec3.new( math.cos( angle ) * 2.5, math.sin( angle ) * 2.5, 0.8 )
		sm.unit.createUnit( BUNNY_UNIT_UUID, spot, math.random() * 2 * math.pi )
	end
	return count
end

-- A cell's first load this trip (ZoneWorld.sv_tripCell): maybe a group here,
-- by the zone tier's chance (BUNNY_CELL_CHANCE), never right by a player
function ZoneBunnies_SvSpawnCell( self, x, y, depth )
	local _, tierIndex = ZoneTierOf( depth )
	if self.sv.saved.retired or ( self.data and self.data.landmark ) or math.random() > ( BUNNY_CELL_CHANCE[tierIndex] or 0 ) then
		return
	end
	local px, py = ( x + 0.2 + math.random() * 0.6 ) * 64, ( y + 0.2 + math.random() * 0.6 ) * 64
	local ground, kind = self:sv_groundBelow( sm.vec3.new( px, py, 512 ), 1024 )
	if not ground or kind ~= "terrainSurface" then return end
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == self.world
			and ( character.worldPosition - ground ):length() < BUNNY_SAFE_DISTANCE then
			return
		end
	end
	local count = ZoneBunnies_SvSpawnGroup( self, ground )
	sm.log.info( "[PacificScrap] Bunnies (" .. count .. ") in cell", x, y )
end

-- /bunnies: a group a little way ahead of the player
function ZoneBunnies_SvSpawnNear( self, player )
	local character = player and player.character
	if not character or not sm.exists( character ) or character:getWorld() ~= self.world then return end
	local forward = sm.vec3.new( character.direction.x, character.direction.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
	local spot = character.worldPosition + forward * 25
	local ground = self:sv_groundBelow( spot + sm.vec3.new( 0, 0, 100 ), 300 ) or spot
	local count = ZoneBunnies_SvSpawnGroup( self, ground )
	sm.log.info( "[PacificScrap] /bunnies:", count, "near", player.name )
end
