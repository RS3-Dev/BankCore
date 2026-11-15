-- Run from the repository root: lua tests/scrollbar_options.lua
id = {
    Inv = { BANK = 95 }, Component = { BANK__BANK_INV = 1, BANK__BANK_ITEMS_CONTAINER = 2 },
    Sprite = setmetatable({}, { __index = function() return 1 end }), StyleSheet = { RECT_BLACK = 269 },
}
Event = { Logic = { Subscribe = function() end, Unsubscribe = function() end } }
Vector4 = { new = function() return {} end }
local controls = {}
local function control()
    local part = { hidden = false }
    function part:SetPos(x, y) self.x, self.y = x, y end
    function part:SetSize(width, height) self.width, self.height = width, height end
    function part:Subscribe() end
    function part:MoveToFront() end
    controls[#controls + 1] = part
    return part
end
ui = { ObjectQuantityDisplayMode = { ALWAYS = 1 }, Sprite = { new = control },
    Rectangle = { new = control }, Hook = {} }
local Pages = require("lib/features/extensions/plugin_pages")
local pages = Pages.new({}, {})
local function spec(value)
    return { id = "test", name = "Test", customView = function() end, alwaysShowScrollbar = value }
end
local default = assert(pages:RegisterOwner(spec(nil)))
assert(default.page.alwaysShowScrollbar == true)
assert(pages:RegisterOwner(spec(true)).page.alwaysShowScrollbar == true)
local input = spec(false)
local custom = assert(pages:RegisterOwner(input))
assert(custom.page.alwaysShowScrollbar == false)
input.alwaysShowScrollbar = true
assert(custom.page.alwaysShowScrollbar == false, "registration copies the option")
for _, invalid in ipairs({ 0, 1, "false", {}, function() end }) do
    local result, reason = pages:RegisterOwner(spec(invalid))
    assert(result == nil and reason == "invalid")
    assert(pages.owners.test == custom, "invalid registration must not replace the current owner")
end
local result, reason = pages:RegisterOwner({ id = "ordinary", name = "Ordinary", alwaysShowScrollbar = false })
assert(result == nil and reason == "invalid", "option is restricted to custom views")

local NativeUi = require("lib/ui/native_ui")
local Scroll = require("lib/engine/bank_page_scroll")
local bar = NativeUi.createScrollbar({}, { height = 200 })
local contentHeight = 50
local display = setmetatable({
    scrollbar = bar, bankView = { shownPage = default.page },
    ContentHeightForCurrentLayout = function() return contentHeight end,
}, { __index = Scroll })
local function check(hidden)
    display:RefreshScrollbar({ scrollY = 0 })
    for _, part in ipairs(controls) do assert(part.hidden == hidden) end
end
check(false) -- Default custom view stays visible with short content.
display.bankView.shownPage = custom.page
check(true)
assert(bar.thumb.height == bar:TrackHeight())
contentHeight = 500
check(false)
assert(bar.thumb.height < bar:TrackHeight())
contentHeight = 200
check(true) -- Exact-fit content does not need scrolling.
display.bankView.shownPage = default.page
check(false) -- Switching views must clear the previous hidden state.
display.bankView.shownPage = { rows = {}, alwaysShowScrollbar = false }
check(false) -- Standard pages keep their scrollbar.
contentHeight = 50
bar:Refresh(contentHeight, 0)
for _, part in ipairs(controls) do assert(part.hidden == false) end
assert(bar:ScrollFromTrack(100, contentHeight) == 0)
print("scrollbar_options: passed")
