-- Discovery self-test: candidates, attach test, chained send test, inbox checks,
-- answers, report, and the controller-joined window.
local loadAddon = require("spec.support.load_addon")

local function log() return table.concat(MailworthyDB.selftest.log, "\n") end
local function has(text, needle) assert.truthy(text:find(needle, 1, true), "missing: " .. needle .. "\n---\n" .. text) end

local function stockBags()
    WowStub.setBag(0, 1, WowStub.item(6948, "Hearthstone", { bound = true, noValue = true, sell = 0, class = 15 }))
    WowStub.setBag(0, 2, WowStub.item(159, "Refreshing Spring Water", { count = 11, sell = 1, class = 0 }))
    WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
    WowStub.setBag(0, 4, WowStub.item(2835, "Rough Stone", { count = 4, sell = 2 }))
    WowStub.setBag(0, 5, WowStub.item(2589, "Linen Cloth", { count = 6, sell = 13 }))
    WowStub.setBag(0, 6, WowStub.item(772, "Large Candle", { count = 7, bound = true, quest = true, class = 12 }))
    WowStub.setBag(1, 1, WowStub.item(6256, "Fishing Pole", { sell = 4, class = 2 }))
end

describe("self-test", function()
    local ns
    before_each(function()
        ns = loadAddon()
        stockBags()
        _G.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(caller, l)
            assert.equal("Mailworthy", caller)
            local prices = { ["Copper Ore"] = 293, ["Rough Stone"] = 8, ["Linen Cloth"] = 17, ["Fishing Pole"] = 900 }
            return prices[l:match("%[(.-)%]")]
        end } } }
        ns.Fire("PLAYER_LOGIN")
    end)

    describe("candidates", function()
        it("picks the two cheapest tradeable, unlocked, non-consumable stacks", function()
            local c = ns.SelfTest.Candidates()
            assert.equal(2835, c[1].itemID) -- Rough Stone 4 x 8 = 32
            assert.equal(2589, c[2].itemID) -- Linen Cloth 6 x 17 = 102
        end)

        it("falls back to the vendor price when Auctionator returns nothing (alpha1 crash)", function()
            Auctionator.API.v1.GetAuctionPriceByItemLink = function() end
            local c = ns.SelfTest.Candidates()
            assert.equal(6256, c[1].itemID) -- Fishing Pole 1 x 4
            assert.equal(2835, c[2].itemID) -- Rough Stone 4 x 2
        end)

        it("skips slots locked with Mailworthy", function()
            ns.Locks.Toggle(0, 4)
            local c = ns.SelfTest.Candidates()
            assert.equal(2589, c[1].itemID)
            assert.equal(6256, c[2].itemID) -- Fishing Pole 900 (Copper Ore is 5 x 293)
        end)
    end)

    describe("attach test", function()
        it("needs the Send Mail tab open", function()
            ns.SelfTest.RunAttach()
            assert.equal(0, #WowStub.state.attached)
            has(ns.SelfTest.state.status, "switch to the Send Mail tab")
        end)

        it("attaches on the press and from a timer, reads postage, then clears", function()
            SendMailFrame:Show()
            ns.SelfTest.RunAttach()
            assert.equal(1, #WowStub.state.attached)
            WowStub.runTimers()
            assert.equal(2, #WowStub.state.attached)
            local r = MailworthyDB.selftest.results.attach
            assert.same({ 30, 30, 60, 1, 2 }, { r.p0, r.p1, r.p2, r.n1, r.n2 })
            has(log(), "from a timer (no button press): called")
            ns.SelfTest.RunClear()
            WowStub.runTimers()
            assert.equal(0, #WowStub.state.attached)
            has(log(), "after ClearSendMail: 0 still attached")
            has(log(), "[Rough Stone]|h|r back yes")
            assert.equal(0, #WowStub.state.used, "nothing was used or eaten")
        end)

        it("falls back to pick up + drop when the timer attach doesn't take", function()
            SendMailFrame:Show()
            local use = C_Container.UseContainerItem
            local calls = 0
            C_Container.UseContainerItem = function(...) calls = calls + 1 if calls == 1 then use(...) end end
            ns.SelfTest.RunAttach()
            WowStub.runTimers()
            C_Container.UseContainerItem = use
            assert.equal(2, #WowStub.state.attached)
            has(log(), "fallback from a timer: PickupContainerItem ok, ClickSendMailItemButton ok -> 2 attached")
        end)

        it("refuses in combat", function()
            SendMailFrame:Show()
            WowStub.state.inCombat = true
            ns.SelfTest.RunAttach()
            assert.equal(0, #WowStub.state.attached)
        end)
    end)

    describe("send test", function()
        before_each(function()
            MailworthyDB.characters[ns.Characters.Key("Zed Banker", "Classic Beta PvP", "Alliance")] =
                { name = "Zed Banker", realm = "Classic Beta PvP", faction = "Alliance" }
            SendMailFrame:Show()
        end)

        it("needs a recipient picked from known characters", function()
            ns.SelfTest.SendPress()
            has(ns.SelfTest.state.status, "choose the recipient first")
            ns.SelfTest.CycleRecipient()
            assert.equal("Zed Banker", MailworthyDB.selftest.recipient)
        end)

        it("arms on the first press, sends on the second, and chains mail 2 after success", function()
            ns.SelfTest.CycleRecipient()
            ns.SelfTest.SendPress()
            assert.equal(1, #WowStub.state.attached)
            assert.equal(0, #WowStub.state.sent, "the first press only attaches")
            ns.SelfTest.SendPress()
            assert.same({ name = "Zed Banker", subject = "Mailworthy test 1/2", body = "", count = 1 }, WowStub.state.sent[1])
            ns.Fire("MAIL_SEND_SUCCESS")
            WowStub.runTimers()
            assert.same({ name = "Zed Banker", subject = "Mailworthy test 2/2", body = "", count = 1 }, WowStub.state.sent[2])
            ns.Fire("MAIL_SEND_SUCCESS")
            assert.is_false(ns.SelfTest.state.busy)
            has(log(), "mail 2 to \"Zed Banker\" from a timer (no button press): 1 attached, postage 30")
            has(ns.SelfTest.state.status, "both mails went out")
            assert.equal(1791900000, MailworthyDB.selftest.sent.at)
        end)

        it("stops and logs on MAIL_FAILED", function()
            ns.SelfTest.CycleRecipient()
            ns.SelfTest.SendPress()
            ns.SelfTest.SendPress()
            ns.Fire("MAIL_FAILED", 12, "Mail failed")
            assert.is_false(ns.SelfTest.state.busy)
            has(log(), "MAIL_FAILED during mail 1: 12, Mail failed")
            assert.equal(1, #WowStub.state.sent)
        end)

        it("times out if the game never answers", function()
            ns.SelfTest.CycleRecipient()
            ns.SelfTest.SendPress()
            ns.SelfTest.SendPress()
            WowStub.runTimers(60)
            has(log(), "no MAIL_SEND_SUCCESS or MAIL_FAILED within 10s for mail 1")
        end)
    end)

    describe("inbox", function()
        it("logs arriving test mails and AH invoices without the other player's name", function()
            MailworthyDB.selftest.sent = { at = 1791899940 }
            WowStub.state.inbox = { { sender = "Rettana Quilwrit", subject = "Mailworthy test 1/2", daysLeft = 30 } }
            WowStub.state.invoices = { [1] = { type = "seller", item = "Copper Ore", player = "Buyer Person", bid = 1000,
                buyout = 1000, deposit = 15, cut = 50, count = 5 } }
            ns.Fire("MAIL_SHOW")
            ns.Fire("MAIL_INBOX_UPDATE")
            ns.Fire("MAIL_INBOX_UPDATE")
            local text = log()
            has(text, 'found "Mailworthy test 1/2" from Rettana Quilwrit, has item 1, days left 30; 60 s after')
            has(text, 'seller "Copper Ore" x5: bid 1000, buyout 1000, deposit 15, house cut 50 (5.00%)')
            assert.falsy(text:find("Buyer Person", 1, true))
            local _, count = text:gsub("found \"Mailworthy test", "")
            assert.equal(1, count, "each mail is logged once per mailbox visit")
        end)
    end)

    describe("window and report", function()
        it("opens beside the mail window as its child at a mailbox, on its own elsewhere", function()
            MailFrame:Show()
            ns.SelfTest.Open("test")
            assert.equal(MailFrame, ns.SelfTestUI.Frame().parent)
            MailFrame:Hide()
            ns.SelfTest.Open("test")
            assert.equal(UIParent, ns.SelfTestUI.Frame().parent)
            assert.equal(0, WowStub.focusCalls)
        end)

        it("records Yes/No answers from the window's buttons", function()
            ns.SelfTest.Open("test")
            _G.MailworthySelfTestYes1:Click()
            _G.MailworthySelfTestNo3:Click()
            assert.equal("yes", MailworthyDB.selftest.answers.no_blocks.value)
            assert.equal("no", MailworthyDB.selftest.answers.unlock_entry.value)
        end)

        it("reports controller style, API presence, characters, answers and the log", function()
            ns.SelfTest.Answer("glyphs", "yes")
            local text = ns.SelfTest.Report()
            has(text, "controller: labelStyle=Shapes")
            has(text, "Triangle glyph=[Triangle/Y]")
            has(text, "api: Menu.ModifyMenu=function")
            has(text, "known character: Rettana Quilwrit (Classic Beta PvP, Alliance) PALADIN level 8")
            has(text, "answer glyphs: yes by Rettana Quilwrit")
            has(text, "answer mail_arrived: not answered")
            has(text, "Menu.ModifyMenu(\"MORE_CONTEXT_ACTIONS\") installed")
            ns.SelfTest.ShowReport()
            assert.equal(text:gsub("%d%d:%d%d", ""), (ns.SelfTestUI.ReportText():gsub("%d%d:%d%d", "")))
            assert.equal(0, WowStub.focusCalls)
        end)
    end)
end)
