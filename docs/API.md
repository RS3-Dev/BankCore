# Bank Core API

This reference describes the current Core runtime API. Dependent plugins use
the API returned by `bankcore`; Core's Lua modules are private to its runtime.
The [examples](../examples/README.md) show complete, independently loaded plugins.

## Responsibilities

Core supplies the bank sidebar space, its icon rail and the one plugin page or
custom view the bank displays. It draws a page's items, handles scrolling, moves
the intended real bank stack beneath a hovered picture, and restores the bank
when that page or view closes. A custom view's plugin draws its own pictures and
controls, and Core puts the real stacks beneath the pictures it binds.

A plugin owns its sidebar controls, folders, filtering, menus, saved data and
page contents. It decides when the player has asked to open a page. Preparing
results or receiving a background update should change the prepared page, not
take over the bank from another plugin.

## Connect to Core

Declare `bankcore` under `requiredDependencies` if your plugin needs Core to
function, and read the injected `bankcore` global. Use `optionalDependencies`
only when the plugin can work without Core. Optional dependencies can also use
`PluginDependencyUpdate(event)` to connect or disconnect when their availability
changes. Dispose your extension from your plugin's `PluginShutdown()`.

Core retains registrations and prepared pages across its own session reloads
while the registering plugins remain running.
Existing API exports and extension handles use the current session. Sidebar
icons and controls return, but previously displayed pages do not reopen
automatically. While Core is suspended, `Open()` returns `bank_closed`, bank
state reports a closed bank, and registration returns `busy`. A disposed or
replaced handle remains stale across reloads. This recovery does not depend on
optional-dependency notifications. Plugins must still dispose their handles
when they unload so Core does not retain callbacks to an unloaded plugin.

The client's `prl bankcore` command disables and re-enables Core. If that also
disables required dependents, their shutdown functions dispose their registrations.
Core must honor those disposals and cannot re-enable the disabled plugins.
Use `plist` to check their state and `pon <plugin folder>` to enable them again.
Keeping Core as a required dependency is correct for plugins that need it.

For local development the dependency value is the string `"bankcore"`.
Before publishing, replace that string in your manifest with Core's numeric
mod.io ID.

```lua
local ext

local function disconnect()
    if ext ~= nil then ext:Dispose() end
    ext = nil
end

local function connect()
    disconnect()
    local core = bankcore or rawget(_G, "__bankcore_api")
    if core == nil then return end
    ext = core.Register({ id = "example.supplies", name = "Supplies", icon = "STAR" })
    if ext ~= nil then
        ext:SetPage({ title = "Supplies", rows = { { slots = { 1944, 1927 } } } })
    end
end

function PluginDependencyUpdate(event)
    if event.pluginIdentifier ~= "bankcore" then return end
    if event.enabled then connect() else disconnect() end
end

function PluginShutdown()
    disconnect()
end

connect()
```

This example prepares a page. Clicking its rail icon opens it; loading the
plugin does not open the page. The callback in this example is for plugins that
choose an optional dependency; required dependents do not need it for Core's
session reload recovery.

## Sanitize player text

`bankcore.SanitizeString(text)` returns a string with all `<...>` tags removed,
including image, sprite and formatting tags. It also removes any remaining
`<` and `>` characters, including unmatched brackets. Other text, whitespace
and Unicode are preserved. Non-string input returns `nil, "invalid", detail`.
The result can be empty; apply your own required-field and length checks.

```lua
local name, reason, detail = bankcore.SanitizeString(imported.name)
if name == nil then return false, reason, detail end
-- Validate name, then save this sanitized value to your plugin's persistentDB.
saved.name = name

-- Sanitize on display too, including data saved before this protection existed.
label.content = bankcore.SanitizeString(saved.name) or ""
-- "Supplies<img=-1><sprite=999999999>" becomes "Supplies".
```

Invalid inline image or sprite IDs can crash the client when rendered. Saving
such text can make the crash recur whenever the stored value is displayed.
Use this helper on imported and manually entered strings before saving them,
and on existing stored strings before passing them to text controls, tooltips
or menus. Sanitize the final combined text if you assemble it from several parts.
Core does not rewrite another plugin's persistentDB or sanitize controls that
plugin draws itself. This is a game-text helper, not an HTML sanitizer.
It is available without registering an extension.

## Register an extension

`bankcore.Register(spec)` returns an extension handle, or `nil, reason, detail`.
The root API provides `Register` and `SanitizeString`. The handle provides `SetPage`, `Refresh`,
`Open`, `Close`, `IsOpen`, `GetBankItems`, `GetBankBounds`, `GetBankState`, `HighlightAllItems`,
`SuspendKeybinds`, `GetMenuItem` and `Dispose`. Both are plain tables of functions, suitable for the client's copied
dependency exports; they expose no session or real bank component.

```lua
local ext, reason, detail = bankcore.Register({
    id = "example.items",
    name = "Example items",
    icon = "STAR",
    column = {
        mount = function(ctx) end,
        resize = function(ctx) end,
        unmount = function() end,
    },
    customView = function(view) end,
    onSelect = function() end,
    onDeselect = function() end,
    onClose = function() end,
    onBankItems = function() end,
    onBankClose = function() end,
    onBankStateChanged = function(state) end,
})
```

