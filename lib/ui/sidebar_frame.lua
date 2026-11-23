-- Draw the sidebar's icon strip and content column.

local Config = require("lib/core/config")
local BankControls = require("lib/ui/bank_controls")
local NativeUi = require("lib/ui/native_ui")
local Theme = require("lib/ui/theme")
local SidebarTabRail = require("lib/ui/sidebar_tab_rail")
local UICoordinates = require("lib/ui/ui_coordinates")

local Layout = require("lib/bank/sidebar_layout")
local SidebarFrame = {}

local CONTENT_OFFSET = Config.SIDEBAR_TAB_WIDTH + Config.SIDEBAR_TAB_GAP
local HEADER_HEIGHT = 36
local RETURN_BUTTON_HEIGHT = 32
local CLASSIC_TITLE_SPRITE_HEIGHT = 40
local SETTINGS_SPACE = Config.SIDEBAR_TAB_WIDTH + 4
local SETTINGS_BOTTOM_INSET = 12

-- Follow the panel's bottom edge instead of an early content-height measurement.
local function anchorSettingsControls(bankView, x)
    local railX, parentX = Layout.Position(bankView, x, Config.SIDEBAR_TAB_WIDTH)
    local y = -SETTINGS_BOTTOM_INSET - Config.SIDEBAR_TAB_WIDTH
    bankView.settingsButton.root:SetPos(railX, y, parentX, 1)
    bankView.settingsSelectionFrame:SetPos(railX, y, parentX, 1)
    if bankView.settingsButton.icon ~= nil then
        bankView.settingsButton.icon:SetPos(railX + 6, y + 6, parentX, 1)
    end
end

-- Keep Core's settings below the plugin rail, outside its scrolling controls.
function SidebarFrame.PluginRailHeight(height)
    return math.max(0, height - SETTINGS_SPACE)
end

