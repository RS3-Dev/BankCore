-- Run from the repository root: lua tests/bank_dialogs.lua
id = { Inv = { BANK = 95 }, Component = { BANK = -1, BANK__ALL = 517 << 16, BANK__CONTENT = (517 << 16) | 2,
    TOPLEVEL_V2__BANK_WINDOW = 1,
    BANKPIN_SETTINGS__MAINMODAL_WINDOW = 2, DIANGO_ITEMS__MAINMODAL_WINDOW = 3,
    SMITHING_HOPPER_READONLY__MAINMODAL_WINDOW = 4 } }
local components = { [1] = { visible = true } }
Player = { IsAvailable = function() return true end }
ui = { Interfaces = { GetComponent = function(_, key) return components[key] end } }
package.loaded["lib/bank/bank_view"] = { new = function() return {} end }
package.loaded["lib/features/extensions/plugin_pages"] = { new = function() return {} end }
package.loaded["lib/core/mini_menu_router"] = { new = function() return {} end }
local Session = require("lib/core/bank_session")
local session = Session.new({ preferences = {}, windowRecord = {} })
local bankIsOpen = session.lifecycle.options.bankIsOpen
components[id.Component.BANK__ALL] = { interfaceID = 517 }
components[id.Component.BANK__CONTENT] = { visible = true, visibleGlobal = true }
local belongsToBank = session.lifecycle.options.selectedEntryBelongsToBank
assert(belongsToBank({ entry = { componentData = { component = { interfaceID = 517 } } } }))
assert(not belongsToBank({ entry = { componentData = { component = { interfaceID = 14 } } } }))
assert(session.lifecycle.options.isBankInventoryEvent({ inv = { id = id.Inv.BANK } }))
assert(not session.lifecycle.options.isBankInventoryEvent({ inv = { id = 96 } }))
assert(bankIsOpen())
components[1].hidden = true
assert(bankIsOpen(), "outer host visibility must not block bank attachment")
components[1].hidden = false
components[1].visibleGlobal = false
assert(bankIsOpen(), "outer host visibility must not block bank attachment")
components[1].visibleGlobal = true

local listeners = {}
Event = {}
for _, name in ipairs({ "Logic", "Draw", "ContentLayerReady", "SettingsLayerReady", "GameStateChanged",
    "MiniMenuReady", "MiniMenuEntrySelected", "InventoryAdded", "InventoryRemoved", "InventoryUpdated", "VarTransmit" }) do
    listeners[name] = {}
    Event[name] = {
        Subscribe = function(key, fn) listeners[name][key] = fn end,
        Unsubscribe = function(key) listeners[name][key] = nil end,
    }
end
local attaches, closes = 0, 0
local owner = { inGame = true, layout = { active = true } }
function owner.layout:IsAttachedToCurrentBank() return self.attached ~= false end
function owner:BeginLayoutRetry() attaches = attaches + 1 end
function owner:CloseBank() closes = closes + 1; self.layout.active = false end
function owner:StopLayoutRetry() end
function owner:RetryLayoutWhenReady() end
function owner:StopFilterSettle() end
function owner:DestroyPanel() end
function owner.layout:Restore() end
owner.layout.windowRecord = { Save = function() end }
local inventoryUpdates = 0
function owner.layout:HandleInventoryUpdate() inventoryUpdates = inventoryUpdates + 1 end
local lifecycle = require("lib/core/lifecycle").new(owner, {
    bankIsOpen = bankIsOpen, isBankInventoryEvent = session.lifecycle.options.isBankInventoryEvent,
})
lifecycle:Start()
assert(attaches == 1)
local function poll()
    for _ = 1, 10 do
        for _, fn in pairs(listeners.Logic) do fn() end
    end
end
for modal = 2, 4 do
    owner.layout.active = true
    components[modal] = { visible = true, visibleGlobal = true }
    components[id.Component.BANK__CONTENT].visibleGlobal = false
    assert(not bankIsOpen())
    poll()
    assert(closes == modal - 1, "opening a dialog must detach without an inventory event")
    poll()
    assert(closes == modal - 1, "do not detach twice")
    components[id.Component.BANK__CONTENT].visibleGlobal = true
    assert(bankIsOpen(), "retained visible dialogs must not block the bank")
    poll()
    assert(attaches == modal, "returning must retry attachment without an inventory event")
    poll()
    assert(attaches == modal, "do not restart attachment while the bank stays open")
end
-- Same-value transmissions also trigger a single deferred rebuild.
local function transmit(name, old, new)
    local variable = setmetatable({ configName = name }, {
        __tostring = function() return "config.VarPlayer." .. name .. "(123)" end,
    })
    for _, fn in pairs(listeners.VarTransmit) do
        fn({ var = variable, oldValue = old, newValue = new })
    end
