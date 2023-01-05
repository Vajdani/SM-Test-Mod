idtest = class()

local ID_of_the_original_mod = 2545301375

function idtest:server_onCreate()
    local file = sm.json.open("$MOD_DATA/description.json")
    if file.fileId ~= ID_of_the_original_mod then
        self.network:sendToClients("cl_crashGame")
    end
end

function idtest:cl_crashGame()
    sm.util.positiveModulo(1,0)
end