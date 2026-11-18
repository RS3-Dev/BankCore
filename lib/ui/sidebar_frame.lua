-- Draw the sidebar's icon strip and content column.

local Config = require("lib/core/config")
local BankControls = require("lib/ui/bank_controls")
local NativeUi = require("lib/ui/native_ui")
local Theme = require("lib/ui/theme")
local SidebarTabRail = require("lib/ui/sidebar_tab_rail")
local UICoordinates = require("lib/ui/ui_coordinates")

local SidebarFrame = {}

local CONTENT_OFFSET = Config.SIDEBAR_TAB_WIDTH + Config.SIDEBAR_TAB_GAP
local HEADER_HEIGHT = 36
local RETURN_BUTTON_HEIGHT = 32
local SETTINGS_SPACE = Config.SIDEBAR_TAB_WIDTH + 4

-- Keep Core's settings below the plugin rail, outside its scrolling controls.
function SidebarFrame.PluginRailHeight(height)
    return math.max(0, height - SETTINGS_SPACE)
end

-- Reserve the top row for Core without changing plugin-local coordinates.
function SidebarFrame.ContentHeight(height)
    return math.max(0, height - HEADER_HEIGHT)
end

-- BankView calls the icon strip tabRail and the content column rail.
function SidebarFrame.Create(bankView, parent, height, x, y, actions)
    local contentHeight = SidebarFrame.ContentHeight(height)
    -- Own the whole subtree before constructors run, so partial builds can be removed.
    bankView.sidebarRoot = ui.Layer.new(parent)
    bankView.sidebarRoot:SetPos(0, 0)
    bankView.sidebarRoot:SetSize(0, 0, 1.0, 1.0)
    bankView.sidebarRoot.clickthrough = true
    -- Tooltips need a sibling of the page, rather than a child of the sidebar.
    bankView.sidebarTooltipOverlay = ui.Layer.new(parent)
    bankView.sidebarTooltipOverlay:SetPos(0, 0)
    bankView.sidebarTooltipOverlay:SetSize(0, 0, 1.0, 1.0)
    bankView.sidebarTooltipOverlay.clickthrough = true
    -- The overlay and sidebar are siblings at (0, 0); measure through their bank parent.
    local function tooltipPosition(target)
        return UICoordinates.relativePosition(target, parent)
    end
    prettyui.Tooltip.registerContext(bankView.sidebarRoot, bankView.sidebarTooltipOverlay, tooltipPosition)
    bankView.returnToBankButton = BankControls.button(bankView.sidebarRoot, "Return to Bank", actions.onReturn, {
        x = x + CONTENT_OFFSET, y = y,
        width = Config.SIDEBAR_COLUMN_WIDTH - 8, height = RETURN_BUTTON_HEIGHT,
        disabled = true,
    })
    bankView.tabRail = SidebarTabRail.new(bankView.sidebarRoot, {
        x = x,
        y = y,
        height = SidebarFrame.PluginRailHeight(height),
        onSelect = actions.onSelect,
        onReorder = actions.onReorder,
        tooltipParent = bankView.sidebarTooltipOverlay,
        tooltipPosition = tooltipPosition,
    })
    bankView.settingsButton = BankControls.button(bankView.sidebarRoot, "", actions.onSettings, {
        x = x, y = y + math.max(0, height - Config.SIDEBAR_TAB_WIDTH),
        size = Config.SIDEBAR_TAB_WIDTH, spriteName = "SETTINGS", iconSize = 20,
        tooltip = "Bank Core settings",
    })
    bankView.settingsSelectionFrame = BankControls.frame(bankView.sidebarRoot, Theme.SELECTED_BORDER)
    bankView.settingsSelectionFrame:SetPos(x, y + math.max(0, height - Config.SIDEBAR_TAB_WIDTH))
    bankView.settingsSelectionFrame:SetSize(Config.SIDEBAR_TAB_WIDTH, Config.SIDEBAR_TAB_WIDTH)
    bankView.settingsSelectionFrame.hidden = true
    bankView.rail = ui.Layer.new(bankView.sidebarRoot)
    bankView.rail:SetPos(x + CONTENT_OFFSET, y + HEADER_HEIGHT)
    bankView.rail:SetSize(Config.SIDEBAR_COLUMN_WIDTH - 8, contentHeight)
    bankView.rail.clickthrough = false
    prettyui.Tooltip.registerContext(bankView.rail, parent, function(tooltipTarget)
        return UICoordinates.relativePosition(tooltipTarget, parent)
    end)
    -- Keep the background behind plugin controls.
    bankView.railBackground = ui.Sprite.new(bankView.rail)
    bankView.railBackground:SetSize(Config.SIDEBAR_COLUMN_WIDTH - 8, contentHeight)
    bankView.railBackground.spriteID = NativeUi.PANEL_BACKGROUND_SPRITE
    bankView.railBackground.isTiling = true
    bankView.railBackground.clickthrough = true

    -- A positive outline size draws the border inside the panel.
    bankView.railFrame = BankControls.frame(bankView.rail, Theme.FRAME)
    bankView.railFrame:SetSize(0, 0, 1.0, 1.0)
