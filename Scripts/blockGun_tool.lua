dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

local blockGunUUID = sm.uuid.new("6f346cef-4e6c-4d32-8dae-9e9c3e04230f")
local vec3_up = sm.vec3.new(0,0,1)
local vec3_zero = sm.vec3.zero()
local rad90 = math.rad(90)
local camRotAdjust = sm.quat.angleAxis(-rad90, vec3_up)

---@class BG_tool : ToolClass
---@field fpAnimations table
---@field tpAnimations table
---@field normalFireMode table
---@field aimFireMode table
---@field isLocal boolean
---@field aiming boolean
---@field hasGun boolean
---@field equipped boolean
---@field shootEffect Effect
---@field shootEffectFP Effect
---@field aimBlendSpeed number
---@field blendTime number
---@field sprintCooldown number
---@field movementDispersion number
---@field gun table
BG_tool = class()

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Base/char_spudgun_base_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Barrel/Barrel_basic/char_spudgun_barrel_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Sight/Sight_basic/char_spudgun_sight_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Stock/Stock_broom/char_spudgun_stock_broom.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Tank/Tank_basic/char_spudgun_tank_basic.rend"
}

local renderablesTp = {
	"$GAME_DATA/Character/Char_Male/Animations/char_male_tp_spudgun.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_tp_animlist.rend"
}
local renderablesFp = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_fp_animlist.rend",
	"$CONTENT_DATA/Tools/blockgun_fp.rend"
}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function BG_tool.client_onCreate( self )
	self.isLocal = self.tool:isLocal()
	self.hasGun = false
	self.gun = {}

	if not self.isLocal then return end

	self.canRegisterF = true
end

function BG_tool.server_onCreate( self )
	local data = self.storage:load()
	if data then
		self.network:sendToClients( "cl_onGunPickup", data )
	end
end

