dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

Molotov = class()

local renderables =   {"$SURVIVAL_DATA/Character/Char_Glowstick/char_glowstick.rend" }
local renderablesTp = {"$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_tp_glowstick.rend", "$SURVIVAL_DATA/Character/Char_Glowstick/char_glowstick_tp_animlist.rend"}
local renderablesFp = {"$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_fp_glowstick.rend", "$SURVIVAL_DATA/Character/Char_Glowstick/char_glowstick_fp_animlist.rend"}

local currentRenderablesTp = {}
local currentRenderablesFp = {}

local flammableParts

dofile("$CONTENT_40639a2c-bb9f-4d4f-b88c-41bfe264ffa8/Scripts/ModDatabase.lua")

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function Molotov.client_onCreate( self )
	self:cl_init()

	self.cl = {}
	self.cl.projectiles = {}
	self.cl.hazards = {}
end

function Molotov.server_onCreate( self )
	self.sv = {}
	self.sv.triggers = {}
end

function Molotov.client_onRefresh( self )
	self:cl_init()
end

function Molotov.cl_init( self )
	self:cl_loadAnimations()
	self.glowEffect = sm.effect.createEffect( "Glowstick - Hold" )
end

function Molotov.cl_loadAnimations( self )
	
	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			idle = { "glowstick_idle" },
			use = { "glowstick_use", { nextAnimation = "idle" } },
			sprint = { "glowstick_sprint" },
			pickup = { "glowstick_pickup", { nextAnimation = "idle" } },
			putdown = { "glowstick_putdown" }
		
		}
	)
	local movementAnimations = {
	
		idle = "glowstick_idle",
		
		runFwd = "glowstick_run_fwd",
		runBwd = "glowstick_run_bwd",
		sprint = "glowstick_sprint",
		
		jump = "glowstick_jump_start",
		jumpUp = "glowstick_jump_up",
		jumpDown = "glowstick_jump_down",
		
		land = "glowstick_jump_land",
		landFwd = "glowstick_jump_land_fwd",
		landBwd = "glowstick_jump_land_bwd",

		crouchIdle = "glowstick_crouch_idle",
		crouchFwd = "glowstick_crouch_fwd",
		crouchBwd = "glowstick_crouch_bwd"
	}

	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	if self.tool:isLocal() then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				idle = { "glowstick_idle", { looping = true } },
				use = { "glowstick_use", { nextAnimation = "idle" } },
				equip = { "glowstick_pickup", { nextAnimation = "idle" } },
				unequip = { "glowstick_putdown" }
			}
		)
	end
	setTpAnimation( self.tpAnimations, "idle", 5.0 )
	self.blendTime = 0.2
	
end

function Molotov:sv_createHazard( pos )
	self.sv.triggers[#self.sv.triggers+1] = {
		trigger = sm.areaTrigger.createSphere(3, pos, sm.quat.identity(), 3),
		lifeTime = 0
	}

	self.network:sendToClients("cl_createHazard", pos)
end

