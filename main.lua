-- SPDX-License-Identifier: BSD-2-Clause
-- Copyright (C) 2026 Bank Core contributors

--[[
BSD 2-Clause License

Copyright (c) 2026 Bank Core contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

-- Start Core and make its functions available to other plugins.

-- Keep the debug setting across failed shutdowns.
local DebugLog = require("lib/core/debug_log")
local debugLog = DebugLog.Write

local previous = rawget(_G, "__bankcore_session")
if previous ~= nil then
    local ok, message = pcall(function() previous:Shutdown() end)
    if not ok then debugLog("Bank Core could not fully stop the previous reload: ", message) end
end
-- Reloading keeps the existing Lua globals and loaded modules.
if rawget(_G, "__bankcore_session") == previous then
    _G.__bankcore_session = nil
end
-- Remove the old API.
if previous ~= nil and rawget(_G, "__bankcore_api") == previous.publicAPI then
    _G.__bankcore_api = nil
end
previous = nil
pcall(function() collectgarbage("collect") end)

-- Reload these modules; update this list when lib/ changes.
if package ~= nil and package.loaded ~= nil then
    for _, moduleName in ipairs({
        "lib/bank/bank_item_hover",
        "lib/bank/bank_item_index",
        "lib/bank/native_tabs",
        "lib/bank/bank_page_items",
        "lib/bank/bank_view",
        "lib/bank/bank_window",
        "lib/bank/bank_window_record",
        "lib/bank/sidebar_host",
        "lib/core/bank_interface",
        "lib/core/bank_session",
        "lib/core/config",
        "lib/core/core_panel",
        "lib/core/core_preferences",
        "lib/core/lifecycle",
        "lib/core/mini_menu_router",
        "lib/core/object_config",
        "lib/core/public_api",
        "lib/engine/bank_grid",
        "lib/engine/bank_page_display",
        "lib/engine/bank_page_scroll",
        "lib/features/extensions/custom_view",
        "lib/features/extensions/extension_mounts",
        "lib/features/extensions/page_layout",
        "lib/features/extensions/plain_data",
        "lib/features/extensions/plugin_pages",
        "lib/ui/bank_controls",
        "lib/ui/menu_entries",
        "lib/ui/native_ui",
        "lib/ui/sidebar_frame",
        "lib/ui/sidebar_tab_rail",
        "lib/ui/theme",
        "lib/ui/tooltip",
        "lib/ui/ui_coordinates",
    }) do
        package.loaded[moduleName] = nil
    end
end

local BankSession = require("lib/core/bank_session")
local session = BankSession.new()
_G.__bankcore_session = session
session:Start()
require("lib/bank/bank_window").LogInterfaceMode()

-- Let other plugins use Core's functions.
local api = session.publicAPI
_G.__bankcore_api = api

function PluginShutdown()
    session:Shutdown()
    if rawget(_G, "__bankcore_session") == session then
        _G.__bankcore_session = nil
    end
    if rawget(_G, "__bankcore_api") == api then
        _G.__bankcore_api = nil
    end
end

return api
