---@class GunnerShield : ShapeClass
GunnerShield = class()
GunnerShield.maxParentCount = 1
GunnerShield.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.seated

local vec3_up      = sm.vec3.new(0,0,1)
local effectUp     = sm.vec3.new(0,1,0)
local DeathTimer   = 10
local ShieldRadius = 5

function GunnerShield:server_onCreate()
    self.deathTimer = DeathTimer
    self.sentStop = false

    local isThrown = false
    local saved = self.storage:load() or {}
    if saved.isThrown then
        isThrown = true
    elseif self.params then
        isThrown = self.params.isThrown
    end

    self.isThrown = isThrown
    self.storage:save({ isThrown = isThrown })

    if (isThrown or #self.shape.body:getCreationShapes() == 1) and not self.shape.body:isDynamic() then
        self:sv_activate(true)
    end
end

function GunnerShield:server_onCollision(other, position, selfPointVelocity, otherPointVelocity, normal)
    local body = self.shape.body
    if other == nil and (body:isDynamic() or body:isOnLift()) then
        local rot = sm.vec3.getRotation(effectUp, normal)
        local uuid = self.shape.uuid
        local shape = sm.shape.createPart(uuid, position + normal * 0.175 - rot * sm.item.getShapeOffset(uuid), rot, false, true)
        shape.interactable:setParams({ isThrown = self.isThrown })
        self.shape:destroyShape()
    else
        sm.physics.applyImpulse(self.shape, normal * self.shape.mass * 1.5, true)
    end
end

function GunnerShield:server_onFixedUpdate(dt)
    -- print(sm.player.getAllPlayers()[1].character.velocity:length())
    local parent = self.interactable:getSingleParent()
    if parent then
        if not parent:hasSeat() then
            self:sv_activate(parent.active)
        end

        return
    elseif self.interactable.active and not self.isThrown then
        self:sv_activate(false)
        return
    end

    if not self.trigger or not sm.exists(self.shape) then return end

    self.deathTimer = self.deathTimer - dt
    if self.deathTimer <= 1 and not self.sentStop then
        self.network:sendToClients("cl_onEvent", "stop")
        sm.areaTrigger.destroy(self.trigger)
        self.sentStop = true
    end

    if self.deathTimer <= 0 then
        self.shape:destroyShape()
    end
end

function GunnerShield:sv_e_onHit() end

function GunnerShield:sv_activate(state)
    if state == nil then
        state = not self.interactable.active
    end

    if state == self.interactable.active then return end

    self.interactable.active = state
    if not state and sm.exists(self.trigger) then
        self.deathTimer = DeathTimer
        sm.areaTrigger.destroy(self.trigger)
    end

    self.network:sendToClients("cl_activate", state)
end

function GunnerShield:sv_enableShield()
    self.trigger = sm.areaTrigger.createAttachedSphere(self.interactable, ShieldRadius, sm.vec3.zero(), sm.quat.identity(), -1, {
        isCustomCollision = true,
        parent = self.shape
    })
    self.trigger:bindOnProjectile("sv_onTriggerHit", self)
    self.trigger:bindOnEnter("sv_onTriggerEnter", self)
end

function GunnerShield:sv_onTriggerHit(trigger, hitPos, airTime, velocity, name, source, damage, data, normal, uuid)
    if self:isInTrigger(source) then return false end

    sm.effect.playEffect(
        "Barrier - SledgeHammerHit",
        hitPos, sm.vec3.zero(),
        sm.vec3.getRotation(effectUp, hitPos - self.shape.worldPosition)
    )

    return true
end

function GunnerShield:sv_onTriggerEnter(trigger, results)
    local pos = self.shape.worldPosition
    for k, v in pairs(results) do
        if not sm.exists(v) or type(v) ~= "Body" then
            goto continue
        end

        local shapes = v:getCreationShapes()
        if #shapes <= 5 and v.velocity:length() >= 10 then
            local hitPos = pos + (v:getCenterOfMassPosition() - pos):normalize() * ShieldRadius

            for _k, _v in pairs(shapes) do
                _v:destroyShape()
            end

            sm.effect.playEffect(
                "Barrier - SledgeHammerHit",
                hitPos, sm.vec3.zero(),
                sm.vec3.getRotation(effectUp, hitPos - pos)
            )
        end

        ::continue::
    end
end



function GunnerShield:client_onCreate()

end

function GunnerShield:cl_activate(state)
    if state then
        self.effect = sm.effect.createEffect("GunnerShield", self.interactable)
        self.effect:setOffsetRotation(sm.vec3.getRotation(vec3_up, effectUp))
        self.effect:setScale(sm.vec3.one() * 4)
        self.effect:bindEventCallback( "cl_onEvent", {}, self )

        self.effect:start()
    else
        self:cl_onEvent("stop")
    end
end

function GunnerShield:client_canInteract(char)
    local parent = self.interactable:getSingleParent()
    if not parent then return false end

    return char == parent:getSeatCharacter()
end

function GunnerShield:client_onInteract(char, state)
    if not state or not sm.exists(char) or char ~= self.interactable:getSingleParent():getSeatCharacter() then
        return
    end

    self.network:sendToServer("sv_activate")
end

function GunnerShield:cl_onEvent(event)
    if event == "activate" and sm.isHost then
        self.network:sendToServer("sv_enableShield")
    end

    if event == "stop" and sm.exists(self.effect) then
        self.effect:stop()
    end
end



function GunnerShield:isInTrigger(obj)
    if type(obj) == "Player" then
        obj = obj.character
    end

    return isAnyOf(obj, self.trigger:getContents())
end



dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

---@class GunnerShield_handheld : ToolClass
---@field fpAnimations table
---@field tpAnimations table
---@field isLocal boolean
---@field normalFireMode table
---@field blendTime number
---@field aimBlendSpeed number
GunnerShield_handheld = class()

local renderables = {
    "$CONTENT_DATA/Objects/Renderables/GunnerShield_handheld.rend"
}
local renderablesTp = {
    "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_tp_eattool.rend",
    "$SURVIVAL_DATA/Character/Char_Tools/Char_eattool/char_eattool_tp.rend",

    "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_tp_glowstick.rend"
}
local renderablesFp = {
    "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_fp_eattool.rend",
    "$SURVIVAL_DATA/Character/Char_Tools/Char_eattool/char_eattool_fp.rend",

    "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_fp_glowstick.rend"
}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function GunnerShield_handheld:client_onCreate()
	self.isLocal = self.tool:isLocal()
	self.owner = self.tool:getOwner()

    if self.isLocal then
        sm.testmod_cmdHandler = self.tool
    end
end

local function OpenFile(path)
    if sm.json.fileExists(path) then
        return sm.json.open(path)
    end

    return {}
end

function GunnerShield_handheld:cl_lhotbar(params)
    local hotbar = OpenFile("$CONTENT_DATA/presets.json")[params[2]]
    if hotbar then
        self.network:sendToServer("sv_switchHotbar", hotbar)
    else
        sm.gui.chatMessage(("#ff0000ff%s %s"):format(sm.gui.translateLocalizationTags("#{UGC_CANNOT_FIND}"), params[2]))
        sm.audio.play("RaftShark")
    end
end

function GunnerShield_handheld:cl_shotbar(params)
    local presets = OpenFile("$CONTENT_DATA/presets.json")
    local name = params[2]
    if presets[name] then
        self.confirmOverwriteGui = sm.gui.createGuiFromLayout( "$GAME_DATA/Gui/Layouts/PopUp/PopUp_YN.layout", true )
        self.confirmOverwriteGui:setButtonCallback( "Yes", "cl_onOverwriteConfirmButtonClick" )
        self.confirmOverwriteGui:setButtonCallback( "No", "cl_onOverwriteConfirmButtonClick" )
        self.confirmOverwriteGui:setText( "Title", "#{MENU_YN_TITLE_ARE_YOU_SURE}" )
        self.confirmOverwriteGui:setText( "Message", "#{ERRMSG_SAVE_ALREADY_EXISTS}\n#{WORLD_BUILDER_OVERWRITE}" )
        self.confirmOverwriteGui:open()
        self.hotbarSaveData = {
            name = name,
            presets = presets,
        }

        return
    end

    self:cl_saveHotbar(presets, name)
end

local uuid_nil = sm.uuid.getNil()
function GunnerShield_handheld:cl_hotbars()
    local presets = OpenFile("$CONTENT_DATA/presets.json")
    local count = 0
    for k, v in pairs(presets) do
        count = count + 1
        sm.gui.chatMessage(("Hotbar %s: %s"):format(count, k))
        for id, item in pairs(v) do
            local uuid = sm.uuid.new(item[1])
            if uuid == uuid_nil then
                goto continue
            end

            if sm.item.isTool(uuid) then
                sm.gui.chatMessage(("\t%s: %s"):format(id, sm.shape.getShapeTitle(uuid)))
            else
                sm.gui.chatMessage(("\t%s: %s x%s"):format(id, sm.shape.getShapeTitle(uuid), item[2]))
            end

            ::continue::
        end
    end

    if count == 0 then
        sm.gui.chatMessage("No saved hotbars found.")
    end
end

function GunnerShield_handheld:sv_switchHotbar(hotbar, player)
    local inventory = player:getHotbar()
    sm.container.beginTransaction()
    for i = 1, 10 do
        local item = hotbar[i]
        inventory:setItem(i - 1, sm.uuid.new(item[1]), item[2])
    end
    sm.container.endTransaction()
end

function GunnerShield_handheld:cl_onOverwriteConfirmButtonClick(button)
    if button == "Yes" then
        self:cl_saveHotbar(self.hotbarSaveData.presets, self.hotbarSaveData.name)
        self.hotbarSaveData = nil
    end

    self.confirmOverwriteGui:close()
    self.confirmOverwriteGui = nil
end

function GunnerShield_handheld:cl_saveHotbar(presets, name)
    local inventory = sm.localPlayer.getHotbar()
    local hotbar = {}
    for i = 0, 9 do
        local item = inventory:getItem(i)
        hotbar[#hotbar+1] = { tostring(item.uuid), item.quantity }
    end

    presets[name] = hotbar
    sm.json.save(presets, "$CONTENT_DATA/presets.json")
end

function GunnerShield_handheld.loadAnimations( self )
    self.tpAnimations = createTpAnimations(
        self.tool,
        {
            idle = { "Idle" },
            use = { "glowstick_use", { nextAnimation = "idle" } },
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
                use = { "glowstick_use", { nextAnimation = "idle" } },
                equip = { "Pickup", { nextAnimation = "idle" } },
                unequip = { "Putdown" }
            }
        )

        setFpAnimation( self.fpAnimations, "idle", 5.0 )
    end

    setTpAnimation( self.tpAnimations, "idle", 5.0 )
    self.blendTime = 0.2
end

function GunnerShield_handheld.client_onUpdate( self, dt )
	if self.isLocal then
		updateFpAnimations( self.fpAnimations, self.equipped, dt )
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

			if animation.time >= animation.info.duration - self.blendTime then
				if ( name == "eat" ) then
					setTpAnimation( self.tpAnimations, "pickup",  10.05 )
				elseif name == "drink" then
						setTpAnimation( self.tpAnimations, "pickup", 10.05 )
				elseif name == "pickup" then
					setTpAnimation( self.tpAnimations, "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 1 )
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

function GunnerShield_handheld.client_onEquip( self, animate )
	if animate then
		sm.audio.play( "PotatoRifle - Equip", self.tool:getPosition() )
	end

	self.wantEquipped = true

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
end

function GunnerShield_handheld.client_onUnequip( self, animate )
	self.wantEquipped = false
	self.equipped = false
	if sm.exists( self.tool ) then
		if animate then
			sm.audio.play( "PotatoRifle - Unequip", self.tool:getPosition() )
		end
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.isLocal then
            self.pendingThrow = false

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

function GunnerShield_handheld:client_onEquippedUpdate( lmb, rmb, f )
    if self.pendingThrow then
		local time = 0.0
		local frameTime = 0.0
		if self.fpAnimations.currentAnimation == "use" then
			time = self.fpAnimations.animations["use"].time
			frameTime = 1.175
		end

		if time >= frameTime and frameTime ~= 0 then
            self.network:sendToServer("sv_throwShield", self.tool:isInFirstPersonView() and sm.camera.getPosition() or self.tool:getTpBonePos("root_item"))
			self.pendingThrow = false
		end
		return true, true
	elseif not f then
		if lmb == 1 then
			local activeItem = sm.localPlayer.getActiveItem()
			if sm.container.canSpend( sm.localPlayer.getInventory(), activeItem, 1 ) then
                self.network:sendToServer( "sv_n_onUse" )
                self.pendingThrow = true
			end
		end
		return true, false
	end

	return not f, false
end


function GunnerShield_handheld.cl_n_onUse( self )
	if self.isLocal then
        setFpAnimation( self.fpAnimations, "use", 0.25 )
        self.fpAnimations.animations.use.time = 0.6
    end
    setTpAnimation( self.tpAnimations, "use", 2.5 )
    self.tpAnimations.animations.use.time = 0.6

    sm.audio.play("Sledgehammer - Swing", self.tool:getPosition())
end

function GunnerShield_handheld.sv_n_onUse( self )
	self.network:sendToClients( "cl_n_onUse" )
end


function GunnerShield_handheld:sv_throwShield(pos, caller)
    local uuid = sm.uuid.new("2715b27d-0f4a-4f01-9d5a-91be9dd70672")
    local rot = sm.vec3.getRotation(-vec3_up, effectUp)
    local dir = caller.character.direction
    local shape = sm.shape.createPart(uuid, pos + dir - rot * sm.item.getShapeOffset(uuid), rot, true, true)
    shape.interactable:setParams({ isThrown = true })
    sm.physics.applyImpulse(shape, dir * 7.5 * shape.mass, true)
end