function Molotov:cl_createHazard( pos )
	local effect = sm.effect.createEffect("Fire - large01")
	effect:setPosition(pos)
	effect:start()

	self.cl.hazards[#self.cl.hazards+1] = effect
end

function Molotov:cl_deleteHazard( index )
	self.cl.hazards[index]:stop()
	self.cl.hazards[index] = nil
end

function Molotov:server_onFixedUpdate( dt )
	if not flammableParts then
		flammableParts = {}
		local checkedShapeSets = {}
		local function AddFlammablesFromShapeSet(shapeSet)
			local set = sm.json.open(shapeSet)
			local _set = set.partList or set.blockList or set.wedgeList
			for i, shape in pairs(_set) do
				if shape.flammable then
					flammableParts[#flammableParts+1] = shape.uuid
				end
			end
		end

		local function AddFlammablesFromShapeDB(shapeDB)
			for k, shapeSet in pairs(sm.json.open(shapeDB).shapeSetList) do
				if not isAnyOf(shapeSet, checkedShapeSets) then
					AddFlammablesFromShapeSet( shapeSet )
					checkedShapeSets[#checkedShapeSets+1] = shapeSet
				end
			end
		end

		AddFlammablesFromShapeDB("$SURVIVAL_DATA/Objects/Database/shapesets.json")
		AddFlammablesFromShapeDB("$GAME_DATA/Objects/Database/shapesets.json")
		AddFlammablesFromShapeDB("$CHALLENGE_DATA/Objects/Database/shapesets.json")

		ModDatabase.loadDescriptions()
		ModDatabase.loadShapesets()
		for k, v in pairs(ModDatabase.getAllLoadedMods()) do
			for i, j in pairs(ModDatabase.databases.shapesets[v] or {}) do
				AddFlammablesFromShapeSet(i)
			end
		end
		ModDatabase.unloadDescriptions()
		ModDatabase.unloadShapesets()

		return
	end


	for k, hazard in pairs(self.sv.triggers) do
		hazard.lifeTime = hazard.lifeTime + dt

		for i, body in pairs(hazard.trigger:getContents()) do
			if sm.exists(body) then
				for j, shape in pairs(body:getShapes()) do
					local uuid = shape.uuid
					if math.random() <= 0.05 and isAnyOf(tostring(uuid), flammableParts) then
						if sm.item.isBlock(uuid) then
							--Thanks QMark for the epic math
							local bbox = (shape:getBoundingBox() * 4) - sm.vec3.one()
							local bbox_noise = sm.vec3.new(math.random(-bbox.x, bbox.x), math.random(-bbox.y, bbox.y), math.random(-bbox.z, bbox.z)) * 0.125
							local global_pos = shape.worldPosition + (shape.worldRotation * bbox_noise)
							if (global_pos - hazard.trigger:getWorldPosition()):length2() <= 9 then
								local local_block_pos = shape:getClosestBlockLocalPosition(global_pos)
								shape:destroyBlock(local_block_pos, sm.vec3.one(), 0)
							end
						else
							shape:destroyShape()
						end
					end
				end
			end
		end

		if hazard.lifeTime >= 7.5 then
			sm.areaTrigger.destroy(hazard.trigger)
			self.sv.triggers[k] = nil
			self.network:sendToClients("cl_deleteHazard", k)
		end
	end
end



function Molotov.client_onUpdate( self, dt )
	for k, projectile in pairs(self.cl.projectiles) do
		projectile.lifeTime = projectile.lifeTime + dt
		projectile.pos = projectile.pos + projectile.dir * projectile.velocity * dt
		projectile.dir.z = sm.util.clamp(projectile.dir.z - dt, -1, 1)

		projectile.effect:setPosition(projectile.pos)
		projectile.effect:setRotation(sm.vec3.getRotation(sm.vec3.new(0,1,0), projectile.dir))

		local hit, result = sm.physics.raycast(projectile.pos, projectile.pos + projectile.dir)

		if projectile.lifeTime >= 15 or hit then
			projectile.effect:destroy()

			if self.tool:isLocal() and hit then
				self.network:sendToServer("sv_createHazard", projectile.pos)
			end

			self.cl.projectiles[k] = nil
		end
	end

	if self.tool:isLocal() then
		updateFpAnimations( self.fpAnimations, self.equipped, dt )
	end

	if self.glowEffect then
		local effectPos = self.tool:getTpBonePos( "jnt_right_hand" )
		local character = self.tool:getOwner().character
		if character and sm.exists( character ) then
			effectPos.z = character.worldPosition.z
		end
		self.glowEffect:setPosition( effectPos )
		if self.equipped and not self.glowEffect:isPlaying() then
			self.glowEffect:start()
		elseif not self.equipped and self.glowEffect:isPlaying() then
			self.glowEffect:stop()
		end
	end

	if not self.equipped then
		if self.wantEquipped then
			self.wantEquipped = false
			self.equipped = true
		end
		return
	end

	local crouchWeight = self.tool:isCrouching() and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight
	local totalWeight = 0.0

	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

			if animation.looping == true then
				if animation.time >= animation.info.duration then
					animation.time = animation.time - animation.info.duration
				end
			end
			if animation.time >= animation.info.duration - self.blendTime and not animation.looping then
				if ( name == "use" ) then
					setTpAnimation( self.tpAnimations, "idle", 10.0 )
				elseif name == "pickup" then
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
end

function Molotov.client_onEquip( self )
	self.wantEquipped = true

	currentRenderablesTp = {}
	currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesFp[#currentRenderablesFp+1] = v end

	self.tool:setTpRenderables( currentRenderablesTp )
	if self.tool:isLocal() then
		self.tool:setFpRenderables( currentRenderablesFp )
	end

	self:cl_loadAnimations()

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if self.tool:isLocal() then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

function Molotov.client_onUnequip( self )
	self.wantEquipped = false
	self.equipped = false
	self.pendingThrowFlag = false
	if sm.exists( self.tool ) then
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.tool:isLocal() and self.fpAnimations.currentAnimation ~= "unequip" then
			swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
		end
	end
end

-- Start


-- Interact
function Molotov.client_onEquippedUpdate( self, primaryState, secondaryState, forceBuildActive )
	if self.pendingThrowFlag == true then
		local time = 0.0
		local frameTime = 0.0
		if self.fpAnimations.currentAnimation == "use" then
			time = self.fpAnimations.animations["use"].time
			frameTime = 1.175
		end

		if time >= frameTime and frameTime ~= 0 then
			self.pendingThrowFlag = false
			if self.tool:getOwner().character then
				local dir = sm.localPlayer.getDirection()
				local firePos = GetOwnerPosition( self.tool ) + sm.vec3.new( 0, 0, 0.5 )
				-- Scale down throw velocity when looking down
				local maxVelocity = 20.0
				local minVelocity = 5.0
				local directionForceScale = math.min( ( dir:dot( sm.vec3.new( 0, 0, 1 ) ) + 1.0 ), 1.0 )
				local fireVelocity = math.max( maxVelocity * directionForceScale, minVelocity )

				--sm.projectile.projectileAttack( projectile_glowstick, 0, firePos, dir * fireVelocity, self.tool:getOwner() )

				local params = {
					--selectedSlot = sm.localPlayer.getSelectedHotbarSlot()
					pos = firePos,
					dir = dir,
					velocity = fireVelocity,
					lifeTime = 0
				}
				self.network:sendToServer( "sv_n_onUse", params )
			end
		end
		return true, true
	else --if not forceBuildActive then
		if primaryState == sm.tool.interactState.start then
			--local activeItem = sm.localPlayer.getActiveItem()
			--if sm.container.canSpend( sm.localPlayer.getInventory(), activeItem, 1 ) then
				--self:onUse()
				self:beginThrow()
				self.pendingThrowFlag = true
			--end
		end
		return true, false
	end

	return false, false
end

function Molotov.beginThrow( self )
	if self.tool:isLocal() then
		setFpAnimation( self.fpAnimations, "use", 0.25 )
	end
	setTpAnimation( self.tpAnimations, "use", 10.0 )

	sm.effect.playHostedEffect( "Glowstick - Throw", self.tool:getOwner():getCharacter() )
end

function Molotov.onUse( self, params )
	if not self.tool:isLocal() then
		setTpAnimation( self.tpAnimations, "use", 10.0 )
	end

	sm.effect.playHostedEffect( "Glowstick - Throw", self.tool:getOwner():getCharacter() )

	params.effect = sm.effect.createEffect("ShapeRenderable")
	params.effect:setParameter("uuid", obj_consumable_glowstick)
	params.effect:setPosition(params.pos)
	params.effect:setRotation(sm.vec3.getRotation(sm.vec3.new(0,1,0), params.dir))
	params.effect:setScale(sm.vec3.one() / 4)
	params.effect:start()
	self.cl.projectiles[#self.cl.projectiles+1] = params
end

function Molotov.cl_n_onUse( self, params )
	if self.tool:isEquipped() then
		self:onUse( params )
	end
end

function Molotov.sv_n_onUse( self, params, player )
	self.network:sendToClients( "cl_n_onUse", params )
end