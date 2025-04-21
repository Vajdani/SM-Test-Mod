local vec3 = sm.vec3.new
local getRotation = sm.vec3.getRotation
local getGravity = sm.physics.getGravity
local angleAxis = sm.quat.angleAxis

local function CalculateRightVector(vector)
    local yaw = math.atan2(vector.y, vector.x) - math.pi / 2
    return vec3(math.cos(yaw), math.sin(yaw), 0)
end

local function BoolToNum(bool)
    return bool and 1 or 0
end

local VEC3_UP = vec3(0,0,1)
local VEC3_ZERO = sm.vec3.zero()

Line_tracer = class()
function Line_tracer:init( thickness, colour )
    self.effect = sm.effect.createEffect("ShapeRenderable")
	self.effect:setParameter("uuid", sm.uuid.new("7030b7b1-f0a1-4b24-bd0d-11d0a42185e6"))
    self.effect:setParameter("color", colour)
    self.effect:setScale( sm.vec3.one() * thickness )

    self.thickness = thickness

    return self
end

---@param startPos Vec3
---@param endPos Vec3
function Line_tracer:update( startPos, endPos )
	local delta = endPos - startPos
    local length = delta:length()

    if length < 0.0001 then
        --sm.log.warning("Line_tracer:update() | Length of 'endPos - startPos' must be longer than 0.")
        return
	end

	self.effect:setPosition(startPos + delta * 0.5)
	self.effect:setScale(vec3(self.thickness, self.thickness, length))
	self.effect:setRotation(getRotation(VEC3_UP, delta))

    if not self.effect:isPlaying() then
        self.effect:start()
    end
end

function Line_tracer:stop()
    if self.effect:isPlaying() then
        self.effect:stop()
    end
end

function Line_tracer:destroy()
    self.effect:destroy()
end



---@class Gunship : ShapeClass
Gunship = class()
Gunship.maxParentCount = 0
Gunship.maxChildCount = 7
Gunship.connectionInput = sm.interactable.connectionType.none
Gunship.connectionOutput = sm.interactable.connectionType.seated
Gunship.colorNormal = sm.color.new( 0xcb0a00ff )
Gunship.colorHighlight = sm.color.new( 0xee0a00ff )

local moveSpeed = 25
local boostSpeed = 100
local fireRate = 1/4
local rocketRate = 1
local rocketBurst = 3
local rocketBurstTicks = 5
local actions = {
    [1] = true, --Right
    [2] = true, --Left
    [3] = true, --Forward
    [4] = true, --Backward
    [5] = true, --Rockets
    [18] = true, --Aim
    [19] = true, --Shoot
    [20] = true, --Down
    [21] = true, --Up
    [16] = true, --Boost
}

local turnLimit = 0.3
local rayFilter = sm.physics.filter.default + sm.physics.filter.areaTrigger
local green = sm.color.new(0,1,0)
local red = sm.color.new(1,0,0)

function Gunship:server_onCreate()
    self.sv_actions = {}

    self.fireTimer = 0
    self.rocketTimer = 0
    self.rocketCounter = 0
end

function Gunship:sv_updateAction(args)
    self.sv_actions[args[1]] = args[2]
    self.network:sendToClients("cl_updateAction", args)
end

