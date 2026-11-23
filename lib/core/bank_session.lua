-- Manage the bank session, plugins, events, and settings.

local BankWindowRecord = require("lib/bank/bank_window_record")
local Config = require("lib/core/config")
local CorePanel = require("lib/core/core_panel")
local CorePreferences = require("lib/core/core_preferences")
local DebugLog = require("lib/core/debug_log")
local PluginPages = require("lib/features/extensions/plugin_pages")
local Lifecycle = require("lib/core/lifecycle")
local MiniMenuRouter = require("lib/core/mini_menu_router")
local PublicAPI = require("lib/core/public_api")
local BankView = require("lib/bank/bank_view")
local debugLog = DebugLog.Write

local BankSession = {}
BankSession.__index = BankSession

local BANK_ATTACH_RETRY_EVENT = Config.CORE_REF .. "_layout_retry"
local BANK_READY_TICKS_REQUIRED = 2
local BANK_ATTACH_RETRY_TICKS = 120

local function bankIsOpen()
    if ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_WINDOW) == nil then
        return false, "bank host missing"
    end
    -- Inspect the bank itself; other loaded dialogs can retain stale visibility flags.
    local content = ui.Interfaces:GetComponent(id.Component.BANK__CONTENT)
    if content == nil then return false, "bank content missing" end
    if content.hidden == true or content.visible ~= true or content.visibleGlobal ~= true then
        return false, "bank content not visible"
    end
    return true
end

local function isBankInventoryEvent(event)
    return event.inv.id == Config.BANK_INVENTORY_ID
end

-- Check the control's parents too.
local function belongsToBank(component)
    local bank = ui.Interfaces:GetComponent(id.Component.BANK__ALL)
    if bank == nil then return false end
    local current = component
    local depth = 0
    while current ~= nil and depth < 32 do
        if current.interfaceID == bank.interfaceID then return true end
        current = current.parent
        depth = depth + 1
    end
    return false
end

local function bankItemFromMenu(miniMenu)
    if miniMenu == nil or miniMenu.entries == nil then return nil end

    for _, entry in ipairs(miniMenu.entries) do
        local componentData = entry.componentData
        local object = componentData and componentData.objConfig
        local component = componentData and componentData.component
        if object ~= nil and component ~= nil and belongsToBank(component) then
            return {
                id = object.id,
                name = object.name,
                categoryID = component.categoryID,
                dynamicID = component.dynamicID,
            }
        end
    end

    return nil
end

local function selectedEntryBelongsToBank(event)
    local entry = event.entry
    local componentData = entry.componentData
    local component = componentData and componentData.component
    return component ~= nil and belongsToBank(component)
end

-- Match bank tab actions regardless of case or formatting.
local function bankViewSelection(event)
    if not selectedEntryBelongsToBank(event) then return nil end
    local actionText = string.lower(event.entry.verbText
        :gsub("<[^>]->", "")
        :match("^%s*(.-)%s*$"))
    if actionText == "view all" then return "all" end
    if actionText == "view"
        or actionText == "view tab"
        or string.match(actionText, "^view tab %d+$") ~= nil then
        return "tab"
    end
    return nil
end

-- Create the session; Start adds event listeners.
function BankSession.new(options)
    options = options or {}
    local session = setmetatable({
        preferences = options.preferences or CorePreferences.load(),
        sidebarKeybindDown = true,
        railPeekKeybindDown = true,
        layout = nil,
        panel = nil,
        lifecycle = nil,
        menuRouter = nil,
        layoutRetryTicks = 0,
        layoutReadyTicks = 0,
        inGame = Player.IsAvailable(),
        shutDown = false,
    }, BankSession)
    session.layout = BankView.new({
        sidebarOpeningState = session.preferences.sidebarOpeningState,
        expansionDirection = session.preferences.expansionDirection,
        sidebarEdge = session.preferences.sidebarEdge,
        bankHeight = session.preferences.bankHeight,
        windowRecord = options.windowRecord or BankWindowRecord.load(),
        readRailOrder = function() return session.preferences.railOrder end,
        saveRailOrder = function(railOrder) return session:SavePreference("railOrder", railOrder) end,
        saveBankHeight = function(height) return session:SavePreference("bankHeight", height) end,
    })
    local pageOptions = {
        isInGame = function() return session.inGame end,
        bankIsOpen = bankIsOpen,
        onKeybindResumed = function() session:ResetKeybindLatches() end,
    }
    if options.pluginPages ~= nil then
        session.pluginPages = PluginPages.Attach(options.pluginPages, session.layout, pageOptions)
    else
        session.pluginPages = PluginPages.new(session.layout, pageOptions)
    end
    session.menuRouter = MiniMenuRouter.new(session, {
        bankIsOpen = bankIsOpen,
        bankItemFromMenu = bankItemFromMenu,
    })
    session.publicAPI = PublicAPI.new(session.pluginPages, session.menuRouter)
    session.layout.settingsPage = {
        owner = { id = "bankcore.settings" }, key = "settings", title = "Bank Core settings",
        alwaysShowScrollbar = false,
        draw = function(view)
            session:CreateContentLayer(view.parent, view.width, view.height, session.layout.pageDisplay.layer)
            return true, session.panel.contentHeight or CorePanel.CONTENT_HEIGHT
        end,
    }
    session.layout.closeSettings = function() session:DestroyPanel() end
    session.lifecycle = Lifecycle.new(session, {
        bankIsOpen = bankIsOpen,
        isBankInventoryEvent = isBankInventoryEvent,
        bankViewSelection = bankViewSelection,
        selectedEntryBelongsToBank = selectedEntryBelongsToBank,
    })
    return session
