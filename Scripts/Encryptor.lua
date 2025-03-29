dofile("$SURVIVAL_DATA/Scripts/util.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_survivalobjects.lua")

---@class Encryptor : ShapeClass
---@field encryptions string[]
---@field sv_saved { warehouseIndex: number, charge: number }
---@field sv_parentBody Body
---@field parent Interactable
---@field cl_state boolean
---@field cl_targetWeight number
---@field cl_currentWeight number
---@field cl_openingTimeMultiplier number
---@field cl_closingTimeMultiplier number
---@field cl_easing string
---@field cl_animating boolean
---@field cl_uv number
Encryptor = class()
Encryptor.maxChildCount = 0
Encryptor.maxParentCount = 2
Encryptor.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
Encryptor.connectionOutput = sm.interactable.connectionType.none
Encryptor.colorNormal = sm.color.new(0x189ef5ff)
Encryptor.colorHighlight = sm.color.new(0x3caef8ff)
Encryptor.poseWeightCount = 1

local batterLifeTime = 10 --13 * 40

local function Clamp(val, min, max)
	return (val < min and min or (val > max and max or val))
end

function Encryptor.server_onCreate(self)
	self.encryptions = self.data.encryptions or {}

	self.sv_saved = self.storage:load() or {
		warehouseIndex = self.params and self.params.warehouseIndex or nil,
		charge = 0
	}
	self.storage:save(self.sv_saved)

	self.sv_parentBody = self.shape.body
end

function Encryptor.server_onDestroy(self)
	if sm.exists(self.sv_parentBody) then
		local bodies = self.sv_parentBody:getCreationBodies()
		for _, body in ipairs(bodies) do
			for _, encryption in ipairs(self.encryptions) do
				-- slightly janky calling newindex directly but if the name is invalid it may throw an error
				---@diagnostic disable-next-line:undefined-field
				if not (pcall(body.__newindex, body, encryption, true)) then
					sm.log.error("Encryption '" .. encryption .. "' is not a valid encryption name!")
				end
			end
		end
	end
	self:sv_syncWarehouseRestrictions(false)
end

function Encryptor.server_onFixedUpdate(self, delta)
	local electricityParent = self.interactable:getParents(512)[1]
	local containerParent = electricityParent and electricityParent:getContainer(0)
	if (containerParent or sm.game.getEnableFuelConsumption()) and
	   self.interactable.active and self.sv_saved.charge > 0 then
		self.sv_saved.charge = max(self.sv_saved.charge - 1, 0)

		--Save when 10% of charge is consumed
		if (self.sv_saved.charge / batterLifeTime) % 0.1 == 0 then
			self.storage:save(self.sv_saved)
		end

		if self.sv_saved.charge == 0 then
			if containerParent and containerParent:canSpend(obj_consumable_battery, 1) then
				sm.container.beginTransaction()
				sm.container.spend(containerParent, obj_consumable_battery, 1)
				sm.container.endTransaction()

				self.sv_saved.charge = batterLifeTime
				self.storage:save(self.sv_saved)
			else
				self:sv_setRestrictions(false)
			end
		end
	end

	self.sv_parentBody = self.shape.body

	local logicParent = self.interactable:getParents(1)[1]
	if logicParent then
		if logicParent.active ~= self.interactable.active then
			self:sv_setRestrictions(logicParent.active)
		end
		self.parent = logicParent
	elseif self.parent ~= nil then
		self.parent = nil
		if self.interactable.active then
			self:sv_setRestrictions(false)
		end
	end
end

function Encryptor.sv_setRestrictions(self, isRestricted, sender)
	if isRestricted and self.sv_saved.charge == 0 then
		local electricityParent = self.interactable:getParents(512)[1]
		local containerParent = electricityParent and electricityParent:getContainer(0)
		if containerParent and containerParent:canSpend(obj_consumable_battery, 1) or
		   not containerParent and not sm.game.getEnableFuelConsumption() then
			if containerParent then
				sm.container.beginTransaction()
				sm.container.spend(containerParent, obj_consumable_battery, 1)
				sm.container.endTransaction()
			end

			self.sv_saved.charge = batterLifeTime
			self.storage:save(self.sv_saved)
		else
			if sender then
				self.network:sendToClient(sender, "cl_failedActivate")
			end

			if self.interactable.active then
				self.interactable.active = false
				isRestricted = false
			else
				return
			end
		end
	elseif not isRestricted and not self.interactable.active then
		return
	end

	self.interactable.active = isRestricted
	local bodies = self.shape.body:getCreationBodies()
	for _, body in ipairs(bodies) do
		for _, encryption in ipairs(self.encryptions) do
			-- slightly janky calling newindex directly but if the name is invalid it may throw an error
			---@diagnostic disable-next-line:undefined-field
			if not (pcall(body.__newindex, body, encryption, not isRestricted)) then
				sm.log.error("Encryption '" .. encryption .. "' is not a valid encryption name!")
			end
		end
	end

	local uuid = self.shape:getShapeUuid()
	if uuid == obj_interactive_encryptor_connection then
		if isRestricted then
			sm.effect.playEffect("Encryptor - Activation", self.shape.worldPosition, nil, self.shape.worldRotation)
		else
			sm.effect.playEffect("Encryptor - Deactivation", self.shape.worldPosition, nil, self.shape.worldRotation)
		end
	elseif uuid == obj_interactive_encryptor_destruction then
		if isRestricted then
			sm.effect.playEffect("Barrier - Activation", self.shape.worldPosition, nil, self.shape.worldRotation)
		else
			sm.effect.playEffect("Barrier - Deactivation", self.shape.worldPosition, nil, self.shape.worldRotation)
		end
	end

	self:sv_syncWarehouseRestrictions(isRestricted)
