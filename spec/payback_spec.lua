-- Paying back (phase 2 of docs/RECOMMENDATIONS.md; operator, 2026-11-22: "these paybacks should also work
-- with our value ledger system so that the 'debt' is slowly cleared"): the owed notice's meter (paid back so
-- far, and what this Send would pay), and Mark part paid (an amount, - / +, two presses) on the notice and in
-- the ledger window. Only this side ever shows.
local loadAddon = require("spec.support.load_addon")

local BOB = "Bob Surname"
local LINEN = { id = 2589, name = "Linen Cloth" }

describe("paying back", function()
    local ns, prices

    local function inboxMail(it, count)
        WowStub.state.inbox = { { sender = BOB, subject = "mats", daysLeft = 29.9,
            items = { { itemID = it.id, name = it.name, count = count } } } }
    end
    local function take(itemID)
        TakeInboxItem(1, 1)
        ns.Fire("MAIL_SUCCESS", itemID)
        WowStub.runTimers(2)
    end
    local function owes() return (ns.Ledger.Net(BOB)) end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
        prices[WowStub.link(LINEN.id, LINEN.name)] = 500 -- 20 = 1g
        MailFrame:Show()
        SendMailFrame:Show()
        ns.Fire("MAIL_SHOW")
        inboxMail(LINEN, 20)
        take(LINEN.id)
    end)
    after_each(function()
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        _G.Auctionator = nil
    end)

    describe("the ledger", function()
        it("the part amount: 20s to start, 5s steps, never past what's owed, at least a step", function()
            local step = ns.Ledger.StepPart
            assert.equal(2000, step(nil, nil, 10000))
            assert.equal(2500, step(2000, 1, 10000))
            assert.equal(1500, step(2000, -1, 10000))
            assert.equal(500, step(500, -1, 10000), "at least one step")
            assert.equal(10000, step(9800, 1, 10000), "never past what's owed")
            assert.equal(1200, step(nil, nil, 1200))
            assert.equal(2500, step(nil, 1, 10000), "a step from the default")
            assert.equal(300, step(nil, nil, 300), "owed under a step: all of it")
        end)

        it("Mark part paid lowers what's owed by the amount; at or over it, back to zero; logged", function()
            assert.equal(10000, owes())
            assert.is_true(ns.Ledger.MarkPaid(BOB, 2500))
            assert.equal(7500, owes())
            local paid, total = ns.Ledger.PaidBack(BOB)
            assert.equal(2500, paid)
            assert.equal(10000, total)
            assert.truthy(ns.Ledger.ExportText():find("MARKED PART PAID  Bob Surname: 25s paid another way by", 1, true))
            assert.truthy(ns.Ledger.ExportText():find("75s left", 1, true))
            assert.is_false(ns.Ledger.MarkPaid(BOB, 0))
            assert.is_true(ns.Ledger.MarkPaid(BOB, 9000))
            assert.equal(0, owes())
            assert.truthy(ns.Ledger.ExportText():find("MARKED PAID  Bob Surname: 75s set back to zero", 1, true))
            assert.is_false(ns.Ledger.MarkPaid(BOB, 500), "nothing owed")
            assert.same({}, ns.Ledger.Debts())
        end)

        it("what you mail them counts as paid back", function()
            WowStub.state.attached = { WowStub.item(LINEN.id, LINEN.name, { count = 8 }) }
            WowStub.state.money = 0
            ns.Fire("MAIL_SEND_INFO_UPDATE")
            SendMail(BOB, "back", "")
            ns.Fire("MAIL_SEND_SUCCESS")
            assert.equal(6000, owes())
            assert.equal(4000, (ns.Ledger.PaidBack(BOB)))
        end)
    end)

    describe("the owed notice", function()
        it("the meter's line, and what this Send would pay (pure)", function()
            assert.equal("Paid back 25s of 1g", ns.MailWindow.MeterText(2500, 10000, 0, 7500))
            assert.equal("Paid back 25s of 1g |cff8ee6b0· this Send pays 40s more, 35s left|r",
                ns.MailWindow.MeterText(2500, 10000, 4000, 7500))
            assert.truthy(ns.MailWindow.MeterText(0, 10000, 20000, 10000):find("pays 1g more, 0c left", 1, true),
                "never more than what's owed")
            local mail = {
                { link = "[A]", count = 2, result = { to = BOB } },
                { link = "[B]", count = 1, result = { to = "bob surname" } },
                { link = "[C]", count = 5, result = { to = "Someone Else" } },
                { link = "[D]", count = 3, result = {} }, -- the bank alt
                { link = "[E]", count = 4, result = { to = BOB } }, -- unpriced
            }
            local values = { ["[A]"] = 100, ["[B]"] = 50, ["[C]"] = 999, ["[D]"] = 999 }
            assert.equal(250, ns.MailWindow.SendShare(mail, BOB, function(n) return n end, function(l) return values[l] end))
        end)

        it("shows the meter with what a binding's mail would pay; Part paid takes two presses, - / + step it", function()
            ns.Routes.Add(BOB, 197) -- Bob's Tailoring takes the linen back
            WowStub.setBag(0, 1, WowStub.item(LINEN.id, LINEN.name, { count = 8, sell = 10, class = 7, subclass = 5 }))
            _G.MailworthyMailButton:Click()
            assert.is_true(_G.MailworthyMailPartPaid:IsShown())
            local who, amount = ns.MailWindow.OwedState()
            assert.equal(BOB, who)
            assert.equal(2000, amount)
            assert.equal("Part paid: 20s", _G.MailworthyMailPartPaid:GetText())
            _G.MailworthyMailPartMore:Click()
            assert.equal("Part paid: 25s", _G.MailworthyMailPartPaid:GetText())
            _G.MailworthyMailPartLess:Click()
            _G.MailworthyMailPartLess:Click()
            assert.equal("Part paid: 15s", _G.MailworthyMailPartPaid:GetText())
            _G.MailworthyMailPartPaid:Click()
            assert.equal(10000, owes(), "one press pays nothing")
            _G.MailworthyMailPartPaid:Click()
            assert.equal(8500, owes())
            assert.equal("Part paid: 20s", _G.MailworthyMailPartPaid:GetText(), "back to 20s for the next one")
        end)

        it("gone once nothing is owed", function()
            ns.Ledger.MarkPaid(BOB)
            _G.MailworthyMailButton:Click()
            assert.is_false(_G.MailworthyMailPartPaid:IsShown())
            assert.is_false(_G.MailworthyMailLedger:IsShown())
        end)
    end)

    describe("the ledger window", function()
        it("each row has Part paid (two presses) with - / +", function()
            ns.LedgerUI.Show()
            assert.equal("Part paid: 20s", _G.MailworthyLedgerPart1:GetText())
            _G.MailworthyLedgerPartMore1:Click()
            assert.equal("Part paid: 25s", _G.MailworthyLedgerPart1:GetText())
            _G.MailworthyLedgerPart1:Click()
            assert.equal("Sure?", _G.MailworthyLedgerPart1:GetText())
            assert.equal(10000, owes())
            _G.MailworthyLedgerPaid1:Click() -- Mark paid's first press cancels Part paid's
            assert.equal("Part paid: 25s", _G.MailworthyLedgerPart1:GetText())
            _G.MailworthyLedgerPart1:Click()
            _G.MailworthyLedgerPart1:Click()
            assert.equal(7500, owes())
            assert.equal("Part paid: 20s", _G.MailworthyLedgerPart1:GetText())
        end)
    end)
end)
