-- Util.lua: the guarded call and the listener lists every module shares.
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
end)