-- BankView calls the icon strip tabRail and the content column rail.
function SidebarFrame.Create(bankView, parent, height, x, y, actions)
    -- Own the whole subtree before constructors run, so partial builds can be removed.
    bankView.sidebarRoot = ui.Layer.new(parent)
    bankView.sidebarRoot:SetPos(0, 0)
    bankView.sidebarRoot:SetSize(0, 0, 1.0, 1.0)
    if bankView.detachedSidebar then
        -- Preserve native-bank coordinates for plugin notices and popups.
        bankView.sidebarOverlay = ui.Layer.new(parent)
        bankView.sidebarOverlay.clickthrough = true
        bankView:PositionDetachedSidebar()
    end
    bankView.sidebarRoot.clickthrough = true
    if bankView.detachedSidebar then
        -- Draw native window decorations entirely inside our detached panel.
        local function sprite(parent, spriteID, x, y, width, height, widthParent, heightParent, xParent, yParent)
            local part = ui.Sprite.new(parent)
            part.spriteID = spriteID
            if bankView.sidebarEdge == "right" then
                x, xParent = -x - width, 1 - (xParent or 0) - (widthParent or 0)
                part.isFlippedHorizontally = true
            end
            part:SetPos(x, y, xParent or 0, yParent or 0)
            part:SetSize(width, height, widthParent or 0, heightParent or 0)
            part.clickthrough = true
            return part
        end
        bankView.sidebarBackground = sprite(bankView.sidebarRoot,
            id.Sprite.RS3_MODAL_WINDOW_CONTENT_TILE, 8, CLASSIC_TITLE_SPRITE_HEIGHT,
            -9, -CLASSIC_TITLE_SPRITE_HEIGHT - 8, 1, 1)
        bankView.sidebarBackground.isTiling = true
        sprite(bankView.sidebarRoot, id.Sprite.RS3_MODAL_WINDOW_1_SIDE_TILE,
            0, CLASSIC_TITLE_SPRITE_HEIGHT, 8, -CLASSIC_TITLE_SPRITE_HEIGHT - 16, 0, 1)
        sprite(bankView.sidebarRoot, id.Sprite.RS3_MODAL_WINDOW_1_BOTTOM_TILE,
            16, -8, -16, 8, 1, 0, 0, 1)
        sprite(bankView.sidebarRoot, id.Sprite.RS3_MODAL_WINDOW_1_BOTTOM_CORNER,
            0, -16, 16, 16, 0, 0, 0, 1)
        -- Carry the icon strip's gray texture through both of its side gutters.
        bankView.sidebarRailBackdrop = sprite(bankView.sidebarRoot,
            id.Sprite.RS3_CHILD_CONTENT_TILE, 8, CLASSIC_TITLE_SPRITE_HEIGHT,
            Config.CLASSIC_SIDEBAR_LEFT_PADDING + CONTENT_OFFSET - 8,
            -CLASSIC_TITLE_SPRITE_HEIGHT - 8, 0, 1)
        bankView.sidebarRailBackdrop.isTiling = true
        -- A single joining edge avoids doubling the native bank's bevel.
        bankView.sidebarOuterFrame = ui.Rectangle.new(bankView.sidebarRoot)
        bankView.sidebarOuterFrame:SetPos(bankView.sidebarEdge == "right" and 0 or -1, 0,
            bankView.sidebarEdge == "right" and 0 or 1, 0)
        bankView.sidebarOuterFrame:SetSize(1, 0, 0, 1)
        bankView.sidebarOuterFrame.fill = true
        bankView.sidebarOuterFrame.rgba = Theme.INNER_FRAME
        bankView.sidebarOuterFrame.clickthrough = true
        bankView.sidebarHeader = ui.Layer.new(bankView.sidebarRoot)
        local fullWidth = Config.SIDEBAR_WIDTH + Config.CLASSIC_SIDEBAR_LEFT_PADDING
        bankView.sidebarHeader:SetSize(fullWidth, CLASSIC_TITLE_SPRITE_HEIGHT)
        bankView.sidebarHeader.clickthrough = true
        sprite(bankView.sidebarHeader, id.Sprite.RS3_MODAL_WINDOW_1_TITLE_CORNER,
            0, 0, 28, CLASSIC_TITLE_SPRITE_HEIGHT)
        sprite(bankView.sidebarHeader, id.Sprite.RS3_MODAL_WINDOW_1_TITLE_TILE,
            28, 0, 64, CLASSIC_TITLE_SPRITE_HEIGHT)
        sprite(bankView.sidebarHeader, id.Sprite.RS3_MODAL_WINDOW_1_TITLE_END,
            92, 0, -156, CLASSIC_TITLE_SPRITE_HEIGHT, 1, 0)
        sprite(bankView.sidebarHeader, id.Sprite.RS3_MODAL_WINDOW_1_TOP_TILE,
            -64, 0, 64, CLASSIC_TITLE_SPRITE_HEIGHT, 0, 0, 1, 0)
        -- Keep the corner bevel at its normal width when only the rail is visible.
        bankView.sidebarCollapsedHeader = ui.Layer.new(bankView.sidebarRoot)
        bankView.sidebarCollapsedHeader:SetSize(0, CLASSIC_TITLE_SPRITE_HEIGHT, 1, 0)
        bankView.sidebarCollapsedHeader.clickthrough = true
        sprite(bankView.sidebarCollapsedHeader, id.Sprite.RS3_MODAL_WINDOW_1_TITLE_CORNER,
            0, 0, 28, CLASSIC_TITLE_SPRITE_HEIGHT)
        sprite(bankView.sidebarCollapsedHeader, id.Sprite.RS3_MODAL_WINDOW_1_TOP_TILE,
            28, 0, -28, CLASSIC_TITLE_SPRITE_HEIGHT, 1, 0)
        bankView.sidebarCollapsedHeader.hidden = true
        -- Stretch every title section equally so their bottom borders meet.
        bankView.sidebarTitle = prettyui.Text.new(bankView.sidebarHeader, {
            categoryID = "auto",
            text = "Bank Plugins", x = 8, y = 4,
            width = fullWidth - 16, height = 34,
            font = id.Font.CINZEL_13PT_BOLD, colour = 0xF2C66DFF,
            alignHorizontal = ui.AlignMode.CENTRE,
            alignVertical = ui.AlignMode.CENTRE,
        })
        bankView.sidebarTitle.clickthrough = true
    end
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
        width = Config.SIDEBAR_COLUMN_WIDTH - 8,
        height = RETURN_BUTTON_HEIGHT,
        disabled = true,
    })
    bankView.tabRail = SidebarTabRail.new(bankView.sidebarRoot, {
        x = x,
        y = y,
        height = SidebarFrame.PluginRailHeight(height),
        bottomInset = SETTINGS_BOTTOM_INSET + SETTINGS_SPACE,
        onSelect = actions.onSelect,
        onReorder = actions.onReorder,
        tooltipParent = bankView.sidebarTooltipOverlay,
        tooltipPosition = tooltipPosition,
    })
    bankView.settingsButton = BankControls.button(bankView.sidebarRoot, "", actions.onSettings, {
        x = x, y = 0,
        size = Config.SIDEBAR_TAB_WIDTH, spriteName = "SETTINGS", iconSize = 20,
        tooltip = "Bank Core settings",
    })
    bankView.settingsSelectionFrame = BankControls.frame(bankView.sidebarRoot, Theme.SELECTED_BORDER)
    bankView.settingsSelectionFrame:SetSize(Config.SIDEBAR_TAB_WIDTH, Config.SIDEBAR_TAB_WIDTH)
    bankView.settingsSelectionFrame.hidden = true
    anchorSettingsControls(bankView, x)
    bankView.rail = ui.Layer.new(bankView.sidebarRoot)
    bankView.rail:SetPos(x + CONTENT_OFFSET, y + HEADER_HEIGHT)
    bankView.rail:SetSize(Config.SIDEBAR_COLUMN_WIDTH - 8,
        -y - HEADER_HEIGHT - SETTINGS_BOTTOM_INSET, 0, 1)
    bankView.rail.clickthrough = false
    prettyui.Tooltip.registerContext(bankView.rail, parent, function(tooltipTarget)
        return UICoordinates.relativePosition(tooltipTarget, parent)
    end)
    -- Keep the background behind plugin controls.
    bankView.railBackground = ui.Sprite.new(bankView.rail)
    bankView.railBackground:SetSize(0, 0, 1, 1)
    bankView.railBackground.spriteID = NativeUi.PANEL_BACKGROUND_SPRITE
    bankView.railBackground.isTiling = true
    bankView.railBackground.clickthrough = true

    -- A positive outline size draws the border inside the panel.
    bankView.railFrame = BankControls.frame(bankView.rail, Theme.FRAME)
    bankView.railFrame:SetSize(0, 0, 1.0, 1.0)
    SidebarFrame.Position(bankView)
    SidebarFrame.RaiseEdges(bankView)
