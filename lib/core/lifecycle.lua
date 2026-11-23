-- Start and stop the bank session's game event listeners.

local Config = require("lib/core/config")
local DebugLog = require("lib/core/debug_log")
local debugLog = DebugLog.Write

local Lifecycle = {}
Lifecycle.__index = Lifecycle

local MENU_EVENT = Config.CORE_REF .. "_menu"
local BANK_ACTION_EVENT = Config.CORE_REF .. "_bank_action"
local BANK_OPEN_EVENT = Config.CORE_REF .. "_bank_open"
local BANK_CLOSE_EVENT = Config.CORE_REF .. "_bank_close"
local BANK_UPDATE_EVENT = Config.CORE_REF .. "_bank_update"
local GAME_STATE_EVENT = Config.CORE_REF .. "_game_state"
local BANK_DRAW_VISIBILITY_EVENT = Config.CORE_REF .. "_bank_draw_visibility"
local SETTINGS_EVENT = Config.CORE_REF .. "_settings"
local BANK_KEYBIND_EVENT = Config.CORE_REF .. "_sidebar_keybind"

function Lifecycle.new(session, options)
    return setmetatable({
        session = session,
        options = options or {},
    }, Lifecycle)
end

function Lifecycle:Start()
    local session = self.session
    local options = self.options
    Event.Logic.Subscribe(BANK_KEYBIND_EVENT, function() session:CheckSidebarKeybind() end)
    Event.SettingsLayerReady.Subscribe(SETTINGS_EVENT, function(event)
        session:CreateContentLayer(event.component, nil, nil, nil, true)
    end)

    Event.GameStateChanged.Subscribe(GAME_STATE_EVENT, function(event)
        if event.newState == GameState.GAME then
            session:ResumeGameUI()
        else
            session:SuspendGameUI()
        end
    end)
    Event.MiniMenuReady.Subscribe(MENU_EVENT, function(event)
        session.menuRouter:HandleMenu(event)
    end)
    Event.MiniMenuEntrySelected.Subscribe(BANK_ACTION_EVENT, function(event)
        local selectedBankTab = options.bankViewSelection(event)
        if session.inGame and selectedBankTab ~= nil then
            local entry = event.entry
            session.layout.itemHover:RestoreHoveredBankStack()
            if session.layout.shownPage ~= nil then session.layout:ShowPage(nil) end
            session.layout:SetNativeViewAll(selectedBankTab == "all")
            debugLog("Bank Core returned control to the native bank after ",
                entry.verbText, " ", entry.subjectText)
            return
        end
        if session.inGame and options.selectedEntryBelongsToBank(event) then
            -- Menu actions can change bank state; item changes arrive through InventoryUpdated.
            session.layout:Changed(false)
        end
    end)

    Event.InventoryAdded.Subscribe(BANK_OPEN_EVENT, function(event)
        if session.inGame and options.isBankInventoryEvent(event) then
            session:AttachFromInventory()
        end
    end)
    Event.InventoryRemoved.Subscribe(BANK_CLOSE_EVENT, function(event)
        if session.inGame and options.isBankInventoryEvent(event) then
            session:CloseBank()
        end
    end)
    Event.InventoryUpdated.Subscribe(BANK_UPDATE_EVENT, function(event)
        if session.inGame and options.isBankInventoryEvent(event) then
            session.layout:HandleInventoryUpdate()
        end
    end)
    -- A reload can start Core while the bank is already open.
    if session.inGame then
        local ok, open = pcall(options.bankIsOpen)
        if ok and open then session:BeginLayoutRetry() end
    end
    -- Detached classic controls do not inherit the native bank's visibility.
    Event.Draw.Subscribe(BANK_DRAW_VISIBILITY_EVENT, function()
        local layout = session.layout
        if layout == nil or not layout.active or not layout.detachedSidebar then return end
        local ok, open = pcall(options.bankIsOpen)
        open = session.inGame and ok and open
        local hidden = layout.IsSidebarHidden ~= nil and layout:IsSidebarHidden()
        for _, name in ipairs({ "sidebarRoot", "sidebarOverlay", "sidebarTooltipOverlay" }) do
            local layer = layout[name]
            if layer ~= nil then pcall(function() layer.hidden = not open or hidden end) end
        end
        -- Follow opening geometry before drawing; hiding must not depend on positioning.
        if open and not hidden then pcall(function() layout:PositionDetachedSidebar() end) end
    end)
    debugLog("Bank Core started its bank session")
end

function Lifecycle:Shutdown()
    local session = self.session
    if session.shutDown then return end
    session.shutDown = true

    -- Continue restoring the bank after cleanup errors.
    local function cleanup(label, action)
        local ok, message = pcall(action)
        if not ok then
            debugLog("Bank Core shutdown could not clean ", label, ": ", message)
        end
    end

    Event.MiniMenuReady.Unsubscribe(MENU_EVENT)
    Event.MiniMenuEntrySelected.Unsubscribe(BANK_ACTION_EVENT)
    Event.GameStateChanged.Unsubscribe(GAME_STATE_EVENT)
    Event.InventoryAdded.Unsubscribe(BANK_OPEN_EVENT)
    Event.InventoryRemoved.Unsubscribe(BANK_CLOSE_EVENT)
    Event.InventoryUpdated.Unsubscribe(BANK_UPDATE_EVENT)
    Event.Logic.Unsubscribe(BANK_KEYBIND_EVENT)
    Event.SettingsLayerReady.Unsubscribe(SETTINGS_EVENT)
    Event.Draw.Unsubscribe(BANK_DRAW_VISIBILITY_EVENT)
    session:StopLayoutRetry()

    cleanup("core panel", function() session:DestroyPanel() end)
    local bankView = session.layout
    if bankView == nil then return end
    cleanup("bank layout", function() bankView:Restore() end)
    -- Save last to include any remaining window changes.
    cleanup("bank window record", function() bankView.windowRecord:Save() end)
    session.layout = nil
end

return Lifecycle
