dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_items.lua"

---@class Titan : ShapeClass
Titan = class()
Titan.movementAnims = {
    ["run"] = function(fwd, right)
        return fwd == 1 and right == 0
    end,
    ["run_left"] = function(fwd, right)
        return fwd == 1 and right == -1
    end,
    ["run_right"] = function(fwd, right)
        return fwd == 1 and right == 1
    end,
    ["run_bwd"] = function(fwd, right)
        return fwd == -1 and right == 0
    end,
    ["run_bwd_left"] = function(fwd, right)
        return fwd == -1 and right == -1
    end,
    ["run_bwd_right"] = function(fwd, right)
        return fwd == -1 and right == 1
    end,
    ["shuffle_left"] = function(fwd, right)
        return fwd == 0 and right == -1
    end,
    ["shuffle_right"] = function(fwd, right)
        return fwd == 0 and right == 1
    end
}
Titan.anims = {
    "idle",
    "run",
    "run_left",
    "run_right",
    "run_bwd",
    "run_bwd_left",
    "run_bwd_right",
    "shuffle_left",
    "shuffle_right"
}
Titan.gunAnims = {
    [tostring(tool_spudgun)] = {
        "spudgun_idle",
        "spudgun_run",
        "spudgun_run_left",
        "spudgun_run_right",
        "spudgun_run_bwd",
        "spudgun_run_bwd_left",
        "spudgun_run_bwd_right",
        "spudgun_shuffle_left",
        "spudgun_shuffle_right"
    }
}
Titan.weapons = {
    {
        id = tool_spudgun,
        model = obj_tool_spudgun
    },
    {
        id = tool_shotgun,
        model = obj_tool_frier
    },
    {
        id = tool_gatling,
        model = obj_tool_spudling
    }
}

local vec3_up = sm.vec3.new(0,0,1)
local vec3_zero = sm.vec3.zero()


function Titan:server_onCreate()
    self.sv = {}

    local actions = sm.interactable.actions
    self.sv.controls = {
        [actions.forward] = false,
        [actions.backward] = false,
        [actions.left] = false,
        [actions.right] = false
    }

end

function Titan:server_onFixedUpdate()
    local controls = self.sv.controls
    local fwd = BoolToVal(controls[3]) - BoolToVal(controls[4])
    local right = BoolToVal(controls[2]) - BoolToVal(controls[1])

    local shape = self.shape
    local moveDir = shape.up * fwd - shape.right * right
    if fwd ~= 0 and right ~= 0 then moveDir = moveDir:normalize() end

    local mass = shape.mass
    local vel = shape.velocity; vel.z = 0
    sm.physics.applyImpulse(
        shape,
        (moveDir - vel * 0.25) * mass,
        true
    )

    local rot = vec3_zero
    local char = self.interactable:getSeatCharacter()
    if char then
        rot = char.direction; rot.z = 0; rot = rot:normalize()
    end

    local body = shape.body
    local up = shape.at
    sm.physics.applyTorque(
        body,
        (up * shape.right:dot(rot) * 0.1 - up * body.angularVelocity * 0.02) * mass,
        true
    )

    local hit, result = sm.physics.raycast(shape.worldPosition, shape.worldPosition - up)
    local normal = hit and result.normalWorld or vec3_up
    sm.physics.applyTorque(
        body,
        up:cross(normal) * mass * 0.25,
        true
    )
end


function Titan:sv_syncControls(controls)
    self.sv.controls = controls
    self.network:sendToClients("cl_syncControls", controls)
end



function Titan:client_onCreate()
    self.cl = {}
    --[[self.cl.movementAnims = {}
    for k, name in pairs(self.anims) do
        local isIdle = name == "idle"
        self.cl.movementAnims[name] = {
            time = 0,
            weight = 0,
            main = isIdle,
            duration = self.interactable:getAnimDuration( name )
        }

        self.interactable:setAnimEnabled( name, isIdle )
    end]]
    self.cl.movementAnim = {
        name = "idle",
        time = 0,
        duration = self.interactable:getAnimDuration("idle")
    }
    self.interactable:setAnimEnabled("idle", true)
    self.interactable:setAnimEnabled("spine_bend", true)

    local actions = sm.interactable.actions
    self.cl.controls = {
        [actions.forward] = false,
        [actions.backward] = false,
        [actions.left] = false,
        [actions.right] = false
    }

    self.spineBend = 0.5

    self.hotBar = sm.gui.createSeatGui()
    for k, data in pairs(self.weapons) do
        self.hotBar:setGridItem(
            "ButtonGrid",
            k-1,
            {
                ["itemId"] = tostring(data.id),
                ["active"] = k == 1
            }
        )
    end

    self.weaponData = self.weapons[1]
    self.weaponEffect = sm.effect.createEffect("ShapeRenderable")
    self.weaponEffect:setParameter("uuid", obj_tool_spudgun)
    self.weaponEffect:setScale(sm.vec3.one() * 0.25)
    self.weaponEffect:start()
