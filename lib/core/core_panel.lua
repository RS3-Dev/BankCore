-- Show Core's debug logging and window layout settings.

local BankControls = require("lib/ui/bank_controls")
local Theme = require("lib/ui/theme")

local CorePanel = {}
CorePanel.__index = CorePanel

local CONTENT_HEIGHT = 516
CorePanel.CONTENT_HEIGHT = CONTENT_HEIGHT
local TEXT_COLOUR = 0xD7C9ADFF

-- Match the gold labels and divider lines used by bank page sections.
local function sectionHeading(parent, text, x, y, width)
    local label = prettyui.Text.new(parent, {
        text = text, x = x, y = y, width = width, height = 20,
        font = id.Font.MUSEO_SANS_11PT_REGULAR, colour = Theme.HEADING_TEXT, maxLines = 1,
    })
    local divider = ui.Rectangle.new(parent)
    divider:SetPos(x, y + 24)
    divider:SetSize(width, 1)
    divider.fill, divider.rgba, divider.clickthrough = true, Theme.HEADING_LINE, true
    return label, divider
end

function CorePanel.new(parent, options)
    local preferences = options ~= nil and options.preferences or {}
    local self = setmetatable({
        options = options or {},
        enableDebug = preferences.enableDebug == true,
        collapseSidebar = preferences.collapseSidebar == true,
        expansionDirection = preferences.expansionDirection == "evenly" and "evenly" or "left",
        destroyed = false,
    }, CorePanel)
    local panelWidth = parent.width > 0 and math.min(self.options.width or parent.width, parent.width)
        or self.options.width or 1
    self.contentHeight = math.max(CONTENT_HEIGHT, self.options.height or parent.height)
    self.view = prettyui.SimpleView.new(parent, {
        width = panelWidth, height = self.contentHeight,
        contentHeight = self.contentHeight, scrollable = false,
    })
    local content = self.view.content
    local contentWidth = content.width > 0 and content.width or panelWidth
    local width = math.max(1, contentWidth - 24)
    local x = 12
    self.title = prettyui.Text.new(content, {
        text = "Bank Core Settings", x = 44, y = 12,
        width = math.max(1, contentWidth - 88), height = 24,
        alignHorizontal = ui.AlignMode.CENTRE,
        font = id.Font.CINZEL_13PT_BOLD or id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = Theme.HEADING_TEXT, maxLines = 1,
    })
    local closeParent = self.options.closeParent or content
    local closeWidth = closeParent.width > 0 and closeParent.width or contentWidth
    self.closeButton = BankControls.button(closeParent, nil, function()
        if not self.destroyed then self.options.onClose() end
    end, { x = closeWidth - 32, y = 4, size = 24, iconSize = 20,
        spriteName = "RS3_BTN_MODAL_WINDOW_1_CLOSE_NML", tooltip = "Close settings" })
    self.generalHeading, self.generalDivider = sectionHeading(content, "General settings", x, 58, width)
    self.collapseToggle = prettyui.CheckboxButton.new(content, {
        { text = "Collapse sidebar when no plugin is selected", value = "collapseSidebar",
            tooltip = "Click the selected plugin icon again to leave only the icon rail" },
    }, {
        x = x, y = 96, width = width, colour = TEXT_COLOUR, selectionCursor = false,
        selectedValues = self.collapseSidebar and { "collapseSidebar" } or {},
        onChange = function(group) self:ChangeCollapseSidebar(group:IsSelected("collapseSidebar")) end,
    })
    for _, option in ipairs(self.collapseToggle.items or {}) do
        option.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    end
    self.expansionLabel = prettyui.Text.new(content, {
        text = "Sidebar expansion (modern interface)", x = x, y = 132,
        width = width, height = 20, colour = TEXT_COLOUR,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
    })
    self.expansionToggle = prettyui.CheckboxButton.new(content, {
        { text = "Left", value = "left", tooltip = "Keep the bank fixed and expand the sidebar to the left" },
        { text = "Evenly", value = "evenly", tooltip = "Expand evenly on both sides of the bank" },
    }, {
        x = x, y = 158, width = width, inline = true,
        colour = TEXT_COLOUR, selectionCursor = false,
        selectedValues = { self.expansionDirection },
        onChange = function(_, _, value, selected)
            local direction = selected and value or (value == "left" and "evenly" or "left")
            self:ChangeExpansionDirection(direction)
        end,
    })
    for _, option in ipairs(self.expansionToggle.items or {}) do
        option.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    end
    -- Keep developer tools near the bottom, with scrolling room on short windows.
    local developerY = math.max(224, self.contentHeight - 292)
    self.developerHeading, self.developerDivider = sectionHeading(content, "Developer settings", x, developerY, width)
    self.debugToggle = prettyui.CheckboxButton.new(content, {
        { text = "Enable debug", value = "enableDebug",
            tooltip = "Write bank core diagnostics to the client log" },
    }, {
        x = x, y = developerY + 36, width = width, colour = TEXT_COLOUR, selectionCursor = false,
        selectedValues = self.enableDebug and { "enableDebug" } or {},
        onChange = function(group) self:ChangeDebug(group:IsSelected("enableDebug")) end,
    })
    for _, option in ipairs(self.debugToggle.items or {}) do
        option.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    end
    self.instructions = {}
    local instructionY = developerY + 72
    for _, row in ipairs({
        { text = "If your bank dimensions look wrong:", height = 20 },
        { text = "1. Resize and move your bank window to where you want it.", height = 36 },
        { text = "2. Open Settings and click Reset geometry.", height = 36 },
        { text = "3. Close and reopen your bank.", height = 20 },
    }) do
        self.instructions[#self.instructions + 1] = prettyui.Text.new(content, {
            text = row.text, x = x, y = instructionY, width = width, height = row.height,
            font = id.Font.MUSEO_SANS_11PT_REGULAR, colour = TEXT_COLOUR,
            alignVertical = ui.AlignMode.TOPLEFT, maxLines = 2,
        })
        instructionY = instructionY + row.height
    end
    self.resetGeometry = prettyui.SimpleButton.new(content, "Reset geometry", function()
        self:ResetGeometry()
    end, { x = x, y = instructionY + 8, width = math.min(width, 180), height = 32 })
    self.status = prettyui.Text.new(content, {
        text = "", x = x, y = developerY + 240, width = width, height = 28,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = 0xE57373FF, maxLines = 2,
    })
    self.status.hidden = true
    return self
