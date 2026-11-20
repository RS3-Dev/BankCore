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
local BANK_ATTACH_DRAW_EVENT = Config.CORE_REF .. "_attachment_timing"
local BANK_ITEMS_SETTLE_EVENT = Config.CORE_REF .. "_filter_settle"
local BANK_ITEMS_SETTLE_TICKS = 128
local BANK_READY_TICKS_REQUIRED = 8
local BANK_ATTACH_RETRY_TICKS = 120

-- Check less often as the game's bank updates settle.
local function shouldCheckBankItems(tick)
    return tick <= 4
        or tick == 8
        or tick == 16
        or tick == 32
        or tick == 64
        or tick == 96
        or tick == BANK_ITEMS_SETTLE_TICKS
end

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
        layout = nil,
        panel = nil,
        lifecycle = nil,
        menuRouter = nil,
        layoutRetryTicks = 0,
        layoutReadyTicks = 0,
        attachmentWanted = false,
        filterSettleTicks = 0,
        inGame = Player.IsAvailable(),
        shutDown = false,
    }, BankSession)
    session.layout = BankView.new({
        collapseSidebar = session.preferences.collapseSidebar,
        expansionDirection = session.preferences.expansionDirection,
        windowRecord = options.windowRecord or BankWindowRecord.load(),
        readRailOrder = function() return session.preferences.railOrder end,
        saveRailOrder = function(railOrder) return session:SavePreference("railOrder", railOrder) end,
    })
    local pageOptions = {
        isInGame = function() return session.inGame end,
        bankIsOpen = bankIsOpen,
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

function BankSession:StopLayoutRetry(keepDrawTiming)
    Event.Logic.Unsubscribe(BANK_ATTACH_RETRY_EVENT)
    if not keepDrawTiming then Event.Draw.Unsubscribe(BANK_ATTACH_DRAW_EVENT) end
    self.layoutRetryTicks = 0
    self.layoutReadyTicks = 0
end

function BankSession:StopFilterSettle()
    Event.Logic.Unsubscribe(BANK_ITEMS_SETTLE_EVENT)
    self.filterSettleTicks = 0
end

-- Refresh the page while bank updates settle.
function BankSession:BeginFilterSettle()
    if not self.inGame or self.layout.shownPage == nil then return end
    self:StopFilterSettle()
    self.filterSettleTicks = 0
    Event.Logic.Subscribe(BANK_ITEMS_SETTLE_EVENT, function()
        if not self.inGame
            or not bankIsOpen()
            or self.layout.shownPage == nil then
            self:StopFilterSettle()
            return
        end
        self.filterSettleTicks = self.filterSettleTicks + 1
        if shouldCheckBankItems(self.filterSettleTicks)
            and not self.layout:ShownPageIsInSync() then
            self.layout:RefreshShownPage()
        end
        if self.filterSettleTicks >= BANK_ITEMS_SETTLE_TICKS then
            self:StopFilterSettle()
        end
    end)
end

-- Wait for eight consecutive ready checks before adding controls.
function BankSession:BeginLayoutRetry()
    if not self.inGame or self.shutDown then return end
    self.attachmentWanted = true
    -- Inventory, variable and visibility events can describe the same transition.
    if self.layout.active or self.layoutRetryTicks > 0 then return end
    debugLog("attachment requested; inGame=", self.inGame,
        "; active=", self.layout.active, "; bank component=", id.Component.BANK__ALL)
    self:StopLayoutRetry()
    self.layoutRetryTicks = BANK_ATTACH_RETRY_TICKS
    local lastReason
    local checkedTicks, firstReadyTick, stableSince = 0, nil, nil
    local built, drawSeconds = false, 0
    if DebugLog.IsEnabled() then
        -- The next draw is a paint opportunity, not a measurement of GPU completion.
        Event.Draw.Subscribe(BANK_ATTACH_DRAW_EVENT, function(event)
            drawSeconds = drawSeconds + event.timeDeltaSecs
            if not built then return end
            Event.Draw.Unsubscribe(BANK_ATTACH_DRAW_EVENT)
            debugLog("[Bank Core timing] request-to-next-draw approximately ",
                math.floor(drawSeconds * 1000 + 0.5), "ms; first ready tick=", firstReadyTick,
                "; final ready run began at tick=", stableSince, "; apply tick=", checkedTicks,
                "; required ready ticks=", BANK_READY_TICKS_REQUIRED)
        end)
    end
    Event.Logic.Subscribe(BANK_ATTACH_RETRY_EVENT, function()
        checkedTicks = checkedTicks + 1
        if not self.inGame then
            self:StopLayoutRetry()
            return
        end
        local openOK, open, reason = pcall(bankIsOpen)
        if not openOK then
            debugLog("bank detection ERROR: ", tostring(open))
            self.attachmentWanted = false
            self:StopLayoutRetry()
            return
        end
        local ready = false
        if open then
            local readyOK
            readyOK, ready, reason = pcall(function() return self.layout:IsReady() end)
            if not readyOK then
                debugLog("readiness ERROR: ", tostring(ready))
                self.attachmentWanted = false
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
            firstReadyTick = firstReadyTick or checkedTicks
            stableSince = stableSince or checkedTicks
            self.layoutReadyTicks = self.layoutReadyTicks + 1
        else
            stableSince = nil
            self.layoutReadyTicks = 0
        end
        if self.layoutReadyTicks >= BANK_READY_TICKS_REQUIRED then
            debugLog("bank ready; applying layout")
            local ok, applied = pcall(function() return self.layout:Apply() end)
            if not ok then
                debugLog("layout application ERROR: ", tostring(applied))
                self.attachmentWanted = false
            end
            if applied or not ok then
                built = ok and applied == true
                debugLog("attachment finished; success=", ok and applied == true)
                self:StopLayoutRetry(built)
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

-- A visible bank can finish measuring after the bounded attachment attempt expires.
function BankSession:RetryLayoutWhenReady()
    if not self.inGame or self.shutDown or not self.attachmentWanted
        or self.layout.active or self.layoutRetryTicks > 0 then return end
    local ok, ready = pcall(function() return self.layout:IsReady() end)
    if ok and ready then
        debugLog("bank geometry became ready after waiting; retrying attachment")
        self:BeginLayoutRetry()
    end
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

-- Save before changing the sidebar so a failed write leaves the layout alone.
function BankSession:SetCollapseSidebarPreference(enabled)
    local saved, reason = self:SavePreference("collapseSidebar", enabled == true)
    if not saved then return false, reason end
    self.layout:SetCollapseSidebar(enabled)
    return true
end

function BankSession:SetExpansionDirectionPreference(direction)
    if direction ~= "left" and direction ~= "evenly" then return false, "Choose Left or Evenly." end
    local saved, reason = self:SavePreference("expansionDirection", direction)
    if not saved then return false, reason end
    self.layout.expansionDirection = direction
    if self.layout.active and self.layout.expanded then self.layout:UpdateSidebarExpansion(true) end
    return true
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
    self.layout.lastBankWindowMeasurements = nil
    return true
end

function BankSession:CreateContentLayer(parent, width, height, closeParent)
    if self.shutDown then return end
    self:DestroyPanel()
    self.panel = CorePanel.new(parent, {
        preferences = self.preferences,
        width = width, height = height,
        closeParent = closeParent,
        onClose = function() return self.layout:ReturnToBank() end,
        onChangeDebug = function(enabled) return self:SetDebugPreference(enabled) end,
        onChangeCollapseSidebar = function(enabled) return self:SetCollapseSidebarPreference(enabled) end,
        onChangeExpansionDirection = function(direction) return self:SetExpansionDirectionPreference(direction) end,
        onResetGeometry = function() return self:ResetGeometry() end,
    })
end

function BankSession:DestroyPanel()
    if self.panel ~= nil then self.panel:Destroy() end
    self.panel = nil
end

function BankSession:SuspendGameUI()
    self.attachmentWanted = false
    self.inGame = false
    self:StopLayoutRetry()
    self:StopFilterSettle()
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
    self.attachmentWanted = false
    self:StopLayoutRetry()
    self:StopFilterSettle()
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