end

function Encryptor.sv_syncWarehouseRestrictions(self, isRestricted)
	-- If the encryptor was loaded as part of a warehouse then it will sync the encryption state to all floors
	if self.sv_saved and self.sv_saved.warehouseIndex ~= nil then
		local restrictions = {}
		for i, encryption in ipairs(self.encryptions) do
			restrictions[encryption] = { name = encryption, state = not isRestricted }
		end

		local params = { warehouseIndex = self.sv_saved.warehouseIndex, restrictions = restrictions }
		sm.event.sendToGame("sv_e_setWarehouseRestrictions", params)
	end
end

function Encryptor.client_onCreate(self)
	self.cl_state = self.interactable.active
	if not self.cl_state then
		self.cl_targetWeight = 1.0
		self.cl_currentWeight = 1.0
		self.interactable:setPoseWeight(0, 1.0)
	else
		self.cl_targetWeight = 0.0
		self.cl_currentWeight = 0.0
	end
	self.cl_openingTimeMultiplier = 0.6
	self.cl_closingTimeMultiplier = 1.3
	self.cl_easing = "easeInCirc"
	--UV stuff
	self.cl_animating = false	--If we are actively changing the pose
	self.cl_uv = 0         		--Current UV frame
end

function Encryptor.client_onUpdate(self, delta)
	if self.interactable.active ~= self.cl_state then
		self.cl_state = self.interactable.active
		if self.cl_state then
			self.cl_targetWeight = 0.0
			self.cl_easing = "easeOutCirc"
		else
			self.cl_targetWeight = 1.0
			self.cl_easing = "easeInCirc"
			--Begin turn off UV animation from the highest UV
			self.cl_uv = 3
		end
	end
	if self.cl_currentWeight > self.cl_targetWeight then
		self.cl_currentWeight = Clamp(self.cl_currentWeight - delta * self.cl_openingTimeMultiplier, 0.0, 1.0)
		self.cl_animating = true
	elseif self.cl_currentWeight < self.cl_targetWeight then
		self.cl_currentWeight = Clamp(self.cl_currentWeight + delta * self.cl_closingTimeMultiplier, 0.0, 1.0)
		self.cl_animating = true
	else
		self.cl_animating = false
	end
	self.interactable:setPoseWeight(0, sm.util.easing(self.cl_easing, self.cl_currentWeight))
end

function Encryptor:client_onFixedUpdate(dt)
	--UV animations
	if self.cl_animating then
		if self.cl_state then
			--Animating and the part is on, activating
			if sm.game.getCurrentTick() % 5 == 0 then
				if self.cl_uv < 3 then
					self.cl_uv = self.cl_uv + 1
				else
					self.cl_uv = 1
				end
			end
		else
			--Animating and the part is off, deactivating
			if sm.game.getCurrentTick() % 15 == 0 then
				if self.cl_uv > 0 then
					self.cl_uv = self.cl_uv - 1
				else
					self.cl_uv = 0
				end
			end
		end
	else
		if self.cl_state then
			--Not animating and the part is on, idling
			if sm.game.getCurrentTick() % 30 == 0 then
				if self.cl_uv < 3 then
					self.cl_uv = self.cl_uv + 1
				else
					self.cl_uv = 1
				end
			end
		else
			--Not animating and the part is off, offline
			self.cl_uv = 0
		end
	end

	self.interactable:setUvFrameIndex(self.cl_uv)
end

function Encryptor.client_canInteract(self)
	return true
end

function Encryptor.client_onInteract(self, char, state)
	if state then
		if self.interactable:getParents(1)[1] then
			sm.gui.displayAlertText("#{ALERT_CONTROL_OVERRIDE}")
			return
		end
		self.network:sendToServer("sv_setRestrictions", not self.interactable.active)
	end
end

function Encryptor:client_getAvailableParentConnectionCount(flags)
	if bit.band(flags, 1) ~= 0 then --logic
		return 1 - #self.interactable:getParents(1)
	elseif bit.band(flags, 512) ~= 0 then --electricity
		return 1 - #self.interactable:getParents(512)
	end
end

function Encryptor:cl_failedActivate()
	sm.gui.displayAlertText("#{INFO_OUT_OF_ENERGY}")
end