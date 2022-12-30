---@class CamParent : ShapeClass
CamParent = class()
CamParent.maxParentCount = -1
CamParent.maxChildCount = -1
CamParent.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.seated
CamParent.connectionOutput = sm.interactable.connectionType.logic
CamParent.colorNormal = sm.color.new( "#a0fcff" )
CamParent.colorHighlight = sm.color.new( "#a1fcff" )

dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"

local inputColours = {
    activation = { sm.color.new( "#df7f00" ), sm.color.new( "#df7f01" ) },
    indexIncrease = sm.color.new( "#eeeeee" )
}
local camChildUuid = sm.uuid.new("28e4e591-1a4f-4f0b-a2c4-416212ff94f3")

function CamParent:server_onCreate()
    self.sv = {}
    self.sv.canChangeIndexTimer = Timer()
    self.sv.canChangeIndexTimer:start( 10 )
end

function CamParent:server_onFixedUpdate()
    self.sv.canChangeIndexTimer:tick()

    --local activationParents = 0
    for k, int in pairs(self.interactable:getParents()) do
        if int.active then
            local colour = int.shape.color

            --if isAnyOf(colour, inputColours.activation) and not int:hasSeat() then
            --    activationParents = activationParents + 1
            --else
            if colour == inputColours.indexIncrease and self.sv.canChangeIndexTimer:done() then
                self.sv.canChangeIndexTimer:reset()
                self.network:sendToClients("cl_changeCamIndex")
            end
        end
    end

    --[[local state = activationParents > 0
    if state ~= self.interactable.active then
        self.interactable.active = state

        local char = self:getSeatedCharacter()
        if char then
            self.network:sendToClients( "cl_onClientCamChanged", { state = state, char = char })
        end
    end]]
end

function CamParent:sv_onClientCamChanged( args )
    self.network:sendToClients( "cl_onClientCamChanged", args)
end



function CamParent:client_onCreate()
    self.cl = {}
    self.cl.camIndex = 0
    self.cl.seatedChar = nil
end

function CamParent:client_getAvailableParentConnectionCount( connectionType )
    if bit.band( connectionType, sm.interactable.connectionType.seated ) ~= 0 then
        return 1 - #self.interactable:getParents(sm.interactable.connectionType.seated)
    end

    return 1
end

function CamParent:client_onUpdate( dt )
    local seatChar, seat = self:getSeatedCharacter()
    local noSeatChar = seatChar == nil
    local char = sm.localPlayer.getPlayer().character

    if noSeatChar then
        if char == self.cl.seatedChar then
            sm.camera.setCameraState( 0 )
        end

        self.cl.seatedChar = nil
    end

    if noSeatChar or char ~= seatChar then return end

    local children = self:getCamChildren()
    local camHost = children[self.cl.camIndex] or self.shape

    local lerpTime = dt * 10
    local newPos = camHost.worldPosition - seat.up * 5
    sm.camera.setPosition( sm.vec3.lerp( sm.camera.getPosition(), newPos, lerpTime ) )
    sm.camera.setDirection( sm.vec3.lerp( sm.camera.getDirection(), camHost.worldPosition - newPos, lerpTime ) )
end

function CamParent:client_canInteract()
    local int = sm.localPlayer.getPlayer().character:getLockingInteractable()
    return int  ~= nil and int:hasSeat()
end

function CamParent:client_onInteract( char, state )
    if not state then return end

    local newState = self.cl.seatedChar == nil
    self.network:sendToServer("sv_onClientCamChanged", { state = newState, char = newState and char or nil })

    if newState then
        sm.camera.setCameraState( 3 )
        sm.camera.setFov(sm.camera.getDefaultFov())
    else
        sm.camera.setCameraState( 0 )
    end
end

function CamParent:cl_changeCamIndex()
    local children = self:getCamChildren()
    self.cl.camIndex = self.cl.camIndex < #children and self.cl.camIndex + 1 or 0
end

function CamParent:cl_onClientCamChanged( args )
    self.cl.seatedChar = args.char
end



function CamParent:getCamChildren()
    local camChildren = {}
    for k, int in pairs(self.interactable:getChildren()) do
        if int.shape.uuid == camChildUuid then
            camChildren[#camChildren+1] = int.shape
        end
    end

    return camChildren
end

function CamParent:getSeatedCharacter()
    for k, int in pairs(self.interactable:getParents()) do
        if int:hasSeat() then
            return int:getSeatCharacter(), int.shape
        end
    end
end