end

function BankSession:StopLayoutRetry()
    self.layoutRetryGeneration = (self.layoutRetryGeneration or 0) + 1
    Event.Logic.Unsubscribe(BANK_ATTACH_RETRY_EVENT)
    self.layoutRetryTicks = 0
    self.layoutReadyTicks = 0
end

-- Attempt attachment directly from the bank inventory event.
function BankSession:AttachFromInventory()
    if not self.inGame or self.shutDown or self.layout.active then return end
    -- A fresh inventory can attach now even while a previous attempt is retrying.
    local keepRetry = self.layoutRetryTicks > 0
    if not keepRetry then self:StopLayoutRetry() end
    debugLog("inventory received; attempting immediate attachment without readiness checks")
    local ok, applied = pcall(function() return self.layout:Apply(true) end)
    if ok and applied then
        if keepRetry then self:StopLayoutRetry() end
        debugLog("immediate inventory attachment succeeded")
        return
    end
    debugLog("immediate inventory attachment failed; retrying normally: ", tostring(applied))
    self:BeginLayoutRetry()
end

-- Retry once controls are usable; ongoing native layout changes must not starve attachment.
function BankSession:BeginLayoutRetry()
    if not self.inGame or self.shutDown then return end
    -- Repeated inventory events must not reset a running retry budget.
    if self.layout.active or self.layoutRetryTicks > 0 then return end
    debugLog("attachment requested; inGame=", self.inGame,
        "; active=", self.layout.active, "; bank component=", id.Component.BANK__ALL)
    self:StopLayoutRetry()
    self.layoutRetryTicks = BANK_ATTACH_RETRY_TICKS
    local generation = self.layoutRetryGeneration
    local lastReason
    Event.Logic.Subscribe(BANK_ATTACH_RETRY_EVENT, function()
        if self.shutDown or generation ~= self.layoutRetryGeneration then return end
        if not self.inGame then
            self:StopLayoutRetry()
            return
        end
        local openOK, open, reason = pcall(bankIsOpen)
        if not openOK then
            debugLog("bank detection ERROR: ", tostring(open))
            self:StopLayoutRetry()
            return
        end
        local ready = false
        if open then
            local readyOK
            readyOK, ready, reason = pcall(function() return self.layout:IsReady() end)
            if not readyOK then
                debugLog("readiness ERROR: ", tostring(ready))
                self:StopLayoutRetry()
                return
            end
        end
        reason = ready and "ready" or reason or "not ready"
        if reason ~= lastReason then
            debugLog("attachment check: ", reason)
            lastReason = reason
        end
        if ready then
            self.layoutReadyTicks = self.layoutReadyTicks + 1
        else
            self.layoutReadyTicks = 0
        end
        if self.layoutReadyTicks >= BANK_READY_TICKS_REQUIRED then
            debugLog("bank ready; applying layout")
            local ok, applied = pcall(function() return self.layout:Apply() end)
            if not ok then
                debugLog("layout application ERROR: ", tostring(applied))
            end
            if applied or not ok then
                debugLog("attachment finished; success=", ok and applied == true)
                self:StopLayoutRetry()
                return
            end
        end
        self.layoutRetryTicks = self.layoutRetryTicks - 1
        if self.layoutRetryTicks <= 0 then
            debugLog("attachment timed out; last check=", lastReason)
            self:StopLayoutRetry()
        end
    end)
