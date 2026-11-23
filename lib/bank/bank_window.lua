-- Resize and position the bank to make room for the sidebar

local Config = require("lib/core/config")
local BankInterface = require("lib/core/bank_interface")
local BankGrid = require("lib/engine/bank_grid")
local UICoordinates = require("lib/ui/ui_coordinates")
local DebugLog = require("lib/core/debug_log")
local debugLog = DebugLog.Write

-- Always log window failures.
local function report(...)
    if type(log) == "function" then log(...) end
end

local SidebarLayout = require("lib/bank/sidebar_layout")
local BankWindow = {}

local COMPONENTS = {
    all = id.Component.BANK__ALL,
    background = id.Component.BANK__BACKGROUND_LAYER,
    content = id.Component.BANK__CONTENT,
    border = id.Component.BANK__BORDER_LAYER,
    help = id.Component.BANK__HELP_BUTTON_LAYER,
    close = id.Component.BANK__CLOSE_BUTTON_LAYER,
}

local FULL_WIDTH_OVERLAYS = {
    -- Keep numeric record keys so existing saved geometry can still be restored.
    [314] = id.Component.BANK__GROUP_IRONMAN_LOADING,
    [315] = id.Component.BANK__COM_315,
    [316] = id.Component.BANK__GROUP_IRONMAN_SPINNER,
    [318] = id.Component.BANK__CONFIRM_DROP_ITEM_LAYER,
    [319] = id.Component.BANK__CONFIRM_BACK_RECT,
    [330] = id.Component.BANK__CONFIRM_WITHDRAW_ITEM_LAYER,
    [331] = id.Component.BANK__CONFIRM_WITHDRAW_BACK_RECT,
    [340] = id.Component.BANK__CUSTOM_X_INPUT_CLICKOUT,
}
local CENTRED_DIALOGS = {
    -- Keep numeric record keys so existing saved geometry can still be restored.
    [320] = id.Component.BANK__CONFIRM_PANEL_CONTAINER,
    [332] = id.Component.BANK__CONFIRM_WITHDRAW_PANEL_CONTAINER,
}
local BANK_ITEMS_COMPONENT_ID = BankInterface.ITEMS
local BANK_ITEMS_CONTAINER_COMPONENT_ID = BankInterface.ITEMS_CONTAINER
local ALL_TAB_BUTTON_COMPONENT_ID = id.Component.BANK__ALL_TAB_BTN
local ALL_TAB_CONTAINER_COMPONENT_ID = id.Component.BANK__TABS_ALL_BUTTON
local ALL_TAB_BUTTON_CATEGORY_ID = 0
local ALL_TAB_BUTTON_DYNAMIC_ID = 0
local CANCEL_CONTROL_COMPONENT_ID = id.Component.BANK__BOTTOM_PANEL_CANCEL
local CANCEL_LABEL_CATEGORY_ID = 0
local CANCEL_LABEL_DYNAMIC_ID = 9
local PRESET_CLOSE_BUTTON_COMPONENT_ID = id.Component.BANK__PRESET_CLOSE

local function registerTabSprites(selectionBySprite, selected, unselected)
    if selected ~= nil and unselected ~= nil and selected ~= unselected then
        selectionBySprite[selected] = true
        selectionBySprite[unselected] = false
    end
end

local ALL_TAB_SELECTION_BY_SPRITE = {}
registerTabSprites(ALL_TAB_SELECTION_BY_SPRITE,
    id.Sprite.BANK_TABS_HORIZONTAL_1, id.Sprite.BANK_TABS_HORIZONTAL_0)
registerTabSprites(ALL_TAB_SELECTION_BY_SPRITE,
    id.Sprite.BANK_TABS_HORIZONTAL_LEGACY_1, id.Sprite.BANK_TABS_HORIZONTAL_LEGACY_0)
registerTabSprites(ALL_TAB_SELECTION_BY_SPRITE,
    id.Sprite.BANK_TABS_VERTICAL_3, id.Sprite.BANK_TABS_VERTICAL_4)
registerTabSprites(ALL_TAB_SELECTION_BY_SPRITE,
    id.Sprite.BANK_TABS_VERTICAL_LEGACY_3, id.Sprite.BANK_TABS_VERTICAL_LEGACY_4)
-- The game has no window move or resize events.
local BANK_WINDOW_CHECK_TICKS = 10

local component = BankInterface.Get

local function interfaceMode()
    if type(prettyui) == "table" and type(prettyui.IsClassicUI) == "function" then
        local ok, classic = pcall(function() return prettyui.IsClassicUI() end)
        if ok and type(classic) == "boolean" then
            return classic and "classic" or "modern", "prettyui.IsClassicUI()=" .. tostring(classic)
        end
    end
    local ok, value = pcall(function() return var.VarPlayer["TOPLEVEL_V2_LEGACY_INTERFACE"].value end)
    if not ok or type(value) ~= "number" then
        return "unknown", "TOPLEVEL_V2_LEGACY_INTERFACE=unavailable"
    end
    local mode = value == 1 and "classic" or (value == 0 and "modern" or "unknown")
    return mode, "TOPLEVEL_V2_LEGACY_INTERFACE=" .. tostring(value)
end

-- Report mode detection only when debug logging is enabled.
function BankWindow.LogInterfaceMode()
    if not DebugLog.IsEnabled() then return end
    local mode, source = interfaceMode()
    debugLog("Bank Core interface mode: ", mode, " (", source,
        "); sidebar layout: ", mode == "classic" and "detached" or "integrated")
end

-- Classic mode needs a separate sidebar beside the native bank.
local function classicUI()
    return interfaceMode() == "classic"
end

