---@class Spine : ToolClass
Spine = class()

dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"

local vec3_up = sm.vec3.new(0,0,1)
local tp = {
    "$GAME_DATA/Character/Char_Male/Animations/char_male_tp_spudgun.rend"
}
sm.tool.preloadRenderables(tp)

function Spine:client_onCreate()
    self.jointWeight = 0
    self.spineWeight = 0
    self.spinning = false
    self.dt_sum = 0
    self.boosting = false
    self.boostsum = 0

    self.isLocal = self.tool:isLocal()

    --uncomment to enable penis
    --[[
    self.effect = sm.effect.createEffect("ShapeRenderable", self.tool:getOwner().character, "jnt_hips")
    self.effect:setParameter("uuid", sm.uuid.new("3c302da3-988a-4ab6-8b49-55dc14f7d8c5"))
    self.effect:setScale(sm.vec3.one() * 0.25)
    self.effect:setOffsetPosition(sm.vec3.new(0,0,0.25))
    self.effect:setOffsetRotation(sm.vec3.getRotation(vec3_up, -vec3_up))
    self.effect:start()
    ]]
end

function Spine:client_onDestroy()
    --self.effect:destroy()
end

function Spine:client_onEquip()
    self.tool:setTpRenderables( tp )
end

function Spine:client_onUpdate( dt )
    --[[self.dt_sum = (self.dt_sum or 0) + dt * 2.5
    self.dt_sum_2 = (self.dt_sum_2 or 0) + dt * 5
    local dir = sm.vec3.new( 0, 0, math.sin(self.dt_sum) ) * 100
    self.tool:updateJoint( "jnt_spine1", dir, 1 )

    local char = self.tool:getOwner().character
    local charPos = char.worldPosition + sm.vec3.new(0,0,0.35)
    local camPos = charPos + char.direction * (3 + math.sin(self.dt_sum_2) * 2)
    sm.camera.setCameraState(3)
    sm.camera.setPosition( camPos )
    sm.camera.setDirection( charPos - camPos )
    char:setNameTag( "I'd rather buy winrar" )]]

    if self.boosting then
        self.boostsum = self.boostsum + dt * 50
        self.dt_sum = self.dt_sum + dt * (1 + self.boostsum)
        local dir = sm.vec3.new( 0, self.dt_sum, 0 ) * 100
        self.tool:updateJoint( "jnt_spine1", dir, 1 )

        return
    end

    if self.spinning then
        self.dt_sum = self.dt_sum + dt * 10
        local dir = sm.vec3.new( 0, 0, self.dt_sum ) * 100

        self.spineWeight = math.min(self.spineWeight + dt * 2, 0.5)
        self.tool:updateJoint( "jnt_spine1", dir, 1 )
    elseif self.spineWeight > 0 then
        self.spineWeight = math.max(self.spineWeight - dt, 0)
    end

    self.tool:updateAnimation( "spudgun_spine_bend", self.spineWeight, self.spineWeight * 2 )

    if self.isLocal then
        self.tool:getOwner().character.movementSpeedFraction = self.spinning and 10 or 1
    end
end

function Spine:client_onEquippedUpdate( lmb, rmb )
    local spinning = isAnyOf(lmb, {1,2})
    if self.spinning ~= spinning then
        self.network:sendToServer("sv_updateSpin", spinning)
    end

    if not self.boosting and rmb == 2 then
        self.network:sendToServer("sv_initateBoost", true)
    end

    return true, true
end

function Spine:cl_updateSpin( spin )
    self.spinning = spin
end

function Spine:cl_initiateBoost( toggle )
    self.boosting = toggle
    self.boostsum = 0
end



function Spine:server_onCreate()
    self.sv_spinning = false
    self.sv_boosting = false
    self.sv_boosthover = sm.vec3.zero()
    self.sv_boostTimer = Timer()
    self.sv_boostTimer:start( 2 * 40 )
end

function Spine:sv_updateSpin( spin )
    self.sv_spinning = spin
    self.network:sendToClients("cl_updateSpin", spin)
end

function Spine:sv_initateBoost( toggle )
    self.sv_boosting = toggle
    self.sv_boosthover = toggle and self.tool:getOwner().character.worldPosition or nil
    self.network:sendToClients("cl_initiateBoost", toggle)
end

function Spine:server_onFixedUpdate()
    local char = self.tool:getOwner().character

    if self.sv_boosting then
        self.sv_boostTimer:tick()
        char:setWorldPosition( self.sv_boosthover )

        if self.sv_boostTimer:done() then
            self.sv_boostTimer:reset()
            sm.physics.applyImpulse(char, (char.direction --[[+ vec3_up]]) * char.mass * 1000)

            self:sv_initateBoost( false )
        end

        return
    end

    if self.sv_spinning then
        sm.physics.applyImpulse(char, vec3_up * char.mass / 1.5)
    end
end