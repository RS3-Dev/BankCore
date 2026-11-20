-- Load and save the debug setting and sidebar icon order.
local Config = require("lib/core/config")
local PlainData = require("lib/features/extensions/plain_data")
local CorePreferences = {}

-- Keep the order of unloaded plugins too.
local MAX_RAIL_ORDER = 64
local ID_LENGTH = 64

function CorePreferences.defaults()
    return { enableDebug = false, collapseSidebar = true, startSidebarCollapsed = true,
        expansionDirection = "left", railOrder = {} }
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
    if type(saved.collapseSidebar) == "boolean" then value.collapseSidebar = saved.collapseSidebar end
    if type(saved.startSidebarCollapsed) == "boolean" then value.startSidebarCollapsed = saved.startSidebarCollapsed end
    if saved.expansionDirection == "left" or saved.expansionDirection == "evenly" then
        value.expansionDirection = saved.expansionDirection
    end
    value.railOrder = readRailOrder(saved.railOrder)
    return value
end

function CorePreferences.save(value)
    local ok, saved = pcall(function()
        return PersistentDB:SetStructuredData(Config.PREFERENCES_KEY,
            { enableDebug = value.enableDebug == true, collapseSidebar = value.collapseSidebar == true,
                startSidebarCollapsed = value.startSidebarCollapsed == true,
                expansionDirection = value.expansionDirection == "evenly" and "evenly" or "left",
                railOrder = value.railOrder })
    end)
    return ok and saved ~= false
end
return CorePreferences
