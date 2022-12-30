---@class test : ToolClass
test = class()

local ACM = sm["6adc7c70-de63-4f47-afbf-018220f548d4"]
local LaserRange = 15
local LaserColour = sm.color.new(0,1,1)
local HeightAdjust = sm.vec3.new(0,0,0.575)

function test:server_onCreate()
    self.sv_laser = ACM.laser.createLaser()
    self.sv_itslaserintime = false
end

function test:server_onFixedUpdate()
    local char = self.tool:getOwner().character
    if self.sv_itslaserintime then
        local hitData = self.sv_laser:sv_fire( char.worldPosition + HeightAdjust, char.direction, LaserRange, false )
        if #hitData > 0 then
            local hit = hitData[1]
            local shape = hit.shape
            if sm.item.isBlock(shape.uuid) then
                shape:destroyBlock( shape:getClosestBlockLocalPosition( hit.hitPos ) )
            else
                shape:destroyShape()
            end
        end
    end
end

function test:sv_onPrimary( bool )
    self.sv_itslaserintime = bool
    self.network:sendToClients("cl_onPrimary", bool)
end



function test:client_onCreate()
    self.cl_laser = ACM.laser.createLaser()
    self.cl_itslaserintime = false
    self.cl_laserPos = sm.vec3.zero()
end

function test:client_onDestroy()
    self.cl_laser:cl_destroy()
end

function test:client_onUpdate( dt )
    if self.cl_itslaserintime then
        local pos = self.tool:getPosition() + HeightAdjust --self.tool:getOwner().character:getTpBonePos("jnt_head")
        self.cl_laser:cl_fire( pos, self.tool:getSmoothDirection(), LaserRange, LaserColour )
    else
        self.cl_laser:cl_stop()
    end
end

function test:client_onEquippedUpdate( rmb, lmb, f )
    local laserin = isAnyOf(rmb, {1,2})
    if laserin ~= self.cl_itslaserintime then
        self.network:sendToServer("sv_onPrimary", laserin)
    end

    return true, true
end

function test:cl_onPrimary( bool )
    self.cl_itslaserintime = bool
end