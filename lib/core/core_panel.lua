-- Show Core's debug logging and window layout settings.

local BankControls = require("lib/ui/bank_controls")
local Theme = require("lib/ui/theme")
local CorePreferences = require("lib/core/core_preferences")

local CorePanel = {}
CorePanel.__index = CorePanel

local CONTENT_HEIGHT = 754
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

-- Keep paired checkboxes mutually exclusive, including when a save fails.
local function choiceSetting(self, parent, text, key, choices, x, y, width, onChange)
    local label = prettyui.Text.new(parent, {
        text = text, x = x, y = y, width = width, height = 20,
        colour = TEXT_COLOUR, font = id.Font.MUSEO_SANS_11PT_REGULAR,
    })
    local group
    group = prettyui.CheckboxButton.new(parent, choices, {
        x = x, y = y + 26, width = width, inline = true, colour = TEXT_COLOUR, selectionCursor = false,
        selectedValues = { self[key] },
        onChange = function(_, _, value, selected)
            local other = value == choices[1].value and choices[2].value or choices[1].value
            self:ChangeChoice(key, group, choices, onChange, selected and value or other)
        end,
    })
    for _, item in ipairs(group.items or {}) do item.label.font = id.Font.MUSEO_SANS_11PT_REGULAR end
    return label, group
end

-- Both shortcut fields share sizing, defaults, and save/rollback handling.
local function keybindSetting(self, parent, text, key, defaults, x, width, onChange)
    local label = prettyui.Text.new(parent, {
        text = text, x = x, y = 366, width = width, height = 20,
        colour = TEXT_COLOUR, font = id.Font.MUSEO_SANS_11PT_REGULAR,
    })
    local field
    field = prettyui.KeybindField.new(parent, {
        x = x, y = 392, width = width, height = 28, value = self[key], defaultValue = defaults[key],
        onChange = function(_, value) self:ChangeKeybind(key, field, onChange, value) end,
    })
    return label, field
end

