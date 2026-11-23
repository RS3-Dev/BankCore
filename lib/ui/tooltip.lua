-- Position Core's tooltips using the published PrettyUI renderer.

local UICoordinates = require("lib/ui/ui_coordinates")

local Tooltip = {}
Tooltip.__index = Tooltip
local GAP = 6

function Tooltip.attach(target, parent, value)
    if value == nil then return nil end
    local options = {}
    if type(value) == "table" then
        for key, option in pairs(value) do options[key] = option end
    else
        options.text = tostring(value)
    end
    if options.categoryID == nil then options.categoryID = "auto" end
    local context = prettyui.Tooltip.getContext(parent)
    local overlay = options.parent or (context and context.parent) or parent
    local self = setmetatable({
        target = target, parent = overlay, context = options.parent == nil and context or nil,
        targetInterfaceID = target.interfaceID, interfaceID = overlay.interfaceID,
        options = options, explicitX = options.x, explicitY = options.y,
    }, Tooltip)
    self.attachment = prettyui.Tooltip.attach(target, parent, options, {
        onMouseOver = function() self:Show() end,
        onMouseLeave = function() self:Hide() end,
    })
    return self
end

-- Center beneath the target, flipping above when the window has no room below.
function Tooltip:Show()
    local tooltip = self.attachment
    if tooltip == nil or tooltip.root == nil
        or ui.Interfaces:GetInterface(self.interfaceID) == nil
        or ui.Interfaces:GetInterface(self.targetInterfaceID) == nil then return end
    local x, y
    if self.context ~= nil and self.context.active then
        x, y = self.context.position(self.target)
    else
        x, y = UICoordinates.relativePosition(self.target, self.parent)
    end
    if x == nil then return end
    local margin = self.options.boundsMargin or GAP
    local below = y + self.target.height + GAP
    if self.parent.height > 0 and below + tooltip.height > self.parent.height - margin then
        below = y - tooltip.height - GAP
    end
    self.options.x = self.explicitX or math.floor(x + (self.target.width - tooltip.width) / 2)
    self.options.y = self.explicitY or below
    tooltip:Show()
end

function Tooltip:SetText(text)
    if self.attachment == nil or self.attachment.root == nil
        or ui.Interfaces:GetInterface(self.interfaceID) == nil then return false end
    local updated = self.attachment:SetText(text)
    if updated and self.attachment.root.hidden ~= true then self:Show() end
    return updated
end

function Tooltip:Hide()
    if self.attachment ~= nil and self.attachment.root ~= nil
        and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.attachment:Hide() end
end

function Tooltip:Destroy()
    local tooltip = self.attachment
    self.attachment = nil
    if tooltip ~= nil then pcall(function() tooltip:Destroy() end) end
end

return Tooltip
