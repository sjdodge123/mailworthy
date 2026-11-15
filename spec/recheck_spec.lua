-- The last-moment re-check (AGENTS Safety: "Re-check each slot right before attaching it; skip
-- anything that changed"): Mailer.StillThere (before each attach) and Vendor.StillThere (before each
-- sale) are one function, Bags.StillThere, with each caller's words. Every case here is refused by
-- both, in their own words, so the two can't drift apart again.
local loadAddon = require("spec.support.load_addon")

describe("the last-moment re-check (Bags.StillThere)", function()
    local ns
    local ORE, ARROW, STONE = 2770, 3030, 5512
    local function ore(o) return WowStub.item(ORE, "Copper Ore", o or { count = 20, sell = 5, class = 7, subclass = 7 }) end
    local function stack(id, name, count) return { bag = 0, slot = 1, itemID = id, link = WowStub.link(id, name), count = count } end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        WowStub.setBag(0, 1, ore())
    end)

    local function both(s)
        return { { ns.Mailer.StillThere(s) }, { ns.Vendor.StillThere(s) } }
    end

    it("passes an unchanged stack, for both", function()
        assert.same({ { true }, { true } }, both(stack(ORE, "Copper Ore", 20)))
    end)

    it("refuses an empty slot", function()
        WowStub.setBag(0, 1, nil)
        assert.same({ { false, "gone" }, { false, "the slot is empty" } }, both(stack(ORE, "Copper Ore", 20)))
    end)

    it("refuses another item, and another variant of the same item ID", function()
        WowStub.setBag(0, 1, WowStub.item(2589, "Linen Cloth", { count = 20 }))
        assert.same({ { false, "a different item" }, { false, "a different item is there now" } },
            both(stack(ORE, "Copper Ore", 20)))
        WowStub.setBag(0, 1, WowStub.item(ORE, "Copper Ore of the Bear", { count = 20, sell = 5 }))
        assert.same({ { false, "a different item" }, { false, "a different item is there now" } },
            both(stack(ORE, "Copper Ore", 20)))
    end)

    it("refuses a stack whose count changed", function()
        assert.same({ { false, "count changed" }, { false, "the stack changed" } }, both(stack(ORE, "Copper Ore", 19)))
    end)

    it("refuses a stack the game has in use", function()
        local item = ore()
        item.isLocked = true
        WowStub.setBag(0, 1, item)
        assert.same({ { false, "in use" }, { false, "in use" } }, both(stack(ORE, "Copper Ore", 20)))
    end)

    it("refuses a locked item", function()
        ns.Locks.ToggleItem(ORE, WowStub.link(ORE, "Copper Ore"), "spec")
        assert.same({ { false, "locked" }, { false, "locked" } }, both(stack(ORE, "Copper Ore", 20)))
    end)

    it("refuses what an active quest asks for", function()
        WowStub.state.quests = { { title = "Ore", objectives = { { text = "Copper Ore: 0/20", type = "item" } } } }
        ns.Fire("QUEST_LOG_UPDATE")
        assert.same({ { false, "an active quest needs it" }, { false, "a quest needs it" } }, both(stack(ORE, "Copper Ore", 20)))
    end)

    it("refuses a conjured item", function()
        WowStub.setBag(0, 1, WowStub.item(STONE, "Minor Healthstone", { count = 1, class = 0 }))
        WowStub.state.conjured[STONE] = true
        assert.same({ { false, "conjured" }, { false, "conjured" } }, both(stack(STONE, "Minor Healthstone", 1)))
    end)

    it("refuses the ammo the equipped ranged weapon fires", function()
        WowStub.setBag(0, 1, WowStub.item(ARROW, "Razor Arrow", { count = 200, sell = 1, class = 6, subclass = 2 }))
        local s = stack(ARROW, "Razor Arrow", 200)
        assert.same({ { true }, { true } }, both(s), "no bow yet")
        WowStub.equipRanged(WowStub.item(9002, "Hunting Bow", { class = 2, subclass = 2 }))
        assert.same({ { false, "ammo" }, { false, "ammo for your ranged weapon" } }, both(s))
    end)

    it("each caller's own checks: soulbound never mails, no vendor buys a no-value item, owed back never sells", function()
        WowStub.setBag(0, 1, ore({ count = 20, sell = 5, class = 7, bound = true }))
        local s = stack(ORE, "Copper Ore", 20)
        assert.same({ false, "soulbound" }, { ns.Mailer.StillThere(s) })
        assert.is_true(ns.Vendor.StillThere(s), "a vendor-pinned soulbound item sells")
        WowStub.setBag(0, 1, ore({ count = 20, sell = 5, class = 7, noValue = true }))
        assert.same({ false, "no vendor buys it" }, { ns.Vendor.StillThere(s) })
        WowStub.setBag(0, 1, ore())
        local current = ns.Returns.Current
        ns.Returns.Current = function() return { [ORE] = { { to = "Bob Surname", count = 20, at = 1 } } } end
        assert.same({ false, "another player mailed it to you" }, { ns.Vendor.StillThere(s) })
        assert.is_true(ns.Mailer.StillThere(s), "a return mail sends it back")
        ns.Returns.Current = current
    end)

    it("a check without words says its own name: it never passes for want of a text", function()
        local s = stack(ORE, "Copper Ore", 20)
        assert.is_true(ns.Bags.StillThere(s))
        ns.Locks.ToggleItem(ORE, WowStub.link(ORE, "Copper Ore"), "spec")
        assert.same({ false, "locked" }, { ns.Bags.StillThere(s, { words = {} }) })
        assert.same({ false, "count" }, { ns.Bags.StillThere(stack(ORE, "Copper Ore", 5)) })
    end)
end)
