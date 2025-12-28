dofile "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua"

---@class BG : ShapeClass
BG = class()
--PotatoRifle settings
BG.defaultValues = {
    canAim = true,
    aimFOVScale = 0.33,
    fullAuto = false,
    shotDelay = 0.2,
    projectile = projectile_potato,
    damage = 28,
    velocity = 130,
    muzzleEffect = { tp = "SpudgunBasic - BasicMuzzel", fp = "SpudgunBasic - FPBasicMuzzel" },
    spread = 8,
    scale = 1
}

local projectileToUUID = {
    Potato              = projectile_potato,
    ["Small Potato"]    = projectile_smallpotato,
    Fries               = projectile_fries,
    Tape                = projectile_tape,
    ["Explosive Tape"]  = projectile_explosivetape,
    ["Pesticide"]       = projectile_pesticide,
    ["Water"]           = projectile_water,
    ["Glowstick"]       = projectile_glowstick,
}
local UUIDToProjectile = {
    [tostring(projectile_potato)]        = "Potato",
    [tostring(projectile_smallpotato)]   = "Small Potato",
    [tostring(projectile_fries)]         = "Fries",
    [tostring(projectile_tape)]          = "Tape",
    [tostring(projectile_explosivetape)] = "Explosive Tape",
    [tostring(projectile_pesticide)]     = "Pesticide",
    [tostring(projectile_water)]         = "Water",
    [tostring(projectile_glowstick)]     = "Glowstick",
}
local muzzleToEffects = {
    Spudgun = { tp = "SpudgunBasic - BasicMuzzel", fp = "SpudgunBasic - FPBasicMuzzel" },
    SpudShotgun = { tp = "SpudgunFrier - FrierMuzzel", fp = "SpudgunFrier - FPFrierMuzzel" },
    Spudling = { tp = "SpudgunSpinner - SpinnerMuzzel" , fp = "SpudgunSpinner - FPSpinnerMuzzel" }
}
local effectToMuzzle = {
    ["SpudgunBasic - BasicMuzzel"] = "Spudgun",
    ["SpudgunFrier - FrierMuzzel"] = "SpudShotgun",
    ["SpudgunSpinner - SpinnerMuzzel"] = "Spudling"
}

local on = "#269e44On"
local off = "#9e2626Off"

function BG:server_onCreate()
    self.sv_data = self.storage:load()
    if self.sv_data == nil then
        self.sv_data = self.defaultValues
    end

    self.network:setClientData( self.sv_data )
    self.interactable.publicData = self.sv_data
end

function BG:sv_updateSettings( data )
    self.sv_data = data
    self.network:setClientData( self.sv_data )
    self.storage:save( self.sv_data )
    self.interactable.publicData = self.sv_data
end

function BG:sv_markMuzzlePos( offset )
    self.sv_data.muzzleOffset = offset[1]
    self.sv_data.muzzleOffsetNormal = offset[2]
    self.network:setClientData( self.sv_data )
    self.storage:save( self.sv_data )
    self.interactable.publicData = self.sv_data
end



function BG:client_onCreate()
    self.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/BG.layout")
    self.gui:setButtonCallback( "aim", "cl_settings_aim" )
    self.gui:setTextAcceptedCallback( "fov", "cl_settings_fov" )
    self.gui:setButtonCallback( "auto", "cl_settings_auto" )
    self.gui:setTextAcceptedCallback( "cooldown", "cl_settings_cooldown" )

    local projectileOptions = {}
    for k, v in pairs(projectileToUUID) do
        table.insert(projectileOptions, k)
    end

    self.gui:createDropDown( "projectile", "cl_settings_projectile", projectileOptions )

    self.gui:setTextAcceptedCallback( "damage", "cl_settings_damage" )
    self.gui:setTextAcceptedCallback( "velocity", "cl_settings_velocity" )

    local muzzleOptions = {}
    for k, v in pairs(muzzleToEffects) do
        table.insert(muzzleOptions, k)
    end
    self.gui:createDropDown( "muzzle", "cl_settings_muzzle", muzzleOptions )

    self.gui:setTextAcceptedCallback( "spread", "cl_settings_spread" )
    self.gui:setTextAcceptedCallback( "scale", "cl_settings_scale" )
    self.gui:setButtonCallback( "reset", "cl_settings_reset" )

    self.cl_data = {}
    self.markingMuzzlePos = false
    self.click = false
    self.blockgunSeen = false
