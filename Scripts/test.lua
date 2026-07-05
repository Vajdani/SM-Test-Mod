---@class NetworkBase
---@field network Network
NetworkBase = class()

---@param client Player
---@param callback string
---@param ... any
function NetworkBase:sendToClient(client, callback, ...)
    self.network:sendToClient(client, "internal_receiveNetworkCall", { callback, {...} })
end

---@param callback string
---@param ... any
function NetworkBase:sendToClients(callback, ...)
    self.network:sendToClients("internal_receiveNetworkCall", { callback, {...} })
end

---@param callback string
---@param ... any
function NetworkBase:sendToServer(callback, ...)
    self.network:sendToServer("internal_receiveNetworkCall", { callback, {...} })
end

function NetworkBase:internal_receiveNetworkCall(data, client)
    local callback, args = unpack(data)
    if client then
        self[callback](self, client, unpack(args))
    else
        self[callback](self, unpack(args))
    end
end



---@class SomeObject : ShapeClass, NetworkBase
SomeObject = class(NetworkBase)
SomeObject.maxChildCount = -1
SomeObject.connectionOutput = 1

function SomeObject:sv_toggle(client, num1, num2, num3, num4)
    self.interactable.active = not self.interactable.active

    print("hello i am server:", client, num1, num2, num3, num4, self.interactable.active)

    self:sendToClients("cl_toggle", num1, num2, num3, num4)
end


function SomeObject:client_onInteract(char, state)
    if not state then return end

    self:sendToServer("sv_toggle", 1, 2, 3, 4)
end

function SomeObject:cl_toggle(num1, num2, num3, num4)
    print("hello i am client:", num1, num2, num3, num4)
end