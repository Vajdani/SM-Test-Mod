dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"

---@class Bomber : ToolClass
---@field tpAnimations table
---@field fpAnimations table
---@field normalFireMode table
---@field aimFireMode table
---@field cl table
---@field aiming boolean
---@field blendTime number
---@field aimBlendSpeed number
---@field shootEffect Effect
---@field shootEffectFP Effect
---@field fireCooldownTimer number
Bomber = class()
Bomber.mods = {
    {
        name = "Carpet Bomb",
        fun = "cl_mode_carpet",
        colour = sm.color.new(1,1,0),
        cycles = 15,
        damage = 100,
        vel = 10
    },
    {
        name = "Air Strike",
        fun = "cl_mode_strike",
        colour = sm.color.new(1,0,0),
        cycles = function() return math.random( 15, 25 ) end,
        getRandomOffset = function() return sm.vec3.new(math.random( -8, 8 ), math.random( -8, 8 ), 0) / 4 end,
        range = 1000,
        damage = 100,
        vel = 50
    },
    {
        name = "Annoy",
        fun = "cl_mode_annoy",
        colour = sm.color.new(0,1,0),
        getRandomOffset = function() return sm.vec3.new(math.random( -15, 15 ), math.random( -15, 15 ), math.random( 2, 8 )) end,
        timerTicks = 4,
        range = 1000,
        damage = 1,
        vel = 420
    },
    {
        name = "Aimbot",
        fun = "cl_mode_aimbot",
        onToggle = "cl_mode_aimbot_reset",
        onSecondary = "cl_mode_aimbot_projectileGui",
        colour = sm.color.new(0,1,1),
        projectileNames = {
            "Potato",
            "Tape",
            "Explosive Tape"
        },
        nameToProjectile = {
            Potato = projectile_potato,
            Tape = projectile_tape,
            ["Explosive Tape"] = projectile_explosivetape
        },
        range = 1000,
        damage = 100,
        vel = 130
    },
    {
        name = "Black Hole",
        fun = "cl_mode_hole",
        colour = sm.color.new(0,0,0),
        radius = 20,
        range = 50
    },
    {
        name = "Sticky Grenade Launcher",
        fun = "cl_mode_sticky",
        onSecondary = "cl_mode_sticky_detonate",
        colour = sm.color.new(0,0,1),
        uuid = sm.uuid.new("8d955bd1-4a39-432e-9eb3-0ec8f620a9c8"),
        vel = sm.vec3.one() * 25
    },
    {
        name = "Saw Launcher",
        fun = "cl_mode_saw",
        colour = sm.item.getShapeDefaultColor(obj_powertools_sawblade),
        uuid = obj_powertools_sawblade,
        vel = sm.vec3.one() * 75,
		torque = sm.vec3.new(0,0,1)
    }
}

local vector_up = sm.vec3.new(0,0,1)
local camAdjust = sm.vec3.new(0,0,0.575)

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Base/char_spudgun_base_basic.rend",
	"$CONTENT_DATA/Tools/char_spudgun_barrel_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Sight/Sight_basic/char_spudgun_sight_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Stock/Stock_broom/char_spudgun_stock_broom.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Tank/Tank_basic/char_spudgun_tank_basic.rend"
}
local renderablesTp = {
    "$GAME_DATA/Character/Char_Male/Animations/char_male_tp_spudgun.rend",
    "$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_tp_animlist.rend"
}
local renderablesFp = {
    "$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_fp_animlist.rend"
}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function Bomber:server_onCreate()
    self.sv = {}
    self.sv.blacHoleActive = false
    self.sv.blackHoleTrigger = sm.areaTrigger.createSphere(
        self.mods[5].radius,
        self.tool:getOwner().character.worldPosition,
        sm.quat.identity(),
        sm.areaTrigger.filter.character + sm.areaTrigger.filter.dynamicBody
    )

    self.sv.stickies = {}
end