function BG_tool.loadAnimations( self )

	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			shoot = { "spudgun_shoot", { crouch = "spudgun_crouch_shoot" } },
			aim = { "spudgun_aim", { crouch = "spudgun_crouch_aim" } },
			aimShoot = { "spudgun_aim_shoot", { crouch = "spudgun_crouch_aim_shoot" } },
			idle = { "spudgun_idle" },
			pickup = { "spudgun_pickup", { nextAnimation = "idle" } },
			putdown = { "spudgun_putdown" }
		}
	)
	local movementAnimations = {
		idle = "spudgun_idle",
		--idleRelaxed = "spudgun_relax",

		sprint = "spudgun_sprint",
		runFwd = "spudgun_run_fwd",
		runBwd = "spudgun_run_bwd",

		jump = "spudgun_jump",
		jumpUp = "spudgun_jump_up",
		jumpDown = "spudgun_jump_down",

		land = "spudgun_jump_land",
		landFwd = "spudgun_jump_land_fwd",
		landBwd = "spudgun_jump_land_bwd",

		crouchIdle = "spudgun_crouch_idle",
		crouchFwd = "spudgun_crouch_fwd",
		crouchBwd = "spudgun_crouch_bwd"
	}

	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	setTpAnimation( self.tpAnimations, "idle", 5.0 )

	if self.isLocal then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "bg_pickup", { nextAnimation = "idle" } },
				unequip = { "bg_putdown" },

				idle = { "bg_idle", { looping = true } },
				shoot = { "bg_shoot", { nextAnimation = "idle" } },

				aimInto = { "bg_aim_into", { nextAnimation = "aimIdle" } },
				aimExit = { "bg_aim_exit", { nextAnimation = "idle", blendNext = 0 } },
				aimIdle = { "bg_aim_idle", { looping = true} },
				aimShoot = { "bg_aim_shoot", { nextAnimation = "aimIdle"} },

				sprintInto = { "bg_sprint_into", { nextAnimation = "sprintIdle",  blendNext = 0.2 } },
				sprintExit = { "bg_sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },
				sprintIdle = { "bg_sprint_idle", { looping = true } },
			}
		)
	end

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

	self.aimFireMode = {
		fireCooldown = 0.20,
		spreadCooldown = 0.18,
		spreadIncrement = 1.3,
		spreadMinAngle = 0,
		spreadMaxAngle = 8,
		fireVelocity =  130.0,

		minDispersionStanding = 0.01,
		minDispersionCrouching = 0.01,

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

function BG_tool.client_onUpdate( self, dt )
	--[[sm.camera.setCameraState(3)
	sm.camera.setPosition(self.tool:getPosition() + sm.vec3.new(0,1,0) + self.tool:getDirection() * 2)
	sm.camera.setDirection(-self.tool:getDirection() - sm.vec3.new(0,1,0))
	sm.camera.setFov(90)]]

	-- First person animation
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()

	if self.isLocal and self.hasGun then
		self:updateFp( dt, isSprinting )
	end

	if not self.equipped then
		if self.wantEquipped then
			self.wantEquipped = false
			self.equipped = true
		end
		return
	end

	if self.hasGun then
		local dir = self.tool:getDirection()
		local camRot = self:getCamRot(dir)
		local handPos = self.tool:isInFirstPersonView() and self.tool:getFpBonePos("jnt_right_weapon") or self.tool:getTpBonePos("jnt_right_weapon")

		if self.equipped then
			for k, data in pairs(self.gun.effects) do
				local effect = data.effect
				effect:setPosition( handPos + camRot * data.pos )
				effect:setRotation( camRot * data.rot )

				if not effect:isPlaying() then
					effect:start()
				end
			end
		end

		local pos = handPos + camRot * (self.gun.data.muzzleOffset or vec3_zero)
		local effectPos, rot
		if self.isLocal then
			--local dir = sm.localPlayer.getDirection()
			--local pos = self.tool:getFpBonePos( "pejnt_barrel" )
			effectPos = self.aiming and pos + dir * 0.45 or pos + dir * 0.2
			rot = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), dir )

			self.shootEffectFP:setPosition( effectPos )
			self.shootEffectFP:setVelocity( self.tool:getMovementVelocity() )
			self.shootEffectFP:setRotation( rot )
		end

		--local pos = self.tool:getTpBonePos( "pejnt_barrel" )
		--local dir = self.tool:getTpBoneDir( "pejnt_barrel" )
		effectPos = pos + dir * 0.2
		rot = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), dir )

		self.shootEffect:setPosition( effectPos )
		self.shootEffect:setVelocity( self.tool:getMovementVelocity() )
		self.shootEffect:setRotation( rot )
	end

	-- Timers
	self.fireCooldownTimer = math.max( self.fireCooldownTimer - dt, 0.0 )
	self.spreadCooldownTimer = math.max( self.spreadCooldownTimer - dt, 0.0 )
	self.sprintCooldownTimer = math.max( self.sprintCooldownTimer - dt, 0.0 )


	if self.isLocal then
		local dispersion = 0.0
		local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
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

		if self.aiming then
			if self.tool:isInFirstPersonView() then
				self.tool:setCrossHairAlpha( 0.0 )
			else
				self.tool:setCrossHairAlpha( 1.0 )
			end
			self.tool:setInteractionTextSuppressed( true )
		else
			self.tool:setCrossHairAlpha( 1.0 )
			self.tool:setInteractionTextSuppressed( false )
		end
	end

	-- Sprint block
	local blockSprint = self.aiming or self.sprintCooldownTimer > 0.0
	self.tool:setBlockSprint( blockSprint )

	if self.hasGun then
		self:updateTP( dt, isSprinting, isCrouching )
	end

	-- Camera update
	local bobbing = 1
	if self.aiming then
		local blend = 1 - (1 - 1 / self.aimBlendSpeed) ^ (dt * 60)
		self.aimWeight = sm.util.lerp( self.aimWeight, 1.0, blend )
		bobbing = 0.12
	else
		local blend = 1 - (1 - 1 / self.aimBlendSpeed) ^ (dt * 60)
		self.aimWeight = sm.util.lerp( self.aimWeight, 0.0, blend )
		bobbing = 1
	end

	local fov = math.ceil(sm.camera.getDefaultFov() * (self.hasGun and self.gun.data.aimFOVScale or 1))
	self.tool:updateCamera( 2.8, fov, sm.vec3.new( 0.65, 0.0, 0.05 ), self.aimWeight )
	self.tool:updateFpCamera( fov, sm.vec3.new( 0.0, 0.0, 0.0 ), self.aimWeight, bobbing )
