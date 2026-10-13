-- Slot locks: Alt+click on a bag item (mouse) through a post-hook of
-- HandleModifiedItemClick; never through the gamepad More menu (that tainted
-- controller input in alpha1/alpha2).
local loadAddon = require("spec.support.load_addon")

describe("slot locks", function()
    local ns, original
    before_each(function()
        original = HandleModifiedItemClick
        ns = loadAddon()
        _G.Menu = setmetatable({}, { __index = function() error("Mailworthy touched Menu") end })
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        ns.Fire("PLAYER_LOGIN")
    end)
    after_each(function()
        _G.HandleModifiedItemClick = original
        _G.Menu = { ModifyMenu = function(tag, fn) WowStub.menuModifiers[tag] = fn end }
    end)

    it("Alt+click on a bag item toggles its lock", function()
        WowStub.state.mods = { alt = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        assert.is_true(ns.Locks.IsLocked(0, 3))
        assert.equal(2770, MailworthyCharDB.lockedSlots["0:3"].itemID)
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        assert.is_false(ns.Locks.IsLocked(0, 3))
        assert.truthy(table.concat(MailworthyDB.selftest.log, "\n"):find("locked bag 0 slot 3", 1, true))
    end)

    it("ignores clicks without Alt, with other modifiers too, and outside the bags", function()
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        WowStub.state.mods = { alt = true, shift = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        WowStub.state.mods = { alt = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(-1, 3)) -- bank
        HandleModifiedItemClick("link", WowStub.itemLocation(nil, nil)) -- equipment slot
        HandleModifiedItemClick("link", nil)
        assert.same({}, MailworthyCharDB.lockedSlots)
    end)

    it("tells listeners (border, window) when a lock changes", function()
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