function Bomber.client_onCreate( self )
	self.shootEffect = sm.effect.createEffect( "SpudgunBasic - BasicMuzzel" )
	self.shootEffectFP = sm.effect.createEffect( "SpudgunBasic - FPBasicMuzzel" )

    self.cl = {}
    self.cl.modIndex = 1
    self.cl.public = self.tool:getOwner():getClientPublicData()

    self.cl.blackHoleEffect = sm.effect.createEffect( "Thruster - Level 5" )

    self:loadAnimations()

    if not self.tool:isLocal() then return end

    self.cl.public.lmb = 0
    self.cl.public.rmb = 0

    self.cl.targetsToAnnoy = {}
    self.cl.annoyTimer = Timer()
    self.cl.annoyTimer:start(self.mods[3].timerTicks)

    self.cl.aimbotTarget = nil
    self.cl.aimbotProjectile = projectile_potato
    self.cl.aimbotGui = sm.gui.createGuiFromLayout( "$CONTENT_DATA/Gui/aimbot.layout" )
    self.cl.aimbotGui:createDropDown( "projectile_dropdown", "cl_mode_aimbot_projectileDropdown", self.mods[4].projectileNames )
    self.cl.aimbotTargetMarker = sm.gui.createWorldIconGui( 50, 50 )
    self.cl.aimbotTargetMarker:setImage( "Icon", "$CONTENT_DATA/Gui/aimbot_marker.png" )
end


function Bomber:server_onFixedUpdate()
    local char = self.tool:getOwner().character
    local newPos = char.worldPosition + char.direction * (self.mods[5].radius + 1)
    self.sv.blackHoleTrigger:setWorldPosition( newPos )

    if self.sv.blacHoleActive then
        for k, obj in pairs(self.sv.blackHoleTrigger:getContents()) do
            if sm.exists(obj) and obj ~= char then
                local impulse = (newPos - obj.worldPosition):normalize() * obj.mass * 1.25
                if type(obj) == "Character" and obj:isTumbling() then
                    obj:applyTumblingImpulse( impulse )
                else
                    sm.physics.applyImpulse( obj, impulse, true )
                end
            end
        end
    end
end

function Bomber:sv_setBlackHoleActive( toggle )
    self.sv.blacHoleActive = toggle
end

---@class BlockLaunchMod
---@field uuid Uuid
---@field vel Vec3
---@field torque Vec3

function Bomber:sv_shootSticky(index)
	---@type BlockLaunchMod
    local mod = self.mods[index]
    local char = self.tool:getOwner().character
    local dir = char.direction
    local sticky = sm.shape.createPart(
		mod.uuid,
		char.worldPosition + camAdjust + dir * 2 - sm.vec3.one() / 4,
		sm.quat.angleAxis(math.rad(90), sm.vec3.new(1,0,0)),
		true,
		true
	)
    sm.physics.applyImpulse(sticky, mod.vel * dir * sticky.mass, true )
	if mod.torque then
		sm.physics.applyTorque(sticky.body, mod.torque * sticky.mass, true)
	end

    sticky.interactable:setPublicData( { tool = self.tool } )
end

