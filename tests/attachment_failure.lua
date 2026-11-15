-- Run from the repository root: lua tests/attachment_failure.lua
local children = { ALL = 0, BACKGROUND_LAYER = 1, CONTENT = 2,
    PRESET_CLOSE = 86, ALL_TAB_BTN = 166, BANK_ITEMS_CONTAINER = 199, BANK_INV = 201,
    BOTTOM_PANEL_CANCEL = 257, BORDER_LAYER = 311, HELP_BUTTON_LAYER = 312,
    GROUP_IRONMAN_LOADING = 314, COM_315 = 315, GROUP_IRONMAN_SPINNER = 316,
    CLOSE_BUTTON_LAYER = 317, CONFIRM_DROP_ITEM_LAYER = 318, CONFIRM_BACK_RECT = 319,
    CONFIRM_PANEL_CONTAINER = 320, CONFIRM_WITHDRAW_ITEM_LAYER = 330,
    CONFIRM_WITHDRAW_BACK_RECT = 331, CONFIRM_WITHDRAW_PANEL_CONTAINER = 332,
    CUSTOM_X_INPUT_CLICKOUT = 340 }
id = { Inv = { BANK = 95 }, Component = { TOPLEVEL_V2__BANK_WINDOW = 99 },
    Sprite = setmetatable({ BANK_TABS_HORIZONTAL_1 = 8070, BANK_TABS_HORIZONTAL_0 = 8069 },
        { __index = function() return 1 end }), StyleSheet = { RECT_BLACK = 269, BUTTON_PANEL = 318 } }
for name, child in pairs(children) do id.Component["BANK__" .. name] = (517 << 16) | child end
local listeners, native, created, fault = {}, {}, {}, {}
local function fail(stage)
    if fault.stage == stage then fault.stage = nil; error("injected " .. stage .. " failure") end