end

local handRot = sm.quat.angleAxis(RAD90, VEC3_RIGHT)
function BG:client_onUpdate()
    if not self.markingMuzzlePos then return end
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Attack", true), "Cancel")

    sm.gui.displayAlertText("Currently marking muzzle positon", 1)
    local hit, result = sm.localPlayer.getRaycast( 7.5 )
    local pos = result.pointWorld
    self.blockgunSeen = hit and result.type == "body" and result:getBody() == self.shape.body

    if self.blockgunSeen then
        if self.nextMuzzle then
            self.nextMuzzle:setPosition(pos + result.normalWorld * 0.25)
            self.nextMuzzle:setRotation(sm.vec3.getRotation(VEC3_UP, result.normalWorld) * handRot)
        end

        if self.currentMuzzle then
            local pos2 = self.shape.worldPosition + self.cl_data.muzzleOffset
            local rot = sm.quat.identity()
            if self.cl_data.muzzleOffsetNormal then
                pos2 = pos2 + self.cl_data.muzzleOffsetNormal * 0.25
                rot = sm.vec3.getRotation(VEC3_UP, self.cl_data.muzzleOffsetNormal)
            end

            self.currentMuzzle:setPosition(pos2)
            self.currentMuzzle:setRotation(rot * handRot)
        end
    else
        return
    end

    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Create", true), "Mark as muzzle position")

    if self.click then
        self.click = false
        self.markingMuzzlePos = false
        self.blockgunSeen = false

        sm.effect.playEffect("Part - Upgrade", pos, sm.vec3.zero(), sm.vec3.getRotation(sm.vec3.new(0,1,0), result.normalWorld))
        sm.gui.displayAlertText("Successfully marked muzzle positon!", 2.5)
        sm.audio.play("Blueprint - Build")

        self:cl_destroyMuzzleEffects()

        sm.localPlayer.getPlayer().character:setLockingInteractable( nil )
        self.network:sendToServer("sv_markMuzzlePos", { pos - self.shape.worldPosition, result.normalWorld })
    end
end

function BG:client_onClientDataUpdate( data )
    self.cl_data = data

    self.gui:setText( "aim", self.cl_data.canAim and on or off )
    self.gui:setText( "fov", string.format("%.3f", tostring(self.cl_data.aimFOVScale)) )
    self.gui:setText( "auto", self.cl_data.fullAuto and on or off )
    self.gui:setText( "cooldown", string.format("%.3f", tostring(self.cl_data.shotDelay)) )
    self.gui:setSelectedDropDownItem( "projectile", UUIDToProjectile[tostring(self.cl_data.projectile)] )
    self.gui:setText( "damage", tostring(self.cl_data.damage) )
    self.gui:setText( "velocity", tostring(self.cl_data.velocity) )
    self.gui:setSelectedDropDownItem( "muzzle", effectToMuzzle[self.cl_data.muzzleEffect.tp] )
    self.gui:setText( "spread", string.format("%.3f", tostring(self.cl_data.spread)) )
    self.gui:setText( "scale", string.format("%.3f", tostring(self.cl_data.scale)) )
end

function BG:client_canInteract()
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), "Configure gun settings")
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Tinker", true), "Mark muzzle position")

    return true
end

function BG:client_onInteract( char, state )
    if not state then return end

    self.gui:open()
end

