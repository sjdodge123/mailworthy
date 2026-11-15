-- Small helpers every module used to copy by hand (UX and architecture pass, 2026-11-15):
-- a guarded call and the listener list behind Locks.OnChanged, Pins.OnChanged, Mailer.OnChanged /
-- OnSent, Ledger.OnChanged, Version.OnChanged and Comms.OnMarksChanged. Loads right after Core and
-- Log, so any file below can take them as locals at load.
local _, ns = ...

local Util = {}
ns.Util = Util

--- Call `fn(...)` under pcall: its results, or nil when `fn` is not a function or it errors.
function Util.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

--- A listener list. `signal.Add(fn)` registers `fn` (anything but a function is ignored);
--- `signal.Fire(...)` calls each one with the arguments, under pcall, in the order they were added.
--- An error is logged under `area` and never stops the other listeners (before this, four of the
--- seven hand-made lists dropped errors without a trace: HANDOFF "Process pitfalls").
function Util.Signal(area)
    local listeners = {}
    local signal = {}
    function signal.Add(fn)
        if type(fn) == "function" then listeners[#listeners + 1] = fn end
    end
    function signal.Fire(...)
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn, ...)
            if not ok and ns.Log then ns.Log.Add("error", "%s listener: %s", tostring(area), tostring(err)) end
        end
    end
    function signal.Count() return #listeners end
    return signal
end
