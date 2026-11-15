-- One "scan inputs changed" signal (Bags.OnInputsChanged / Bags.InputsChanged): everything that changes
-- what a scan reads fires it, and the bag tags' cache (BankAlt) and Trip listen, so none of them is
-- left stale until the next bag update.
local loadAddon = require("spec.support.load_addon")

describe("scan inputs changed (Bags.OnInputsChanged)", function()
    local ns, fired
    local BOB = "Bob Surname"
    local ORE = 2770

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.setBag(0, 1, WowStub.item(ORE, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }))
        fired = {}
        ns.Bags.OnInputsChanged(function(why, lazy) fired[#fired + 1] = why .. (lazy and " (lazy)" or "") end)
    end)
    after_each(function()
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    local function firedFor(action)
        fired = {}
        action()
        return fired
    end

    it("every input fires it: locks, pins, the pin mode, the bank alt skipped, Return to sender", function()
        local link = WowStub.link(ORE, "Copper Ore")
        assert.same({ "lock" }, firedFor(function() ns.Locks.ToggleItem(ORE, link, "spec") end))
        assert.same({ "pin" }, firedFor(function() ns.Pins.Set(ORE, link, ns.Pins.BANK, "spec") end))
        assert.same({ "pin" }, firedFor(function() ns.Pins.SetMode(ns.Pins.HERE, "spec") end))
        assert.same({ "bank alt skip" }, firedFor(function() ns.Bags.SkipBankAlt(true) end))
        assert.same({ "returns" }, firedFor(function() ns.Returns.Set(true) end))
    end)

    it("bindings: added, removed, moved, capped, Gear, skipped once, picked; the visit's end drops picks", function()
        local route
        assert.same({ "routes" }, firedFor(function() route = ns.Routes.Add(BOB, 333) end))
        assert.same({ "routes" }, firedFor(function() ns.Routes.StepCap(route.key, 1) end))
        assert.same({ "routes" }, firedFor(function() ns.Routes.ToggleGear(route.key) end))
        assert.same({ "routes" }, firedFor(function() ns.Routes.ToggleScope(route.key) end))
        assert.same({ "skip" }, firedFor(function() ns.Routes.SkipOnce(route.key) end))
        assert.same({ "skip" }, firedFor(function() ns.Routes.Unskip(route.key) end))
        assert.same({ "pick" }, firedFor(function() ns.Routes.Pick(WowStub.link(ORE, "Copper Ore"), route.key) end))
        local closed = firedFor(function() ns.Fire("MAIL_CLOSED") end)
        assert.truthy(table.concat(closed, ","):find("visit over (lazy)", 1, true), table.concat(closed, ","))
        assert.same({ "routes" }, firedFor(function() ns.Routes.Remove(route.key) end))
    end)

    it("quests, recipes, settings and the bank alt: the last three lazily", function()
        ns.Fire("QUEST_LOG_UPDATE") -- the first read
        WowStub.state.quests = { { title = "Ore", objectives = { { text = "Copper Ore: 0/20", type = "item" } } } }
        assert.same({ "quests" }, firedFor(function() ns.Fire("QUEST_LOG_UPDATE") end))
        assert.same({}, firedFor(function() ns.Fire("QUEST_LOG_UPDATE") end), "the same needs: nothing")
        local shown = firedFor(function() ns.Fire("MAIL_SHOW") end)
        assert.truthy(table.concat(shown, ","):find("recipes (lazy)", 1, true), table.concat(shown, ","))
        assert.same({ "settings (lazy)" }, firedFor(function() ns.Config.Set("minGain", 200) end))
        assert.same({ "bank alt (lazy)" }, firedFor(function() ns.Config.ClearBankAlt() end))
        assert.same({ "bank alt (lazy)" }, firedFor(function() ns.Config.SetBankAlt("Roknua Themicrulah") end))
    end)

    it("the bag tags read the bags again after a row pick (before, they lagged until the next bag update)", function()
        ns.Config.SetBankAltHere() -- the bank alt: its bags are tagged
        local scans, evaluate = 0, ns.Bags.Evaluate
        ns.Bags.Evaluate = function(...)
            scans = scans + 1
            return evaluate(...)
        end
        ns.BankAlt.ItemFor(ORE)
        local before = scans
        ns.BankAlt.ItemFor(ORE)
        assert.equal(before, scans, "nothing changed: the cached scan")
        ns.Routes.Pick(WowStub.link(ORE, "Copper Ore"), ns.Routes.MINE)
        ns.BankAlt.ItemFor(ORE)
        assert.is_true(scans > before, "a pick: scanned again")
        before = scans
        ns.Config.Set("minGain", 300) -- lazy: stale, read at the next use
        assert.equal(before, scans)
        ns.BankAlt.ItemFor(ORE)
        assert.equal(before + 1, scans)
        ns.Bags.Evaluate = evaluate
    end)
end)
