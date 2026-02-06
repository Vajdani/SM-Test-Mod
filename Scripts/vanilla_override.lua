testmod_originalHookFuncs = testmod_originalHookFuncs or {}
for k, v in pairs(_G) do
    if type(v) ~= "table" then
        goto continue
    end

    if v.server_onPlayerJoined then
        if testmod_originalHookFuncs[k] == nil then
			testmod_originalHookFuncs[k] = {
				cl_onChatCommand = v.cl_onChatCommand
			}
		end

        function v:cl_onChatCommand(params)
            local cmd = params[1]
            if cmd == "/lhotbar" then
                sm.event.sendToTool(sm.testmod_cmdHandler, "cl_lhotbar", params)
                return
            elseif cmd == "/shotbar" then
                sm.event.sendToTool(sm.testmod_cmdHandler, "cl_shotbar", params)
            elseif cmd == "/hotbars" then
                sm.event.sendToTool(sm.testmod_cmdHandler, "cl_hotbars", params)
                return
            end

            if testmod_originalHookFuncs[k].cl_onChatCommand then
                testmod_originalHookFuncs[k].cl_onChatCommand(self, params)
            end
        end
    end

    ::continue::
end