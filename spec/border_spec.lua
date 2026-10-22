-- Blue glow on locked items (the quest-item border, tinted): textures on the
-- game's bag buttons, refreshed after UpdateItems, on lock changes and when the
-- mailbox opens or closes; shown only while a mailbox is open unless the
-- "glow everywhere" setting is on; no field is written on Blizzard's buttons
-- (the stub errors if one is).
local loadAddon = require("spec.support.load_addon")

local function shown(button)
    if #button.textures == 0 then return false end
    for _, t in ipairs(button.textures) do if not t:IsShown() then return false end end
    return true
end

describe("locked-item glow", function()
    local ns, combined
    before_each(function()
        ns = loadAddon()
        WowStub.setBag(0, 1, WowStub.item(2589, "Linen Cloth", { count = 6 }))
        WowStub.setBag(0, 2, WowStub.item(2770, "Copper Ore", { count = 5 }))
        WowStub.setBag(1, 1, WowStub.item(2770, "Copper Ore", { count = 9 }))
        combined = ContainerFrameCombinedBags
        combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2), WowStub.itemButton(1, 1) }
        ns.Fire("PLAYER_LOGIN")
        ns.Fire("MAIL_SHOW") -- most of these run at the mailbox
    end)

    it("shows only while a mailbox is open", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        ns.Fire("MAIL_CLOSED")
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[2]), "away from the mailbox: no glow")
        ns.Locks.Toggle(0, 1, "test")
        assert.is_false(shown(combined.Items[1]), "a lock change away from the mailbox draws nothing")
        assert.is_true(ns.Locks.IsItemLocked(2589), "but the lock itself is kept")
        ns.Fire("MAIL_SHOW")
        assert.is_true(shown(combined.Items[1]), "opening the mailbox refreshes the open bags")
        assert.is_true(shown(combined.Items[2]))
        ns.Fire("MAIL_CLOSED")
        assert.is_false(shown(combined.Items[1]), "closing it clears them")
        assert.is_false(shown(combined.Items[3]))
    end)

    it("the glow everywhere setting keeps it on away from the mailbox", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        ns.Fire("MAIL_CLOSED")
        ns.Config.Set("glowEverywhere", true)
        combined:UpdateItems()
        assert.is_true(shown(combined.Items[2]))
        _G.MailworthySettingsGlow:Click()
        assert.is_false(ns.Config.Flag("glowEverywhere"))
        assert.is_false(shown(combined.Items[2]), "the settings button refreshes the bags at once")
        assert.equal("Locked items glow blue: at the mailbox only", _G.MailworthySettingsGlow:GetText())
    end)

    it("Blizzard's mail window being shown counts as a mailbox too", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        ns.Fire("MAIL_CLOSED")
        MailFrame:Show()
        combined:UpdateItems()
        assert.is_true(shown(combined.Items[2]))
    end)

    it("glows every stack of a locked item after the bags update", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[1]))
        assert.is_true(shown(combined.Items[2]))
        assert.is_true(shown(combined.Items[3]))
        assert.equal(2, #combined.Items[2].textures, "border + additive glow")
    end)

    it("follows a lock change at once, and recomputes pooled buttons", function()
        ns.Locks.Toggle(0, 1, "test")
        assert.is_true(shown(combined.Items[1]))
        combined.Items[1].slot = 2 -- the pool reused the button for another slot (Copper Ore)
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[1]))
    end)

    it("covers the individual bag frames too", function()
        local bag = ContainerFrameContainer.ContainerFrames[1]
        bag.Items = { WowStub.itemButton(1, 1) }
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        bag:UpdateItems()
        assert.is_true(shown(bag.Items[1]))
    end)
end)