end
owner.layout.active = true
local before = attaches
local closedBefore = closes
local sidebar, page = {}, {}
owner.layout.sidebarRoot, owner.layout.shownPage = sidebar, page
owner.layout.sidebarMode, owner.layout.scrollY = "selected", 75
for _, callback in pairs(listeners.InventoryUpdated) do
    callback({ inv = { id = id.Inv.BANK } })
    callback({ inv = { id = 858 } })
end
assert(inventoryUpdates == 1, "bank updates still refresh item data")
transmit("CLOCK_TIME_DATE_MINUTES", 1, 2)
assert(listeners.Logic["bankcore_bank_transition"] == nil)
transmit("BANK_TEMP", 65, 65)
transmit("BANK_TEMP", 65, 65)
assert(attaches == before, "must defer until interface changes finish")
listeners.Logic["bankcore_bank_transition"]()
assert(attaches == before and closes == closedBefore,
    "ordinary bank variable updates must preserve the live sidebar")
assert(owner.layout.sidebarRoot == sidebar and owner.layout.shownPage == page
    and owner.layout.sidebarMode == "selected" and owner.layout.scrollY == 75,
    "deposits and withdrawals preserve the sidebar, selection, page and scroll state")
assert(listeners.Logic["bankcore_bank_transition"] == nil)
-- A real replacement still requires one deferred rebuild.
owner.layout.attached = false
transmit("BANK_TEMP", 65, 65)
transmit("BANK_TEMP", 65, 65)
listeners.Logic["bankcore_bank_transition"]()
assert(attaches == before + 1 and closes == closedBefore + 1)
-- Other bank return paths can resend BANK_RESIZE_CYCLE without BANK_TEMP.
owner.layout.active = true
before = attaches
transmit("BANK_RESIZE_CYCLE", -1, -1)
assert(attaches == before, "resize cycle must also defer the rebuild")
listeners.Logic["bankcore_bank_transition"]()
assert(attaches == before + 1, "resize cycle must rebuild without a BANK_TEMP event")
assert(not owner.layout.active, "dispose the old layout before attaching again")
owner.layout.active = true
owner.layout.attached = true
before, closedBefore = attaches, closes
transmit("BANK_RESIZE_CYCLE", -1, -1)
listeners.Logic["bankcore_bank_transition"]()
assert(attaches == before and closes == closedBefore, "resize notifications must preserve a live sidebar")
transmit("BANK_TEMP", 64, 65)
lifecycle:Shutdown()
assert(next(listeners.VarTransmit) == nil, "shutdown must remove variable listener")
assert(next(listeners.Logic) == nil, "shutdown must remove the visibility watcher")

-- Diagnostic attachment failures must report the cause instead of disappearing.
require("lib/core/debug_log").SetEnabled(true)
local messages = {}
log = function(...)
    local parts = {}
    for index = 1, select("#", ...) do parts[index] = tostring(select(index, ...)) end
    messages[#messages + 1] = table.concat(parts)
end
session.inGame = true
session.layout.IsReady = function() return false, "CONTENT (2) hidden" end
session:BeginLayoutRetry()
for _ = 1, 120 do
    for _, fn in pairs(listeners.Logic) do fn() end
end
assert(next(listeners.Logic) == nil)
assert(table.concat(messages, "\n"):find("attachment timed out; last check=CONTENT (2) hidden", 1, true))
-- A Diango return can stay visible while its geometry becomes usable much later.
session:RetryLayoutWhenReady()
assert(next(listeners.Logic) == nil, "do not spin attachment attempts while geometry is unready")
local applications = 0
session.layout.IsReady = function() return true end
session.layout.Apply = function() applications = applications + 1; return true end
session:RetryLayoutWhenReady()
assert(next(listeners.Logic) ~= nil, "late readiness must restart an expired attachment")
for tick = 1, 8 do
    session:BeginLayoutRetry() -- Repeated return signals must not reset consecutive readiness.
    for _, fn in pairs(listeners.Logic) do fn() end
    assert(applications == (tick == 8 and 1 or 0), "attach after eight ready ticks despite duplicate requests")
end
assert(next(listeners.Logic) == nil)
for _, fn in pairs(listeners.Draw) do fn({ timeDeltaSecs = 0.02 }) end
assert(next(listeners.Draw) == nil, "paint timing removes itself after the next draw")
assert(table.concat(messages, "\n"):find("[Bank Core timing] request-to-next-draw", 1, true),
    "report a draw opportunity separately from completed attachment")
-- An explicit reset or close must not be undone by background retries.
session.attachmentWanted = false
session:RetryLayoutWhenReady()
assert(next(listeners.Logic) == nil)
messages = {}
session.layout.IsReady = function() return true end
session.layout.Apply = function() error("sidebar construction failed") end
session:BeginLayoutRetry()
for _ = 1, 8 do
    for _, fn in pairs(listeners.Logic) do fn() end
end
assert(next(listeners.Logic) == nil)
assert(table.concat(messages, "\n"):find("layout application ERROR:", 1, true))
assert(next(listeners.Draw) == nil, "failed attachment cancels its draw timing listener")
print("bank_dialogs: passed")