function BankWindow.IsClassicUI()
    return classicUI()
end

local function sidebarParent(self)
    if not self.detachedSidebar then return self.components.all end
    local bankLayer = component(id.Component.TOPLEVEL_V2__BANK_LAYER)
    local gameArea = component(id.Component.TOPLEVEL_V2__GAME_AREA)
    local function usable(value)
        return value ~= nil and value.hidden ~= true and value.visibleGlobal ~= false
            and value.width > 0 and value.height > 0
    end
    -- Keep a usable parent through the opening transition instead of rebuilding it.
    local current = self.sidebarRoot ~= nil and self.sidebarRoot.parent or nil
    if usable(current) and (current == bankLayer or current == gameArea
        or tostring(current) == tostring(bankLayer) or tostring(current) == tostring(gameArea)) then return current end
    if usable(bankLayer) then return bankLayer end
    if usable(gameArea) then return gameArea end
    return nil
end

local function sidebarIsCollapsed(self)
    if self.IsSidebarCollapsed ~= nil then return self:IsSidebarCollapsed() end
    return self.sidebarOpeningState ~= "expanded" and self.sidebarMode == nil
end

-- Follow the bank using coordinates in the outer layer.
function BankWindow:PositionDetachedSidebar()
    if not self.detachedSidebar or self.sidebarRoot == nil then return end
    local x, y = UICoordinates.absolutePosition(self.components.all)
    local parentX, parentY = UICoordinates.absolutePosition(self.sidebarRoot.parent)
    local contentWidth = sidebarIsCollapsed(self)
        and (Config.SIDEBAR_TAB_WIDTH + Config.SIDEBAR_TAB_GAP) or Config.SIDEBAR_WIDTH
    local width = contentWidth + Config.CLASSIC_SIDEBAR_LEFT_PADDING
    local sidebarX = self.sidebarEdge == "right" and x + self.components.all.width or x - width
    local localX, localY = sidebarX - parentX, y - parentY
    if self.sidebarRoot.x ~= localX or self.sidebarRoot.y ~= localY then
        self.sidebarRoot:SetPos(localX, localY)
    end
    if self.sidebarRoot.width ~= width or self.sidebarRoot.height ~= self.components.all.height then
        self.sidebarRoot:SetSize(width, self.components.all.height)
    end
    if self.sidebarOverlay ~= nil then
        if self.sidebarOverlay.x ~= x - parentX or self.sidebarOverlay.y ~= y - parentY then
            self.sidebarOverlay:SetPos(x - parentX, y - parentY)
        end
        if self.sidebarOverlay.width ~= self.components.all.width
            or self.sidebarOverlay.height ~= self.components.all.height then
            self.sidebarOverlay:SetSize(self.components.all.width, self.components.all.height)
        end
    end
end

-- Find a bank control that may disappear when views change.
local function dynamicComponent(componentID, categoryID, dynamicID)
    local ok, value = pcall(function()
        return ui.Interfaces:GetComponent(
            componentID,
            categoryID,
            dynamicID
        )
    end)
    return ok and value or nil
end

local MAX_PARENT_DEPTH = 32

-- Two references to the same control may compare as different.
local function samePart(firstComponent, secondComponent)
    return firstComponent ~= nil and secondComponent ~= nil and (firstComponent == secondComponent or tostring(firstComponent) == tostring(secondComponent))
end

local function readPartLayout(value)
    local position, size = value.position, value.size
    return {
        x = position.x, y = position.y,
        xParent = position.xParentPc, yParent = position.yParentPc,
        xSelf = position.xSelfPc, ySelf = position.ySelfPc,
        width = size.width, height = size.height,
        widthParent = size.widthParentPc, heightParent = size.heightParentPc,
    }
end

-- Adjust position and width without changing how the control is aligned.
local function offsetPart(value, x, width, applied)
    local partLayout = readPartLayout(value)
    if width ~= 0 then
        value:SetSize(partLayout.width + width, partLayout.height, partLayout.widthParent, partLayout.heightParent)
        if applied ~= nil then applied.width = width end
    end
    if x ~= 0 then
        value:SetPos(partLayout.x + x, partLayout.y, partLayout.xParent, partLayout.yParent, partLayout.xSelf, partLayout.ySelf)
        if applied ~= nil then applied.x = x end
    end
end

local function round(value)
    return math.floor(value + 0.5)
end

