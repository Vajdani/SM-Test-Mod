---@class Tank : ShapeClass
Tank = class()

dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"

local vec3_zero = sm.vec3.zero()
local vec3_up = sm.vec3.new(0, 0, 1)
local Rad2Deg = 180 / math.pi

function Tank:server_onCreate()
    self.sv_controls = { false, false, false, false }

    self.machineGunTimer = Timer()
    self.machineGunTimer:start( 4 )

    self.cannonTimer = Timer()
    self.cannonTimer:start( 2 * 40 )
end

function Tank:server_onFixedUpdate()
    self.machineGunTimer:tick()
    self.cannonTimer:tick()

    local controls = self.sv_controls
    local fwd = BoolToVal(controls[3]) - BoolToVal(controls[4])
    local right = BoolToVal(controls[1]) - BoolToVal(controls[2])

    local shape = self.shape
    local mass = shape.mass * (self:isGrounded() and 1 or 0)
    local vel = shape.velocity; vel.z = 0
    sm.physics.applyImpulse(shape, (shape.right * fwd - vel * 0.25) * mass, true)

    local body = shape.body
    local angularVel = body.angularVelocity;
    angularVel.x = 0;
    angularVel.y = 0
    sm.physics.applyTorque(body, (shape.at * right * 0.25 - angularVel * 0.25) * mass, true)

    local char = self.interactable:getSeatCharacter()
    if not char then return end

    local cannonPos = shape.worldPosition + vec3_up * 0.5 + shape.right * 2
    local attacker = char:getPlayer()
    if controls[18] and self.machineGunTimer:done() then
        sm.projectile.projectileAttack(
            projectile_potato,
            28,
            cannonPos,
            char.direction * 250,
            attacker
        )
        self.machineGunTimer:reset()

        self.network:sendToClients("cl_playEffect", "machineGunEffect")
    end

    if controls[19] and self.cannonTimer:done() then
        sm.projectile.projectileAttack(
            projectile_explosivetape,
            150,
            cannonPos,
            char.direction * 250,
            attacker
        )
        self.cannonTimer:reset()

        self.network:sendToClients("cl_playEffect", "cannonEffect")
    end
end

function Tank:sv_updateControls(controls, caller)
    local char = self.interactable:getSeatCharacter()
    if not char or char:getPlayer() ~= caller then return end

    self.sv_controls = controls
    self.network:sendToClients("cl_updateControls", controls)
end

function Tank:sv_onEnter(toggle, caller)
    self.network:sendToClients("cl_onEnter", { toggle = toggle, player = toggle and caller or nil })
end



function Tank:client_onCreate()
    local actions = sm.interactable.actions
    self.cl_controls = {
        false,
        false,
        false,
        false,
        [actions.create] = false,
        [actions.attack] = false
    }
    self.controller = nil

    self.engine = sm.effect.createEffect("GasEngine - Level 3", self.interactable)
    self.machineGunEffect = sm.effect.createEffect("SpudgunSpinner - SpinnerMuzzel", self.interactable, "barrel")
    self.cannonEffect = sm.effect.createEffect("TapeBot - Shoot", self.interactable, "barrel")

    local rot = sm.quat.angleAxis(math.rad(-90), sm.vec3.new(1,0,0))
    self.machineGunEffect:setOffsetPosition(sm.vec3.new(0.03,0.3,-0.115))
    self.machineGunEffect:setOffsetRotation(rot)
    self.cannonEffect:setOffsetPosition(sm.vec3.new(0.025,1.9,0))
    self.cannonEffect:setOffsetRotation(rot)

    self.rpm = 0
    self.pitch = 0
    self.yaw = 0

    self.interactable:setAnimEnabled("turret_rotate", true)
    self.interactable:setAnimEnabled("barrel_rotate", true)
end

function Tank:client_onDestroy()
    --[[
    if sm.localPlayer.getPlayer() == self.controller then
        sm.camera.setCameraState(0)
    end
    ]]
end

function Tank:client_onUpdate( dt )
    local controls = self.cl_controls
    local rpm = sm.util.clamp(BoolToVal(controls[3]) + BoolToVal(controls[4]) + BoolToVal(controls[1]) * 0.5 + BoolToVal(controls[2]) * 0.5, 0, 1)
    local lerp = dt * 2.5
    self.rpm = sm.util.lerp(self.rpm, rpm, lerp)
    self.engine:setParameter("rpm", self.rpm)

    local yaw, pitch = 0, 0
    --[[
    local char = self.interactable:getSeatCharacter()
    if char then
        local dir = char.direction
        local _yaw = math.atan2(dir.x, dir.z) * Rad2Deg
        local _pitch = math.atan2(dir.y, math.sqrt(dir.x * dir.x + dir.z * dir.z)) * Rad2Deg
        yaw = (_yaw + 180) / 360
        pitch = (_pitch + 90) / 180;
    end
    ]]

    --self.yaw = sm.util.lerp(self.yaw, yaw, lerp)
    self.interactable:setAnimProgress("turret_rotate", yaw --[[self.yaw]])

    --self.pitch = sm.util.lerp(self.pitch, pitch, lerp)
    self.interactable:setAnimProgress("barrel_rotate", pitch --[[self.pitch]])

    --[[
    if sm.localPlayer.getPlayer() == self.controller then
        local worldPos = shape.worldPosition
        local fwd = shape.right
        local newPos = worldPos - fwd * 3 + shape.at * 2

        local lerpTime = dt * 5
        sm.camera.setPosition(sm.vec3.lerp(sm.camera.getPosition(), newPos, lerpTime))
        sm.camera.setDirection(sm.vec3.lerp(sm.camera.getDirection(), (worldPos - newPos + vec3_up):normalize(), lerpTime))
    elseif sm.camera.getCameraState() == 0 then
        sm.camera.setPosition(sm.camera.getPosition())
        sm.camera.setDirection(sm.camera.getDirection())
    end
    ]]
end

function Tank:client_canInteract()
    return self.interactable:getSeatCharacter() == nil
end

function Tank:client_onInteract(char, state)
    if not state then return end

    self.interactable:setSeatCharacter(char)
    self.network:sendToServer("sv_onEnter", true)
    --sm.camera.setCameraState(3)
    --sm.camera.setFov(sm.camera.getDefaultFov())
end

function Tank:client_onAction(action, state)
    if self.cl_controls[action] ~= nil then
        self.cl_controls[action] = state
        self.network:sendToServer("sv_updateControls", self.cl_controls)
    end

    if state then
        if action == 15 then
            local actions = sm.interactable.actions
            self.cl_controls = {
                false,
                false,
                false,
                false,
                [actions.create] = false,
                [actions.attack] = false
            }
            self.network:sendToServer("sv_updateControls", self.cl_controls)
            self.interactable:setSeatCharacter(sm.localPlayer.getPlayer().character)
            self.network:sendToServer("sv_onEnter", false)
            --sm.camera.setCameraState(0)
        end
    end

    return not isAnyOf(action, { 20, 21 })
end

function Tank:cl_onEnter(args)
    if args.toggle then
        self.engine:start()
    else
        self.engine:stop()
    end

    --self.controller = args.player
end

function Tank:cl_updateControls(controls)
    self.cl_controls = controls
end

function Tank:cl_playEffect( effect )
    self[effect]:start()
end

function Tank:isGrounded()
    local pos = self.shape.worldPosition
    local hit, result = sm.physics.spherecast(pos, pos - self.shape.at * 0.75, 0.1, self.shape.body, 1 + 2 + 128 + 256)
    return hit
end

function BoolToVal(bool)
    return bool and 1 or 0
end