end

function SidebarFrame.Resize(bankView, height)
    local contentHeight = SidebarFrame.ContentHeight(height)
    bankView.tabRail:SetHeight(SidebarFrame.PluginRailHeight(height))
    local button = bankView.settingsButton
    button.root:SetPos(bankView.tabRail.x, bankView.tabRail.y + math.max(0, height - Config.SIDEBAR_TAB_WIDTH))
    bankView.settingsSelectionFrame:SetPos(button.root.x, button.root.y)
    if button.icon ~= nil then
        button.icon:SetPos(button.root.x + 6, button.root.y + 6)
    end
    bankView.rail:SetSize(Config.SIDEBAR_COLUMN_WIDTH - 8, contentHeight)
    bankView.railBackground:SetSize(Config.SIDEBAR_COLUMN_WIDTH - 8, contentHeight)
end

function SidebarFrame.RaiseEdges(bankView)
    if bankView.railFrame ~= nil then bankView.railFrame:MoveToFront() end
    if bankView.sidebarTooltipOverlay ~= nil then bankView.sidebarTooltipOverlay:MoveToFront() end
end

-- Hide the content column without hiding the plugin rail or settings button.
function SidebarFrame.SetCollapsed(bankView, collapsed)
    if bankView.rail ~= nil then bankView.rail.hidden = collapsed end
    if bankView.returnToBankButton ~= nil then bankView.returnToBankButton.root.hidden = collapsed end
end

function SidebarFrame.Destroy(bankView)
    local failure
    local function cleanup(action)
        local ok, message = pcall(action)
        if not ok then failure = failure or message end
    end
    if bankView.returnToBankButton ~= nil then cleanup(function() bankView.returnToBankButton:Destroy() end) end
    if bankView.settingsButton ~= nil then cleanup(function() bankView.settingsButton:Destroy() end) end
    if bankView.tabRail ~= nil then cleanup(function() bankView.tabRail:Destroy() end) end
    if bankView.rail ~= nil then cleanup(function() prettyui.Tooltip.unregisterContext(bankView.rail) end) end
    if bankView.sidebarRoot ~= nil then cleanup(function() prettyui.Tooltip.unregisterContext(bankView.sidebarRoot) end) end
    if bankView.sidebarTooltipOverlay ~= nil then cleanup(function() bankView.sidebarTooltipOverlay:Destroy() end) end
    if bankView.sidebarRoot ~= nil then cleanup(function() bankView.sidebarRoot:Destroy() end) end
    bankView.returnToBankButton = nil
    bankView.settingsButton = nil
    bankView.settingsSelectionFrame = nil
    bankView.sidebarRoot = nil
    bankView.sidebarTooltipOverlay = nil
    bankView.tabRail = nil
    bankView.rail = nil
    bankView.railBackground = nil
    bankView.railFrame = nil
    if failure ~= nil then error(failure, 0) end
end

return SidebarFrame