end

function BankSession:SavePreference(key, value)
    if self.shutDown then return false, "Bank Core is not running." end
    local preferences = {}
    for name, current in pairs(self.preferences) do preferences[name] = current end
    preferences[key] = value
    if not CorePreferences.save(preferences) then return false, "Could not save the setting." end
    self.preferences = preferences
    return true
end

function BankSession:SetDebugPreference(enabled)
    local saved, reason = self:SavePreference("enableDebug", enabled == true)
    if not saved then return false, reason end
    DebugLog.SetEnabled(self.preferences.enableDebug)
    return true
end

function BankSession:SetExpansionDirectionPreference(direction)
    if direction ~= "edge" and direction ~= "evenly" then return false, "Choose Expand to the side or Evenly." end
    local saved, reason = self:SavePreference("expansionDirection", direction)
    if not saved then return false, reason end
    self.layout.expansionDirection = direction
    if self.layout.active and self.layout.expanded then self.layout:UpdateSidebarExpansion(true) end
    return true
end

-- Rebuild only Core's sidebar so native bank controls keep their current state.
function BankSession:SetSidebarEdgePreference(edge)
    if edge ~= "left" and edge ~= "right" then return false, "Choose Left or Right." end
    local saved, reason = self:SavePreference("sidebarEdge", edge)
    if not saved then return false, reason end
    local layout = self.layout
    layout.sidebarEdge = edge
    if layout.active and layout.expanded then
        local parent, height = layout.sidebarRoot.parent, layout.sidebarHeight
        layout:DestroySidebar()
        layout:UpdateSidebarExpansion(true)
        layout:CreateSidebar(parent, height)
        layout:PositionDetachedSidebar()
        layout:Changed(false)
    end
    return true
end

function BankSession:SetSidebarOpeningStatePreference(state)
    if state ~= "expanded" and state ~= "rail" and state ~= "hidden" then return false, "Choose an opening state." end
    local saved, reason = self:SavePreference("sidebarOpeningState", state)
    if not saved then return false, reason end
    self.layout:SetSidebarOpeningState(state)
    return true
end

function BankSession:SetRailPeekEnabledPreference(enabled)
    local saved, reason = self:SavePreference("railPeekEnabled", enabled == true)
    if not saved then return false, reason end
    if not enabled and self.layout.peekRail then
        self.layout.peekRail = false
        self.layout:UpdateLayoutControls()
        self.layout:Changed(false)
    end
    return true
end

local function sameBinding(first, second)
    if #first == 0 or #first ~= #second then return false end
    for _, key in ipairs(first) do
        local found = false
        for _, other in ipairs(second) do if key == other then found = true end end
        if not found then return false end
    end
    return true
end

function BankSession:SaveSidebarKeybind(key, value)
    local keybind = CorePreferences.ReadKeybind(value)
    if keybind == nil then return false, "Choose a valid keybind." end
    local other = key == "sidebarKeybind" and "railPeekKeybind" or "sidebarKeybind"
    if sameBinding(keybind, self.preferences[other] or {}) then
        return false, "Expand Sidebar and Peek Rail need different shortcuts."
    end
    local saved, reason = self:SavePreference(key, keybind)
    if saved then
        self.sidebarKeybindDown, self.railPeekKeybindDown = true, true
    end
    return saved, reason
end

function BankSession:SetSidebarKeybindPreference(value)
    return self:SaveSidebarKeybind("sidebarKeybind", value)
end

function BankSession:SetRailPeekKeybindPreference(value)
    return self:SaveSidebarKeybind("railPeekKeybind", value)
end

function BankSession:AreKeybindsSuspended()
    return self.pluginPages ~= nil and self.pluginPages.HasKeybindSuspensions ~= nil
        and self.pluginPages:HasKeybindSuspensions() == true
end

function BankSession:ResetKeybindLatches()
    self.sidebarKeybindDown = true
    self.railPeekKeybindDown = true
end

