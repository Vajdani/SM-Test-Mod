---@class Medi : ToolClass
---@field target Character
---@field effects Effect[]
Medi = class()
Medi.beamSegments = 20

local defaultDir = sm.vec3.new(1,0,0)
local effectColor = sm.color.new(1,1,0)
local effectScale = sm.vec3.one() * 0.25
local camAdjust = sm.vec3.new(0,0,0.575)
local camAdjust_crouch = sm.vec3.new(0,0,0.275)

function Medi.sv_updateTarget( self, target )
    self.network:sendToClients("cl_updateTarget", target)
end

function Medi.client_onCreate( self )
    self.target = nil

    self.effects = {}
    for i = 1, self.beamSegments - 1 do
        local effect = sm.effect.createEffect("ShapeRenderable")
        effect:setParameter("uuid", small_2way_pipe)
        effect:setParameter("color", effectColor)
        effect:setScale(effectScale)
        self.effects[#self.effects+1] = effect --sm.effect.createEffect( "SledgehammerHit - Default" )
    end
end

function Medi:client_onDestroy()
    for k, effect in pairs(self.effects) do
        effect:destroy()
    end
end

function Medi.client_onUpdate( self )
    local exists = not sm.exists(self.target)
    if not self.target or exists or not self.tool:isEquipped() then
        if self.effects[1]:isPlaying() then
            for i = 1, #self.effects do
                self.effects[i]:stop()
            end
        end

        if not exists then
            self.target = nil
        end

        return
    end

    local owner = self.tool:getOwner().character
    local start = self.tool:getTpBonePos("jnt_head") --owner.worldPosition + (owner:isCrouching() and camAdjust_crouch or camAdjust)
    local _end = self.target.worldPosition
    if (_end - start):length2() > 100 then --10 meters
        self.target = nil
        return
    end

    local mid = start + owner.direction * 5
    local hit, result = sm.physics.raycast(start, mid, owner)
    if hit then
        mid = result.pointWorld + result.normalWorld * 0.1
    end

    local segments = self.beamSegments
    local posCache = {}
    for i = 1, segments do
        posCache[i] = sm.vec3.bezier2( start, mid, _end, i / segments)
    end

    for i = 1, #self.effects do
        local pos = posCache[i]
        local effect = self.effects[i]
        effect:setPosition( pos )

        local nextPos = posCache[i + 1]
        if nextPos then
            effect:setRotation( sm.vec3.getRotation(defaultDir, (nextPos - pos):normalize()) )
        end

        if not effect:isPlaying() then effect:start() end
    end
end

function Medi.client_onEquippedUpdate( self, lmb )
    if lmb == 1 then
        if self.target then
            self.network:sendToServer("sv_updateTarget", nil)
        else
            local hit, result = sm.localPlayer.getRaycast(7.5)
            if hit then
                local character = result:getCharacter()
                if character then
                    self.network:sendToServer("sv_updateTarget", character)
                end
            end
        end
    end

    return true, true
end

function Medi.cl_updateTarget( self, target )
    self.target = target
end