function Gunship:server_onFixedUpdate(dt)
    local char = self.interactable:getSeatCharacter()
    if not char then return end

    local up = BoolToNum(self.sv_actions[21]) - BoolToNum(self.sv_actions[20])
    local fwd = BoolToNum(self.sv_actions[3]) - BoolToNum(self.sv_actions[4])
    local right = BoolToNum(self.sv_actions[1]) - BoolToNum(self.sv_actions[2])

	local mass = 0
    for k, v in pairs(self.shape.body:getCreationBodies()) do
        mass = mass + v.mass
    end

    local direction = char.direction
	local force = vec3(0, 0, getGravity() + 0.45) --result.pointWorld + vec3(0,0,5) - pos

    -- local groundCheck = self.shape.body:getWorldAabb()
    -- local hit, result = sm.physics.raycast(groundCheck, groundCheck - VEC3_UP * 5, self.shape.body, rayFilter)
    -- if hit then
    --     force = force + VEC3_UP * moveSpeed
    --     -- up = 1
    -- end

    force = force + (self.shape.at * up + self.shape.up * fwd + self.shape.right * right):safeNormalize(VEC3_ZERO) * (self.sv_actions[16] and boostSpeed or moveSpeed)
    force = force - self.shape.velocity * 0.5

	-- sm.physics.applyImpulse(self.shape, ((force  * 2) - ( self.shape.velocity--[[@as Vec3]] * 0.3 )) * mass, true)
	sm.physics.applyImpulse(self.shape, force * dt * mass, true)

    local torque = -self.shape.body.angularVelocity * 0.3 - direction * right * 0.15
    if self.sv_actions[18] or self.forceStatic then
        torque = torque + CalculateRightVector(self.aimDirection):cross(self.shape.right)
    else
        self.aimDirection = direction

        local steer = CalculateRightVector(direction):cross(self.shape.right)
        local length = steer:length()
        if length > turnLimit then
            steer = steer * (turnLimit / length)
        end

        torque = torque + self.shape.up:cross(direction) + steer
    end

    -- sm.physics.applyTorque(self.shape.body, torque * dt * mass, true)
    sm.physics.applyTorque(self.shape.body, torque * mass, true)

    self.fireTimer = math.max(self.fireTimer - dt, 0)
    self.rocketTimer = math.max((self.rocketTimer or 0) - dt, 0)
    if self.sv_actions[19] and self.fireTimer <= 0 then
        local firePos = self.interactable:getWorldBonePosition("jnt_turret_firepos") + self.shape.velocity * (1/40)
        local camPos = self:GetCameraPosition()
        local targetPos = camPos + direction * 100
        local hit, result = sm.physics.raycast(camPos, targetPos, self.shape, rayFilter)
        if hit then
            targetPos = result.pointWorld
        end

        local low, high = sm.projectile.solveBallisticArc(firePos, targetPos, 200, 10)
        local fireDir
        if low then
            fireDir = low:normalize()
        else
            fireDir = direction --(targetPos - firePos):normalize()
        end

        -- fireDir.z = min(fireDir.z, self.shape.up.z)

        sm.effect.playEffect("GunshipTurret - Shoot", firePos, nil, getRotation(VEC3_UP, fireDir))
        sm.projectile.projectileAttack(projectile_tape, 100, firePos, fireDir * 200, char:getPlayer())

        self.fireTimer = fireRate
    end

    if self.sv_actions[5] and self.rocketTimer <= 0 then
        self.rocketCounter = self.rocketCounter % 2 + 1
        local player = char:getPlayer()
        self:sv_fireRocket({ delay = 0, player = player })
        for i = 1, rocketBurst - 1 do
            sm.event.sendToInteractable(self.interactable, "sv_fireRocket", { delay = i * rocketBurstTicks, player = player })
        end

        self.rocketTimer = rocketRate
    end
end

function Gunship:sv_fireRocket(args)
    if args.delay > 0 then
        args.delay = args.delay - 1
        sm.event.sendToInteractable(self.interactable, "sv_fireRocket", args)
        return
    end

    local firePos, fireDir = self:GetRocketFireData(self.interactable:getWorldBonePosition("jnt_rocket"..self.rocketCounter.."_firepos"))
    sm.effect.playEffect("GunshipTurret - Shoot", firePos, nil, getRotation(VEC3_UP, fireDir))
    sm.projectile.projectileAttack(projectile_explosivetape, 100, firePos + fireDir, fireDir * 200, args.player)
end

function Gunship:sv_onRocketFire()
    self.forceStatic = true
end

function Gunship:sv_onRocketExplode()
    self.forceStatic = false
end



function Gunship:client_onCreate()
    self.cl_actions = {}

    local cockpit = sm.effect.createEffect("ShapeRenderable", self.interactable)
    cockpit:setParameter("uuid", sm.uuid.new("5e7a0724-a469-468a-9138-eea1b23c2387"))
    cockpit:setParameter("color", self.shape.color)
    cockpit:setScale(vec3(0.25, 0.25, 0.25))
    cockpit:setOffsetRotation(angleAxis(math.rad(-90), vec3(1,0,0)))
    cockpit:start()

    self.cockpit = cockpit

    self.thrusters = {}
    for i = 1, 4 do
        local thruster = sm.effect.createEffect("Thruster - Level 5", self.interactable, "jnt_engine"..i.."_effect")
        thruster:setOffsetRotation(angleAxis(math.rad(90), vec3(1,0,0)))
        table.insert(self.thrusters, thruster)
    end

    local aimPoint = sm.effect.createEffect("ShapeRenderable")
    aimPoint:setParameter("uuid", sm.uuid.new("7030b7b1-f0a1-4b24-bd0d-11d0a42185e6"))
    aimPoint:setParameter("color", green)
    aimPoint:setScale(vec3(0.25, 0.25, 0.25))
    self.aimPoint = aimPoint

    self.tracers = {}
    for i = 1, 2 do
        table.insert(self.tracers, Line_tracer():init(0.15, green))
    end

    self.engine = sm.effect.createEffect("GasEngine - Level 4", self.interactable)

    self.gui = sm.gui.createSeatGui()