end

function CorePanel:ShowResult(saved, reason, defaultMessage)
    self.status.rgba = 0xE57373FF
    self.status.content = saved and "" or tostring(reason or defaultMessage)
    self.status.hidden = saved == true
end

-- Show when the reset will take effect.
function CorePanel:ResetGeometry()
    if self.destroyed then return false end
    local cleared, reason = self.options.onResetGeometry()
    -- Resetting detaches the bank and destroys this page before returning.
    if self.destroyed then return cleared, reason end
    self:ShowResult(cleared, reason, "Could not reset bank geometry.")
    if cleared then
        self.status.content = "Geometry cleared. Close and reopen the bank."
        self.status.rgba = TEXT_COLOUR
        self.status.hidden = false
    end
    return cleared, reason
end

-- Undo the checkbox change if saving fails.
function CorePanel:ChangeDebug(enabled)
    if self.destroyed then return false end
    local saved, reason = self.options.onChangeDebug(enabled)
    if saved then
        self.enableDebug = enabled
    else
        self.debugToggle:SetSelected("enableDebug", self.enableDebug, false)
    end
    self:ShowResult(saved, reason, "Could not save the setting.")
    return saved, reason
end

-- Restore the checkbox if saving the collapse preference fails.
function CorePanel:ChangeCollapseSidebar(enabled)
    if self.destroyed then return false end
    local saved, reason = self.options.onChangeCollapseSidebar(enabled)
    if saved then
        self.collapseSidebar = enabled
    else
        self.collapseToggle:SetSelected("collapseSidebar", self.collapseSidebar, false)
    end
    self:ShowResult(saved, reason, "Could not save the setting.")
    return saved, reason
end

function CorePanel:ChangeExpansionDirection(direction)
    if self.destroyed then return false end
    local saved, reason = self.options.onChangeExpansionDirection(direction)
    if saved then self.expansionDirection = direction end
    -- Update both without firing another change event; exactly one stays selected.
    self.expansionToggle:SetSelected("left", self.expansionDirection == "left", false)
    self.expansionToggle:SetSelected("evenly", self.expansionDirection == "evenly", false)
    self:ShowResult(saved, reason, "Could not save the setting.")
    return saved, reason
end

-- Remove controls before the game removes their parent.
function CorePanel:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    self.closeButton:Destroy()
    self.debugToggle:Destroy()
    self.collapseToggle:Destroy()
    self.expansionToggle:Destroy()
    self.resetGeometry:Destroy()
    self.view:Destroy()
end

return CorePanel