end

-- Position the rail and column independently from the native bank content.
function SidebarFrame.Position(bankView)
    if bankView.tabRail == nil then return end
    local inset = Layout.Inset(bankView)
    local railX, railParent = Layout.Position(bankView, inset, Config.SIDEBAR_TAB_WIDTH)
    bankView.tabRail.root:SetPos(railX, bankView.tabRail.y, railParent, 0)
    local contentX, contentParent = Layout.Position(bankView, inset + CONTENT_OFFSET, Config.SIDEBAR_COLUMN_WIDTH - 8)
    bankView.rail:SetPos(contentX, bankView.tabRail.y + HEADER_HEIGHT, contentParent, 0)
    bankView.returnToBankButton.root:SetPos(contentX, bankView.tabRail.y, contentParent, 0)
    anchorSettingsControls(bankView, inset)
end

function SidebarFrame.Resize(bankView, height)
    bankView.tabRail:SetHeight(SidebarFrame.PluginRailHeight(height))
    SidebarFrame.Position(bankView)
    -- Backgrounds follow the window immediately; only icon pagination needs a new measurement.
end

function SidebarFrame.RaiseEdges(bankView)
    if bankView.railFrame ~= nil then bankView.railFrame:MoveToFront() end
    if bankView.sidebarOuterFrame ~= nil then bankView.sidebarOuterFrame:MoveToFront() end
    if bankView.sidebarInnerFrame ~= nil then bankView.sidebarInnerFrame:MoveToFront() end
    if bankView.sidebarTooltipOverlay ~= nil then bankView.sidebarTooltipOverlay:MoveToFront() end
end

-- Hide the content column without hiding the plugin rail or settings button.
function SidebarFrame.SetCollapsed(bankView, collapsed, hidden)
    for _, name in ipairs({ "sidebarRoot", "sidebarTooltipOverlay", "sidebarOverlay" }) do
        if bankView[name] ~= nil then bankView[name].hidden = hidden == true end
    end
    if bankView.rail ~= nil then bankView.rail.hidden = collapsed end
    if bankView.returnToBankButton ~= nil then bankView.returnToBankButton.root.hidden = collapsed end
    if bankView.detachedSidebar then
        if bankView.sidebarHeader ~= nil then bankView.sidebarHeader.hidden = collapsed end
        if bankView.sidebarCollapsedHeader ~= nil then bankView.sidebarCollapsedHeader.hidden = not collapsed end
    end
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
    if bankView.sidebarOverlay ~= nil then cleanup(function() bankView.sidebarOverlay:Destroy() end) end
    bankView.returnToBankButton = nil
    bankView.settingsButton = nil
    bankView.settingsSelectionFrame = nil
    bankView.sidebarRoot = nil
    bankView.sidebarOverlay = nil
    bankView.sidebarBackground = nil
    bankView.sidebarRailBackdrop = nil
    bankView.sidebarOuterFrame = nil
    bankView.sidebarInnerFrame = nil
    bankView.sidebarHeader = nil
    bankView.sidebarCollapsedHeader = nil
    bankView.sidebarTitle = nil
    bankView.sidebarTooltipOverlay = nil
    bankView.tabRail = nil
    bankView.rail = nil
    bankView.railBackground = nil
    bankView.railFrame = nil
    if failure ~= nil then error(failure, 0) end
end

return SidebarFrame
