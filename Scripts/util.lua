dofile "ProjectileLibrary.lua"


vec3 = sm.vec3.new
getRotation = sm.vec3.getRotation
getGravity = sm.physics.getGravity
angleAxis = sm.quat.angleAxis



--thanks QMark
function CalculateRightVector(vector)
    local yaw = math.atan2(vector.y, vector.x) - math.pi / 2
    return vec3(math.cos(yaw), math.sin(yaw), 0)
end

function BoolToNum(bool)
    return bool and 1 or 0
end

function quat_dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
end

function quat_normalise(a)
    local l = 1.0 / math.sqrt(quat_dot(a, a));
    return sm.quat.new(l * a.x, l * a.y, l * a.z, l * a.w);
end

oldQuatSLerp = oldQuatSLerp or sm.quat.slerp
---@diagnostic disable-next-line:duplicate-set-field
function sm.quat.slerp(q1, q2, t)
    return quat_normalise(oldQuatSLerp(q1, q2, t))
end

---@return Vec3
function getClosestBlockWorldPosition( target, position )
    local A = target:getClosestBlockLocalPosition( position )/4
    local B = target.localPosition/4 - sm.vec3.new(0.125,0.125,0.125)
    local C = target:getBoundingBox()
    return target:transformLocalPoint( A-(B+C/2) )
end

function roundVector( vec3 )
    return sm.vec3.new(round(vec3.x), round(vec3.y), round(vec3.z))
end



VEC3_RIGHT = vec3(1, 0, 0)
VEC3_FORWARD = vec3(0, 1, 0)
VEC3_UP = vec3(0, 0, 1)
VEC3_ZERO = sm.vec3.zero()
RAD90 = math.pi * 0.5
DIVRAD90 = 1 / RAD90

green = sm.color.new(0, 1, 0)
red = sm.color.new(1, 0, 0)
white = sm.color.new(1, 1, 1)
yellow = sm.color.new(1, 1, 0)
black = sm.color.new(0, 0, 0)



oldRaycast = oldRaycast or sm.physics.raycast
---@diagnostic disable-next-line:duplicate-set-field
function sm.physics.raycast(startPos, endPos, ignoredObject, mask)
    local hit, result = oldRaycast(startPos, endPos, ignoredObject,
        sm.physics.filter.default + sm.physics.filter.areaTrigger)
    if hit and result.type == "areaTrigger" then
        local trigger = result:getAreaTrigger()
        if sm.exists(trigger) then
            local userdata = trigger:getUserData()
            if userdata and userdata.isCustomCollision then
                return true, {
                    directionWorld = result.directionWorld,
                    fraction = result.fraction,
                    normalLocal = result.normalLocal,
                    normalWorld = result.normalWorld,
                    originWorld = result.originWorld,
                    pointLocal = result.pointLocal,
                    pointWorld = result.pointWorld,
                    type = "body",
                    valid = result.valid,
                    getAreaTrigger = function() return nil end,
                    getBody = function()
                        return userdata.parent.body
                    end,
                    getCharacter = function() return nil end,
                    getHarvestable = function() return nil end,
                    getJoint = function() return nil end,
                    getLiftData = function() return nil end,
                    getShape = function()
                        return userdata.parent
                    end,
                }
            end
        end
    end

    return oldRaycast(startPos, endPos, ignoredObject, mask)
end

oldSpherecast = oldSpherecast or sm.physics.spherecast
---@diagnostic disable-next-line:duplicate-set-field
function sm.physics.spherecast(startPos, endPos, radius, object, mask)
    local hit, result = oldSpherecast(startPos, endPos, radius, object,
        sm.physics.filter.default + sm.physics.filter.areaTrigger)
    if hit and result.type == "areaTrigger" then
        local trigger = result:getAreaTrigger()
        if sm.exists(trigger) then
            local userdata = trigger:getUserData()
            if userdata and userdata.isCustomCollision then
                return true, {
                    directionWorld = result.directionWorld,
                    fraction = result.fraction,
                    normalLocal = result.normalLocal,
                    normalWorld = result.normalWorld,
                    originWorld = result.originWorld,
                    pointLocal = result.pointLocal,
                    pointWorld = result.pointWorld,
                    type = "body",
                    valid = result.valid,
                    getAreaTrigger = function() return nil end,
                    getBody = function()
                        return userdata.parent.body
                    end,
                    getCharacter = function() return nil end,
                    getHarvestable = function() return nil end,
                    getJoint = function() return nil end,
                    getLiftData = function() return nil end,
                    getShape = function()
                        return userdata.parent
                    end,
                }
            end
        end
    end

    return oldSpherecast(startPos, endPos, radius, object, mask)
end