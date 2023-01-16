---@class sus : ShapeClass
sus = class()

function sus:server_onCreate()
    self.trigger = sm.areaTrigger.createAttachedSphere(self.interactable, 10, sm.vec3.zero(), sm.quat.identity(), sm.areaTrigger.filter.character)
end

function sus:server_onFixedUpdate()
    ---@type Character, number, Vec3
    local target, distance, dir
    local shapePos = self.shape.worldPosition
    for k, char in pairs(self.trigger:getContents() --[[@as Character[] ]]) do
        local _dir = char.worldPosition - shapePos
        local _distance = _dir:length2()
        if not distance or _distance < distance then
            distance = _distance
            target = char
            dir = _dir:normalize()
        end
    end

    local impulse = sm.vec3.zero()
    if target then
        impulse = dir
        sm.physics.applyTorque(self.shape.body, self.shape.at:cross(dir) * -2, true)
    end

    local vel = self.shape.velocity; vel.z = 0
    sm.physics.applyImpulse(self.shape, (impulse - vel * 0.2) * self.shape.mass, true)
end



function sus:client_onCreate()
    self.interactable:setAnimEnabled("run", true)
    self.animProgress = 0
    self.animDuration = self.interactable:getAnimDuration("run")
end

function sus:client_onUpdate(dt)
    self.animProgress = self.animProgress + dt
    self.interactable:setAnimProgress("run", self.animProgress / self.animDuration)
end