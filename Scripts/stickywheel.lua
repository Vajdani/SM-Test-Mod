Line_swheel = class()
local up = sm.vec3.new(0,0,1)
function Line_swheel:init( thickness, colour )
    self.effect = sm.effect.createEffect("ShapeRenderable")
	self.effect:setParameter("uuid", sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a"))
    self.effect:setParameter("color", colour)
    self.effect:setScale( sm.vec3.one() * thickness )

    self.thickness = thickness
	self.spinTime = 0
end

---@param startPos Vec3
---@param endPos Vec3
---@param dt number
---@param spinSpeed number
function Line_swheel:update( startPos, endPos, dt, spinSpeed )
	local delta = endPos - startPos
    local length = delta:length()

    if length < 0.0001 then
        --sm.log.warning("Line_swheel:update() | Length of 'endPos - startPos' must be longer than 0.")
        return
	end

	local rot = sm.vec3.getRotation(up, delta)
	local deltaTime = dt or 0
	local speed = spinSpeed or 0
	self.spinTime = self.spinTime + deltaTime * speed
	rot = rot * sm.quat.angleAxis( math.rad(self.spinTime), up )

	local distance = sm.vec3.new(self.thickness, self.thickness, length)

	self.effect:setPosition(startPos + delta * 0.5)
	self.effect:setScale(distance)
	self.effect:setRotation(rot)

    if not self.effect:isPlaying() then
        self.effect:start()
    end
end

function Line_swheel:destroy()
    self.effect:destroy()
end



---@class SWheel : ShapeClass
SWheel = class()
SWheel.maxChildCount = 0
SWheel.maxParentCount = -1
SWheel.connectionInput = sm.interactable.connectionType.logic
SWheel.connectionOutput = sm.interactable.connectionType.none
SWheel.colorNormal = sm.color.new("#00aa00")
SWheel.colorHighlight = sm.color.new("#00ff00")
SWheel.poseWeightCount = 1

function SWheel:server_onCreate()
    self.sv_impulsePoins = {}
end

function SWheel:server_onCollision( other, position, selfPointVelocity, otherPointVelocity, normal )
    if not self:isActive() then return end

    local objType = type(other)
    if objType == "Character" or isAnyOf(other, self.shape.body:getCreationShapes()) then return end

    for k, data in pairs(self.sv_impulsePoins) do
        local point = type(data) == "table" and data.shape:transformLocalPoint( data.pos ) or data
        if (point - position):length2() <= 1 then
            return
        end
    end

    local data = objType == "Shape" and { shape = other, pos = other:transformPoint(position) } or position
    self.sv_impulsePoins[#self.sv_impulsePoins+1] = data

    if #self.sv_impulsePoins > 3 then
        table.remove(self.sv_impulsePoins, 1)
        self.network:sendToClients("cl_destroyLine", 1)
    end

    self.network:sendToClients("cl_createLine", data)
end

function SWheel:server_onFixedUpdate()
    if not self:isActive() then
        if #self.sv_impulsePoins > 0 then
            self.sv_impulsePoins = {}
            self.network:sendToClients("cl_destroyLines")
        end

        return
    end

    local shape = self.shape
    local mass = shape.mass
    local position = shape.worldPosition

    for k, data in pairs(self.sv_impulsePoins) do
        ---@type Vec3
        local point
        if type(data) == "table" then
            if sm.exists(data.shape) then
                point = data.shape:transformLocalPoint( data.pos )
            else
                table.remove(self.sv_impulsePoins, k)
                self.network:sendToClients("cl_destroyLine", k)
            end
        else
            point = data
        end

        if point then
            local direction = point - position
            local multiplier = direction:length()/2

            if multiplier >= 1 then
                table.remove(self.sv_impulsePoins, k)
                self.network:sendToClients("cl_destroyLine", k)
            else
                sm.physics.applyImpulse(
                    shape,
                    direction:normalize() * mass * multiplier,
                    true
                )
            end
        end
    end
end


function SWheel:client_onCreate()
    self.cl_impulsePoins = {}
end

function SWheel:client_onDestroy()
    for k, data in pairs(self.cl_impulsePoins) do
        data.line:destroy()
    end
end

function SWheel:cl_createLine(data)
    local line = Line_swheel()
    line:init( 0.1, sm.color.new(0,1,0))
    self.cl_impulsePoins[#self.cl_impulsePoins+1] = { pos = data, line = line }
end

function SWheel:cl_destroyLine(k)
    self.cl_impulsePoins[k].line:destroy()
    table.remove(self.cl_impulsePoins, k)
end

function SWheel:cl_destroyLines()
    for k, v in pairs(self.cl_impulsePoins) do
        self.cl_impulsePoins[k].line:destroy()
    end
    self.cl_impulsePoins = {}
end

function SWheel:client_onUpdate( dt )
    local pos = self.shape.worldPosition
    for k, data in pairs(self.cl_impulsePoins) do
        local point = data.pos
        if type(data.pos) == "table" and sm.exists(data.pos.shape) then
            point = data.pos.shape:transformLocalPoint( data.pos.pos )
        end
        data.line:update( pos, point )
    end
end




function SWheel:isActive()
    local parents = self.interactable:getParents()
    if #parents == 0 then return true end

    for k, parent in pairs(parents) do
        if parent.active then return true end
    end

    return false
end