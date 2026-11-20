-- Manage plugins, sidebar content, and pages.

local BankInterface = require("lib/core/bank_interface")
local BankItemIndex = require("lib/bank/bank_item_index")
local NativeTabs = require("lib/bank/native_tabs")
local Config = require("lib/core/config")
local debugLog = require("lib/core/debug_log").Write
local ExtensionMounts = require("lib/features/extensions/extension_mounts")
local PageLayout = require("lib/features/extensions/page_layout")
local PlainData = require("lib/features/extensions/plain_data")

local PluginPages = {}
PluginPages.__index = PluginPages

local TAB_PREFIX = "__bankutils_ext_tab:"
local REFRESH_EVENT = Config.CORE_REF .. "_extension_refresh"
local NOTIFY_EVENT = Config.CORE_REF .. "_extension_notify"
local REGISTRATION_FIELDS = { id = true, name = true, icon = true, column = true, customView = true, allowNativeDrag = true,
    alwaysShowScrollbar = true,
    onSelect = true, onDeselect = true, onClose = true, onBankItems = true, onBankClose = true, onBankStateChanged = true }
local CALLBACKS = { "customView", "onSelect", "onDeselect", "onClose", "onBankItems", "onBankClose", "onBankStateChanged" }
local PAGE_FIELDS = { title = true, rows = true, allowNativeDrag = true }
local ID_LENGTH = 64
local TEXT_LENGTH = 80

local hasOnlyFields = PlainData.HasOnlyFields

-- A plugin's error must not stop other plugins.
local function callExtensionCallback(extension, name, ...)
    local action = extension.callbacks[name]
    if action == nil then return end
    local ok, message = pcall(action, ...)
    if not ok then debugLog("Bank Core extension ", extension.id, " ", name, " failed: ", message) end
end

-- Check plugin details and keep a copy.
local function readRegistration(description)
    if type(description) ~= "table" or not hasOnlyFields(description, REGISTRATION_FIELDS) then
        return nil, "a registration is a table of id, name, icon, column, customView, onClose, onBankItems,"
            .. " onSelect, onDeselect, onBankClose, onBankStateChanged and optional allowNativeDrag and alwaysShowScrollbar"
    end
    local id = rawget(description, "id")
    if not PlainData.ID(id, ID_LENGTH) then
        return nil, "id must be 1 to 64 letters, digits, '.', '_' or '-'"
    end
    local registration = { id = id, name = PlainData.Label(rawget(description, "name"), TEXT_LENGTH),
        icon = rawget(description, "icon") }
    local allowNativeDrag = rawget(description, "allowNativeDrag")
    if allowNativeDrag ~= nil and type(allowNativeDrag) ~= "boolean" then
        return nil, "allowNativeDrag must be a boolean"
    end
    registration.allowNativeDrag = allowNativeDrag == true
    local alwaysShowScrollbar = rawget(description, "alwaysShowScrollbar")
    if alwaysShowScrollbar ~= nil then
        if type(alwaysShowScrollbar) ~= "boolean" then return nil, "alwaysShowScrollbar must be a boolean" end
        if type(rawget(description, "customView")) ~= "function" then
            return nil, "alwaysShowScrollbar is only supported for customView registrations"
        end
    end
    registration.alwaysShowScrollbar = alwaysShowScrollbar ~= false
    if registration.name == nil then return nil, "name must be 1 to " .. TEXT_LENGTH .. " characters" end
    if registration.icon ~= nil and not PlainData.ValidIcon(registration.icon) then
        return nil, "icon must be a sprite ID from 0 to 2147483647, a PrettyUI name, or a native sprite constant name"
    end
    if rawget(description, "column") ~= nil then
        if registration.icon == nil then return nil, "a column needs an icon" end
        local callbacks, problem = ExtensionMounts.Read(rawget(description, "column"))
        if callbacks == nil then return nil, problem end
        registration.column = callbacks
    end
    for _, name in ipairs(CALLBACKS) do
        local action = rawget(description, name)
        if action ~= nil and type(action) ~= "function" then return nil, name .. " must be a function" end
        registration[name] = action
    end
    return registration
