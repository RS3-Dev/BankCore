-- Run from the repository root: lua tests/return_to_bank.lua
id = { Inv = { BANK = 95 }, Component = { BANK__BANK_INV = 1, BANK__BANK_ITEMS_CONTAINER = 2 } }
local function control(parent)
    local c = { parent = parent, text = {}, hooks = {} }
    function c:SetPos(x, y) self.x, self.y = x, y end
    function c:SetSize(width, height) self.width, self.height = width, height end
    function c:Subscribe(hook, key, callback) self.hooks[hook] = callback or key end
    function c:Unsubscribe(hook) self.hooks[hook] = nil end
    function c:MoveToFront() end
    function c:Destroy() self.destroyed = true end
    return c
end
ui = {
    Hook = setmetatable({}, { __index = function(_, key) return key end }),
    AlignMode = { CENTRE = 1, TOPLEFT = 2 },
    Button = { new = control }, Layer = { new = control },
    Sprite = { new = control }, Rectangle = { new = control },
}
prettyui = { Text = { new = control }, Tooltip = {
    bind = function() end, unbind = function() end,
    registerContext = function() end, unregisterContext = function() end,
} }
prettyui.Sprites = { SPRITE_BUTTONS = {} }
package.loaded["lib/ui/native_ui"] = {
    PANEL_BACKGROUND_SPRITE = 8082, styleID = function() return 318 end,
}
package.loaded["lib/ui/sidebar_tab_rail"] = { new = function(parent, options)
    return {
        root = control(parent), y = options.y, height = options.height,
        SetHeight = function(self, height) self.height = height end,
        SetTabs = function() end, Destroy = function(self) self.destroyed = true end,
    }
end }
-- Exercise the real sidebar and page-close code without game item rendering.
package.loaded["lib/bank/bank_window"] = { install = function() end }
for _, name in ipairs({ "lib/bank/bank_page_items", "lib/bank/bank_item_hover",
    "lib/engine/bank_page_display", "lib/features/extensions/custom_view" }) do
    package.loaded[name] = {}
end
local View = require("lib/bank/bank_view")
local parent = control()
local restored, revoked, changed = 0, 0, 0
local mount = {
    Open = function(self, _, _, bounds) self.bounds = bounds; return true end,
    Resize = function(self, bounds) self.bounds = bounds end,
    IsMounted = function() return true end,
    Close = function(self) self.closed = true end,
}
local view = setmetatable({
    active = true, pageTransitions = 0, components = { all = parent },
    extensionTabs = { { id = "selected", mount = mount } }, sidebarMode = "selected",
    pageState = { Restore = function() restored = restored + 1 end },
    pageDisplay = { DestroyRuntimeSprites = function() end },
    itemHover = { RemovePageInput = function() end, RestoreBankItemPositions = function() end },
    onChange = function() changed = changed + 1 end,
}, { __index = View })
view:CreateSidebar(parent, 604)
local button = view.returnToBankButton
assert(button.root.text.content == "Return to Bank")
assert(button.icon == nil, "return button displays text only")
assert(button.root.x == 52 and button.root.y == 44)
assert(button.root.width == 236 and button.root.height == 32)
assert(view.tabRail.y == 44 and view.tabRail.height == 604, "icon rail retains its top and height")
assert(button.root.y == view.tabRail.y, "return button aligns with the top rail icon")
assert(button.root.x == view.rail.x and button.root.width == view.rail.width,
    "return button fills the sidebar column without side padding")
assert(view.rail.y == 80 and view.rail.height == 568, "plugin column gains the removed top padding")
assert(mount.bounds.height == 566 and mount.bounds.y == 1)
assert(button.disabled and not button.root.enabled)
button.root.hooks.ONBUTTONPRESSED()
assert(restored == 0, "native-bank button is disabled")

for _, custom in ipairs({ false, true }) do
    view.shownPage = { title = "Plugin page", owner = { id = "example" } }
    if custom then view.customView = { Revoke = function() revoked = revoked + 1 end } end
    view:UpdateLayoutControls()
    assert(not button.disabled and button.root.enabled)
    button.root.hooks.ONBUTTONPRESSED()
    assert(view.shownPage == nil and view.customView == nil)
    assert(button.disabled and not button.root.enabled)
    assert(view.sidebarMode == "selected" and view.tabMount == mount,
        "returning keeps the selected plugin's sidebar")
end
assert(restored == 2 and revoked == 1 and changed == 2)
view:ResizeSidebar(500)
assert(view.tabRail.height == 500 and view.rail.height == 464 and mount.bounds.height == 462)
assert(view.rail.y == 80 and button.root.y == 44)
view.shownPage = {}
view.pageTransitions = 1
assert(not view:ReturnToBank(), "ignore clicks during a page transition")
assert(restored == 2)
local root = button.root
view:DestroySidebar()
assert(root.destroyed and view.returnToBankButton == nil and mount.closed)
assert(view.rail == nil and view.tabRail == nil)
print("return_to_bank: passed")
