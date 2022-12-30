---@class CamChild : ShapeClass
CamChild = class()
CamChild.maxParentCount = -1
CamChild.maxChildCount = 0
CamChild.connectionInput = sm.interactable.connectionType.logic
CamChild.connectionOutput = sm.interactable.connectionType.logic
CamChild.colorNormal = sm.color.new( "#f0a0bf" )
CamChild.colorHighlight = sm.color.new( "#f1a0bf" )