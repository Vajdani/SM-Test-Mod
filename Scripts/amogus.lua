dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

---@class Amogus : ToolClass
---@field fpAnimations table
---@field tpAnimations table
---@field isLocal boolean
---@field normalFireMode table
---@field blendTime number
---@field aimBlendSpeed number
Amogus = class()
Amogus.modes = {
	{
		name = "Ex/Im - ploder",
		colour = sm.color.new(1,0,0),
		lmbFuncs = {
			"cl_mode_exploder_ex"
		},
		rmbFuncs = {
			"cl_mode_exploder_imp"
		}
	},
	{
		name = "Black Hole",
		colour = sm.color.new(0,0,0),
		lmbFuncs = {
			"sv_mode_blackhole"
		},
		rmbFuncs = {
			"sv_mode_blackhole_detonate"
		}
	},
	{
		name = "Grenade",
		colour = sm.color.new(0.2,0.5,0),
		lmbFuncs = {
			"sv_mode_grenade"
		},
		rmbFuncs = {}
	}
}

local camAdjust = sm.vec3.new(0,0,0.575)

local renderables = { "$CONTENT_DATA/Objects/sus.rend" }
local renderablesTp = { "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_tp_eattool.rend", "$SURVIVAL_DATA/Character/Char_Tools/Char_eattool/char_eattool_tp.rend" }
local renderablesFp = { "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_fp_eattool.rend", "$SURVIVAL_DATA/Character/Char_Tools/Char_eattool/char_eattool_fp.rend" }

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function Amogus:server_onCreate()
	self.sv_blackholes = {}
end

function Amogus:client_onCreate()
	self.isLocal = self.tool:isLocal()
	self.owner = self.tool:getOwner()

	self.modIndex = 1
	self.cl_blackholes = {}
end

function Amogus:client_onToggle()
	return true
end

function Amogus:client_onReload()
	self.modIndex = self.modIndex < #self.modes and self.modIndex + 1 or 1
	local mode = self.modes[self.modIndex]
	sm.gui.displayAlertText(string.format("Current Mode:%s %s", "#"..mode.colour:getHexStr():sub(1,6), mode.name))
	sm.audio.play("PaintTool - ColorPick")
	self.network:sendToServer("sv_modeSwitch", self.modIndex)

	return true
end



function Amogus:sv_modeSwitch( index )
	self.network:sendToClients("cl_modeSwitch", index)
end

function Amogus:cl_modeSwitch( index )
	self.modIndex = index

	setTpAnimation( self.tpAnimations, "pickup", 1 )
	if self.isLocal then
		setFpAnimation( self.fpAnimations, "equip", 0.1 )
	end

	self:cl_updateColour()
end

function Amogus:cl_updateColour( colour )
	local col = colour or self.modes[self.modIndex].colour
	self.tool:setFpColor( col )
	self.tool:setTpColor( col )
end

-- #region Ex/Im - ploder
function Amogus:cl_mode_exploder_ex()
	self:cl_mode_exploder( 1 )
end

function Amogus:cl_mode_exploder_imp()
	self:cl_mode_exploder( -1 )
end

function Amogus:cl_mode_exploder( mult )
	local char = self.owner.character
	local pos = sm.camera.getPosition()
	local hit, result = sm.physics.raycast( pos, pos + char.direction * 100, char )

	if hit then
		local body = result:getBody()
		if body then
			self.network:sendToServer("sv_mode_exploder", { target = body:getCreationBodies(), mult = mult } )
			return
		end

		self.network:sendToServer("sv_mode_exploder", { target = result.pointWorld, mult = mult })
	end
end

function Amogus:sv_mode_exploder( args )
	local target = args.target
	local mult = args.mult

	if type(target) == "Vec3" then
		sm.physics.explode(target, 10, 15, 20, 150 * mult, "PropaneTank - ExplosionBig")
	else
		for k, body in pairs(target) do
			if sm.exists(body) then
				sm.physics.explode(body.centerOfMassPosition, 10, 2.5, 5, 100 * mult, "PropaneTank - ExplosionBig")
			end
		end
	end