end

function Gunship:client_onDestroy()
    if self.seatedTick then
        sm.camera.setCameraState(0)
    end

    self.cockpit:destroy()

    for i = 1, 4 do
        self.thrusters[i]:destroy()
    end

    self.aimPoint:destroy()
    for i = 1, 2 do
        self.tracers[i]:destroy()
    end

    self.gui:destroy()
end

local rocketOffset = {
    vec3(-1.0625, -4.625, 0.187502),
    vec3( 1.0625, -4.625, 0.187502),
}
local turretOffset = {
    vec3(0, -4.25, -1),
    vec3(0, -4.25, -1),
}
function Gunship:client_onUpdate(dt)
    self.cockpit:setParameter("color", self.shape.color)
    self.interactable:setSubMeshVisible("Glass", not self.seatedTick or self.controllingRocket)

    -- self.interactable:setAnimEnabled("engine1_rotate", true)
    -- self.interactable:setAnimEnabled("engine2_rotate", true)
    -- self.interactable:setAnimEnabled("engine3_rotate", true)
    -- self.interactable:setAnimEnabled("engine4_rotate", true)
    -- self.interactable:setAnimProgress("engine1_rotate", 0.5)
    -- self.interactable:setAnimProgress("engine2_rotate", 0.5)
    -- self.interactable:setAnimProgress("engine3_rotate", 0.5)
    -- self.interactable:setAnimProgress("engine4_rotate", 0.5)

    -- for i = 1, 4 do
    --     local name = "engine"..i.."_rotate"
    --     self.interactable:setAnimEnabled(name, true)
    --     -- self.interactable:setAnimProgress(name, self.interactable:getAnimDuration(name) * 0.5)
    --     self.interactable:setAnimProgress(name, 0.5)
    --     -- print(name, self.interactable:getAnimDuration(name))
    -- end

    local seatedChar = self.interactable:getSeatCharacter()
    if seatedChar then
        if not self.thrusters[1]:isPlaying() then
            for i = 1, 4 do
                self.thrusters[i]:start()
            end
            self.engine:start()
        end

        self.engine:setParameter("gas", 1)

        local moving = (self.cl_actions[21] or self.cl_actions[20] or self.cl_actions[3] or self.cl_actions[4] or self.cl_actions[1] or self.cl_actions[2]) and 1 or 0
        if self.cl_actions[16] and moving == 1 then
            self.engine:setParameter("rpm", 1)
            self.engine:setParameter("load", 0)
        else
            self.engine:setParameter("rpm", 0.33 + moving * 0.1)
            self.engine:setParameter("load", 0.5 + moving * 0.1)
        end
    elseif not seatedChar and self.thrusters[1]:isPlaying() then
        for i = 1, 4 do
            self.thrusters[i]:stop()
        end
        self.engine:stop()
    end

    if self.seatedTick and not self.controllingRocket then
        if not self.cockpit:isPlaying() then
            self.cockpit:start()
            self.aimPoint:start()
        end

        self:cl_updateSeatGui()
    else
        if self.cockpit:isPlaying() then
            self.cockpit:stop()
            self.aimPoint:stop()

            for i = 1, 2 do
                self.tracers[i]:stop()
            end
        end

        return
    end

    local camPos = self:GetCameraPosition(dt)
    local char = sm.localPlayer.getPlayer().character
    local charDir = char:getSmoothViewDirection()

    sm.camera.setCameraState(2)
    sm.camera.setPosition(camPos)
    sm.camera.setDirection(charDir)
    if self.cl_actions[18] then
        sm.camera.setFov(sm.camera.getDefaultFov() * 0.4)
    else
        sm.camera.setFov(sm.camera.getDefaultFov())
    end

    local targetPos, offsets
    if self.tracingTurret then --or self.cl_actions[18] then
        targetPos = camPos + charDir * 100
        local gunPos = self.interactable:getWorldBonePosition("jnt_turret_firepos")
        local hit, result = sm.physics.raycast(camPos, targetPos, self.shape, rayFilter)
        if hit then
            targetPos = result.pointWorld
        end

        local colHit, colResult = sm.physics.spherecast(gunPos, targetPos, 0.075, nil, rayFilter)
        if colResult:getShape() == self.shape then
            self:cl_setTracerColour(red)
        else
            self:cl_setTracerColour(green)
        end

        offsets = turretOffset
    else
        _, _, targetPos = self:GetRocketFireData(camPos)
        offsets = rocketOffset

        self:cl_setTracerColour(green)
    end

    self.aimPoint:setPosition(targetPos)
    self.aimPoint:setScale(vec3(1,1,1) * 0.5)
    if self.tracerEnabled then
        for i = 1, 2 do
            local offset = offsets[i]
            self.tracers[i]:update(
                self.shape:getInterpolatedWorldPosition() +
                self.shape:getInterpolatedAt() * offset.z -
                self.shape:getInterpolatedUp() * offset.y +
                self.shape:getInterpolatedRight() * offset.x +
                self.shape.velocity * dt, targetPos
            )
        end
    elseif self.tracers[1].effect:isPlaying() then
        for i = 1, 2 do
            self.tracers[i]:stop()
        end
    end
