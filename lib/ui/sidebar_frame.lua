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
    bankView.returnToBankButton = BankControls.button(bankView.sidebarRoot, "Return to Bank", actions.onReturn, {
        x = x + CONTENT_OFFSET, y = y,
        width = Config.SIDEBAR_COLUMN_WIDTH - 8, height = RETURN_BUTTON_HEIGHT,
        disabled = true,
    })
    bankView.tabRail = SidebarTabRail.new(bankView.sidebarRoot, {
        x = x,
        y = y,
        height = height,
        onSelect = actions.onSelect,
        onReorder = actions.onReorder,
    })
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
    bankView.tabRail:SetHeight(height)
    bankView.rail:SetSize(Config.SIDEBAR_COLUMN_WIDTH - 8, contentHeight)
    bankView.railBackground:SetSize(Config.SIDEBAR_COLUMN_WIDTH - 8, contentHeight)
end

function SidebarFrame.RaiseEdges(bankView)
    if bankView.railFrame ~= nil then bankView.railFrame:MoveToFront() end
end

function SidebarFrame.Destroy(bankView)
    local failure
    local function cleanup(action)
        local ok, message = pcall(action)
        if not ok then failure = failure or message end
    end
    if bankView.returnToBankButton ~= nil then cleanup(function() bankView.returnToBankButton:Destroy() end) end
    if bankView.tabRail ~= nil then cleanup(function() bankView.tabRail:Destroy() end) end
    if bankView.rail ~= nil then cleanup(function() prettyui.Tooltip.unregisterContext(bankView.rail) end) end
    if bankView.sidebarRoot ~= nil then cleanup(function() bankView.sidebarRoot:Destroy() end) end
    bankView.returnToBankButton = nil
    bankView.sidebarRoot = nil
    bankView.tabRail = nil
    bankView.rail = nil
    bankView.railBackground = nil
    bankView.railFrame = nil
    if failure ~= nil then error(failure, 0) end
end

return SidebarFrame