end
-- #endregion

-- #region Black Hole
function Amogus:cl_mode_blackhole_create( pos )
	self.cl_blackholes[#self.cl_blackholes+1] = pos
end

function Amogus:cl_mode_blackhole_destroy( index )
	self.cl_blackholes[index] = nil
end

function Amogus:sv_mode_blackhole()
	local char = self.tool:getOwner().character
	local startPos = char.worldPosition + camAdjust
	local endPos = startPos + char.direction * 10
	local hit, result = sm.physics.raycast( startPos, endPos, char )

	local pos = hit and result.pointWorld or endPos
	self.sv_blackholes[#self.sv_blackholes+1] = { pos = pos, lifeTime = 20 }
	self.network:sendToClients("cl_mode_blackhole_create", pos)
end

function Amogus:sv_mode_blackhole_detonate()
	for k, data in pairs(self.sv_blackholes) do
		sm.physics.explode(data.pos, 10, 10, 15, 150, "PropaneTank - ExplosionBig")
		self.network:sendToClients("cl_mode_blackhole_destroy", k)
		self.sv_blackholes[k] = nil
	end
end
-- #endregion

-- #region Grenade
function Amogus:sv_mode_grenade()
	local char = self.tool:getOwner().character
	local dir = char.direction

	local grenade = sm.shape.createPart(
		obj_interactive_propanetank_small,
		char.worldPosition + camAdjust + dir - sm.vec3.one() / 4,
		sm.quat.identity()
	)

	sm.physics.applyImpulse(
		grenade,
		dir * 50 * grenade.mass,
		true
	)
end
-- #endregion


function Amogus:server_onFixedUpdate( dt )
	for k, data in pairs(self.sv_blackholes) do
		data.lifeTime = data.lifeTime - dt
		if data.lifeTime <= 0 then
			self.network:sendToClients("cl_mode_blackhole_destroy", k)
			self.sv_blackholes[k] = nil
		else
			---@type Vec3
			local pos = data.pos
			local objs = sm.physics.getSphereContacts( pos, 30 )
			for i, obj in pairs(objs.bodies) do
				---@type Body
				local obj = obj --lol
				local mass = obj.mass

				sm.physics.applyImpulse(
					obj,
					((pos - obj.centerOfMassPosition) * mass * 2) - ( obj.velocity * mass * 0.3 ),
					true
				)
			end

			--[[for i, obj in pairs(objs.characters) do
				---@type Character
				local obj = obj --lol
				local mass = obj.mass
				sm.physics.applyImpulse( obj, ((pos - obj.worldPosition) * mass * 2) - ( obj.velocity * mass * 0.3 ) )
			end]]
		end
	end
end




function Amogus.loadAnimations( self )
	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			idle = { "Idle" },
			eat = { "Eat" },
			drink = { "Drink" },
			sprint = { "Sprint_fwd" },
			pickup = { "Pickup", { nextAnimation = "idle" } },
			putdown = { "Putdown" }
		}
	)
	local movementAnimations = {
		idle = "Idle",

		runFwd = "Run_fwd",
		runBwd = "Run_bwd",

		sprint = "Sprint_fwd",

		jump = "Jump",
		jumpUp = "Jump_up",
		jumpDown = "Jump_down",

		land = "Jump_land",
		landFwd = "Jump_land_fwd",
		landBwd = "Jump_land_bwd",

		crouchIdle = "Crouch_idle",
		crouchFwd = "Crouch_fwd",
		crouchBwd = "Crouch_bwd"
	}

	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	if self.isLocal then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				idle = { "Idle", { looping = true } },

				eat = { "Eat" },
				drink = { "Drink" },

				sprintInto = { "Sprint_into", { nextAnimation = "sprintIdle",  blendNext = 0.2 } },
				sprintIdle = { "Sprint_idle", { looping = true } },
				sprintExit = { "Sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },

				jump = { "Jump", { nextAnimation = "idle" } },
				land = { "Jump_land", { nextAnimation = "idle" } },

				equip = { "Pickup", { nextAnimation = "idle" } },
				unequip = { "Putdown" }
			}
		)
	end
	setTpAnimation( self.tpAnimations, "idle", 5.0 )

	self.normalFireMode = {
		fireCooldown = 0.20,
		spreadCooldown = 0.18,
		spreadIncrement = 2.6,
		spreadMinAngle = .25,
		spreadMaxAngle = 8,
		fireVelocity = 130.0,

		minDispersionStanding = 0.1,
		minDispersionCrouching = 0.04,

		maxMovementDispersion = 0.4,
		jumpDispersionMultiplier = 2
	}

	self.fireCooldownTimer = 0.0
	self.spreadCooldownTimer = 0.0

	self.movementDispersion = 0.0

	self.sprintCooldownTimer = 0.0
	self.sprintCooldown = 0.3

	self.aimBlendSpeed = 3.0
	self.blendTime = 0.2

	self.jointWeight = 0.0
	self.spineWeight = 0.0
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )

