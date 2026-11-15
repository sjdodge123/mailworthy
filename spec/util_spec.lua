-- Util.lua: the guarded call, the listener lists and the small helpers every module shares.
local loadAddon = require("spec.support.load_addon")

describe("Util", function()
    local ns
    before_each(function() ns = loadAddon() end)

    local function errorLines()
        local out = {}
        for _, line in ipairs(MailworthyDB.log or {}) do
            if line:find("[error]", 1, true) then out[#out + 1] = line end
        end
        return out
    end

    it("Call returns every result, and nil for an error or a non-function", function()
        local a, b, c = ns.Util.Call(function(x) return x, nil, 3 end, 1)
        assert.equal(1, a)
        assert.is_nil(b)
        assert.equal(3, c)
        assert.is_nil(ns.Util.Call(function() error("boom") end))
        assert.is_nil(ns.Util.Call(nil))
        assert.is_nil(ns.Util.Call("not a function"))
    end)

    it("Signal calls each listener in order with the arguments, and ignores non-functions", function()
        local s, got = ns.Util.Signal("test"), {}
        s.Add(function(...) got[#got + 1] = { "a", ... } end)
        s.Add(nil)
        s.Add("nope")
        s.Add(function(...) got[#got + 1] = { "b", ... } end)
        assert.equal(2, s.Count())
        s.Fire(7, "x")
        assert.same({ { "a", 7, "x" }, { "b", 7, "x" } }, got)
    end)

    it("a listener's error is logged and never stops the others", function()
        ns.Init()
        local s, after = ns.Util.Signal("test area"), false
        s.Add(function() error("listener broke") end)
        s.Add(function() after = true end)
        s.Fire()
        assert.is_true(after)
        local lines = errorLines()
        assert.equal(1, #lines)
        assert.truthy(lines[1]:find("test area listener", 1, true))
        assert.truthy(lines[1]:find("listener broke", 1, true))
    end)

    it("Locks and Pins listeners now log their errors (they were dropped silently)", function()
        ns.Init()
        for _, add in ipairs({ ns.Locks.OnChanged, ns.Pins.OnChanged }) do
            add(function() error("redraw failed") end)
        end
        ns.Locks.ToggleItem(2770, "[Copper Ore]", "spec")
        ns.Pins.Set(2770, "[Copper Ore]", ns.Pins.BANK, "spec")
        assert.equal(2, #errorLines())
    end)

    -- Round two ------------------------------------------------------------------------------

    it("Now is the server time, or the client's when GetServerTime is missing, fails or says nothing", function()
        assert.equal(1791900000, ns.Util.Now())
        local saved, savedTime = _G.GetServerTime, _G.time
        finally(function() _G.GetServerTime, _G.time = saved, savedTime end)
        _G.time = function() return 42 end
        _G.GetServerTime = function() error("no server time") end
        assert.equal(42, ns.Util.Now())
        _G.GetServerTime = function() end
        assert.equal(42, ns.Util.Now())
        _G.GetServerTime = nil
        assert.equal(42, ns.Util.Now())
    end)

    it("After waits with C_Timer, and runs at once without one", function()
        local ran = 0
        ns.Util.After(2, function() ran = ran + 1 end)
        assert.equal(0, ran)
        local timer = WowStub.timers[#WowStub.timers]
        assert.equal(2, timer.delay)
        timer.fn()
        assert.equal(1, ran)
        local saved = _G.C_Timer
        finally(function() _G.C_Timer = saved end)
        _G.C_Timer = nil
        ns.Util.After(2, function() ran = ran + 1 end)
        assert.equal(2, ran)
        _G.C_Timer = {}
        ns.Util.After(2, function() ran = ran + 1 end)
        assert.equal(3, ran)
    end)

    it("RealmKey is realm|faction, then the realm and the faction; tostring'd when unknown", function()
        local key, realm, faction = ns.Util.RealmKey()
        assert.equal("Classic Beta PvP|Alliance", key)
        assert.equal("Classic Beta PvP", realm)
        assert.equal("Alliance", faction)
        WowStub.state.realm, WowStub.state.faction = nil, "Horde"
        assert.equal("nil|Horde", (ns.Util.RealmKey()))
    end)

    it("Table keeps a table and gives a new one for anything else", function()
        local t = { 1 }
        assert.equal(t, ns.Util.Table(t))
        for _, v in ipairs({ "x", 5, false }) do assert.same({}, ns.Util.Table(v)) end
        assert.same({}, ns.Util.Table(nil))
        assert.are_not.equal(ns.Util.Table(nil), ns.Util.Table(nil))
    end)

    it("Store makes db[field] (and db[field][key]) a table, keeps what is there, and returns it", function()
        local db = { a = "junk", b = { k = { 1 } } }
        local a = ns.Util.Store(db, "a")
        assert.same({}, a)
        assert.equal(db.a, a)
        assert.equal(db.b.k, ns.Util.Store(db, "b", "k"))
        assert.same({ 1 }, db.b.k)
        local made = ns.Util.Store(db, "c", 7)
        assert.equal(db.c[7], made)
        assert.same({ [7] = {} }, db.c)
        db.b.k = 3
        assert.same({}, ns.Util.Store(db, "b", "k"))
        assert.equal(db.b, ns.Util.Store(db, "b"))
    end)

    it("NameKey is Routes.Clean's name lower-cased, nil when there is none", function()
        assert.equal("rettana quilwrit", ns.Util.NameKey("  Rettana   Quilwrit-Classic Beta PvP "))
        assert.equal("bob", ns.Util.NameKey("Bob-Realm"))
        for _, v in ipairs({ "", "   ", 5, false }) do assert.is_nil(ns.Util.NameKey(v)) end
        assert.is_nil(ns.Util.NameKey(nil))
    end)

    it("LinkName is the name in a link's brackets, nil for anything else", function()
        assert.equal("Copper Ore", ns.Util.LinkName("|cffffffff|Hitem:2770::::::::|h[Copper Ore]|h|r"))
        assert.equal("Copper Ore", ns.Util.LinkName("[Copper Ore]"))
        assert.equal("", ns.Util.LinkName("[]"))
        assert.is_nil(ns.Util.LinkName("Copper Ore"))
        assert.is_nil(ns.Util.LinkName(2770))
        assert.is_nil(ns.Util.LinkName(nil))
    end)

    it("ListText joins with commas and a last 'and', and gives `none` for an empty list", function()
        assert.equal("nobody", ns.Util.ListText({}, "nobody"))
        assert.is_nil(ns.Util.ListText({}))
        assert.equal("Ann", ns.Util.ListText({ "Ann" }, "nobody"))
        assert.equal("Ann and Bob", ns.Util.ListText({ "Ann", "Bob" }))
        assert.equal("Ann, Bob and Cy", ns.Util.ListText({ "Ann", "Bob", "Cy" }))
    end)
end)
