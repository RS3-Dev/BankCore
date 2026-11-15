"""Compare readiness waits in the real session code with simulated client events.

Requires the developer-only lupa package. Results describe simulated ticks,
not measured client paint time.
"""
import json
from pathlib import Path

from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "lib/core/bank_session.lua").read_text(encoding="utf-8")
assert SOURCE.count("local BANK_READY_TICKS_REQUIRED = 8") == 1
HARNESS = r'''
id = { Inv = { BANK = 95 }, Component = {
    BANK__ALL = 517 << 16, BANK__CONTENT = (517 << 16) | 2, TOPLEVEL_V2__BANK_WINDOW = 1,
} }
Player = { IsAvailable = function() return true end }
local listeners = { Logic = {}, Draw = {} }
Event = {}
for _, kind in ipairs({ "Logic", "Draw" }) do
    Event[kind] = {
        Subscribe = function(key, callback) listeners[kind][key] = callback end,
        Unsubscribe = function(key) listeners[kind][key] = nil end,
    }
end
ui = { Interfaces = { GetComponent = function()
    return { visible = true, visibleGlobal = true }
end } }
local tick, appliedAt = 0, nil
local layout = {
    active = false,
    IsReady = function()
        return tick >= stableAt or (tick >= transientStart and tick <= transientEnd)
    end,
    Apply = function(self) self.active = true; appliedAt = tick; return true end,
}
package.loaded["lib/bank/bank_view"] = { new = function() return layout end }
package.loaded["lib/features/extensions/plugin_pages"] = { new = function() return {} end }
package.loaded["lib/core/mini_menu_router"] = { new = function() return {} end }
local Session = assert(load(sessionSource))()
local session = Session.new({ preferences = {}, windowRecord = {} })
session:BeginLayoutRetry()
local function dispatch(kind, event)
    local pending = {}
    for key, callback in pairs(listeners[kind]) do pending[#pending + 1] = { key, callback } end
    for _, entry in ipairs(pending) do
        if listeners[kind][entry[1]] == entry[2] then entry[2](event) end
    end
end
for nextTick = 1, 250 do
    tick = nextTick
    if duplicateRequests then session:BeginLayoutRetry() end
    if tick % 10 == 0 then session:RetryLayoutWhenReady() end
    dispatch("Logic", { logicTick = tick })
    dispatch("Draw", { timeDeltaSecs = 0.02 })
    if appliedAt ~= nil then break end
end
assert(appliedAt ~= nil, "simulation did not attach")
resultTick = appliedAt
premature = appliedAt < stableAt
'''


def main():
    cases = [
        ("ready immediately", 1, 0, -1, False),
        ("six ticks of unavailable geometry", 7, 0, -1, False),
        ("one-tick false ready state", 7, 1, 1, False),
        ("four-tick temporary ready state", 9, 1, 4, False),
        ("duplicate attachment requests", 1, 0, -1, True),
        ("geometry ready after retry timeout", 151, 0, -1, False),
    ]
    rows = []
    for required in (1, 2, 4, 8):
        for name, stable, first, last, duplicates in cases:
            runtime = LuaRuntime()
            state = runtime.globals()
            state.sessionSource = SOURCE.replace(
                "local BANK_READY_TICKS_REQUIRED = 8",
                f"local BANK_READY_TICKS_REQUIRED = {required}",
                1,
            )
            state.stableAt, state.transientStart, state.transientEnd = stable, first, last
            state.duplicateRequests = duplicates
            runtime.execute(HARNESS)
            row = dict(scenario=name, ready_ticks=required, apply_tick=state.resultTick,
                       premature=state.premature, approximate_tick_ms=state.resultTick * 20)
            rows.append(row)
            print(f"wait={required} {name}: apply tick {state.resultTick}, premature={state.premature}")
    output = ROOT / "dist/attachment-benchmark.json"
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps({"kind": "simulation", "results": rows}, indent=2) + "\n")
    print(output)


if __name__ == "__main__":
    main()
