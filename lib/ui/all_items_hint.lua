-- Highlight and point to the native All Items tab when a plugin page cannot open on another tab.

local Config = require("lib/core/config")

local AllItemsHint = {}
AllItemsHint.__index = AllItemsHint

local ROOT_KEY = "__bankcore_all_items_hint_root"
local EVENT_KEY = (Config.CORE_REF or "bankcore") .. "_all_items_hint"
local MAX_PARENT_DEPTH = 32
local CORNER_SIZE = 10
local ARROW_WIDTH = 41
local ARROW_HEIGHT = 54
local ABOVE_THRESHOLD_Y = 62

local YELLOW_SPRITE_NAMES = {
    "AIF_EXAMINE_HIGHLIGHT_1_0",
    "AIF_EXAMINE_HIGHLIGHT_1_1",
    "AIF_EXAMINE_HIGHLIGHT_1_2",
    "AIF_EXAMINE_HIGHLIGHT_1_3",
    "AIF_EXAMINE_HIGHLIGHT_1_4",
    "AIF_EXAMINE_HIGHLIGHT_1_5",
    "AIF_EXAMINE_HIGHLIGHT_1_6",
    "AIF_EXAMINE_HIGHLIGHT_1_7",
    "AIF_EXAMINE_HIGHLIGHT_1_8",
}

local WHITE_SPRITE_NAMES = {
    "AIF_EXAMINE_HIGHLIGHT_2_0",
    "AIF_EXAMINE_HIGHLIGHT_2_1",
    "AIF_EXAMINE_HIGHLIGHT_2_2",
    "AIF_EXAMINE_HIGHLIGHT_2_3",
    "AIF_EXAMINE_HIGHLIGHT_2_4",
    "AIF_EXAMINE_HIGHLIGHT_2_5",
    "AIF_EXAMINE_HIGHLIGHT_2_6",
    "AIF_EXAMINE_HIGHLIGHT_2_7",
    "AIF_EXAMINE_HIGHLIGHT_2_8",
}

local POINTER_SPRITE_NAME = "RS3_INFO_DISPLAY_POINTER"

local function destroyControl(control)
    if control ~= nil then pcall(function() control:Destroy() end) end
end

local function unsubscribeLogic()
    if Event ~= nil and Event.Logic ~= nil and Event.Logic.Unsubscribe ~= nil then
        pcall(function() Event.Logic.Unsubscribe(EVENT_KEY) end)
    end
end

local function clearGlobalRoot(expected)
    local current = rawget(_G, ROOT_KEY)
    if current == nil then return end
    if expected ~= nil and current ~= expected then return end
    pcall(function() current.hidden = true end)
    destroyControl(current)
    if rawget(_G, ROOT_KEY) == current then _G[ROOT_KEY] = nil end
end

local function getComponent(componentID, categoryID, dynamicID)
    if ui == nil or ui.Interfaces == nil or componentID == nil then return nil end
    local ok, control = pcall(function()
        if categoryID ~= nil then
            return ui.Interfaces:GetComponent(componentID, categoryID, dynamicID)
        end
        return ui.Interfaces:GetComponent(componentID)
    end)
    return ok and control or nil
end

local function usableParent(control)
    if control == nil then return false end
    local ok, usable = pcall(function()
        if control.hidden == true or control.visibleGlobal == false then return false end
        local width, height = tonumber(control.width), tonumber(control.height)
        if width ~= nil and width <= 0 then return false end
        if height ~= nil and height <= 0 then return false end
        return true
    end)
    return ok and usable == true
end

local function findOverlayParent()
    local components = id ~= nil and id.Component or nil
    if components == nil then return nil end
    local bankLayer = getComponent(components.TOPLEVEL_V2__BANK_LAYER)
    if usableParent(bankLayer) then return bankLayer end
    local gameArea = getComponent(components.TOPLEVEL_V2__GAME_AREA)
    if usableParent(gameArea) then return gameArea end
    return nil
end

local function usableTarget(control)
    if control == nil then return false end
    local ok, usable = pcall(function()
        return control.hidden ~= true
            and control.visibleGlobal ~= false
            and (tonumber(control.width) or 0) > 0
            and (tonumber(control.height) or 0) > 0
    end)
    return ok and usable == true
