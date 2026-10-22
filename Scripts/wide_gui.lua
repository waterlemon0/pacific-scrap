-- Stretches a Hideout-style menu (Fabricator.gui: the main panel on the left,
-- the item panel on the right) across the whole screen. Used by the Fabricator
-- and the Route Planner / junction map so they look the same.
--
-- Json GUIs are laid out for 1280x720 and scaled by height, so the screen is
-- 720 * aspect units wide (1280 on 16:9). On a narrower window they scale by
-- width instead, which leaves at least that much room, so this always fits.

local WIDE_GUI_MARGIN = 20 -- units left free on each side
local Original = {} -- json -> the sizes before widening (not a json key: the game would read it)

-- json: the root, main: the main panel. grow: widgets that get wider with it,
-- shift: widgets that move right with its right edge. Call it every time the
-- menu opens: it works from the original sizes, so a resized window is fine.
function WidenHideoutGui( json, main, grow, shift )
	local base = Original[json]
	if not base then
		-- The panels sit side by side from the left and don't fill the root (the
		-- Hideout leaves room on the right): the main panel takes that slack too,
		-- or the whole thing looks shifted left
		local used = 0
		for _, child in ipairs( json.Childs or {} ) do
			used = used + ( child.x or 0 ) + ( child.width or 0 )
		end
		base = { width = json.width, x = json.x, main = main.width, slack = math.max( json.width - used, 0 ), grow = {}, shift = {} }
		for i, widget in ipairs( grow or {} ) do base.grow[i] = widget.width end
		for i, widget in ipairs( shift or {} ) do base.shift[i] = widget.x end
		Original[json] = base
	end
	local screen = 1280
	local ok, w, h = pcall( sm.gui.getScreenSize )
	if ok and w and h and h > 0 then
		screen = 720 * w / h
	end
	local extra = math.max( math.floor( screen - 2 * WIDE_GUI_MARGIN - base.width ), 0 )
	json.width = base.width + extra
	json.x = 0 -- centred
	extra = extra + base.slack
	main.width = base.main + extra
	for i, widget in ipairs( grow or {} ) do
		widget.width = base.grow[i] + extra
	end
	for i, widget in ipairs( shift or {} ) do
		widget.x = base.shift[i] + extra
	end
end
