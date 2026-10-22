-- Compact form of a tile list for world creation data.
-- The game saves a world's creation data with a 16-bit length, so anything over
-- 64KB gets cut short and the save can never load again (the game eats memory
-- until the PC freezes). A plain tile list for the zone is ~66KB; packed it is
-- a few KB.
--   packed = { paths = { "forest/Forest(1111)_01.tile", ... },
--              cells = "pathIndex,x,y,size,rotation;..." }

local TILE_ROOT = "$SURVIVAL_DATA/Terrain/Tiles/"

function PackTiles( tiles )
	local paths, indexOf, cells = {}, {}, {}
	for _, tile in ipairs( tiles ) do
		local path = tile.path
		if path:sub( 1, #TILE_ROOT ) == TILE_ROOT then
			path = path:sub( #TILE_ROOT + 1 )
		end
		local index = indexOf[path]
		if not index then
			paths[#paths + 1] = path
			index = #paths
			indexOf[path] = index
		end
		cells[#cells + 1] = string.format( "%d,%d,%d,%d,%d", index, tile.x, tile.y, tile.size or 0, tile.rotation or 0 )
	end
	local packed = { paths = paths, cells = table.concat( cells, ";" ) }
	local size = #packed.cells
	for _, path in ipairs( paths ) do size = size + #path + 3 end
	if size > 50000 then
		sm.log.error( "[PacificScrap] Packed tile list is " .. size .. " bytes, close to the 64KB save limit. Make the zone smaller!" )
	end
	return packed
end

function UnpackTiles( packed )
	if packed == nil then
		return {}
	end
	if packed.cells == nil then
		return packed -- already a plain tile list
	end
	local tiles = {}
	for index, x, y, size, rotation in packed.cells:gmatch( "(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)" ) do
		local path = packed.paths[tonumber( index )]
		if path:sub( 1, 1 ) ~= "$" then
			path = TILE_ROOT .. path
		end
		size = tonumber( size )
		tiles[#tiles + 1] = { path = path, x = tonumber( x ), y = tonumber( y ), size = size > 0 and size or nil, rotation = tonumber( rotation ) }
	end
	return tiles
end
