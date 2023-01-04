---@class BM : ShapeClass
BM = class()
BM.hotbarItems = {
    {
        id = tostring(obj_interactive_button)
    },
    {
        id = tostring(obj_interactive_button)
    },
    {
        id = tostring(blk_wood1),
        gui = "blockSelect",
        lmb = "cl_blockPlace",
        rmb = "cl_blockRemove",
        descriptions = { lmb = "Place block", rmb = "Remove block" }
    },
    {
        id = tostring(blk_concrete1),
        gui = "partSelect",
        lmb = "",
        rmb = "",
        descriptions = { lmb = "Place part", rmb = "Remove part" }
    },
    {
        id = tostring(blk_metal1)
    },
    {
        id = tostring(blk_bricks)
    },
    {
        id = tostring(blk_bubblewrap)
    }
}

local vec3_up = sm.vec3.new(0,0,1)
local vec3_one = sm.vec3.one()
local vec3_zero = sm.vec3.zero()


function BM:server_onCreate()
    self.creation = nil
end

function BM:sv_updateState( args, caller )
    self.network:sendToClients("cl_updateState", caller)
end

---@class BlockPlaceData
---@field block Uuid
---@field pos Vec3
---@field dir Vec3

---@param args BlockPlaceData
function BM:sv_blockPlace( args )
    if not sm.exists(self.creation) then self.creation = nil end

    if self.creation == nil then
        self.creation = sm.body.createBody( self.shape.worldPosition + vec3_up * 5, sm.quat.identity(), false )
        self.creation:setConvertibleToDynamic(false)
        self.creation:createBlock(
            args.block,
            vec3_one,
            vec3_zero
        )

        return
    end

    local pos = args.pos
    local hit, result = sm.physics.raycast(pos, pos + args.dir * 100)
    if hit and result.type == "body" and result:getBody() == self.creation then
        local gridPos, normal = self:getBlockPos(result)
        sm.construction.buildBlock( args.block, gridPos, result:getShape() )
    end
end

function BM:getBlockPos(result)
    local groundPointOffset = -( sm.construction.constants.subdivideRatio_2 - 0.04 + sm.construction.constants.shapeSpacing + 0.005 )
    local pointLocal = result.pointLocal
    if result.type ~= "body" and result.type ~= "joint" then
        pointLocal = pointLocal + result.normalLocal * groundPointOffset
    end

    local n = sm.vec3.closestAxis( result.normalLocal )
    local a = pointLocal * sm.construction.constants.subdivisions - n * 0.5
    local gridPos = sm.vec3.new( math.floor( a.x ), math.floor( a.y ), math.floor( a.z ) ) + n

    return gridPos, result.normalLocal
end

---@param args BlockPlaceData
function BM:sv_blockRemove( args )
    if self.creation == nil then return end

    local pos = args.pos
    local hit, result = sm.physics.raycast(pos, pos + args.dir * 100)
    if hit and result.type == "body" and result:getBody() == self.creation then
        local shape = result:getShape()
        shape:destroyBlock(shape:getClosestBlockLocalPosition(result.pointWorld))
    end
end


