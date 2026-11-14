-- Ammo (Ammo.lua; operator, 2026-11-14: "Matching type only"): the arrows or bullets the equipped
-- ranged weapon fires are a hard keep; the other type, and all ammo with no bow, crossbow or gun
-- equipped, are valued like any item. Before this, a stack of either was listed for the bank alt
-- with or without Auctionator.
local loadAddon = require("spec.support.load_addon")

local BANK_ALT = "Roknua Themicrulah"
local RAZOR_ARROW, SOLID_SHOT = 3030, 3033

describe("ammo", function()
    local ns, prices

    local function find(list, itemID)
        for _, it in ipairs(list) do if it.itemID == itemID then return it end end
    end

    local function useAuctionator()
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end

    local function equip(name, subclass)
        WowStub.equipRanged(name and WowStub.item(9000 + subclass, name, { class = 2, subclass = subclass }) or nil)
    end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(BANK_ALT)
        prices = {}
        local arrows = WowStub.item(RAZOR_ARROW, "Razor Arrow", { count = 200, sell = 0, class = 6, subclass = 2 })
        local shot = WowStub.item(SOLID_SHOT, "Solid Shot", { count = 200, sell = 0, class = 6, subclass = 3 })
        WowStub.setBag(0, 1, arrows)
        WowStub.setBag(0, 2, shot)
        prices[arrows.hyperlink] = 25 -- 25c an arrow: 50s a stack, clears the minimum gain
        prices[shot.hyperlink] = 25
    end)
    after_each(function() _G.Auctionator = nil end)

    describe("which ammo a ranged weapon fires", function()
        it("a bow or a crossbow fires arrows, a gun bullets; a wand, a thrown weapon or a non-weapon nothing", function()
            assert.equal(2, ns.Ammo.Fires(2, 2), "bow")
            assert.equal(2, ns.Ammo.Fires(2, 18), "crossbow")
            assert.equal(3, ns.Ammo.Fires(2, 3), "gun")
            assert.is_nil(ns.Ammo.Fires(2, 19), "wand")
            assert.is_nil(ns.Ammo.Fires(2, 16), "thrown")
            assert.is_nil(ns.Ammo.Fires(4, 2), "armor of the same subclass")
            assert.is_nil(ns.Ammo.Fires(nil, nil))
        end)

        it("matches only projectiles of that subclass", function()
            assert.is_true(ns.Ammo.Matches(6, 2, 2))
            assert.is_false(ns.Ammo.Matches(6, 3, 2))
            assert.is_false(ns.Ammo.Matches(7, 2, 2), "a trade good with the arrows' subclass number")
            assert.is_false(ns.Ammo.Matches(6, 2, nil), "nothing equipped")
        end)

        it("reads the ranged slot, and no answer from the client keeps nothing", function()
            assert.is_nil(ns.Ammo.Equipped())
            equip("Hunting Bow", 2)
            assert.equal(2, ns.Ammo.Equipped())
            assert.is_true(ns.Ammo.Is(WowStub.link(RAZOR_ARROW, "Razor Arrow")))
            assert.is_false(ns.Ammo.Is(WowStub.link(SOLID_SHOT, "Solid Shot")))
            local saved = _G.GetInventoryItemID
            _G.GetInventoryItemID = function() error("no such call") end
            assert.is_nil(ns.Ammo.Equipped())
            _G.GetInventoryItemID = nil
            assert.is_nil(ns.Ammo.Equipped())
            _G.GetInventoryItemID = saved
        end)
    end)

    describe("the bag scan", function()
        it("with a bow, the arrows stay ('ammo'), without a price source and with Auctionator; the bullets go", function()
            equip("Hunting Bow", 2)
            local result = ns.Bags.Evaluate()
            assert.equal("ammo", find(result.keep, RAZOR_ARROW).result.reason)
            assert.equal("mail", find(result.mail, SOLID_SHOT).result.action)
            useAuctionator()
            result = ns.Bags.Evaluate()
            assert.equal("ammo", find(result.keep, RAZOR_ARROW).result.reason, "priced, worth listing: still stays")
            assert.equal("ah", find(result.mail, SOLID_SHOT).result.route)
        end)

        it("with a crossbow the arrows stay; with a gun the bullets stay and the arrows go", function()
            equip("Light Crossbow", 18)
            assert.truthy(find(ns.Bags.Evaluate().keep, RAZOR_ARROW))
            equip("Rough Boomstick", 3)
            local result = ns.Bags.Evaluate()
            assert.equal("ammo", find(result.keep, SOLID_SHOT).result.reason)
            assert.truthy(find(result.mail, RAZOR_ARROW))
        end)

        it("with no ranged weapon, or a wand or a thrown weapon, all ammo is valued like any item", function()
            for _, weapon in ipairs({ false, { "Gnarled Wand", 19 }, { "Small Throwing Knife", 16 } }) do
                equip(weapon and weapon[1], weapon and weapon[2])
                local result = ns.Bags.Evaluate()
                assert.truthy(find(result.mail, RAZOR_ARROW), tostring(weapon and weapon[1]))
                assert.truthy(find(result.mail, SOLID_SHOT), tostring(weapon and weapon[1]))
            end
        end)
    end)

    describe("a hard keep", function()
        local function arrows(extra)
            local it = { itemID = RAZOR_ARROW, count = 200, stacks = 1, quality = 1, classID = 6, subclassID = 2,
                vendor = 0, ammo = true }
            for k, v in pairs(extra or {}) do it[k] = v end
            return it
        end

        it("beats a bank pin, a bank-here pin and a vendor pin", function()
            for _, pin in ipairs({ ns.Valuation.PIN_BANK, ns.Valuation.PIN_HERE, ns.Valuation.PIN_VENDOR }) do
                local r = ns.Valuation.Evaluate(arrows({ pin = pin, vendor = 1 }), { ah = 25, age = 0 }, ns.Valuation.DEFAULTS)
                assert.same({ action = "keep", reason = "ammo" }, r, pin)
            end
        end)

        it("is one no binding, pick or Return to sender overrides, and the window says why", function()
            assert.is_true(ns.Routes.HARD_KEEPS.ammo)
            assert.equal("ammo for your ranged weapon", ns.MailWindow.StayReason({ action = "keep", reason = "ammo" }))
        end)

        it("is checked again right before attaching: a bow equipped since the preview keeps its arrows", function()
            local stack = { bag = 0, slot = 1, itemID = RAZOR_ARROW, link = WowStub.link(RAZOR_ARROW, "Razor Arrow"), count = 200 }
            assert.is_true(ns.Mailer.StillThere(stack))
            equip("Hunting Bow", 2)
            assert.same({ false, "ammo" }, { ns.Mailer.StillThere(stack) })
        end)
    end)

    it("a bow equipped while the arrows sit attached: nothing is sent, the attachments come back (Codex review)", function()
        ns.Fire("MAIL_SHOW")
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.truthy(find(ns.MailWindow.Result().mail, RAZOR_ARROW), "no bow yet: the arrows are on the list")
        _G.MailworthyMailSend:Click()
        assert.is_true(#WowStub.state.attached > 0, "attached at the press")
        equip("Hunting Bow", 2)
        for _ = 1, 10 do
            WowStub.runTimers()
            if not ns.Mailer.Busy() then break end
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        assert.equal(0, #WowStub.state.sent, "a mail went with the bow's arrows in it")
        assert.equal(0, #WowStub.state.attached, "the attachments went back to the bags")
        assert.truthy(tostring(ns.Mailer.Status()):find("ammo for your ranged weapon", 1, true), tostring(ns.Mailer.Status()))
    end)

    it("/mw report says what the ranged slot holds and which ammo stays", function()
        assert.same({ "ammo (kept for the ranged weapon): nothing in the ranged slot; keeping none" }, ns.Ammo.ReportLines())
        equip("Rough Boomstick", 3)
        assert.same({ "ammo (kept for the ranged weapon): ranged slot item 9003, class 2 subclass 3; keeping bullets" },
            ns.Ammo.ReportLines())
    end)
end)
