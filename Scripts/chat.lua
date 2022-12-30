---@class Chat : ShapeClass
Chat = class()
Chat.questions = {
    ["doyoulikedeeznuts"] = "lol no",
    ["haveyouvisitedmymomshousebefore"]= "yes",
    ["whatsthemeaningoflife"] =  "42",
    ["ch2when"] =  "stfu",
    ["sexmodwhen"] =  "go to horny jail",
    ["amogus"] =  "STOP POSTING ABOUT AMONG US! I'M TIRED OF SEEING IT! MY FRIENDS ON TIKTOK SEND ME MEMES, ON DISCORD IT'S FUCKING MEMES! I was in a server, right? and ALL OF THE CHANNELS were just among us stuff. I-I showed my champion underwear to my girlfriend and t-the logo I flipped it and I said 'hey babe, when the underwear is sus HAHA DING DING DING DING DING DING DING DI DI DING' I fucking looked at a trashcan and said 'THATS A BIT SUSSY' I looked at my penis I think of an astronauts helmet and I go 'PENIS? MORE LIKE PENSUS' AAAAAAAAAAAAAAHGESFG",
    ["test"] =  "my mom? MY mom? well ok then buddy. I only have one thing to say: deez nuts",
    ["v1"] =  "MACHINE! I will CUT you DOWN, BREAK you APART, SPLAY the GORE of your profane form across the stars! I will GRIND you DOWN until the very sparks CRY for mercy! My hands shall RELISH ending you, HERE, AND, NOW!",
}
Chat.removeChars = { "?", ",", ";", ".", " ", "'" }
Chat.pauseChars = { "?", "!", ".", ":" }
Chat.pauseChars_quick = { "," }
Chat.defaultAnswer = "I can't answer that sadly."
Chat.arrow = "YOUR MOM"
Chat.pauseTicks = 24
Chat.pauseTicks_quick = 12
Chat.printTicks = 3

function Chat:client_onCreate()
    self.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/chat.layout")
    self.gui:setTextAcceptedCallback("input", "cl_input_accept")
    self.gui:setTextChangedCallback("input", "cl_input_change")

    self.prevString = ""
    self.printing = false
    self.printText = ""
    self.displayedText = ""
    self.charIndex = 0
    self.charTicker = Timer()
    self.charTicker:start( self.printTicks )
    self.arrowTicker = Timer()
    self.arrowTicker:start( 20 )
end

function Chat:cl_input_accept( widget, text )
    sm.audio.play("Button off")

    if self.printing then
        sm.gui.displayAlertText("Bot is busy!")
        self.gui:setText("input", self.prevString)
        return
    end

    self.prevString = text
    local finalText = text:lower()
    for k, v in pairs(self.removeChars) do
        finalText = finalText:gsub("%"..v, "")
    end

    if finalText == "" then
        self.gui:setText("output", "")
        return
    end

    self:cl_startPrinting( self.questions[finalText] or self.defaultAnswer )
end

function Chat:cl_input_change( widget, text )
    sm.audio.play("Button on")
end


function Chat:client_onInteract( char, state )
    if not state then return end

    self.gui:open()
end

function Chat:cl_startPrinting( text )
    self.printing = true
    self.printText = text
    self.displayedText = ""
    self.charIndex = 0
    self.charTicker.count = self.charTicker.ticks
    self.arrowTicker:reset()
    self.gui:setText("output", "")
end

function Chat:client_onFixedUpdate()
    if self.printText ~= "" and self.charIndex >= self.printText:len() then
        self.printing = false

        --[[self.arrowTicker:tick()
        if self.arrowTicker:done() then
            self.arrowTicker:reset()

            if self.displayedText:find(self.arrow) == nil then
                self.displayedText = self.displayedText..self.arrow
            else
                self.displayedText = self.displayedText:gsub(self.arrow, "")
            end

            self.gui:setText("output", self.displayedText)
        end]]
    end

    if self.printing and self.gui:isActive() then
        self.charTicker:tick()
        if self.charTicker:done() then
            self.charIndex = self.charIndex + 1
            local char = self.printText:sub(self.charIndex, self.charIndex)
            self.displayedText = self.displayedText..char

            if char ~= " " then
                sm.audio.play("Button on")
            end

            self.gui:setText("output", self.displayedText)

            if isAnyOf(char, self.pauseChars) then
                self.charTicker:start( self.pauseTicks )
            elseif isAnyOf(char, self.pauseChars_quick) then
                self.charTicker:start( self.pauseTicks_quick )
            else
                self.charTicker:start( self.printTicks )
            end
        end
    end
end