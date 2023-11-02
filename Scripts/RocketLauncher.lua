---@class RocketLauncher : ShapeClass
RocketLauncher = class()
RocketLauncher.maxChildCount = 0
RocketLauncher.maxParentCount = 1
RocketLauncher.connectionInput = sm.interactable.connectionType.seated + sm.interactable.connectionType.logic
RocketLauncher.connectionOutput = sm.interactable.connectionType.none
RocketLauncher.colorNormal = sm.color.new(0xcb0a00ff)
RocketLauncher.colorHighlight = sm.color.new(0xee0a00ff)
RocketLauncher.poseWeightCount = 1

local fx_rocket = sm.uuid.new("6aa659cf-b9fe-4eb8-983c-cd2182fa35fc")
local fxScale = sm.vec3.one() * 0.25
local defaultDir = sm.vec3.new(1, 0, 0)
local barrelRot = sm.quat.angleAxis(math.rad(90), defaultDir)
local barrelOfsset = sm.vec3.new(0, 0.2855, 0) * 0.25
local vec3_up = sm.vec3.new(0,0,1)
local vec3_zero = sm.vec3.zero()

local reloadTime = 0.5 * 40
local rocektSpeed = 50
local rocketLifeTime = 10
local autoAimSpread = 1
local autoAimRange = 1000
local barrelRotateSpeed = 5

function RocketLauncher:server_onCreate()
    self.sv_shootTimer = Timer()
    self.sv_shootTimer:start(reloadTime)
    self.sv_shootTimer.count = self.sv_shootTimer.ticks
end

function RocketLauncher:server_onFixedUpdate()
    self.sv_shootTimer:tick()
end

function RocketLauncher:sv_shoot()
    if not self.sv_shootTimer:done() then return end

    self.sv_shootTimer:start(reloadTime)
    self.network:sendToClients("cl_shoot")
end

function RocketLauncher:sv_onRocketHit(pos)
    sm.physics.explode(pos, 7, 2.0, 6.0, 25.0, "PropaneTank - ExplosionSmall")
end



function RocketLauncher:client_onCreate()
    self.interactable:setSubMeshVisible("launcher", false)

    self.cl_shootTimer = Timer()
    self.cl_shootTimer:start(reloadTime)
    self.cl_shootTimer.count = self.cl_shootTimer.ticks

    local col = self.shape.color
    self.colour = col
    self.fx_barrel_full = sm.effect.createEffect("ShapeRenderable", self.interactable)
    self.fx_barrel_full:setScale(fxScale)
    self.fx_barrel_full:setParameter("uuid", sm.uuid.new("23498502-aeb4-48c1-b77a-dd649a384bd7"))
    self.fx_barrel_full:setParameter("color", col)
    self.fx_barrel_full:setOffsetPosition(barrelOfsset)
    self.fx_barrel_full:start()

    self.fx_barrel = sm.effect.createEffect("ShapeRenderable", self.interactable)
    self.fx_barrel:setScale(fxScale)
    self.fx_barrel:setParameter("uuid", sm.uuid.new("343e2817-69a6-4879-bebc-277f7940b814"))
    self.fx_barrel:setParameter("color", col)
    self.fx_barrel:setOffsetPosition(barrelOfsset)

    self.targetMarker = sm.gui.createWorldIconGui( 50, 50 )
    self.targetMarker:setImage( "Icon", "$CONTENT_DATA/Gui/aimbot_marker.png" )

    self.dir = self.shape.right
    self.shooting = false
    self.rockets = {}
end

function RocketLauncher:client_canInteract(char)
    local int = char:getLockingInteractable()
    return int ~= nil and int:hasSeat()
end

function RocketLauncher:client_onFixedUpdate()
    self.cl_shootTimer:tick()
    if self:canShoot() then
        self.network:sendToServer("sv_shoot")
    end
end

function RocketLauncher:client_onInteract(char, state)
    self.shooting = state
end

function RocketLauncher:client_onDestroy()
    self.fx_barrel_full:destroy()
    self.fx_barrel:destroy()

    for k, rocket in pairs(self.rockets) do
        rocket.effect:destroy()
        rocket.thrust:destroy()
    end

    self.targetMarker:close()
end

