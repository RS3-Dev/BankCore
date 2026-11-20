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
local BANK_VISIBILITY_EVENT = Config.CORE_REF .. "_bank_visibility"
local BANK_DRAW_VISIBILITY_EVENT = Config.CORE_REF .. "_bank_draw_visibility"
local BANK_VAR_EVENT = Config.CORE_REF .. "_bank_var"
local BANK_TRANSITION_EVENT = Config.CORE_REF .. "_bank_transition"

function Lifecycle.new(session, options)
    return setmetatable({
        session = session,
        options = options or {},
    }, Lifecycle)
end

function Lifecycle:Start()
    local session = self.session
    local options = self.options

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
            session:StopFilterSettle()
            session.layout.itemHover:RestoreHoveredBankStack()
            if session.layout.shownPage ~= nil then session.layout:ShowPage(nil) end
            session.layout:SetNativeViewAll(selectedBankTab == "all")
            debugLog("Bank Core returned control to the native bank after ",
                entry.verbText, " ", entry.subjectText)
            return
        end
        if session.inGame and options.selectedEntryBelongsToBank(event) then
            -- Preset changes have no event of their own.
            session.layout:Changed(false)
            if session.layout.shownPage ~= nil
                and not session.layout.itemHover:HasHoveredBankStack() then
                session:BeginFilterSettle()
            end
        end
    end)

    Event.InventoryAdded.Subscribe(BANK_OPEN_EVENT, function(event)
        if session.inGame and options.isBankInventoryEvent(event) then
            session:BeginLayoutRetry()
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
    Event.VarTransmit.Subscribe(BANK_VAR_EVENT, function(event)
        if not session.inGame then return end
        local name = event.var.configName
        if name ~= "BANK_TEMP" and name ~= "BANK_RESIZE_CYCLE" then return end
        debugLog(name, " transmitted: ", event.oldValue, " -> ", event.newValue)
        -- Coalesce updates and let the game's interface changes finish first.
        Event.Logic.Subscribe(BANK_TRANSITION_EVENT, function()
            Event.Logic.Unsubscribe(BANK_TRANSITION_EVENT)
            if session.shutDown or not session.inGame then return end
            -- Bank variables also update during deposits and withdrawals.
            if session.layout.active then
                local ok, open = pcall(options.bankIsOpen)
                if ok and open and session.layout:IsAttachedToCurrentBank() then return end
                session:CloseBank()
            end
            session:BeginLayoutRetry()
        end)
    end)
    debugLog("inventory listeners registered; checking existing bank")
    local function readBankVisibility()
        if not session.inGame then return false, "not in game" end
        local ok, open, reason = pcall(options.bankIsOpen)
        if not ok then return false, "bank detection ERROR: " .. tostring(open) end
        return open, reason or (open and "bank detected" or "bank not detected")
    end
    local bankWasOpen, lastVisibilityReason = readBankVisibility()
    debugLog("initial bank open=", bankWasOpen, "; reason=", lastVisibilityReason)
    if bankWasOpen then session:BeginLayoutRetry() end
    -- Detached classic controls do not inherit the native bank's visibility.
    Event.Draw.Subscribe(BANK_DRAW_VISIBILITY_EVENT, function()
        local layout = session.layout
        if layout == nil or not layout.active or not layout.detachedSidebar then return end
        local open = readBankVisibility()
        if open then return end
        for _, name in ipairs({ "sidebarRoot", "sidebarOverlay", "sidebarTooltipOverlay" }) do
            local layer = layout[name]
            if layer ~= nil then pcall(function() layer.hidden = true end) end
        end
    end)
    -- Returning from a bank dialog may not add the inventory again.
    local visibilityTicks = 0
    Event.Logic.Subscribe(BANK_VISIBILITY_EVENT, function()
        visibilityTicks = visibilityTicks + 1
        local layout = session.layout
        local classicActive = layout ~= nil and layout.active and layout.detachedSidebar
        if visibilityTicks < 10 and not classicActive then return end
        visibilityTicks = 0
        local bankOpen, reason = readBankVisibility()
        if reason ~= lastVisibilityReason then
            debugLog("bank visibility check: ", reason)
            lastVisibilityReason = reason
        end
        if bankOpen == bankWasOpen then
            if bankOpen then
                if session.layout.active and not session.layout:IsAttachedToCurrentBank() then
                    session:CloseBank()
                    session:BeginLayoutRetry()
                else
                    session:RetryLayoutWhenReady()
                end
            elseif session.layout.active then
                session:CloseBank()
            end
            return
        end
        debugLog("bank visibility changed: ", bankWasOpen, " -> ", bankOpen)
        bankWasOpen = bankOpen
        if bankOpen then
            session:BeginLayoutRetry()
        elseif session.layout.active then
            session:CloseBank()
        else
            session:StopLayoutRetry()
        end
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
    Event.VarTransmit.Unsubscribe(BANK_VAR_EVENT)
    Event.Logic.Unsubscribe(BANK_TRANSITION_EVENT)
    Event.Logic.Unsubscribe(BANK_VISIBILITY_EVENT)
    Event.Draw.Unsubscribe(BANK_DRAW_VISIBILITY_EVENT)
    session:StopFilterSettle()
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
