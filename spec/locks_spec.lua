-- Item locks: a lock belongs to the item (its ID), so it follows the item when
-- it moves; toggled by Alt+click (mouse) or L3 in the bags (controller, the
-- selected slot read from SmartNavigation); never via the gamepad More menu.
local loadAddon = require("spec.support.load_addon")

describe("item locks", function()
    local ns, original
    before_each(function()
        original = HandleModifiedItemClick
        ns = loadAddon()
        _G.Menu = setmetatable({}, { __index = function() error("Mailworthy touched Menu") end })
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        WowStub.setBag(0, 4, WowStub.item(2770, "Copper Ore", { count = 7 }))
        ns.Fire("PLAYER_LOGIN")
    end)
    after_each(function()
        _G.HandleModifiedItemClick = original
        _G.Menu = { ModifyMenu = function(tag, fn) WowStub.menuModifiers[tag] = fn end }
    end)

    it("Alt+click locks the item: every stack, wherever it moves", function()
        WowStub.state.mods = { alt = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        assert.is_true(ns.Locks.IsItemLocked(2770))
        assert.is_true(ns.Locks.IsLocked(0, 4), "the other stack too")
        WowStub.setBag(2, 6, WowStub.state.bags[0][3]) -- sorted into another bag
        WowStub.state.bags[0][3] = nil
        assert.is_true(ns.Locks.IsLocked(2, 6))
        assert.is_false(ns.Locks.IsLocked(0, 3), "the old slot isn't locked any more")
        HandleModifiedItemClick("link", WowStub.itemLocation(2, 6))
        assert.is_false(ns.Locks.IsItemLocked(2770))
    end)

    it("Alt+click in the reagent bag (bag 5) locks; a bank tab (bag 6) doesn't", function()
        WowStub.setBag(5, 2, WowStub.item(2589, "Linen Cloth", { count = 6 }))
        WowStub.setBag(6, 1, WowStub.item(2835, "Rough Stone", { count = 3 }))
        WowStub.state.mods = { alt = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(5, 2))
        assert.is_true(ns.Locks.IsItemLocked(2589))
        HandleModifiedItemClick("link", WowStub.itemLocation(6, 1))
        assert.is_false(ns.Locks.IsItemLocked(2835))
        WowStub.state.navButton = WowStub.itemButton(5, 2)
        ns.Locks.ToggleSelectedBagSlot()
        assert.is_false(ns.Locks.IsItemLocked(2589), "L3 reaches the reagent bag too")
    end)

    it("ignores clicks without Alt, with other modifiers too, and outside the bags", function()
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        WowStub.state.mods = { alt = true, shift = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        WowStub.state.mods = { alt = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(-1, 3)) -- bank
        HandleModifiedItemClick("link", WowStub.itemLocation(nil, nil)) -- equipment slot
        HandleModifiedItemClick("link", nil)
        assert.same({}, MailworthyCharDB.lockedItems)
    end)

    it("L3: locks the bag item smart navigation has selected, and nothing else", function()
        WowStub.state.navButton = WowStub.itemButton(0, 3)
        ns.Locks.ToggleSelectedBagSlot()
        assert.is_true(ns.Locks.IsItemLocked(2770))
        WowStub.state.navButton = { buttonContext = "ButtonContext_PaperDollItemSlotButton" }
        assert.is_nil(ns.Locks.ToggleSelectedBagSlot())
        WowStub.state.navButton = nil
        assert.is_nil(ns.Locks.ToggleSelectedBagSlot())
    end)

    it("converts slot locks from earlier builds into item locks", function()
        local ns2 = loadAddon()
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        MailworthyCharDB.lockedSlots = { ["0:3"] = { itemID = 2770 }, ["1:9"] = { itemID = 1 } }
        ns2.Fire("PLAYER_LOGIN")
        assert.is_true(ns2.Locks.IsItemLocked(2770))
        assert.is_nil(MailworthyCharDB.lockedSlots)
    end)

    it("tells listeners (glow, window) when a lock changes", function()
        local calls = 0
        ns.Locks.OnChanged(function() calls = calls + 1 end)
        ns.Locks.Toggle(0, 3, "test")
        assert.equal(1, calls)
    end)

    it("can be switched off", function()
        local ns2 = loadAddon()
        ns2.HandleSlash("feature altclicklock off")
        assert.is_false(ns2.Locks.Install())
    end)
end)
