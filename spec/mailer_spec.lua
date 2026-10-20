-- Sending: one press mails everything to the saved bank alt in mails of 12
-- stacks, each slot re-checked right before attaching, money and COD zeroed,
-- the next mail chained on MAIL_SEND_SUCCESS; stops on failure, close, combat.
local loadAddon = require("spec.support.load_addon")

describe("mailer", function()
    local ns

    -- n different items, one stack each, priced well above vendor.
    local function fillBags(n)
        local prices = {}
        for i = 1, n do
            local bag, slot = math.floor((i - 1) / 20), (i - 1) % 20 + 1
            WowStub.state.numSlots[bag] = 20
            WowStub.setBag(bag, slot, WowStub.item(3000 + i, "Ore " .. i, { count = 5, sell = 5 }))
            prices[WowStub.link(3000 + i, "Ore " .. i)] = 500
        end
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end

    local function items() return ns.Bags.Evaluate().mail end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        MailFrame:Show()
        SendMailFrame:Show()
    end)
    after_each(function() _G.Auctionator = nil end)

    it("plans 12 stacks per mail", function()
        fillBags(14)
        local plan = ns.Mailer.Plan(items())
        assert.equal(2, #plan)
        assert.equal(12, #plan[1].stacks)
        assert.equal(2, #plan[2].stacks)
    end)

    it("one press sends every mail to the bank alt, chained on MAIL_SEND_SUCCESS, with no money", function()
        fillBags(14)
        WowStub.state.money = 12345 -- e.g. typed into the mail window earlier
        assert.is_true(ns.Mailer.Start(items(), ns.Config.BankAlt()))
        WowStub.runTimers()
        local sent = WowStub.state.sent
        assert.equal(1, #sent)
        assert.same({ name = "Roknua Themicrulah", subject = "Mailworthy 1/2", body = "", count = 12, money = 0, cod = 0 },
            sent[1])
        assert.same({ "cod 0", "money 0", "send" }, WowStub.state.moneyCalls)
        ns.Fire("MAIL_SEND_SUCCESS")
        WowStub.runTimers()
        assert.equal(2, #sent)
        assert.equal("Mailworthy 2/2", sent[2].subject)
        assert.equal(2, sent[2].count)
        ns.Fire("MAIL_SEND_SUCCESS")
        WowStub.runTimers()
        assert.is_false(ns.Mailer.Busy())
        assert.equal("Sent 2 mail(s), 14 stacks, to Roknua Themicrulah.", ns.Mailer.Status())
        local record = MailworthyDB.mailed[3001]
        assert.equal("ah", record.route)
        assert.is_nil(record.listRoute)
        assert.equal("Rettana Quilwrit", record.from)
        assert.equal("Roknua Themicrulah", record.to)
    end)

    it("a banked item's record keeps the route it would have been listed for", function()
        fillBags(1)
        local plan = items()
        plan[1].result.route, plan[1].result.listRoute = "bank", "ah"
        assert.is_true(ns.Mailer.Start(plan, ns.Config.BankAlt()))
        WowStub.runTimers()
        ns.Fire("MAIL_SEND_SUCCESS")
        WowStub.runTimers()
        local record = MailworthyDB.mailed[plan[1].itemID]
        assert.equal("bank", record.route)
        assert.equal("ah", record.listRoute)
    end)

    it("re-checks each slot right before attaching and skips anything that changed", function()
        fillBags(4)
        local plan = items()
        WowStub.state.bags[0][1].stackCount = 3                                  -- count changed
        WowStub.setBag(0, 2, WowStub.item(9999, "Something Else", { count = 5 })) -- a different item
        WowStub.state.bags[0][3].isBound = true                                   -- now bound
        ns.Locks.ToggleItem(3004, "link", "spec")                                 -- locked meanwhile
        ns.Mailer.Start(plan, ns.Config.BankAlt())
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent, "nothing left to attach: nothing sent")
        assert.equal(4, ns.Mailer.state.skipped)
        assert.is_false(ns.Mailer.Busy())
    end)

    it("won't start without a bank alt, on the bank alt, off the Send Mail tab, in combat or with nothing to mail", function()
        fillBags(2)
        local list = items()
        assert.is_false(ns.Mailer.Start(list, nil))
        assert.truthy(ns.Mailer.Status():find("no bank alt", 1, true))
        assert.is_false(ns.Mailer.Start(list, "rettana quilwrit"))
        assert.truthy(ns.Mailer.Status():find("this character is the bank alt", 1, true))
        SendMailFrame:Hide()
        assert.is_false(ns.Mailer.Start(list, "Roknua Themicrulah"))
        assert.truthy(ns.Mailer.Status():find("Send Mail tab", 1, true))
        SendMailFrame:Show()
        WowStub.state.inCombat = true
        assert.is_false(ns.Mailer.Start(list, "Roknua Themicrulah"))
        WowStub.state.inCombat = false
        assert.is_false(ns.Mailer.Start({}, "Roknua Themicrulah"))
        assert.equal(0, #WowStub.state.sent)
    end)

    it("stops on MAIL_FAILED and gives the attachments back", function()
        fillBags(14)
        ns.Mailer.Start(items(), ns.Config.BankAlt())
        WowStub.runTimers()
        ns.Fire("MAIL_FAILED")
        assert.is_false(ns.Mailer.Busy())
        assert.truthy(ns.Mailer.Status():find("MAIL_FAILED", 1, true))
        ns.Fire("MAIL_SEND_SUCCESS")
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent, "no second mail after a failure")
    end)

    it("stops when the mailbox closes, at combat, or with no answer in 10 s", function()
        fillBags(14)
        ns.Mailer.Start(items(), ns.Config.BankAlt())
        WowStub.runTimers()
        ns.Fire("MAIL_CLOSED")
        assert.is_false(ns.Mailer.Busy())

        ns.Mailer.Start(items(), ns.Config.BankAlt())
        ns.Fire("PLAYER_REGEN_DISABLED")
        assert.is_false(ns.Mailer.Busy())

        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent, "a stopped run's pending timer sends nothing")
        assert.equal(0, #WowStub.state.attached, "stopping gives the attachments back")

        ns.Mailer.Start(items(), ns.Config.BankAlt())
        WowStub.runTimers(10)
        assert.is_false(ns.Mailer.Busy())
        assert.truthy(ns.Mailer.Status():find("no answer", 1, true))
    end)

    it("forgets mail records after 30 days", function()
        MailworthyDB.mailed = { [1] = { at = 1000 }, [2] = { at = WowStub.state.serverTime } }
        ns.Mailer.Prune(WowStub.state.serverTime)
        assert.is_nil(MailworthyDB.mailed[1])
        assert.truthy(MailworthyDB.mailed[2])
    end)
end)
