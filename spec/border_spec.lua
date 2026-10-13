-- Blue border on locked slots: textures on the game's bag buttons, refreshed
-- after each container frame's UpdateItems and on lock changes; no field is
-- written on Blizzard's buttons (the stub errors if one is).
local loadAddon = require("spec.support.load_addon")

local function shown(button)
    if #button.textures == 0 then return false end
    for _, t in ipairs(button.textures) do if not t:IsShown() then return false end end
    return true
end

describe("locked-slot border", function()
    local ns, combined
    before_each(function()
        ns = loadAddon()
        combined = ContainerFrameCombinedBags
        combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2), WowStub.itemButton(1, 1) }
        ns.Fire("PLAYER_LOGIN")
    end)

    it("draws the border on locked slots after the bags update", function()
        MailworthyCharDB.lockedSlots["0:2"] = { itemID = 1 }
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[1]))
        assert.is_true(shown(combined.Items[2]))
        assert.is_false(shown(combined.Items[3]))
    end)

    it("follows a lock change at once, and recomputes pooled buttons", function()
        ns.Locks.Toggle(1, 1, "test")
        assert.is_true(shown(combined.Items[3]))
        combined.Items[3].slot = 2 -- the pool reused the button for another slot
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[3]))
    end)

    it("covers the individual bag frames too", function()
        local bag = ContainerFrameContainer.ContainerFrames[1]
        bag.Items = { WowStub.itemButton(2, 4) }
        MailworthyCharDB.lockedSlots["2:4"] = { itemID = 1 }
        bag:UpdateItems()
        assert.is_true(shown(bag.Items[1]))
    end)
end)
