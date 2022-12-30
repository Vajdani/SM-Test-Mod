-- #region PID
PID = class()
---@class PID
---@field pGain number
---@field iGain number
---@field dGain number
---@field errorLast number
---@field valueLast number
---@field derivativeMeasurement string
---@field integrationStored number
---@field integralSaturation number
---@field init function
---@field setAfterInit function
---@field update function
---@field reset function
---@field angleDifference function
---@field updateAngle function

---@param dMeasure number Velocity/ErrorRateOfChange
function PID:init( pGain, iGain, dGain, dMeasure, iSaturation )
    self.pGain = pGain
    self.iGain = iGain
    self.dGain = dGain
    self.errorLast = 0
    self.valueLast = 0
    self.derivativeMeasurement = dMeasure
    self.integrationStored = 0
    self.integralSaturation = iSaturation
    self.outputMin = -1
    self.outputMax = 1
    self.derivativeInit = false
end

function PID:setAfterInit( pGain, iGain, dGain, dMeasure, iSaturation )
    self.pGain = pGain
    self.iGain = iGain
    self.dGain = dGain
    self.derivativeMeasurement = dMeasure
    self.integralSaturation = iSaturation
end

function PID:reset()
    self.derivativeInit = false
end

function PID:update( dt, current, target )
    local error = target - current
    local P = self.pGain * error

    self.integrationStored = sm.util.clamp(self.integrationStored + (error * dt), -self.integralSaturation, self.integralSaturation)
    local I = self.iGain * self.integrationStored

    local errorRateOfChange = (error - self.errorLast) / dt
    self.errorLast = error

    local valueRateOfChange = (current - self.valueLast) / dt
    self.valueLast = current

    local deriveMeasure = 0
    if self.derivativeInit then
        if self.derivativeMeasurement == "Velocity" then
            deriveMeasure = -valueRateOfChange
        else
            deriveMeasure = errorRateOfChange
        end
    else
        self.derivativeInit = true
    end

    local D = self.dGain * deriveMeasure

    return sm.util.clamp( P + I + D, self.outputMin, self.outputMax )
end


function PID:angleDifference( a, b )
    return (a - b + 540) % 360 - 180
end

function PID:updateAngle( dt, current, target )
    local error = self:angleDifference(target, current)
    local P = self.pGain * error

    self.integrationStored = sm.util.clamp(self.integrationStored + (error * dt), -self.integralSaturation, self.integralSaturation)
    local I = self.iGain * self.integrationStored

    local errorRateOfChange = self:angleDifference(error, self.errorLast) / dt
    self.errorLast = error

    local valueRateOfChange = self:angleDifference(current, self.valueLast) / dt
    self.valueLast = current

    local deriveMeasure = 0
    if self.derivativeInit then
        if self.derivativeMeasurement == "Velocity" then
            deriveMeasure = -valueRateOfChange
        else
            deriveMeasure = errorRateOfChange
        end
    else
        self.derivativeInit = true
    end

    local D = self.dGain * deriveMeasure

    return sm.util.clamp( P + I + D, self.outputMin, self.outputMax )
end
-- #endregion


--[[
TODO:
1. Fix camera getting stuck afer bot fucks you out of seat
2. PID for body roll
3. Find whoever made sm.quat.slerp and give them a bad time
4. Settings gui
5. Reduce size to just a block
]]


dofile "$SURVIVAL_DATA/Scripts/util.lua"
local vec3_up = sm.vec3.new(0,0,1)
local vec3_zero = sm.vec3.zero()
local vec3_down = sm.vec3.new(0,0,-1)
local vec3_x = sm.vec3.new(1,0,0)
local camRotAdjust = sm.quat.angleAxis(math.rad(-90), vec3_x) * sm.quat.angleAxis(math.rad(180), vec3_up)
--local camAngleDown = sm.quat.angleAxis(math.rad(-15), vec3_x)

