-- Bunnies (Pacific Drive's hares): little
-- balls of junk (survival's trash ball from the Trashbot fight, drawn smaller)
-- that sit about the zone in groups. When someone comes near, driving or on
-- foot, they give chase: they swirl round them, closing in slowly and only ever
-- a little faster than the car, hopping as they go, so it plays out as a chase.
-- Once they're close they pounce: a leap aimed at where the car will be. A
-- quick swerve makes them miss; a hit on the car latches on, a hit on someone
-- on foot bites (and it bounces off and comes again).
-- A latched bunny stops being a unit: it becomes a part (BunnyLatched, below)
-- stuck onto the block it hit, so it rides along, can be hit off, and falls
-- off (a bunny again) if that block goes.
--
-- The character (Characters/Database/CharacterSets/example.characterset) has
-- an invisible body; the ball is survival's trash ball renderable drawn on it.

dofile( "$CONTENT_DATA/Scripts/layouts.lua" )

local GRAVITY = 10 -- m/s² (for aiming the leap)
local BITE_MELEE = sm.uuid.new( "5b335dd6-10da-4a3c-9faa-36c1f8154d2c" ) -- (survival's cablebot bite)
BUNNY_PART_UUID = sm.uuid.new( "2c8f4e61-7a3b-4d95-b1e0-5f9a6c3d8e72" ) -- (a latched bunny, example.shapeset)
BUNNY_UNIT_UUID = sm.uuid.new( "5b7e2c91-3d4a-4f6e-a8b2-9c1d7e3f6a05" )

local function Clamp( v, lo, hi )
	return math.max( lo, math.min( hi, v ) )
end

local function Flat( v )
	return sm.vec3.new( v.x, v.y, 0 )
end

-- The nearest player within radius to go after: a car they're driving (its
-- seat) or them on foot (their character)
local function NearestTarget( world, position, radius )
	local best, bestDistance
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == world and not character:isDowned() then
			local seat = character:getLockingInteractable()
			local target
			if seat and sm.exists( seat ) and seat.shape and sm.exists( seat.shape ) and seat.shape.body:isDynamic() then
				target = { seat = seat }
			elseif not seat then
				target = { character = character }
			end
			if target then
				local at = target.seat and target.seat.shape.worldPosition or character.worldPosition
				local distance = ( at - position ):length()
				if distance < radius and ( not bestDistance or distance < bestDistance ) then
					best, bestDistance = target, distance
				end
			end
		end
	end
	return best
end

-- The box round a whole car: its low and high corners
local function CarBox( body )
	local low, high
	for _, b in ipairs( body:getCreationBodies() ) do
		local ok, a, c = pcall( function() return b:getWorldAabb() end )
		if ok and a then
			low = low and sm.vec3.new( math.min( low.x, a.x ), math.min( low.y, a.y ), math.min( low.z, a.z ) ) or a
			high = high and sm.vec3.new( math.max( high.x, c.x ), math.max( high.y, c.y ), math.max( high.z, c.z ) ) or c
		end
	end
	return low, high
end


-- Unit (server) -----------------------------------------------------------------

BunnyUnit = class( nil )

function BunnyUnit.server_onCreate( self )
	self.sv = {}
	self.sv.state = "idle"
	self.sv.side = math.random() < 0.5 and 1 or -1 -- (which way it swirls)
	self.sv.angle = math.random() * 2 * math.pi
	self.sv.nextHop = sm.game.getCurrentTick() + math.random( 40, 200 )
	self.unit:setMovementType( "stand" )
end

function BunnyUnit.server_onFixedUpdate( self, dt )
	local character = self.unit.character
	if self.sv.gone or not character or not sm.exists( character ) then
		return
	end
	local tick = sm.game.getCurrentTick()
	if self.sv.state == "idle" then
		-- (looking for someone only now and then: cheap)
		if tick % 10 == 0 then
			local target = NearestTarget( character:getWorld(), character.worldPosition, BUNNY_NOTICE_RADIUS )
			if target then
				self:sv_startChase( target )
				return
			end
		end
		-- (the odd little hop on the spot)
		if tick >= self.sv.nextHop then
			self:sv_hop( 0.5 )
			self.sv.nextHop = tick + math.random( 80, 320 )
		end
		return
	end
	if not self:sv_readTarget( tick ) then
		self:sv_stopChase()
		return
	end
	if self.sv.state == "leap" then
		self:sv_leaping( tick )
	elseif self.sv.state == "recover" then
		if tick >= self.sv.recoverEnd then
			self.sv.state = "chase"
		end
	else
		self:sv_chase( dt, tick )
	end
end

-- target: { seat } (a car) or { character } (someone on foot)
function BunnyUnit.sv_startChase( self, target )
	local character = self.unit.character
	local seconds = target.seat and BUNNY_CHASE_SECONDS or BUNNY_FOOT_CHASE_SECONDS
	self.sv.state = "chase"
	self.sv.target = target
	self.sv.chaseStart = sm.game.getCurrentTick()
	self.sv.chaseLength = seconds[1] + math.random() * ( seconds[2] - seconds[1] )
	local at = target.seat and target.seat.shape.worldPosition or target.character.worldPosition
	self.sv.startRadius = math.max( ( at - character.worldPosition ):length(), BUNNY_ORBIT_START )
	self.sv.boxTick = nil
	self.sv.heading = sm.vec3.new( 0, 1, 0 )
	self.sv.nextLeap = 0
end

-- Back to sitting about (they got away, or they're gone)
function BunnyUnit.sv_stopChase( self )
	self.sv.state = "idle"
	self.sv.target = nil
	self.unit:setMovementDirection( sm.vec3.zero() )
	self.unit:setMovementType( "stand" )
end

-- Where the target is now: self.sv.center, .halfSize (how far its edge is
-- from its middle), .velocity, .creation (a car's creation id). False when
-- it's gone, or the car's driver got out and walked off (it goes after them
-- next time it looks).
function BunnyUnit.sv_readTarget( self, tick )
	local target = self.sv.target
	if target.seat then
		local seat = target.seat
		if not sm.exists( seat ) or not seat.shape or not sm.exists( seat.shape ) then
			return false
		end
		local body = seat.shape.body
		if not self.sv.boxTick or tick >= self.sv.boxTick then
			self.sv.boxTick = tick + 20
			self.sv.low, self.sv.high = CarBox( body )
		end
		if not self.sv.low then
			return false
		end
		self.sv.center = ( self.sv.low + self.sv.high ) * 0.5
		self.sv.halfSize = math.max( self.sv.high.x - self.sv.low.x, self.sv.high.y - self.sv.low.y ) * 0.5
		self.sv.velocity = body.velocity
		self.sv.creation = body:getCreationId()
	else
		local character = target.character
		if not sm.exists( character ) or character:isDowned() or character:getLockingInteractable() then
			return false
		end
		self.sv.center = character.worldPosition
		self.sv.halfSize = 0.4
		self.sv.velocity = character.velocity
		self.sv.creation = nil
	end
	if Flat( self.sv.center - self.unit.character.worldPosition ):length() > BUNNY_GIVE_UP_DISTANCE then
		return false
	end
	return true
end

function BunnyUnit.sv_hop( self, strength )
	local character = self.unit.character
	if character:isOnGround() then
		sm.physics.applyImpulse( character, sm.vec3.new( 0, 0, character.mass * BUNNY_HOP * strength ) )
	end
end

-- The chase: a point that circles the target (behind it, swinging side to
-- side, once it's moving fast), its circle shrinking over the chase until it's
-- right against it. The bunny runs at that point, at the target's speed plus
-- a little, so it creeps up rather than jumping on. Close enough, it pounces.
function BunnyUnit.sv_chase( self, dt, tick )
	local character = self.unit.character
	local position = character.worldPosition
	local center, halfSize = self.sv.center, self.sv.halfSize
	local velocity = Flat( self.sv.velocity )
	local speed = velocity:length()
	if speed > 2 then
		self.sv.heading = velocity:normalize()
	end

	-- How far into the chase (0 to 1), and how far out its point circles
	local progress = Clamp( ( tick - self.sv.chaseStart ) / 40 / self.sv.chaseLength, 0, 1 )
	local ease = progress * progress * ( 3 - 2 * progress )
	local radius = self.sv.startRadius + ( halfSize + BUNNY_LATCH_GAP - self.sv.startRadius ) * ease

	-- Its point: all the way round something slow, behind and to the sides of
	-- something moving (blended by speed)
	self.sv.angle = self.sv.angle + self.sv.side * BUNNY_SWIRL * dt * ( 1 - 0.5 * ease )
	local around = sm.vec3.new( math.cos( self.sv.angle ), math.sin( self.sv.angle ), 0 )
	local behind = ( self.sv.heading * -1 ):rotateZ( math.sin( self.sv.angle ) * 1.3 )
	local fast = Clamp( speed / 10, 0, 1 )
	local offset = ( around * ( 1 - fast ) + behind * fast ):safeNormalize( around ) * radius
	local goal = center + velocity * 0.3 + offset

	local toGoal = Flat( goal - position )
	local direction = toGoal:safeNormalize( self.sv.heading )
	local wanted = math.min( speed + Clamp( toGoal:length() * 0.5, 1.5, BUNNY_CATCH_UP ), BUNNY_MAX_SPEED )
	self.unit:setMovementDirection( direction )
	self.unit:setFacingDirection( direction )
	self.unit:setMovementType( Flat( character.velocity ):length() < wanted and "sprint" or "walk" )

	-- (bunny hops all the way)
	if tick >= self.sv.nextHop then
		self:sv_hop( 1 )
		self.sv.nextHop = tick + math.random( BUNNY_HOP_TICKS[1], BUNNY_HOP_TICKS[2] )
	end

	-- Pouncing: late enough in the chase, close enough, on the ground
	if progress >= BUNNY_LEAP_FROM and tick >= self.sv.nextLeap and tick % 5 == 0
		and character:isOnGround() and Flat( center - position ):length() < halfSize + BUNNY_LEAP_RANGE then
		self:sv_leap( tick )
	end
end

-- A leap in a high arc (its top BUNNY_LEAP_HEIGHT above it) at where the
-- target will be when it comes down, going on as it is: turn or brake while
-- it's in the air and it misses
local function LeapTime( fromZ, toZ, height )
	local top = math.max( fromZ, toZ ) + height
	return math.sqrt( 2 * ( top - fromZ ) / GRAVITY ) + math.sqrt( 2 * ( top - toZ ) / GRAVITY ), top
end

function BunnyUnit.sv_leap( self, tick )
	local character = self.unit.character
	local position = character.worldPosition
	local lift = self.sv.target.seat and 0.4 or 0 -- (at a car's middle, a little up)
	local time = LeapTime( position.z, self.sv.center.z + lift, BUNNY_LEAP_HEIGHT )
	local aim = self.sv.center + sm.vec3.new( 0, 0, lift ) + self.sv.velocity * time
	local top
	time, top = LeapTime( position.z, aim.z, BUNNY_LEAP_HEIGHT )
	local across = Flat( aim - position ) * ( 1 / time )
	if across:length() > BUNNY_MAX_SPEED + 10 then
		across = across:normalize() * ( BUNNY_MAX_SPEED + 10 )
	end
	local up = math.sqrt( 2 * GRAVITY * ( top - position.z ) )
	local wanted = across + sm.vec3.new( 0, 0, up )
	sm.physics.applyImpulse( character, ( wanted - character.velocity ) * character.mass )
	self.sv.state = "leap"
	self.sv.leapEnd = tick + math.floor( time * 40 ) + 20
	self.sv.hit = false
	self.unit:setMovementDirection( Flat( wanted ):safeNormalize( self.sv.heading ) )
	self.unit:setMovementType( "sprint" )
	BunnyPuff( position )
end

-- In the air: touching the car (also caught in server_onCollision) latches on;
-- landing without having hit anything is a miss
function BunnyUnit.sv_leaping( self, tick )
	local character = self.unit.character
	local position = character.worldPosition
	if self.sv.target.seat then
		local toCenter = self.sv.center - position
		local from = position + toCenter:safeNormalize( sm.vec3.new( 0, 0, -1 ) ) * 0.5
		local hit, result = sm.physics.raycast( from, self.sv.center )
		if hit and result.type == "body" then
			local body = result:getBody()
			if body and body:getCreationId() == self.sv.creation and ( result.pointWorld - position ):length() < BUNNY_LATCH_DISTANCE then
				self:sv_latch( result.pointWorld, result:getShape() )
				return
			end
		end
	elseif ( self.sv.center - position ):length() < 1.3 then
		self:sv_bite( self.sv.target.character )
		return
	end
	if tick >= self.sv.leapEnd and character:isOnGround() then
		self:sv_recover( BUNNY_MISS_SECONDS )
	end
end

-- A moment on the ground (after a miss or a bite) before it comes again
function BunnyUnit.sv_recover( self, seconds )
	local tick = sm.game.getCurrentTick()
	self.sv.state = "recover"
	self.sv.recoverEnd = tick + math.floor( seconds * 40 )
	self.sv.nextLeap = self.sv.recoverEnd + math.random( BUNNY_LEAP_COOLDOWN_TICKS[1], BUNNY_LEAP_COOLDOWN_TICKS[2] )
	self.unit:setMovementDirection( sm.vec3.zero() )
	self.unit:setMovementType( "walk" )
end

function BunnyUnit.server_onCollision( self, other, position, selfPointVelocity, otherPointVelocity, normal )
	if self.sv.gone or self.sv.state ~= "leap" or not self.sv.target then
		return
	end
	if self.sv.target.seat and type( other ) == "Shape" and sm.exists( other ) and other.body:getCreationId() == self.sv.creation then
		self:sv_latch( position, other )
	elseif self.sv.target.character and type( other ) == "Character" and other == self.sv.target.character then
		self:sv_bite( other )
	end
end

-- How many bunnies are on a car already
local function BunniesOn( body )
	local count = 0
	for _, b in ipairs( body:getCreationBodies() ) do
		for _, shape in ipairs( b:getShapes() ) do
			if shape.uuid == BUNNY_PART_UUID then count = count + 1 end
		end
	end
	return count
end

-- Onto the car: a bunny part on the body of the block it hit, just out from
-- the surface (BUNNY_LATCH_SINK) so it goes a little into that block: it has
-- to, or the game counts it as not connected and splits it straight off. A car
-- with a full load already: it bounces off and comes again.
function BunnyUnit.sv_latch( self, point, hitShape )
	if self.sv.gone or not hitShape or not sm.exists( hitShape ) then return end
	local body = hitShape.body
	if BunniesOn( body ) >= BUNNY_MAX_PER_CAR then
		self:sv_recover( BUNNY_MISS_SECONDS )
		return
	end
	local out = ( point - self.sv.center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
	local spot = point + out * BUNNY_LATCH_SINK
	-- (the body's grid: quarter blocks from its origin; the part is 2 across, so
	-- its corner is 1 back from its middle)
	local grid = sm.quat.inverse( body.worldRotation ) * ( spot - body.worldPosition ) * 4
	local corner = sm.vec3.new( math.floor( grid.x - 0.5 ), math.floor( grid.y - 0.5 ), math.floor( grid.z - 0.5 ) )
	local ok, shape = pcall( function()
		return body:createPart( BUNNY_PART_UUID, corner, sm.vec3.new( 0, 0, 1 ), sm.vec3.new( 1, 0, 0 ), true )
	end )
	if not ok or not shape then
		sm.log.warning( "[PacificScrap] A bunny couldn't latch on:", tostring( shape ) )
		self:sv_recover( BUNNY_MISS_SECONDS )
		return
	end
	BunnyPuff( spot )
	sm.log.info( "[PacificScrap] A bunny latched onto a car (" .. ( BunniesOn( body ) + 1 ) .. " on it now); off by",
		string.format( "%.2f", ( shape.worldPosition - spot ):length() ), "m" )
	self.sv.gone = true
	self.unit:destroy()
end

-- Someone on foot: a bite, and it bounces back off them
function BunnyUnit.sv_bite( self, victim )
	if self.sv.hit then return end
	self.sv.hit = true
	local character = self.unit.character
	local toVictim = victim.worldPosition - character.worldPosition
	sm.melee.meleeAttack( BITE_MELEE, BUNNY_BITE_DAMAGE, character.worldPosition, toVictim:safeNormalize( character.direction ) * 2, self.unit, 0, BUNNY_BITE_KNOCKBACK )
	local back = Flat( toVictim ):safeNormalize( sm.vec3.new( 1, 0, 0 ) ) * -5 + sm.vec3.new( 0, 0, 4 )
	sm.physics.applyImpulse( character, ( back - character.velocity ) * character.mass )
	BunnyPuff( character.worldPosition )
	self:sv_recover( BUNNY_BITE_RECOVER_SECONDS )
end

-- One hit and it bursts
function BunnyUnit.sv_burst( self )
	if self.sv.gone then return end
	self.sv.gone = true
	BunnyPuff( self.unit.character.worldPosition )
	self.unit:destroy()
end

function BunnyUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker )
	self:sv_burst()
end

function BunnyUnit.server_onMelee( self, hitPos, attacker )
	self:sv_burst()
end

function BunnyUnit.server_onExplosion( self, center, destructionLevel )
	self:sv_burst()
end


-- Character (client): the trash ball, small, rolling as it moves --------------

BunnyCharacter = class( nil )

function BunnyCharacter.client_onCreate( self )
	self.cl = {}
end

function BunnyCharacter.client_onGraphicsLoaded( self )
	self.cl.angle = 0
	self.cl.ball = sm.effect.createEffect( "ShapeRenderable", self.character )
	self.cl.ball:setParameter( "uuid", BUNNY_BALL_UUID )
	self.cl.ball:setScale( sm.vec3.new( BUNNY_BALL_SCALE, BUNNY_BALL_SCALE, BUNNY_BALL_SCALE ) )
	self.cl.ball:setOffsetPosition( sm.vec3.new( 0, self.character:getRadius(), 0 ) )
	self.cl.ball:start()
	self.cl.trail = sm.effect.createEffect( "Trashball - TrailGreen" )
	self.cl.loaded = true
end

function BunnyCharacter.client_onGraphicsUnloaded( self )
	self.cl.loaded = false
	for _, name in ipairs( { "ball", "trail" } ) do
		if self.cl[name] then
			self.cl[name]:destroy()
			self.cl[name] = nil
		end
	end
end

function BunnyCharacter.client_onDestroy( self )
	self:client_onGraphicsUnloaded()
end

-- Rolls the ball the way it's going (as survival's TrashBallCharacter), and
-- leaves the trail behind it when it's fast
function BunnyCharacter.client_onUpdate( self, dt )
	if not self.cl.loaded or not sm.exists( self.character ) then
		return
	end
	local flat = Flat( self.character.velocity )
	local speed = flat:length()
	local trail = false
	if self.character:isOnGround() then
		self.cl.angle = ( self.cl.angle - speed / self.character:getRadius() * dt ) % ( math.pi * 2 )
		local roll = flat:safeNormalize( sm.vec3.new( 0, 1, 0 ) )
		local right = roll:cross( sm.vec3.new( 0, 0, 1 ) )
		local meshRight = sm.quat.fromEuler( sm.vec3.new( 0, 0, 180 ) ) * sm.quat.fromEuler( sm.vec3.new( 90, 0, 0 ) ) * right
		self.cl.ball:setOffsetRotation( sm.quat.angleAxis( self.cl.angle, meshRight ) )
		trail = speed > 4
		if trail then
			self.cl.trail:setPosition( self.character.worldPosition - sm.vec3.new( 0, 0, self.character:getHeight() * 0.5 ) )
			self.cl.trail:setRotation( sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), roll ) )
		end
	end
	if trail and not self.cl.trail:isPlaying() then
		self.cl.trail:start()
	elseif not trail and self.cl.trail:isPlaying() then
		self.cl.trail:stop()
	end
end


-- Latched (a part on the car) ---------------------------------------------------

-- A bunny stuck to a car: a small hidden part with the ball drawn on it. It
-- drags the car back while it's on, and every few seconds shoves it about. Hit it and it bursts; if the block it's on goes (it's on its own) it drops off
-- and is a bunny again; out of the zone (the car went home) it's gone.
BunnyLatched = class( nil )

-- Dragging the car back: every tick, a push on the car's heaviest body (its
-- chassis) against the way it's going (on the ground), harder the faster it
-- goes, sized to the whole car's weight so it's the same on any car
-- (BUNNY_DRAG). Not on the bunny's own spot: on a wheel that would push
-- against the wheel's spin and mostly cancel out.
function BunnyLatched.server_onFixedUpdate( self, dt )
	if self.sv_gone then
		return
	end
	local chassis = self.sv_chassis
	if chassis and sm.exists( chassis ) then
		local velocity = chassis.velocity
		local flat = sm.vec3.new( velocity.x, velocity.y, 0 )
		local speed = flat:length()
		if speed > 0.5 then
			local slowing = BUNNY_DRAG_BASE + BUNNY_DRAG * speed -- (m/s²)
			sm.physics.applyImpulse( chassis, flat * ( -slowing / speed * self.sv_carMass * dt ), true )
		end
		-- Every few seconds (BUNNY_JOLT_SECONDS) a big shove or tug, some random
		-- way, and a twist: the car lurches about
		local tick = sm.game.getCurrentTick()
		if not self.sv_nextJolt then
			self.sv_nextJolt = tick + math.random( BUNNY_JOLT_SECONDS[1] * 40, BUNNY_JOLT_SECONDS[2] * 40 )
		elseif tick >= self.sv_nextJolt then
			self.sv_nextJolt = tick + math.random( BUNNY_JOLT_SECONDS[1] * 40, BUNNY_JOLT_SECONDS[2] * 40 )
			local angle = math.random() * 2 * math.pi
			local push = sm.vec3.new( math.cos( angle ), math.sin( angle ), 0.3 ) * ( BUNNY_JOLT * self.sv_carMass )
			sm.physics.applyImpulse( chassis, push, true )
			local twist = ( math.random() < 0.5 and -1 or 1 ) * BUNNY_JOLT_SPIN * self.sv_carMass
			sm.physics.applyTorque( chassis, sm.vec3.new( 0, 0, twist ), true )
			-- (the first one says how big the car is, to tune by)
			if not self.sv_jolted then
				self.sv_jolted = true
				sm.log.info( "[PacificScrap] Bunny jolt: car", math.floor( self.sv_carMass ), "kg, chassis", math.floor( chassis.mass ), "kg, going", string.format( "%.1f", speed ), "m/s" )
			end
		end
	end
	-- (the rest is checked now and then, spread out over the ticks: cheap)
	if ( sm.game.getCurrentTick() + self.shape.id ) % 20 ~= 0 then
		return
	end
	local body = self.shape.body
	self.sv_carMass, self.sv_chassis = 0, nil
	for _, b in ipairs( body:getCreationBodies() ) do
		self.sv_carMass = self.sv_carMass + b.mass
		if b:isDynamic() and ( not self.sv_chassis or b.mass > self.sv_chassis.mass ) then
			self.sv_chassis = b
		end
	end
	local world = body:getWorld()
	if not ( world.publicData and world.publicData.type == "ZoneWorld" ) then
		self.sv_gone = true
		self.shape:destroyShape()
		return
	end
	if #body:getCreationShapes() == 1 then
		self.sv_gone = true
		local position = self.shape.worldPosition
		self.shape:destroyShape()
		sm.unit.createUnit( BUNNY_UNIT_UUID, position + sm.vec3.new( 0, 0, 0.5 ), math.random() * 2 * math.pi )
	end
end

function BunnyLatched.sv_burst( self )
	if self.sv_gone then return end
	self.sv_gone = true
	BunnyPuff( self.shape.worldPosition )
	self.shape:destroyShape()
end

function BunnyLatched.server_onMelee( self )
	self:sv_burst()
end

function BunnyLatched.server_onProjectile( self )
	self:sv_burst()
end

function BunnyLatched.server_onExplosion( self )
	self:sv_burst()
end

function BunnyLatched.client_onCreate( self )
	self.cl = {}
	self.cl.ball = sm.effect.createEffect( "ShapeRenderable", self.interactable )
	self.cl.ball:setParameter( "uuid", BUNNY_BALL_UUID )
	self.cl.ball:setScale( sm.vec3.new( BUNNY_BALL_SCALE, BUNNY_BALL_SCALE, BUNNY_BALL_SCALE ) )
	-- (each turned its own way, so they don't all look the same; then still)
	self.cl.ball:setOffsetRotation( sm.quat.angleAxis( math.random() * 2 * math.pi, sm.vec3.new( 0, 0, 1 ) ) )
	self.cl.ball:start()
end

function BunnyLatched.client_onDestroy( self )
	if self.cl.ball and sm.exists( self.cl.ball ) then
		self.cl.ball:destroy()
	end
end