end

-- Check horizontal and vertical All Items controls, falling back to dynamic children if a container has zero size.
local function findTarget()
    local components = id ~= nil and id.Component or nil
    if components == nil then return nil end
    local candidates = {
        { components.BANK__ALL_TAB_BTN },
        { components.BANK__ALL_TAB_BTN, 0, 0 },
        { components.BANK__TABS_ALL_BUTTON },
        { components.BANK__TABS_ALL_BUTTON, 0, 0 },
    }
    for _, candidate in ipairs(candidates) do
        local control = getComponent(candidate[1], candidate[2], candidate[3])
        if usableTarget(control) then return control end
    end
    return nil
end

local function componentPosition(control)
    local ok, point = pcall(function() return control.xyGlobal end)
    if ok and point ~= nil and type(point.x) == "number" and type(point.y) == "number" then
        return point.x, point.y
    end
    local x, y, node, depth = 0, 0, control, 0
    while node ~= nil and depth < MAX_PARENT_DEPTH do
        local readOK, nx, ny, parent = pcall(function()
            return tonumber(node.x) or 0, tonumber(node.y) or 0, node.parent
        end)
        if not readOK then break end
        x, y, node, depth = x + nx, y + ny, parent, depth + 1
    end
    return x, y
end

local function resolveSprites()
    local sprites = id ~= nil and id.Sprite or nil
    if sprites == nil then return nil end
    local pointer = sprites[POINTER_SPRITE_NAME]
    if pointer == nil then return nil end
    local yellow, white = {}, {}
    for index = 1, 9 do
        local yellowID = sprites[YELLOW_SPRITE_NAMES[index]]
        local whiteID = sprites[WHITE_SPRITE_NAMES[index]]
        if yellowID == nil or whiteID == nil then return nil end
        yellow[index], white[index] = yellowID, whiteID
    end
    return yellow, white, pointer
end

local function createNinePiece(parent, spriteIDs)
    local root = ui.Layer.new(parent)
    root:SetPos(0, 0)
    root.clickthrough = true
    local parts = {}
    for index, spriteID in ipairs(spriteIDs) do
        local part = ui.Sprite.new(root)
        part.spriteID = spriteID
        part.clickthrough = true
        part.isTiling = true
        parts[index] = part
    end
    return { root = root, parts = parts }
end

local function sizeNinePiece(frame, width, height)
    frame.root:SetPos(0, 0)
    frame.root:SetSize(width, height)
    local xs = { 0, CORNER_SIZE, width - CORNER_SIZE }
    local ys = { 0, CORNER_SIZE, height - CORNER_SIZE }
    local widths = { CORNER_SIZE, width - CORNER_SIZE * 2, CORNER_SIZE }
    local heights = { CORNER_SIZE, height - CORNER_SIZE * 2, CORNER_SIZE }
    for index, part in ipairs(frame.parts) do
        local column = (index - 1) % 3 + 1
        local row = math.floor((index - 1) / 3) + 1
        part:SetPos(xs[column], ys[row])
        part:SetSize(widths[column], heights[row])
    end
end

local function moveToFront(control)
    if control ~= nil and control.MoveToFront ~= nil then control:MoveToFront() end
end

local function sameComponent(first, second)
    return first ~= nil and second ~= nil and (first == second or tostring(first) == tostring(second))
end

function AllItemsHint.new(shouldShow)
    -- Recover any overlay left behind by an interrupted reload without touching Event.Logic on clean startup.
    if rawget(_G, ROOT_KEY) ~= nil then
        unsubscribeLogic()
        clearGlobalRoot(nil)
    end
    return setmetatable({
        shouldShow = shouldShow or function() return true end,
        active = false,
        subscribed = false,
        ticks = 0,
        parent = nil,
        root = nil,
        highlight = nil,
        flashYellow = nil,
        flashWhite = nil,
        arrow = nil,
    }, AllItemsHint)
end

function AllItemsHint:IsActive()
    return self.active == true
end

