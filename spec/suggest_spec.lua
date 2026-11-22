-- Suggested bindings (docs/RECOMMENDATIONS.md; operator, 2026-11-22): crafters in the group and the
-- account's own characters (Routes.Suggestions), the short-lived bindings they offer (Routes.AddTemp:
-- "While grouped", "This visit"), the block in the mailbox window (MailSuggestions.lua: one line or a
-- list, fold, Not now, More, lit rows) and the chat line away from the mailbox (Suggest.lua).
local loadAddon = require("spec.support.load_addon")

describe("suggested bindings", function()
    local ns, prices
    local GRACE, DORN, BRANN, SADIE = "Grace Thorn", "Dorn Ashby", "Brann Oakes", "Sadie Ember"
    local TAILORING, BLACKSMITHING = 197, 164

    local function text(name) return tostring(_G[name] and _G[name].text) end
    local function shown(name) return _G[name] ~= nil and _G[name]:IsShown() end
    local function character(name, professions)
        MailworthyDB.characters[ns.Characters.Key(name, "Classic Beta PvP", "Alliance")] = {
            name = name, realm = "Classic Beta PvP", faction = "Alliance", class = "MAGE", level = 30,
            professions = professions,
        }
    end
    local function names(list)
        local out = {}
        for _, s in ipairs(list) do out[#out + 1] = s.name .. ":" .. s.profession .. ":" .. s.scope end
        return out
    end
    local function suggestions() return ns.Routes.Suggestions(ns.Bags.Evaluate(), ns.Config.BankAlt()) end
    local function toOf(itemID)
        for _, item in ipairs(ns.MailWindow.Result().mail) do
            if item.itemID == itemID then return item.result.to or "bank alt" end
        end
        return nil
    end
    local function enter(button) for _, fn in ipairs(button.hooks.OnEnter or {}) do fn(button) end end
    local function leave(button) for _, fn in ipairs(button.hooks.OnLeave or {}) do fn(button) end end

    before_each(function()
        ns = loadAddon()
        ns.Valuation.DEFAULTS.minGain = 500
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }))
        prices[WowStub.link(2770, "Copper Ore")] = 174
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10, class = 7, subclass = 5 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 40
        -- Grace: a guild member in the party (her Tailoring from the roster); Brann: a guild member who isn't;
        -- Dorn: in the party, not in the guild, his Mailworthy said Blacksmithing.
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = GRACE, level = 26, online = true, professions = { TAILORING }, ranks = { 60 } },
            { name = BRANN, level = 30, online = true, professions = { BLACKSMITHING }, ranks = { 50 } },
        } }
        WowStub.state.group = { members = { { name = GRACE, online = true }, { name = DORN, online = true } } }
        ns.Comms.UpdatePeer(DORN, { name = DORN, professions = { BLACKSMITHING } }, true)
        MailFrame:Show()
        SendMailFrame:Show()
    end)
    after_each(function()
        _G.Auctionator = nil
        ns.Routes.ClearTemp()
        assert.equal(0, WowStub.focusCalls)
    end)

    describe("who is suggested (Routes.Suggestions)", function()
        it("the party (a guild member of it first), then the alts; never a guild member outside the group", function()
            character(SADIE, { { name = "Blacksmithing", skillLine = BLACKSMITHING, rank = 40 } })
            assert.same({ GRACE .. ":197:group", DORN .. ":164:group", SADIE .. ":164:visit" }, names(suggestions()))
            local grace = suggestions()[1]
            assert.is_true(grace.party)
            assert.is_true(grace.sources.guild)
            assert.equal(1, grace.count)
            assert.equal(2589, grace.items[1].itemID)
            assert.equal(60, grace.skill, "the roster's rank")
        end)

        it("never this character's own profession, a profession already bound, the bank alt, or a dismissed pair", function()
            WowStub.state.professions[1] = { index = 5, name = "Tailoring", rank = 20, maxRank = 75, skillLine = TAILORING }
            assert.same({ DORN .. ":164:group" }, names(suggestions()), "a tailor keeps its cloth: me first")
            WowStub.state.professions[1] = nil
            ns.Routes.Add("Bob Surname", BLACKSMITHING)
            assert.same({ GRACE .. ":197:group" }, names(suggestions()), "Blacksmithing is bound already")
            ns.Routes.DismissOffer(GRACE, TAILORING)
            assert.same({}, names(suggestions()))
            ns.Config.SetBankAlt(GRACE)
            ns.Routes.Remove(ns.Routes.List()[1].key)
            assert.same({ DORN .. ":164:group" }, names(suggestions()), "the bank alt is never suggested")
        end)

        it("nothing when not grouped and no alt crafts", function()
            WowStub.state.group = nil
            assert.same({}, names(suggestions()))
        end)
    end)

    describe("short-lived bindings (Routes.AddTemp)", function()
        it("While grouped: only for a group member, and it ends when they leave the group", function()
            assert.is_nil((ns.Routes.AddTemp(BRANN, BLACKSMITHING, "group")), "Brann isn't in the group")
            local r = ns.Routes.AddTemp(GRACE, TAILORING, "group")
            assert.equal("group", r.scope)
            assert.is_nil((ns.Routes.AddTemp(GRACE, TAILORING, "group")), "already bound")
            assert.equal("group", ns.Routes.List()[1].scope)
            ns.Fire("MAIL_CLOSED")
            assert.equal(1, #ns.Routes.Temp(), "a mailbox closing doesn't end it")
            WowStub.state.group = { members = { { name = DORN, online = true } } }
            ns.Fire("GROUP_ROSTER_UPDATE")
            assert.equal(0, #ns.Routes.Temp(), "Grace left the group")
            assert.equal(0, ns.Routes.Count())
        end)

        it("This visit: until the mailbox closes; never this character; Bind replaces it; Remove ends it", function()
            character(SADIE, { { name = "Blacksmithing", skillLine = BLACKSMITHING, rank = 40 } })
            assert.is_nil((ns.Routes.AddTemp(ns.PlayerName(), BLACKSMITHING, "visit")))
            assert.is_nil((ns.Routes.AddTemp(SADIE, BLACKSMITHING, "account")), "not a short-lived scope")
            assert.truthy(ns.Routes.AddTemp(SADIE, BLACKSMITHING, "visit"))
            ns.Fire("MAIL_CLOSED")
            assert.equal(0, #ns.Routes.Temp())
            local r = ns.Routes.AddTemp(SADIE, BLACKSMITHING, "visit")
            assert.truthy(ns.Routes.Remove(r.key))
            assert.equal(0, #ns.Routes.Temp())
            ns.Routes.AddTemp(SADIE, BLACKSMITHING, "visit")
            assert.truthy(ns.Routes.Add(SADIE, BLACKSMITHING))
            assert.equal(0, #ns.Routes.Temp(), "bound for good: the short-lived one goes")
            assert.equal("account", ns.Routes.List()[1].scope)
        end)

        it("a Bind that fails (too many bindings) leaves the short-lived one in place (Codex review)", function()
            ns.Routes.AddTemp(GRACE, TAILORING, "group")
            for i = 1, ns.Routes.MAX do ns.Routes.Add("Friend Number" .. i, "MAGE") end
            local r, why = ns.Routes.Add(GRACE, TAILORING)
            assert.is_nil(r)
            assert.equal("too many bindings", why)
            assert.equal(1, #ns.Routes.Temp(), "still bound while grouped")
        end)

        it("one guild roster read for every candidate (Codex review: a raid read it once per crafter)", function()
            local info, calls = _G.C_Club.GetMemberInfo, 0
            _G.C_Club.GetMemberInfo = function(...) calls = calls + 1; return info(...) end
            suggestions()
            _G.C_Club.GetMemberInfo = info
            assert.is_true(calls <= 2 * #WowStub.state.guild.members, calls .. " member reads")
        end)

        it("takes the item like any binding: under the cap, never a hard keep", function()
            ns.Routes.AddTemp(GRACE, TAILORING, "group")
            local scan = ns.Bags.Evaluate()
            for _, item in ipairs(scan.mail) do
                if item.itemID == 2589 then assert.equal(GRACE, item.result.to) end
            end
            ns.Locks.ToggleItem(2589, WowStub.link(2589, "Linen Cloth"), "spec")
            for _, item in ipairs(ns.Bags.Evaluate().mail) do assert.are_not.equal(2589, item.itemID, "locked: it stays") end
        end)
    end)

    describe("words (pure)", function()
        it("a party member's line names the items; an alt's keeps the offer's words; no price anywhere", function()
            local line = ns.MailWindow.OfferText({ name = GRACE, profession = TAILORING, skill = 60, party = true,
                sources = { party = true, guild = true }, count = 2,
                items = { { link = WowStub.link(2589, "Linen Cloth"), count = 20 },
                    { link = WowStub.link(2592, "Wool Cloth"), count = 40 } } })
            assert.equal("|cffffd100Grace Thorn|r |cff888888(party, guild)|r is a tailor in your group (skill 60)."
                .. " Send them Linen Cloth x20 and Wool Cloth x40?", line)
            assert.is_nil(line:find("|cffffffff%d"), "no money in it")
            assert.equal("A x2, B and 2 more", ns.Suggest.ItemsText({ { link = "[A]", count = 2 }, { link = "[B]", count = 1 },
                { link = "[C]" }, { link = "[D]" } }))
            assert.equal("Dorn Ashby is in your group: their Blacksmithing could use your Copper Ore x20 at your next mailbox.",
                ns.Suggest.JoinText({ name = DORN, profession = BLACKSMITHING,
                    items = { { link = WowStub.link(2770, "Copper Ore"), count = 20 } } }))
            local order, any = ns.Suggest.Order({ { n = 1 }, { n = 2, new = true }, { n = 3 } }, function(s) return s.new end)
            assert.same({ 2, 1, 3 }, { order[1].n, order[2].n, order[3].n })
            assert.is_true(any)
        end)
    end)

    describe("the mailbox window", function()
        it("one suggestion: the one-line offer with While grouped, Bind, Not for, Not now; no heading", function()
            WowStub.state.group = { members = { { name = GRACE, online = true } } }
            _G.MailworthyMailButton:Click()
            assert.equal(1, #ns.MailWindow.Suggestions())
            assert.is_true(shown("MailworthyMailOfferVisit"))
            assert.equal("While grouped", text("MailworthyMailOfferVisit"))
            assert.equal("Not for Grace", text("MailworthyMailOfferNot"))
            assert.is_true(shown("MailworthyMailSuggestNotNow"))
            assert.is_false(shown("MailworthyMailSuggestFold"), "no heading for one")
            assert.are_not.equal(GRACE, toOf(2589), "suggested only: the cloth stays (not worth the AH)")
            _G.MailworthyMailOfferVisit:Click()
            assert.equal(GRACE, toOf(2589), "the cloth goes to Grace, in the list before anything is sent")
            assert.truthy(ns.MailWindow.RouteLine(1):find("Tailoring", 1, true))
            assert.is_nil(ns.MailWindow.Offer(), "bound while grouped: no second suggestion for Tailoring")
        end)

        it("an alt's suggestion says This visit; the binding is gone at the next visit", function()
            WowStub.state.group = nil
            character(SADIE, { { name = "Blacksmithing", skillLine = BLACKSMITHING, rank = 40 } })
            _G.MailworthyMailButton:Click()
            assert.equal("This visit", text("MailworthyMailOfferVisit"))
            _G.MailworthyMailOfferVisit:Click()
            assert.equal(SADIE, toOf(2770))
            ns.Fire("MAIL_CLOSED")
            ns.Fire("MAIL_SHOW")
            ns.MailWindow.Refresh()
            assert.equal("bank alt", toOf(2770), "this visit is over")
            assert.truthy(ns.MailWindow.Offer(), "suggested again")
        end)

        it("several: a heading with Fold and Not now; Fold is remembered, and a new one opens it first", function()
            _G.MailworthyMailButton:Click()
            assert.equal(2, #ns.MailWindow.Suggestions())
            assert.is_true(shown("MailworthyMailSuggestFold"))
            assert.is_true(shown("MailworthyMailOfferVisit2"))
            assert.equal("Not for Dorn", text("MailworthyMailOfferNot2"))
            _G.MailworthyMailSuggestFold:Click()
            assert.is_true(ns.Suggest.Folded())
            assert.is_false(shown("MailworthyMailOfferVisit"))
            assert.is_true(shown("MailworthyMailSuggestFold"))
            ns.Fire("MAIL_CLOSED")
            ns.Fire("MAIL_SHOW")
            ns.MailWindow.Refresh()
            assert.is_false(shown("MailworthyMailOfferVisit"), "still folded at the next mailbox")
            character(SADIE, { { name = "Blacksmithing", skillLine = BLACKSMITHING, rank = 40 } })
            ns.MailWindow.Refresh()
            assert.is_false(ns.Suggest.Folded(), "Sadie is new: it opens")
            assert.equal(SADIE, ns.MailWindow.Suggestions()[1].name, "the new one first")
            assert.truthy(_G.MailworthyMailOfferVisit and ns.MailWindow.Suggestions()[1].new)
            assert.is_false(ns.MailWindow.Suggestions()[2].new == true, "Grace was seen when the block was folded")
        end)

        it("Not now hides it until the mailbox closes; Settings > Suggestions: off hides it for good", function()
            _G.MailworthyMailButton:Click()
            _G.MailworthyMailSuggestNotNow:Click()
            assert.is_nil(ns.MailWindow.Offer())
            assert.is_false(shown("MailworthyMailOfferVisit"))
            ns.Fire("MAIL_CLOSED")
            ns.Fire("MAIL_SHOW")
            ns.MailWindow.Refresh()
            assert.truthy(ns.MailWindow.Offer())
            ns.Config.Set("hideSuggestions", true)
            ns.MailWindow.Refresh()
            assert.is_nil(ns.MailWindow.Offer())
            assert.is_false(shown("MailworthyMailSuggestNotNow"))
        end)

        it("a short-lived binding's row shows first, so its Skip once and Remove are never behind \"+ N more\"", function()
            for i = 1, 3 do ns.Routes.Add("Friend Number" .. i, "MAGE") end
            WowStub.state.group = { members = { { name = GRACE, online = true } } }
            _G.MailworthyMailButton:Click()
            _G.MailworthyMailOfferVisit:Click()
            assert.truthy(ns.MailWindow.RouteLine(1):find("Grace", 1, true), ns.MailWindow.RouteLine(1))
            assert.is_true(_G.MailworthyMailUnbind1:IsShown())
            _G.MailworthyMailSkip1:Click()
            assert.are_not.equal(GRACE, toOf(2589), "skipped this visit")
        end)

        it("follows the group while the window is open (Codex review)", function()
            WowStub.state.group = { members = { { name = DORN, online = true } } }
            _G.MailworthyMailButton:Click()
            ns.Fire("MAIL_SHOW")
            assert.equal(DORN, ns.MailWindow.Offer().name)
            WowStub.state.group = { members = { { name = GRACE, online = true }, { name = DORN, online = true } } }
            ns.Fire("GROUP_ROSTER_UPDATE")
            assert.equal(GRACE, ns.MailWindow.Offer().name, "Grace joined: suggested at once")
        end)

        it("More pages past three", function()
            character(SADIE, { { name = "Blacksmithing", skillLine = BLACKSMITHING, rank = 40 } })
            character("Anna Bolt", { { name = "Tailoring", skillLine = TAILORING, rank = 30 } })
            _G.MailworthyMailButton:Click()
            assert.equal(4, #ns.MailWindow.Suggestions())
            assert.equal("More (1/2)", text("MailworthyMailSuggestMore"))
            _G.MailworthyMailSuggestMore:Click()
            assert.equal("More (2/2)", text("MailworthyMailSuggestMore"))
            assert.is_true(shown("MailworthyMailOfferVisit"))
            assert.is_false(shown("MailworthyMailOfferVisit2"))
        end)

        it("a suggestion's rows light up under the mouse and the controller's highlight", function()
            _G.MailworthyMailButton:Click()
            assert.is_false(ns.MailWindow.RowLit(2589))
            enter(_G.MailworthyMailOfferBind)
            assert.is_true(ns.MailWindow.RowLit(2589), "Grace's cloth")
            assert.is_false(ns.MailWindow.RowLit(2770))
            leave(_G.MailworthyMailOfferBind)
            assert.is_false(ns.MailWindow.RowLit(2589))
            ns.Nav.Select(_G.MailworthyMailOfferVisit2)
            assert.is_true(ns.MailWindow.RowLit(2770), "Dorn's ore")
            ns.Nav.Select(_G.MailworthyMailSend)
            assert.is_false(ns.MailWindow.RowLit(2770))
        end)

        it("Not for <name> is remembered; nothing while a send runs", function()
            _G.MailworthyMailButton:Click()
            _G.MailworthyMailOfferNot:Click()
            assert.is_true(ns.Routes.OfferDismissed(GRACE, TAILORING))
            assert.equal(DORN, ns.MailWindow.Offer().name)
            _G.MailworthyMailSend:Click()
            assert.is_true(ns.Mailer.Busy())
            assert.is_nil(ns.MailWindow.Offer())
            WowStub.runTimers()
        end)
    end)

    describe("the chat line away from the mailbox", function()
        local function said()
            local n = 0
            for _, line in ipairs(WowStub.printed) do if line:find("is in your group", 1, true) then n = n + 1 end end
            return n
        end
        before_each(function()
            MailFrame:Hide()
            SendMailFrame:Hide()
            ns.Suggest.Reset()
        end)

        it("once a session per crafter, after a group change; never in combat or at a mailbox", function()
            ns.Fire("GROUP_ROSTER_UPDATE")
            WowStub.runTimers(ns.Suggest.DELAY)
            assert.equal(2, said(), "Grace and Dorn")
            ns.Fire("GROUP_ROSTER_UPDATE")
            WowStub.state.group = { members = { { name = GRACE, online = true } } }
            ns.Fire("GROUP_ROSTER_UPDATE")
            WowStub.runTimers(ns.Suggest.DELAY)
            assert.equal(2, said(), "said once a session")
            ns.Suggest.Reset()
            WowStub.state.inCombat = true
            WowStub.state.group = { members = { { name = GRACE, online = true }, { name = DORN, online = true } } }
            ns.Fire("GROUP_ROSTER_UPDATE")
            WowStub.runTimers(ns.Suggest.DELAY)
            assert.equal(2, said(), "not in combat")
            WowStub.state.inCombat = false
            ns.Fire("PLAYER_REGEN_ENABLED")
            WowStub.runTimers(ns.Suggest.DELAY)
            assert.equal(4, said(), "after combat")
        end)

        it("not at a mailbox, nor with Suggestions off", function()
            ns.Fire("MAIL_SHOW")
            ns.Fire("GROUP_ROSTER_UPDATE")
            WowStub.runTimers(ns.Suggest.DELAY)
            assert.equal(0, said())
            ns.Fire("MAIL_CLOSED")
            ns.Config.Set("hideSuggestions", true)
            WowStub.state.group = { members = { { name = GRACE, online = true } } }
            ns.Fire("GROUP_ROSTER_UPDATE")
            WowStub.runTimers(ns.Suggest.DELAY)
            assert.equal(0, said())
        end)
    end)
end)
