---@class Segment
---@field angle number
---@field length number
---@field pos Vec3
---@field effect Effect

---@class Arm
---@field segments Segment[]
---@field x number
---@field y number

---@class IK : ToolClass
---@field leftArm Arm
---@field rightArm Arm
IK = class()

---@return Segment
local function CreateSegment(scale)
    local effect = sm.effect.createEffect("ShapeRenderable")
    effect:setParameter("uuid", blk_plastic)
    effect:setScale(scale)

    return {
        angle = 0,
        length = scale.z,
        pos = sm.vec3.zero(),
        effect = effect
    }
end

local armScale = sm.vec3.new(0.5, 0.5, 2.5) * 0.25
local handScale = sm.vec3.new(0.75, 0.75, 0.75) * 0.25

---@return Arm
local function CreateArm()
    return {
        segments = {
            CreateSegment(armScale),
            CreateSegment(armScale),
            CreateSegment(handScale),
        },
        x = 0,
        y = 0
    }
end

---@param arm Arm
local function StartArm(arm)
    for k, v in pairs(arm.segments) do
        v.effect:start()
    end
end

---@param arm Arm
local function StopArm(arm)
    for k, v in pairs(arm.segments) do
        v.effect:stop()
    end
end

---@param arm Arm
local function DestroyArm(arm)
    for k, v in pairs(arm.segments) do
        v.effect:destroy()
    end
end

---@param origin Vec3
---@param arm Arm
---@param position Vec3
local function UpdateArmIK(origin, arm, position)
    -- local x, y, z = position.x - origin.x, position.y - origin.y, position.z - origin.z
    -- local b = math.atan2(y, x) * (180 / math.pi)
    -- local l = math.sqrt(x*x + y*y)
    -- local h = math.sqrt(l*l + z*z)
    -- local phi = math.atan(z/l) * (180 / math.pi)
    -- local theta = math.acos((h/2)) * (180 / math.pi)
    -- local a1 = phi + theta
    -- local a2 = phi - theta

    -- local armOffset = sm.vec3.new(0, 0, armScale.z * 0.5)
    -- local upperArmRot = sm.quat.fromEuler(sm.vec3.new(0, a1, 0))
    -- local upperArmPos = origin - upperArmRot * armOffset
    -- arm.effects[1]:setPosition(upperArmPos)
    -- arm.effects[1]:setRotation(upperArmRot)
    -- arm.effects[1]:setScale(armScale)

    -- local foreArmRot =  sm.quat.fromEuler(sm.vec3.new(0, a2, 0))
    -- arm.effects[2]:setPosition(upperArmPos - upperArmRot * armOffset + foreArmRot * armOffset)
    -- arm.effects[2]:setRotation(foreArmRot)
    -- arm.effects[2]:setScale(armScale)

    local segments = arm.segments
    
end



function IK:client_onCreate()
    self.isLocal = self.tool:isLocal()

    if not self.isLocal then return end

    self.leftArm = CreateArm()
    self.rightArm = CreateArm()
end

function IK:client_onDestroy()
    if not self.isLocal then return end

    DestroyArm(self.leftArm)
    DestroyArm(self.rightArm)
end

function IK:client_onEquippedUpdate(lmb, rmb, f)
    local x, y = sm.localPlayer.getMouseDelta()
    if lmb == 1 or lmb == 2 then
        self.leftArm.x = sm.util.clamp(self.leftArm.x - x, -1, 0)
        self.leftArm.y = sm.util.clamp(self.leftArm.y + y, -0.75, 0.75)
    end

    if rmb == 1 or rmb == 2 then
        self.rightArm.x = sm.util.clamp(self.rightArm.x - x, 0, 1)
        self.rightArm.y = sm.util.clamp(self.rightArm.y + y, -0.75, 0.75)
    end

    local forward = self.rotation * sm.vec3.new(0,1,0)
    local leftHandPosition = self.origin + forward + self.rotation * sm.vec3.new(self.leftArm.x, 0, self.leftArm.y)
    self.leftArm.segments[3].effect:setPosition(leftHandPosition)
    self.leftArm.segments[3].effect:setRotation(self.rotation)
    UpdateArmIK(self.origin + forward * 0.25 - self.rotation * sm.vec3.new(0.25,0,0), self.leftArm, leftHandPosition)

    local rightHandPosition = self.origin + forward + self.rotation * sm.vec3.new(self.rightArm.x, 0, self.rightArm.y)
    self.rightArm.segments[3].effect:setPosition(rightHandPosition)
    self.rightArm.segments[3].effect:setRotation(self.rotation)
    UpdateArmIK(self.origin + forward * 0.25 + self.rotation * sm.vec3.new(0.25,0,0), self.rightArm, rightHandPosition)

    return true, true
end

function IK:client_onEquip()
    if not self.isLocal then return end

    self.leftArm.x = -0.5
    self.leftArm.y = 0
    self.rightArm.x = 0.5
    self.rightArm.y = 0

    self.origin = sm.camera.getPosition()
    self.rotation = sm.camera.getRotation()

    sm.camera.setCameraState(sm.camera.state.cutsceneFP)
    sm.camera.setPosition(self.origin)
    sm.camera.setRotation(self.rotation)
    sm.camera.setFov(sm.camera.getFov())

    StartArm(self.leftArm)
    StartArm(self.rightArm)
end

function IK:client_onUnequip()
    if not self.isLocal then return end

    sm.camera.setCameraState(0)

    StopArm(self.leftArm)
    StopArm(self.rightArm)
end