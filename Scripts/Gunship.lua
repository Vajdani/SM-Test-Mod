---@class Gunship : ShapeClass
Gunship = class()

local vec3 = sm.vec3.new
local VEC3_UP = vec3(0,0,1)

local moveSpeed = 15
local boostSpeed = 50
local fireRate = 1/4
local rocketRate = 1
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

function Gunship:server_onCreate()
    self.sv_actions = {}

    self.fireTimer = 0
    self.rocketTimer = 0
    self.rocketCounter = 0
end

function Gunship:sv_updateAction(args)
    self.sv_actions[args[1]] = args[2]
end

function Gunship:server_onFixedUpdate(dt)
    local char = self.interactable:getSeatCharacter()
    if not char then return end

    local up = self.sv_actions[21] and 1 or (self.sv_actions[20] and -1 or 0)
    local fwd = self.sv_actions[3] and 1 or (self.sv_actions[4] and -1 or 0)
    local right = self.sv_actions[1] and 1 or (self.sv_actions[2] and -1 or 0)

	local mass = self.shape.mass
    local direction = char.direction
	local force = vec3(0,0,sm.physics.getGravity()) --result.pointWorld + vec3(0,0,5) - pos

    local groundCheck = self.shape.body:getWorldAabb()
    local hit, result = sm.physics.raycast(groundCheck, groundCheck - VEC3_UP * 5, self.shape.body)
    if hit then
        -- force = force + VEC3_UP * moveSpeed
        up = 1
    end

    local speed = self.sv_actions[16] and boostSpeed or moveSpeed
    force = force + VEC3_UP * up * speed
    force = force + self.shape.up * fwd * speed
    force = force + self.shape.right * right * speed
    force = force - self.shape.velocity * 0.5

	-- sm.physics.applyImpulse(self.shape, ((force  * 2) - ( self.shape.velocity--[[@as Vec3]] * 0.3 )) * mass, true)
	sm.physics.applyImpulse(self.shape, force * dt * mass, true)

    local torque = -self.shape.body.angularVelocity * 0.3 - direction * right * 0.15
    if self.sv_actions[18] then
        torque = torque + calculateRightVector(self.aimDirection):cross(self.shape.right)
    else
        self.aimDirection = direction
        torque = torque + self.shape.up:cross(direction) + calculateRightVector(direction):cross(self.shape.right)
    end

    sm.physics.applyTorque(self.shape.body, torque * mass, true)

    self.fireTimer = math.max(self.fireTimer - dt, 0)
    self.rocketTimer = math.max((self.rocketTimer or 0) - dt, 0)
    if self.sv_actions[19] and self.fireTimer <= 0 then
        local firePos = self.interactable:getWorldBonePosition("jnt_turret_firepos") + self.shape.velocity * (1/40)
        local camPos = self:GetCameraPosition()
        local targetPos = camPos + direction * 100
        local hit, result = sm.physics.raycast(camPos, targetPos, self.shape)
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

        sm.effect.playEffect("GunshipTurret - Shoot", firePos, nil, sm.vec3.getRotation(VEC3_UP, fireDir))
        sm.projectile.projectileAttack(projectile_tape, 100, firePos, fireDir * 200, char:getPlayer())

        self.fireTimer = fireRate
    end

    if self.sv_actions[5] and self.rocketTimer <= 0 then
        self.rocketCounter = self.rocketCounter % 2 + 1
        local player = char:getPlayer()
        self:sv_fireRocket({ delay = 0, player = player })
        for i = 1, 2 do
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

    local firePos = self.interactable:getWorldBonePosition("jnt_rocket"..self.rocketCounter.."_firepos") + self.shape.velocity * (1/40)
    local camPos = self:GetCameraPosition()
    local targetPos = camPos + self.shape.up * 100
    local hit, result = sm.physics.spherecast(camPos, targetPos, 0.15, self.shape)
    if hit then
        targetPos = result.pointWorld
    end

    local low, high = sm.projectile.solveBallisticArc(firePos, targetPos, 200, 10)
    local fireDir
    if low then
        fireDir = low:normalize()
    else
        fireDir = self.shape.up --(targetPos - firePos):normalize()
    end

    sm.effect.playEffect("GunshipTurret - Shoot", firePos, nil, sm.vec3.getRotation(VEC3_UP, fireDir))
    sm.projectile.projectileAttack(projectile_explosivetape, 100, firePos + fireDir, fireDir * 200, args.player)