function BM:client_onCreate()
    local actions = sm.interactable.actions
    self.controls = {
        false, false, false, false,
        [actions.item0] = false,
        [actions.item1] = false,
    }
    self.controller = nil
    self.zoom = 1
    self.camPos = vec3_zero

    self.mode = 3
    self.hotBar = sm.gui.createSeatGui()
    for k, data in pairs(self.hotbarItems) do
        self.hotBar:setGridItem(
            "ButtonGrid",
            k-1,
            {
                ["itemId"] = data.id,
                ["active"] = k == 3
            }
        )
    end

    self.selectedBlock = blk_wood1
    self.blockSelect = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/buildmode_blockplace.layout")
    self.blockSelect:createGridFromJson(
        --[[
        "inventory",
        {
            type = "materialGrid",
            layout = "$GAME_DATA/Gui/Layouts/Interactable/Interactable_CraftBot_IngredientItem.layout",
            itemWidth = 44,
            itemHeight = 60,
            itemCount = 25,
        }
        ]]
        "inventory",
        {
            type = "itemGrid",
            layout = "$CONTENT_DATA/Gui/buildmode_blockselect_gridItem.layout",
            itemWidth = 75,
            itemHeight = 75,
            itemCount = 25,
        }
    )
    self.blockSelect:setGridButtonCallback( "MainPanel", "cl_blockSelect" )

    local count = 0
    for k, v in pairs(_G) do
        if type(v) == "Uuid" and sm.item.isBlock(v) then
            self.blockSelect:setGridItem(
                "inventory",
                count,
                {
                    itemId = tostring(v),
                    quantity = 1,
                }
            )

            count = count + 1
        end

        if count == 25 then break end
    end

    self.selectedPart = obj_vehicle_smallwheel
    self.partSelect = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/buildmode_blockplace.layout")
    self.partSelect:createGridFromJson(
        "inventory",
        {
            type = "itemGrid",
            layout = "$CONTENT_DATA/Gui/buildmode_blockselect_gridItem.layout",
            itemWidth = 75,
            itemHeight = 75,
            itemCount = 25,
        }
    )
    self.partSelect:setGridButtonCallback( "MainPanel", "cl_partSelect" )

    count = 0
    for k, v in pairs(_G) do
        if type(v) == "Uuid" and not sm.item.isBlock(v) then
            self.partSelect:setGridItem(
                "inventory",
                count,
                {
                    itemId = tostring(v),
                    quantity = 1,
                }
            )

            count = count + 1
        end

        if count == 25 then break end
    end

    self.blockVisualisation = sm.effect.createEffect("ShapeRenderable")
    self.blockVisualisation:setParameter("uuid", blk_plastic)
    self.blockVisualisation:setParameter("visualization", true)
    self.blockVisualisation:setScale(vec3_one*0.25)
end

function BM:client_canInteract()
    return self.controller == nil
end

function BM:client_onInteract( char, state )
    if not state then return end

    char:setLockingInteractable(self.interactable)
    local camPos = sm.camera.getPosition()
    sm.camera.setPosition(camPos)
    self.camPos = camPos
    sm.camera.setDirection(sm.camera.getDirection())
    sm.camera.setCameraState(3)
    sm.camera.setFov(sm.camera.getDefaultFov())
    self.hotBar:open()

    self.network:sendToServer("sv_updateState")
end

function BM:cl_updateState( caller )
    if self.controller ~= nil then
        self.controller = nil
    else
        self.controller = caller
    end
end

function BM:client_onAction( action, state )
    if self.controls[action] ~= nil then
        self.controls[action] = state

        if action == 5 then
            self.hotBar:setGridItem( "ButtonGrid", 0, { ["itemId"] = self.hotbarItems[1].id, ["active"] = state })
        end

        if action == 6 then
            self.hotBar:setGridItem( "ButtonGrid", 1, { ["itemId"] = self.hotbarItems[2].id, ["active"] = state })
        end
    end

    local newMode = action - 4
    if isAnyOf(action, { 7, 8, 9, 10 }) and newMode ~= self.mode then
        self.hotBar:setGridItem( "ButtonGrid", self.mode - 1, { ["itemId"] = self.hotbarItems[self.mode].id, ["active"] = false })
        self.hotBar:setGridItem( "ButtonGrid", newMode - 1, { ["itemId"] = self.hotbarItems[newMode].id, ["active"] = true })

        self.mode = newMode
    end

    if not state then return false end

    if action == 15 then
        sm.localPlayer.getPlayer().character:setLockingInteractable(nil)
        sm.camera.setCameraState(0)
        self.hotBar:close()
        self.network:sendToServer("sv_updateState")
    elseif action == 16 then
        local gui = self.hotbarItems[self.mode].gui
        if gui then
            self[gui]:open()
        end
    elseif action == 18 then
        local func = self.hotbarItems[self.mode].rmb
        if func then
            self[func]( self )
        end
    elseif action == 19 then
        local func = self.hotbarItems[self.mode].lmb
        if func then
            self[func]( self )
        end
    elseif action == 20 then
        self.zoom = sm.util.clamp(self.zoom - 0.1, 0.1, 1)
    elseif action == 21 then
        self.zoom = sm.util.clamp(self.zoom + 0.1, 0.1, 1)
    end

    return true
