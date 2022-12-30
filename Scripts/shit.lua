---@class Shit : ToolClass
Shit = class()

local vec3_up = sm.vec3.new(0,0,1)
local ShitColour = sm.color.new(PAINT_COLORS[30])
local uuid = sm.uuid.new("056cd6ce-c035-47cf-8c94-f74c95e7155e")

function Shit:server_onCreate()
    self.canShit = true
end

function Shit:server_onFixedUpdate()
    local char = self.tool:getOwner().character
    local isCrouching = char:isCrouching()

    if isCrouching --[[and self.canShit]] then
        local pos = char.worldPosition - vec3_up:cross(calculateRightVector(char.direction) * 0.5)

        self.network:sendToClients("cl_onShit", pos)
        local shape = sm.shape.createPart(
            uuid,
            pos,
            sm.quat.identity(),
            true,
            true
        )
        shape:setColor(ShitColour)

        self.canShit = false
    elseif not isCrouching then
        self.canShit = true
    end
end



function Shit:cl_onShit( pos )
    sm.particle.createParticle("paint_smoke", pos, sm.quat.identity(), ShitColour)
    sm.audio.play("PotatoRifle - Shoot", pos)
end

--[[function Shit:client_onCreate()
    self.cursorX = 0
    self.cursorY = 0
    self.gui = sm.gui.createWorldIconGui( 50, 50 )
    self.gui:setImage("Icon", "$CONTENT_DATA/Gui/cursor.png" )
    self.gui:open()
end

function Shit:client_onUpdate()
    local mx, my = sm.localPlayer.getMouseDelta()
    local sens = sm.localPlayer.getAimSensitivity() * 3
    self.cursorX = sm.util.clamp(self.cursorX + mx * sens, -1, 1)
    self.cursorY = sm.util.clamp(self.cursorY + my * sens, -1, 1)

    local screenx, screeny = sm.gui.getScreenSize()
    local mousePos = sm.vec3.new( (screenx * self.cursorX) / screenx, 0, (screeny * self.cursorY) / screeny )

    local char = sm.localPlayer.getPlayer().character
    local dir = sm.vec3.new(0,-1,0)
    self.gui:setWorldPosition(char.worldPosition + dir + mousePos)

    sm.camera.setCameraState(0)
    sm.camera.setPosition(char.worldPosition)
    sm.camera.setDirection(dir)
    sm.camera.setFov(90)
end]]



--thanks QMark
function calculateRightVector(vector)
    local yaw = math.atan2(vector.y, vector.x) - math.pi / 2
    return sm.vec3.new(math.cos(yaw), math.sin(yaw), 0)
end