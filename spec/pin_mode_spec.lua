-- Where pins bank (operator, 2026-11-13): BA (mailed to the bank alt) or BH (stays, to bank here), a
-- per-character setting that flips every pin; one colour per destination on the tag, the glow, the
-- window's chip and the tooltip (Palette); the warning when a BA pin takes what this character's
-- profession uses; tags that follow bindings and Return to sender; every tag after a Send, saved; and
-- "Keep my professions' materials" per character.
local loadAddon = require("spec.support.load_addon")

describe("pin mode and tags", function()
    local ns, combined, prices

    local function tagOf(button)
        for _, f in ipairs(button.fontStrings) do
            if f:IsShown() then return f.text end
        end
        return nil
    end

    before_each(function()
        ns = loadAddon()
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
            IsAuctionDataExactByItemLink = function() return true end,
        } } }
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        prices[WowStub.link(2770, "Copper Ore")] = 174
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 38
        combined = ContainerFrameCombinedBags
        combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2) }
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah") -- a main with a bank alt
    end)

    after_each(function() _G.Auctionator = nil end)

    describe("the pin mode", function()
        it("is BA by default, BH by the setting, and BH with no bank alt or on the bank alt itself", function()
            ns.Pins.Set(2770, "Copper Ore", ns.Pins.BANK, "spec")
            assert.equal(ns.Pins.BANK, ns.Pins.Mode())
            assert.equal(ns.Pins.BANK, ns.Pins.Effective(2770))
            assert.equal(ns.Palette.BA, ns.Pins.Palette(2770))
            assert.is_nil(ns.Pins.Effective(2589), "no pin")
            ns.Pins.SetMode(ns.Pins.HERE, "spec")
            assert.equal(ns.Pins.HERE, ns.Pins.Effective(2770))
            assert.equal(ns.Palette.BH, ns.Pins.Palette(2770))
            assert.equal("setting", ns.Pins.HereBecause())
            ns.Pins.SetMode(ns.Pins.BANK, "spec")
            MailworthyDB.bankAlts = {}
            assert.equal(ns.Pins.HERE, ns.Pins.Effective(2770))
            assert.equal("no bank alt", ns.Pins.HereBecause())
            ns.Config.SetBankAltHere()
            assert.equal("bank alt", ns.Pins.HereBecause())
        end)

        it("is saved per character: the pins stay the account's", function()
            ns.Pins.Set(2770, "Copper Ore", ns.Pins.BANK, "spec")
            ns.Pins.SetMode(ns.Pins.HERE, "spec")
            assert.equal("here", MailworthyCharDB.pinMode)
            assert.is_nil(MailworthyDB.pinMode)
            local db = MailworthyDB
            ns = loadAddon({ db = db, charDB = {} }) -- another character on the account
            ns.Fire("PLAYER_LOGIN")
            assert.equal(ns.Pins.BANK, ns.Pins.Mode())
            assert.equal("bank", ns.Pins.Kind(2770), "the pin itself is the account's")
        end)

        it("can't change while a send runs, from Settings or from the warning", function()
            local busy = ns.Mailer.Busy
            ns.Mailer.Busy = function() return true end
            assert.is_nil(ns.Pins.SetMode(ns.Pins.HERE, "spec"))
            assert.equal(ns.Pins.BANK, ns.Pins.Mode())
            ns.Pins.Set(2770, "Copper Ore", ns.Pins.BANK, "spec")
            ns.PinWarning.Show(2770, "Copper Ore", "Blacksmithing")
            _G.MailworthyPinWarningUnpin:Click()
            assert.equal("bank", ns.Pins.Kind(2770), "Unpin it waits for the send (Codex review)")
            ns.Mailer.Busy = busy
        end)

        it("a pin waits for the item's data, BH or BA: not even Return to sender takes it (Codex review)", function()
            for _, pin in ipairs({ ns.Valuation.PIN_HERE, ns.Valuation.PIN_BANK }) do
                local item = { link = "x", itemID = 1, count = 1, stacks = 1, quality = 1, vendor = nil, pin = pin }
                local r = ns.Valuation.Evaluate(item, { ah = 500, age = 0 }, ns.Valuation.Settings({}, false))
                assert.equal("item info not loaded yet", r.reason, pin)
                assert.is_true(ns.Routes.HARD_KEEPS[r.reason])
            end
        end)

        it("the Settings button flips it and says where pins go, in the tag's letters", function()
            ns.SettingsUI.Show()
            assert.truthy(_G.MailworthySettingsPins:GetText():find("BA|r mail to your bank alt", 1, true))
            _G.MailworthySettingsPins:Click()
            assert.equal(ns.Pins.HERE, ns.Pins.Mode())
            assert.truthy(_G.MailworthySettingsPins:GetText():find("BH|r bank here, on this character", 1, true))
            MailworthyDB.bankAlts = {}
            ns.SettingsUI.Refresh()
            assert.truthy(_G.MailworthySettingsPins:GetText():find("(no bank alt)", 1, true))
        end)

        it("a bank-here pin keeps the item, past the hard keeps, and is not a hard keep itself", function()
            local item = { link = "x", itemID = 1, count = 1, stacks = 1, quality = 1, vendor = 5, pin = ns.Valuation.PIN_HERE }
            local r = ns.Valuation.Evaluate(item, { ah = 500, age = 0 }, ns.Valuation.Settings({}, false))
            assert.equal("keep", r.action)
            assert.equal(ns.Valuation.PIN_HERE_REASON, r.reason)
            assert.is_true(r.pinned)
            assert.is_nil(ns.Routes.HARD_KEEPS[r.reason], "Return to sender still wins")
            item.bound = true
            assert.equal("soulbound", ns.Valuation.Evaluate(item, { ah = 500, age = 0 }, ns.Valuation.Settings({}, false)).reason)
        end)
    end)

    describe("the profession warning", function()
        before_each(function()
            WowStub.state.professions = { { index = 1, name = "Enchanting", rank = 60, maxRank = 150, skillLine = 333 } }
            WowStub.setBag(0, 3, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        end)

        it("shows when a BA pin takes what this character's profession uses, not for anything else", function()
            ns.Pins.Set(2770, WowStub.link(2770, "Copper Ore"), ns.Pins.BANK, "spec")
            assert.is_false(ns.PinWarning.Frame():IsShown(), "Enchanting doesn't use ore")
            ns.Pins.Set(10940, WowStub.link(10940, "Strange Dust"), ns.Pins.BANK, "spec")
            assert.is_true(ns.PinWarning.Frame():IsShown())
            assert.truthy(ns.PinWarning.Text():find("your Enchanting uses it", 1, true))
            assert.truthy(ns.PinWarning.Text():find("The pin wins", 1, true))
            local r = ns.Bags.Evaluate().mail
            local dust
            for _, it in ipairs(r) do if it.itemID == 10940 then dust = it end end
            assert.equal("Enchanting", dust.result.pinConflict, "the window and the tooltip say it every time")
            assert.truthy(ns.MailWindow.TooltipLines(dust, false, false, "Roknua Themicrulah", false)
                :find("Your Enchanting uses it, but the pin wins", 1, true))
        end)

        it("its buttons: unpin, bank pins here, don't show again (and /mw pinwarning on brings it back)", function()
            local link = WowStub.link(10940, "Strange Dust")
            ns.Pins.Set(10940, link, ns.Pins.BANK, "spec")
            _G.MailworthyPinWarningUnpin:Click()
            assert.is_nil(ns.Pins.Kind(10940))
            assert.is_false(ns.PinWarning.Frame():IsShown())
            ns.Pins.Set(10940, link, ns.Pins.BANK, "spec")
            _G.MailworthyPinWarningHere:Click()
            assert.equal(ns.Pins.HERE, ns.Pins.Mode())
            ns.Pins.SetMode(ns.Pins.BANK, "spec")
            ns.Pins.Set(10940, nil, nil, "spec")
            ns.Pins.Set(10940, link, ns.Pins.BANK, "spec")
            _G.MailworthyPinWarningHide:Click()
            assert.is_true(ns.Config.Flag("hidePinWarning"))
            ns.Pins.Set(10940, nil, nil, "spec")
            ns.Pins.Set(10940, link, ns.Pins.BANK, "spec")
            assert.is_false(ns.PinWarning.Frame():IsShown(), "not again")
            ns.HandleSlash("pinwarning on")
            assert.is_false(ns.Config.Flag("hidePinWarning"))
        end)

        it("no warning for a bank-here pin: it stays anyway", function()
            ns.Pins.SetMode(ns.Pins.HERE, "spec")
            ns.Pins.Set(10940, WowStub.link(10940, "Strange Dust"), ns.Pins.BANK, "spec")
            assert.is_false(ns.PinWarning.Frame():IsShown())
        end)
    end)

    describe("tags on a main", function()
        it("before any send: only pinned items, in their destination's tag; the legend lists only those", function()
            combined:UpdateItems()
            assert.is_nil(tagOf(combined.Items[1]))
            assert.equal("", ns.BankAlt.LegendText())
            ns.Pins.Set(2589, "Linen Cloth", ns.Pins.BANK, "spec")
            combined:UpdateItems()
            assert.is_nil(tagOf(combined.Items[1]), "not pinned: no tag before a send")
            assert.equal("BA", tagOf(combined.Items[2]), "a pin always shows its tag")
            assert.truthy(ns.BankAlt.LegendText():find("BA|r bank on alt", 1, true))
            assert.is_nil(ns.BankAlt.LegendText():find("AH|r", 1, true))
            ns.Pins.SetMode(ns.Pins.HERE, "spec")
            combined:UpdateItems()
            assert.equal("BH", tagOf(combined.Items[2]))
        end)

        it("a binding's item is F and, with Return to sender on, a returned item is R", function()
            MailworthyCharDB.tagsAfterSend = true -- a main that has sent
            WowStub.setBag(0, 3, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
            prices[WowStub.link(10940, "Strange Dust")] = 3
            combined.Items[3] = WowStub.itemButton(0, 3)
            ns.Routes.Add("Bob Surname", 333) -- Enchanting: the dust
            ns.BankAlt.Redraw()
            combined:UpdateItems()
            assert.equal("F", tagOf(combined.Items[3]), "a binding takes it: F, not the market's tag")
            assert.equal("AH", tagOf(combined.Items[1]), "the rest as the market says")
            assert.equal(ns.Palette.F, ns.BankAlt.Tag("friend"))
            assert.equal(ns.Palette.R, ns.BankAlt.Tag("return"))
            -- Return to sender switched on or off redraws the tags at once (Codex review).
            local redraws = 0
            local redraw = ns.BankAlt.Redraw
            ns.BankAlt.Redraw = function() redraws = redraws + 1 end
            ns.Returns.Set(true)
            ns.Returns.Set(false)
            ns.BankAlt.Redraw = redraw
            assert.equal(2, redraws)
            assert.equal("return", ns.BankAlt.Verdict({ result = { action = "mail", route = "return", to = "Bob" } }))
            local lines = ns.BankAlt.TooltipLines({ advice = "return", result = { action = "mail", route = "return", to = "Bob" } },
                nil, ns.BankAlt.Settings())
            assert.truthy(lines[2][1]:find("Goes back to Bob at the mailbox", 1, true))
            assert.same(ns.Palette.R.fg, { lines[2][2], lines[2][3], lines[2][4] })
        end)
    end)

    describe("the summary", function()
        it("counts pinned items on their own row, not as banked for a later phase", function()
            ns.Config.SetBankAltHere()
            ns.Pins.Set(2589, "Linen Cloth", ns.Pins.BANK, "spec")
            local s = ns.BankAlt.Summary(ns.BankAlt.Refresh())
            assert.equal(1, s.pin.stacks)
            assert.equal(0, s.b.stacks)
            assert.equal(0, s.v.stacks, "Linen Cloth is pinned, not vendored")
        end)

        it("its pinned row's chip follows the pin mode: BH on a main set to bank here (Codex review)", function()
            ns.Pins.Set(2589, "Linen Cloth", ns.Pins.BANK, "spec")
            ns.Pins.SetMode(ns.Pins.HERE, "spec")
            ns.BankAlt.ShowWindow()
            local found
            for _, f in ipairs(ns.BankAlt.Frame().fontStrings or {}) do
                if tostring(f.text):find("pinned", 1, true) then found = f.text end
            end
            if found then assert.equal("BH pinned", found) end
            assert.equal(ns.Palette.BH, ns.BankAlt.Tag(ns.Pins.HereBecause() and "here" or "b"))
        end)
    end)

    describe("profession materials, per character", function()
        it("a bank alt can sell what its own profession would keep while the account keeps it", function()
            WowStub.state.professions = { { index = 1, name = "Enchanting", rank = 60, maxRank = 150, skillLine = 333 } }
            local dust = { link = "d", itemID = 10940, count = 20, stacks = 1, quality = 1, vendor = 2, classID = 7,
                subclassID = 12 }
            local s = ns.Config.Values()
            s.professions = ns.Characters.Professions()
            assert.equal("keep", ns.Valuation.Evaluate(dust, { ah = 300, age = 0 }, s).action)
            ns.Config.Set("keepProfessionMats", false) -- this character only
            s = ns.Config.Values()
            s.professions = ns.Characters.Professions()
            s.serverDay = 90 -- past the "bank for later" days
            local r = ns.Valuation.Evaluate(dust, { ah = 300, age = 0 }, s)
            assert.equal("ah", r.route, "sold, not kept for its own Enchanting")
            assert.is_nil(MailworthyDB.settings.keepProfessionMats)
            ns = loadAddon({ db = MailworthyDB, charDB = {} }) -- another character
            assert.is_true(ns.Config.Values().keepProfessionMats)
        end)
    end)
end)