-- Expand fires once per press; Peek remains visible only while its chord is held.
function BankSession:CheckSidebarKeybind()
    if self:AreKeybindsSuspended() then
        self:ResetKeybindLatches()
        if not self.shutDown and self.layout ~= nil and self.layout.peekRail then self.layout:SetRailPeek(false) end
        return
    end
    local function pressed(key, latch)
        local binding = self.preferences[key] or {}
        local down = #binding > 0 and prettyui.KeybindField.IsDown(binding)
        local edge = down and not self[latch]
        self[latch] = down
        return edge, #binding, down
    end
    local expandPressed, expandKeys = pressed("sidebarKeybind", "sidebarKeybindDown")
    local peekPressed, peekKeys, peekDown = pressed("railPeekKeybind", "railPeekKeybindDown")
    local state = CorePreferences.OpeningState(self.preferences)
    local usable = not self.shutDown and self.inGame and self.layout.active
    local peekAllowed = usable and state == "hidden" and self.preferences.railPeekEnabled == true
    -- Clear an active peek even when input is blocked, settings change, or the bank closes.
    if self.layout.peekRail and (not peekDown or not peekAllowed) then self.layout:SetRailPeek(false) end
    if not usable then return end
    local expandAllowed = state ~= "expanded"
    local peek = peekAllowed and peekPressed and (not expandPressed or not expandAllowed or peekKeys > expandKeys)
    if not peek and not (expandAllowed and expandPressed) then return end
    local ok, open = pcall(bankIsOpen)
    if not ok or not open then return end
    local invoked, message = pcall(function()
        if peek then return self.layout:SetRailPeek(true) end
        return self.layout:ToggleSidebarExpansion()
    end)
    if not invoked then debugLog("Bank Core sidebar keybind failed: ", tostring(message)) end
end

-- Undo window changes before forgetting them; reconnect on the next bank opening.
function BankSession:ResetGeometry()
    if self.shutDown then return false, "Bank Core is not running." end
    local ok, message = pcall(function() self:CloseBank() end)
    if not ok then
        debugLog("Bank Core could not detach for a geometry reset: ", tostring(message))
        return false, "Could not reset geometry. Close the bank and try again."
    end
    local cleared, reason = self.layout.windowRecord:Clear()
    if not cleared then return false, reason end
    self.layout.savedBankHeight = nil
    self.layout.persistedBankHeight = nil
    if self.preferences ~= nil and self.preferences.bankHeight ~= nil then
        self:SavePreference("bankHeight", nil)
    end
    self.layout.lastBankWindowMeasurements = nil
    return true
end

function BankSession:CreateContentLayer(parent, width, height, closeParent, nativeSettings)
    if self.shutDown then return end
    self:DestroyPanel()
    self.panel = CorePanel.new(parent, {
        preferences = self.preferences,
        nativeSettings = nativeSettings == true,
        width = width, height = height,
        closeParent = closeParent,
        onClose = function() return self.layout:ReturnToBank() end,
        onChangeDebug = function(enabled) return self:SetDebugPreference(enabled) end,
        onChangeSidebarOpeningState = function(state) return self:SetSidebarOpeningStatePreference(state) end,
        onChangeRailPeekEnabled = function(enabled) return self:SetRailPeekEnabledPreference(enabled) end,
        onChangeExpansionDirection = function(direction) return self:SetExpansionDirectionPreference(direction) end,
        onChangeSidebarEdge = function(edge) return self:SetSidebarEdgePreference(edge) end,
        onChangeSidebarKeybind = function(value) return self:SetSidebarKeybindPreference(value) end,
        onChangeRailPeekKeybind = function(value) return self:SetRailPeekKeybindPreference(value) end,
        onResetGeometry = function() return self:ResetGeometry() end,
    })
end

function BankSession:DestroyPanel()
    if self.panel ~= nil then self.panel:Destroy() end
    self.panel = nil
end

function BankSession:SuspendGameUI()
    self.inGame = false
    self:StopLayoutRetry()
    self.pluginPages:BankClosed("game_state")
    self.layout:Restore()
end

-- Connect Core if the bank is already open.
function BankSession:ResumeGameUI()
    if self.shutDown then return end
    self.inGame = true
    self.layout:Changed(false)
    if bankIsOpen() then self:BeginLayoutRetry() end
end

function BankSession:CloseBank()
    self:StopLayoutRetry()
    self.pluginPages:BankClosed("closed")
    self.layout:Restore()
end

function BankSession:Start()
    DebugLog.SetEnabled(self.preferences.enableDebug)
    self.lifecycle:Start()
end

-- Close plugins before stopping the session.
function BankSession:Shutdown()
    if self.shutDown then return end
    -- Continue shutdown even if page cleanup fails.
    local function close(label, action)
        local ok, message = pcall(action)
        if not ok then debugLog("Bank Core shutdown could not close ", label, ": ", message) end
    end
    -- Let the page clean up before removing its bank view.
    close("extension pages", function() self.pluginPages:Suspend() end)
    self.lifecycle:Shutdown()
end

return BankSession
