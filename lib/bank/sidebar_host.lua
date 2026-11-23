-- Draw plugin tabs and the selected sidebar content.

local BankInterface = require("lib/core/bank_interface")
local Config = require("lib/core/config")
local DebugLog = require("lib/core/debug_log")
local debugLog = DebugLog.Write
local SidebarFrame = require("lib/ui/sidebar_frame")

local SidebarHost = {}

local RAIL_X = 12
local RAIL_Y = 44
local MESSAGE_INSET = 8
local SETTINGS_MODE = "__bankcore_settings"

-- Use saved tab order, with new tabs at the end.
local function sortByRailOrder(tabs, railOrder)
    local byExtension, sorted, placed = {}, {}, {}
    for _, tab in ipairs(tabs) do byExtension[tab.extensionID] = tab end
    for _, extensionID in ipairs(railOrder) do
        local tab = byExtension[extensionID]
        if tab ~= nil and not placed[tab] then
            sorted[#sorted + 1] = tab
            placed[tab] = true
        end
    end
    for _, tab in ipairs(tabs) do
        if not placed[tab] then sorted[#sorted + 1] = tab end
    end
    return sorted
end

-- Save the new tab order without moving unloaded plugins.
local function mergeRailOrder(railOrder, tabs)
    local shown, saved, order, last = {}, {}, {}, nil
    for _, tab in ipairs(tabs) do shown[tab.extensionID] = true end
    for index, extensionID in ipairs(railOrder) do
        order[index], saved[extensionID] = extensionID, true
        if shown[extensionID] then last = index end
    end
    last = last or #order
    for _, tab in ipairs(tabs) do
        if not saved[tab.extensionID] then
            last = last + 1
            table.insert(order, last, tab.extensionID)
        end
    end
    -- Only replace positions belonging to loaded tabs.
    local shownIndex = 1
    for index, extensionID in ipairs(order) do
        if shown[extensionID] then
            order[index] = tabs[shownIndex].extensionID
            shownIndex = shownIndex + 1
        end
    end
    return order
end

function SidebarHost:FindSidebarTab(tabID)
    for _, tab in ipairs(self.extensionTabs) do
        if tab.id == tabID then return tab end
    end
    return nil
end

function SidebarHost:FirstSidebarTab()
    for _, tab in ipairs(self.extensionTabs) do
        if tab.mount ~= nil then return tab.id end
    end
    return nil
end

function SidebarHost:CloseTabMount()
    local columnMount = self.tabMount
    self.tabMount = nil
    self.tabMountBounds = nil
    if columnMount ~= nil then columnMount:Close() end
end

local function positiveNumber(value)
    return type(value) == "number" and value > 0 and value or nil
end

local function boundsMatch(current, target)
    return current ~= nil
        and current.x == target.x
        and current.y == target.y
        and current.width == target.width
        and current.height == target.height
end

local function describeSidebarHeights(self, bounds)
    local all = (id ~= nil and id.Component ~= nil and id.Component.BANK__ALL ~= nil
        and BankInterface.Find(id.Component.BANK__ALL))
        or (self.components ~= nil and self.components.all or nil)
    local host = self.components ~= nil and self.components.host or nil
    local content = (id ~= nil and id.Component ~= nil and id.Component.BANK__CONTENT ~= nil
        and BankInterface.Find(id.Component.BANK__CONTENT))
        or (self.components ~= nil and self.components.content or nil)
    return string.format("bounds=%s rail=%s root=%s all=%s host=%s content=%s saved=%s settling=%s",
        tostring(bounds and bounds.height),
        tostring(self.rail and self.rail.height),
        tostring(self.sidebarRoot and self.sidebarRoot.height),
        tostring(all and all.height),
        tostring(host and host.height),
        tostring(content and content.height),
        tostring(self.savedBankHeight),
        tostring(self.settlingOpenHeight == true))
end

-- Replace the sidebar content when selection changes.
function SidebarHost:RefreshTabMount(tab)
    local columnMount = tab ~= nil and tab.mount or nil
    if self.tabMount ~= nil and self.tabMount ~= columnMount then self:CloseTabMount() end
    if columnMount == nil or self.tabMount == columnMount then return end
    -- Leave room for the outline.
    local overlayParent = self.detachedSidebar and self.sidebarOverlay or self.components.all
    local bounds = self:TabMountBounds()
    if DebugLog.IsEnabled() then
        debugLog("Bank Core mounting sidebar tab ", tostring(tab.extensionID or tab.id), ": ",
            describeSidebarHeights(self, bounds))
    end
    if columnMount:Open(self.rail, overlayParent, bounds) then
        self.tabMount = columnMount
        self.tabMountBounds = bounds
    end
    SidebarFrame.RaiseEdges(self)
end

function SidebarHost:LiveBankHeight()
    local all = (id ~= nil and id.Component ~= nil and id.Component.BANK__ALL ~= nil
        and BankInterface.Find(id.Component.BANK__ALL))
        or (self.components ~= nil and self.components.all or nil)
    return positiveNumber(all ~= nil and all.height or nil)
        or positiveNumber(self.sidebarRoot ~= nil and self.sidebarRoot.height or nil)
end

-- Hold the saved settled bank height across transient opening steps until live height catches up.
function SidebarHost:TabMountBounds()
    local hostHeight = self:LiveBankHeight()
    if self.settlingOpenHeight and self.savedBankHeight ~= nil then
        hostHeight = self.savedBankHeight
    end
    local railHeight
    if hostHeight ~= nil then
        railHeight = SidebarFrame.ColumnHeight(hostHeight, RAIL_Y)
    else
        railHeight = positiveNumber(self.rail ~= nil and self.rail.height or nil)
        if railHeight == nil then
            local fallbackHeight = positiveNumber(self.sidebarHeight)
            railHeight = fallbackHeight ~= nil and SidebarFrame.ColumnHeight(fallbackHeight, RAIL_Y) or 0
        end
    end
    return { x = 1, y = 1, width = Config.SIDEBAR_COLUMN_WIDTH - 10,
        height = math.max(0, railHeight - 2) }
end

-- Sync the mounted plugin column whenever settled bounds differ from its current size.
function SidebarHost:SyncTabMountBounds()
    if self.rail == nil or self.tabMount == nil then return false end
    local bounds = self:TabMountBounds()
    local previous = self.tabMount.bounds or self.tabMountBounds
    if boundsMatch(previous, bounds) then return false end
    if DebugLog.IsEnabled() then
        debugLog("Bank Core resizing sidebar mount from ", tostring(previous and previous.height),
            " to ", tostring(bounds.height), " (", describeSidebarHeights(self, bounds), ")")
    end
    self.tabMount:Resize(bounds)
    -- Show why the content failed to resize.
    if self.tabMount ~= nil and not self.tabMount:IsMounted() then
        self.tabMount = nil
        self.tabMountBounds = nil
        self:RefreshSidebar()
    elseif self.tabMount ~= nil then
        self.tabMountBounds = bounds
    end
    return true
end

-- Show the selected content or explain why it is unavailable.
function SidebarHost:RefreshSidebar()
    if self.emptyLabel == nil then return end
    local tab = self:FindSidebarTab(self.sidebarMode)
    if self.sidebarTitle ~= nil then
        self.sidebarTitle.content = tab ~= nil and tab.label or "Bank Plugins"
    end
    self:RefreshTabMount(tab)
    if tab == nil then
        self.emptyLabel.content = #self.extensionTabs == 0 and "No bank plugins found." or "Select a bank plugin."
    else
        self.emptyLabel.content = "This tab could not be shown."
    end
    self.emptyLabel.hidden = self.tabMount ~= nil
end

-- Show a message for missing or failed content.
local function createEmptyLabel(parent)
    local label = prettyui.Text.new(parent, {
        text = "",
        x = MESSAGE_INSET,
        y = MESSAGE_INSET,
        width = Config.SIDEBAR_COLUMN_WIDTH - 24,
        height = 72,
        colour = 0xB7AA8EFF,
        maxLines = 4,
    })
    label.alignHorizontal = ui.AlignMode.CENTRE
    label.alignVertical = ui.AlignMode.TOPLEFT
    return label
end

function SidebarHost:CreateSidebar(parent, height)
    self.sidebarHeight = height
    local x = self.detachedSidebar and Config.CLASSIC_SIDEBAR_LEFT_PADDING or RAIL_X
    SidebarFrame.Create(self, parent, height, x, RAIL_Y, {
        onSelect = function(tabID) self:SetSidebarMode(tabID) end,
        onReorder = function(tabIDs, movedID) self:ReorderSidebarTabs(tabIDs, movedID) end,
        onReturn = function() self:ReturnToBank() end,
        onSettings = function() self:ToggleSettings() end,
    })
    self.emptyLabel = createEmptyLabel(self.rail)
    self:UpdateLayoutControls()
    self:RefreshSidebar()
    SidebarFrame.RaiseEdges(self)
end

-- Open Core's own page without adding an entry to the plugin registry.
function SidebarHost:ToggleSettings()
    if not self.active or self.pageTransitions > 0 or self.settingsPage == nil then return false end
    if self.shownPage == self.settingsPage then return self:ReturnToBank() end
    local ok, shown = pcall(function() return self:ShowPage(self.settingsPage) end)
    if not ok then debugLog("Bank Core could not open settings: ", tostring(shown)) end
    if ok and shown == true then
        self.sidebarMode = SETTINGS_MODE
        self:RefreshSidebar()
        self:UpdateLayoutControls()
        self:Changed(false)
    end
    return ok and shown == true
end

-- Close whichever plugin owns the displayed page or custom view.
function SidebarHost:ReturnToBank()
    if not self.active or self.shownPage == nil or self.pageTransitions > 0 then return false end
    local ok, closed = pcall(function() return self:ShowPage(nil) end)
    if not ok then debugLog("Bank Core could not return to the native bank: ", tostring(closed)) end
    return ok and closed == true
end

-- Resize the sidebar and its plugin content.
function SidebarHost:ResizeSidebar(height)
    if self.rail == nil then return end
    if height ~= nil and height > 0 and height ~= self.sidebarHeight then
        self.sidebarHeight = height
        SidebarFrame.Resize(self, height)
    elseif self.tabRail ~= nil and self.tabRail.bottomInset ~= nil then
        self.tabRail:SetHeight(0)
    end
    self:SyncTabMountBounds()
end

-- Remove the sidebar and its contents.
function SidebarHost:DestroySidebar()
    local closed, closeError = pcall(function() self:CloseTabMount() end)
    self.emptyLabel = nil
    local destroyed, destroyError = pcall(SidebarFrame.Destroy, self)
    if not closed then error(closeError, 0) end
    if not destroyed then error(destroyError, 0) end
end

function SidebarHost:UpdateLayoutControls()
    if self.sidebarMode == SETTINGS_MODE and self.shownPage ~= self.settingsPage then self.sidebarMode = nil end
    local selected = self:FindSidebarTab(self.sidebarMode)
    if selected ~= nil and selected.mount == nil
        and (self.shownPage == nil or self.shownPage.owner.id ~= selected.extensionID) then
        self.sidebarMode = nil
    end
    if self.active and self.expanded then self:UpdateSidebarExpansion() end
    SidebarFrame.SetCollapsed(self, self:IsSidebarCollapsed(), self:IsSidebarHidden())
    if self.settingsButton ~= nil then
        self.settingsButton.active = self.settingsPage ~= nil and self.shownPage == self.settingsPage
        self.settingsButton:_UpdateState()
        if self.settingsSelectionFrame ~= nil then
            self.settingsSelectionFrame.hidden = not self.settingsButton.active
            self.settingsSelectionFrame:MoveToFront()
        end
    end
    if self.returnToBankButton ~= nil then
        self.returnToBankButton:SetDisabled(self.shownPage == nil)
    end
    if self.tabRail == nil then return end
    self.tabRail:SetTabs(self.extensionTabs, self.sidebarMode)
end

-- Fully collapsed means neither the column nor the icon rail is visible.
function SidebarHost:IsSidebarHidden()
    return self.sidebarOpeningState == "hidden" and self.sidebarMode == nil and not self.peekRail
end

function SidebarHost:SetSidebarOpeningState(state)
    self.sidebarOpeningState = state
    self.peekRail = false
    if not self.active and state ~= "expanded" then self.sidebarMode = nil end
    if state == "expanded" and self.sidebarMode == nil then self.sidebarMode = self:FirstSidebarTab() end
    self:RefreshSidebar()
    self:UpdateLayoutControls()
    self:Changed(false)
end

-- Releasing a peek hides the rail unless a plugin or settings has been selected.
function SidebarHost:SetRailPeek(reveal)
    reveal = reveal == true
    if reveal and (not self.active or self.pageTransitions > 0 or self.sidebarOpeningState ~= "hidden") then return false end
    if self.peekRail == reveal then return true end
    self.peekRail = reveal
    self:RefreshSidebar()
    self:UpdateLayoutControls()
    self:Changed(false)
    return true
end

-- Keep the reserved column while settings are open in fully expanded mode.
function SidebarHost:IsSidebarCollapsed()
    if self.sidebarMode == SETTINGS_MODE then
        return self.sidebarOpeningState ~= "expanded"
    end
    local selected = self:FindSidebarTab(self.sidebarMode)
    if selected ~= nil and selected.mount == nil then return true end
    return (self.sidebarOpeningState ~= "expanded") and self.sidebarMode == nil
end

-- Use saved rail order without toggling an already-selected first plugin off.
function SidebarHost:SelectFirstSidebarTab()
    if not self.active or self.pageTransitions > 0 then return false end
    local first = self.extensionTabs[1]
    if first == nil then return false end
    if self.sidebarMode ~= first.id then self:SetSidebarMode(first.id) end
    return self.sidebarMode == first.id
end

-- The expand shortcut also returns any selected plugin to the configured collapsed state.
function SidebarHost:ToggleSidebarExpansion()
    if not self.active or self.pageTransitions > 0 or self.sidebarOpeningState == "expanded" then return false end
    if self:FindSidebarTab(self.sidebarMode) == nil then return self:SelectFirstSidebarTab() end
    if self.shownPage ~= nil and not self:ReturnToBank() then return false end
    self.sidebarMode, self.peekRail = nil, false
    self:RefreshSidebar()
    self:UpdateLayoutControls()
    self:Changed(false)
    return true
end

-- Show the sidebar content, or open the page if there is none.
function SidebarHost:SetSidebarMode(selectedTabID)
    if self.pageTransitions > 0 then return end
    local tab = self:FindSidebarTab(selectedTabID)
    local deselected = false
    if tab ~= nil and self.sidebarMode == selectedTabID and (self.sidebarOpeningState ~= "expanded" or tab.mount == nil) then
        local page = self.shownPage
        if page ~= nil and page.owner.id == tab.extensionID and not self:ReturnToBank() then return end
        selectedTabID, tab = nil, nil
        deselected = true
    end
    if tab ~= nil and tab.mount == nil then
        if tab.open == nil or not tab.open() then return end
        self.sidebarMode = selectedTabID
        self:RefreshSidebar()
        self:UpdateLayoutControls()
        self:Changed(false)
        return
    end
    if tab ~= nil and self.shownPage == self.settingsPage and self.settingsPage ~= nil then
        if not self:ReturnToBank() then return end
    end
    if tab == nil and self.sidebarOpeningState == "expanded" and not deselected then
        selectedTabID = self:FirstSidebarTab()
    end
    if self.sidebarMode == selectedTabID then
        self:UpdateLayoutControls()
        return
    end
    self.sidebarMode = selectedTabID
    self:UpdateLayoutControls()
    self:RefreshSidebar()
    self:Changed(false)
end

-- Keep the selected tab unless it was removed.
function SidebarHost:SetExtensionTabs(tabs)
    self.extensionTabs = sortByRailOrder(tabs, self.readRailOrder())
    local selected = self:FindSidebarTab(self.sidebarMode)
    if selected == nil and self.sidebarMode ~= SETTINGS_MODE then
        self.sidebarMode = self.sidebarOpeningState == "expanded" and self:FirstSidebarTab() or nil
    end
    self:UpdateLayoutControls()
    self:RefreshSidebar()
    self:Changed(false)
end

-- Save the tab order before redrawing; keep the current content and page.
function SidebarHost:ReorderSidebarTabs(tabIDs, movedID)
    if #tabIDs ~= #self.extensionTabs then return false end
    local tabs, used, moved = {}, {}, false
    for index, tabID in ipairs(tabIDs) do
        local tab = self:FindSidebarTab(tabID)
        if tab == nil or used[tab] then return false end
        tabs[index], used[tab] = tab, true
        moved = moved or tab ~= self.extensionTabs[index]
    end
    if not moved then return false end
    if not self.saveRailOrder(mergeRailOrder(self.readRailOrder(), tabs)) then
        if type(log) == "function" then
            log("Bank Core could not save the new sidebar icon order, so the icons keep their"
                .. " previous order. Drag the icon again to retry.")
        end
        return false
    end
    self.extensionTabs = tabs
    if self.tabRail ~= nil then self.tabRail:SetTabs(tabs, self.sidebarMode, movedID) end
    return true
end

function SidebarHost.install(bankViewClass)
    for name, method in pairs(SidebarHost) do
        if name ~= "install" then bankViewClass[name] = method end
    end
end

return SidebarHost