function Bomber:sv_addSticky( sticky )
    self.sv.stickies[#self.sv.stickies+1] = sticky
end

function Bomber:sv_detonateStickies()
    for k, sticky in pairs(self.sv.stickies) do
        if sm.exists(sticky) then
            sm.event.sendToInteractable( sticky.interactable, "sv_explode" )
        end
    end

    for k, sticky in pairs(self.sv.stickies) do
        if not sm.exists(sticky) then
            self.sv.stickies[k] = nil
        end
    end
end

function Bomber:cl_mode_carpet( state )
    if state ~= sm.tool.interactState.start then return end

    local mod = self.mods[1]
    local player = sm.localPlayer.getPlayer()
    local char = player.character
    local dir = char.direction * 2
    local pos = char.worldPosition + dir * 3
    local fireDir = vector_up * -mod.vel
    local up = vector_up * 5

    for i = 1, mod.cycles do
        sm.projectile.projectileAttack(
            projectile_explosivetape,
            mod.damage,
            pos + dir * i + up + sm.vec3.new(0,0,i),
            fireDir,
            player
        )
    end
end

function Bomber:cl_mode_strike( state )
    if state ~= sm.tool.interactState.start then return end

    local mod = self.mods[2]
    local hit, result = sm.localPlayer.getRaycast( mod.range )
    if not hit then return end
    local player = sm.localPlayer.getPlayer()
    local pos = result.pointWorld
    local fireDir = vector_up * -1
    local up = vector_up * 10

    for i = 1, mod.cycles() do
        sm.projectile.projectileAttack(
            projectile_explosivetape,
            mod.damage,
            pos + mod.getRandomOffset() + up,
            fireDir,
            player
        )
    end
end

function Bomber:cl_mode_annoy( state )
    if state ~= sm.tool.interactState.start then return end

    local mod = self.mods[3]
    local hit, result = sm.localPlayer.getRaycast( mod.range )
    if not hit or not isAnyOf(result.type, {"character", "body"}) then return end

    self.cl.targetsToAnnoy[#self.cl.targetsToAnnoy+1] = result:getCharacter() or result:getBody()
    sm.gui.displayAlertText("Target selected!", 2.5)
end

function Bomber:cl_mode_aimbot( state )
    if state ~= sm.tool.interactState.start then return end

    local mod = self.mods[4]

    if not sm.exists(self.cl.aimbotTarget) then self.cl.aimbotTarget = nil end

    if self.cl.aimbotTarget == nil then
        local hit, result = sm.localPlayer.getRaycast( mod.range )
        if not hit or not isAnyOf(result.type, {"character", "body"}) then return end

		---@type Character|Body
        self.cl.aimbotTarget = result:getCharacter() or result:getBody()
        sm.gui.displayAlertText("Target selected!", 2.5)
    else
        local firePos = self:calculateFirePosition()
        local low, high = sm.projectile.solveBallisticArc(
            firePos,
            type(self.cl.aimbotTarget) == "Character" and
            self.cl.aimbotTarget.worldPosition or
            self.cl.aimbotTarget:getCenterOfMassPosition(),
            mod.vel,
            10
        )

        sm.projectile.projectileAttack(
            self.cl.aimbotProjectile,
            mod.damage,
            firePos,
            low or high,
            sm.localPlayer.getPlayer()
        )
    end
end

function Bomber:cl_mode_aimbot_reset( state )
    if state ~= sm.tool.interactState.start then return end

    self.cl.aimbotTarget = nil
    sm.gui.displayAlertText("Aimbot target cleared!", 2.5)
end

function Bomber:cl_mode_aimbot_projectileGui( state )
    if state ~= sm.tool.interactState.start then return end

    self.cl.aimbotGui:open()
end

function Bomber:cl_mode_aimbot_projectileDropdown( projectileName )
    self.cl.aimbotProjectile = self.mods[4].nameToProjectile[projectileName]
end

function Bomber:cl_mode_hole( state )
    self.network:sendToServer("sv_setBlackHoleActive", state == sm.tool.interactState.start or state == sm.tool.interactState.hold)
end

function Bomber:cl_mode_sticky( state )
    if state ~= sm.tool.interactState.start then return end

    self.network:sendToServer("sv_shootSticky", 6)
end

function Bomber:cl_mode_sticky_detonate( state )
    if state ~= sm.tool.interactState.start then return end

    self.network:sendToServer("sv_detonateStickies")
end

function Bomber:cl_mode_saw( state )
    if state ~= sm.tool.interactState.start then return end

    self.network:sendToServer("sv_shootSticky", 7)
end

function Bomber:client_onReload()
    self.cl.modIndex = self.cl.modIndex < #self.mods and self.cl.modIndex + 1 or 1
    local mod = self.mods[self.cl.modIndex]
    sm.gui.displayAlertText( "#"..mod.colour:getHexStr():sub(1, 6)..mod.name, 2.5 )
    self.network:sendToServer("sv_modSwitch", self.cl.modIndex)

    return true
end

function Bomber:client_onToggle()
    local func = self[self.mods[self.cl.modIndex].onToggle]
    if func then
        func(self)
    end

    return true
end

function Bomber:sv_modSwitch( index )
    self.network:sendToClients("cl_modSwitch", index)
end

function Bomber:cl_modSwitch( index )
    sm.audio.play( "ConnectTool - Rotate", self.tool:getOwner().character.worldPosition )
    self:cl_updateCol( index )
    setTpAnimation( self.tpAnimations, "pickup", 0.2 )
    if self.tool:isLocal() then
        sm.camera.setShake( 0.05 )
        setFpAnimation( self.fpAnimations, "equip", 0.001 )
    end
end

function Bomber:cl_updateCol( index )
    self.cl.modIndex = index
    local colour = self.mods[index].colour

    self.tool:setFpColor( colour )
    self.tool:setTpColor( colour )
end

function Bomber:client_onFixedUpdate()
    if not self.tool:isLocal() or #self.cl.targetsToAnnoy == 0 then return end

    self.cl.annoyTimer:tick()
    if self.cl.annoyTimer:done() then
        self.cl.annoyTimer:reset()

        local mod = self.mods[3]
        for k, char in pairs(self.cl.targetsToAnnoy) do
            if char ~= nil and sm.exists(char) then
                ---@type Vec3
				local pos = char.worldPosition
                local firePos = pos + mod.getRandomOffset() + vector_up * 5
                sm.projectile.projectileAttack(
                    projectile_potato,
                    mod.damage,
                    firePos,
                    (pos - firePos):normalize() * mod.vel,
                    sm.localPlayer.getPlayer()
                )
            else
                self.cl.targetsToAnnoy[k] = nil
            end
        end
    end
end

function Bomber:client_onDestroy()
    if self.cl.aimbotTargetMarker then
        self.cl.aimbotTargetMarker:close()
    end
end

function Bomber.loadAnimations( self )

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
		idleRelaxed = "spudgun_relax",

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

	if self.tool:isLocal() then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "spudgun_pickup", { nextAnimation = "idle" } },
				unequip = { "spudgun_putdown" },

				idle = { "spudgun_idle", { looping = true } },
				shoot = { "spudgun_shoot", { nextAnimation = "idle" } },

				aimInto = { "spudgun_aim_into", { nextAnimation = "aimIdle" } },
				aimExit = { "spudgun_aim_exit", { nextAnimation = "idle", blendNext = 0 } },
				aimIdle = { "spudgun_aim_idle", { looping = true} },
				aimShoot = { "spudgun_aim_shoot", { nextAnimation = "aimIdle"} },

				sprintInto = { "spudgun_sprint_into", { nextAnimation = "sprintIdle",  blendNext = 0.2 } },
				sprintExit = { "spudgun_sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },
				sprintIdle = { "spudgun_sprint_idle", { looping = true } },
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

function Bomber.client_onUpdate( self, dt )
	-- First person animation
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()
    local isEquipped = self.tool:isEquipped()

    if isEquipped and self.cl.modIndex == 5 then
        if self.cl.public.lmb == sm.tool.interactState.hold then
            local dir = self.tool:getOwner().character.direction
            self.cl.blackHoleEffect:setPosition( self.tool:isInFirstPersonView() and self.tool:getFpBonePos( "pejnt_barrel" ) - dir * 0.15 or self.tool:getTpBonePos( "pejnt_barrel" ) )
            self.cl.blackHoleEffect:setRotation( sm.vec3.getRotation( vector_up, dir ) )

            --if not self.cl.blackHoleEffect:isPlaying() then self.cl.blackHoleEffect:start() end
        elseif self.cl.blackHoleEffect:isPlaying() then
            self.cl.blackHoleEffect:stop()
        end
    end

	if self.tool:isLocal() then
        if self.cl.aimbotTarget ~= nil and not sm.exists(self.cl.aimbotTarget) then self.cl.aimbotTarget = nil end

        if self.cl.aimbotTarget then
            self.cl.aimbotTargetMarker:setWorldPosition( type(self.cl.aimbotTarget) == "Character" and self.cl.aimbotTarget.worldPosition or self.cl.aimbotTarget:getCenterOfMassPosition() )
            if not self.cl.aimbotTargetMarker:isActive() then self.cl.aimbotTargetMarker:open() end
        elseif self.cl.aimbotTargetMarker:isActive() then
            self.cl.aimbotTargetMarker:close()
        end

		if isEquipped then
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
		updateFpAnimations( self.fpAnimations, isEquipped, dt )

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

	if isEquipped then
		local effectPos, rot
		if self.tool:isLocal() then
			local firePos = self.tool:getFpBonePos( "pejnt_barrel" )
			local dir = sm.localPlayer.getDirection()
			if not self.aiming then
				effectPos = firePos + dir * 0.2
			else
				effectPos = firePos + dir * 0.45
			end

			rot = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), dir )
			self.shootEffectFP:setPosition( effectPos )
			self.shootEffectFP:setVelocity( self.tool:getMovementVelocity() )
			self.shootEffectFP:setRotation( rot )
		end
		local pos = self.tool:getTpBonePos( "pejnt_barrel" )
		local dir = self.tool:getTpBoneDir( "pejnt_barrel" )
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

	-- Sprint block
	local blockSprint = self.aiming or self.sprintCooldownTimer > 0.0
	self.tool:setBlockSprint( blockSprint )

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

    local fov = sm.camera.getDefaultFov() / 3
	self.tool:updateCamera( 2.8, fov, sm.vec3.new( 0.65, 0.0, 0.05 ), self.aimWeight )
	self.tool:updateFpCamera( fov, sm.vec3.new( 0.0, 0.0, 0.0 ), self.aimWeight, bobbing )
