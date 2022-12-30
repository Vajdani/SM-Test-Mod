dofile("$SURVIVAL_DATA/Scripts/game/survival_units.lua")

BotDetector = class()
BotDetector.maxChildCount = 0
BotDetector.maxParentCount = 1
BotDetector.connectionInput = sm.interactable.connectionType.logic
BotDetector.connectionOutput = sm.interactable.connectionType.logic
BotDetector.colorNormal = sm.color.new("#00ff33")
BotDetector.colorHighlight = sm.color.new("#00ff00")

local charIdToName = {
    [tostring(unit_woc)] = "Woc",
    [tostring(unit_tapebot)] = "Tapebot",
    [tostring(unit_tapebot_red)] = "Red Tapebot",
    [tostring(unit_tapebot_taped_1)] = "Tapebot",
    [tostring(unit_tapebot_taped_2)] = "Tapebot",
    [tostring(unit_tapebot_taped_3)] = "Tapebot",
    [tostring(unit_totebot_green)] = "Green Totebot",
    [tostring(unit_haybot)] = "Haybot",
    [tostring(unit_farmbot)] = "Farmbot",
    [tostring(unit_worm)] = "Glowbug"
}

function BotDetector:server_onCreate()
    self.sv = {
        units = {}
    }
end

function BotDetector:client_onCreate()
    self.cl = {
        chars = {},
        guis = {}
    }
end

function BotDetector:server_onFixedUpdate( dt )
    local units = sm.unit.getAllUnits()
    if #units ~= #self.sv.units then
        self.sv.units = units

        local characters = {}
        for v, k in pairs(units) do
            characters[#characters+1] = k:getCharacter()
        end
        self.network:sendToClients("cl_createGUI", characters)
    end

    local parent = self.interactable:getSingleParent()
    local active = parent and parent.active
    if self.interactable.active ~= active then
        self.interactable.active = active
        self.interactable.power = active and 1 or 0
        self.network:sendToClients("cl_updateUV", active)
    end
end

function BotDetector:cl_createGUI( chars )
    self.cl.chars = chars
    for v, k in pairs(self.cl.guis) do
        k:close()
        k = nil
    end

    for i = 1, #chars do
        local gui = sm.gui.createNameTagGui()
        gui:setRequireLineOfSight( false )
	    gui:setMaxRenderDistance( 1000 )

        self.cl.guis[i] = gui
    end
end

function BotDetector:cl_updateUV( active )
    self.interactable:setUvFrameIndex( active and 6 or 0 )
end

function BotDetector:client_onUpdate( dt )
    for v, k in pairs(self.cl.guis) do
        local currentChar = self.cl.chars[v]
        if sm.exists(currentChar) then
            k:setWorldPosition( currentChar.worldPosition + sm.vec3.new(0,0,1.5) )
	        k:setText("Text", "#"..currentChar.color:getHexStr():sub(1, 6)..tostring(charIdToName[tostring(currentChar:getCharacterType())]))

            if self.interactable.active then
                k:open()
            else
                k:close()
            end
        end
    end
end