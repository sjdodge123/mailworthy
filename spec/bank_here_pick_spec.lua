-- Here / Alt on a bank-here row (operator, 2026-11-21: "For the bank here vs bank alt items, i want the item
-- to still appear in the UI at the mailbox ... I want to be able to click a toggle between Here/Alt"; "can
-- this use the same ui interaction that the other toggle does, the me/friend/guild toggle? i want the ui to
-- be uniform"): what this character banks itself (its profession uses it, or a bank-here pin) names its own
-- rule "Here" on the row's pick button, and Alt, next, mails it to the bank alt this visit as a bank pin
-- would. Outcomes at the mailbox are in critical_path_spec; this is the rule, the labels and the tags.
local loadAddon = require("spec.support.load_addon")

describe("Here / Alt on a bank-here row", function()
    local ns
    local bar = { itemID = 2840, classID = 7, subclassID = 7, quality = 1, count = 10, stacks = 2, vendor = 10 }
    local craft = { action = "keep", kind = "profession", reason = "your Blacksmithing needs it", neededBy = "Blacksmithing" }

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
    end)

    describe("the rule (Routes)", function()
        it("a bank-here verdict: a profession's keep or a bank-here pin, nothing else", function()
            assert.is_true(ns.Routes.BankHere(craft))
            assert.is_true(ns.Routes.BankHere(ns.Valuation.Keep(ns.Valuation.K.pinHere, { pinned = true })))
            assert.is_false(ns.Routes.BankHere({ action = "mail", route = "bank", pinned = true }), "a BA pin already goes")
            assert.is_false(ns.Routes.BankHere({ action = "mail", route = "bank", craftBank = true, neededBy = "Blacksmithing" }),
                "materials on my bank alt already go")
            assert.is_false(ns.Routes.BankHere({ action = "keep", neededBy = "Lockpicking", ownSkill = true }),
                "a rogue's lockbox is picked here, not banked")
            assert.is_false(ns.Routes.BankHere({ action = "keep", neededBy = "Leatherworking", convert = { count = 5 } }),
                "one to convert is crafted now")
            assert.is_false(ns.Routes.BankHere(ns.Valuation.Keep(ns.Valuation.K.notWorth)))
            assert.is_false(ns.Routes.BankHere(nil))
        end)

        it("Alt is offered with a bank alt taking mail, never past a hard keep, a failed price call or unloaded data", function()
            assert.is_true(ns.Routes.AltOffered(bar, craft, { ah = 900, age = 0 }, {}))
            assert.is_true(ns.Routes.AltOffered(bar, craft, nil, {}), "no price source: like a bank pin")
            assert.is_false(ns.Routes.AltOffered(bar, craft, nil, { hold = "bank alt skipped" }))
            assert.is_false(ns.Routes.AltOffered(bar, craft, nil, { hold = "no bank alt" }))
            assert.is_false(ns.Routes.AltOffered(bar, craft, nil, { hold = "this is your bank alt" }))
            assert.is_false(ns.Routes.AltOffered(bar, craft, { failed = true }, {}))
            local failed = { action = "keep", neededBy = "Blacksmithing", failed = true }
            assert.is_false(ns.Routes.AltOffered(bar, failed, nil, {}))
            local unloaded = { itemID = 2840, count = 1, stacks = 1 }
            assert.is_false(ns.Routes.AltOffered(unloaded, craft, nil, {}), "item data first")
            for _, kind in ipairs({ "locked", "questItem", "conjured", "ammo", "soulbound", "tool", "inUse", "notLoaded" }) do
                assert.is_false(ns.Routes.AltOffered(bar, ns.Valuation.Keep(ns.Valuation.K[kind]), nil, {}), kind)
            end
            assert.is_false(ns.Routes.AltOffered(bar, { action = "mail", route = "ah" }, nil, {}), "not a bank-here row")
        end)

        it("Alt's verdict mails to the bank alt (no recipient of its own), with postage per stack", function()
            local v = ns.Routes.ToBankAlt(bar, { postage = 30 })
            assert.equal("mail", v.action)
            assert.equal("bank", v.route)
            assert.is_nil(v.to, "the bank alt, not a binding")
            assert.is_true(v.altPick)
            assert.equal(60, v.postage)
            assert.equal(100, v.vendor)
            assert.equal("b", ns.Valuation.Verdict({ result = v }, false), "the bag tag says BA")
        end)

        it("the cycle: Here, Alt, then each binding, and back; labels for each", function()
            local choices = { { key = "f", scope = "account" }, { key = "g", scope = "guild" } }
            assert.same({ ns.Routes.MINE, ns.Routes.ALT, "f", "g" }, ns.Routes.PickStates(choices, true))
            assert.equal(ns.Routes.ALT, ns.Routes.NextPick(ns.Routes.MINE, choices, true))
            assert.equal("f", ns.Routes.NextPick(ns.Routes.ALT, choices, true))
            assert.equal(ns.Routes.MINE, ns.Routes.NextPick("g", choices, true))
            assert.equal(ns.Routes.ALT, ns.Routes.NextPick(ns.Routes.MINE, {}, true), "Alt alone is a choice")
            assert.equal(ns.Routes.MINE, ns.Routes.NextPick(ns.Routes.ALT, {}, true))
            assert.is_nil(ns.Routes.NextPick(ns.Routes.MINE, {}, false), "nothing to pick between")
            assert.equal(ns.Routes.MINE, ns.Routes.NextPick(ns.Routes.ALT, choices, false), "Alt gone: back to the start")
            assert.equal("Here", ns.Routes.PickLabel(ns.Routes.MINE, choices, true))
            assert.equal("Me", ns.Routes.PickLabel(ns.Routes.MINE, choices, false))
            assert.equal("Alt", ns.Routes.PickLabel(ns.Routes.ALT, choices, true))
            assert.equal("Friend", ns.Routes.PickLabel("f", choices, true))
            assert.equal("Here", ns.Routes.PickLabel("gone", choices, true))
        end)
    end)

    describe("at the mailbox", function()
        local prices
        before_each(function()
            prices = {}
            _G.Auctionator = { API = { v1 = {
                GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
                GetAuctionAgeByItemLink = function() return 0 end,
            } } }
            WowStub.state.professions = { { index = 1, name = "Blacksmithing", rank = 50, maxRank = 150, skillLine = 164 } }
            WowStub.setBag(0, 1, WowStub.item(2840, "Copper Bar", { count = 10, sell = 10, class = 7, subclass = 7 }))
            prices[WowStub.link(2840, "Copper Bar")] = 900
            ns.Config.SetBankAlt("Roknua Themicrulah")
        end)
        after_each(function() _G.Auctionator = nil end)

        local function find(list, itemID)
            for _, it in ipairs(list) do
                if it.itemID == itemID then return it end
            end
            return nil
        end

        it("the row offers Alt; picked, it mails to the bank alt, and a send switch that is off doesn't hold it", function()
            local scan = ns.Bags.Evaluate()
            local item = find(scan.keep, 2840)
            assert.is_true(item.bankHere)
            assert.is_true(item.alt)
            ns.Routes.Pick(item.link, ns.Routes.ALT)
            scan = ns.Bags.Evaluate()
            item = find(scan.mail, 2840)
            assert.truthy(item, "Alt: on the Mailing list")
            assert.is_nil(item.result.to)
            assert.equal(ns.Routes.ALT, item.pickState)
            assert.is_true(item.result.picked)
            local s = ns.Bags.Settings()
            s[ns.Valuation.SEND.b] = false -- Send: Bank off
            assert.truthy(find(ns.Bags.Evaluate(s).mail, 2840), "the player's click: like a bank pin")
        end)

        it("the bag tag follows the pick: BH, then BA", function()
            local scan = ns.Bags.Evaluate(ns.Bags.Settings({ forTags = true }))
            assert.equal("craft", ns.Valuation.Verdict(find(scan.keep, 2840), false))
            ns.Routes.Pick(WowStub.link(2840, "Copper Bar"), ns.Routes.ALT)
            scan = ns.Bags.Evaluate(ns.Bags.Settings({ forTags = true }))
            assert.equal("b", ns.Valuation.Verdict(find(scan.mail, 2840), false))
        end)

        it("an Alt pick is dropped while the bank alt is skipped, and back when the skip is undone", function()
            ns.Routes.Pick(WowStub.link(2840, "Copper Bar"), ns.Routes.ALT)
            ns.Bags.SkipBankAlt(true)
            local scan = ns.Bags.Evaluate()
            local item = find(scan.keep, 2840)
            assert.truthy(item)
            assert.is_nil(item.alt)
            assert.is_nil(item.result.picked)
            ns.Bags.SkipBankAlt(false)
            assert.truthy(find(ns.Bags.Evaluate().mail, 2840))
        end)

        it("the pick button's tooltip names Here and Alt", function()
            local item = find(ns.Bags.Evaluate().keep, 2840)
            local lines = ns.MailWindow.PickLines(item, false, false)
            assert.equal("Where this goes, for this visit", lines[1])
            assert.equal("> Here: it stays, to bank on this character", lines[2])
            assert.equal("   Alt: to Roknua (your bank alt)", lines[3])
            assert.equal("Click: Alt (to Roknua). Cleared when the mailbox closes.", lines[4])
            assert.is_true(ns.MailWindow.HasPick(item))
            assert.is_false(ns.MailWindow.HasPick({ choices = {} }))
        end)
    end)
end)
