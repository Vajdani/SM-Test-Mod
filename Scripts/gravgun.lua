local BETA = false
local ico_lmb = sm.gui.getKeyBinding("Create", true)
local ico_rmb = sm.gui.getKeyBinding("Attack", true)
local ico_q = sm.gui.getKeyBinding("NextCreateRotation", true)
local gui_intText = sm.gui.setInteractionText
local vec3_up = sm.vec3.new(0,0,1)
local vec3_one = sm.vec3.one()
local vec3_zero = sm.vec3.zero()
local defaultBlockScale = vec3_one * 0.25

Line_grav = class()
function Line_grav:init( thickness, colour )
    self.effect = sm.effect.createEffect("ShapeRenderable")
	self.effect:setParameter("uuid", sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a"))
    self.effect:setParameter("color", colour)
    self.effect:setScale( vec3_one * thickness )

    self.thickness = thickness
	self.spinTime = 0
	self.colour = sm.color.new(0,0,0)
end

---@param startPos Vec3
---@param endPos Vec3
---@param dt number
---@param spinSpeed number
function Line_grav:update( startPos, endPos, dt, spinSpeed )
	local delta = endPos - startPos
    local length = delta:length()

    if length < 0.0001 then
        sm.log.warning("Line_grav:update() | Length of 'endPos - startPos' must be longer than 0.")
        return
	end

	self.dt_sum = (self.dt_sum or 0) + dt
	self.colour = sm.color.new(
		math.abs( math.cos(self.dt_sum) ),
		math.abs( math.sin(self.dt_sum) ),
		math.abs( math.sin(self.dt_sum + 0.5) )
	)
	self.effect:setParameter("color", self.colour)

	local rot = sm.vec3.getRotation(vec3_up, delta)
	local speed = spinSpeed or 1
	self.spinTime = self.spinTime + dt * speed
	rot = rot * sm.quat.angleAxis( math.rad(self.spinTime), vec3_up )

	local distance = sm.vec3.new(self.thickness, self.thickness, length)

	self.effect:setPosition(startPos + delta * 0.5)
	self.effect:setScale(distance)
	self.effect:setRotation(rot)

    if not self.effect:isPlaying() then
        self.effect:start()
    end
end


dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )

---@class Grav : ToolClass
---@field line table
---@field gui GuiInterface
---@field scanUIs table
---@field fpAnimations table
---@field tpAnimations table
---@field deleteEffects table
---@field normalFireMode table
---@field aimBlendSpeed number
---@field blendTime number
---@field isLocal boolean
---@field copyTarget Body|Character
---@field copyTargetGui GuiInterface
---@field oldUuid Uuid
---@field newUuid Uuid
Grav = class()
Grav.raycastRange = 1000
Grav.minHover = 1
Grav.maxHover = 50
Grav.lineColour = sm.color.new(0,1,1)
Grav.modes = {
	["Gravity Gun"] = {
		onEquipped = "cl_mode_grav",
		onToggle = "cl_mode_grav_hoverDec",
		onReload = "cl_mode_grav_hoverInc",
		colour = sm.color.new(1,1,1)
	},
	["Tumbler"] = {
		onEquipped = "cl_mode_tumble",
		colour = sm.color.new(1,0,0)
	},
	["Copy/Paste Object"] = {
		onEquipped = "cl_mode_copyrightInfringement",
		onPrimary = "cl_mode_copyrightInfringement_onClick",
		onSecondary = "cl_mode_copyrightInfringement_reset",
		colour = sm.color.new(1,1,0)
	},
	["Delete Object"] = {
		onEquipped = "cl_mode_delete",
		colour = sm.color.new(0,0,0)
	},
	["Teleport"] = {
		onEquipped = "cl_mode_teleport",
		onToggle = "cl_mode_teleport_resetPlayer",
		colour = sm.color.new(0,1,1)
	},
	["World clear"] = {
		onEquipped = "cl_mode_clear",
		onToggle = "cl_mode_clear_units",
		colour = sm.color.new(0,1,0)
	},
	["Split and Explode"] = {
		onPrimary = "cl_mode_split",
		colour = sm.color.new(0,0,1)
	},
	["Scan"] = {
		onPrimary = "cl_mode_scan_onClick",
		onEquipped = "cl_mode_scan",
		colour = sm.color.new(0.5,0,0.5)
	}
}

if BETA == true then
	Grav.modes["Scalable Wedge Test"] = {
		onEquipped = "cl_mode_scalableWedge",
		onToggle = "cl_mode_scalableWedge_rotate",
		colour = sm.color.new(0.5,1,0.5)
	}
	--[[
	Grav.modes["Block Replacer"] = {
		onPrimary = "cl_mode_blockReplace",
		colour = sm.color.new(1,1,0.5)
	}
	]]
	Grav.modes["Ragdoll Shitter"] = {
		onFixed = "cl_mode_dollShitter_update",
		onEquipped = "cl_mode_dollShitter_equipped",
		onPrimary = "cl_mode_dollShitter_fire",
		onToggle = "sv_wipeDolls",
		colour = sm.color.new(1,0.5,0.5)
	}
	Grav.modes["Export mods with recipes"] = {
		onPrimary = "cl_mode_modRecipes",
		colour = sm.color.new(0.25,0.3,0.69)
	}
	Grav.modes["Export CG's with recipes"] = {
		onPrimary = "cl_mode_cgRecipes",
		colour = sm.color.new(0.75,0.9,0.420)
	}
end

local camAdjust = sm.vec3.new(0,0,0.575)