end




function BG_tool:client_onReload()
	return true
end

function BG_tool:client_onToggle()
	return true
end


function BG_tool:updateRenderables()
	local currentRenderablesTp = {}
	local currentRenderablesFp = {}

	if self.hasGun then
		for k, v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
		for k, v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	end

	--[[for k, v in pairs( renderables ) do
		currentRenderablesTp[#currentRenderablesTp+1] = v
		currentRenderablesFp[#currentRenderablesFp+1] = v
	end]]

	self.tool:setTpRenderables( currentRenderablesTp )
	if self.isLocal then
		self.tool:setFpRenderables( currentRenderablesFp )
	end
end

function BG_tool:updateFp( dt, isSprinting )
	if self.equipped then
		if isSprinting and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
			swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
		elseif not self.tool:isSprinting() and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
			swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
		end

		if self.aiming and not isAnyOf( self.fpAnimations.currentAnimation, { "aimInto", "aimIdle", "aimShoot" } ) then
			swapFpAnimation( self.fpAnimations, "aimExit", "aimInto", 0.0 )
		end
		if not self.aiming and isAnyOf( self.fpAnimations.currentAnimation, { "aimInto", "aimIdle", "aimShoot" } ) then
			swapFpAnimation( self.fpAnimations, "aimInto", "aimExit", 0.0 )
		end
	end
	updateFpAnimations( self.fpAnimations, self.equipped, dt )
end

function BG_tool:updateTP( dt, isSprinting, isCrouching )
	local playerDir = self.tool:getSmoothDirection()
	local angle = math.asin( playerDir:dot( sm.vec3.new( 0, 0, 1 ) ) ) / ( math.pi / 2 )

	local crouchWeight = self.tool:isCrouching() and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight

	local totalWeight = 0.0
	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

			if animation.time >= animation.info.duration - self.blendTime then
				if ( name == "shoot" or name == "aimShoot" ) then
					setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 10.0 )
				elseif name == "pickup" then
					setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 0.001 )
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

	-- Third Person joint lock
	local relativeMoveDirection = self.tool:getRelativeMoveDirection()
	if ( ( ( isAnyOf( self.tpAnimations.currentAnimation, { "aimInto", "aim", "shoot" } ) and ( relativeMoveDirection:length() > 0 or isCrouching) ) or ( self.aiming and ( relativeMoveDirection:length() > 0 or isCrouching) ) ) and not isSprinting ) then
		self.jointWeight = math.min( self.jointWeight + ( 10.0 * dt ), 1.0 )
	else
		self.jointWeight = math.max( self.jointWeight - ( 6.0 * dt ), 0.0 )
	end

	if ( not isSprinting ) then
		self.spineWeight = math.min( self.spineWeight + ( 10.0 * dt ), 1.0 )
	else
		self.spineWeight = math.max( self.spineWeight - ( 10.0 * dt ), 0.0 )
	end

	local finalAngle = ( 0.5 + angle * 0.5 )
	self.tool:updateAnimation( "spudgun_spine_bend", finalAngle, self.spineWeight )

	local totalOffsetZ = lerp( -22.0, -26.0, crouchWeight )
	local totalOffsetY = lerp( 6.0, 12.0, crouchWeight )
	local crouchTotalOffsetX = clamp( ( angle * 60.0 ) -15.0, -60.0, 40.0 )
	local normalTotalOffsetX = clamp( ( angle * 50.0 ), -45.0, 50.0 )
	local totalOffsetX = lerp( normalTotalOffsetX, crouchTotalOffsetX , crouchWeight )

	local finalJointWeight = ( self.jointWeight )


	self.tool:updateJoint( "jnt_hips", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.35 * finalJointWeight * ( normalWeight ) )

	local crouchSpineWeight = ( 0.35 / 3 ) * crouchWeight

	self.tool:updateJoint( "jnt_spine1", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight )  * finalJointWeight )
	self.tool:updateJoint( "jnt_spine2", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_spine3", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.45 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_head", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.3 * finalJointWeight )
end