function BG:client_onTinker( char, state )
    if not state then return end

    if self.cl_data.muzzleOffset then
        self.currentMuzzle = sm.effect.createEffect("ShapeRenderable")
        self.currentMuzzle:setParameter("uuid", obj_decor_mannequinhand)
        self.currentMuzzle:setParameter("visualization", true)
        self.currentMuzzle:setParameter("valid", false)
        self.currentMuzzle:setScale(sm.vec3.one() * 0.25)
        self.currentMuzzle:start()
    end

    self.nextMuzzle = sm.effect.createEffect("ShapeRenderable")
    self.nextMuzzle:setParameter("uuid", obj_decor_mannequinhand)
    self.nextMuzzle:setParameter("visualization", true)
    self.nextMuzzle:setParameter("valid", true)
    self.nextMuzzle:setScale(sm.vec3.one() * 0.25)
    self.nextMuzzle:start()

    self.markingMuzzlePos = true
    char:setLockingInteractable( self.interactable )
end

function BG:client_onAction( action, state )
    if action == sm.interactable.actions.create then
        if self.blockgunSeen then
            self.click = state
        end

        return true
    elseif action == sm.interactable.actions.attack then
        self.click = false
        self.markingMuzzlePos = false
        sm.gui.displayAlertText("Cancelled muzzle marking!", 2.5)
        sm.audio.play("Blueprint - Delete")
        sm.localPlayer.getPlayer().character:setLockingInteractable( nil )

        self:cl_destroyMuzzleEffects()

        return true
    end

    return false
end

function BG:cl_destroyMuzzleEffects()
    if self.currentMuzzle then
        self.currentMuzzle:destroy()
        self.currentMuzzle = nil
    end

    self.nextMuzzle:destroy()
    self.nextMuzzle = nil
end


function BG:cl_settings_aim()
    self.cl_data.canAim = not self.cl_data.canAim
    self.network:sendToServer("sv_updateSettings", self.cl_data)
end

function BG:cl_settings_fov( widget, text )
    local valid, value = self:verifyInput( text, widget, self.cl_data.aimFOVScale )

    if valid then
        self.cl_data.aimFOVScale = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function BG:cl_settings_auto()
    self.cl_data.fullAuto = not self.cl_data.fullAuto
    self.network:sendToServer("sv_updateSettings", self.cl_data)
end

function BG:cl_settings_cooldown( widget, text )
    local valid, value = self:verifyInput( text, widget, self.cl_data.shotDelay )

    if valid then
        self.cl_data.shotDelay = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function BG:cl_settings_projectile( item )
    self.cl_data.projectile = projectileToUUID[item]
    self.network:sendToServer("sv_updateSettings", self.cl_data)
end

function BG:cl_settings_damage( widget, text )
    local valid, value = self:verifyInput( text, widget, self.cl_data.damage )

    if valid then
        self.cl_data.damage = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function BG:cl_settings_velocity( widget, text )
    local valid, value = self:verifyInput( text, widget, self.cl_data.velocity )

    if valid then
        self.cl_data.velocity = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function BG:cl_settings_muzzle( item )
    self.cl_data.muzzleEffect = muzzleToEffects[item]
    self.network:sendToServer("sv_updateSettings", self.cl_data)
end

function BG:cl_settings_spread( widget, text )
    local valid, value = self:verifyInput( text, widget, self.cl_data.spread )

    if valid then
        self.cl_data.spread = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function BG:cl_settings_scale( widget, text )
    local valid, value = self:verifyInput( text, widget, self.cl_data.scale )

    if valid then
        self.cl_data.scale = value
        self.network:sendToServer("sv_updateSettings", self.cl_data)
    end
end

function BG:cl_settings_reset()
    sm.gui.displayAlertText("Gun settings have been reset to default!", 2.5)
    sm.audio.play("Blueprint - Delete")
    self.network:sendToServer("sv_updateSettings", self.defaultValues)
end



function BG:verifyInput( input, widget, default )
    local num = tonumber(input)
	if num == nil then
		sm.gui.displayAlertText("#ff0000Please only enter numbers!", 2.5)
		sm.audio.play("RaftShark")
		self.gui:setText( widget, tostring(default) )

		return false
	end

    return true, num
end