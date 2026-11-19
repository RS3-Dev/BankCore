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
local CLASSIC_TITLE_SPRITE_HEIGHT = 40

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
    if bankView.detachedSidebar then
        -- Preserve native-bank coordinates for plugin notices and popups.
        bankView.sidebarOverlay = ui.Layer.new(parent)
        bankView.sidebarOverlay.clickthrough = true
        bankView:PositionDetachedSidebar()
    end
    bankView.sidebarRoot.clickthrough = true
    if bankView.detachedSidebar then
        -- Draw native window decorations entirely inside our detached panel.
        local function sprite(parent, spriteID, x, y, width, height, widthParent, heightParent)
            local part = ui.Sprite.new(parent)
            part.spriteID = spriteID
            part:SetPos(x, y)
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
        local bottom = sprite(bankView.sidebarRoot, id.Sprite.RS3_MODAL_WINDOW_1_BOTTOM_TILE,
            16, -8, -16, 8, 1, 0)
        bottom:SetPos(16, -8, 0, 1)
        local corner = sprite(bankView.sidebarRoot, id.Sprite.RS3_MODAL_WINDOW_1_BOTTOM_CORNER,
            0, -16, 16, 16)
        corner:SetPos(0, -16, 0, 1)
        -- Carry the icon strip's gray texture through both of its side gutters.
        bankView.sidebarRailBackdrop = sprite(bankView.sidebarRoot,
            id.Sprite.RS3_CHILD_CONTENT_TILE, 8, CLASSIC_TITLE_SPRITE_HEIGHT,
            Config.CLASSIC_SIDEBAR_LEFT_PADDING + CONTENT_OFFSET - 8,
            -CLASSIC_TITLE_SPRITE_HEIGHT - 8, 0, 1)
        bankView.sidebarRailBackdrop.isTiling = true
        -- A single joining edge avoids doubling the native bank's bevel.
        bankView.sidebarOuterFrame = ui.Rectangle.new(bankView.sidebarRoot)
        bankView.sidebarOuterFrame:SetPos(-1, 0, 1, 0)
        bankView.sidebarOuterFrame:SetSize(1, 0, 0, 1)
        bankView.sidebarOuterFrame.fill = true
        bankView.sidebarOuterFrame.rgba = Theme.INNER_FRAME
        bankView.sidebarOuterFrame.clickthrough = true
        bankView.sidebarHeader = ui.Layer.new(bankView.sidebarRoot)
        bankView.sidebarHeader:SetSize(0, CLASSIC_TITLE_SPRITE_HEIGHT, 1, 0)
        bankView.sidebarHeader.clickthrough = true
        sprite(bankView.sidebarHeader, id.Sprite.RS3_MODAL_WINDOW_1_TITLE_CORNER,
            0, 0, 28, CLASSIC_TITLE_SPRITE_HEIGHT)
        sprite(bankView.sidebarHeader, id.Sprite.RS3_MODAL_WINDOW_1_TITLE_TILE,
            28, 0, 64, CLASSIC_TITLE_SPRITE_HEIGHT)
        sprite(bankView.sidebarHeader, id.Sprite.RS3_MODAL_WINDOW_1_TITLE_END,
            92, 0, -156, CLASSIC_TITLE_SPRITE_HEIGHT, 1, 0)
        local endTile = sprite(bankView.sidebarHeader, id.Sprite.RS3_MODAL_WINDOW_1_TOP_TILE,
            -64, 0, 64, CLASSIC_TITLE_SPRITE_HEIGHT)
        endTile:SetPos(-64, 0, 1, 0)
        -- Stretch every title section equally so their bottom borders meet.
        bankView.sidebarTitle = prettyui.Text.new(bankView.sidebarHeader, {
            text = "Bank Plugins", x = 8, y = 4,
            width = bankView.sidebarRoot.width - 16, height = 34,
            font = id.Font.CINZEL_13PT_BOLD, colour = 0xF2C66DFF,
            alignHorizontal = ui.AlignMode.CENTRE,
            alignVertical = ui.AlignMode.CENTRE,
        })
        bankView.sidebarTitle.clickthrough = true
    end
    bankView.returnToBankButton = BankControls.button(bankView.sidebarRoot, "Return to Bank", actions.onReturn, {
        x = x + CONTENT_OFFSET, y = y,
        width = Config.SIDEBAR_COLUMN_WIDTH - 8,
        height = RETURN_BUTTON_HEIGHT,
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
    SidebarFrame.RaiseEdges(bankView)
end

function SidebarFrame.Resize(bankView, height)
    local contentHeight = SidebarFrame.ContentHeight(height)
    bankView.tabRail:SetHeight(height)
    bankView.rail:SetSize(Config.SIDEBAR_COLUMN_WIDTH - 8, contentHeight)
    bankView.railBackground:SetSize(Config.SIDEBAR_COLUMN_WIDTH - 8, contentHeight)
end

function SidebarFrame.RaiseEdges(bankView)
    if bankView.railFrame ~= nil then bankView.railFrame:MoveToFront() end
    if bankView.sidebarOuterFrame ~= nil then bankView.sidebarOuterFrame:MoveToFront() end
    if bankView.sidebarInnerFrame ~= nil then bankView.sidebarInnerFrame:MoveToFront() end
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
    if bankView.sidebarOverlay ~= nil then cleanup(function() bankView.sidebarOverlay:Destroy() end) end
    bankView.returnToBankButton = nil
    bankView.sidebarRoot = nil
    bankView.sidebarOverlay = nil
    bankView.sidebarBackground = nil
    bankView.sidebarRailBackdrop = nil
    bankView.sidebarOuterFrame = nil
    bankView.sidebarInnerFrame = nil
    bankView.sidebarHeader = nil
    bankView.sidebarTitle = nil
    bankView.tabRail = nil
    bankView.rail = nil
    bankView.railBackground = nil
    bankView.railFrame = nil
    if failure ~= nil then error(failure, 0) end
end

return SidebarFrame