function BG_tool:sv_onGunPickup( args )
	local data = args.gun.publicData
	if data == nil then return end

	local shapes = {}
	local referencePoint = args.blockGun.worldPosition
	for k, shape in pairs(args.body:getShapes()) do --args.body:getCreationShapes()
		shapes[#shapes+1] = {
			uuid = shape.uuid,
			color = shape.color,
			pos = (shape.worldPosition - referencePoint),
			rot = shape.worldRotation,
			boundingBox = shape:getBoundingBox()
		}
	end

	--local saved = { settings = data, shapes = args.body:getCreationShapes(), blockGun = args.blockGun }
	local saved = { settings = data, shapes = shapes }
	self.storage:save( saved )
	self.network:sendToClients( "cl_onGunPickup", saved )
end

function BG_tool:cl_onGunPickup( data )
	if self.hasGun then self:cl_clearGun() end

	self.gun.data = data.settings
	self.gun.effects = {}

	local scale = self.gun.data.scale
	--[[local referencePoint = data.blockGun.worldPosition
	for k, shape in pairs(data.shapes) do
		local effect = sm.effect.createEffect( "ShapeRenderable" )
		local uuid = shape.uuid
		effect:setParameter("uuid", uuid)
		effect:setParameter("color", shape.color)
		effect:setScale( (sm.item.isBlock(uuid) and shape:getBoundingBox() or sm.vec3.one() * 0.25) * scale )

		self.gun.effects[#self.gun.effects+1] = {
			effect = effect,
			pos = (shape.worldPosition - referencePoint) * scale,
			rot = shape.worldRotation
		}
	end]]

	for k, shape in pairs(data.shapes) do
		local uuid = shape.uuid
		if uuid ~= blockGunUUID then
			local effect = sm.effect.createEffect( "ShapeRenderable" )
			effect:setParameter("uuid", uuid)
			effect:setParameter("color", shape.color)
			effect:setScale( (sm.item.isBlock(uuid) and shape.boundingBox or sm.vec3.one() * 0.25) * scale )

			self.gun.effects[#self.gun.effects+1] = {
				effect = effect,
				pos = shape.pos * scale,
				rot = shape.rot
			}
		end
	end

	if self.gun.data.muzzleOffset then
		self.gun.data.muzzleOffset = self.gun.data.muzzleOffset * scale
	end

	self.hasGun = true

	self:updateRenderables()
	self:loadAnimations()

	local effects = self.gun.data.muzzleEffect
	self.shootEffect = sm.effect.createEffect( effects.tp )

	if self.isLocal then
		self.shootEffectFP = sm.effect.createEffect( effects.fp )

		self:updateFireModes()
	end
end

function BG_tool:updateFireModes()
	local settings = self.gun.data
	local fireCooldown = settings.shotDelay
	local spreadMaxAngle = settings.spread
	local velocity = settings.velocity
	self.normalFireMode.fireCooldown = fireCooldown
	self.normalFireMode.spreadMaxAngle = spreadMaxAngle
	self.normalFireMode.fireVelocity = velocity

	self.aimFireMode.fireCooldown = fireCooldown
	self.aimFireMode.spreadMaxAngle = spreadMaxAngle
	self.aimFireMode.fireVelocity = velocity
end

function BG_tool:sv_clearGun()
	self.storage:save({})
	self.network:sendToClients("cl_clearGun")
end

function BG_tool:cl_clearGun()
	for k, data in pairs(self.gun.effects) do
		data.effect:stop()
	end

	self.gun = {}
	self.hasGun = false

	self:updateRenderables()
	self:loadAnimations()

	self.shootEffect:destroy()
	if self.isLocal then
		self.shootEffectFP:destroy()
	end
end

function BG_tool:client_onDestroy()
	if self.hasGun then
		for k, data in pairs(self.gun.effects) do
			data.effect:destroy()
		end
	end
end




function BG_tool.client_onEquip( self, animate )
	if animate then
		sm.audio.play( "PotatoRifle - Equip", self.tool:getPosition() )
	end

	self.wantEquipped = true
	self.aiming = false
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
	self.jointWeight = 0.0

	self:updateRenderables()

	if self.hasGun or self.tpAnimations == nil then
		self:loadAnimations()
	end

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if self.isLocal then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )

		if self.hasGun then
			self:updateFireModes()
		end
	end
