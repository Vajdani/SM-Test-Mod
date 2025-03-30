local connection_seated = 8
local connection_logic = 1
local conenction_bearing = sm.interactable.connectionType.bearing

---@class Aim : ShapeClass
Aim = class()
Aim.maxParentCount = 2
Aim.maxChildCount = -1
Aim.connectionInput = connection_seated + connection_logic
Aim.connectionOutput = conenction_bearing
Aim.colorNormal = sm.color.new( 0xff8000ff )
Aim.colorHighlight = sm.color.new( 0xff9f3aff )

Aim.LR_col = sm.color.new("#eeeeee")
Aim.UD_col = sm.color.new("#222222")

function Aim:server_onFixedUpdate()
    local active = false
    for k, v in pairs(self.interactable:getParents(connection_logic)) do
        if v.active then
            active = true
            break
        end
    end

    if not active then return end

    local seat = self.interactable:getParents(connection_seated)[1]
    if not seat then return end

    local char = seat:getSeatCharacter()
    if not char then return end

    local yaw, pitch = getYawPitch( char.direction )
    local lr, ud = {}, {}
    for k, bearing in pairs(self.interactable:getChildren(conenction_bearing)) do
        if bearing.color == self.LR_col then
            lr[#lr+1] = bearing
        elseif bearing.color == self.UD_col then
            ud[#ud+1] = bearing
        end
    end

    for k, bearing in pairs(lr) do
        bearing:setTargetAngle( yaw, 100, 400 )
    end

    for k, bearing in pairs(ud) do
        bearing:setTargetAngle( pitch, 100, 400 )
    end
end

function Aim:client_getAvailableParentConnectionCount( connectionType )
    if bit.band( connectionType, connection_seated ) ~= 0 then
        return 1 - #self.interactable:getParents( connection_seated )
    end

    return 1
end

--Thanks Nick
function getYawPitch( direction )
    return math.atan2(direction.y, direction.x) - math.pi/2, math.asin(direction.z)
end