-- Grow toward the chosen edge, or evenly around the native center.
local function expansionChanges(parts, width, direction, edge)
    local expansionPlan = {}
    local leftWidth = SidebarLayout.LeftGrowth(width, direction, edge)
    local contentOffset = SidebarLayout.BeforeBank(width, edge)
    local function add(slot, value, x, change)
        if value ~= nil then
            expansionPlan[#expansionPlan + 1] = { slot = slot, value = value, x = x, width = change }
        end
    end
    -- Move the outer frame if present; otherwise move the bank window itself.
    if parts.host ~= nil and not samePart(parts.host, parts.all) then
        add("host", parts.host, -leftWidth, width)
        add("all", parts.all, 0, width)
    else
        add("all", parts.all, -leftWidth, width)
    end
    add("background", parts.background, 0, width)
    add("border", parts.border, 0, width)
    for key, value in pairs(parts.overlays) do add("overlay" .. key, value, 0, width) end
    for key, value in pairs(parts.dialogs) do add("dialog" .. key, value, leftWidth, 0) end
    add("content", parts.content, contentOffset, 0)
    add("help", parts.help, width, 0)
    add("close", parts.close, width, 0)
    return expansionPlan
end

-- Include width added by resizing the containing control.
local function widthChange(value, expansionPlan, depth)
    if value == nil or depth > MAX_PARENT_DEPTH then return 0 end
    for _, change in ipairs(expansionPlan) do
        if samePart(change.value, value) then return change.width end
    end
    local parentWidthRatio = readPartLayout(value).widthParent
    if parentWidthRatio == 0 then return 0 end
    return parentWidthRatio * widthChange(value.parent, expansionPlan, depth + 1)
end

-- Do not add width twice when a control grows with its container.
local function expandWindow(parts, width, appliedOffsets, direction, edge)
    local expansionPlan = expansionChanges(parts, width, direction, edge)
    local plannedOffsets = {}
    for _, change in ipairs(expansionPlan) do
        local partLayout = readPartLayout(change.value)
        local parentWidthChange = widthChange(change.value.parent, expansionPlan, 1)
        plannedOffsets[#plannedOffsets + 1] = {
            slot = change.slot,
            value = change.value,
            width = round(change.width - partLayout.widthParent * parentWidthChange),
            -- Self anchoring subtracts the added width, so add it back here.
            x = round(change.x - partLayout.xParent * parentWidthChange + partLayout.xSelf * change.width),
        }
    end
    for _, entry in ipairs(plannedOffsets) do
        local applied = { slot = entry.slot, value = entry.value, x = 0, width = 0 }
        appliedOffsets[#appliedOffsets + 1] = applied
        offsetPart(entry.value, entry.x, entry.width, applied)
    end
    return appliedOffsets
end

-- Undo Core's window changes while keeping the player's resizing.
local function undoExpansion(appliedOffsets)
    local allPartsRestored = true
    for _, entry in ipairs(appliedOffsets) do
        local ok, message = pcall(function() offsetPart(entry.value, -entry.x, -entry.width) end)
        if not ok then
            allPartsRestored = false
            debugLog("Bank Core could not restore the bank's ", entry.slot, ": ", tostring(message))
        end
    end
    return allPartsRestored
end

local function findPartByName(parts, slot)
    local overlay = string.match(slot, "^overlay(.+)$")
    if overlay ~= nil then return parts.overlays[tonumber(overlay) or overlay] end
    local dialog = string.match(slot, "^dialog(.+)$")
    if dialog ~= nil then return parts.dialogs[tonumber(dialog) or dialog] end
    return parts[slot]
end

-- Find which window frame Core widened.
local function findFrameRecord(record)
    local layer = nil
    for _, entry in ipairs(record.parts) do
        if entry.slot == "host" then return entry end
        if entry.slot == "all" then layer = entry end
    end
    return layer
end

-- Find the frame again in case the game replaced it.
local function findCurrentFrame(slot)
    local ok, value = pcall(function()
        if slot == "host" then
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_WINDOW)
        end
        return component(COMPONENTS.all)
    end)
    return ok and value or nil
end

-- The game may have removed this control.
local function tryReadPartLayout(value)
    local ok, partLayout = pcall(readPartLayout, value)
    if not ok or type(partLayout.x) ~= "number" or type(partLayout.width) ~= "number" then return nil end
    return partLayout
end

-- Undo any remaining added width; retry failures when Core next connects to the bank.
function BankWindow.RecoverExpansion(parts, record)
    if record == nil then return true end
    local frame = findFrameRecord(record)
    local appliedOffsets = {}
    for _, entry in ipairs(record.parts) do
        local value = not entry.restored and findPartByName(parts, entry.slot) or nil
        local partLayout = value ~= nil and tryReadPartLayout(value) or nil
        if partLayout ~= nil and (entry.x ~= 0 or entry.width ~= 0)
            and partLayout.width == entry.expandedWidth
            and (entry == frame or partLayout.x == entry.expandedX) then
            appliedOffsets[#appliedOffsets + 1] = { slot = entry.slot, value = value, x = entry.x,
                width = entry.width, entry = entry, nativeX = partLayout.x - entry.x }
        elseif entry == frame and partLayout ~= nil
            and partLayout.width ~= entry.expandedWidth - entry.width then
            debugLog("Bank Core kept a bank window width set while it was off: ", partLayout.width)
        end
    end
    if #appliedOffsets > 0 then
        report("Bank Core taking a kept sidebar expansion of ", record.sidebarWidth,
            " pixels off the bank")
        undoExpansion(appliedOffsets)
    end
    local recovered = true
    for _, change in ipairs(appliedOffsets) do
        local entry = change.entry
        local value = entry == frame and findCurrentFrame(entry.slot) or change.value
        local partLayout = value ~= nil and tryReadPartLayout(value) or nil
        if partLayout ~= nil and partLayout.x == change.nativeX
            and partLayout.width == entry.expandedWidth - entry.width then
            entry.restored = true
        else
            recovered = false
        end
    end
    if not recovered then
        report("Bank Core could not take a kept sidebar expansion off the bank; will retry")
        return false
    end
    return true
end

function BankWindow:LogBankWindowMeasurements(reason)
    if not DebugLog.IsEnabled() then return end
    local parts = self.components
    local options = game and game.options
    local scale = options and options.InterfaceScale
    debugLog("Bank Core bank window ", reason, ": expanded ", tostring(self.expanded),
        ", interface scale ", tostring(scale and scale.setting))
    local list = {
        { "host", parts.host }, { "all", parts.all }, { "background", parts.background },
        { "border", parts.border }, { "content", parts.content }, { "help", parts.help },
        { "close", parts.close },
        { "viewport", BankInterface.Find(BANK_ITEMS_CONTAINER_COMPONENT_ID) },
        { "items", BankInterface.Find(BANK_ITEMS_COMPONENT_ID) },
    }
    for _, entry in ipairs(list) do
        local name, value = entry[1], entry[2]
        local ok, line = pcall(function()
            local partLayout = readPartLayout(value)
            local anchorDetails = string.format("pos %s,%s parent %s,%s self %s,%s size %sx%s parent %s,%s",
                partLayout.x, partLayout.y, partLayout.xParent, partLayout.yParent, partLayout.xSelf, partLayout.ySelf,
                partLayout.width, partLayout.height, partLayout.widthParent, partLayout.heightParent)
            -- Compare both position measurements while changing display scale or scrolling.
            local x, y = UICoordinates.absolutePosition(value)
            local global = value.xyGlobal
            return string.format("%s,%s %sx%s; %s; screen %s,%s API %s,%s",
                value.x, value.y, value.width, value.height, anchorDetails, x, y, global.x, global.y)
        end)
        debugLog("Bank Core bank window ", name, ": ", ok and line or "unreadable")
    end
end

function BankWindow:RebuildPageInput()
    self.itemHover:RemovePageInput()
    if self.shownPage ~= nil then self.itemHover:BuildPageInput() end
end

local function frameMoved(layout, entry)
    if layout.xParent ~= 0 or layout.xSelf ~= 0 then
        return math.abs(layout.x - entry.expandedX) > 2
    end
    local leftMoved = math.abs(layout.x - entry.expandedX) > 2
    local rightMoved = math.abs((layout.x + layout.width) - (entry.expandedX + entry.expandedWidth)) > 2
    local centerMoved = math.abs((layout.x + layout.width * 0.5) - (entry.expandedX + entry.expandedWidth * 0.5)) > 2
    return leftMoved and rightMoved and centerMoved
end

-- Detect when the client strips Core's added frame width or snaps the frame smaller during a move.
local function isFrameWidthReset(layout, entry)
    if layout == nil or entry == nil or entry.width <= 0 then return false end
    if math.abs(layout.width - (entry.expandedWidth - entry.width)) <= 2 then return true end
    return layout.width < entry.expandedWidth - 2 and frameMoved(layout, entry)
end

-- Remember the player's window size while the sidebar is open
function BankWindow:CaptureFrame()
    local record = self.windowRecord.value
    -- Do not replace the saved frame with a bank layout reset by the game.
    if record ~= nil then
        for _, part in ipairs(record.parts) do
            if part.slot == "content" then
                local content = self.components.content
                local layout = content ~= nil and tryReadPartLayout(content) or nil
                if layout == nil or layout.x ~= part.expandedX or layout.width ~= part.expandedWidth then return end
            end
        end
    end
    local entry = record ~= nil and findFrameRecord(record) or nil
    local value = entry ~= nil and findPartByName(self.components, entry.slot) or nil
    if value == nil then return end
    local partLayout = tryReadPartLayout(value)
    if partLayout == nil then
        debugLog("Bank Core could not read the bank window frame; keeping its last width")
        return
    end
    if isFrameWidthReset(partLayout, entry) then
        debugLog("Bank Core ignored a native frame width shrink while capturing geometry: ",
            partLayout.width, " vs ", entry.expandedWidth)
        return
    end
    entry.expandedX, entry.expandedWidth = partLayout.x, partLayout.width
end

-- Find each window part using its saved name.
local function lookUpParts()
    local parts = {
        host = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_WINDOW),
        overlays = {},
        dialogs = {},
    }
    for slot, componentID in pairs(COMPONENTS) do parts[slot] = component(componentID) end
    for recordID, componentID in pairs(FULL_WIDTH_OVERLAYS) do
        parts.overlays[recordID] = component(componentID)
    end
    for recordID, componentID in pairs(CENTRED_DIALOGS) do
        parts.dialogs[recordID] = component(componentID)
    end
    return parts