local camAdjust = sm.vec3.new(0,0,0.575)
function RocketLauncher:client_onUpdate(dt)
    for k, rocket in pairs(self.rockets) do
        rocket.lifeTime = rocket.lifeTime - dt

        local dir = rocket.dir
        local pos = rocket.pos + dir * rocektSpeed * dt
        local hit, result = sm.physics.raycast(pos, pos + dir)
        if rocket.lifeTime <= 0 or hit then
            rocket.effect:destroy()
            rocket.thrust:destroy()

            if sm.isHost then
                self.network:sendToServer("sv_onRocketHit", rocket.pos)
            end

            self.rockets[k] = nil
        else
            rocket.pos = pos
            rocket.effect:setPosition(pos)
            rocket.thrust:setPosition(pos)
        end
    end

    local shape, int = self.shape, self.interactable
    local parent = int:getSingleParent()
    local dir = GetAccurateShapeRight(shape)
    if parent then
        if parent:hasSeat() then
            local char = parent:getSeatCharacter()
            if char then
                local hit, pos
                dir, hit, pos = self:autoAim(char, char.worldPosition + camAdjust, char.direction)

                if hit and char == sm.localPlayer.getPlayer().character then
                    self.targetMarker:setWorldPosition(pos)
                    if not self.targetMarker:isActive() then
                        self.targetMarker:open()
                    end
                else
                    self.targetMarker:close()
                end
            else
                self.shooting = false
                self.targetMarker:close()
            end
        else
            dir = self:autoAim()
        end
    end

    self.dir = Vec3Slerp(self.dir, dir, dt * barrelRotateSpeed)
    local rot = shape:transformRotation(sm.vec3.getRotation(defaultDir, self.dir)) * barrelRot
    self.fx_barrel_full:setOffsetRotation(rot)
    self.fx_barrel:setOffsetRotation(rot)

    local done, playing = self.cl_shootTimer:done(), self.fx_barrel_full:isPlaying()
    if done and not playing then
        sm.effect.playHostedEffect("Refinery - Unpack", int)
        self.fx_barrel_full:start()
        self.fx_barrel:stop()
    elseif not done and playing then
        self.fx_barrel_full:stop()
        self.fx_barrel:start()
    end

    local col = shape.color
    if self.colour ~= col then
        self.colour = col
        self.fx_barrel_full:setParameter("color", col)
        self.fx_barrel:setParameter("color", col)
    end
end

function RocketLauncher:cl_shoot()
    self.cl_shootTimer:start(reloadTime)
    sm.effect.playHostedEffect("RocketLauncher - Shoot", self.interactable)

    local dir = self.dir
    local pos = self.shape:transformLocalPoint(barrelOfsset)
    local hit, result = sm.physics.raycast(pos, pos + dir)
    if hit then
        if sm.isHost then
            self.network:sendToServer("sv_onRocketHit", result.pointWorld)
        end

        return
    end

    local effect =  sm.effect.createEffect("ShapeRenderable")
    effect:setScale(fxScale)
    effect:setParameter("uuid", fx_rocket)
    effect:setParameter("color", self.shape.color)
    effect:setPosition(pos)
    effect:setRotation(sm.vec3.getRotation(defaultDir, dir))
    effect:start()

    local thrust = sm.effect.createEffect("Thruster - Level 5")
    thrust:setPosition(pos)
    thrust:setRotation(sm.vec3.getRotation(vec3_up, dir * -1))
    thrust:start()

    self.rockets[#self.rockets+1] = {
        pos = pos,
        dir = dir,
        effect = effect,
        thrust = thrust,
        lifeTime = rocketLifeTime
    }
end



function RocketLauncher:canShoot()
    local parent = self.interactable:getSingleParent()
    return (self.shooting or parent and not parent:hasSeat() and parent.active) and self.cl_shootTimer:done()
end

function RocketLauncher:autoAim(ignore, customPos, customDir)
    local start = customPos or self.shape.worldPosition
    local dir = customDir or GetAccurateShapeRight(self.shape)
    local hit, result = sm.physics.raycast(start, start + dir * autoAimRange, ignore or self.shape.body)
    local obj = result:getBody() or result:getCharacter()

    if hit and obj and sm.exists(obj) then
        local _type = type(obj)
        if _type == "Character" and obj ~= ignore then
            local charPos = obj.worldPosition
            return (charPos - start):normalize(), true, charPos
        elseif _type == "Body" then
            local center = vec3_zero
            local bodies = obj:getCreationBodies()
            for k, body in pairs(bodies) do
                center = center + body.centerOfMassPosition
            end

            center = center / #bodies
            return (center - start):normalize(), true, center
        end
    end

    return dir, false, vec3_zero
end



--https://stackoverflow.com/questions/67919193/how-does-unity-implements-vector3-slerp-exactly
function Vec3Slerp(start, end_, percent)
    local dot = start:dot(end_)
    local theta = math.acos(dot) * percent
    local RelativeVec = (end_ - start * dot)
    if RelativeVec:length2() < FLT_EPSILON then
        return end_
    else
        RelativeVec = RelativeVec:normalize()
    end

    return ((start * math.cos(theta)) + (RelativeVec * math.sin(theta)))
end

---@param shape Shape
---@return Vec3
function GetAccurateShapeRight(shape)
    local ang = shape.body.angularVelocity
    local length = ang:length()
    local dir = shape:getInterpolatedRight()
    if length < FLT_EPSILON then return dir end

    return dir:rotate(length * 0.025, ang)
end