end

function Titan:client_onDestroy()
    self.weaponEffect:destroy()
end

function Titan:client_canInteract()
    local canInteract = self.interactable:getSeatCharacter() == nil
    if canInteract then
        sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), "Enter Titan")
    else
        sm.gui.setInteractionText("<p textShadow='false' bg='gui_keybinds_bg_orange' color='#ff0000' spacing='9'>Titan is occupied</p>")
    end

    return canInteract
end

function Titan:client_onInteract(char, state)
    if not state then return end

    self.interactable:setSeatCharacter(char)
    self.hotBar:open()
end

function Titan:client_onAction(action, state)
    if self.cl.controls[action] ~= nil then
        self.cl.controls[action] = state
        self.network:sendToServer("sv_syncControls", self.cl.controls)
    end

    if not state then return true end

    if action == 15 then
        self.interactable:setSeatCharacter(sm.localPlayer.getPlayer().character)

        local actions = sm.interactable.actions
        self.cl.controls = {
            [actions.forward] = false,
            [actions.backward] = false,
            [actions.left] = false,
            [actions.right] = false
        }
        self.network:sendToServer("sv_syncControls", self.cl.controls)

        self.hotBar:close()
    end

    return not isAnyOf(action, { 20, 21 })
end

function Titan:client_onUpdate(dt)
    --[[local totalWeight = 0
    for name, animData in pairs(self.cl.movementAnims) do
        animData.time = animData.time + dt
        if animData.main then
            animData.weight = math.min( animData.weight + 2 * dt, 1.0 )
        else
            animData.weight = math.max( animData.weight - 2 * dt, 0.0 )
            if animData.weight == 0 then
                --self.interactable:setAnimEnabled( name, false )
            end
        end

        totalWeight = totalWeight + animData.weight
    end

    totalWeight = totalWeight == 0 and 1.0 or totalWeight
    for name, animData in pairs(self.cl.movementAnims) do
        local weight = animData.weight / totalWeight
        self.interactable:setAnimProgress( name, (animData.time / animData.duration))
    end]]

    local animData = self.cl.movementAnim
    animData.time = animData.time + dt
    self.interactable:setAnimProgress(animData.name, (animData.time / animData.duration))

    local char = self.interactable:getSeatCharacter()
    if char then
        self.spineBend = sm.util.lerp(
            self.spineBend,
            sm.util.clamp( self.shape.up.z - char.direction.z + 0.4, 0, 1 ),
            dt * 5
        )
    else
        self.spineBend = sm.util.lerp( self.spineBend, 0.5, dt * 10 )
    end
    self.interactable:setAnimProgress("spine_bend", self.spineBend)

    self.weaponEffect:setPosition(self.interactable:getWorldBonePosition( "jnt_spine2" ))
end

function Titan:cl_syncControls(controls)
    self.cl.controls = controls
    self:cl_updateMovementAnims()
end

function Titan:cl_updateMovementAnims()
    --[[local prevAnim = self:getMainAnim()
    local prevAnimData = self.cl.movementAnims[prevAnim]
    prevAnimData.main = false]]

    local prevAnim = self.cl.movementAnim.name
    self.interactable:setAnimEnabled(prevAnim, false)
    self.interactable:setAnimProgress(prevAnim, 0)

    local controls = self.cl.controls
    local fwd = BoolToVal(controls[3]) - BoolToVal(controls[4])
    local right = BoolToVal(controls[2]) - BoolToVal(controls[1])

    local nextAnim = "idle"
    for anim, fun in pairs(self.movementAnims) do
        if fun(fwd, right) then
            nextAnim = anim
            break
        end
    end

    --[[local newAnim = self.cl.movementAnims[nextAnim]
    newAnim.main = true
    self.interactable:setAnimEnabled( nextAnim, true )]]

    self.cl.movementAnim = {
        name = nextAnim,
        time = 0,
        weight = 0,
        duration = self.interactable:getAnimDuration(nextAnim)
    }
    self.interactable:setAnimEnabled(nextAnim, true)
end

function Titan:getMainAnim()
    for k, v in pairs(self.cl.movementAnims) do
        if v.main then
            return k, v
        end
    end

    return "", {}
end

function BoolToVal(bool)
    return bool and 1 or 0
end