---@class Car : ShapeClass
Car = class()
Car.cameraModes = {
    "Free Camera",
    "Follow Camera",
    "Strict Follow Camera"
}
Car.defaultEffectRot = sm.vec3.getRotation(vec3_up, sm.vec3.new(0,-1,0))
--[[
Car.stoppingDistance = 25
Car.stoppingSpeed = 25
Car.reverseDistance = 50
Car.reachedTargetDistance = 5
]]

function Car:server_onCreate()
    self.sv_controls = { false, false, false, false }
    --self.manual = true
    self:getCreationMass( self.shape.body )

    self.sv_data = self.storage:load()
    if not self.sv_data then
        self.sv_data = {
            wheelCount = 4,
            wheelOffsets = {
                sm.vec3.new( 1.5, 0, 2.5 ),
                sm.vec3.new( -1.5, 0, 2.5 ),
                sm.vec3.new( 1.5, 0, -2.5 ),
                sm.vec3.new( -1.5, 0, -2.5 ),
            },

            --physics
            hoverHeight = 3,
            speed = 1.25,
            acceleration = 1,
            friction = 0.05,
            turnSpeed = 0.5,
            turnFriction = 0.1,

            --visuals
            cameraFollowSpeed = 5
        }
    end

    self.sv_pids = {}
    for i = 1, self.sv_data.wheelCount do
        local pid = PID()
        pid:init( 0.2, 0.5, 0.06, "Velocity", 0.5 ) --( 1, 0.25, 0.1, "Velocity", 1 )

        self.sv_pids[#self.sv_pids+1] = pid
    end

    self.fwd = 0
    self.network:setClientData( self.sv_data )
end

function Car:sv_updateSettings( data )
    if data.wheelCount ~= self.sv_data.wheelCount then
        local newPids = {}
        for i = 1, data.wheelCount do
            local pid = self.sv_pids[i]
            if not pid then
                pid = PID()
                pid:init( 0.2, 0.5, 0.06, "Velocity", 0.5 )
            end

            newPids[#newPids+1] = pid
        end

        self.sv_pids = newPids
    end


    self.sv_data = data
    self.network:setClientData( self.sv_data )
    self.storage:save( self.sv_data )
end

function Car:server_onFixedUpdate( dt )
    local shape = self.shape
    local body = self.shape.body

    if body:hasChanged(sm.game.getServerTick()-1) then
        self:getCreationMass( body )
    end

    local mass = self.sv_mass
    local up = vec3_up --shape.at
    local vel = shape.velocity; vel.z = 0
    local fwdDir = shape.up
    local rightDir = shape.at
    local wheelHits = 0
    local data = self.sv_data
    local wheelMult = 1 / #data.wheelOffsets

    for k, offset in pairs(data.wheelOffsets) do
        local pos = shape:transformLocalPoint(offset)
        local hit, result = sm.physics.raycast(pos, pos - vec3_up * (data.hoverHeight + 1), body, -1)

        if hit and (result.type ~= "areaTrigger" or self:isLiquid(result:getAreaTrigger())) then
            local pid = self.sv_pids[k]
            if pid then
                local pidValue = pid:update(dt, pos.z, result.pointWorld.z + data.hoverHeight)
                sm.physics.applyImpulse(
                    shape,
                    ((up * pidValue) + (vel * -data.friction * wheelMult)) * mass,
                    true,
                    shape.worldRotation * offset
                )

                wheelHits = wheelHits + 1
            end
        end
    end

    local fwd = BoolToVal(self.sv_controls[3]) - BoolToVal(self.sv_controls[4])
    local right = BoolToVal(self.sv_controls[1]) - BoolToVal(self.sv_controls[2])
    self.fwd = sm.util.lerp(self.fwd, fwd, dt * data.acceleration)
    sm.physics.applyImpulse( shape, (fwdDir * mass * data.speed * self.fwd) * (wheelHits / #data.wheelOffsets), true )

    local angularVel = body.angularVelocity
    local dir = round(shape.at:dot(vec3_up))
    if dir == 0 then dir = 1 end
    sm.physics.applyTorque( body, ((rightDir * data.turnSpeed * right) + (rightDir * angularVel * -data.turnFriction)) * mass * dir, true )
end

function Car:sv_syncControls( controls, caller )
    local char = self.interactable:getSeatCharacter()
    if not char and caller or caller ~= char:getPlayer() then return end

    self.sv_controls = controls
    self.network:sendToClients("cl_syncControls", controls)
end

--[[
function Car:sv_toggleAi()
    self.manual = not self.manual
    self:sv_syncControls( { false, false, false, false } )
end
]]



function Car:client_onCreate()
    self.cl_controls = { false, false, false, false }
    self.seated = false
    self.cameraMode = 1
    self.zoom = 1
    self.selectedWheel = 1

    self.cl_data = nil
    self.effects = {}
end

function Car:client_onDestroy()
    if self.seated then
        sm.camera.setCameraState(0)
    end
end

function Car:client_onClientDataUpdate( data )
    if self.cl_data == nil or data.wheelCount ~= self.cl_data.wheelCount then
        if self.gui then
            self.gui:close()
            self.gui:destroy()
        end

        self:cl_ui_create( data.wheelCount )
        if self.cl_data ~= nil then
            self.gui:open()
        end
    end

    self.cl_data = data
    self.gui:setText("editbox_height",          string.format("%.3f", tostring(data.hoverHeight)))
    self.gui:setText("editbox_speed",           string.format("%.3f", tostring(data.speed)))
    self.gui:setText("editbox_acceleration",    string.format("%.3f", tostring(data.acceleration)))
    self.gui:setText("editbox_friction",        string.format("%.3f", tostring(data.friction)))
    self.gui:setText("editbox_turnspeed",       string.format("%.3f", tostring(data.turnSpeed)))
    self.gui:setText("editbox_turnfriction",    string.format("%.3f", tostring(data.turnFriction)))
    self.gui:setText("editbox_camspeed",        string.format("%.3f", tostring(data.cameraFollowSpeed)))
    self.gui:setText("editbox_wheels",          tostring(data.wheelCount))
    self:cl_ui_updateOffsets()

    for k, effectData in pairs(self.effects) do
        effectData.effect:destroy()
    end

    self.effects = {}
    for k, offset in pairs(data.wheelOffsets) do
        local effect = sm.effect.createEffect("Thruster - Level 5", self.interactable)
        effect:setOffsetPosition( offset )
        effect:setOffsetRotation( self.defaultEffectRot )
        effect:start()

        self.effects[#self.effects+1] = { effect = effect, rot = self.defaultEffectRot }
    end
end

function Car:client_canInteract()
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), "Enter vehicle")
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Tinker", true), "Configure settings")

    return self.interactable:getSeatCharacter() == nil
end

function Car:client_onInteract( char, state )
    if not state then return end
    self.interactable:setSeatCharacter( char )
    self.seated = true

    if self.cameraMode ~= 1 then
        sm.camera.setCameraState(3)
        sm.camera.setFov(sm.camera.getDefaultFov())
    end
end

function Car:client_onTinker( char, state )
    if not state then return end

    self.gui:open()
end

function Car:client_onAction( action, state )
    if self.cl_controls[action] ~= nil then
        self.cl_controls[action] = state
        self.network:sendToServer("sv_syncControls", self.cl_controls)
    end

    if state then
        local customCam = isAnyOf(self.cameraMode, {2,3})

        if action == 15 then --Use
            self:cl_unSeat()
        elseif action == 18 then --Right click
            --self.network:sendToServer("sv_toggleAi")
        elseif action == 19 then --Left click
            self.cameraMode = self.cameraMode < 3 and self.cameraMode + 1 or 1
            if self.cameraMode == 1 then
                sm.camera.setCameraState(0)
            elseif sm.camera.getCameraState() ~= 3 then
                sm.camera.setCameraState(3)
                sm.camera.setFov(sm.camera.getDefaultFov())
            end

            sm.gui.displayAlertText(self.cameraModes[self.cameraMode], 2.5)
        elseif action == 20 and self.zoom ~= 1 and customCam then
            self.zoom = sm.util.clamp(self.zoom - 1, 1, 10)
            --if self.zoom == 0 then sm.gui.startFadeToBlack( 0.1, 0.5 ) end
            sm.gui.displayAlertText(string.format("Zoom Level:#df7f00 %s", self.zoom), 2.5)
        elseif action == 21 and self.zoom ~= 10 and customCam then
            self.zoom = sm.util.clamp(self.zoom + 1, 1, 10)
            --if self.zoom == 1 then sm.gui.startFadeToBlack( 0.1, 0.5 ) end
            sm.gui.displayAlertText(string.format("Zoom Level:#df7f00 %s", self.zoom), 2.5)
        end
    end

    return not isAnyOf( action, { 20, 21, 15 } )
end

function Car:cl_syncControls( controls )
    self.cl_controls = controls
end

function Car:client_onUpdate( dt )
    if not self.cl_data then return end

    local shape = self.shape
    local dir_forward = shape.up
    local dir_left = shape.right
    local dir_up = shape.at

    local fwd = BoolToVal(self.cl_controls[3]) - BoolToVal(self.cl_controls[4])
    local right = BoolToVal(self.cl_controls[1]) - BoolToVal(self.cl_controls[2])

    local rearWheels = #self.effects * 0.5
    local fwdDir = dir_forward * -fwd
    for k, data in pairs(self.effects) do
        local downwardRot = shape:transformRotation(
            sm.vec3.getRotation(
                vec3_up,
                vec3_down + fwdDir + (dir_left * (k > rearWheels and right or -right))
            )
        )

        data.rot = sm.quat.slerp( data.rot, downwardRot, dt * 10 )
        data.effect:setOffsetRotation( data.rot )
    end

    local char = self.interactable:getSeatCharacter()
    if char == sm.localPlayer.getPlayer().character then
        --sm.gui.displayAlertText(string.format("%.0f km/h",tostring(self.shape.velocity:length()*3.6)), 1)

        if self.cameraMode ~= 1 then
            local worldPos = shape.worldPosition
            --1.875 7.5
            local offset = (fwd == -1 and dir_forward or -dir_forward) * (3.75 * self.zoom) + dir_up * 4
            local newPos = worldPos + offset

            local lerp = dt * self.cl_data.cameraFollowSpeed
            if self.cameraMode == 3 then
                local hit, result = sm.physics.raycast(worldPos, newPos, shape.body)
                if hit then newPos = result.pointWorld + dir_forward * 0.25 end

                sm.camera.setPosition(hit and newPos or sm.vec3.lerp( sm.camera.getPosition(), newPos, lerp ))
                sm.camera.setRotation(shape.worldRotation * camRotAdjust * sm.quat.angleAxis(-math.rad(15), vec3_x))
            elseif self.cameraMode == 2 then
                local hit, result = sm.physics.raycast(worldPos, newPos, shape.body)
                if hit then newPos = result.pointWorld + dir_forward * 0.25 end

                sm.camera.setPosition(hit and newPos or sm.vec3.lerp(sm.camera.getPosition(), newPos, lerp))
                sm.camera.setDirection(
                    sm.vec3.lerp(
                        sm.camera.getDirection(),
                        (worldPos - newPos + dir_up * 2):normalize(),
                        lerp
                    )
                )
            --[[else
                local standing, seated = sm.camera.getCameraPullback()
                local defaultDir = sm.camera.getDefaultRotation() * sm.vec3.new(0,1,0)

                newPos = sm.camera.getDefaultPosition() - defaultDir * seated
                local hit, result = sm.physics.raycast(pos, newPos, shape.body)
                if hit then newPos = result.pointWorld + defaultDir * 0.5 end

                --lerp = lerp * 10
                sm.camera.setPosition(hit and newPos or sm.vec3.lerp(sm.camera.getPosition(), newPos, lerp))
                sm.camera.setDirection(
                    sm.vec3.lerp(
                        sm.camera.getDirection(),
                        defaultDir,
                        lerp
                    )
                )

                --[[if (sm.camera.getPosition() - sm.camera.getDefaultPosition()):length2() <= seated then
                    sm.camera.setCameraState(0)
                end]]
            end

            local lag = shape.velocity * 0.2 --newPos - sm.camera.getPosition()
            sm.camera.setFov(sm.util.lerp(sm.camera.getFov(), sm.camera.getDefaultFov() + 2.5 * lag:length(), lerp) )
        else
            sm.camera.setPosition( sm.camera.getPosition() )
            sm.camera.setDirection( sm.camera.getDirection() )
        end
    elseif sm.camera.getCameraState() == 0 then
        sm.camera.setPosition(sm.camera.getPosition())
        sm.camera.setDirection(sm.camera.getDirection())
    end
end

function Car:cl_unSeat()
    self.interactable:setSeatCharacter( sm.localPlayer.getPlayer().character )
    sm.camera.setCameraState(0)

    self.cl_controls = { false, false, false, false }
    self.seated = false
    self.network:sendToServer("sv_syncControls", self.cl_controls)
end



function Car:cl_ui_create( wheelCount )
    self.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/car.layout")
    self.gui:setTextAcceptedCallback( "editbox_height",         "cl_ui_height" )
    self.gui:setTextAcceptedCallback( "editbox_speed",          "cl_ui_speed" )
    self.gui:setTextAcceptedCallback( "editbox_acceleration",   "cl_ui_acceleration" )
    self.gui:setTextAcceptedCallback( "editbox_friction",       "cl_ui_friction" )
    self.gui:setTextAcceptedCallback( "editbox_turnspeed",      "cl_ui_turnspeed" )
    self.gui:setTextAcceptedCallback( "editbox_turnfriction",   "cl_ui_turnfriction" )
    self.gui:setTextAcceptedCallback( "editbox_camspeed",       "cl_ui_camspeed" )

    self.gui:setTextAcceptedCallback( "editbox_wheels",         "cl_ui_wheelCount" )
    self.gui:setTextAcceptedCallback( "editbox_offsetx",        "cl_ui_offset" )
    self.gui:setTextAcceptedCallback( "editbox_offsety",        "cl_ui_offset" )
    self.gui:setTextAcceptedCallback( "editbox_offsetz",        "cl_ui_offset" )

    self.gui:setOnCloseCallback( "cl_ui_onClose" )

    local options = {}
    for i = 1, wheelCount do
        options[#options+1] = tostring(i)
    end
    self.gui:createDropDown( "dropdown_wheels", "cl_ui_wheelSelect", options )
end

function Car:cl_ui_height(widget, text)
    local valid, value = self:verifyInput( text, widget, self.cl_data.hoverHeight )
    if valid then
        self.cl_data.hoverHeight = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function Car:cl_ui_speed(widget, text)
    local valid, value = self:verifyInput( text, widget, self.cl_data.speed )
    if valid then
        self.cl_data.speed = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function Car:cl_ui_acceleration(widget, text)
    local valid, value = self:verifyInput( text, widget, self.cl_data.acceleration )
    if valid then
        self.cl_data.acceleration = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function Car:cl_ui_friction(widget, text)
    local valid, value = self:verifyInput( text, widget, self.cl_data.friction )
    if valid then
        self.cl_data.friction = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function Car:cl_ui_turnspeed(widget, text)
    local valid, value = self:verifyInput( text, widget, self.cl_data.turnSpeed )
    if valid then
        self.cl_data.turnSpeed = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function Car:cl_ui_turnfriction(widget, text)
    local valid, value = self:verifyInput( text, widget, self.cl_data.turnFriction )
    if valid then
        self.cl_data.turnFriction = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function Car:cl_ui_camspeed(widget, text)
    local valid, value = self:verifyInput( text, widget, self.cl_data.cameraFollowSpeed )
    if valid then
        self.cl_data.cameraFollowSpeed = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function Car:cl_ui_wheelCount( widget, text )
    local valid, value = self:verifyInput( text, widget, self.cl_data.wheelCount )
    if valid then
        value = round(value)
        local sent = shallowcopy(self.cl_data)
        sent.wheelCount = value
        local newOffsets = {}
        for i = 1, value do
            newOffsets[#newOffsets+1] = self.cl_data.wheelOffsets[i] or sm.vec3.zero()
        end

        sent.wheelOffsets = newOffsets
        self.selectedWheel = 1
        self.network:sendToServer("sv_updateSettings", sent)
    end
end

function Car:cl_ui_offset( widget, text )
    local axis = widget:sub(15,15)
    local valid, value = self:verifyInput( text, widget, self.cl_data.wheelOffsets[self.selectedWheel][axis] )

    if valid then
        self.cl_data.wheelOffsets[self.selectedWheel][axis] = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function Car:cl_ui_wheelSelect( option )
    self.selectedWheel = tonumber(option)
    self:cl_ui_updateOffsets()
end

function Car:cl_ui_updateOffsets()
    local offset = self.cl_data.wheelOffsets[self.selectedWheel]
    self.gui:setText("editbox_offsetx", tostring(offset.x))
    self.gui:setText("editbox_offsety", tostring(offset.y))
    self.gui:setText("editbox_offsetz", tostring(offset.z))
end

function Car:cl_ui_onClose()
    self.network:sendToServer("sv_updateSettings", self.cl_data)
end



function Car:verifyInput( input, widget, default )
    local num = tonumber(input)
	if num == nil then
		sm.gui.displayAlertText("#ff0000Please only enter numbers!", 2.5)
		sm.audio.play("RaftShark")
		self.gui:setText( widget, tostring(default) )

		return false
	end

    return true, num
end

function Car:cl_visualize( node )
    ---@type Vec3
    local pos = node.position
    for i = 1, 10 do
        sm.particle.createParticle("paint_smoke", pos + sm.vec3.new(0,0,i))
    end
end

function Car:getCreationMass( body )
    local mass = 0
    for k, v in pairs(body:getCreationBodies()) do
        mass = mass + v.mass
    end

    self.sv_mass = mass
end

function Car:isLiquid( trigger )
    if trigger and sm.exists(trigger) then
        local userdata = trigger:getUserData()
        if userdata then
            for k, v in pairs(userdata) do
                if isAnyOf(k, {"water", "chemical", "oil"}) and v == true then
                    return true
                end
            end
        end
    end

    return false
end

function BoolToVal( bool )
    return bool and 1 or 0
end

--[[
function GetRotation( forward, up )
    local vector = sm.vec3.normalize( forward )
    local vector2 = sm.vec3.normalize( sm.vec3.cross( up, vector ) )
    local vector3 = sm.vec3.cross( vector, vector2 )
    local m00 = vector2.x
    local m01 = vector2.y
    local m02 = vector2.z
    local m10 = vector3.x
    local m11 = vector3.y
    local m12 = vector3.z
    local m20 = vector.x
    local m21 = vector.y
    local m22 = vector.z
    local num8 = (m00 + m11) + m22
    local quaternion = sm.quat.identity()
    if num8 > 0 then
        local num = math.sqrt(num8 + 1)
        quaternion.w = num * 0.5
        num = 0.5 / num
        quaternion.x = (m12 - m21) * num
        quaternion.y = (m20 - m02) * num
        quaternion.z = (m01 - m10) * num
        return quaternion
    end
    if (m00 >= m11) and (m00 >= m22) then
        local num7 = math.sqrt(((1 + m00) - m11) - m22)
        local num4 = 0.5 / num7
        quaternion.x = 0.5 * num7
        quaternion.y = (m01 + m10) * num4
        quaternion.z = (m02 + m20) * num4
        quaternion.w = (m12 - m21) * num4
        return quaternion
    end
    if m11 > m22 then
        local num6 = math.sqrt(((1 + m11) - m00) - m22)
        local num3 = 0.5 / num6
        quaternion.x = (m10+ m01) * num3
        quaternion.y = 0.5 * num6
        quaternion.z = (m21 + m12) * num3
        quaternion.w = (m20 - m02) * num3
        return quaternion
    end
    local num5 = math.sqrt(((1 + m22) - m00) - m11)
    local num2 = 0.5 / num5
    quaternion.x = (m20 + m02) * num2
    quaternion.y = (m21 + m12) * num2
    quaternion.z = 0.5 * num5;
    quaternion.w = (m01 - m10) * num2
    return quaternion
end

function QuatAngle(q1)
    local angle = 2 * math.acos(q1.w)
    local s = math.sqrt(1-q1.w*q1.w)
    local x, y, z

    if (s < 0.001) then
        x = q1.x
        y = q1.y
        z = q1.z
    else
        x = q1.x / s
        y = q1.y / s
        z = q1.z / s
    end

    return {x, y , z}
end


function Angle(from, to)
    local function sqrMagnitude( vec3 )
        return vec3.x * vec3.x + vec3.y * vec3.y + vec3.z * vec3.z
    end

    local num = math.sqrt(sqrMagnitude(from) * sqrMagnitude(to))
    if (num < 1E-15) then
        return 0
    end

    local num2 = sm.util.clamp(from:dot(to) / num, -1, 1)
    return math.acos(num2) * 57.29578
end

function Sign( number )
    return number > 0 and 1 or -1
end

function SignedAngle(from, to, axis)
    local num = Angle(from, to);
    local num2 = from.y * to.z - from.z * to.y;
    local num3 = from.z * to.x - from.x * to.z;
    local num4 = from.x * to.y - from.y * to.x;
    local num5 = Sign(axis.x * num2 + axis.y * num3 + axis.z * num4);
    return num * num5;
end

    local fwd = 0
    local right = 0
    if self.manual then
        fwd = BoolToVal(self.sv_controls[3]) - BoolToVal(self.sv_controls[4])
        right = BoolToVal(self.sv_controls[1]) - BoolToVal(self.sv_controls[2])
    else
        local worldPos = shape.worldPosition
        local worldPos_64 = worldPos / 64
        local waypoints = sm.cell.getNodesByTag( math.floor(worldPos_64.x), math.floor(worldPos_64.y), "AREATRIGGER" )
        local closestWaypoint = waypoints[1]
        if closestWaypoint then
            if #waypoints > 1 then
                for k, waypoint in pairs(waypoints) do
                    local distance = (closestWaypoint.position - worldPos):length2()
                    if distance > 0.1 and (waypoint.position - worldPos):length2() < distance then
                        closestWaypoint = waypoint
                    end
                end
            end
            self.network:sendToClients("cl_visualize", closestWaypoint)

            local dir = closestWaypoint.position - worldPos
            local distanceToPoint = dir:length()
            if distanceToPoint > self.reachedTargetDistance then
                local dirToPoint = dir:normalize()
                local dot = fwdDir:dot(dirToPoint)
                fwd = dot > 0 and (distanceToPoint < self.stoppingDistance and vel:length() > self.stoppingSpeed and -0.5 or 1) or (distanceToPoint > self.reverseDistance and 1 or -1)

                local angleToDir = SignedAngle(fwdDir, dirToPoint, vec3_up)
                right = angleToDir > 0 and 1 or -1
            else
                fwd = vel:length() > 5 and -0.5 or 0
                right = 0
            end

            if self.prevFwd ~= fwd or self.prevRight ~= right then
                self.prevFwd = fwd
                self.prevRight = right
                self:sv_syncControls( { right > 0, right < 0, fwd > 0, fwd < 0 } )
            end
        end
    end
]]