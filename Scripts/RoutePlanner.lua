-- Route Planner: a console in the garage. Interact with it to plan trips on the
-- junction map: scan junctions with scanner charges, re-stabilize them and set a
-- destination. (The map itself is in JunctionMap.lua; driving into a junction
-- opens the travel-only version of it.)
RoutePlanner = class()
RoutePlanner.maxParentCount = 0
RoutePlanner.maxChildCount = 0

function RoutePlanner.sv_n_open( self, _, player )
	sm.event.sendToGame( "sv_e_openRoutePlanner", { player = player } )
end

-- No power in the garage yet (the Getting Started quest): it doesn't work.
-- The server shows the power state as the interactable being on.
function RoutePlanner.server_onFixedUpdate( self )
	if sm.game.getCurrentTick() % 40 == 13 and self.interactable.active ~= ( g_garagePowered == true ) then
		self.interactable.active = g_garagePowered == true
	end
end

function RoutePlanner.client_canInteract( self )
	if not self.interactable.active then
		sm.gui.setInteractionText( "No power", "Put the battery in the garage's socket" )
		return false
	end
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Route Planner" )
	return true
end

function RoutePlanner.client_onInteract( self, character, state )
	if state then
		self.network:sendToServer( "sv_n_open" )
	end
end