end



function Gunship:client_onCreate()
    self.cl_actions = {}

    local effect = sm.effect.createEffect("ShapeRenderable", self.interactable)
    effect:setParameter("uuid", sm.uuid.new("5e7a0724-a469-468a-9138-eea1b23c2387"))
    effect:setParameter("color", self.shape.color)
    effect:setScale(vec3(0.25, 0.25, 0.25))
    effect:setOffsetRotation(sm.quat.angleAxis(math.rad(-90), vec3(1,0,0)))
    effect:start()

    self.cockpit = effect

    self.thrusters = {}
    for i = 1, 4 do
        local effect = sm.effect.createEffect("Thruster - Level 5", self.interactable, "jnt_engine"..i.."_effect")
        effect:setOffsetRotation(sm.quat.angleAxis(math.rad(90), vec3(1,0,0)))
        table.insert(self.thrusters, effect)
    end
end

function Gunship:client_onDestroy()
    if self.seated then
        sm.camera.setCameraState(0)
    end
end

-- local camRotAdjust = sm.quat.angleAxis(math.rad(90), vec3(1,0,0)) * sm.quat.angleAxis(math.rad(180), vec3(0,1,0))
function Gunship:client_onUpdate(dt)
    self.interactable:setSubMeshVisible("Glass", not self.seated)

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
    --     self.interactable:setAnimProgress(name, 0.1)
    --     -- print(name, self.interactable:getAnimDuration(name))
    -- end

    local seatedChar = self.interactable:getSeatCharacter()
    if seatedChar and not self.thrusters[1]:isPlaying() then
        for i = 1, 4 do
            self.thrusters[i]:start()
        end
    elseif not seatedChar and self.thrusters[1]:isPlaying() then
        for i = 1, 4 do
            self.thrusters[i]:stop()
        end
    end

    if self.seated then
        if not self.cockpit:isPlaying() then
            self.cockpit:start()
        end
    else
        if self.cockpit:isPlaying() then
            self.cockpit:stop()
        end

        return
    end

    local char = sm.localPlayer.getPlayer().character
    if self.cl_actions[18] then
        sm.camera.setPosition(self:GetCameraPosition(dt))
        sm.camera.setDirection(char.direction)
        sm.camera.setFov(sm.camera.getDefaultFov() * 0.4)
    else
        sm.camera.setPosition(self:GetCameraPosition(dt))
        -- sm.camera.setRotation(self.shape.worldRotation * camRotAdjust)
        sm.camera.setDirection(char.direction)
        sm.camera.setFov(sm.camera.getDefaultFov())
    end
end

function Gunship:client_canInteract()
    return self.interactable:getSeatCharacter() == nil
end

function Gunship:client_onInteract(char, state)
    if not state then return end

    sm.camera.setCameraState(2)
    self.interactable:setSeatCharacter(char)
    self.seated = true
end

function Gunship:client_onAction(action, state)
    if actions[action] then
        self.cl_actions[action] = state
        self.network:sendToServer("sv_updateAction", { action, state })
    end

    if not state then return true end

    if action == 15 then
        sm.camera.setCameraState(0)
        self.interactable:setSeatCharacter(sm.localPlayer.getPlayer().character)
        self.seated = false
    end

    return true
end



function Gunship:GetCameraPosition(dt)
    -- return self.interactable:getWorldBonePosition("jnt_camera")
    return self.shape:getInterpolatedWorldPosition() + self.shape.velocity * (dt or (1/40)) + self.shape:getInterpolatedUp() * 4
    -- return self.shape:getInterpolatedWorldPosition() + self.shape.velocity * (dt or (1/40)) - self.shape:getInterpolatedUp() * 10 + self.shape:getInterpolatedAt() * 2
end

function calculateRightVector(vector)
    local yaw = math.atan2(vector.y, vector.x) - math.pi / 2
    return vec3(math.cos(yaw), math.sin(yaw), 0)
end