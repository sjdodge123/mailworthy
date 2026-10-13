-- "Mailworthy: Lock slot" in the bag item Triangle menu (Menu.ModifyMenu on
-- MORE_CONTEXT_ACTIONS), only for bag item buttons; locks are per character.
local loadAddon = require("spec.support.load_addon")

local function bagButton(bag, slot)
    return {
        buttonContext = "ButtonContext_ContainerFrameItemButton",
        GetBagID = function() return bag end,
        GetID = function() return slot end,
        GetDebugName = function() return "ContainerFrame1Item" .. slot end,
    }
end

local function menu()
    local m = { buttons = {} }
    function m:CreateButton(label, fn) table.insert(self.buttons, { label = label, fn = fn }) end
    return m
end

describe("slot locks", function()
    local ns
    before_each(function()
        ns = loadAddon()
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        ns.Fire("PLAYER_LOGIN")
    end)

    it("hooks the bag item More menu", function()
        assert.is_function(WowStub.menuModifiers.MORE_CONTEXT_ACTIONS)
    end)

    it("adds Lock slot on a bag item, then Unlock slot once locked", function()
        local m = menu()
        WowStub.menuModifiers.MORE_CONTEXT_ACTIONS(bagButton(0, 3), m)
        assert.equal("Mailworthy: Lock slot", m.buttons[1].label)
        m.buttons[1].fn()
        assert.is_true(ns.Locks.IsLocked(0, 3))
        assert.equal(2770, MailworthyCharDB.lockedSlots["0:3"].itemID)
        local m2 = menu()
        WowStub.menuModifiers.MORE_CONTEXT_ACTIONS(bagButton(0, 3), m2)
        assert.equal("Mailworthy: Unlock slot", m2.buttons[1].label)
        m2.buttons[1].fn()
        assert.is_false(ns.Locks.IsLocked(0, 3))
    end)

    it("adds nothing to other More menus (spellbook, character screen)", function()
        local m = menu()
        WowStub.menuModifiers.MORE_CONTEXT_ACTIONS({ buttonContext = "ButtonContext_SpellButton" }, m)
        WowStub.menuModifiers.MORE_CONTEXT_ACTIONS(nil, m)
        assert.equal(0, #m.buttons)
        local log = table.concat(MailworthyDB.selftest.log, "\n")
        assert.truthy(log:find("not a bag item (context ButtonContext_SpellButton)", 1, true))
    end)

    it("ignores the stale replay ModifyMenu makes while installing", function()
        local m = menu()
        _G.Menu.ModifyMenu = function(tag, fn)
            WowStub.menuModifiers[tag] = fn
            fn(bagButton(0, 3), m) -- replay of an earlier menu, at install time
        end
        ns.Locks.Install()
        assert.equal(0, #m.buttons)
    end)

    it("logs and carries on when the menu API is missing", function()
        _G.Menu = nil
        assert.is_false(ns.Locks.Install())
        _G.Menu = { ModifyMenu = function(tag, fn) WowStub.menuModifiers[tag] = fn end }
    end)
end)
