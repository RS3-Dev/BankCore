-- Run from the repository root: lua tests/tooltip.lua
local loaded = true
ui = { Interfaces = { GetInterface = function() return loaded and {} or nil end } }
local context, lastHandlers
prettyui = { Tooltip = {
    getContext = function() return context end,
    attach = function(target, parent, options, handlers)
        assert(options.alignment == nil, "do not depend on an added PrettyUI option")
        lastHandlers = handlers
        local overlay = options.parent or (context and context.parent) or parent
        local attachment = { width = options.width or #options.text * 5 + 16,
            height = options.height or 30, root = { hidden = true } }
        function attachment:Show()
            local margin = options.boundsMargin or 6
            self.root.x = math.max(margin, math.min(options.x, overlay.width - self.width - margin))
            self.root.y = math.max(margin, math.min(options.y, overlay.height - self.height - margin))
            self.root.hidden = false
        end
        function attachment:Hide() self.root.hidden = true end
        function attachment:SetText(text)
            self.width = options.width or #text * 5 + 16
            return true
        end
        function attachment:Destroy() self.root = nil end
        return attachment
    end,
} }
local Tooltip = require("lib/ui/tooltip")
local parent = { width = 600, height = 400, interfaceID = 1 }
local target = { x = 200, y = 100, width = 32, height = 32, interfaceID = 1, parent = parent }
local options = { text = "Item", width = 160, height = 30 }
local tooltip = Tooltip.attach(target, parent, options)
lastHandlers.onMouseOver()
local root = tooltip.attachment.root
assert(root.x == 136 and root.y == 138, "center beneath the sprite on hover")
assert(options.x == nil and options.y == nil, "do not mutate the caller's options")
lastHandlers.onMouseLeave()
assert(root.hidden)
target.y = 360
tooltip:Show()
assert(root.x == 136 and root.y == 324, "flip above while preserving centering")
target.x, target.y = 0, 100
tooltip:Show()
assert(root.x == 6 and root.y == 138, "stay below at the left edge")
target.x = 580
tooltip:Show()
assert(root.x == 434 and root.y == 138, "stay below at the right edge")
tooltip:Destroy()
tooltip:Destroy()
assert(tooltip.attachment == nil)
context = { active = true, parent = parent, position = function() return 200, 100 end }
tooltip = Tooltip.attach(target, {}, "Item")
tooltip:Show()
root = tooltip.attachment.root
assert(root.x + tooltip.attachment.width / 2 == 216 and root.y == 138,
    "use the overlay context's coordinates")
assert(tooltip:SetText("Longer item name"))
assert(root.x + tooltip.attachment.width / 2 == 216, "recenter after text changes width")
loaded = false
tooltip:Show()
assert(not tooltip:SetText("Unloaded"), "do not update unloaded native components")
tooltip:Hide()
tooltip:Destroy()
assert(Tooltip.attach(target, parent, nil) == nil)
print("tooltip: passed")