end

function BM:client_onUpdate(dt)
    local player = sm.localPlayer.getPlayer()
    if self.controller == player then
        local moveSpeed = dt * 10
        local fwd = 0
        if self.controls[3] then fwd = fwd + moveSpeed end
        if self.controls[4] then fwd = fwd - moveSpeed end

        local right = 0
        if self.controls[2] then right = right + moveSpeed end
        if self.controls[1] then right = right - moveSpeed end

        local up = 0
        if self.controls[5] then up = up + moveSpeed end
        if self.controls[6] then up = up - moveSpeed end

        local playerDir = player.character.direction
        self.camPos = self.camPos + playerDir * fwd + calculateRightVector(playerDir) * right + vec3_up * up

        local lerp = dt * 10
        local pos = self.camPos
        local lerpedPos = sm.vec3.lerp(sm.camera.getPosition(), pos, lerp)

        sm.camera.setPosition(lerpedPos)
        sm.camera.setDirection(sm.vec3.lerp(sm.camera.getDirection(), playerDir, lerp))
        sm.camera.setFov(sm.util.lerp(sm.camera.getFov(), sm.camera.getDefaultFov() * self.zoom, lerp))

        local mode = self.hotbarItems[self.mode]
        if mode.gui == "blockSelect" then
            local hit, result = sm.physics.raycast(lerpedPos, lerpedPos + playerDir * 100)
            if hit and result.type == "body" and result:getBody() == self.creation then
                self.blockVisualisation:setPosition(
                    getClosestBlockWorldPosition(result:getShape(), result.pointWorld) + sm.vec3.closestAxis(result.normalLocal) * 0.25
                )

                if not self.blockVisualisation:isPlaying() then
                    self.blockVisualisation:start()
                end
            elseif self.blockVisualisation:isPlaying() then
                self.blockVisualisation:stop()
            end
        elseif self.blockVisualisation:isPlaying() then
            self.blockVisualisation:stop()
        end

        local mouseText = ""
        if mode.lmb then
            mouseText = mouseText..sm.gui.getKeyBinding("Create", true)..mode.descriptions.lmb.."\t"
        end
        if mode.rmb then
            mouseText = mouseText..sm.gui.getKeyBinding("Attack", true)..mode.descriptions.rmb
        end
        sm.gui.setInteractionText("", mouseText, "")

        if mode.gui then
            sm.gui.setInteractionText("", sm.gui.getKeyBinding("Jump", true), "Open gui")
        end
    end
end


function BM:cl_blockSelect( buttonName, gridIndex, gridItemData, gridName )
    self.selectedBlock = sm.uuid.new(gridItemData.itemId)
end

function BM:cl_partSelect( buttonName, gridIndex, gridItemData, gridName )
    self.selectedPart = sm.uuid.new(gridItemData.itemId)
end

function BM:cl_blockPlace()
    self.network:sendToServer("sv_blockPlace",
        {
            pos = self.camPos,
            dir = sm.camera.getDirection(),
            block = self.selectedBlock
        }
    )
end

function BM:cl_blockRemove()
    self.network:sendToServer("sv_blockRemove",
        {
            pos = self.camPos,
            dir = sm.camera.getDirection()
        }
    )
end



function calculateRightVector(vector)
    local yaw = math.atan2(vector.y, vector.x) - math.pi / 2
    return sm.vec3.new(math.cos(yaw), math.sin(yaw), 0)
end

---@return Vec3
function getClosestBlockWorldPosition( target, position )
    local A = target:getClosestBlockLocalPosition( position )/4
    local B = target.localPosition/4 - sm.vec3.new(0.125,0.125,0.125)
    local C = target:getBoundingBox()
    return target:transformLocalPoint( A-(B+C/2) )
end

function roundVector( vec3 )
    return sm.vec3.new(round(vec3.x), round(vec3.y), round(vec3.z))
end