---@class Drone : ShapeClass
Drone = class()
Drone.reloadTime = 8
Drone.damage = 40
Drone.projectileSpeed = 130
Drone.minFloatHight = 5
Drone.maxFloatHight = 50
Drone.movementControls = {
    {
        id = sm.interactable.actions.forward,
        dir = function( camUp, dir, up )
            return up:cross(dir:cross(camUp))
        end
    },
    {
        id = sm.interactable.actions.backward,
        dir = function( camUp, dir, up )
            return up:cross(camUp:cross(dir))
        end
    },
    {
        id = sm.interactable.actions.left,
        dir = function( camUp, dir )
            return camUp:cross(dir)
        end
    },
    {
        id = sm.interactable.actions.right,
        dir = function( camUp, dir )
            return dir:cross(camUp)
        end
    }
}

local camAdjust = sm.vec3.new(0,0,0.575)
local up = sm.vec3.new(0,0,1)

dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua"

function Drone:server_onCreate()
    self.sv = {}
    self.sv.controls = {
        [sm.interactable.actions.create] = false,
        [sm.interactable.actions.attack] = false,
        [sm.interactable.actions.forward] = false,
        [sm.interactable.actions.backward] = false,
        [sm.interactable.actions.left] = false,
        [sm.interactable.actions.right] = false,
        [sm.interactable.actions.jump] = false
    }
    self.sv.hoverHeight = self.minFloatHight
end

function Drone:sv_updatePlayerControls( controls )
    self.sv.controls = controls
end

function Drone:sv_changeHoverHeight( change )
    self.sv.hoverHeight = self.sv.hoverHeight + change
end

function Drone:server_onFixedUpdate()
    local worldPos = self.shape.worldPosition
    local appliedForce = sm.vec3.zero()
    local hit, result = sm.physics.raycast( worldPos, worldPos - sm.vec3.new(0,0,self.sv.hoverHeight) )
    if hit then
        local proportionalHeight = (self.sv.hoverHeight - (result.pointWorld - worldPos):length()) / self.sv.hoverHeight
        appliedForce = up * proportionalHeight * 1.5;
    end

    local seatedChar = self.interactable:getSeatCharacter()
    if seatedChar ~= nil then
        appliedForce = appliedForce + self:sv_getMoveDir()

        local dir = seatedChar.direction; dir.z = 0; dir = dir:normalize()
        local forceDir = self.shape.up:cross(dir)
        sm.physics.applyTorque( self.shape.body, forceDir * 0.005, true )
    end

    sm.physics.applyImpulse( self.shape, appliedForce, true )
end

function Drone:sv_getMoveDir()
    local char = self.interactable:getSeatCharacter()
    local dir = char:getDirection()
    local camUp = dir:rotate(math.rad(90), dir:cross(up))
    local moveDir = sm.vec3.zero()

    for k, v in pairs(self.movementControls) do
        if self.sv.controls[v.id] then
            moveDir = moveDir + v.dir( camUp, dir, up )
        end
    end

    return moveDir
end

function Drone:client_onCreate()
    self.cl = {}
    self.cl.shootTimer = Timer()
    self.cl.shootTimer:start(self.reloadTime)
    self.cl.controls = {
        [sm.interactable.actions.create] = false,
        [sm.interactable.actions.attack] = false,
        [sm.interactable.actions.forward] = false,
        [sm.interactable.actions.backward] = false,
        [sm.interactable.actions.left] = false,
        [sm.interactable.actions.right] = false,
        [sm.interactable.actions.jump] = false
    }

    self.cl.heightChangeTimer = Timer()
    self.cl.heightChangeTimer:start( 40 )
end

function Drone:client_onFixedUpdate()
    local player = sm.localPlayer.getPlayer()
    local seatedChar = self.interactable:getSeatCharacter()
    if seatedChar == nil or player.character ~= seatedChar then return end

    self.cl.shootTimer:tick()
    if self.cl.controls[sm.interactable.actions.create] and self.cl.shootTimer:done() then
        local dir = seatedChar.direction

        sm.projectile.projectileAttack(
            projectile_potato,
            self.damage,
            self.shape.worldPosition + dir, --sm.camera.getPosition()
            dir * self.projectileSpeed,
            player
        )
        self.cl.shootTimer:reset()
    end

    self.cl.heightChangeTimer:tick()
    if self.cl.heightChangeTimer:done() then
        if self.cl.controls[sm.interactable.actions.jump] then
            self.network:sendToServer("sv_changeHoverHeight", 1)
        elseif seatedChar:isCrouching() then
            self.network:sendToServer("sv_changeHoverHeight", -1)
        end
    end
end

function Drone:client_onUpdate( dt )
    --Thanks Axolot
    if sm.camera.getCameraState() == 0 then
        sm.camera.setPosition( sm.camera.getPosition() )
        sm.camera.setDirection( sm.camera.getDirection() )
    end

    local player = sm.localPlayer.getPlayer()
    local seatedChar = self.interactable:getSeatCharacter()
    if seatedChar == nil or player.character ~= seatedChar then return end

    local lerpTime = dt*10

    sm.camera.setPosition( sm.vec3.lerp( sm.camera.getPosition(), seatedChar.worldPosition + camAdjust - self.shape.up, lerpTime ) )
    sm.camera.setDirection( sm.vec3.lerp( sm.camera.getDirection(), seatedChar.direction, lerpTime * 5 ) )

    local fov = self.cl.controls[sm.interactable.actions.attack] and sm.camera.getDefaultFov() / 3 or sm.camera.getDefaultFov()
    sm.camera.setFov( sm.util.lerp( sm.camera.getFov(), fov, lerpTime ) )
end

function Drone:client_canInteract()
    sm.gui.setInteractionText(
        "Move: "..sm.gui.getKeyBinding("Forward", true)..sm.gui.getKeyBinding("StrafeLeft", true)..sm.gui.getKeyBinding("Backward", true)..sm.gui.getKeyBinding("StrafeRight", true),
        "\tShoot: "..sm.gui.getKeyBinding("Create", true),
        "\tZoom: "..sm.gui.getKeyBinding("Attack", true),
        "\tAscend/Descend: "..sm.gui.getKeyBinding("Jump", true).."/"..sm.gui.getKeyBinding("Crawl", true)
    )
    sm.gui.setInteractionText(
        "",
        sm.gui.getKeyBinding("Use", true),
        "Enter"
    )

    return self.interactable:getSeatCharacter() == nil
end

function Drone:client_onInteract( char, state )
    if not state then return end

    self.interactable:setSeatCharacter(char)
    sm.camera.setCameraState( 2 )
end

function Drone:client_onAction( action, state )
    if self.cl.controls[action] ~= nil then
        self.cl.controls[action] = state
        self.network:sendToServer("sv_updatePlayerControls", self.cl.controls)
    end

    if not state then return true end

    local player = sm.localPlayer.getPlayer()
    local char = player.character
    if action == sm.interactable.actions.use then
        self.interactable:setSeatCharacter(char)
        sm.camera.setCameraState( 0 )
    end

    return not isAnyOf(action, { sm.interactable.actions.zoomIn, sm.interactable.actions.zoomOut })
end