function CorePanel.new(parent, options)
    local preferences = options ~= nil and options.preferences or {}
    local defaults = CorePreferences.defaults()
    local self = setmetatable({
        options = options or {},
        enableDebug = preferences.enableDebug == true,
        sidebarOpeningState = CorePreferences.OpeningState(preferences),
        railPeekEnabled = preferences.railPeekEnabled == true,
        railPeekKeybind = preferences.railPeekKeybind or defaults.railPeekKeybind,
        expansionDirection = preferences.expansionDirection == "evenly" and "evenly" or "edge",
        sidebarEdge = preferences.sidebarEdge == "right" and "right" or "left",
        sidebarKeybind = preferences.sidebarKeybind or defaults.sidebarKeybind,
        destroyed = false,
    }, CorePanel)
    local panelWidth = parent.width > 0 and math.min(self.options.width or parent.width, parent.width)
        or self.options.width or 1
    self.contentHeight = math.max(CONTENT_HEIGHT, self.options.height or parent.height)
    self.view = prettyui.SimpleView.new(parent, {
        width = panelWidth, height = self.options.nativeSettings and parent.height > 0 and parent.height or self.contentHeight,
        contentHeight = self.contentHeight, scrollable = self.options.nativeSettings == true,
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
    if not self.options.nativeSettings then
    self.closeButton = BankControls.button(closeParent, nil, function()
        if not self.destroyed then self.options.onClose() end
    end, { x = closeWidth - 32, y = 4, size = 24, iconSize = 20,
        spriteName = "RS3_BTN_MODAL_WINDOW_1_CLOSE_NML", tooltip = "Close settings" })
    end
    self.generalHeading, self.generalDivider = sectionHeading(content, "General settings", x, 58, width)
    self.expansionLabel, self.expansionToggle = choiceSetting(self, content,
        "Sidebar expansion (modern interface)", "expansionDirection", {
            { text = "Expand to the side", value = "edge", tooltip = "Keep the bank fixed and expand toward the selected sidebar edge" },
            { text = "Evenly", value = "evenly", tooltip = "Expand evenly on both sides of the bank" },
        }, x, 96, width, "onChangeExpansionDirection")
    self.edgeLabel, self.edgeToggle = choiceSetting(self, content, "Sidebar position", "sidebarEdge", {
        { text = "Left", value = "left" }, { text = "Right", value = "right" },
    }, x, 158, width, "onChangeSidebarEdge")
    self.openingLabel = prettyui.Text.new(content, {
        text = "Sidebar on bank open", x = x, y = 220, width = width, height = 20,
        colour = TEXT_COLOUR, font = id.Font.MUSEO_SANS_11PT_REGULAR,
    })
    self.openingChoices = prettyui.RadioButton.new(content, {
        { text = "Expanded", value = "expanded", tooltip = "Open with a plugin sidebar visible" },
        { text = "Rail only", value = "rail", tooltip = "Open with only the plugin icon rail" },
        { text = "Fully collapsed", value = "hidden", tooltip = "Open with no sidebar or rail and no added bank width" },
    }, {
        x = x, y = 246, width = width, colour = TEXT_COLOUR, selectionCursor = false,
        selectedValue = self.sidebarOpeningState,
        onChange = function(_, value) self:ChangeSidebarOpeningState(value) end,
    })
    for _, option in ipairs(self.openingChoices.items or {}) do option.label.font = id.Font.MUSEO_SANS_11PT_REGULAR end
    self.railPeekToggle = prettyui.CheckboxButton.new(content, {
        { text = "Enable rail peeking", value = "railPeekEnabled",
            tooltip = "In Fully collapsed mode, hold Peek Rail to show the icon rail; release to hide it" },
    }, {
        x = x, y = 328, width = width, colour = TEXT_COLOUR, selectionCursor = false,
        selectedValues = self.railPeekEnabled and { "railPeekEnabled" } or {},
        onChange = function(group) self:ChangeRailPeekEnabled(group:IsSelected("railPeekEnabled")) end,
    })
    for _, option in ipairs(self.railPeekToggle.items or {}) do option.label.font = id.Font.MUSEO_SANS_11PT_REGULAR end
    local keybindWidth = math.min(160, math.max(1, math.floor((width - 12) / 2)))
    self.keybindLabel, self.sidebarKeybindField = keybindSetting(self, content, "Expand Sidebar",
        "sidebarKeybind", defaults, x, keybindWidth, "onChangeSidebarKeybind")
    self.peekKeybindLabel, self.railPeekKeybindField = keybindSetting(self, content, "Peek Rail (hold)",
        "railPeekKeybind", defaults, x + keybindWidth + 12, keybindWidth, "onChangeRailPeekKeybind")
    self:UpdateShortcutControls()
    -- Keep developer tools near the bottom, with scrolling room on short windows.
    local developerY = math.max(400, self.contentHeight - 292)
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

function CorePanel:UpdateShortcutControls()
    local hidden = self.sidebarOpeningState == "hidden"
    self.sidebarKeybindField:SetDisabled(self.sidebarOpeningState == "expanded")
    self.railPeekToggle:SetDisabled(not hidden)
    self.railPeekKeybindField:SetDisabled(not hidden or not self.railPeekEnabled)
    self.keybindLabel.rgba = self.sidebarOpeningState == "expanded" and 0x82796DFF or TEXT_COLOUR
    self.peekKeybindLabel.rgba = hidden and self.railPeekEnabled and TEXT_COLOUR or 0x82796DFF
end

function CorePanel:ChangeSidebarOpeningState(state)
    if self.destroyed then return false end
    local saved, reason = self.options.onChangeSidebarOpeningState(state)
    if saved then self.sidebarOpeningState = state end
    self.openingChoices:SetSelectedValue(self.sidebarOpeningState, false)
    self:UpdateShortcutControls()
    self:ShowResult(saved, reason, "Could not save the opening state.")
    return saved, reason
end

function CorePanel:ChangeRailPeekEnabled(enabled)
    if self.destroyed then return false end
    local saved, reason = self.options.onChangeRailPeekEnabled(enabled)
    if saved then self.railPeekEnabled = enabled end
    self.railPeekToggle:SetSelected("railPeekEnabled", self.railPeekEnabled, false)
    self:UpdateShortcutControls()
    self:ShowResult(saved, reason, "Could not save the setting.")
    return saved, reason
end

function CorePanel:ChangeChoice(key, group, choices, onChange, value)
    if self.destroyed then return false end
    local saved, reason = self.options[onChange](value)
    if saved then self[key] = value end
    for _, choice in ipairs(choices) do group:SetSelected(choice.value, self[key] == choice.value, false) end
    self:ShowResult(saved, reason, "Could not save the setting.")
    return saved, reason
end

function CorePanel:ChangeKeybind(key, field, onChange, value)
    if self.destroyed then return false end
    local saved, reason = self.options[onChange](value)
    if saved then self[key] = field:GetValue()
    else field:SetValue(self[key], false) end
    self:ShowResult(saved, reason, "Could not save the keybind.")
    return saved, reason
end

-- Remove controls before the game removes their parent.
function CorePanel:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    if self.closeButton ~= nil then self.closeButton:Destroy() end
    self.debugToggle:Destroy()
    self.openingChoices:Destroy()
    self.railPeekToggle:Destroy()
    self.railPeekKeybindField:Destroy()
    self.expansionToggle:Destroy()
    self.edgeToggle:Destroy()
    self.sidebarKeybindField:Destroy()
    self.resetGeometry:Destroy()
    self.view:Destroy()
end

return CorePanel