end

-- Check the custom view's returned height.
local function drawView(customView, view)
    local height = customView(view)
    if height ~= nil and (type(height) ~= "number" or height ~= height or height < 0
        or height > PageLayout.MAX_HEIGHT) then
        error("customView must return nil or a height from 0 to " .. PageLayout.MAX_HEIGHT, 0)
    end
    return height
end

-- Check the page and keep a copy.
local function readPage(description)
    if type(description) ~= "table" or not hasOnlyFields(description, PAGE_FIELDS) then
        return nil, "a page is a table of rows, optional title, and optional allowNativeDrag"
    end
    local title = rawget(description, "title")
    if title == nil then
        title = "" -- An omitted title leaves no heading or extra space.
    else
        title = PlainData.Label(title, TEXT_LENGTH)
        if title == nil then return nil, "title must be 1 to " .. TEXT_LENGTH .. " characters when provided" end
    end
    local allowNativeDrag = rawget(description, "allowNativeDrag")
    if allowNativeDrag ~= nil and type(allowNativeDrag) ~= "boolean" then
        return nil, "allowNativeDrag must be a boolean"
    end
    local rows, problem = PageLayout.ReadRows(rawget(description, "rows"), TEXT_LENGTH)
    if rows == nil then return nil, problem end
    return { title = title, rows = rows, allowNativeDrag = allowNativeDrag }
end

function PluginPages.new(bankView, options)
    local self = setmetatable({
        layout = bankView,
        isInGame = options.isInGame,
        bankIsOpen = options.bankIsOpen,
        owners = {},
        -- Wait for plugin drawing to finish before changing tabs.
        pluginCallbacks = 0,
        publishPending = false,
        closed = false,
    }, PluginPages)
    -- Unique event names prevent reloads from removing another session's event handlers.
    local eventSuffix = ":" .. string.match(tostring(self), "%x+$")
    self.refreshEvent = REFRESH_EVENT .. eventSuffix
    self.notifyEvent = NOTIFY_EVENT .. eventSuffix
    bankView.onChange = function() self:Notify() end
    return self
end

-- Attach retained registrations to a fresh bank session after Core reloads.
function PluginPages.Attach(self, bankView, options)
    setmetatable(self, PluginPages)
    self.layout = bankView
    self.isInGame, self.bankIsOpen = options.isInGame, options.bankIsOpen
    self.suspended, self.closed = false, false
    self.pluginCallbacks = 0
    bankView.onChange = function() self:Notify() end
    for _, extension in pairs(self.owners) do
        extension.heardState, extension.heardItems = nil, nil
        extension.shown, extension.bankClosed, extension.redrawPending = false, false, false
        if extension.callbacks.column ~= nil then
            extension.mount = ExtensionMounts.new(self, extension, extension.callbacks.column)
        end
    end
    self.publishPending = true
    self:QueueRefresh()
    self:Notify()
    return self
end

function PluginPages:IsChanging()
    return self.suspended or self.layout.pageTransitions > 0 or self.pluginCallbacks > 0
end

function PluginPages:BankReady()
    return not self.suspended and self.isInGame() and self.bankIsOpen() and self.layout.active
end

function PluginPages:ViewAll()
    return self.layout:IsNativeViewAll()
end

-- Explain why the page cannot open, or return nil.
function PluginPages:OpenBlocker()
    if not self:BankReady() or BankInterface.Get(BankInterface.ITEMS) == nil then
        return "bank_closed"
    end
    if self:IsChanging() then return "busy" end
    if self.layout:IsPresetViewOpen() then return "preset_open" end
    if not self:ViewAll() then return "not_all_items" end
    return nil
end

function PluginPages:IsLive(extension)
    return not self.closed and self.owners[extension.id] == extension
end

function PluginPages:ShownPage(extension)
    local page = self.layout ~= nil and self.layout.shownPage or nil
    return page ~= nil and page.owner == extension and page or nil
end