end

function Bomber.client_onEquip( self, animate )

	if animate then
		sm.audio.play( "PotatoRifle - Equip", self.tool:getPosition() )
	end

	self.aiming = false
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
	self.jointWeight = 0.0

	local currentRenderablesTp = {}
	local currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	self:loadAnimations()

    local isLocal = self.tool:isLocal()

    self.tool:setTpRenderables( currentRenderablesTp )
    if isLocal then
		self.tool:setFpRenderables( currentRenderablesFp )
    end

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if isLocal then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end

    self:cl_updateCol( self.cl.modIndex )
end

function Bomber.client_onUnequip( self, animate )
	self.aiming = false
	if sm.exists( self.tool ) then
		if animate then
			sm.audio.play( "PotatoRifle - Unequip", self.tool:getPosition() )
		end
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.tool:isLocal() then
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

function Bomber.sv_n_onAim( self, aiming )
	self.network:sendToClients( "cl_n_onAim", aiming )
end

function Bomber.cl_n_onAim( self, aiming )
	if not self.tool:isLocal() and self.tool:isEquipped() then
		self:onAim( aiming )
	end
end

function Bomber.onAim( self, aiming )
	self.aiming = aiming
	if self.tpAnimations.currentAnimation == "idle" or self.tpAnimations.currentAnimation == "aim" or self.tpAnimations.currentAnimation == "relax" and self.aiming then
		setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 5.0 )
	end
