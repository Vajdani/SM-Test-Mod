---@class Binder : ShapeClass
Binder = class()
Binder.maxParentCount = 0
Binder.maxChildCount = -1
Binder.connectionInput = sm.interactable.connectionType.none
Binder.connectionOutput = sm.interactable.connectionType.logic
Binder.colorNormal = sm.color.new( 0xcb0a00ff )
Binder.colorHighlight = sm.color.new( 0xee0a00ff )

function Binder:server_onCreate()
    --sm.customEventSystem:registerEvent("binder_event", true, { sus = false })
end

function Binder:sv_delete()
    --sm.customEventSystem:deleteEvent("binder_event")
end

function Binder:sv_trigger()
    --sm.customEventSystem:invokeEvent("binder_event")
end

function Binder:client_onInteract(char, state)
    if not state then return end

    if char:isCrouching() then
        self.network:sendToServer("sv_delete")
    else
        self.network:sendToServer("sv_trigger")
    end
end

function Binder:sv_change()
    local data = sm.customEventSystem:getEventData("binder_event")
    data.sus = not data.sus

    sm.customEventSystem:setEventData("binder_event", data)
end

function Binder:client_onTinker(char, state)
    if not state then return end

    --self.network:sendToServer("sv_change")
end



local quat_zero = sm.quat.identity()
function Binder:client_onCreate()
    local layout = {
        Background = {
            skin = "TransparentBG",
            transform = { pos_x = 0, pos_y = 0, scale_x = 500, scale_y = 500, rotation = quat_zero },
            children = {
                Button = {
                    skin = "Orange",
                    widgetType = "button",
                    transform = { pos_x = 0, pos_y = 95, scale_x = 400, scale_y = 270, rotation = quat_zero },
                    parent = "Background"
                },
                StateDisplay = {
                    skin = "Red",
                    transform = { pos_x = 0, pos_y = -150, scale_x = 400, scale_y = 150, rotation = quat_zero },
                    parent = "Background"
                }
            }
        }
    }
    self.gui = sm.worldgui.createGui(layout, self.shape.worldPosition, self.shape.worldRotation)
    self.gui:bindButtonPressCallback("Button", self.interactable, "cl_button")
    self.gui:open()
end

function Binder:cl_button(args)
	if args.state then
		sm.audio.play("Button on")
        self.network:sendToServer("sv_updateState")
	else
		sm.audio.play("Button off")
	end
end

function Binder:client_onDestroy()
    self.gui:destroy()
end

local rot = sm.quat.angleAxis(math.rad(90), sm.vec3.new(0,1,0)) * sm.quat.angleAxis(math.rad(90), sm.vec3.new(1,0,0))
local col_green = sm.color.new(0,1,0)
local col_red = sm.color.new(1,0,0)
function Binder:client_onUpdate(dt)
    --self.gui:update(self.shape:getInterpolatedWorldPosition() + self.shape.velocity * dt + self.shape.at * 0.4, self.shape.worldRotation * rot, 0.2)

    self.gui:setPosition(self.shape:getInterpolatedWorldPosition() + self.shape.velocity * dt + self.shape.at * 0.4)
    self.gui:setRotation(self.shape.worldRotation * rot)
    self.gui:setScale(0.2)

    local light = self.gui:getWidget("StateDisplay") --[[@as WorldGuiWidget]]
    light.effect:setParameter("color", self.interactable.active and col_green or col_red)
end

function Binder:sv_updateState()
    self.interactable.active = not self.interactable.active
end



---@class Receiver : ShapeClass
Receiver = class()

function Receiver:server_onCreate()
    --sm.customEventSystem:subscribeToEvent(self.interactable, "sv_trigger", "binder_event")
end

function Receiver:sv_trigger(data)
    print("Receiver", self.shape.id, "received event, data:", data)
end

function Receiver:client_onCreate()
    local layout = {
        Background = {
            skin = "TransparentBG",
            transform = { pos_x = 0, pos_y = 0, scale_x = 400, scale_y = 400, rotation = quat_zero },
            children = {
                Button = {
                    skin = "Red",
                    widgetType = "button",
                    transform = { pos_x = 0, pos_y = -75, scale_x = 300, scale_y = 200, rotation = quat_zero },
                    parent = "Background"
                },
                Slider = {
                    skin = "Orange",
                    widgetType = "slider",
                    widgetData = {
                        maxRange = 300,
                        isFlipped = false
                    },
                    transform = { pos_x = 0, pos_y = 125, scale_x = 100, scale_y = 100, rotation = quat_zero },
                    parent = "Background"
                }
            }
        }
    }
    self.gui = sm.worldgui.createGui(layout, self.shape.worldPosition, self.shape.worldRotation)
    self.gui:bindButtonPressCallback("Button", self.interactable, "cl_button")
    self.gui:open()

    self.baseIntensity = 2.5
    self.spotlight = sm.effect.createEffect("HeadLight", self.interactable)
    self.spotlight:setParameter("maxIntensity", self.baseIntensity)
    self.spotlight:setOffsetPosition(sm.vec3.new(0,0.1,0))
    self.spotlight:setOffsetRotation(sm.quat.angleAxis(math.rad(90), sm.vec3.new(0,1,0)))
end

function Receiver:cl_button(args)
    if args.state then
		sm.audio.play("Button on")
        self.network:sendToServer("sv_updateState")
	else
		sm.audio.play("Button off")
	end
end

function Receiver:sv_updateState()
    self.interactable.active = not self.interactable.active
end

function Receiver:client_onDestroy()
    self.gui:destroy()
end

local rot2 = sm.quat.angleAxis(math.rad(-90), sm.vec3.new(0,1,0)) * sm.quat.angleAxis(math.rad(90), sm.vec3.new(1,0,0))
function Receiver:client_onUpdate(dt)
    --self.gui:update(self.shape:getInterpolatedWorldPosition() + self.shape.velocity * dt + self.shape.at * 0.375, self.shape.worldRotation * rot2, 0.5)
    self.gui:setPosition(self.shape:getInterpolatedWorldPosition() + self.shape.velocity * dt + self.shape.at * 0.375)
    self.gui:setRotation(self.shape.worldRotation * rot2)
    self.gui:setScale(0.5)

    self.dt = (self.dt or 0) + dt * 100
    self.gui:setWidgetRotation("Slider", sm.quat.angleAxis(math.rad(0), sm.vec3.new(0,1,0)))

    self.spotlight:setParameter("intensity", self.baseIntensity * self.gui:getSliderFraction("Slider"))

    local playing = self.spotlight:isPlaying()
    local shouldPlay = self.interactable.active
    if playing and not shouldPlay then
        self.spotlight:stop()
    elseif not playing and shouldPlay then
        self.spotlight:start()
    end
end