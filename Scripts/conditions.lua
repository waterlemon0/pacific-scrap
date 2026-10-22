-- Junction conditions (Pacific Drive style): each new zone rolls a few of these.
-- They're shown in the quest tracker ("Junction Conditions") and when you arrive.
--   title:    name shown in the tracker
--   text:     what it does (shown on arrival)
--   weight:   how likely it is to be rolled
--   minDepth: first junction it can show up at
--   excludes: conditions it can't be combined with
-- The effects themselves live where they apply (Game.lua, DriveWorld.lua,
-- ZoneTornadoes.lua); look for ZoneHasCondition / HasCondition.
ZONE_CONDITIONS = {
	stable = {
		title = "Perpetual Stability", text = "The zone won't collapse on its own",
		weight = 2, minDepth = 1, excludes = { "unstable" },
	},
	unstable = {
		title = "Elevated Instability", text = "The zone starts collapsing much sooner",
		weight = 3, minDepth = 2, excludes = { "stable" },
	},
	rapid = {
		title = "Rapid Collapse", text = "Once the zone collapses, the storm closes in fast",
		weight = 3, minDepth = 2,
	},
	daylight = {
		title = "Perpetual Daylight", text = "The sun never sets here",
		weight = 2, minDepth = 1, excludes = { "nightfall" },
	},
	nightfall = {
		title = "Nightfall", text = "It's always night here",
		weight = 2, minDepth = 2, excludes = { "daylight" },
	},
	rain = {
		title = "Rainfall", text = "Steady rain",
		weight = 3, minDepth = 1, excludes = { "thunderstorm", "acidRain" },
	},
	thunderstorm = {
		title = "Electrical Storm", text = "Heavy rain and lightning",
		weight = 2, minDepth = 3, excludes = { "rain", "acidRain" },
	},
	acidRain = {
		title = "Acid Rain", text = "The rain burns: you take damage on foot outside your car",
		weight = 2, minDepth = 3, excludes = { "rain", "thunderstorm" },
	},
	minefield = {
		title = "Minefield", text = "Explosive red totebots lurk all over the zone",
		weight = 2, minDepth = 2,
	},
	fog = {
		title = "Dense Fog", text = "Thick fog hangs over the zone",
		weight = 3, minDepth = 1,
	},
	tornadoes = {
		title = "Hurricane Squall", text = "Tornadoes tear through the zone",
		weight = 2, minDepth = 2,
	},
	anchorSurge = {
		title = "Anchor Surge", text = "Extra energy anchors",
		weight = 2, minDepth = 1, excludes = { "anchorDrought" },
	},
	anchorDrought = {
		title = "Anchor Drought", text = "Barely enough anchors to open a gateway",
		weight = 2, minDepth = 2, excludes = { "anchorSurge" },
	},
}

-- How many conditions a junction rolls: { min, max } per depth (deeper than the
-- list uses the last entry)
ZONE_CONDITION_COUNTS = { { 0, 2 }, { 1, 2 }, { 1, 3 }, { 2, 3 }, { 2, 4 } }

-- Effect strengths
CONDITION_UNSTABLE_TIME_FACTOR = 0.5   -- calm period multiplier
CONDITION_RAPID_SPEED_FACTOR = 1.6     -- storm wall speed multiplier
CONDITION_DAYLIGHT_TIME = 0.5          -- time of day held in the zone (0.5 = noon)
CONDITION_NIGHT_TIME = 0.0             -- (0.0 = midnight)
CONDITION_ANCHOR_SURGE = 3             -- extra anchors
CONDITION_TORNADO_CHANCE = 1.0         -- Hurricane Squall: tornado roll chance...
CONDITION_TORNADO_MAX = 8              -- ...how many at once...
CONDITION_TORNADO_ROLL_SECONDS = 12    -- ...how often it rolls...
CONDITION_TORNADO_PER_ROLL = 2         -- ...how many each time...
CONDITION_TORNADO_SPAWN_DISTANCE = { 50, 140 } -- ...how close to a player (m)...
CONDITION_TORNADO_LIFETIME = 150       -- ...and how long they last (s)
CONDITION_ACID_DAMAGE = 2              -- Acid Rain: damage per second on foot
CONDITION_MINES_PER_CELL = { 0, 2 }    -- Minefield: red totebots per 64m cell (random in range)
CONDITION_MINE_CHANCE = 0.6            -- chance a cell gets any
CONDITION_MINE_SAFE_DISTANCE = 60      -- none spawn this close to a player

local function Contains( list, value )
	for _, v in ipairs( list or {} ) do
		if v == value then return true end
	end
	return false
end

function HasCondition( conditions, name )
	return Contains( conditions, name )
end

-- Rolls the conditions for a junction depth; returns a list of names
function RollConditions( depth )
	local counts = ZONE_CONDITION_COUNTS[math.min( math.max( depth or 1, 1 ), #ZONE_CONDITION_COUNTS )]
	local wanted = math.random( counts[1], counts[2] )
	local picked = {}
	for _ = 1, wanted do
		local pool, total = {}, 0
		for name, condition in pairs( ZONE_CONDITIONS ) do
			local allowed = ( depth or 1 ) >= ( condition.minDepth or 1 ) and not Contains( picked, name )
			for _, other in ipairs( picked ) do
				if Contains( condition.excludes, other ) or Contains( ZONE_CONDITIONS[other].excludes, name ) then
					allowed = false
				end
			end
			if allowed then
				pool[#pool + 1] = name
				total = total + ( condition.weight or 1 )
			end
		end
		if total == 0 then break end
		local r = math.random() * total
		for _, name in ipairs( pool ) do
			r = r - ( ZONE_CONDITIONS[name].weight or 1 )
			if r <= 0 then
				picked[#picked + 1] = name
				break
			end
		end
	end
	table.sort( picked )
	return picked
end

-- Tracker text: one condition per line
function ConditionsTrackerText( conditions )
	if not conditions or #conditions == 0 then
		return "Nothing unusual"
	end
	local lines = {}
	for _, name in ipairs( conditions ) do
		local condition = ZONE_CONDITIONS[name]
		if condition then lines[#lines + 1] = condition.title end
	end
	return table.concat( lines, "\n" )
end
