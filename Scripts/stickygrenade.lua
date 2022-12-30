Sticky = class()
Sticky.armTime = 40

function Sticky:server_onCreate()
    self.fireTick = sm.game.getServerTick()
end

function Sticky:sv_explode()
    if sm.game.getServerTick() - self.fireTick < self.armTime then return end

    sm.physics.explode( self.shape.worldPosition, 5, 10, 12, 75, "PropaneTank - ExplosionSmall" )
    self.shape:destroyShape()
end

---@param position Vec3
function Sticky:server_onCollision( other, position, selfPointVelocity, otherPointVelocity, normal )
    if self.interactable:getPublicData().placed == true then return end

    local sticky

    if other == nil then
        sticky = sm.shape.createPart(self.shape.uuid, position, sm.quat.identity(), false, true)
    elseif type(other) == "Shape" then
        if sm.item.isBlock(other.uuid) then
            sticky = other.body:createPart(
                self.shape.uuid,
                other:getClosestBlockLocalPosition(position),
                sm.vec3.new(0,0,1),
                sm.vec3.new(1,0,0)
            )
        else
            sticky = other.body:createPart(
                self.shape.uuid,
                other:transformPoint(position),
                sm.vec3.new(0,0,1),
                sm.vec3.new(1,0,0)
            )
        end
    end

    if sticky then
        sm.event.sendToTool( self.interactable:getPublicData().tool, "sv_addSticky", sticky)
        sticky.interactable:setPublicData( { placed = true } )

        self.shape:destroyShape()
    end
end