-- Run from the repository root: lua tests/direct_component_lookup.lua
local children = { ALL = 0, BACKGROUND_LAYER = 1, CONTENT = 2,
    PRESET_CLOSE = 86, ALL_TAB_BTN = 166, BANK_ITEMS_CONTAINER = 199, BANK_INV = 201,
    BOTTOM_PANEL_CANCEL = 257, BORDER_LAYER = 311, HELP_BUTTON_LAYER = 312,
    GROUP_IRONMAN_LOADING = 314, COM_315 = 315, GROUP_IRONMAN_SPINNER = 316,
    CLOSE_BUTTON_LAYER = 317, CONFIRM_DROP_ITEM_LAYER = 318, CONFIRM_BACK_RECT = 319,
    CONFIRM_PANEL_CONTAINER = 320, CONFIRM_WITHDRAW_ITEM_LAYER = 330,
    CONFIRM_WITHDRAW_BACK_RECT = 331, CONFIRM_WITHDRAW_PANEL_CONTAINER = 332,
    CUSTOM_X_INPUT_CLICKOUT = 340 }
id = { Component = {}, Inv = { BANK = 95 }, Sprite = {
    BANK_TABS_HORIZONTAL_1 = 8070, BANK_TABS_HORIZONTAL_0 = 8069,
} }
local parts = {}
for name, child in pairs(children) do
    local combined = (517 << 16) | child
    id.Component["BANK__" .. name] = combined
    parts[combined] = { width = 600, height = 400, visible = true, visibleGlobal = true }
end
local bank = id.Component
local calls = {}
ui = { Interfaces = {
    GetInterface = function() error("must not look up an interface") end,
    GetComponent = function(_, combined, ...)
        assert(combined >= (517 << 16), "must use the full component enum")
        local count = select("#", ...)
        assert(count == 0 or count == 2, "use combined ID overloads")
        calls[#calls + 1] = combined
        if count == 2 then
            local category, dynamic = ...
            assert(category == 0)
            if combined == bank.BANK__ALL_TAB_BTN then
                assert(dynamic == 0)
                return { spriteID = 8070 }
            end
            assert(combined == bank.BANK__BOTTOM_PANEL_CANCEL and dynamic == 9)
            return { visible = true, visibleGlobal = true, content = "Cancel Search" }
        end
        return parts[combined]
    end,
} }
package.loaded["lib/ui/ui_coordinates"] = {}
local lookup = require("lib/core/bank_interface")
assert(lookup.Get(lookup.ITEMS) == parts[bank.BANK__BANK_INV])
assert(lookup.Find(lookup.ITEMS_CONTAINER) == parts[bank.BANK__BANK_ITEMS_CONTAINER])
local Window = require("lib/bank/bank_window")
local view = setmetatable({ active = false }, { __index = Window })
assert(view:IsReady())
parts[bank.BANK__CONTENT].hidden = true
local ready, reason = view:IsReady()
assert(not ready and reason == "CONTENT (2) hidden")
parts[bank.BANK__CONTENT].hidden = false
assert(view:DetectNativeViewAll())
assert(view:ReadNativeFilterMode() == "search")
assert(view:IsPresetViewOpen())
print("direct_component_lookup: passed")