end

function Gunship:client_onFixedUpdate()
    if #self.interactable:getChildren(2^14) == 0 then
        self.controllingRocket = false
        self.network:sendToServer("sv_onRocketExplode")
    end

    if self.seatedTick and sm.game.getServerTick() - self.seatedTick > 5 and not self.interactable:getSeatCharacter() then
        self.seatedTick = nil
        sm.camera.setCameraState(0)
        self.gui:close()
    end
end

function Gunship:client_canInteract()
    return self.interactable:getSeatCharacter() == nil
end

function Gunship:client_onInteract(char, state)
    if not state then return end

    sm.localPlayer.setLockedControls(true)
    sm.localPlayer.setDirection(self.shape.up)
    sm.event.sendToInteractable(self.interactable, "cl_seat")
end

function Gunship:cl_seat()
    sm.localPlayer.setLockedControls(false)
    sm.camera.setCameraState(2)
    self.gui:open()
    self.interactable:setSeatCharacter(sm.localPlayer.getPlayer().character)
    self.seatedTick = sm.game.getServerTick()
end

function Gunship:client_onAction(action, state)
    if self:cl_checkRocketInput(action, state) then
        return true
    end

    if actions[action] then
        self.cl_actions[action] = state
        self.network:sendToServer("sv_updateAction", { action, state })
    end

    if state then
        if action == 15 then
            sm.camera.setCameraState(0)
            self.gui:close()
            self.interactable:setSeatCharacter(sm.localPlayer.getPlayer().character)
            self.seatedTick = nil
        elseif action == 6 then
            self.tracerEnabled = not self.tracerEnabled
        elseif action == 7 then
            self.tracingTurret = not self.tracingTurret
        end
    end

    if action >= 8 and action <= 14 then
        if state then
			self.interactable:pressSeatInteractable( action - 8 )
        else
			self.interactable:releaseSeatInteractable( action - 8 )
        end
    end

    return true
end

local rocketIcon, tracerIcon, turretIcon =
    tostring(obj_interactive_propanetank_small),
    tostring(tool_connect),
    tostring(obj_interactive_mountablespudgun)