if Grav.allShapes == nil and BETA == true then
	Grav.allShapes = {}
	Grav.allShapeNames = {}
	local dbPaths = {
		"$GAME_DATA/Objects/Database/shapesets.json",
		"$SURVIVAL_DATA/Objects/Database/shapesets.json",
		"$CHALLENGE_DATA/Objects/Database/shapesets.json"
	}

	for k, dbPath in pairs(dbPaths) do
		local sets = sm.json.open(dbPath).shapeSetList
		for _k, setPath in pairs(sets) do
			local openedSet = sm.json.open(setPath)
			local shapes = openedSet.blockList or openedSet.partList
			for __k, shape in pairs(shapes) do
				local uuid = sm.uuid.new(shape.uuid)
				if sm.item.isBlock(uuid) then
					local name = sm.shape.getShapeTitle(uuid)

					Grav.allShapes[name] = uuid
					Grav.allShapeNames[#Grav.allShapeNames+1] = name
				end
			end
		end
	end
end

local renderables = {
    "$CONTENT_DATA/Objects/mongiconnect.rend"
}
local renderablesTp = {
    "$GAME_DATA/Character/Char_Male/Animations/char_male_tp_connecttool.rend",
    "$GAME_DATA/Character/Char_Tools/Char_connecttool/char_connecttool_tp_animlist.rend"
}
local renderablesFp = {
    "$GAME_DATA/Character/Char_Tools/Char_connecttool/char_connecttool_fp_animlist.rend"
}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

-- #region Server
function Grav:server_onCreate()
	self.sv = {}
	self.sv.target = nil
	self.sv.equipped = false

	self.sv.hoverRange = 5

	self.sv.copyTarget = nil

	self.sv.rotState = false
	self.sv.rotDirection = nil
	self.sv.mouseDelta = { x = 0, y = 0 }

	self.sv.dolls = {}
end

function Grav:sv_targetSelect( target )
	self.sv.target = target
	self.network:sendToClients( "cl_targetSelect", target )
end

function Grav:sv_updateRange( range )
	self.sv.hoverRange = range
end

function Grav:sv_updateEquipped( toggle )
	self.sv.equipped = toggle
	self:sv_setRotState({state = false})
end

function Grav:sv_setRotState( args )
	self.sv.rotState = args.state
	self.sv.rotDirection = args.dir
	self.sv.mouseDelta = { x = 0, y = 0 }
end

function Grav:sv_syncMouseDelta( mouseDelta )
	self.sv.mouseDelta.x = self.sv.mouseDelta.x + mouseDelta[1]
	self.sv.mouseDelta.y = self.sv.mouseDelta.y + mouseDelta[2]
end

function Grav:server_onFixedUpdate()
	local sv = self.sv
	for k, data in pairs(sv.dolls) do
		local char = data.unit:getCharacter()
		if char and not data.appliedImpulse then
			char:setTumbling(true)
			char:applyTumblingImpulse(data.dir * 25 * char.mass)
			data.appliedImpulse = true
		end
	end

	local target = sv.target
	if not target or not sm.exists(target) or not sv.equipped then return end

	---@type Character
	local char = self.tool:getOwner().character
	local dir = sv.rotState and sv.rotDirection or char.direction
	local pos = char.worldPosition + camAdjust + dir * sv.hoverRange

	local targetIsChar = type(target) == "Character"
	local force = pos - (targetIsChar and target.worldPosition or target:getCenterOfMassPosition())
	local mass = target.mass
	force = ((force  * 2) - ( target.velocity--[[@as Vec3]] * 0.3 )) * mass

	if targetIsChar and target:isTumbling() then
		target:applyTumblingImpulse( force )
	else
		sm.physics.applyImpulse( target, force, true )

		if sv.rotState and not targetIsChar then
			local mouseDelta = sv.mouseDelta
			local charDir = sv.rotDirection:rotate(math.rad(mouseDelta.x), vec3_up)
			charDir = charDir:rotate(math.rad(mouseDelta.y), calculateRightVector(charDir))
			local difference = (target.worldRotation * sm.vec3.new(1,0,0)):cross(charDir) --[[@as Vec3]]
			sm.physics.applyTorque(target, ((difference * 2) - ( target.angularVelocity--[[@as Vec3]] * 0.3 )) * mass, true)
		end
	end
end

function calculateRightVector(vector)
    local yaw = math.atan2(vector.y, vector.x) - math.pi / 2
    return sm.vec3.new(math.cos(yaw), math.sin(yaw), 0)
end

function Grav:sv_yeet()
	local force = self.tool:getOwner().character.direction * 100 * self.sv.target.mass

	if type(self.sv.target) == "Character" and self.sv.target:isTumbling() then
		self.sv.target:applyTumblingImpulse( force )
	else
		sm.physics.applyImpulse( self.sv.target, force, true )
	end
	self:sv_targetSelect( nil )

	self:sv_setRotState({state = false})
end

function Grav:sv_targetTumble( target )
	target:setTumbling( true )
end

function Grav:sv_pasteTarget( pos )
	local target
	if type(pos) == "table" then
		target = pos.data
		pos = pos.pos
	else
		target = self.sv.copyTarget
	end

	local type = type(target)
	if type == "string" then
		sm.creation.importFromString(
			self.tool:getOwner().character:getWorld(),
			target,
			pos,
			sm.quat.identity(),
			true
		)
	elseif type == "Uuid" then
		sm.unit.createUnit(target, pos)
	else
		sm.harvestable.create(target[1], pos, sm.vec3.getRotation(sm.vec3.new(0,1,0), vec3_up))
	end
end

function Grav:sv_setCopyTarget( target )
	if type(target) == "Body" then
		self.sv.copyTarget = sm.creation.exportToString( target, false, true )
	else
		self.sv.copyTarget = target
	end
end

function Grav:sv_deleteObject( obj )
	local override, data, pos = false, nil, nil
	local _type = type(obj)
	if _type == "table" then
		override = obj.override
		pos = obj.pos
		obj = obj.obj

		_type = type(obj)
		data = _type == "Body" and sm.creation.exportToString( obj, false, true ) or obj:getCharacterType()
	end

	if _type == "Body" then
		if not override then
			self.network:sendToClients("cl_deleteObject", obj)
		end

		for k, shape in pairs(obj:getCreationShapes()) do
			if sm.item.isBlock(shape.uuid) then
				shape:destroyShape()
			else
				shape:destroyPart()
			end
		end
	elseif _type == "Harvestable" then
		obj:destroy()
	else
		obj:getUnit():destroy()
	end

	if override then
		self:sv_pasteTarget( { pos = pos, data = data  } )
	end
end

function Grav:sv_replaceBlocks( args )
	---@type Body
	local body = args.body
	local new, old = tostring(args.new), tostring(args.old)
	if new == old then return end

	local creation = sm.creation.exportToTable( body, false, true )
	for k, v in pairs(creation.bodies) do
		for i, j in pairs(v.childs) do
			if j.shapeId == old then
				j.shapeId = new
			end
		end
	end

	local world = body:getWorld()
	local pos = body.worldPosition
	for k, v in pairs(body:getCreationShapes()) do
		v:destroyShape()
	end

	sm.json.save(creation, "$CONTENT_DATA/exportedBP.json")
	sm.creation.importFromFile(
		world,
		"$CONTENT_DATA/exportedBP.json",
		pos + sm.vec3.new(0,0,10)
	)
end

function Grav:sv_clear( mode )
	if mode == 1 then
		for k, body in pairs(sm.body.getAllBodies()) do
			for j, shape in pairs(body:getCreationShapes()) do
				if sm.item.isBlock(shape.uuid) then
					shape:destroyShape()
				else
					shape:destroyPart()
				end
			end
		end
	elseif mode == 2 then
		for k, body in pairs(sm.body.getAllBodies()) do
			if body:isDynamic() then
				for j, shape in pairs(body:getCreationShapes()) do
					if sm.item.isBlock(shape.uuid) then
						shape:destroyShape()
					else
						shape:destroyPart()
					end
				end
			end
		end
	elseif mode == 3 then
		for k, unit in pairs(sm.unit.getAllUnits()) do
			unit:destroy()
		end
	end
end

---@param body Body
function Grav:sv_split( body )
	self.network:sendToClients("cl_split", body)

	local center = body:getCenterOfMassPosition()
	for k, shape in pairs(body:getCreationShapes()) do
		--[[
		local pos = shape.worldPosition
		local rot = shape.worldRotation
		local mass = shape.mass
		local uuid = shape.uuid
		local colour = shape.color
		local size = shape:getBoundingBox() * 4
		]]

		shape:destroyShape()

		--[[
		local newShape
		if sm.item.isBlock(uuid) then
			print(size)
			local size_clamped = sm.vec3.new(
				sm.util.clamp(size.x, 1, 69420),
				sm.util.clamp(size.y, 1, 69420),
				sm.util.clamp(size.z, 1, 69420)
			)
			newShape = sm.shape.createBlock(uuid, size_clamped, pos, rot, true, true)
		else
			newShape = sm.shape.createPart(uuid, pos, rot, true, true)
		end
		newShape:setColor(colour)

		sm.physics.applyImpulse(newShape, (pos - center):normalize() * mass * 20, true)
		]]
	end
end

function Grav:sv_scan(pos)
	self.network:sendToClient(self.tool:getOwner(), "cl_mode_scan_recieve", sm.physics.getSphereContacts(pos, 10))
end

function Grav:sv_resetOwner()
	self.tool:getOwner().character:setWorldPosition(vec3_up * 100)
end

function Grav:sv_updateColour(mode)
	self.network:sendToClients("cl_updateColour", mode)
end

function Grav:sv_spawnDoll()
	local owner = self.tool:getOwner().character
	local dir = owner.direction
	local unit = sm.unit.createUnit(unit_mechanic, owner.worldPosition + dir * 2)

	self.sv.dolls[#self.sv.dolls+1] = { unit = unit, dir = dir, appliedImpulse = false }
end

function Grav:sv_tossDoll(doll)
	doll:applyTumblingImpulse(self.tool:getOwner().character.direction * 25 * doll.mass)
end


function Grav:sv_wipeDolls()
	for k, data in pairs(self.sv.dolls) do
		local unit = data.unit
		if sm.exists(unit) then
			unit:destroy()
		end
	end

	self.sv.dolls = {}
end
-- #endregion



function Grav.client_onCreate( self )
	self.isLocal = self.tool:isLocal()
	self.target = nil
	self.line = Line_grav()
	self.line:init( 0.05, self.lineColour )
	self.deleteEffects = {}

	self.mode = "Gravity Gun"
	self.modeData = self.modes[self.mode]

	self:loadAnimations()

    if not self.isLocal then return end
	self.hoverRange = 5
	self.canTriggerFb = true

	self.scanUIs = {}
	self.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/gravgun2.layout", false,
		{
			isHud = false,
			isInteractive = true,
			needsCursor = true,
			hidesHotbar = false,
			isOverlapped = false,
			backgroundAlpha = 0,
		}
	)
	self.gui:setText("Name", "Tool Gun Mode")
	self.gui:setText("SubTitle", "Select mode")
	self.gui:setText("Interaction", "hi")

	local options = {}
	for k, v in pairs(self.modes) do
		options[#options+1] = k
	end
	self.gui:createDropDown( "modes", "cl_gui_modeDropDown", options )
	self.gui:setSelectedDropDownItem( "modes", self.mode )

	if BETA == true then
		self.oldUuid = blk_wood1
		self.newUuid = blk_concrete1
		self.gui:createDropDown( "uuidOld", "cl_gui_oldUuid", self.allShapeNames )
		self.gui:createDropDown( "uuidNew", "cl_gui_newUuid", self.allShapeNames )
		self.gui:setSelectedDropDownItem( "uuidOld", sm.shape.getShapeTitle(self.oldUuid) )
		self.gui:setSelectedDropDownItem( "uuidNew", sm.shape.getShapeTitle(self.newUuid) )
		self.gui:setVisible( "panel_blockReplace", false )
		--self.gui:setMeshPreview( "meshOld", self.oldUuid )
		--self.gui:setMeshPreview( "meshNew", self.newUuid )
	end

	self.copyTarget = nil
	self.copyTargetBodies = nil
	self.copyTargetGui = sm.gui.createWorldIconGui( 50, 50 )
    self.copyTargetGui:setImage( "Icon", "$CONTENT_DATA/Gui/aimbot_marker.png" )

	self.teleportObject = nil

	self.blockF = false

	self.wedgeRot = 0

	self.dollshitTimer = 0
end

function Grav:client_onDestroy()
	self.line.effect:stop()
end

function Grav:cl_gui_modeDropDown( selected )
	self.mode = selected

	local visible = selected == "Block Replacer"
	self.gui:setVisible( "panel_blockReplace", visible )

	self.network:sendToServer("sv_updateColour", self.mode)
end

function Grav:cl_gui_oldUuid( selected )
	self.oldUuid = self.allShapes[selected]
end

function Grav:cl_gui_newUuid( selected )
	self.newUuid = self.allShapes[selected]
end

function Grav:cl_mode_grav( lmb, rmb, f )
	if self.target then
		if rmb == 1 then
			self.blockF = true
			sm.camera.setCameraState(0)
			self.network:sendToServer("sv_yeet")
			sm.gui.displayAlertText("#00ff00Target thrown!", 2.5)
			sm.audio.play("Blueprint - Build")
			return true
		end

		if lmb == 1 then
			self.blockF = true
			self.target = nil
			self.network:sendToServer( "sv_targetSelect", nil )
			sm.gui.displayAlertText("Target cleared!", 2.5)
			sm.audio.play("Blueprint - Delete")

			sm.camera.setCameraState(0)
			self.network:sendToServer("sv_setRotState", {state = false})
			return true
		end
	end

	if self.target then
		local canRotate = type(self.target) == "Body" and BETA == true
		if f and BETA == true then
			gui_intText(
				ico_lmb.."Drop target\t",
				ico_rmb.."Throw target",
				""
			)
			if canRotate then
				gui_intText("<p textShadow='false' bg='gui_keybinds_bg' color='#ffffff' spacing='9'>Move your mouse to rotate the creation</p>")
			end
		else
			gui_intText(
				ico_lmb.."Drop target\t",
				ico_rmb.."Throw target",
				""
			)
			gui_intText(
				sm.gui.getKeyBinding("NextCreateRotation", true).."Decrease distance\t",
				sm.gui.getKeyBinding("Reload", true).."Increase distance\t",
				canRotate and sm.gui.getKeyBinding("ForceBuild", true).."Hold to Rotate Target" or "",
				""
			)
		end

		if canRotate then
			local cam = sm.camera
			if f then
				if cam.getCameraState() ~= 2 then
					cam.setCameraState(2)
					cam.setFov(cam.getDefaultFov())
					self.dir = sm.localPlayer.getDirection()
					self.pos = cam.getDefaultPosition()
					self.network:sendToServer("sv_setRotState", {state = true, dir = self.dir})
				end

				cam.setPosition(self.pos)
				cam.setDirection(self.dir)
			elseif self.dir ~= nil then
				cam.setCameraState(0)
				self.network:sendToServer("sv_setRotState", {state = false})

				self.dir = nil
				self.pos = nil
			end
		end

		return false
	end

	local hit, result = sm.localPlayer.getRaycast( self.raycastRange )
	if not hit then return true end

	local target = result:getBody() or result:getCharacter()
	if not target or type(target) == "Body" and not target:isDynamic() then return true end

	if not self.target then
		gui_intText("", ico_lmb, "Pick up target")
		if lmb == 1  then
			self.target = target
			self.network:sendToServer( "sv_targetSelect", target )
			sm.gui.displayAlertText("#00ff00Target selected!", 2.5)
			sm.audio.play("Blueprint - Camera")
		end
	end

	return true
end

function Grav:cl_mode_grav_hoverInc()
	self.hoverRange = self.hoverRange < self.maxHover and self.hoverRange + 1 or self.maxHover
	sm.gui.displayAlertText("Hover range: #df7f00"..self.hoverRange, 2.5)
	sm.audio.play("Button on")
	self.network:sendToServer("sv_updateRange", self.hoverRange)
end

function Grav:cl_mode_grav_hoverDec()
	self.hoverRange = self.hoverRange > self.minHover and self.hoverRange - 1 or self.minHover
	sm.gui.displayAlertText("Hover range: #df7f00"..self.hoverRange, 2.5)
	sm.audio.play("Button off")
	self.network:sendToServer("sv_updateRange", self.hoverRange)
end

function Grav:cl_mode_tumble(lmb)
	local hit, result = sm.localPlayer.getRaycast( self.raycastRange )
	if not hit then return true end

	local target = result:getCharacter()
	if not target then return true end

	gui_intText("", ico_lmb, "Tumble mob")

	if lmb == 1 then
		self.network:sendToServer( "sv_targetTumble", target )
		sm.gui.displayAlertText("#00ff00Target tumbled!", 2.5)
		sm.audio.play("Blueprint - Open")
	end
end

function Grav:cl_mode_copyrightInfringement()
	local start = sm.localPlayer.getRaycastStart()
	local endPos = start + sm.localPlayer.getDirection() * self.raycastRange
	local hit, result = sm.physics.raycast( start, endPos, sm.localPlayer.getPlayer().character )

	local displayed = ""
	if self.copyTarget then
		if hit then
			displayed = displayed..ico_lmb.."Paste target\t"
		end
		displayed = displayed..ico_rmb.."Clear target"

		gui_intText(displayed, "")
	end

	if not hit then return true end

	local target = result:getBody() or result:getCharacter() or result:getHarvestable()
	local isChar = type(target) == "Character"
	if target == nil or isChar and target:isPlayer() then return true end

	if not self.copyTarget then
		gui_intText("", ico_lmb, "Set target")
	end

	return true
end

function Grav:cl_mode_copyrightInfringement_onClick( override )
	local start = sm.localPlayer.getRaycastStart()
	local endPos = start + sm.localPlayer.getDirection() * self.raycastRange
	local hit, result = sm.physics.raycast( start, endPos, sm.localPlayer.getPlayer().character )

	if self.copyTarget and not override and hit then
		sm.gui.displayAlertText("Pasted Object!", 2.5)
		sm.audio.play("Blueprint - Open")
		self.network:sendToServer("sv_pasteTarget", hit and result.pointWorld or endPos)
		return
	end

	local target = result:getBody() or result:getCharacter() or result:getHarvestable()
	local isChar = type(target) == "Character"
	if target == nil or isChar and target:isPlayer() then return end

	if not override then
		self.copyTarget = target
		if isChar then
			self.network:sendToServer("sv_setCopyTarget", target:getCharacterType())
		elseif type(target) == "Harvestable" then
			self.network:sendToServer("sv_setCopyTarget", { target.uuid })
		else
			self.network:sendToServer("sv_setCopyTarget", target)
			self.copyTargetBodies = target:getCreationBodies()
		end
	else
		sm.gui.displayAlertText("Teleport Object Selected!", 2.5)
		sm.audio.play("Blueprint - Camera")
		return target
	end

	sm.gui.displayAlertText("Copied Object!", 2.5)
	sm.audio.play("Blueprint - Camera")
end

function Grav:cl_mode_copyrightInfringement_reset()
	if not self.copyTarget then return end

	self.copyTarget = nil
	self.copyTargetBodies = nil
	self.network:sendToServer("sv_setCopyTarget", nil)
	sm.gui.displayAlertText("Target cleared!", 2.5)
	sm.audio.play("Blueprint - Delete")
end

function Grav:cl_mode_delete(lmb)
	local hit, result = sm.localPlayer.getRaycast( self.raycastRange )
	if not hit then return true end

	local target = result:getBody() or result:getCharacter() or result:getHarvestable()
	if not target or type(target) == "Character" and target:isPlayer() then return true end

	gui_intText("", ico_lmb, "Delete object")

	if lmb == 1 then
		self.network:sendToServer("sv_deleteObject", target)
		sm.gui.displayAlertText("Object deleted!", 2.5)
		sm.audio.play("Blueprint - Delete")
	end

	return true
end

---@param obj Body
function Grav:cl_deleteObject( obj )
	local scale = 1
	local referencePoint = obj:getCenterOfMassPosition()
	local creation = { data = {}, pos = referencePoint, scale = scale }

	for k, shape in pairs(obj:getCreationShapes()) do
		local uuid = shape.uuid
		local effect = sm.effect.createEffect( "ShapeRenderable" )
		effect:setParameter("uuid", uuid)
		effect:setParameter("color", shape.color)
		local box = sm.item.isBlock(uuid) and shape:getBoundingBox() or defaultBlockScale
		effect:setScale(box * scale)
		effect:setRotation(shape.worldRotation)

		creation.data[#creation.data+1] = {
			effect = effect,
			box = box,
			pos = (shape.worldPosition - referencePoint)
		}
	end

	--[[
	for k, joint in pairs(obj:getCreationJoints()) do
		local uuid = joint.uuid
		local effect = sm.effect.createEffect( "ShapeRenderable" )
		effect:setParameter("uuid", uuid)
		effect:setParameter("color", joint.color)

		local shapeA = joint.shapeA
		local posA = shapeA.worldPosition
		local posB
		if joint.shapeB then
			posB = joint.shapeB.worldPosition
		else
			posB = posA + joint.zAxis
		end

		local pos = (posA + posB) * 0.5
		local dir = sm.vec3.closestAxis((posB - posA):normalize())
		local box = defaultBlockScale
		effect:setScale(box * scale)
		effect:setRotation(sm.vec3.getRotation(vec3_up, dir))

		creation.data[#creation.data+1] = {
			effect = effect,
			box = box,
			pos = (pos - referencePoint + (joint.type == "bearing" and dir * 0.125 or vec3_zero))
		}
	end
	]]

	self.deleteEffects[#self.deleteEffects+1] = creation
end

function Grav:cl_mode_teleport(lmb, rmb)
	self:cl_mode_teleport_organs(lmb, rmb)
	self:cl_mode_teleport_skin()

	return true
end

function Grav:cl_mode_teleport_organs(lmb, rmb)
	if rmb == 2 then
		self.teleportObject = nil
	end

	local hit, result = sm.localPlayer.getRaycast( self.raycastRange )
	if not hit then return true end

	local target = result:getBody() or result:getCharacter()
	if not target and not self.teleportObject then return true end

	if lmb == 1 then
		if self.teleportObject then
			if not hit then return true end
			self.network:sendToServer("sv_deleteObject", { obj = self.teleportObject, override = true, pos = result.pointWorld })
			self.teleportObject = nil
		else
			self.teleportObject = self:cl_mode_copyrightInfringement_onClick( true )
		end
	end
end

function Grav:cl_mode_teleport_skin()
	local hit, result = sm.localPlayer.getRaycast( self.raycastRange )
	local target = result:getBody() or result:getCharacter()

	local displayed = ""
	if hit and target and not self.teleportObject then
		gui_intText("", ico_lmb, "Set target")
	end

	if self.teleportObject then
		if hit then
			displayed = displayed..ico_lmb.." Teleport target to position\t"
		end
		displayed = displayed..ico_rmb.."Clear target"

		gui_intText(displayed, "")
	end

	gui_intText("", ico_q, "Teleport yourself to spawn")
end

function Grav:cl_mode_teleport_resetPlayer()
	self.network:sendToServer("sv_resetOwner")
end

function Grav:cl_mode_blockReplace()
	local hit, result = sm.localPlayer.getRaycast( self.raycastRange )
	if hit and result.type == "body" then
		self.network:sendToServer(
			"sv_replaceBlocks",
			{
				body = result:getBody(),
				old = self.oldUuid,
				new = self.newUuid
			}
		)
	end
end

function Grav:cl_mode_clear( lmb, rmb, f )
	gui_intText(
		ico_lmb.."Clear all bodies\t",
		ico_rmb.."Clear all dynamic bodies",
		""
	)
	gui_intText("", ico_q, "Clear all units")

	if lmb == 1 then
		sm.gui.displayAlertText("#00ff00All bodies cleared!", 2.5)
		sm.audio.play("Blueprint - Delete")
		self.network:sendToServer("sv_clear", 1)
	end

	if rmb == 1 then
		sm.gui.displayAlertText("#00ff00All dynamic bodies cleared!", 2.5)
		sm.audio.play("Blueprint - Delete")
		self.network:sendToServer("sv_clear", 2)
	end

	return true
end

function Grav:cl_mode_clear_units()
	sm.gui.displayAlertText("#00ff00All units cleared!", 2.5)
	sm.audio.play("Blueprint - Delete")
	self.network:sendToServer("sv_clear", 3)
end

function Grav:cl_mode_split()
	local hit, result = sm.localPlayer.getRaycast( self.raycastRange )
	if hit and result.type == "body" then
		self.network:sendToServer("sv_split", result:getBody())
	end
end

---@param body Body
function Grav:cl_split( body )
	local center = body:getCenterOfMassPosition()
	for k, shape in pairs(body:getCreationShapes()) do
		local pos = shape.worldPosition
		sm.debris.createDebris(
			shape.uuid,
			pos,
			shape.worldRotation,
			(pos - center):normalize() * 10,
			vec3_zero,
			shape.color,
			5
		)
	end

	for k, joint in pairs(body:getJoints()) do
		local pos = joint.worldPosition
		sm.debris.createDebris(
			joint.uuid,
			pos,
			joint.localRotation,
			(pos - center):normalize() * 10,
			vec3_zero,
			joint.color,
			5
		)
	end
end

function Grav:cl_mode_scan()
	gui_intText("", ico_lmb, "Scan for mobs and loot")

	return true
end

function Grav:cl_mode_scan_onClick()
	self.network:sendToServer("sv_scan", self.tool:getPosition())
end

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

---@param objs SphereContacts
function Grav:cl_mode_scan_recieve(objs)
	local ignoreChar = self.tool:getOwner().character

	for k, char in pairs(objs.characters) do
		if char ~= ignoreChar then
			local gui = sm.gui.createWorldIconGui(32, 32, "$GAME_DATA/Gui/Layouts/Hud/Hud_WorldIcon.layout", false)
			gui:setImage("Icon", "gui_icon_popup_alert.png")
			gui:setHost(char)
			gui:setMaxRenderDistance(20)
			gui:setRequireLineOfSight(false)
			gui:open()

			local text = sm.gui.createNameTagGui()
			local col = char.color
			local name = charIdToName[tostring(char:getCharacterType())] or "unkown"
			text:setText("Text", "#"..col:getHexStr():sub(1, 6)..name)
			text:setHost(char)
			text:setRequireLineOfSight(false)
			text:setMaxRenderDistance(20)
			text:open()

			self.scanUIs[#self.scanUIs+1] = { gui = gui, text = text, colour = col, host = char }
		end
	end

	for k, hvs in pairs(objs.harvestables) do
		local uuid = hvs.uuid
		if isAnyOf(uuid, {hvs_lootcrate, hvs_lootcrateepic, hvs_loot}) then
			local gui = sm.gui.createWorldIconGui(32, 32, "$GAME_DATA/Gui/Layouts/Hud/Hud_WorldIcon.layout", false)
			gui:setImage("Icon", "gui_icon_popup_alert.png")
			gui:setWorldPosition(hvs.worldPosition)
			gui:setMaxRenderDistance(20)
			gui:setRequireLineOfSight(false)
			gui:open()

			self.scanUIs[#self.scanUIs+1] = { gui = gui, host = hvs }
		end
	end
end

function Grav:cl_mode_scalableWedge(lmb, rmb, f)
	local hit, result = sm.localPlayer.getRaycast(20)
	local canDrag = hit and result.type == "body" and sm.item.isBlock(result:getShape().uuid)
	if canDrag then
		if self.shape then
			gui_intText("Let go of", ico_lmb , "to place wedge")
			gui_intText("", ico_rmb, "Cancel")
		else
			gui_intText("", ico_lmb, "Start placing wedge")
		end
	end

	if lmb == 1 then
		if canDrag then
			self.shape = result:getShape()
			self.localPos = self.shape:getClosestBlockLocalPosition(result.pointWorld) + result.normalLocal
		end
	elseif lmb == 2 and self.shape and canDrag then
		local pos = self.localPos
		local hitShape = self.shape
		if hit and result.type == "body" and self.shape.body == result:getBody() then
			hitShape = result:getShape()
			pos = hitShape:getClosestBlockLocalPosition(result.pointWorld) + result.normalLocal
		end

		local startPos = self:getPos(self.shape, self.localPos)
		local endPos = self:getPos(hitShape, pos)
		sm.particle.createParticle("paint_smoke", startPos)
		sm.particle.createParticle("paint_smoke", endPos, sm.quat.identity(), sm.color.new(0,0,0))

		if not self.wedge then
			self.wedge = sm.effect.createEffect("ShapeRenderable")
			self.wedge:setParameter("uuid", obj_industrial_stairwedge)
			self.wedge:setParameter("visualization", true)
			self.wedge:start()
		end

		local scale = self:clampScale(pos - self.localPos)
		self.wedge:setPosition((startPos + (hitShape.worldRotation * scale) * 0.125))
		self.wedge:setRotation(hitShape.worldRotation * sm.quat.angleAxis(math.rad(90 * self.wedgeRot), hitShape:transformDirection(vec3_up)))
		self.wedge:setScale((self:absVec3(scale) + sm.vec3.one()) * 0.25)
	elseif lmb == 3 then
		self.shape = nil
		self.localPos = nil

		if self.wedge then
			self.wedge:destroy()
			self.wedge = nil
		end
	end

	if rmb == 2 then
		self.shape = nil
		self.localPos = nil

		if self.wedge then
			self.wedge:destroy()
			self.wedge = nil
		end
	end

	return true
end

function Grav:cl_mode_scalableWedge_rotate()
	self.wedgeRot = self.wedgeRot < 3 and self.wedgeRot + 1 or 0
end

function Grav:cl_mode_dollShitter_fire()
	if self.dollshitTimer > 0 then return end

	self.dollshitTimer = 0.2
	self.network:sendToServer("sv_spawnDoll")
end

function Grav:cl_mode_dollShitter_equipped(lmb, rmb, f)
	if lmb == 2  then
		self:cl_mode_dollShitter_fire()
	end

	local displayed = ico_lmb.."Fire Ragdoll\t"
	local hit, result = sm.localPlayer.getRaycast(self.raycastRange)
	if hit then
		local target = result:getCharacter()
		if target and target:getCharacterType() == unit_mechanic then
			displayed = displayed..ico_rmb.."Toss Ragdoll"

			if rmb == 1 then
				self.network:sendToServer("sv_tossDoll", target)
			end
		end
	end

	gui_intText(displayed, "")
	gui_intText("", ico_q, "Clear all ragdolls")

	return true
end

function Grav:cl_mode_dollShitter_update(dt)
	self.dollshitTimer = math.max(self.dollshitTimer - dt, 0)
end

dofile("$CONTENT_40639a2c-bb9f-4d4f-b88c-41bfe264ffa8/Scripts/ModDatabase.lua")
function Grav:cl_mode_modRecipes()
	print("~~[EXPORTING MODS WITH RECIPES]~~")
	local fileExists = sm.json.fileExists
	local foundMods = {}
	ModDatabase.loadDescriptions()

	for uuid, desc in pairs(ModDatabase.databases.descriptions) do
		if desc.type ~= "Custom Game" then
			local key = "$CONTENT_"..uuid
			local success, exists = pcall(fileExists, key)
			if success == true and exists == true then
				local recipes = key.."/CraftingRecipes/"
				if fileExists(recipes) then
					if fileExists(recipes.."craftbot.json") or fileExists(recipes.."workbench.json") or fileExists(recipes.."hideout.json") then
						print("Mod found with recipes!", desc.name)
						foundMods[#foundMods+1] = "https://steamcommunity.com/workshop/filedetails/?id="..desc.fileId
					end
				end
			end
		end
	end

	sm.json.save(foundMods, "$CONTENT_DATA/modsWithRecipes.json")
	sm.gui.displayAlertText("Exported mods with recipes!", 2.5)

	ModDatabase.unloadDescriptions()
end

function Grav:cl_mode_cgRecipes()
	print("~~[EXPORTING CUSTOM GAMES WITH RECIPE SUPPORT]~~")
	local fileExists = sm.json.fileExists
	local foundMods = {}
	ModDatabase.loadDescriptions()

	for uuid, desc in pairs(ModDatabase.databases.descriptions) do
		if desc.type == "Custom Game" then
			local key = "$CONTENT_"..uuid
			local success, exists = pcall(fileExists, key)
			if success == true and exists == true and desc.dependencies then
				for k, dependency in pairs(desc.dependencies) do
					if dependency.fileId == 2504530003 then
						print("Custom Game found with recipe support!", desc.name)
						foundMods[#foundMods+1] = "https://steamcommunity.com/workshop/filedetails/?id="..desc.fileId
					end
				end
			end
		end
	end

	sm.json.save(foundMods, "$CONTENT_DATA/CGsWithRecipeSupport.json")
	sm.gui.displayAlertText("Exported Custom Games with recipe support!", 2.5)

	ModDatabase.unloadDescriptions()
end



---@return Vec3
function Grav:getPos(target, position)
	local A = position * 0.25 --target:getClosestBlockLocalPosition( position )/4
	local B = target.localPosition/4 - sm.vec3.one() * 0.125
	local C = target:getBoundingBox()
	return target:transformLocalPoint( A-(B+C*0.5) )
end

---@return Vec3
function Grav:absVec3(vec3)
	return sm.vec3.new(math.abs(vec3.x), math.abs(vec3.y), math.abs(vec3.z))
end

function Grav:clampScale(vec3)
	return sm.vec3.new(sm.util.clamp(vec3.x, -16, 16), sm.util.clamp(vec3.y, -16, 16), sm.util.clamp(vec3.z, -16, 16))
end

function Grav:cl_targetSelect( target )
	self.target = target
end

function Grav:cl_updateColour(mode)
	if mode then
		self.mode = mode
		self.modeData = self.modes[self.mode]
	end

	local col = self.modeData.colour
	if not col then return end

	self.tool:setTpColor(col)
	if self.isLocal then
		self.tool:setFpColor(col)
	end
end

function Grav.client_onUpdate( self, dt )
	local crouch =  self.tool:isCrouching()
	local equipped = self.tool:isEquipped()

	if self.isLocal then
		if self.target then
			local x, y = sm.localPlayer.getMouseDelta()
			if (x ~= 0 or y ~= 0) and sm.camera.getCameraState() == 2 then
				local sensitivity = sm.localPlayer.getAimSensitivity() * 100
				self.network:sendToServer("sv_syncMouseDelta", { x * sensitivity, y * sensitivity })
			end

			if not sm.exists(self.target) then
				self.target = nil
				self.network:sendToServer( "sv_targetSelect", nil )
			end
		end

		for k, data in pairs(self.scanUIs) do
			local host = data.host
			if not sm.exists(host) then
				data.gui:destroy()
				if data.text then
					data.text:destroy()
				end
				self.scanUIs[k] = nil
			elseif type(host) == "Character" then
				local col = host.color
				if col ~= data.colour then
					data.text:setText("Text", "#"..col:getHexStr():sub(1, 6)..charIdToName[tostring(host:getCharacterType())])
					data.colour = col
				end
			end
		end

		local char = sm.localPlayer.getPlayer().character
		if char then
			if self.copyTarget and sm.exists(self.copyTarget) then
				self.copyTargetGui:setWorldPosition(type(self.copyTarget) == "Body" and self.copyTarget:getCenterOfMassPosition() or self.copyTarget.worldPosition)
				if not self.copyTargetGui:isActive() then self.copyTargetGui:open() end

				if self.copyTargetBodies and equipped then
					sm.visualization.setCreationBodies( self.copyTargetBodies )
					sm.visualization.setCreationFreePlacement( true )

					local start = sm.localPlayer.getRaycastStart()
					local endPos = start + sm.localPlayer.getDirection() * self.raycastRange
					local hit, result = sm.physics.raycast( start, endPos, char )

					if hit then
						sm.visualization.setCreationFreePlacementPosition( result.pointWorld )
						sm.visualization.setCreationValid( true )
						sm.visualization.setCreationVisible( true )
					end
				end
			elseif self.copyTargetGui:isActive() then
				self.copyTargetGui:close()
			end

			if self.teleportObject and sm.exists(self.teleportObject) then
				if equipped and type(self.teleportObject) == "Body" then
					sm.visualization.setCreationBodies( self.teleportObject:getCreationBodies() )
					sm.visualization.setCreationFreePlacement( true )

					local start = sm.localPlayer.getRaycastStart()
					local endPos = start + sm.localPlayer.getDirection() * self.raycastRange
					local hit, result = sm.physics.raycast( start, endPos, char )

					if hit then
						sm.visualization.setCreationFreePlacementPosition( result.pointWorld )
						sm.visualization.setCreationValid( true )
						sm.visualization.setCreationVisible( true )
					end
				end
			elseif self.teleportObject ~= nil then
				self.teleportObject = nil
			end
		end

		self:updateFP(crouch, self.tool:isSprinting(), equipped, dt)
	end

	self:updateTP( crouch, dt )

	if self.target and sm.exists(self.target) then
		if equipped then
			local startPos = self.tool:isInFirstPersonView() and self.tool:getFpBonePos( "pipe" )  or self.tool:getTpBonePos( "pipe" )
			self.line:update( startPos, type(self.target) == "Character" and self.target.worldPosition or self.target:getCenterOfMassPosition(), dt, 100 )

			local col = self.line.colour
			self.tool:setTpColor(col)
			if self.isLocal then
				self.tool:setFpColor(col)
			end
		elseif self.line.effect:isPlaying() then
			self.line.effect:stop()
		end
	elseif self.line.effect:isPlaying() then
		self.line.effect:stop()
	end

	for k, creation in pairs(self.deleteEffects) do
		creation.scale = creation.scale - dt * 5
		if creation.scale <= 0 then
			for i, data in pairs(creation.data) do
				data.effect:destroy()
			end
			table.remove(self.deleteEffects, k)
		else
			local scale = creation.scale
			local creationPos = creation.pos
			for i, data in pairs(creation.data) do
				local effect = data.effect
				effect:setPosition( creationPos + data.pos * scale )
				effect:setScale( data.box * scale )

				if not effect:isPlaying() then
					effect:start()
				end
			end
		end
	end
end

function Grav:client_onFixedUpdate(dt)
	if not self.isLocal then return end

	self:callModeFunction(self.modeData.onFixed, dt)
end

function Grav.client_onEquip( self, animate )
	if animate then
		sm.audio.play( "PotatoRifle - Equip", self.tool:getPosition() )
	end

	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
	self.jointWeight = 0.0

	local currentRenderablesTp = {}
	local currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do
		currentRenderablesTp[#currentRenderablesTp+1] = v
		currentRenderablesFp[#currentRenderablesFp+1] = v
	end

	self.tool:setTpRenderables( currentRenderablesTp )
	if self.isLocal then
		self.tool:setFpRenderables( currentRenderablesFp )
	end

	self:cl_updateColour()

	self:loadAnimations()
	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if self.isLocal then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
		self.network:sendToServer("sv_updateEquipped", true)
	end
end

function Grav.client_onUnequip( self, animate )
	if not sm.exists( self.tool ) then return end

	if animate then
		sm.audio.play( "PotatoRifle - Unequip", self.tool:getPosition() )
	end

	setTpAnimation( self.tpAnimations, "putdown" )

	if self.isLocal then
		self.tool:setMovementSlowDown( false )
		self.tool:setBlockSprint( false )
		self.tool:setCrossHairAlpha( 1.0 )
		self.tool:setInteractionTextSuppressed( false )
		if self.fpAnimations.currentAnimation ~= "unequip" then
			swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
		end

		sm.camera.setCameraState(0)
		self.network:sendToServer("sv_updateEquipped", false)
	end
end

-- #region input
function Grav.cl_onPrimaryUse( self, state )
	if state ~= 1 then return end

	self:callModeFunction(self.modeData.onPrimary)
end

function Grav.cl_onSecondaryUse( self, state )
	if state ~= 1 then return end

	self:callModeFunction(self.modeData.onSecondary)
end

function Grav.client_onEquippedUpdate( self, lmb, rmb, f )
	if lmb ~= self.prevlmb then
		self:cl_onPrimaryUse( lmb )
		self.prevlmb = lmb
	end

	if rmb ~= self.prevrmb then
		self:cl_onSecondaryUse( rmb )
		self.prevrmb = rmb
	end

	local guiToggleEnabled = self:callModeFunction(self.modeData.onEquipped, lmb, rmb, f)
	if guiToggleEnabled == true then
		if f and self.canTriggerFb and not self.blockF then
			self.canTriggerFb = false
			self.gui:open()
		elseif not f then
			self.canTriggerFb = true
			self.blockF = false
		end
	elseif self.gui:isActive() then
		self.gui:close()
	end

	return true, true
end

function Grav:client_onToggle()
	self:callModeFunction(self.modeData.onToggle)

	return true
end

function Grav:client_onReload()
	self:callModeFunction(self.modeData.onReload)

	return true
end


function Grav:callModeFunction(funcName, _1, _2, _3)
	local func = self[funcName]
	if not func then return true end

	if funcName:sub(1,2) == "sv" then
		self.network:sendToServer(funcName)
		return true
	else
		return func( self, _1, _2, _3 )
	end
end
-- #endregion

-- #region animations
function Grav.loadAnimations( self )
	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			idle = { "connecttool_idle" },
			pickup = { "connecttool_pickup", { nextAnimation = "idle" } },
			putdown = { "connecttool_putdown" }
		}
	)
	local movementAnimations = {
		idle = "connecttool_idle",

		sprint = "connecttool_sprint",
		runFwd = "connecttool_run_fwd",
		runBwd = "connecttool_run_bwd",

		jump = "connecttool_jump",
		jumpUp = "connecttool_jump_up",
		jumpDown = "connecttool_jump_down",

		land = "connecttool_jump_land",
		landFwd = "connecttool_jump_land_fwd",
		landBwd = "connecttool_jump_land_bwd",

		crouchIdle = "connecttool_crouch_idle",
		crouchFwd = "connecttool_crouch_fwd",
		crouchBwd = "connecttool_crouch_bwd"
	}

	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	setTpAnimation( self.tpAnimations, "idle", 5.0 )

	if self.isLocal then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "connecttool_pickup", { nextAnimation = "idle" } },
				unequip = { "connecttool_putdown" },

				idle = { "connecttool_idle", { looping = true } },

				sprintInto = { "connecttool_sprint_into", { nextAnimation = "sprintIdle",  blendNext = 0.2 } },
				sprintExit = { "connecttool_sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },
				sprintIdle = { "connecttool_sprint_idle", { looping = true } },
			}
		)
	end

	self.normalFireMode = {
		fireCooldown = 0.20,
		spreadCooldown = 0.18,
		spreadIncrement = 2.6,
		spreadMinAngle = .25,
		spreadMaxAngle = 8,
		fireVelocity = 130.0,

		minDispersionStanding = 0.1,
		minDispersionCrouching = 0.04,

		maxMovementDispersion = 0.4,
		jumpDispersionMultiplier = 2
	}

	self.movementDispersion = 0.0

	self.aimBlendSpeed = 3.0
	self.blendTime = 0.2

	self.jointWeight = 0.0
	self.spineWeight = 0.0
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )

end

function Grav:updateTP( crouch, dt )
	local crouchWeight = crouch and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight

	local totalWeight = 0.0
	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

			if animation.time >= animation.info.duration - self.blendTime then
                if name == "pickup" then
					setTpAnimation( self.tpAnimations, "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 0.001 )
				end
			end
		else
			animation.weight = math.max( animation.weight - ( self.tpAnimations.blendSpeed * dt ), 0.0 )
		end

		totalWeight = totalWeight + animation.weight
	end

	totalWeight = totalWeight == 0 and 1.0 or totalWeight
	for name, animation in pairs( self.tpAnimations.animations ) do
		local weight = animation.weight / totalWeight
		if name == "idle" then
			self.tool:updateMovementAnimation( animation.time, weight )
		elseif animation.crouch then
			self.tool:updateAnimation( animation.info.name, animation.time, weight * normalWeight )
			self.tool:updateAnimation( animation.crouch.name, animation.time, weight * crouchWeight )
		else
			self.tool:updateAnimation( animation.info.name, animation.time, weight )
		end
	end
end

function Grav:updateFP(crouch, sprint, equipped, dt)
	if equipped then
		if sprint and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
			swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
		elseif not sprint and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
			swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
		end
	end
	updateFpAnimations( self.fpAnimations, equipped, dt )


	local dispersion = 0.0
	local fireMode = self.normalFireMode
	if crouch then
		dispersion = fireMode.minDispersionCrouching
	else
		dispersion = fireMode.minDispersionStanding
	end

	if self.tool:getRelativeMoveDirection():length() > 0 then
		dispersion = dispersion + fireMode.maxMovementDispersion * self.tool:getMovementSpeedFraction()
	end

	if not self.tool:isOnGround() then
		dispersion = dispersion * fireMode.jumpDispersionMultiplier
	end

	self.movementDispersion = dispersion
	self.tool:setDispersionFraction( clamp( self.movementDispersion, 0.0, 1.0 ) )
	self.tool:setCrossHairAlpha( 1.0 )
	self.tool:setInteractionTextSuppressed( false )


	local bobbing = 1
	local blend = 1 - (1 - 1 / self.aimBlendSpeed) ^ (dt * 60)
	self.aimWeight = sm.util.lerp( self.aimWeight, 0.0, blend )

	self.tool:updateCamera( 2.8, 30.0, sm.vec3.new( 0.65, 0.0, 0.05 ), self.aimWeight )
	self.tool:updateFpCamera( 30.0, sm.vec3.new( 0.0, 0.0, 0.0 ), self.aimWeight, bobbing )
end
-- #endregion