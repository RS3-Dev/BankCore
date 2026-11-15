-- Run from the repository root: lua tests/sanitize_string.lua
local api = require("lib/core/public_api").new(nil, nil)

local cases = {
    { "Supplies<img=-1><sprite=999999999>", "Supplies" },
    { "<img=#><sprite=#>", "" },
    { "<col=ff0000>Food</col> <b>and potions</b>", "Food and potions" },
    { "<img=0><sprite=1>", "" },
    { "", "" },
    { "  Food\n\tCafé 銀行  ", "  Food\n\tCafé 銀行  " },
    { "before<>after", "beforeafter" },
    { "a<img=-1\n>b", "ab" },
    { "<img=<sprite=-1>>", "img=" },
    { "<im<sprite=-1>g=-1>", "img=-1" },
    { "before<img=-1", "beforeimg=-1" },
    { "x > y < z", "x  y  z" },
    { string.rep("<", 100000), "" },
}

for _, case in ipairs(cases) do
    local result = api.SanitizeString(case[1])
    assert(result == case[2], string.format("expected %q, got %q", case[2], result))
    assert(not result:find("[<>]"), "sanitized text must contain no markup brackets")
    assert(api.SanitizeString(result) == result, "sanitizing twice must be safe")
    assert(select("#", api.SanitizeString(case[1])) == 1, "return only the sanitized string")
end

local function rejects(value)
    local result, reason, detail = api.SanitizeString(value)
    assert(result == nil and reason == "invalid" and type(detail) == "string")
end
rejects(nil)
for _, value in ipairs({ false, 1, {}, function() end }) do rejects(value) end
rejects(setmetatable({}, { __tostring = function() error("must not convert objects") end }))

-- The dependency export remains a plain table containing only functions.
for _, value in pairs(api) do assert(type(value) == "function") end
print("sanitize_string: passed")