end
local function component(parent)
    local c = { parent = parent, children = {}, text = {}, hooks = {}, interfaceID = 517,
        hidden = false, visible = true, visibleGlobal = true, x = 0, y = 0, width = 800, height = 604,
        position = { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        size = { width = 800, height = 604, widthParentPc = 0, heightParentPc = 0 } }
    if parent then parent.children[#parent.children + 1] = c end
    function c:SetSize(width, height, parentWidth, parentHeight)
        if self == native[99] then fail("resize") end
        if self.parent == native[id.Component.BANK__ALL] then fail("root sizing") end
        self.size = { width = width, height = height,
            widthParentPc = parentWidth or 0, heightParentPc = parentHeight or 0 }
        self.width = width + (self.parent and self.parent.width or 0) * (parentWidth or 0)
        self.height = height + (self.parent and self.parent.height or 0) * (parentHeight or 0)
    end
    function c:SetPos(x, y, parentX, parentY, selfX, selfY)
        if self == native[99] then fail("position after resize") end
        self.x, self.y = x, y
        self.position = { x = x, y = y, xParentPc = parentX or 0, yParentPc = parentY or 0,
            xSelfPc = selfX or 0, ySelfPc = selfY or 0 }
    end
    function c:Subscribe(hook, key, callback) self.hooks[hook] = callback or key end
    function c:Unsubscribe(hook) self.hooks[hook] = nil end
    function c:MoveToFront() end
    function c:Destroy()
        self.destroyed = true
        for _, child in ipairs(self.children) do child:Destroy() end
    end
    return c
end
native[99] = component()
for _, childID in pairs(id.Component) do
    if childID ~= 99 then native[childID] = component(native[99]) end
end
local function constructor(kind)
    return function(parent)
        local c = component(parent)
        created[#created + 1] = c
        fail(kind) -- Throw after creating the native control, before returning its handle.
        return c
    end
end
ui = {
    Interfaces = { GetComponent = function(_, combined, category)
        if category ~= nil then return { spriteID = 8070 } end
        return native[combined]
    end },
    Hook = setmetatable({}, { __index = function(_, key) return key end }),
    AlignMode = { CENTRE = 1, TOPLEFT = 2 },
    Layer = { new = constructor("layer") }, Button = { new = constructor("button") },
    Sprite = { new = constructor("sprite") }, Rectangle = { new = constructor("rectangle") },
}
prettyui = { Text = { new = constructor("text") }, Tooltip = {
    registerContext = function() end, unregisterContext = function() end,
} }
Event = { Logic = {
    Subscribe = function(key, callback) listeners[key] = callback end,
    Unsubscribe = function(key) listeners[key] = nil end,
} }
package.loaded["lib/bank/bank_page_items"] = { new = function()
    return { Restore = function() end }
end }
package.loaded["lib/bank/bank_item_hover"] = { new = function()
    return {
        RemovePageInput = function() fail("input cleanup") end,
        RestoreBankItemPositions = function() end, CancelMissingStackRetry = function() end,
    }
end }
package.loaded["lib/engine/bank_page_display"] = { new = function()
    return { DestroyRuntimeSprites = function() end }
end }
local View = require("lib/bank/bank_view")
local baseline = {}
for key, c in pairs(native) do baseline[key] = { x = c.x, width = c.width } end
local function checkGeometry()
    for key, c in pairs(native) do
        assert(c.x == baseline[key].x and c.width == baseline[key].width,
            "restore bank geometry for component " .. key)
    end
end
for _, stage in ipairs({ "selection", "resize", "position after resize", "save", "root sizing",
    "button", "sprite", "rectangle", "text", "watcher", "cleanup" }) do
    local record = { Save = function() fail("save") end }
    local view = View.new({ windowRecord = record })
    -- Seed an older geometry record to ensure early failures do not shrink an unexpanded bank.
    assert(view:Apply())
    assert(view:IsAttachedToCurrentBank())
    local contentID = id.Component.BANK__CONTENT
    local currentContent = native[contentID]
    native[contentID] = component(native[99])
    assert(not view:IsAttachedToCurrentBank(), "detect replacement bank components")
    native[contentID] = currentContent
    view.sidebarRoot.hidden = true
    assert(not view:IsAttachedToCurrentBank(), "detect a lost or hidden sidebar")
    view.sidebarRoot.hidden = false
    view:Restore()
    checkGeometry()
    local start = #created
    if stage == "selection" then
        local detect = view.DetectNativeViewAll
        view.DetectNativeViewAll = function(self) fail("selection"); return detect(self) end
    elseif stage == "watcher" then
        local watch = view.StartBankWindowWatch
        view.StartBankWindowWatch = function(self) watch(self); fail("watcher") end
    elseif stage == "cleanup" then
        local create = view.CreateSidebar
        view.CreateSidebar = function(self, ...)
            create(self, ...)
            fault.stage = "input cleanup"
            error("injected original construction failure")
        end
    end
    fault.stage = stage
    local ok, message = pcall(function() view:Apply() end)
    assert(not ok, "injected failure must be reported: " .. stage)
    assert(not view.active and not view.expanded and not view.nativeViewAll)
    assert(view.sidebarRoot == nil and view.returnToBankButton == nil and view.tabRail == nil)
    assert(view.rail == nil and view.expansion == nil and next(view.components) == nil)
    assert(next(listeners) == nil, "remove watchers even when they were partially started")
    for index = start + 1, #created do assert(created[index].destroyed, "remove partial controls") end
    checkGeometry()
    if stage == "cleanup" then
        assert(tostring(message):find("original construction failure", 1, true), "preserve the build error")
        view.CreateSidebar = nil
    end
    fault.stage = nil
    assert(view:Apply(), "a later attachment must genuinely rebuild")
    assert(view.active and view.expanded and view.sidebarRoot ~= nil and not view.sidebarRoot.destroyed)
    view:Restore()
    checkGeometry()
end
print("attachment_failure: passed (11 build stages, partial UI, geometry rollback and retry)")
