-- Load and save the debug setting and sidebar icon order.
local Config = require("lib/core/config")
local PlainData = require("lib/features/extensions/plain_data")
local CorePreferences = {}

-- Keep the order of unloaded plugins too.
local MAX_RAIL_ORDER = 64
local ID_LENGTH = 64
local MAX_BANK_HEIGHT = 100000

local function readBankHeight(value)
    if type(value) ~= "number" or value ~= value or value < 1 or value > MAX_BANK_HEIGHT or value % 1 ~= 0 then
        return nil
    end
    return math.floor(value)
end

function CorePreferences.defaults()
    return { enableDebug = false,
        expansionDirection = "edge", sidebarEdge = "left", sidebarOpeningState = "rail", railPeekEnabled = false,
        sidebarKeybind = { GameKey.CONTROL }, railPeekKeybind = { GameKey.SHIFT }, railOrder = {} }
end

-- Normalize the single runtime opening state.
function CorePreferences.OpeningState(value)
    local state = value.sidebarOpeningState
    return (state == "expanded" or state == "hidden") and state or "rail"
end

-- PrettyUI keybind fields accept up to two distinct GameKey IDs.
function CorePreferences.ReadKeybind(value)
    if type(value) ~= "table" or #value > 2 then return nil end
    local keys, count = {}, 0
    for index, key in pairs(value) do
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #value then return nil end
        if type(key) ~= "number" or key % 1 ~= 0 then return nil end
        local ok, name = pcall(function() return GameKey.FromID(key) end)
        if not ok or name == nil or (index == 2 and key == value[1]) then return nil end
        keys[index], count = key, count + 1
    end
    return count == #value and keys or nil
end

-- Skip invalid or duplicate plugin IDs.
local function readRailOrder(value)
    local railOrder, seen = {}, {}
    if type(value) ~= "table" then return railOrder end
    for _, extensionID in ipairs(value) do
        if #railOrder == MAX_RAIL_ORDER then break end
        if PlainData.ID(extensionID, ID_LENGTH) and not seen[extensionID] then
            seen[extensionID] = true
            railOrder[#railOrder + 1] = extensionID
        end
    end
    return railOrder
end

-- Use defaults for missing or invalid settings.
function CorePreferences.load()
    local value = CorePreferences.defaults()
    local ok, saved = pcall(function()
        return PersistentDB:GetStructuredData(Config.PREFERENCES_KEY)
    end)
    if not ok or type(saved) ~= "table" then return value end
    if type(saved.enableDebug) == "boolean" then value.enableDebug = saved.enableDebug end
    value.expansionDirection = saved.expansionDirection == "evenly" and "evenly" or "edge"
    value.sidebarEdge = saved.sidebarEdge == "right" and "right" or "left"
    value.sidebarOpeningState = CorePreferences.OpeningState(saved)
    -- Migrate old checkboxes only at the persistence boundary.
    if saved.sidebarOpeningState == nil and (saved.startSidebarCollapsed == false
        or (saved.startSidebarCollapsed == nil and saved.collapseSidebar == false)) then
        value.sidebarOpeningState = "expanded"
    end
    value.railPeekEnabled = saved.railPeekEnabled == true
    value.sidebarKeybind = CorePreferences.ReadKeybind(saved.sidebarKeybind) or value.sidebarKeybind
    value.railPeekKeybind = CorePreferences.ReadKeybind(saved.railPeekKeybind) or value.railPeekKeybind
    value.railOrder = readRailOrder(saved.railOrder)
    value.bankHeight = readBankHeight(saved.bankHeight)
    return value
end

function CorePreferences.save(value)
    local defaults = CorePreferences.defaults()
    local keybind = CorePreferences.ReadKeybind(value.sidebarKeybind or defaults.sidebarKeybind)
    local peekKeybind = CorePreferences.ReadKeybind(value.railPeekKeybind or defaults.railPeekKeybind)
    if keybind == nil or peekKeybind == nil then return false end
    local state = CorePreferences.OpeningState(value)
    local ok, saved = pcall(function()
        return PersistentDB:SetStructuredData(Config.PREFERENCES_KEY,
            { enableDebug = value.enableDebug == true,
                expansionDirection = value.expansionDirection == "evenly" and "evenly" or "edge",
                sidebarEdge = value.sidebarEdge == "right" and "right" or "left",
                sidebarKeybind = keybind, railPeekKeybind = peekKeybind,
                sidebarOpeningState = state, railPeekEnabled = value.railPeekEnabled == true,
                railOrder = value.railOrder,
                bankHeight = readBankHeight(value.bankHeight) })
    end)
    return ok and saved ~= false
end
return CorePreferences
