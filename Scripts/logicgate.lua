---@class LGate : ShapeClass

LGate = class()
LGate.maxChildCount = -1
LGate.maxParentCount = -1
LGate.connectionInput = sm.interactable.connectionType.logic
LGate.connectionOutput = sm.interactable.connectionType.logic
LGate.colorNormal = sm.color.new("#00ff33")
LGate.colorHighlight = sm.color.new("#00ff00")
LGate.poseWeightCount = 1

LGate.modes = {
    And =       { update = "sv_mode_And",     uvs = { off = 0, on = 6 } },
    Or =        { update = "sv_mode_Or",      uvs = { off = 1, on = 7 } },
    Xor =       { update = "sv_mode_Xor",     uvs = { off = 2, on = 8 } },
    Nand =      { update = "sv_mode_Nand",    uvs = { off = 3, on = 9 } },
    Nor =       { update = "sv_mode_Nor",     uvs = { off = 4, on = 10 } },
    Xnor =      { update = "sv_mode_Xnor",    uvs = { off = 5, on = 11 } },
}

function LGate:server_onCreate()
    self.sv = {}
    self.sv.data = self.storage:load()
    if self.sv.data == nil then
        self.sv.data = {}
        self.sv.data.mode = self.modes.And
    end

    self:sv_save()
end

function LGate:sv_save()
    self.storage:save( self.sv.data )
    self.network:setClientData( self.sv.data )
end

function LGate:sv_changeMode( mode )
    self.sv.data.mode = self.modes[mode]
    self:sv_save()
end

function LGate:server_onFixedUpdate()
    local parents = self.interactable:getParents()
    local active = parents == 0 and false or self[self.sv.data.mode.update](self, parents)

    if active ~= self.interactable.active then
        self.interactable.active = active
        self.network:sendToClients("cl_updateModel")
    end
end

function LGate:sv_mode_And( parents )
    local active = #parents > 0
    for k, int in pairs(parents) do
        if not int.active then
            active = false
            break
        end
    end

    return active
end

function LGate:sv_mode_Or( parents )
    local active = false
    for k, int in pairs(parents) do
        if int.active then
            active = true
            break
        end
    end

    return active
end

function LGate:sv_mode_Xor( parents )
    local active = 0
    for k, int in pairs(parents) do
        if int.active then
            active = active + 1
        end
    end

    return active == 1
end

function LGate:sv_mode_Nand( parents )
    local active = false
    for k, int in pairs(parents) do
        if not int.active then
            active = true
            break
        end
    end

    return active
end

function LGate:sv_mode_Nor( parents )
    local active = #parents > 0
    for k, int in pairs(parents) do
        if int.active then
            active = false
            break
        end
    end

    return active
end

function LGate:sv_mode_Xnor( parents )
    local active = 0
    for k, int in pairs(parents) do
        if int.active then
            active = active + 1
        end
    end

    return active % 2 == 0
end



function LGate:client_onCreate()
    self.cl = {}
    self.cl.mode = {}
    self.cl.selectedMode = ""

    self.cl.gui = sm.gui.createGuiFromLayout( "$GAME_DATA/Gui/Layouts/Interactable/Interactable_LogicGate.layout" )
    self.cl.gui:setButtonCallback( "And", "cl_button" )
    self.cl.gui:setButtonCallback( "Or", "cl_button" )
    self.cl.gui:setButtonCallback( "Xor", "cl_button" )
    self.cl.gui:setButtonCallback( "Nand", "cl_button" )
    self.cl.gui:setButtonCallback( "Nor", "cl_button" )
    self.cl.gui:setButtonCallback( "Xnor", "cl_button" )
end

function LGate:client_onInteract( char, state )
    if not state then return end

    self.cl.gui:open()
end

function LGate:cl_button( button )
    self.network:sendToServer("sv_changeMode", button)
end

function LGate:client_onClientDataUpdate( data, channel )
    self.cl.mode = data.mode
    self:cl_updateModel()
end

function LGate:cl_updateModel()
    local active = self.interactable.active
    self.interactable:setUvFrameIndex( active and self.cl.mode.uvs.on or self.cl.mode.uvs.off )
    self.interactable:setPoseWeight( 0, active and 1 or 0 )

    self.cl.gui:setButtonState( self.cl.selectedMode, false )
    self.cl.selectedMode = self.cl.mode.update:sub(9, 12)
    self.cl.gui:setButtonState( self.cl.selectedMode, true )
end