end

function Bomber.sv_n_onShoot( self, dir )
	self.network:sendToClients( "cl_n_onShoot", dir )
end

function Bomber.cl_n_onShoot( self, dir )
	if not self.tool:isLocal() and self.tool:isEquipped() then
		self:onShoot( dir )
	end
end

function Bomber.onShoot( self, dir )
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

function Bomber.calculateFirePosition( self )
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

function Bomber.calculateTpMuzzlePos( self )
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

function Bomber.calculateFpMuzzlePos( self )
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

	return self.tool:getFpBonePos( "pejnt_barrel" ) + sm.vec3.lerp( muzzlePos45, muzzlePos90, fovScale )
end

function Bomber.cl_onPrimaryUse( self, state )
	if self.tool:getOwner().character == nil or self.fireCooldownTimer > 0.0 then
		return
	end

    self[self.mods[self.cl.modIndex].fun](self, state)

    if state == sm.tool.interactState.start then
        local dir = sm.localPlayer.getDirection()
        self:onShoot( dir )
        self.network:sendToServer( "sv_n_onShoot", dir )
        setFpAnimation( self.fpAnimations, self.aiming and "aimShoot" or "shoot", 0.05 )
    end
end

function Bomber.cl_onSecondaryUse( self, state )
    local fun = self[self.mods[self.cl.modIndex].onSecondary]
    if fun then
        fun(self, state)
    else
        if state == sm.tool.interactState.null or state == sm.tool.interactState.hold then return end

        self.aiming = state == sm.tool.interactState.start
        self.tpAnimations.animations.idle.time = 0

        self:onAim( self.aiming )
        self.tool:setMovementSlowDown( self.aiming )
        self.network:sendToServer( "sv_n_onAim", self.aiming )
    end
end

function Bomber.client_onEquippedUpdate( self, primaryState, secondaryState )
    self.cl.public.lmb = primaryState
    self.cl.public.rmb = secondaryState

	if primaryState ~= self.prevPrimaryState then
		self:cl_onPrimaryUse( primaryState )
		self.prevPrimaryState = primaryState
	end

	if secondaryState ~= self.prevSecondaryState then
		self:cl_onSecondaryUse( secondaryState )
		self.prevSecondaryState = secondaryState
	end

	return true, true
end