end

local function frameOffsets(entry)
    local frame = findCurrentFrame(entry.slot)
    return frame ~= nil and tryReadPartLayout(frame) or nil
end

-- Reapply the recorded expansion without clearing it or adding width again.
function BankWindow:FixBankGeometry(preserveMovedFrame)
    if not self.active then return false end
    local ok, message = pcall(function()
        if self.detachedSidebar then
            self:PositionDetachedSidebar()
        else
            local record = self.windowRecord.value
            if record == nil then error("No saved bank geometry is available.", 0) end
            local parts = lookUpParts()
            local frameEntry = findFrameRecord(record)
            local changes = {}
            for _, entry in ipairs(record.parts) do
                local value = findPartByName(parts, entry.slot)
                if value ~= nil then
                    local layout = readPartLayout(value)
                    changes[#changes + 1] = { value = value, layout = layout, entry = entry }
                elseif entry.slot == "host" or COMPONENTS[entry.slot] ~= nil then
                    error("Bank control is unavailable: " .. entry.slot, 0)
                end
            end
            for _, change in ipairs(changes) do
                local value, layout, entry = change.value, change.layout, change.entry
                local targetX, targetWidth = entry.expandedX, entry.expandedWidth
                if preserveMovedFrame and entry == frameEntry then
                    local nativeResetX = layout.x == entry.expandedX - entry.x
                    if layout.x ~= entry.expandedX and not nativeResetX then
                        targetX = layout.x
                        entry.expandedX = layout.x
                    end
                    if layout.width > entry.expandedWidth then
                        targetWidth = layout.width
                        entry.expandedWidth = layout.width
                    end
                end
                value:SetSize(targetWidth, layout.height, layout.widthParent, layout.heightParent)
                value:SetPos(targetX, layout.y, layout.xParent, layout.yParent, layout.xSelf, layout.ySelf)
            end
            -- Undo these offsets on close using the current component handles.
            self.components, self.expansion = parts, {}
            for _, change in ipairs(changes) do
                local entry = change.entry
                self.expansion[#self.expansion + 1] = {
                    slot = entry.slot, value = change.value, x = entry.x, width = entry.width,
                }
            end
            self.expansionRecord = record
            self.windowRecord:Save()
        end
        self:ResizeSidebar(self.components.content.height)
        self.lastBankWindowMeasurements = nil
        self:Changed(true)
    end)
    if not ok then report("Bank Core could not fix bank geometry: ", tostring(message)) end
    return ok
end

-- Restore Core's added frame width when the client snaps the frame smaller during a move or reset.
function BankWindow:RestoreExpandedFrameWidth(frame, frameLayout, frameEntry)
    local ok, message = pcall(function()
        local targetX = frameLayout.x
        if frameLayout.x == frameEntry.expandedX - frameEntry.x then
            targetX = frameEntry.expandedX
        else
            frameEntry.expandedX = frameLayout.x
        end
        frame:SetSize(frameEntry.expandedWidth, frameLayout.height,
            frameLayout.widthParent, frameLayout.heightParent)
        if targetX ~= frameLayout.x then
            frame:SetPos(targetX, frameLayout.y, frameLayout.xParent, frameLayout.yParent,
                frameLayout.xSelf, frameLayout.ySelf)
        end
        self.windowRecord:Save()
        self.lastBankWindowMeasurements = nil
        self:Changed(false)
    end)
    if not ok then debugLog("Bank Core could not restore bank frame width: ", tostring(message)) end
    return ok
end

-- Native layout settlement can replace child offsets after immediate attachment.
local function liveExpansionOffsets(self, record)
    local savedParts = {}
    for _, part in ipairs(record ~= nil and record.parts or {}) do savedParts[part.slot] = part end
    local frame = record ~= nil and findFrameRecord(record) or nil
    local offsets = {}
    for _, applied in ipairs(self.expansion or {}) do
        local x, width = applied.x, applied.width
        local saved = savedParts[applied.slot]
        if saved ~= nil then
            local layout = tryReadPartLayout(applied.value)
            if layout ~= nil then
                if saved == frame then
                    if saved.width ~= 0 and math.abs(layout.width - (saved.expandedWidth - saved.width)) <= 2 then
                        width = 0
                        if layout.x == saved.expandedX - saved.x then x = 0 end
                        debugLog("Bank Core skipped restoring frame width already reset by the client")
                    end
                else
                    if layout.x ~= saved.expandedX then x = 0 end
                    if layout.width ~= saved.expandedWidth then width = 0 end
                    if x ~= applied.x or width ~= applied.width then
                        debugLog("Bank Core kept native layout changes for ", applied.slot,
                            "; removing only offsets still present")
                    end
                end
            end
        end
        offsets[#offsets + 1] = { slot = applied.slot, value = applied.value, x = x, width = width }
    end
    return offsets
end

-- Remove the width Core added, keeping player resizes and the saved changes.
function BankWindow:RestoreBankWindowSizeAndPosition()
    if self.detachedSidebar then return end
    -- A failed resize may have applied only some offsets, without creating a new record.
    if self.expansionRecord ~= self.windowRecord.value then
        if not undoExpansion(self.expansion or {}) then
            report("Bank Core could not fully undo a partial sidebar expansion")
        end
        self.expansion = nil
        return
    end
    BankWindow.CaptureFrame(self)
    local record = self.windowRecord.value
    local allPartsRestored = undoExpansion(liveExpansionOffsets(self, record))
    self.expansion = nil
    if record == nil then return end
    local entry = findFrameRecord(record)
    local partLayout = frameOffsets(entry)
    -- Find the current controls before undoing remaining window changes.
    if partLayout ~= nil and partLayout.width == entry.expandedWidth then
        local ok, message = pcall(function()
            allPartsRestored = BankWindow.RecoverExpansion(lookUpParts(), record)
        end)
        if not ok then debugLog("Bank Core could not look up the bank's parts: ", message) end
        -- Check window changes again when Core next connects to the bank.
        for _, part in ipairs(record.parts) do part.restored = nil end
        partLayout = frameOffsets(entry)
    end
    if partLayout == nil then
        debugLog("Bank Core could not read the bank window frame after restoring it")
    elseif not allPartsRestored or partLayout.width ~= entry.expandedWidth - entry.width then
        report("Bank Core could not confirm the bank window lost the sidebar's width: ",
            partLayout.width, " for ", entry.expandedWidth - entry.width)
    end
end

-- Reserve the rail alone when the optional content column is collapsed.
local function sidebarExpansionWidth(self)
    if self.IsSidebarHidden ~= nil and self:IsSidebarHidden() then return 0 end
    if sidebarIsCollapsed(self) then
        return Config.SIDEBAR_TAB_WIDTH + Config.SIDEBAR_TAB_GAP
    end
    return Config.SIDEBAR_WIDTH
end

-- Widen the bank for the sidebar and record what it added.
function BankWindow:WidenBankForSidebar(width)
    if self.detachedSidebar then return end
    width = width or sidebarExpansionWidth(self)
    self.expansion = {}
    self.expansionRecord = nil
    expandWindow(self.components, width, self.expansion, self.expansionDirection, self.sidebarEdge)
    local record = { sidebarWidth = width, parts = {} }
    for _, entry in ipairs(self.expansion) do
        local partLayout = readPartLayout(entry.value)
        record.parts[#record.parts + 1] = { slot = entry.slot, x = entry.x, width = entry.width,
            expandedX = partLayout.x, expandedWidth = partLayout.width }
    end
    self.windowRecord.value = record
    self.expansionRecord = record
end

-- Replace only Core's added width, keeping the player's native window size.
function BankWindow:UpdateSidebarExpansion(force)
    if self.detachedSidebar then
        self:PositionDetachedSidebar()
        self.lastBankWindowMeasurements = nil
        return
    end
    local width = sidebarExpansionWidth(self)
    if not force and self.expansionRecord ~= nil and self.expansionRecord.sidebarWidth == width then return end
    local anchorX
    local anchorRatio = SidebarLayout.Anchor(self.expansionDirection, self.sidebarEdge)
    if not force and self.expansionRecord ~= nil then
        local frame = self.components.host or self.components.all
        local x = UICoordinates.absolutePosition(frame)
        anchorX = x + frame.width * anchorRatio
    end
    self:RestoreBankWindowSizeAndPosition()
    self:WidenBankForSidebar(width)
    if anchorX ~= nil then
        -- The native client can change anchors after our immediate attachment.
        local frame = self.components.host or self.components.all
        local x = UICoordinates.absolutePosition(frame)
        local correction = round(anchorX - x - frame.width * anchorRatio)
        if correction ~= 0 then
            offsetPart(frame, correction, 0)
            local entry = findFrameRecord(self.expansionRecord)
            entry.expandedX = readPartLayout(frame).x
            -- Rebase the native position; keep Core's reversible offsets unchanged.
            debugLog("Bank Core preserved the live window anchor after native layout settlement: ", correction)
        end
    end
    self.windowRecord:Save()
    self.lastBankWindowMeasurements = nil
end

function BankWindow:ReadBankWindowMeasurements()
    if not self.active then return nil end
    local frame = self.components.host or self.components.all
    -- Window parts may disappear between checks.
    local itemLayer = BankInterface.Find(BANK_ITEMS_COMPONENT_ID)
    local itemWidth = itemLayer ~= nil and itemLayer.width or 0
    if frame == nil or itemWidth <= 0 then return nil end
    local x, y = UICoordinates.absolutePosition(frame)
    -- Use the column count of the displayed layout.
    local columns = self.shownPage ~= nil and self.pageState.columns
        or BankGrid.ColumnCount(itemWidth)
    return {
        columns = columns,
        bounds = { x = x, y = y, width = frame.width,
            height = frame.height },
    }
end

local function describeBankWindowMeasurements(bankWindowMeasurements)
    if bankWindowMeasurements == nil then return "closed" end
    local bounds = bankWindowMeasurements.bounds
    return table.concat({ bankWindowMeasurements.columns, bounds.x, bounds.y, bounds.width, bounds.height }, " ")
end

-- Cover a full 600 ms game tick of opening layout settlement before backing off to 10-tick checks.
local SIDEBAR_SETTLE_TICKS = 40

local function recordSettledBankHeight(self, liveHeight)
    if liveHeight == nil or liveHeight <= 0 then return end
    local rounded = round(liveHeight)
    self.savedBankHeight = rounded
    if self.persistedBankHeight ~= rounded and self.saveBankHeight ~= nil then
        if self.saveBankHeight(rounded) then self.persistedBankHeight = rounded end
    end
end

local function syncSidebarSize(self, content)
    if not self.expanded then return end
    local liveHeight = self.LiveBankHeight ~= nil and self:LiveBankHeight() or nil
    local settling = (self.sidebarSettleTicks or 0) > 0
    if self.settlingOpenHeight then
        if liveHeight ~= nil and self.savedBankHeight ~= nil and liveHeight >= self.savedBankHeight then
            self.settlingOpenHeight = false
            if liveHeight == self.savedBankHeight and liveHeight ~= self.openingBankHeight then
                self.sidebarSettleTicks = 0
                settling = false
            end
        elseif not settling then
            self.settlingOpenHeight = false
        end
    end
    -- Only save once opening settlement finishes so intermediate default heights cannot overwrite savedBankHeight.
    if not self.settlingOpenHeight and not settling and liveHeight ~= nil
        and (self.savedBankHeight == nil or round(liveHeight) ~= self.savedBankHeight) then
        recordSettledBankHeight(self, liveHeight)
    end
    content = content or BankInterface.Find(COMPONENTS.content)
    local height = content ~= nil and content.height or 0
    if self.ResizeSidebar ~= nil then self:ResizeSidebar(height > 0 and height or nil) end
end

function BankWindow:WatchBankWindow()
    if self.active and (self.detachedSidebar == true) ~= classicUI() then
        debugLog("Bank Core detected interface mode change while bank is attached")
        if self.onInterfaceModeChanged ~= nil then self.onInterfaceModeChanged() end
        return
    end
    local content = self.expanded and BankInterface.Find(COMPONENTS.content) or nil
    -- Some native interactions reset the content offset or strip Core's frame width without replacing handles.
    if self.active and self.expanded and not self.detachedSidebar and not self:IsPresetViewOpen() then
        local record = self.windowRecord.value
        local layout = content ~= nil and tryReadPartLayout(content) or nil
        if record ~= nil and record.sidebarWidth > 0 and layout ~= nil
            and content.hidden ~= true and content.height > 0 then
            local contentReset = false
            for _, entry in ipairs(record.parts) do
                if entry.slot == "content"
                    and (layout.x ~= entry.expandedX or layout.width ~= entry.expandedWidth) then
                    contentReset = true
                    break
                end
            end
            local frameEntry = findFrameRecord(record)
            local frame = frameEntry ~= nil and findPartByName(self.components, frameEntry.slot) or nil
            local frameLayout = frame ~= nil and tryReadPartLayout(frame) or nil
            local frameWidthReset = isFrameWidthReset(frameLayout, frameEntry)
            if contentReset then
                debugLog("Bank Core reapplying saved geometry after a native layout reset")
                self:FixBankGeometry(true)
            elseif frameWidthReset then
                debugLog("Bank Core restoring bank frame width after a native frame reset")
                self:RestoreExpandedFrameWidth(frame, frameLayout, frameEntry)
            end
        end
    end
    -- Bank panels can change without events, even when no plugin page is open.
    self.onChange()
    syncSidebarSize(self, content)
    local signature = describeBankWindowMeasurements(self:ReadBankWindowMeasurements())
    if signature == self.lastBankWindowMeasurements then return end
    self.lastBankWindowMeasurements = signature
    -- Save to disk on bank close or shutdown.
    if self.expanded then self:CaptureFrame() end
    self:LogBankWindowMeasurements("changed")
end

function BankWindow:StartBankWindowWatch()
    self:StopBankWindowWatch()
    self.windowSession = self.windowSession + 1
    self.sidebarSettleTicks = SIDEBAR_SETTLE_TICKS
    -- Give each bank opening its own listener.
    self.bankWindowWatch = Config.CORE_REF .. "_bank_window_watch:"
        .. string.match(tostring(self), "%x+$") .. ":" .. self.windowSession
    local ticks = 0
    Event.Logic.Subscribe(self.bankWindowWatch, function()
        ticks = ticks + 1
        if ticks >= BANK_WINDOW_CHECK_TICKS then
            ticks = 0
            if (self.sidebarSettleTicks or 0) > 0 then
                self.sidebarSettleTicks = self.sidebarSettleTicks - 1
            end
            self:WatchBankWindow()
            return
        end
        if (self.sidebarSettleTicks or 0) > 0 then
            self.sidebarSettleTicks = self.sidebarSettleTicks - 1
            syncSidebarSize(self)
        end
    end)
end

function BankWindow:StopBankWindowWatch()
    self.sidebarSettleTicks = 0
    if self.bankWindowWatch == nil then return end
    self.windowSession = self.windowSession + 1
    Event.Logic.Unsubscribe(self.bankWindowWatch)
    self.bankWindowWatch = nil
end

-- Wait until bank controls are visible and have usable sizes.
function BankWindow:IsReady()
    if self.active then return true end
    local all = component(COMPONENTS.all)
    local backgroundLayer = component(COMPONENTS.background)
    local content = component(COMPONENTS.content)
    local border = component(COMPONENTS.border)
    local viewport = component(BANK_ITEMS_CONTAINER_COMPONENT_ID)
    local itemLayer = component(BANK_ITEMS_COMPONENT_ID)
    for _, part in ipairs({
        { "ALL (0)", all, true, true },
        { "BACKGROUND_LAYER (1)", backgroundLayer, false, false },
        { "CONTENT (2)", content, true, true },
        { "BORDER_LAYER (311)", border },
        { "BANK_ITEMS_CONTAINER (199)", viewport, true, true },
        { "BANK_INV (201)", itemLayer, false, false },
    }) do
        local name, value, checkHidden, checkHeight = part[1], part[2], part[3], part[4]
        if value == nil then return false, name .. " missing" end
        if checkHidden and value.hidden == true then return false, name .. " hidden" end
        if name ~= "BORDER_LAYER (311)" then
            if value.width <= 0 then return false, name .. " width=" .. tostring(value.width) end
            if checkHeight and value.height <= 0 then
                return false, name .. " height=" .. tostring(value.height)
            end
        end
    end
    if not classicUI() then
        local host = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_WINDOW)
        if host ~= nil and type(host.width) == "number" and host.width <= 0 then
            return false, "HOST width=" .. tostring(host.width)
        end
    end
    return true
end

-- Find the bank parts, add sidebar space, and watch window changes
local function applyWindow(self)
    self.components = lookUpParts()
    local all = self.components.all
    if all == nil or self.components.content == nil then
        debugLog("window parts unavailable on immediate attach; deferring to readiness retry")
        self.components = {}
        return false
    end
    local detached = classicUI()
    if not detached then
        local frame = self.components.host or all
        local frameLayout = frame ~= nil and tryReadPartLayout(frame) or nil
        if frameLayout == nil
            or (type(frame.width) == "number" and frame.width <= 0)
            or (frameLayout.widthParent == 0 and frameLayout.width <= 0) then
            debugLog("bank frame width unavailable on attach; deferring to readiness retry")
            self.components = {}
            return false
        end
        debugLog("window parts located; recovering saved geometry")
        -- Undo leftover expansion before adding sidebar space.
        if not BankWindow.RecoverExpansion(self.components, self.windowRecord.value) then
            debugLog("saved geometry recovery blocked attachment")
            self.components = {}
            self.windowRecord:Save()
            return false
        end
    end
    self:LogBankWindowMeasurements("attached")

    self.active = true
    debugLog("reading All Items selection")
    self.nativeViewAll = self:DetectNativeViewAll() == true
    self.detachedSidebar = detached
    local liveHeight = all ~= nil and type(all.height) == "number" and all.height > 0 and all.height or 0
    self.openingBankHeight = liveHeight
    self.settlingOpenHeight = self.savedBankHeight ~= nil and self.savedBankHeight ~= liveHeight
    if not self.detachedSidebar then
        debugLog("widening bank")
        self:WidenBankForSidebar()
    end
    -- Save first so a crash can be recovered.
    self.windowRecord:Save()
    debugLog("creating sidebar; height=", self.components.content.height,
        "; registered tabs=", #self.extensionTabs)
    local parent = sidebarParent(self)
    if parent == nil then error("the outer bank layer is unavailable", 0) end
    self:CreateSidebar(parent, self.components.content.height)
    self:PositionDetachedSidebar()
    debugLog("sidebar created; rail=", self.tabRail ~= nil,
        "; column=", self.rail ~= nil)
    self.expanded = true
    self:LogBankWindowMeasurements("expanded")
    self:StartBankWindowWatch()
    self:Changed(true)
    return true
end

-- Roll back partial attachment before reporting the original build failure.
function BankWindow:Apply(skipReadiness)
    debugLog("Apply entered; active=", self.active)
    if self.active then return true end
    if not skipReadiness and not self:IsReady() then return false end
    local ok, result = pcall(applyWindow, self)
    if ok then return result end
    local restored, cleanupError = pcall(function() self:Restore() end)
    if not restored then report("Bank Core attachment cleanup failed: ", tostring(cleanupError)) end
    report("Bank Core could not build the sidebar: ", tostring(result))
    error(result, 0)
end

-- Hidden controls may still exist; rebuilds may remove them.
local function controlIsVisible(componentID)
    local ok, visible = pcall(function()
        local control = component(componentID)
        return control ~= nil and control.hidden ~= true
            and control.visible == true and control.visibleGlobal ~= false
    end)
    return ok and visible == true
end

-- Search and filters share the same text control.
function BankWindow:ReadNativeFilterMode()
    if not controlIsVisible(CANCEL_CONTROL_COMPONENT_ID) then return nil end
    local label = dynamicComponent(CANCEL_CONTROL_COMPONENT_ID, CANCEL_LABEL_CATEGORY_ID, CANCEL_LABEL_DYNAMIC_ID)
    local ok, text = pcall(function()
        if label == nil or label.hidden == true or label.visible ~= true
            or label.visibleGlobal == false then return nil end
        return label.content
    end)
    if not ok or type(text) ~= "string" then return nil end
    text = text:gsub("<[^>]*>", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    local normalized = text:lower()
    if normalized == "cancel search" then return "search", text end
    if normalized == "clear filter" then return "filter", text end
    return nil, text:sub(1, 80)
end

-- A visible close button means the preset selector is open.
function BankWindow:IsPresetViewOpen()
    return controlIsVisible(PRESET_CLOSE_BUTTON_COMPONENT_ID)
end

-- Prefer the current control over the last tab-selection event.
function BankWindow:IsNativeViewAll()
    local detected = self:DetectNativeViewAll()
    if detected ~= nil then return detected end
    return self.nativeViewAll == true
end

local function readTabSpriteSelection(target)
    if target == nil then return nil end
    local okHidden, hidden = pcall(function() return target.hidden end)
    if okHidden and hidden == true then return nil end
    local okSprite, spriteID = pcall(function() return target.spriteID end)
    if not okSprite or spriteID == nil then return nil end
    return ALL_TAB_SELECTION_BY_SPRITE[spriteID]
end

local function findTabSpriteInTree(node, depth)
    if node == nil or depth > 4 then return nil end
    local okHidden, hidden = pcall(function() return node.hidden end)
    if okHidden and hidden == true then return nil end
    local selected = readTabSpriteSelection(node)
    if selected ~= nil then return selected end
    if node.IterateDynamicComponents == nil then return nil end
    local found = nil
    pcall(function()
        node:IterateDynamicComponents(function(child)
            local childSelected = findTabSpriteInTree(child, depth + 1)
            if childSelected ~= nil then
                found = childSelected
                return true
            end
            return false
        end)
    end)
    return found
end

local function inspectAllTabComponent(componentID)
    if componentID == nil then return nil end
    -- Fast path: the first dynamic child usually holds the tab background sprite.
    local selected = readTabSpriteSelection(dynamicComponent(
        componentID,
        ALL_TAB_BUTTON_CATEGORY_ID,
        ALL_TAB_BUTTON_DYNAMIC_ID
    ))
    if selected ~= nil then return selected end
    return findTabSpriteInTree(component(componentID), 0)
end

function BankWindow:DetectNativeViewAll()
    local selected = inspectAllTabComponent(ALL_TAB_BUTTON_COMPONENT_ID)
    if selected ~= nil then return selected end
    return inspectAllTabComponent(ALL_TAB_CONTAINER_COMPONENT_ID)
end

-- Restore and save the window before reporting cleanup errors.
function BankWindow:Restore()
    local failure = nil
    -- Continue cleanup after errors, keeping the first failure.
    local function step(action)
        local ok, message = pcall(action)
        if not ok then
            debugLog("Bank Core could not fully leave the bank: ", tostring(message))
            failure = failure or message
        end
    end
    if self.active and self.LiveBankHeight ~= nil then
        step(function()
            local liveHeight = self:LiveBankHeight()
            if liveHeight ~= nil and (self.savedBankHeight == nil
                or (not self.settlingOpenHeight and round(liveHeight) ~= self.savedBankHeight)) then
                recordSettledBankHeight(self, liveHeight)
            end
        end)
    end
    step(function() self.pageState:Restore() end)
    self.shownPage = nil
    self.nativeViewAll = false
    step(function() self:DestroyRail() end)
    step(function() self:StopBankWindowWatch() end)
    if self.active then step(function() self:RestoreBankWindowSizeAndPosition() end) end
    self.active = false
    self.expanded = false
    self.openingBankHeight = nil
    self.settlingOpenHeight = false
    if self.sidebarOpeningState ~= "expanded" then self.sidebarMode = nil end
    self.peekRail = false
    self.expansionRecord = nil
    self.detachedSidebar = nil
    self.components = {}
    self.windowRecord:Save()
    self:Changed(true)
    if failure ~= nil then error(failure, 0) end
end

function BankWindow.install(target)
    for name, method in pairs(BankWindow) do
        if name ~= "install" then target[name] = method end
    end
end

return BankWindow
