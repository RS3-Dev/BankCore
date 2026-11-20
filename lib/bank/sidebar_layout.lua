-- Share the sidebar's edge and expansion geometry across both interface modes.
local Config = require("lib/core/config")
local Layout = {}

-- Return the width added before the native bank contents.
function Layout.BeforeBank(width, edge)
    return edge == "right" and 0 or width
end

function Layout.LeftGrowth(width, expansion, edge)
    if expansion == "evenly" then return math.floor(width / 2) end
    return Layout.BeforeBank(width, edge)
end

function Layout.Anchor(expansion, edge)
    if expansion == "evenly" then return 0.5 end
    return edge == "right" and 0 or 1
end

-- Mirror a fixed-width control while keeping its text and artwork upright.
function Layout.Position(view, x, width)
    if view.sidebarEdge == "right" then return -x - width, 1 end
    return x, 0
end

function Layout.Inset(view)
    return view.detachedSidebar and Config.CLASSIC_SIDEBAR_LEFT_PADDING or 12
end

return Layout
