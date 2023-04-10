---@class Label : ShapeClass
Label = class()

function Label:server_onCreate()
    local data = self.storage:load()
    if data then
        self.network:sendToClients("cl_setLabel", data.label)
    end
end

function Label:sv_setLabel(label)
    self.storage:save({ label = label })
    self.network:sendToClients("cl_setLabel", label)
end



function Label:client_onCreate()
    self.label = ""

    self.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/label.layout")
    self.gui:setText("title", "Enter text")
    self.gui:setTextChangedCallback("name", "cl_labelEntered")
    self.gui:setButtonCallback("cancel", "cl_button")
    self.gui:setButtonCallback("ok", "cl_button")
end

function Label:cl_setLabel(label)
    self.label = label
end

function Label:client_onInteract(char, state)
    if not state then return end

    self.gui:setText("name", self.label)
    self.gui:open()
end

function Label:cl_labelEntered(widget, text)
    self.newLabel = text
end

function Label:cl_button(button)
    if button == "ok" then
        self.network:sendToServer("sv_setLabel", self.newLabel)
    end

    self.gui:close()
end

function Label:client_canInteract()
    sm.gui.setInteractionText("<p textShadow='false' bg='gui_keybinds_bg' color='#ffffff' spacing='9'>"..self.label.."</p>")
    return true
end