-- Selection is independent of the plugin page and sidebar mount lifetime.
function PluginPages:SelectedOwner()
    if self.closed or self.suspended or not self:BankReady() then return nil end
    local tabID = self.layout.sidebarMode
    if type(tabID) ~= "string" or tabID:sub(1, #TAB_PREFIX) ~= TAB_PREFIX then return nil end
    local extension = self.owners[tabID:sub(#TAB_PREFIX + 1)]
    return extension ~= nil and extension.icon ~= nil and extension or nil
end

function PluginPages:DeselectExtension(extension)
    if extension == nil or self.selectedExtension ~= extension then return end
    self.selectedExtension = nil
    callExtensionCallback(extension, "onDeselect")
end

-- Finish the old plugin's cleanup before notifying the newly selected plugin.
function PluginPages:DeliverSelectionChanges()
    if self.selectedExtension == self:SelectedOwner() then return end
    self:DeselectExtension(self.selectedExtension)
    local selected = self:SelectedOwner()
    if selected ~= nil then
        self.selectedExtension = selected
        callExtensionCallback(selected, "onSelect")
    end
end

-- Build sidebar tabs for plugins with icons.
function PluginPages:PublishTabs()
    if self.suspended then self.publishPending = true; return end
    -- Wait until the sidebar finishes rebuilding.
    if self.pluginCallbacks > 0 then
        self.publishPending = true
        self:QueueRefresh()
        return
    end
    self.publishPending = false
    local extensionIDs = {}
    for extensionID, extension in pairs(self.owners) do
        if extension.icon ~= nil then extensionIDs[#extensionIDs + 1] = extensionID end
    end
    table.sort(extensionIDs)
    local tabs = {}
    for _, extensionID in ipairs(extensionIDs) do
        local extension = self.owners[extensionID]
        tabs[#tabs + 1] = { id = TAB_PREFIX .. extension.id, extensionID = extension.id,
            label = extension.name, tooltip = extension.name, icon = extension.icon, mount = extension.mount,
            open = extension.mount == nil and function() return self:Open(extension) end or nil }
    end
    self.layout:SetExtensionTabs(tabs)
end

-- Log page-change failures after the bank recovers.
function PluginPages:Transition(action)
    local ok, result = pcall(action)
    if not ok then debugLog("Bank Core could not change the extension page: ", result) end
    return ok, result
end

function PluginPages:QueueRefresh()
    if self.closed or self.suspended then return end
    Event.Logic.Subscribe(self.refreshEvent, function()
        Event.Logic.Unsubscribe(self.refreshEvent)
        self:RunQueued()
    end)
end

-- Finish work delayed by drawing or page changes.
function PluginPages:RunQueued()
    if self.closed or self.suspended then return end
    if self.publishPending then self:PublishTabs() end
    self:LeaveRemovedPage()
    local page = self.layout.shownPage
    if page ~= nil and page.owner.redrawPending then self:Redraw(page.owner) end
end

-- Return to the bank when the page's plugin is gone.
function PluginPages:LeaveRemovedPage()
    if self.suspended then return end
    local page = self.layout.shownPage
    if page ~= nil and page == self.layout.settingsPage then return end
    if page == nil or self:IsLive(page.owner) then return end
    -- Leave the page on the next game update, after the current change finishes.
    if self:IsChanging() then
        self:QueueRefresh()
        return
    end
    self:Transition(function() self.layout:ShowPage(nil) end)
end

-- Register a plugin, replacing any with the same ID.
function PluginPages:RegisterOwner(description)
    if self.closed then return nil, "stopped" end
    if self.suspended then return nil, "busy" end
    if self.pluginCallbacks > 0 then return nil, "busy" end
    local registration, problem = readRegistration(description)
    if registration == nil then return nil, "invalid", problem end
    -- Update tabs once so the selected sidebar content stays open.
    local previous = self.owners[registration.id]
    if previous ~= nil then self:DisposeOwner(previous, true) end
    local extension = { id = registration.id, name = registration.name, icon = registration.icon, callbacks = registration,
        page = nil, opens = 0, shown = false, heardItems = nil, bankClosed = false }
    if registration.column ~= nil then extension.mount = ExtensionMounts.new(self, extension, registration.column) end
    -- Custom views can open immediately.
    local customView = registration.customView
    if customView ~= nil then
        extension.page = { owner = extension, key = extension.opens, title = extension.name,
            allowNativeDrag = registration.allowNativeDrag,
            alwaysShowScrollbar = registration.alwaysShowScrollbar,
            draw = function(view) return self:RunPluginCallback(extension, "customView", drawView, customView, view) end }
    end
    self.owners[extension.id] = extension
    -- Give the plugin its Core functions before drawing its sidebar.
    if extension.icon ~= nil or (previous ~= nil and previous.icon ~= nil) then
        self.publishPending = true
        self:QueueRefresh()
    end
    -- Notify the plugin once bank items are readable.
    self:Notify()
    return extension
end

-- Remove the plugin and empty its page immediately.
function PluginPages:DisposeOwner(extension, replaced)
    if not self:IsLive(extension) then return true end
    self.owners[extension.id] = nil
    self:DeselectExtension(extension)
    local page = self:ShownPage(extension)
    if page ~= nil then page.title, page.rows, page.draw = "", {}, nil end
    if extension.icon ~= nil and not replaced then self:PublishTabs() end
    self:LeaveRemovedPage()
    return true
end

-- Redraw now, or after the current page change finishes.
function PluginPages:Redraw(extension)
    extension.redrawPending = false
    if self:ShownPage(extension) == nil or not self:IsLive(extension) then return end
    if self:IsChanging() then
        extension.redrawPending = true
        self:QueueRefresh()
        return
    end
    self:Transition(function() return self.layout:ShowPage(extension.page) end)
end

-- Save the page and queue a redraw; custom views cannot set pages.
function PluginPages:SetPage(extension, description)
    if not self:IsLive(extension) then return false, "stale" end
    if extension.callbacks.customView ~= nil then
        return false, "invalid", "this extension draws a custom view; register it without customView to set a page"
    end
    local page, problem = readPage(description)
    if page == nil then return false, "invalid", problem end
    -- Pages can override the plugin's drag setting.
    if page.allowNativeDrag == nil then page.allowNativeDrag = extension.callbacks.allowNativeDrag == true end
    -- Keep the same page opening ID so its scroll position is saved.
    page.owner, page.key = extension, extension.opens
    extension.page = page
    if self:ShownPage(extension) ~= nil then
        extension.redrawPending = true
        self:QueueRefresh()
    end
    return true
end

-- Queue a redraw; reject requests during drawing to prevent loops.
function PluginPages:Refresh(extension)
    if not self:IsLive(extension) then return false, "stale" end
    if self:IsChanging() then return false, "busy" end
    if self:ShownPage(extension) ~= nil then
        extension.redrawPending = true
        self:QueueRefresh()
    end
    return true
end

-- Open the plugin's page, or explain why it cannot open.
function PluginPages:Open(extension)
    if not self:IsLive(extension) then return false, "stale" end
    if extension.page == nil then return false, "no_page" end
    local blockedReason = self:OpenBlocker()
    if blockedReason ~= nil then return false, blockedReason end
    -- Start each new opening at the top.
    extension.redrawPending = false
    extension.opens = extension.opens + 1
    extension.page.key = extension.opens
    local ok, shown = self:Transition(function() return self.layout:ShowPage(extension.page) end)
    -- A failed page returns to the normal bank.
    if not ok or not shown then return false, "failed" end
    extension.shown = true
    return true
end

function PluginPages:ClosePage(extension)
    if not self:IsLive(extension) then return false, "stale" end
    if self:ShownPage(extension) == nil then return true end
    if self:IsChanging() then return false, "busy" end
    if not self:Transition(function() self.layout:ShowPage(nil) end) then return false, "failed" end
    return true
end

function PluginPages:IsOpen(extension)
    return self:IsLive(extension) and self:ShownPage(extension) ~= nil
end

-- Explain why bank items are unreadable, or return nil.
function PluginPages:ItemsBlocker()
    if not self:BankReady() then return "bank_closed" end
    if not self:ViewAll() then return "not_all_items" end
    return nil
end

-- Copy stacks in bank order, using positions saved before Core moved them.
function PluginPages:BankItems(extension)
    if not self:IsLive(extension) then return nil, "stale" end
    local blockedReason = self:ItemsBlocker()
    if blockedReason ~= nil then return nil, blockedReason end
    local bankView = self.layout
    local entries = nil
    if bankView.shownPage ~= nil then
        -- Wait for fresh bank data.
        local pageState = bankView.pageState
        entries = pageState.active and not pageState.stale and pageState.bankItems or nil
    else
        local itemLayer = BankInterface.Find(BankInterface.ITEMS)
        entries = itemLayer ~= nil and BankItemIndex.Collect(itemLayer) or nil
    end
    if entries == nil then return nil, "busy" end
    local items = {}
    local tabSizes = NativeTabs.Read(entries)
    for index, entry in ipairs(entries) do
        items[index] = { objectID = entry.objectID, quantity = math.max(0, entry.quantity or 0),
            bankSlot = entry.bankSlot, nativeTab = NativeTabs.ForSlot(tabSizes, entry.bankSlot) }
    end
    return items
end

function PluginPages:BankBounds(extension)
    if not self:IsLive(extension) or not self:BankReady() then return nil end
    local bankWindowMeasurements = self.layout:ReadBankWindowMeasurements()
    if bankWindowMeasurements == nil then return nil end
    local bounds = bankWindowMeasurements.bounds
    return { x = bounds.x, y = bounds.y, width = bounds.width, height = bounds.height,
        columns = bankWindowMeasurements.columns }
end

-- Check bank controls even without registered plugins.
function PluginPages:ReadBankState()
    local state = { bankOpen = self:BankReady(), viewAll = false, presetOpen = false,
        searchActive = false, filterActive = false }
    if not state.bankOpen then return state end
    local layout = self.layout
    state.viewAll = self:ViewAll()
    state.presetOpen = layout:IsPresetViewOpen()
    local mode = layout:ReadNativeFilterMode()
    state.searchActive = mode == "search"
    state.filterActive = mode == "filter"
    return state
end

-- Share control state without exposing the controls themselves.
function PluginPages:BankState(extension)
    if not self:IsLive(extension) then return nil, "stale" end
    local state = self:ReadBankState()
    return state
end

-- Run plugin drawing and log errors.
function PluginPages:RunPluginCallback(extension, name, action, ...)
    if action == nil then return true end
    self.pluginCallbacks = self.pluginCallbacks + 1
    local ok, result = pcall(action, ...)
    self.pluginCallbacks = self.pluginCallbacks - 1
    if not ok and type(log) == "function" then
        log("Bank Core extension ", extension.id, " ", name, " failed: ", tostring(result))
    end
    return ok, result
end

-- Send one close notification per bank opening on the next game update.
function PluginPages:BankClosed()
    if self.closed or self.suspended or not self.layout.active then return end
    for _, extension in pairs(self.owners) do extension.bankClosed = true end
    self:DeselectExtension(self.selectedExtension)
    self:Notify()
end

function PluginPages:Notify()
    if self.closed or self.suspended then return end
    Event.Logic.Subscribe(self.notifyEvent, function()
        Event.Logic.Unsubscribe(self.notifyEvent)
        self:DeliverChanges()
    end)
end

-- Include removed optional fields when comparing.
local function sameBankState(first, second)
    if first == nil then return false end
    for key, value in pairs(first) do if second[key] ~= value then return false end end
    for key, value in pairs(second) do if first[key] ~= value then return false end end
    return true
end

function PluginPages:ItemsReadable()
    return self:ItemsBlocker() == nil and not self.layout.pageState.stale
        and (self.layout.shownPage ~= nil or BankInterface.Find(BankInterface.ITEMS) ~= nil)
end

-- Notify of bank closure, page closure, then item changes; stop if the plugin is removed.
function PluginPages:DeliverTo(extension)
    if extension.bankClosed then
        extension.bankClosed = false
        callExtensionCallback(extension, "onBankClose")
        if not self:IsLive(extension) then return end
    end
    -- Do not report closure if the plugin reopened its page.
    local shown = self:ShownPage(extension) ~= nil
    if extension.shown and not shown then
        extension.shown = false
        callExtensionCallback(extension, "onClose")
        if not self:IsLive(extension) then return end
    elseif shown then
        extension.shown = true
    end
    if extension.callbacks.onBankStateChanged ~= nil then
        local state = self:BankState(extension)
        if not sameBankState(extension.heardState, state) then
            -- Keep a copy so plugin changes cannot affect later comparisons.
            extension.heardState = {}
            for key, value in pairs(state) do extension.heardState[key] = value end
            callExtensionCallback(extension, "onBankStateChanged", state)
            if not self:IsLive(extension) then return end
        end
    end
    if not self:ItemsReadable() then return end
    local bankView = self.layout
    local itemsVersion = bankView.windowSession .. ":" .. bankView.itemsGeneration
    if itemsVersion ~= extension.heardItems then
        extension.heardItems = itemsVersion
        callExtensionCallback(extension, "onBankItems")
    end
end

-- Notify registered plugins in ID order.
function PluginPages:DeliverChanges()
    self:DeliverSelectionChanges()
    local extensionIDs = {}
    for extensionID in pairs(self.owners) do extensionIDs[#extensionIDs + 1] = extensionID end
    table.sort(extensionIDs)
    local owners = {}
    for index, extensionID in ipairs(extensionIDs) do owners[index] = self.owners[extensionID] end
    for _, extension in ipairs(owners) do
        if self:IsLive(extension) then self:DeliverTo(extension) end
    end
end

-- Release session references while retaining registrations and prepared pages.
function PluginPages:Suspend()
    if self.closed or self.suspended then return end
    local layout = self.layout
    local shown = layout.shownPage
    local owners = {}
    for _, extension in pairs(self.owners) do owners[#owners + 1] = extension end
    self.suspended, self.layout, self.menuRouter = true, nil, nil
    self:DeselectExtension(self.selectedExtension)
    self.isInGame, self.bankIsOpen = nil, nil
    Event.Logic.Unsubscribe(self.refreshEvent)
    Event.Logic.Unsubscribe(self.notifyEvent)
    for _, extension in ipairs(owners) do
        local wasShown = extension.shown or (shown ~= nil and shown.owner == extension)
        extension.shown = false
        if self:IsLive(extension) and wasShown then callExtensionCallback(extension, "onClose") end
        if self:IsLive(extension) and (layout.active or extension.bankClosed) then
            callExtensionCallback(extension, "onBankClose")
        end
        extension.mount = nil
    end
end

-- Close all plugins and clear tabs before permanent disposal.
function PluginPages:Close()
    if self.closed then return end
    if self.suspended then
        self.owners = {}
        self.closed = true
        return
    end
    local bankOpen = self.layout.active
    local page = self.layout.shownPage
    local shownExtension = page ~= nil and page.owner or nil
    local extensionsToClose = {}
    for _, extension in pairs(self.owners) do extensionsToClose[#extensionsToClose + 1] = extension end
    table.sort(extensionsToClose, function(a, b) return a.id < b.id end)
    self.owners = {}
    if page ~= nil then page.title, page.rows, page.draw = "", {}, nil end
    self:PublishTabs()
    self:LeaveRemovedPage()
    Event.Logic.Unsubscribe(self.refreshEvent)
    Event.Logic.Unsubscribe(self.notifyEvent)
    self.closed = true
    self.layout = nil
    self:DeselectExtension(self.selectedExtension)
    for _, extension in ipairs(extensionsToClose) do
        if extension.shown or extension == shownExtension then callExtensionCallback(extension, "onClose") end
        if bankOpen or extension.bankClosed then callExtensionCallback(extension, "onBankClose") end
    end
end

return PluginPages