end

function Amogus.client_onUpdate( self, dt )
	for k, pos in pairs(self.cl_blackholes) do
		sm.particle.createParticle("paint_smoke", pos)
	end

	-- First person animation
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()

	if self.isLocal then
		if self.equipped then
			if isSprinting and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
				swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
			elseif not self.tool:isSprinting() and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
				swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
			end
		end
		updateFpAnimations( self.fpAnimations, self.equipped, dt )
	end

	if not self.equipped then
		if self.wantEquipped then
			self.wantEquipped = false
			self.equipped = true
		end
		return
	end

	-- Timers
	self.fireCooldownTimer = math.max( self.fireCooldownTimer - dt, 0.0 )
	self.spreadCooldownTimer = math.max( self.spreadCooldownTimer - dt, 0.0 )
	self.sprintCooldownTimer = math.max( self.sprintCooldownTimer - dt, 0.0 )


	if self.isLocal then
		local dispersion = 0.0
		local fireMode = self.normalFireMode
		local recoilDispersion = 1.0 - ( math.max( fireMode.minDispersionCrouching, fireMode.minDispersionStanding ) + fireMode.maxMovementDispersion )

		if isCrouching then
			dispersion = fireMode.minDispersionCrouching
		else
			dispersion = fireMode.minDispersionStanding
		end

		if self.tool:getRelativeMoveDirection():length() > 0 then
			dispersion = dispersion + fireMode.maxMovementDispersion * self.tool:getMovementSpeedFraction()
		end

		if not self.tool:isOnGround() then
			dispersion = dispersion * fireMode.jumpDispersionMultiplier
		end

		self.movementDispersion = dispersion

		self.spreadCooldownTimer = clamp( self.spreadCooldownTimer, 0.0, fireMode.spreadCooldown )
		local spreadFactor = fireMode.spreadCooldown > 0.0 and clamp( self.spreadCooldownTimer / fireMode.spreadCooldown, 0.0, 1.0 ) or 0.0

		self.tool:setDispersionFraction( clamp( self.movementDispersion + spreadFactor * recoilDispersion, 0.0, 1.0 ) )

		self.tool:setCrossHairAlpha( 1.0 )
		self.tool:setInteractionTextSuppressed( false )
	end

	-- Sprint block
	local blockSprint = self.sprintCooldownTimer > 0.0
	self.tool:setBlockSprint( blockSprint )

	local crouchWeight = self.tool:isCrouching() and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight

	local totalWeight = 0.0
	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

			if animation.time >= animation.info.duration - self.blendTime then
				if name == "pickup" then
					setTpAnimation( self.tpAnimations, "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 0.001 )
				end
			end
		else
			animation.weight = math.max( animation.weight - ( self.tpAnimations.blendSpeed * dt ), 0.0 )
		end

		totalWeight = totalWeight + animation.weight
	end

	totalWeight = totalWeight == 0 and 1.0 or totalWeight
	for name, animation in pairs( self.tpAnimations.animations ) do
		local weight = animation.weight / totalWeight
		if name == "idle" then
			self.tool:updateMovementAnimation( animation.time, weight )
		elseif animation.crouch then
			self.tool:updateAnimation( animation.info.name, animation.time, weight * normalWeight )
			self.tool:updateAnimation( animation.crouch.name, animation.time, weight * crouchWeight )
		else
			self.tool:updateAnimation( animation.info.name, animation.time, weight )
		end
	end

	-- Camera update
	local bobbing = 1
	local blend = 1 - 1 - 1 / self.aimBlendSpeed ^ (dt * 60 )
	self.aimWeight = sm.util.lerp( self.aimWeight, 0.0, blend )

	self.tool:updateCamera( 2.8, 30.0, sm.vec3.new( 0.65, 0.0, 0.05 ), self.aimWeight )
	self.tool:updateFpCamera( 30.0, sm.vec3.new( 0.0, 0.0, 0.0 ), self.aimWeight, bobbing )
end

function Amogus.client_onEquip( self, animate )

	if animate then
		sm.audio.play( "PotatoRifle - Equip", self.tool:getPosition() )
	end

	self.wantEquipped = true
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
	self.jointWeight = 0.0

	local currentRenderablesTp = {}
	local currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesFp[#currentRenderablesFp+1] = v end

	self.tool:setTpRenderables( currentRenderablesTp )
	if self.isLocal then
		self.tool:setFpRenderables( currentRenderablesFp )
	end

	self:loadAnimations()

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if self.isLocal then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end

	self:cl_updateColour()
end

function Amogus.client_onUnequip( self, animate )

	self.wantEquipped = false
	self.equipped = false
	if sm.exists( self.tool ) then
		if animate then
			sm.audio.play( "PotatoRifle - Unequip", self.tool:getPosition() )
		end
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.isLocal then
			self.tool:setMovementSlowDown( false )
			self.tool:setBlockSprint( false )
			self.tool:setCrossHairAlpha( 1.0 )
			self.tool:setInteractionTextSuppressed( false )
			if self.fpAnimations.currentAnimation ~= "unequip" then
				swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
			end
		end
	end
end

function Amogus:cl_onPrimaryUse( state )
	local func = self.modes[self.modIndex].lmbFuncs[state]
	if func then
		if func:sub(1,2) == "sv" then
			self.network:sendToServer(func)
		else
			self[func]( self )
		end
	end
end

function Amogus:cl_onSecondaryUse( state )
	local func = self.modes[self.modIndex].rmbFuncs[state]
	if func then
		if func:sub(1,2) == "sv" then
			self.network:sendToServer(func)
		else
			self[func]( self )
		end
	end
end

function Amogus:client_onEquippedUpdate( primaryState, secondaryState )
	if primaryState ~= self.prevPrimaryState then
		self:cl_onPrimaryUse( primaryState )
		self.prevPrimaryState = primaryState
	end

	if secondaryState ~= self.prevSecondaryState then
		self:cl_onSecondaryUse( secondaryState )
		self.prevSecondaryState = secondaryState
	end

	if self.modIndex == 1 then
		local char = self.owner.character
		local pos = sm.camera.getPosition()
		local hit, result = sm.physics.raycast( pos, pos + char.direction * 100, char )

		if hit then
			sm.gui.setInteractionText(
				sm.gui.getKeyBinding("Create", true).."Create explosion\t",
				sm.gui.getKeyBinding("Attack", true).."Create implosion",
				""
			)
		end
	elseif self.modIndex == 2 then
		local char = self.owner.character
		local pos = sm.camera.getPosition()
		local hit, result = sm.physics.raycast( pos, pos + char.direction * 100, char )

		sm.gui.setInteractionText(
			sm.gui.getKeyBinding("Create", true).."Spawn black hole\t",
			#self.cl_blackholes > 0 and sm.gui.getKeyBinding("Attack", true).."Detonate black hole(s)" or "",
			""
		)
	else
		sm.gui.setInteractionText("", sm.gui.getKeyBinding("Create", true).."Throw explosive", "")
	end

	return true, true
end