end

function BG_tool.client_onUnequip( self, animate )
	self.wantEquipped = false
	self.equipped = false
	self.aiming = false
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

	if self.hasGun then
		for k, data in pairs(self.gun.effects) do
			data.effect:stop()
		end
	end
end

function BG_tool.sv_n_onAim( self, aiming )
	self.network:sendToClients( "cl_n_onAim", aiming )
end

function BG_tool.cl_n_onAim( self, aiming )
	if not self.isLocal and self.tool:isEquipped() then
		self:onAim( aiming )
	end
end

function BG_tool.onAim( self, aiming )
	self.aiming = aiming
	if self.tpAnimations.currentAnimation == "idle" or self.tpAnimations.currentAnimation == "aim" or self.tpAnimations.currentAnimation == "relax" and self.aiming then
		setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 5.0 )
	end
end

function BG_tool.sv_n_onShoot( self, dir )
	self.network:sendToClients( "cl_n_onShoot", dir )
end

function BG_tool.cl_n_onShoot( self, dir )
	if not self.isLocal and self.tool:isEquipped() then
		self:onShoot( dir )
	end
end

function BG_tool.onShoot( self, dir )

	self.tpAnimations.animations.idle.time = 0
	self.tpAnimations.animations.shoot.time = 0
	self.tpAnimations.animations.aimShoot.time = 0

	setTpAnimation( self.tpAnimations, self.aiming and "aimShoot" or "shoot", 10.0 )

	if self.tool:isInFirstPersonView() then
		self.shootEffectFP:start()
	else
		self.shootEffect:start()
	end

end

function BG_tool.calculateFirePosition( self )
	local crouching = self.tool:isCrouching()
	local firstPerson = self.tool:isInFirstPersonView()
	local dir = sm.localPlayer.getDirection()
	local pitch = math.asin( dir.z )
	local right = sm.localPlayer.getRight()

	local fireOffset = sm.vec3.new( 0.0, 0.0, 0.0 )

	if crouching then
		fireOffset.z = 0.15
	else
		fireOffset.z = 0.45
	end

	if firstPerson then
		if not self.aiming then
			fireOffset = fireOffset + right * 0.05
		end
	else
		fireOffset = fireOffset + right * 0.25
		fireOffset = fireOffset:rotate( math.rad( pitch ), right )
	end
	local firePosition = GetOwnerPosition( self.tool ) + fireOffset
	return firePosition
end

function BG_tool.calculateTpMuzzlePos( self )
	local crouching = self.tool:isCrouching()
	local dir = sm.localPlayer.getDirection()
	local pitch = math.asin( dir.z )
	local right = sm.localPlayer.getRight()
	local up = right:cross(dir)

	local fakeOffset = sm.vec3.new( 0.0, 0.0, 0.0 )

	--General offset
	fakeOffset = fakeOffset + right * 0.25
	fakeOffset = fakeOffset + dir * 0.5
	fakeOffset = fakeOffset + up * 0.25

	--Action offset
	local pitchFraction = pitch / ( math.pi * 0.5 )
	if crouching then
		fakeOffset = fakeOffset + dir * 0.2
		fakeOffset = fakeOffset + up * 0.1
		fakeOffset = fakeOffset - right * 0.05

		if pitchFraction > 0.0 then
			fakeOffset = fakeOffset - up * 0.2 * pitchFraction
		else
			fakeOffset = fakeOffset + up * 0.1 * math.abs( pitchFraction )
		end
	else
		fakeOffset = fakeOffset + up * 0.1 *  math.abs( pitchFraction )
	end

	local fakePosition = fakeOffset + GetOwnerPosition( self.tool )
	return fakePosition
end

