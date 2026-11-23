-- Let other plugins use Core without accessing its internal files.

local PublicAPI = {}

local function createExtensionHandle(pluginPages, extension)
    return {
        SetPage = function(_, page) return pluginPages:SetPage(extension, page) end,
        Refresh = function() return pluginPages:Refresh(extension) end,
        Open = function() return pluginPages:Open(extension) end,
        Close = function() return pluginPages:ClosePage(extension) end,
        IsOpen = function() return pluginPages:IsOpen(extension) end,
        GetBankItems = function() return pluginPages:BankItems(extension) end,
        GetBankBounds = function() return pluginPages:BankBounds(extension) end,
        GetBankState = function() return pluginPages:BankState(extension) end,
        HighlightAllItems = function() return pluginPages:HighlightAllItems(extension) end,
        GetMenuItem = function(_, menu)
            local router = pluginPages.menuRouter
            if router == nil or not pluginPages:IsLive(extension) then return nil end
            return router:Describe(extension, menu)
        end,
        Dispose = function() return pluginPages:DisposeOwner(extension) end,
    }
end

-- Keep only functions here because the game copies this table.
function PublicAPI.new(pluginPages, menuRouter)
    pluginPages.menuRouter = menuRouter
    return {
        SanitizeString = function(text)
            if type(text) ~= "string" then return nil, "invalid", "text must be a string" end
            -- Strip tags first, then brackets so malformed or nested input cannot leave markup.
            local sanitized = text:gsub("<[^<>]*>", ""):gsub("[<>]", "")
            return sanitized
        end,
        Register = function(registration)
            local extension, reason, detail = pluginPages:RegisterOwner(registration)
            if extension == nil then return nil, reason, detail end
            return createExtensionHandle(pluginPages, extension)
        end,
    }
end

return PublicAPI
