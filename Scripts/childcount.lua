---@class ChildCount : ShapeClass
ChildCount = class()
ChildCount.maxChildCount = -1
ChildCount.maxParentCount = 1
ChildCount.connectionInput = sm.interactable.connectionType.logic
ChildCount.connectionOutput = sm.interactable.connectionType.logic
ChildCount.colorNormal = sm.color.new("#00ff33")
ChildCount.colorHighlight = sm.color.new("#00ff00")

function ChildCount:client_onCreate()
    self.cl = {
        children = {},
        guis = {}
    }
end

function ChildCount:server_onFixedUpdate( dt )
    local parent = self.interactable:getSingleParent()
    local active = parent and parent.active
    if self.interactable.active ~= active then
        self.interactable.active = active
        self.interactable.power = active and 1 or 0
        self.network:sendToClients("cl_updateUV", active)
    end
end

function ChildCount:cl_createGUI( children )
    self.cl.children = children
    for v, k in pairs(self.cl.guis) do
        k:close()
        k = nil
    end

    for i = 1, #children do
        local gui = sm.gui.createNameTagGui()
        gui:setRequireLineOfSight( false )
	    gui:setMaxRenderDistance( 1000 )
	    gui:setText("Text", tostring(i))
        gui:open()

        self.cl.guis[i] = gui
    end
end

function ChildCount:cl_updateUV( active )
    self.interactable:setUvFrameIndex( active and 6 or 0 )
end

function ChildCount:client_onUpdate( dt )
    local children = self.interactable:getChildren()
    if #children ~= #self.cl.children then
        self:cl_createGUI( children )
    end

    for v, gui in pairs(self.cl.guis) do
        local currentChild = self.cl.children[v]
        if sm.exists(currentChild) then
            gui:setWorldPosition( currentChild.shape.worldPosition )

            if sm.localPlayer.getActiveItem() == tool_connect then
                gui:open()
            else
                gui:close()
            end
        end
    end
end