---@return Vec3
function BG_tool.calculateFpMuzzlePos( self )
	local fovScale = ( sm.camera.getFov() - 45 ) / 45

	local up = sm.localPlayer.getUp()
	local dir = sm.localPlayer.getDirection()
	local right = sm.localPlayer.getRight()

	local muzzlePos45 = sm.vec3.new( 0.0, 0.0, 0.0 )
	local muzzlePos90 = sm.vec3.new( 0.0, 0.0, 0.0 )

	if self.aiming then
		muzzlePos45 = muzzlePos45 - up * 0.2
		muzzlePos45 = muzzlePos45 + dir * 0.5

		muzzlePos90 = muzzlePos90 - up * 0.5
		muzzlePos90 = muzzlePos90 - dir * 0.6
	else
		muzzlePos45 = muzzlePos45 - up * 0.15
		muzzlePos45 = muzzlePos45 + right * 0.2
		muzzlePos45 = muzzlePos45 + dir * 1.25

		muzzlePos90 = muzzlePos90 - up * 0.15
		muzzlePos90 = muzzlePos90 + right * 0.2
		muzzlePos90 = muzzlePos90 + dir * 0.25
	end

	return self.tool:getTpBonePos("jnt_right_weapon") + sm.vec3.lerp( muzzlePos45, muzzlePos90, fovScale )
end

function BG_tool.cl_onPrimaryUse( self, state )
	if self.tool:getOwner().character == nil then
		return
	end

	if self.fireCooldownTimer <= 0.0 then --and state == sm.tool.interactState.start then

		if not sm.game.getEnableAmmoConsumption() or sm.container.canSpend( sm.localPlayer.getInventory(), obj_plantables_potato, 1 ) then
			local firstPerson = self.tool:isInFirstPersonView()

			local dir = sm.localPlayer.getDirection()

			local firePos = self:calculateFirePosition()
			local fakePosition = self:calculateTpMuzzlePos()
			local fakePositionSelf = fakePosition
			if firstPerson then
				fakePositionSelf = self:calculateFpMuzzlePos()
			end

			-- Aim assist
			if not firstPerson then
				local raycastPos = sm.camera.getPosition() + sm.camera.getDirection() * sm.camera.getDirection():dot( GetOwnerPosition( self.tool ) - sm.camera.getPosition() )
				local hit, result = sm.localPlayer.getRaycast( 250, raycastPos, sm.camera.getDirection() )
				if hit then
					local norDir = sm.vec3.normalize( result.pointWorld - firePos )
					local dirDot = norDir:dot( dir )

					if dirDot > 0.96592583 then -- max 15 degrees off
						dir = norDir
					else
						local radsOff = math.asin( dirDot )
						dir = sm.vec3.lerp( dir, norDir, math.tan( radsOff ) / 3.7320508 ) -- if more than 15, make it 15
					end
				end
			end

			dir = dir:rotate( math.rad( 0.955 ), sm.camera.getRight() ) -- 50 m sight calibration

			-- Spread
			local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
			local recoilDispersion = 1.0 - ( math.max(fireMode.minDispersionCrouching, fireMode.minDispersionStanding ) + fireMode.maxMovementDispersion )

			local spreadFactor = fireMode.spreadCooldown > 0.0 and clamp( self.spreadCooldownTimer / fireMode.spreadCooldown, 0.0, 1.0 ) or 0.0
			spreadFactor = clamp( self.movementDispersion + spreadFactor * recoilDispersion, 0.0, 1.0 )
			local spreadDeg =  fireMode.spreadMinAngle + ( fireMode.spreadMaxAngle - fireMode.spreadMinAngle ) * spreadFactor

			dir = sm.noise.gunSpread( dir, spreadDeg )

			local data = self.gun.data
			sm.projectile.projectileAttack( data.projectile, data.damage, firePos, dir * fireMode.fireVelocity, self.tool:getOwner(), fakePosition, fakePositionSelf )

			-- Timers
			self.fireCooldownTimer = fireMode.fireCooldown
			self.spreadCooldownTimer = math.min( self.spreadCooldownTimer + fireMode.spreadIncrement, fireMode.spreadCooldown )
			self.sprintCooldownTimer = self.sprintCooldown

			-- Send TP shoot over network and dircly to self
			self:onShoot( dir )
			self.network:sendToServer( "sv_n_onShoot", dir )

			-- Play FP shoot animation
			setFpAnimation( self.fpAnimations, self.aiming and "aimShoot" or "shoot", 0.05 )
		else
			local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
			self.fireCooldownTimer = fireMode.fireCooldown
			sm.audio.play( "PotatoRifle - NoAmmo" )
		end
	end