local mountedCannonUUID = "0af5379e-29e8-4eb3-b965-6b3993c8f1df"
local MountedCannonGun = {
    ammoTypes = {
        "24d5e812-3902-4ac3-b214-a0c924a5c40f",
        -- "4c69fa44-dd0d-42ce-9892-e61d13922bd2",
        "e36b172c-ae2d-4697-af44-8041d9cbde0e",
        "242b84e4-c008-4780-a2dd-abacea821637"
    },
    overrideAmmoTypes = {
        "47b43e6e-280d-497e-9896-a3af721d89d2",
        "24001201-40dd-4950-b99f-17d878a9e07b",
        "8d3b98de-c981-4f05-abfe-d22ee4781d33",
    }
}
function Gunship:cl_updateSeatGui()
    self.gui:setGridItem( "ButtonGrid", 0, {
        itemId = rocketIcon,
        active = self.cl_actions[5]
    })

    self.gui:setGridItem( "ButtonGrid", 1, {
        itemId = tracerIcon,
        active = self.tracerEnabled
    })

    if self.tracingTurret then
        self.gui:setGridItem( "ButtonGrid", 2, {
            itemId = turretIcon,
            active = self.cl_actions[19]
        })
    else
        self.gui:setGridItem( "ButtonGrid", 2, {
            itemId = rocketIcon,
            active = self.cl_actions[5]
        })
    end

    local children = self.interactable:getChildren()
    for i = 1, self.maxChildCount do
        local int = children[i]
        if int then
            local uuid = tostring(int.shape.uuid)
            if uuid == mountedCannonUUID then
                self.gui:setGridItem( "ButtonGrid", 2 + i, {
                    itemId = sm.GetTurretAmmoData(MountedCannonGun, sm.GetInteractableClientPublicData(int).ammoType),
                    active = int.active
                })
            else
                self.gui:setGridItem( "ButtonGrid", 2 + i, {
                    itemId = uuid,
                    active = int.active
                })
            end
        else
            self.gui:setGridItem( "ButtonGrid", 2 + i, nil)
        end
    end
end

function Gunship:cl_updateAction(args)
    if sm.localPlayer.getPlayer().character ~= self.interactable:getSeatCharacter() then
        self.cl_actions[args[1]] = args[2]
    end
end

function Gunship:cl_setTracerColour(colour)
    for i = 1, 2 do
        self.tracers[i].effect:setParameter("color", colour)
    end
    self.aimPoint:setParameter("color", colour)
end

function Gunship:cl_checkRocketInput(action, state)
	local cannon = self.interactable:getChildren(2^14)[1]
	if cannon and sm.GetInteractableClientPublicData(cannon --[[@as Interactable]]).hasRocket then
		self.network:sendToServer("sv_onRocketInput", { cannon = cannon, action = action, state = state })

		if state then
			return true
		end
	end

	return false
end

function Gunship:sv_onRocketInput(data)
	sm.event.sendToInteractable(data.cannon, "sv_onRocketInput", { action = data.action, state = data.state })
end

function Gunship:cl_onRocketFire()
    self.controllingRocket = true
    self.network:sendToServer("sv_onRocketFire")
	self.gui:close()
end

function Gunship:cl_onRocketExplode()
    self.controllingRocket = false
    self.network:sendToServer("sv_onRocketExplode")

    self.gui:open()
    sm.localPlayer.setLockedControls(true)
    sm.localPlayer.setDirection(self.shape.up)
    sm.event.sendToInteractable(self.interactable, "cl_onRocketExplodeEnd")
end

function Gunship:cl_onRocketExplodeEnd()
    sm.localPlayer.setLockedControls(false)
end



function Gunship:GetCameraPosition(dt)
    -- return self.interactable:getWorldBonePosition("jnt_camera")
    return self.shape:getInterpolatedWorldPosition() + self.shape.velocity * (dt or (1/40)) + self.shape:getInterpolatedUp() * 4 + self.shape:getInterpolatedAt() * 0.25
    -- return self.shape:getInterpolatedWorldPosition() + self.shape.velocity * (dt or (1/40)) - self.shape:getInterpolatedUp() * 10 + self.shape:getInterpolatedAt() * 2
end

function Gunship:GetRocketFireData(start)
    local firePos = start + self.shape.velocity * (1/40)
    local camPos = self:GetCameraPosition()
    local targetPos = camPos + self.shape:getInterpolatedUp() * 100
    local hit, result = sm.physics.spherecast(camPos, targetPos, 0.15, self.shape, rayFilter)
    if hit then
        targetPos = result.pointWorld
    end

    local low, high = sm.projectile.solveBallisticArc(firePos, targetPos, 200, 10)
    local fireDir
    if low and low:length2() > FLT_EPSILON then
        fireDir = low:normalize()
    else
        fireDir = self.shape:getInterpolatedUp() --(targetPos - firePos):normalize()
    end

    return firePos, fireDir, targetPos
end