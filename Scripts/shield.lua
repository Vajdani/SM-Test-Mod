---@class Shield : ToolClass
Shield = class()

dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

function Shield:server_onCreate()
    self.trigger = sm.areaTrigger.createBox(sm.vec3.one(), sm.vec3.zero())
    self.trigger:bindOnProjectile("sv_onProjectile")
    self.sv_active = false
    self.sv_owner = self.tool:getOwner()
end

function Shield:server_onDestroy()
    sm.areaTrigger.destroy(self.trigger)
end

function Shield:server_onFixedUpdate()
    self.trigger:setWorldPosition(self.sv_owner.character.worldPosition)
end

function Shield:sv_onProjectile( trigger, hitPos, airTime, velocity, projectileUuid, source, damage, data, customData, hitNormal )
    if self.sv_active then
        local player = self.sv_owner
        local char = player.character
        local dir = char.direction
        sm.projectile.projectileAttack(
            projectileUuid,
            damage * 1.5,
            char.worldPosition + dir,
            dir * velocity:length() * 1.5,
            player
        )

        self.network:sendToClients("cl_onProjectile")
    end

    return self.sv_active
end

function Shield:sv_toggle()
    self.sv_active = not self.sv_active
    self.network:sendToClients("cl_toggle")
end




local renderablesTp = { "$CONTENT_DATA/Tools/Anims/char_male_tp.rend" }
local renderablesFp = { "$CONTENT_DATA/Tools/Anims/char_male_fp.rend" }
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function Shield:client_onCreate()
    self.cl_active = false
    self.effect = sm.effect.createEffect("ShapeRenderable")
    self.effect:setScale(sm.vec3.one() * 2)
    self.effect:setParameter("uuid", blk_wood1)
    self.effect:setParameter("visualization", true)

    self.isLocal = self.tool:isLocal()
    self.cl_owner = self.tool:getOwner()

    self.tpAnimations = createTpAnimations(
		self.tool,
		{
			parry = { "parry" },
		}
	)

    if self.isLocal then
        self.fpAnimations = createFpAnimations(
            self.tool,
            {
                parry = { "parry" },
            }
        )
    end
end

function Shield:client_onDestroy()
    self.effect:destroy()
end

function Shield:client_onUpdate( dt )
    self.effect:setPosition(self.cl_owner.character.worldPosition)

	local totalWeight = 0.0
	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

            if animation.time >= animation.info.duration then
                self.tpAnimations.currentAnimation = ""
            end
		else
			animation.weight = math.max( animation.weight - ( self.tpAnimations.blendSpeed * dt ), 0.0 )
		end

		totalWeight = totalWeight + animation.weight
	end

	totalWeight = totalWeight == 0 and 1.0 or totalWeight
	for name, animation in pairs( self.tpAnimations.animations ) do
		local weight = animation.weight / totalWeight
		self.tool:updateAnimation( animation.info.name, animation.time, weight )
	end

    if self.isLocal then
	    updateFpAnimations( self.fpAnimations, self.tool:isEquipped(), dt )
    end
end

function Shield:client_onEquip()
    if self.cl_active then
        self.effect:start()
    end

    self.tool:setTpRenderables( renderablesTp )
	if self.isLocal then
		self.tool:setFpRenderables( renderablesFp )
    end
end

function Shield:client_onUnequip()
    self.effect:stop()
end

function Shield:client_onEquippedUpdate( rmb, lmb )
    if rmb == 1 then
        self.network:sendToServer("sv_toggle")

        sm.gui.displayAlertText(self.cl_active and "Shield deactivated" or "Shield activated", 2.5)
        sm.audio.play("Button on")
    end

    return true, true
end

function Shield:cl_toggle()
    self.cl_active = not self.cl_active
    if self.cl_active then self.effect:start() else self.effect:stop() end
end

function Shield:cl_onProjectile()
	setTpAnimation( self.tpAnimations, "parry", 1 )
    if self.isLocal then
	    setFpAnimation( self.fpAnimations, "parry", 1 )
        sm.camera.setShake( 0.1 )
    end
end