end

function BG_tool.cl_onSecondaryUse( self, state )
	local aiming = isAnyOf(state, { 1, 2 }) and self.gun.data.canAim
	if aiming ~= self.aiming then
		self.aiming = aiming
		self.tpAnimations.animations.idle.time = 0

		self:onAim( self.aiming )
		self.tool:setMovementSlowDown( self.aiming )
		self.network:sendToServer( "sv_n_onAim", self.aiming )
	end
end

function BG_tool.client_onEquippedUpdate( self, lmb, rmb, f )
	if not f then self.canRegisterF = true end

	if self.canRegisterF then
		if self.hasGun then
			if f then
				self.network:sendToServer("sv_clearGun")
				self.canRegisterF = false
			end
		else
			local hit, result = sm.localPlayer.getRaycast( 7.5 )
			local gun_int, gun_body, gun_shape

			if hit and result.type == "body" then
				local body = result:getBody()
				for k, int in pairs(body:getInteractables()) do
					local shape = int:getShape()
					if shape.uuid == blockGunUUID then
						gun_int, gun_body, gun_shape = int, body, shape
						break
					end
				end

				if gun_int then
					sm.gui.setInteractionText( "", sm.gui.getKeyBinding("ForceBuild", true), "Pick up weapon" )

					if f then
						self.network:sendToServer(
							"sv_onGunPickup",
							{
								gun = gun_int,
								body = gun_body,
								blockGun = gun_shape
							}
						)

						self.canRegisterF = false
					end
				end
			end
		end
	end

	if not self.hasGun then return true, true end

	local data = self.gun.data
	if lmb == 1 or data.fullAuto and lmb == 2 then
		self:cl_onPrimaryUse( lmb )
		self.prevPrimaryState = lmb
	end

	if rmb ~= self.prevSecondaryState then
		self:cl_onSecondaryUse( rmb )
		self.prevSecondaryState = rmb
	end

	return true, true
end



function BG_tool:getRotation( forward, up )
    local vector = sm.vec3.normalize( forward )
    local vector2 = sm.vec3.normalize( sm.vec3.cross( up, vector ) )
    local vector3 = sm.vec3.cross( vector, vector2 )
    local m00 = vector2.x
    local m01 = vector2.y
    local m02 = vector2.z
    local m10 = vector3.x
    local m11 = vector3.y
    local m12 = vector3.z
    local m20 = vector.x
    local m21 = vector.y
    local m22 = vector.z
    local num8 = (m00 + m11) + m22
	local quaternion = sm.quat.identity()
    if num8 > 0 then
        local num = math.sqrt(num8 + 1)
        quaternion.w = num * 0.5
        num = 0.5 / num
        quaternion.x = (m12 - m21) * num
        quaternion.y = (m20 - m02) * num
        quaternion.z = (m01 - m10) * num
        return quaternion
    end
    if (m00 >= m11) and (m00 >= m22) then
        local num7 = math.sqrt(((1 + m00) - m11) - m22)
        local num4 = 0.5 / num7
        quaternion.x = 0.5 * num7
        quaternion.y = (m01 + m10) * num4
        quaternion.z = (m02 + m20) * num4
        quaternion.w = (m12 - m21) * num4
        return quaternion
    end
    if m11 > m22 then
        local num6 = math.sqrt(((1 + m11) - m00) - m22)
		local num3 = 0.5 / num6
        quaternion.x = (m10+ m01) * num3
        quaternion.y = 0.5 * num6
        quaternion.z = (m21 + m12) * num3
        quaternion.w = (m20 - m02) * num3
        return quaternion
    end
    local num5 = math.sqrt(((1 + m22) - m00) - m11)
    local num2 = 0.5 / num5
    quaternion.x = (m20 + m02) * num2
    quaternion.y = (m21 + m12) * num2
    quaternion.z = 0.5 * num5;
    quaternion.w = (m01 - m10) * num2
    return quaternion
end

function BG_tool:getCamRot( dir )
	return self:getRotation(dir:rotate(rad90, dir:cross(vec3_up)), dir) * camRotAdjust
end