function AllItemsHint:Clear()
    local root = self.root
    local wasSubscribed = self.subscribed == true
    if not self.active and root == nil and not wasSubscribed then return end
    self.active = false
    self.subscribed = false
    self.ticks = 0
    if wasSubscribed then unsubscribeLogic() end
    if root ~= nil then
        pcall(function() root.hidden = true end)
        destroyControl(root)
        if rawget(_G, ROOT_KEY) == root then _G[ROOT_KEY] = nil end
    end
    self.parent, self.root = nil, nil
    self.highlight, self.flashYellow, self.flashWhite, self.arrow = nil, nil, nil, nil
end

function AllItemsHint:Position()
    if not self.active or self.root == nil then return false end
    if not self.shouldShow() or not usableParent(self.parent) then
        self:Clear()
        return false
    end
    local target = findTarget()
    if target == nil then
        self.highlight.hidden = true
        self.arrow.hidden = true
        return false
    end
    local targetX, targetY = componentPosition(target)
    local parentX, parentY = componentPosition(self.parent)
    local width, height = tonumber(target.width) or 0, tonumber(target.height) or 0
    if width <= 0 or height <= 0 then
        self.highlight.hidden = true
        self.arrow.hidden = true
        return false
    end
    local x, y = targetX - parentX, targetY - parentY
    self.highlight.hidden = false
    self.arrow.hidden = false
    local frameWidth, frameHeight = math.max(20, width + 3), math.max(20, height + 3)
    self.highlight:SetPos(x - 1, y - 1)
    self.highlight:SetSize(frameWidth, frameHeight)
    sizeNinePiece(self.flashYellow, frameWidth, frameHeight)
    sizeNinePiece(self.flashWhite, frameWidth, frameHeight)
    local pulse = 0.5 + 0.5 * math.sin(self.ticks / 7)
    self.flashYellow.root.alpha = pulse
    self.flashWhite.root.alpha = 1 - pulse
    local bob = 3 + 3 * math.sin(self.ticks / 7)
    if y >= ABOVE_THRESHOLD_Y then
        self.arrow.rotationDegrees = 0
        self.arrow:SetPos(x + width / 2 - 20, y - 58 - bob)
    else
        self.arrow.rotationDegrees = 180
        self.arrow:SetPos(x + width / 2 - 20, y + height + 4 + bob)
    end
    moveToFront(self.root)
    moveToFront(self.highlight)
    moveToFront(self.arrow)
    return true
end

function AllItemsHint:Tick()
    if not self.active then
        self.subscribed = false
        unsubscribeLogic()
        return
    end
    self.ticks = self.ticks + 1
    local ok = pcall(function() self:Position() end)
    if not ok then self:Clear() end
end

function AllItemsHint:Show()
    if ui == nil or ui.Layer == nil or ui.Sprite == nil or Event == nil or Event.Logic == nil then
        return false
    end
    if not self.shouldShow() then
        self:Clear()
        return false
    end
    local parent = findOverlayParent()
    if parent == nil or findTarget() == nil then
        self:Clear()
        return false
    end
    if self.active and self.root ~= nil and sameComponent(self.parent, parent) then
        local ok = pcall(function() self:Position() end)
        if ok and self.active then return true end
        self:Clear()
    end
    local yellowSprites, whiteSprites, pointerSprite = resolveSprites()
    if yellowSprites == nil then return false end
    self:Clear()
    clearGlobalRoot(nil)
    local ok = pcall(function()
        self.parent = parent
        self.ticks = 0
        local root = ui.Layer.new(parent)
        self.root = root
        _G[ROOT_KEY] = root
        root:SetPos(0, 0)
        root:SetSize(0, 0, 1, 1)
        root.clickthrough = true
        self.highlight = ui.Layer.new(root)
        self.highlight.clickthrough = true
        self.flashYellow = createNinePiece(self.highlight, yellowSprites)
        self.flashWhite = createNinePiece(self.highlight, whiteSprites)
        self.arrow = ui.Sprite.new(root)
        self.arrow.spriteID = pointerSprite
        self.arrow:SetSize(ARROW_WIDTH, ARROW_HEIGHT)
        self.arrow.clickthrough = true
        self.active = true
        self:Position()
        Event.Logic.Subscribe(EVENT_KEY, function() self:Tick() end)
        self.subscribed = true
    end)
    if not ok then
        self:Clear()
        return false
    end
    return self.active == true
end

return AllItemsHint