- `id`: 1–64 letters, digits, `.`, `_` or `-`; use a stable plugin-specific ID.
- `name`: nonempty plain text, at most 80 bytes, used for the rail tooltip.
- `icon`: optional numeric game sprite ID, PrettyUI sprite-button name
  such as `STAR`, or native `id.Sprite` constant name such as
  `RS3_ICON_WARDROBE_VIEW_GRID_24PX_0`. IDs must be whole numbers from 0 to
  2,147,483,647. Omitting it creates an extension without a rail entry.
- `column`: optional sidebar callbacks; requires an icon and a `mount` function.
  `resize` and `unmount` are optional.
- `customView`: optional function that draws the extension's own view instead of
  a page; see [Draw a custom view](#draw-a-custom-view).
- `alwaysShowScrollbar`: optional boolean for `customView` registrations only,
  default `true`. Set it to `false` to hide the scrollbar when the custom content
  fits. Overflowing content always shows it. Standard item pages always show it.
- `allowNativeDrag`: optional boolean, default `false`. Sets the drag behavior
  for the extension's pages and custom view. A `SetPage` description can override
  it with an explicit `true` or `false` for that page.
- `onSelect`, `onDeselect`, `onClose`, `onBankItems`, `onBankClose`, `onBankStateChanged`: optional functions
  described below.

Extra fields and incorrect types are refused. Registration returns `invalid`
with a detail for bad input, `stopped` after permanent registry disposal, or
`busy` while Core is suspended or when called inside a sidebar callback.

Registering an ID again disposes its previous extension. Its old handle becomes
stale and its queued callbacks are discarded. `ext:Dispose()` removes its icon,
column and displayed page and is safe to repeat. After disposal or replacement,
actions return `false, "stale"`, `IsOpen()` returns false and reads return nil.

## Sidebar icons and columns

A rail icon for a plugin without a sidebar column opens its prepared page and
is highlighted while selected. It keeps the bank at rail-only width; clicking
the selected icon again closes its page. A refused opening keeps the previous
selection. Core's Settings cog follows the same rail-only behavior and clears
the selected plugin column when opened.

Pass a game sprite ID directly to use a sprite outside PrettyUI's icon list:

```lua
local ext = bankcore.Register({
    id = "example.organizer",
    name = "Bank organizer",
    icon = 18035, -- Replace with your chosen game sprite ID.
})
```

Numeric icons and native constant names use the same sprite for every state.
The selection frame still marks the active tab. PrettyUI names keep their
existing state-specific sprites. Icons are drawn at 20 by 20 interface units,
including while being dragged. Core checks the ID's format; the game must have
a sprite for that ID to display it.

Core owns the rail's order. A player can drag an icon up or down the rail to
move it; Core saves the new order in its own preferences and keeps it across
bank openings and reloads. Icons it has not saved yet follow in extension ID
order, and an extension that unloads keeps its remembered place for when it
returns. Core adds paging arrows if the icons do not fit. Registration updates
the rail on the next logic tick, after `Register` returns.

- A click acts when the press is released. Dragging an icon moves it without
  selecting its column, opening its page or changing the displayed page.
- An icon with a column selects that column without changing the displayed page.
  In collapsed opening modes, clicking the selected icon again deselects it and
  returns to the rail or hidden state. In Expanded mode it remains selected.
- An icon without a column opens its prepared page or custom view directly.
- Bank opening follows the player's Expanded, Rail only, or Fully collapsed
  setting. Expanded selects an available column; the collapsed modes start with
  no plugin selected. Expand Sidebar selects the first icon in the saved order.
  Peeking reveals only the rail and does not select a plugin. A newly registered
  icon never replaces an existing selection.

`mount(ctx)` receives `{ parent, overlay, width, height }`. Build controls in
`parent`, which clips them to the sidebar column. Use the window-sized,
click-through `overlay` for tooltips or popups that must extend outside it.
Plugins receive these rendering layers, not the bank's own components.

Core reserves the row above the plugin column for **Return to Bank**, aligned
with the native bank tabs. The plugin column starts below that row; `ctx.height`
already excludes its 36 interface units. Use the supplied dimensions when
laying out controls. The icon rail keeps its existing top position.

Return to Bank closes the displayed plugin page or custom view through Core's
normal page-close path, leaving the selected sidebar column in place. The
button is disabled while the native bank is displayed. Plugins do not need to
provide their own return control.

When the column size changes, Core updates the context and calls `resize(ctx)`.
Without `resize`, Core calls `unmount()` and mounts again. Keep search text and
other state in the plugin so it survives a remount.

`unmount()` runs before Core destroys both layers when the column changes, the
bank closes, or the extension is disposed or replaced. Clear references and
release any plugin-owned listeners there. A failing `mount` removes the layers
and shows an error until the extension registers again. A failing `unmount`
still allows cleanup. Callback errors are logged.

Calling `Open` or `Register` inside a sidebar callback returns `busy`. Disposing
an extension there removes it immediately and updates the rail next tick.

## Describe a page

`ext:SetPage(page)` validates and copies a description and returns `true`, or
`false, "invalid", detail`. Invalid input leaves the previous prepared page
unchanged. Editing the caller's table afterward has no effect.

```lua
ext:SetPage({ title = "Supplies", rows = {
    { label = "Equipment and food" },
    { slots = { 4151, false, 385, 385 } },
    { slots = {} },
} })
```

The page fields are required `rows`, optional `title`, and optional
`allowNativeDrag`. Omitting `title` hides the heading and its space above the
rows. A supplied title and each label must be nonempty plain text of at most
80 bytes after trimming. Control characters and the client's `<` and `>` markup
brackets are refused.

```lua
ext:SetPage({ rows = rows }) -- Show items without a page heading.
```

`allowNativeDrag` must be a boolean. When omitted, it inherits the registration's
setting, which defaults to `false`. Set it to `true`
for organizer pages that let players drag real bank items from the page onto
the game's bank tabs:

```lua
ext:SetPage({
    title = "Herblore",
    allowNativeDrag = true,
    rows = rows,
})
```

This uses the game's normal drag-and-drop behavior and changes the real bank.
It allows all native drag destinations, including rearranging items; Core cannot
restrict it to dropping onto tabs.
It does not rearrange the plugin's page rows. Missing-item pictures cannot be
dragged. Each `SetPage` call sets this option again; leaving it out uses the
registration's default, rather than the previous page's setting.

Each row has either a `label` or a `slots` list. Slots contain numeric object IDs
or `false` for blank cells; `{ slots = {} }` deliberately leaves an empty line.
A slot can also be `{ objectID = 249, bankSlot = 12 }` to target a specific
current bank stack. `bankSlot` must be a whole number from 1 to 2,147,483,647,
as returned by `GetBankItems()`. If that slot no longer holds the requested
item, Core shows a missing-item picture instead of using another copy.
Object IDs must be whole numbers from 0 to 2,147,483,647. Lists must have no gaps
or extra keys. A page can contain at most 10,000 rows and slots counted together.
Validation does not run custom table lookup functions.

Core draws the title, section labels and one item grid using the bank's spacing.
Long rows wrap to the current column count. When the window width changes, Core
fits the visible page immediately and rearranges rows once the width has held
steady for 10 logic ticks. Height changes do not rearrange rows. Scroll stays
within the new page height, and a stationary pointer must move before it can
pick up a stack displaced by scrolling or rearrangement.

### Repeated items, placeholders and missing items

Core matches each slot to a native bank stack of its object. Stocked stacks
come first in All Items order, followed by zero-quantity placeholders in All
Items order. How repeated object IDs match depends on the client's stack type
for the object:

- An item that stacks in the bank (`SOMETIMES` or `ALWAYS`) has one stack.
  Every slot listing it shows that stack's quantity and reaches it, so a vial of
  water listed in six sections shows the same 9,000 vials six times. Each
  picture keeps its own `slot`.
- An item that never stacks (`NEVER`, as for objects with ObjVars such as
  augmented weapons) takes successive stacks. For bank stacks `X(0), X(50)`,
  listing X once shows the 50; listing it twice shows the 50 and then the
  placeholder.
- If the client cannot read an item's stack type, its repeats take successive
  stacks until a later bank read can.

A slot with no matching stack left shows the item's picture with quantity zero,
without native input. This is a missing-item picture, sometimes called a ghost.
It can show the item's name, but it cannot withdraw or drag a bank item. A real
zero-quantity native placeholder can still supply its own tooltip and, with
`allowNativeDrag = true`, drag behavior, including for several slots sharing it.
A blank cell has neither an item picture nor native input. Pictures never add bank stacks:
`GetBankItems()` lists each native stack once.

The API cannot identify an augmented weapon by its perks or keep a permanent
identity for unstackable copies. Moving matching items in the native bank can
change which stack a repeated object ID displays. A `bankSlot` reference targets
one current slot, not a permanent item identity; reread it after bank changes.

### Open, update and close

`ext:Open()` displays the prepared page, or draws the custom view, and returns
`true`. Every opening starts at the top, including reopening the same
extension's page. It does not select that extension's sidebar column.

A refusal returns `false, reason` without replacing the displayed page:

- `stale`: the handle was disposed or replaced.
- `no_page`: no page has been set.
- `bank_closed`: the bank is closed, unavailable or still attaching.
- `busy`: a page change or sidebar callback is running.
- `preset_open`: the preset selector is open.
- `not_all_items`: the native All Items tab is not selected.

The current tab control takes precedence over the last tab-selection event,
including for `GetBankState().viewAll`. If the control cannot be read, Core uses
the last known selection.

If drawing begins and fails, `Open` returns `false, "failed"` and Core restores
the native view. Core displays no refusal text; the plugin explains the result in
its own UI. When `Open` fails with `not_all_items` (including when clicking a
columnless rail icon) and presets, search and filters are inactive, Core highlights
and points to the native All Items tab until the player switches to All Items,
opens a page, opens presets/search/filter, changes or collapses the sidebar, or
closes the bank.

Plugins that pre-check `GetBankState()` on an explicit player click before
preparing a page can call `ext:HighlightAllItems()` when `viewAll` is false to
show the same highlight. It returns `true`, or `false, reason` (`stale`,
`bank_closed`, `busy`, `preset_open`, `search_active`, `filter_active`,
`already_all_items`, or `unavailable`). Do not call it for passive state updates
or silent background checks.

Setting the currently displayed page queues one redraw for the next logic tick,
keeping scroll within the new height. Several `SetPage` calls before that tick
use the latest description. An intervening `Open` draws it once as a new opening.
Setting a hidden page only prepares it; it never takes the bank from another
plugin or from the player's native tab. A failed queued redraw restores the
native view.

`ext:Refresh()` queues the same redraw of the extension's displayed page or
custom view, and returns `true`. For a hidden one it does nothing and returns
`true`. It returns `false, "busy"` while a page change or a sidebar or view
callback runs, and `false, "stale"` after disposal.

`ext:Close()` returns the bank to its native view if this extension's page is
displayed, and otherwise does nothing. It returns `true`, or `false` with
`stale`, `busy` or `failed`. It cannot close another extension's page.
`ext:IsOpen()` reports whether this extension's page is displayed.

## Draw a custom view

Instead of a page, an extension can draw its own view in the bank's item area
with the client's UI components, then attach a bank item to any component with
`view:BindItem(element, objectID)`. While the pointer is over a bound component,
Core moves the real bank stack beneath it, so the game's own tooltip, menu,
and clicks work there, and restores the stack afterward. Dragging is enabled
when the registration has `allowNativeDrag = true`. The plugin
never works out stack positions or handles native input.

```lua
local ext
local wanted = { 4151, 1127, 1079 }

-- Draw the wanted items larger than bank items, stepping down the view
local function drawView(view)
    local grid = view:GetGeometry()
    local size = grid.cellWidth + 16
    local title = ui.Text.new(view.parent)
    title:SetPos(12, 8)
    title:SetSize(view.width - 24, 20)
    title.content = #wanted .. " wanted"
    for index, objectID in ipairs(wanted) do
        local picture = ui.Sprite.new(view.parent)
        picture:SetPos(12 + (index - 1) * (size + 24), 36 + (index - 1) * 20)
        picture:SetSize(size, size)
        picture:SetAssociatedObject(objectID)
        view:BindItem(picture, objectID)
    end
    -- The content's height, so the view scrolls to its last picture
    return 36 + #wanted * 20 + size
end

-- Change the list from the plugin's own controls; a shown view draws again
local function setWanted(list)
    wanted = list
    if ext ~= nil then ext:Refresh() end
end

local function disconnect()
    if ext ~= nil then ext:Dispose() end
    ext = nil
end

local function connect()
    disconnect()
    local core = bankcore or rawget(_G, "__bankcore_api")
    if core == nil then return end
    ext = core.Register({ id = "example.wanted", name = "Wanted", icon = "STAR",
        customView = drawView })
end

function PluginDependencyUpdate(event)
    if event.pluginIdentifier ~= "bankcore" then return end
    if event.enabled then connect() else disconnect() end
end

function PluginShutdown()
    disconnect()
end

connect()
```

Registering with `customView` prepares the view, so it needs no `SetPage`, and
`SetPage` returns `false, "invalid"`. Register again without it to use a page.
The rail icon opens the view, or selects the extension's column if it has one,
and `ext:Open()`, `ext:Close()` and `ext:IsOpen()` work as they do for pages.
Only one page or view shows at a time.

Custom views can opt into hiding the scrollbar when it is unnecessary:

```lua
local ext = bankcore.Register({
    id = "example.wanted", name = "Wanted", icon = "STAR",
    customView = drawView,
    alwaysShowScrollbar = false,
})
```

Omitting `alwaysShowScrollbar` keeps it visible, including for short content.
The option hides the controls without changing the view's width or reserved
scrollbar space. Register again to change it.

### The view

`customView(view)` receives a plain table of its own fields:

- `parent`: the layer to draw in, in interface units from the item area's top
  left. It scrolls with the view and is clipped to the item area.
- `overlay`: a click-through layer over the whole bank window for popups and
  tooltips that must leave the item area. It lies above bound items.
- `width`, `height`: the item area's size in interface units, without the bank's
  tabs and header or Core's sidebar.
- `scrollY`: the view's scroll offset, kept current while the view shows.
- `BindItem`, `UnbindItem` and `GetGeometry`, described below.

`view:GetGeometry()` returns a fresh `{ x, y, width, height, scrollY, columns,
itemWidth, itemHeight, cellWidth, cellHeight, stepX, stepY }`. `x` and `y` are
the item area's top left on the screen in interface units. `itemWidth` and
`itemHeight` are the size of the bank's item pictures. `columns`, `cellWidth`,
`cellHeight`, `stepX` and `stepY` describe the grid Core's pages use, for a view
that wants to match it. `GetBankBounds()` still describes the whole bank window.

`customView` may return the content's height, or `nil`. The view is at least as
tall as the item area and reaches the lowest bound component as its containers
show it; return a height to scroll to unbound content below that. A height must
be a number from 0 to 440,000, the most a page can reach. Any other result, or an
error in `customView`, is logged and returns the bank to its own view, as a page
that cannot be drawn does; `Open` then returns `false, "failed"`.

### When the view draws

Core calls `customView` when the view opens, after `ext:Refresh()`, when it reads
the bank's items again after they change, and once the item area has kept a new
size for 10 logic ticks. Scrolling and moving the window do not draw it again.
Opening starts at the top; drawing the shown view again keeps its scroll within
the new height. Leaving the view restores the bank's own scroll.

Each drawing gets a new `view` with new layers. Core destroys the previous layers
and everything in them, and the previous `view` becomes stale: `BindItem` and
`GetGeometry` return `nil, "stale"` and `UnbindItem` returns `false, "stale"`.
Keep the view's data in the plugin rather than in its components. Listeners the
plugin subscribes itself remain its own to remove.

While `customView` runs, `GetBankItems()` answers from the bank read Core made
for the drawing, so the plugin can show current quantities. `Open`, `Close`,
`Refresh` and `Register` return `busy` there. Disposing the extension inside it
returns the bank to its own view. A drawing for `Refresh` does not count as an
item change, so `onBankItems` is not called for it.

### Bind items

`view:BindItem(element, objectID)` attaches a bank item to a component inside
`view.parent` and returns its binding ID, or `nil, reason, detail`:

- `invalid`: the object ID is not a whole number from 0 to 2,147,483,647, the
  element is not a component inside `view.parent`, or the view already binds
  10,000 items. Bindings already made are unchanged.
- `stale`: the view has been drawn again or closed.

Binding IDs count up from 1 in each drawing. Every component has its own ID,
even when several show one stack; `GetMenuItem()` reports it as `slot`. IDs are
not bank identities, so do not keep them after the view draws again. Binding a
component again keeps its ID. Binding it to another object releases its stack at
once and attaches the new object on the next tick.

`view:UnbindItem(element)` detaches a component and returns `true`, also when it
is repeated or the component was never bound. A stack beneath it is released at
once. Bindings may change after `customView` returns, for example from the
plugin's own button: Core rebuilds the view's item input once on the next tick
from the bank read the view was drawn with, without calling `customView` again.

Bound components match bank stacks as a page's repeated slots do, in binding
order: every picture of an item that stacks in the bank reaches its one stack,
and pictures of an item that never stacks take successive stacks in bank order
until none is left. Binding works by object ID. It cannot choose a particular
augmented weapon by its perks or keep a permanent identity for a stack.

### Input, layering and appearance

Core finds where each bound component shows: its position, size and anchors,
its containers' positions, scrolling and clipping, the view's scroll and the
item area's edges. A partly clipped component takes input only where it shows.
Moving, resizing, hiding, scrolling or clipping a bound component needs no new
binding. A component takes no input while it, a layer holding it or
`view.parent` is hidden, or while the client reports it not visible in its tree,
and takes input again once it shows. A component Core can no longer read, or
that is no longer inside `view.parent`, as after it or one of its layers is
destroyed, is unbound.

The stack beneath a bound component takes exactly the size of the part that
shows, with any stacks overlapping it moved aside. Core restores each stack's
own position, size and input when the pointer leaves, when the component is
unbound, hidden or destroyed, and when the view draws again or closes.

Where bound components overlap, the one bound last takes the pointer, so bind
overlapping items from back to front. This includes a picture with no stack, such
as a missing item: it covers what is bound beneath it, and no bank stack is
reached there. When bound components move, show or hide, the pointer is checked
again even if it has not moved, so the item now on top beneath it takes the
pointer and a stack no longer beneath it is released.

Core makes a bound component click-through, and gives a component its own
setting back when it is unbound or the view draws again. Set `clickthrough` on
the plugin's layers that contain bound components too, so the pointer reaches
Core beneath them. Unbound controls in `parent` keep their
own input, also when drawn over bound items, and so do controls in `overlay`.
Where no plugin component takes the pointer, Core takes it, so no bank stack is
reached there. The mouse wheel scrolls the view except over a plugin control
that takes the wheel.

The plugin draws every picture, border, label and quantity; Core does not change
the bound components' appearance. Core still decides what the bank allows: a
native placeholder gives its own tooltip but is not `interactive`;
a picture with no stack left shows the item's name and reaches no stack; and a
stack whose quantity cannot be read takes no input.

## Read bank state

`ext:GetBankItems()` returns a fresh list of
`{ objectID, quantity, bankSlot, nativeTab }`, one record
per native stack in All Items order. Placeholders have quantity zero. While a
page is displayed, Core uses the bank positions saved before moving stacks
beneath its pictures. It returns `nil, reason` for `bank_closed`, `not_all_items`
or `busy`, including while a displayed page waits for a fresh bank read.

`bankSlot` is the current one-based native inventory slot. `nativeTab` is 1 for
the main tab or 2–15 for custom tabs. It is nil if the game's tab counts cannot
be read reliably, including during a partial inventory rebuild. Neither field
is a permanent item identity. Page order and screen positions do not determine
tab membership.

`ext:GetBankBounds()` returns a fresh `{ x, y, width, height, columns }` for the
bank window. Its size includes Core's sidebar, and its position uses the game's
interface units. `columns` is the grid width used by the displayed page, or the
native item area if no page is open. It returns nil while closed or attaching.

## Callbacks

Callbacks normally run on the next logic tick, after the
change has finished. Selection changes are delivered first, with the old plugin's
`onDeselect()` before the new plugin's `onSelect()`. Other pending notices follow
in this order: bank close, page close, bank state changed, items changed. Extensions are notified in
ID order, whatever the rail order. Errors are logged without stopping other
plugins' callbacks.

- `onSelect()`: this extension becomes the selected sidebar icon while the bank
  is open. This includes automatic selection on bank opening and icons without
  a sidebar column. It does not mean the extension's bank page is open.
- `onDeselect()`: an extension that received `onSelect()` is no longer selected,
  including switching plugins, opening Core settings, deselecting its icon, or
  closing the bank. It also runs immediately during disposal, replacement, or
  Core suspension so the plugin can remove bank-wide controls before teardown.
  Mount resizing/rebuilding alone does not trigger selection hooks. Changes
  within one logic tick coalesce to the final selection.

Both hooks take no arguments. Use them for plugin-owned UI or state tied to the
rail selection; keep column control construction in `mount`/`unmount`. A plugin
without an icon is never selected and does not receive these hooks.

```lua
local ext = bankcore.Register({
    id = "example.overlay", name = "Overlay", icon = "STAR",
    column = { mount = function(ctx) buildSidebar(ctx) end },
    onSelect = function() showBankOverlay() end,
    onDeselect = function() hideBankOverlay() end,
})
```

The other callbacks are:

- `onBankClose()`: the bank Core attached to closed or the player left the game.
  Use it to close plugin windows tied to that bank opening. A native tab change,
  resize, page replacement or preset change is not a bank close. Core has already
  restored the bank when this runs, so `GetBankBounds()` returns nil.
- `onClose()`: this extension's page stopped showing because another page, the
  native view, a close or a failed redraw replaced it. It is skipped if that
  page has reopened before delivery.
- `onBankItems()`: the bank's items first became readable for this opening, or
  may have changed. Delivery waits for All Items and a fresh bank read. While
  a stack is moved under a stationary pointer, the fresh read can wait until it
  returns to its original position.
- `onBankStateChanged(state)`: receives an initial snapshot after registration,
  then a fresh snapshot when any field changes. It works while the extension's
  page is hidden and while a native tab or presets prevent reading bank items.
  Other callbacks take no arguments. See the state fields below.

### Native bank state

`ext:GetBankState()` returns a fresh table, or `nil, "stale"` after disposal,
or replacement. While Core is suspended, it reports a closed bank instead.
Register without an icon or page to observe only.

- `bankOpen`: Core has attached to the open bank. False while closed, unavailable
  or still attaching.
- `viewAll`: the native All Items tab is selected. False while closed. This does
  not mean the native items are visible: a plugin page or presets can cover them.
- `presetOpen`: the native preset selector is visible. False while closed.
- `searchActive`: the visible native cancel label has the text
  "Cancel Search". False while closed or when the label cannot be recognized.
- `filterActive`: that control has the text "Clear Filter". False while closed
  or when the label cannot be recognized. Filtering inside feature plugins does
  not affect this field. These labels currently support English client text.

These fields describe native bank controls. Switching between plugin pages or
sidebar columns does not change this state or trigger its callback.

Native tab, search, filter and preset changes are checked every 10 logic ticks (about 200 ms),
including changes without menu or inventory events. Notifications coalesce to
the latest state; they are not a history of every click. Modifying a returned
table does not affect Core or another plugin. Search and filters read `.content`
from the shared label at `GetComponent(517, 257, 0, 9)`, ignoring formatting tags
and case. Both the cancel control and label must be visible. Presets read the
visible close button (517, 86), and All Items reads sprite 8070 on the first
dynamic child of its button (517, 166).

```lua
local ext = bankcore.Register({
    id = "example.observer", name = "Bank observer",
    onBankStateChanged = function(state)
        -- Hide plugin controls while native controls restrict the bank view.
        local available = state.bankOpen and state.viewAll
            and not state.searchActive and not state.filterActive and not state.presetOpen
        updateControls(available)
    end,
})
local state = ext:GetBankState()
```

Disposed or replaced extensions receive no later callbacks after their final
`onDeselect()` cleanup, if selected. During Core
shutdown there is no later tick: page-close and bank-close callbacks run
immediately where applicable, after Core has suspended bank access. Registrations
remain available for the next Core session unless their plugins dispose them.

## Item menus and completed drops

`ext:GetMenuItem(menu)` describes a bank item from the menu passed to the
plugin's own `MiniMenuReady` handler. It returns a fresh table or nil:

- `objectID`: the object's numeric ID.
- `interactive`: a stocked native stack can receive the host's normal actions.
  It is false for native placeholders, missing items, preset views and clicks
  covered by a plugin column. It does not indicate whether a placeholder can
  be dragged or give permission to invoke a server action.
- `slot`: the position on this extension's displayed page, counting blank slots
  but not labels. Each picture of a shared stack reports its own position. On the
  extension's custom view it is the bound component's binding ID. It is absent
  for other extensions' views and while a redraw is pending.

A stack moved aside, a closed bank or a stale handle returns nil. A missing-item
picture can still return its object ID and slot with `interactive = false`.
The call reads the native menu without changing it.

Plugins edit menus with the client's own `Add` and `Swap`. Keep the existing
native default, promoted Cancel or another plugin's default. Core protects
missing items and stacks moved off screen by making Cancel the default. Over a
custom view, as over a column, it keeps a plugin's own default action, since a
plugin can draw controls over its items. It does not add feature-specific
entries or modifier-click withdrawal rules.

The order of handlers from different plugins is unspecified. The examples find
their added menu entry by comparing the list before and after `Add`, then move
it below the default. For an action deferred until a later tick, check the
plugin's own revision so an old menu cannot edit a newly changed page.

Core observes a completed native drag without consuming it. It blocks page
input immediately and rereads the bank on the next tick, sharing that rebuild
with pending inventory notifications. A later inventory update remains a
fallback if the native order changes after the drop callback. Leaving the page
or closing the bank cancels that queued work. This does not use native drag
coordinates, perform a drop itself, or provide plugins with drop callbacks.

## Suspend Core keybinds

Bank Core polls its own keyboard shortcuts on every logic tick while the bank
is open — currently **Expand Sidebar** (default `Ctrl`) and **Peek Rail**
(default `Shift`). When a plugin opens a modal window, editor or blocking
overlay on top of the bank, shortcuts meant for that overlay (such as `Ctrl+C`,
`Ctrl+V`, `Ctrl+Z`, `Ctrl+Y` or `Shift`-click inside an editor) can also match
Core's shortcuts and expand, collapse or shift the hidden bank window beneath
it.

Call `ext:SuspendKeybinds([label])` while an overlay covers the bank or owns
keyboard shortcuts, and release the returned hold when that overlay closes.

### When to use it (and when not to)

Use `SuspendKeybinds` when your plugin displays UI over the bank where Core's
shortcuts should not react:

- Full-bank or modal editors with their own shortcuts (for example, Bank Tags'
  layout editor using `Ctrl+C`/`Ctrl+V`/`Ctrl+Z` or `Shift` selection).
- Confirmation prompts, import/share windows, pickers or plugin settings modals
  rendered on top of the bank.
- Custom drag or shortcut modes where holding `Ctrl`, `Shift` or another bound
  key would otherwise toggle the sidebar behind the user's cursor.

Do **not** hold a suspension during normal bank browsing:

- Do not suspend keybinds simply because your sidebar column is mounted or your
  plugin page/custom view is displayed in the bank — players still expect
  **Expand Sidebar** and **Peek Rail** to work while browsing bank pages.
- Do not acquire a permanent hold at plugin startup.
- You do **not** need `SuspendKeybinds` solely for focused text boxes or
  PrettyUI `KeybindField` inputs: Core already suppresses its shortcuts whenever
  `Keyboard.IsBlocked()` or `prettyui.KeybindField.IsCapturing()` is true.
  `SuspendKeybinds` covers everything outside focused text input, such as
  overlay windows handling `Event.KeyDown` shortcuts directly.

### Acquire and release a hold

```lua
local hold, reason, detail = ext:SuspendKeybinds("layout editor")
```

- `label` (optional): 1–80 plain-text characters without control characters or
  `<`/`>` brackets. Core includes this label alongside your extension ID in
  debug logs to make it easy to see which overlay owns each active hold.
- On success, returns a plain lease handle table with two functions:
  - `hold:Release()`: releases this specific hold and returns `true`. Safe to
    call repeatedly and safe after `ext:Dispose()`, extension replacement or
    Core reload/shutdown. Releasing a hold never affects another overlay's or
    another plugin's hold.
  - `hold:IsActive()`: returns `true` while this hold is still active on its
    live extension, or `false` after `hold:Release()`, `ext:Dispose()`,
    replacement or permanent Core shutdown.
- On refusal, returns `nil, reason, detail`:
  - `stale`: the extension handle was disposed, replaced or permanently closed.
  - `invalid` (with `detail`): `label` was supplied but is not a valid 1–80
    character plain-text string.
  - `limit` (with `detail`): this extension already holds the maximum of 32
    simultaneous active suspensions. This cap protects against accidentally
    calling `SuspendKeybinds` inside a tick, draw or reposition loop.

### Scope, overlap and held-key behavior

- **Core shortcuts only:** Suspending keybinds pauses Core's own shortcut
  polling (**Expand Sidebar**, **Peek Rail** and any future Core keybinds). It
  does **not** change `Keyboard.IsBlocked()` and does **not** block native game
  keys or other plugins' `Event.KeyDown` handlers.
- **Active rail peek retracts:** If the player is currently holding **Peek
  Rail** in Fully collapsed mode when a hold begins, Core retracts the peeked
  rail on the next logic tick and keeps it closed while suspended.
- **Independent leases across windows and plugins:** Every call returns an
  independent hold. If one plugin opens an editor and then opens a confirmation
  dialog over it, each window can hold its own lease; closing the child dialog
  releases only the child's hold while the parent's hold keeps Core suspended.
  Similarly, if two plugins hold leases at the same time, Core stays suspended
  until every live lease has been released (or its owning extension is
  disposed).
- **No accidental fire on resume:** When the final active hold is released (or
  cleared on disposal), Core latches its shortcuts as held until the bound keys
  are physically released and pressed again. Closing a modal with a shortcut
  like `Ctrl+W`, `Ctrl+Enter` or `Shift+Esc` — or clicking Close while still
  holding `Ctrl` or `Shift` — will not toggle the sidebar or peek the rail on
  the next tick.

### Lifecycle and cleanup guarantees

- **Callable anytime while live:** `ext:SuspendKeybinds()` does not require the
  bank to be open and never returns `busy`, even inside `mount`, `unmount`,
  `customView` or other callbacks. Acquiring a hold before the bank opens keeps
  Core keybinds suspended if the bank opens while your overlay is still on
  screen.
- **Not auto-cleared on bank close:** Closing the bank does **not** release
  active holds, so standalone overlays (such as an import or settings dialog)
  that remain open across a bank close/reopen stay protected. For bank-tied
  overlays, always close the overlay and call `hold:Release()` in both the
  overlay's teardown (`Destroy` / `onClose`) and `onBankClose`.
- **Automatic cleanup on dispose or replacement:** Calling `ext:Dispose()` or
  re-registering the same extension ID immediately releases all active holds
  owned by that extension so an unloaded, crashed or reloaded plugin cannot
  leave Core keybinds permanently disabled.
- **Core reload retention:** Across Core session reloads (`prl bankcore`),
  retained extensions keep any holds that were not released during
  `onBankClose`, and existing `hold:Release()` / `hold:IsActive()` handles keep
  working against the new Core session.

### Examples

#### Modal editor window (single overlay)

Check `ext.SuspendKeybinds ~= nil` if your plugin supports older Core releases
without this method, store the hold on the window, and release it from one
idempotent cleanup helper called by every exit path:

```lua
local EditorWindow = {}

function EditorWindow:ReleaseKeybinds()
    if self.keybindHold ~= nil then
        self.keybindHold:Release()
        self.keybindHold = nil
    end
end

function EditorWindow.Open(ext, parent)
    local self = setmetatable({}, { __index = EditorWindow })
    if ext ~= nil and ext.SuspendKeybinds ~= nil then
        self.keybindHold = ext:SuspendKeybinds("layout editor")
    end

    local ok, err = pcall(function()
        self.window = prettyui.Window.new(parent, {
            title = "Layout Editor",
            destroyOnClose = true,
            onClose = function() self:Destroy(true) end,
        })
        -- Register Event.KeyDown for Ctrl+C / Ctrl+V / Ctrl+Z here.
    end)
    if not ok then
        -- Always release if construction fails before the window opens.
        self:ReleaseKeybinds()
        error(err)
    end
    return self
end

function EditorWindow:Destroy(fromWindowClose)
    if self.destroyed then return end
    self.destroyed = true
    self:ReleaseKeybinds()
    -- Unsubscribe Event.KeyDown and destroy window if not already closing.
    if not fromWindowClose and self.window ~= nil then
        self.window:Destroy()
    end
    self.window = nil
end
```

Also close bank-tied windows from `onBankClose` and `PluginShutdown` so the
hold is always released promptly:

```lua
local editor
local ext = bankcore.Register({
    id = "example.editor",
    name = "Editor",
    icon = "STAR",
    onBankClose = function()
        if editor ~= nil then
            editor:Destroy()
            editor = nil
        end
    end,
})

function PluginShutdown()
    if editor ~= nil then
        editor:Destroy()
        editor = nil
    end
    if ext ~= nil then
        ext:Dispose()
        ext = nil
    end
end
```

#### Nested dialogs (multiple overlapping overlays)

Each overlay manages its own hold without coordinating a manual counter:

```lua
local editorHold = ext:SuspendKeybinds("layout editor")

-- Later, while the editor is still open, show a confirmation dialog on top:
local confirmHold = ext:SuspendKeybinds("confirm delete")

-- When the confirmation dialog closes:
confirmHold:Release()
-- confirmHold:IsActive() is now false, while editorHold:IsActive() is still true
-- and Bank Core keybinds remain suspended until editorHold:Release() runs.

-- Even calling confirmHold:Release() again is a safe no-op.
confirmHold:Release()

-- When the editor itself closes:
editorHold:Release()
-- Now all holds are released and Bank Core keybinds resume on the next fresh press.
```

### Best practices and debugging

- **Acquire once per open overlay:** Store the returned hold on the overlay
  instance rather than calling `ext:SuspendKeybinds()` inside `Show()`,
  `Event.Logic`, `Event.Draw` or `customView`. If a window can be hidden and
  shown repeatedly, release on hide and acquire on show (only when
  `self.keybindHold == nil`).
- **Guard construction failures:** If building the window can throw an error
  after acquiring a hold, wrap construction in `pcall` (or acquire right after
  construction succeeds) so a failed open cannot leak a hold.
- **Pass a short `label`:** Passing a descriptive label like `"layout editor"`
  or `"import modal"` makes Core's debug logs immediately actionable.
- **Diagnosing stuck keybinds:** Enable **Enable debug** in Bank Core Settings.
  Core logs each acquire, release and automatic dispose cleanup with the
  extension ID, label and remaining active hold count:
  - `Bank Core suspended keybinds for <id> (<label>); active holds=<n>`
  - `Bank Core released keybind hold for <id> (<label>); active holds=<n>`
  - `Bank Core cleared <k> active keybind hold(s) on dispose for <id> (<labels>); active holds=<n>`

## Known limitations

- Input timing, native menu behavior, clipping, overlay draw order and dependency
  callbacks need verification in the live client.
  Very large pages also need live performance checks.
- Dragging rail icons relies on the client sending the pressed icon its hold and
  release events while the pointer crosses the rail. Shared stacks rely on the
  client reporting each object's stack type as its documented number. Both need
  live checks, including at Windows and game interface scaling.
- When a page scrolls beyond the native bank's item height, the client may clamp
  its own scroll. Core positions moved stacks against the offset it reads back.
  Different client behavior still needs live checking.
- Custom views rely on client behavior: that each layer
  clips its children and offsets them by its scroll, that click-through layers
  pass hover, clicks and the wheel to Core's input beneath, that a resized bank
  stack takes input over its new size, that `visibleGlobal` is true for drawn
  components, including ones just made, and that a destroyed component stops
  answering reads. These need live checks, including at Windows and game
  interface scaling. Core reads each bound component's position, size, scroll
  and visibility every logic tick, so very large views need performance checks.
- Logic ticks run 50 times a second. A click in the same tick as the pointer
  leaves a hovered item for a spot where no page cell, bound item or plugin
  control takes it can reach a bank stack in its own place, as in a page's gaps
  between cells.
- In modern mode, Core adds 0, 40, or 284 interface units for the hidden, rail-only,
  or expanded sidebar and subtracts only its added width and movement when
  restoring the bank. Classic mode uses a detached sidebar. Player resizes are preserved. It
  checks window size and position every 10 ticks because native resize events
  have not been verified for this use.
- A client component can ignore or refuse restoration after it disappears.
  Core keeps a record under `bankcore:window:v1`, checks the current components
  before adding sidebar space again, and retries unfinished restoration on a
  later attach. It does not widen again until that recovery succeeds.
- While Core is disabled, a player-chosen window width exactly matching the
  recorded widened width is indistinguishable from a leftover expansion. Core
  subtracts the sidebar width in that case. Native minimum-width behavior and
  changes to anchor values across interface scales also need live verification.

Core's sidebar preferences, shortcuts, debug setting and rail order are stored under
`bankcore:settings:v1`. Core settings are available from the rail cog and the
plugin manager; feature plugins host their own settings. Core
requires no HTTP permission, performs no network requests, and bundles no client
assets or PrettyUI source.
