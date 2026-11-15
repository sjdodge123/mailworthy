-- Small helpers every module used to copy by hand (UX and architecture pass, 2026-11-15):
-- a guarded call and the listener list behind Locks.OnChanged, Pins.OnChanged, Mailer.OnChanged /
-- OnSent, Ledger.OnChanged, Version.OnChanged and Comms.OnMarksChanged; then (round two) the server
-- time, a timer with a synchronous fallback, the realm|faction key, SavedVariables stores, a name's
-- lower-case key, an item's name from its link and "a, b and c". Loads right after Core and Log, so
-- any file below can take them as locals at load.
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

--- The server's time (GetServerTime), or the client's (time()) when it is missing or fails.
function Util.Now()
    return Util.Call(GetServerTime) or time()
end

--- Run `fn` after `delay` seconds (C_Timer.After), or at once when there is no C_Timer.
function Util.After(delay, fn)
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(delay, fn) else fn() end
end

--- The key a realm's SavedVariables are kept under: "realm|faction" for this character; then the
--- realm and the faction themselves (Characters.Current).
function Util.RealmKey()
    local _, realm, faction = ns.Characters.Current()
    return tostring(realm) .. "|" .. tostring(faction), realm, faction
end

--- `v` when it is a table, else a new empty one.
function Util.Table(v)
    return type(v) == "table" and v or {}
end

--- `db[field]`, made a table when it isn't one; with `key`, `db[field][key]`, made a table the same way.
function Util.Store(db, field, key)
    db[field] = Util.Table(db[field])
    if key == nil then return db[field] end
    local t = db[field]
    t[key] = Util.Table(t[key])
    return t[key]
end

--- A player name's lower-case key: Characters.Clean's name (no realm, spaces trimmed), lower-cased; nil
--- when there is none. Characters loads later, so it is read at call time.
function Util.NameKey(name)
    local clean = ns.Characters.Clean(name)
    return clean and clean:lower() or nil
end

--- The name inside an item link ("|cff..|h[Copper Ore]|h|r" -> "Copper Ore"), or nil (not a string, no name).
function Util.LinkName(link)
    return type(link) == "string" and link:match("%[(.-)%]") or nil
end

--- "a", "a and b", "a, b and c"; `none` for an empty list.
function Util.ListText(list, none)
    if #list == 0 then return none end
    if #list == 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end
