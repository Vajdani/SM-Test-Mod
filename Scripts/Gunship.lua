---@class Gunship : ShapeClass
Gunship = class()

local actions = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [18] = true,
    [19] = true,
}

function Gunship:server_onCreate()
    self.sv_actions = {}
end

function Gunship:sv_updateAction(args)
    self.sv_actions[args[1]] = args[2]
end

function Gunship:server_onFixedUpdate(dt)
    local char = self.interactable:getSeatCharacter()
    if not char then return end

    local pos = self.shape.worldPosition
    local hit, result = sm.physics.raycast(pos, pos - sm.vec3.new(0,0,100), self.shape)

    local fwd = self.sv_actions[3] and 1 or (self.sv_actions[4] and -1 or 0)
    local right = self.sv_actions[1] and 1 or (self.sv_actions[2] and -1 or 0)

	local mass = self.shape.mass
	local force = result.pointWorld + sm.vec3.new(0,0,5) - pos
    force = force + self.shape.up * fwd * 5
    force = force + self.shape.right * right * 5

	sm.physics.applyImpulse(self.shape, ((force  * 2) - ( self.shape.velocity--[[@as Vec3]] * 0.3 )) * mass, true)
    sm.physics.applyTorque(self.shape.body, (self.shape.up:cross(char.direction) + calculateRightVector(char.direction):cross(self.shape.right) - self.shape.body.angularVelocity * 0.3) * mass, true)

    self.fireTimer = math.max((self.fireTimer or 0) - dt, 0)
    if self.sv_actions[19] then
        if self.fireTimer <= 0 then
            -- self.fireCounter = (self.fireCounter or 0) % 2 + 1
            local firePos = self.interactable:getWorldBonePosition("jnt_turret_firepos")
            sm.effect.playEffect("SpudgunSpinner - SpinnerMuzzel", firePos, nil, sm.vec3.getRotation(sm.vec3.new(0,0,1), char.direction))
            sm.projectile.projectileAttack(projectile_tape, 100, firePos, char.direction * 200, char:getPlayer())
            self.fireTimer = 0.1
        end
    end
end



function Gunship:client_onCreate()
    self.cl_actions = {}
end

local camRotAdjust = sm.quat.angleAxis(math.rad(90), sm.vec3.new(1,0,0)) * sm.quat.angleAxis(math.rad(180), sm.vec3.new(0,1,0))
function Gunship:client_onUpdate(dt)
    local char = sm.localPlayer.getPlayer().character
    if not sm.exists(char) or char ~= self.interactable:getSeatCharacter() then
        return
    end

    sm.camera.setPosition(self.shape:getInterpolatedWorldPosition() + self.shape.velocity * dt + self.shape.up * 4)
    -- sm.camera.setRotation(self.shape.worldRotation * camRotAdjust)
    sm.camera.setDirection(char.direction)
    sm.camera.setFov(sm.camera.getDefaultFov())
end

function Gunship:client_canInteract()
    return self.interactable:getSeatCharacter() == nil
end

function Gunship:client_onInteract(char, state)
    if not state then return end

    sm.camera.setCameraState(2)
    self.interactable:setSeatCharacter(char)
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
    end

    return true
end


function calculateRightVector(vector)
    local yaw = math.atan2(vector.y, vector.x) - math.pi / 2
    return sm.vec3.new(math.cos(yaw), math.sin(yaw), 0)
end