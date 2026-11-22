-- Button labels stay inside their borders (2026-11-07: "button text commonly runs over the button
-- borders"), the mailbox window's binding rows name the recipient's skill, and the settings' Guild
-- button says where the guild rules stand.
local loadAddon = require("spec.support.load_addon")

describe("widgets and labels", function()
    local ns

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
    end)

    it("FitFont: the normal font when it fits, the small one when not, cut only when even that doesn't", function()
        local W = ns.Widgets
        assert.same({ 1, false }, { W.FitFont(182, 150) })
        assert.same({ 1, false }, { W.FitFont(182, 166) }, "exactly the room inside the border")
        assert.same({ 2, false }, { W.FitFont(182, 200, 160) })
        assert.same({ 2, true }, { W.FitFont(182, 260, 220) })
        assert.same({ 1, false }, { W.FitFont(182, nil) }, "can't measure: left as it is")
    end)

    it("a button's label switches to the small font after SetText when it runs over, and back", function()
        local widths = { GameFontNormal = 7, GameFontNormalSmall = 5 } -- pixels per character
        local font = "GameFontNormal"
        _G.GameFontNormal, _G.GameFontNormalSmall = { name = "GameFontNormal" }, { name = "GameFontNormalSmall" }
        local cut
        local fs = {
            GetUnboundedStringWidth = function() return #ns.Widgets.lastText * widths[font] end,
            SetWidth = function(_, w) cut = w > 0 and w or nil end,
        }
        local b = ns.Widgets.Button(_G.UIParent, "", 182, function() end, "MailworthyTestButton")
        rawset(b, "GetFontString", function() return fs end)
        rawset(b, "GetWidth", function() return 182 end)
        rawset(b, "SetNormalFontObject", function(_, f) font = f.name end)
        local function set(text)
            ns.Widgets.lastText = text
            b:SetText(text)
        end
        set("Friends...")
        assert.equal("GameFontNormal", font)
        set(string.rep("x", 30)) -- 210 normal, 150 small
        assert.equal("GameFontNormalSmall", font)
        assert.is_nil(cut)
        set(string.rep("x", 40)) -- 200 small: cut at the border
        assert.equal(166, cut)
        set("Done")
        assert.equal("GameFontNormal", font)
        assert.is_nil(cut)
        _G.GameFontNormal, _G.GameFontNormalSmall = nil, nil
    end)

    it("a binding row names the recipient's skill and the guild", function()
        assert.equal(" |cff888888(guild, skill 120)|r", ns.MailWindow.RouteTags(true, 120))
        assert.equal(" |cff888888(skill 40)|r", ns.MailWindow.RouteTags(false, 40))
        assert.equal(" |cff888888(guild)|r", ns.MailWindow.RouteTags(true, nil))
        assert.equal("", ns.MailWindow.RouteTags(false, nil))
    end)

    it("Send holds when a fresh scan sends an item somewhere the list didn't show (Codex review)", function()
        local function mail(itemID, to) return { itemID = itemID, result = { to = to } } end
        local changed = ns.MailWindow.Changed
        assert.same({}, changed({ mail(1, "Smith"), mail(2) }, { mail(1, "Smith"), mail(2) }, "Bank"))
        assert.same({}, changed({ mail(1, "Smith") }, { mail(1, "Smith"), mail(9) }, "Bank"), "new item, bank alt")
        assert.same({}, changed({ mail(1, "Smith") }, { mail(9, "Smith") }, "Bank"), "new item, a shown friend")
        assert.same({}, changed({ mail(1, "Smith"), mail(2) }, { mail(2) }, "Bank"), "an item gone: fewer mails")
        local c = changed({ mail(1, "Smith") }, { mail(1, "Jold") }, "Bank")
        assert.equal(1, #c)
        assert.equal("Smith", c[1].was)
        assert.equal("Jold", c[1].to)
        assert.equal(1, #changed({ mail(1, "Smith") }, { mail(1) }, "Bank"), "a friend's item now to the bank alt")
        assert.equal(1, #changed({ mail(1, "Smith") }, { mail(9, "Ann") }, "Bank"), "a new item to someone unseen")
        -- Codex re-review: the bank alt changed in Settings beside the list; one item ID, two items
        assert.equal(1, #changed({ mail(1) }, { mail(1) }, "Old Bank", "New Bank"), "the bank alt changed after the preview")
        assert.equal(1, #changed({ mail(1, "Smith") }, { mail(9) }, "Old Bank", "New Bank"), "a new item to the new bank alt")
        local function green(link, to) return { itemID = 15210, link = link, result = { to = to } } end
        local list = { green("[Raider Shortsword of the Tiger]"), green("[Raider Shortsword of the Monkey]", "Bob") }
        assert.same({}, changed(list, list, "Bank"), "two suffixes of one item ID, two recipients: unchanged")
        -- Codex review, 2026-11-08: an item the list showed under Staying, now in the mail.
        local c2 = changed({}, { mail(1081) }, "Bank", "Bank", { mail(1081) })
        assert.equal(1, #c2)
        assert.equal("Staying", c2[1].was)
        assert.equal(1, #changed(list, { green("[Raider Shortsword of the Tiger]", "Bob"),
            green("[Raider Shortsword of the Monkey]", "Bob") }, "Bank"))
        -- Codex review, 2026-11-08: Return to sender splits one item by stacks; restacked between the
        -- preview and Send, the same two recipients would get other amounts.
        local function cloth(n, to) return { itemID = 2592, link = "[Wool Cloth]", count = n, result = { to = to } } end
        local shownSplit = { cloth(20, "Bob"), cloth(10) }
        assert.same({}, changed(shownSplit, { cloth(20, "Bob"), cloth(10) }, "Bank"))
        local c3 = changed(shownSplit, { cloth(15, "Bob"), cloth(15) }, "Bank")
        assert.equal(2, #c3)
        assert.equal("Bob", c3[1].to)
        assert.equal(15, c3[1].count)
        assert.equal(20, c3[1].wasCount)
    end)

    describe("two presses (Widgets.ConfirmButton; UX review U7)", function()
        local W, b, done
        before_each(function()
            W = ns.Widgets
            done = 0
            b = W.ConfirmButton(ns.RoutesUI.Frame(), "Remove", "Sure?", 80, function() done = done + 1 end,
                "MailworthyTestConfirm")
        end)

        it("the first press asks, the second within 3 seconds acts", function()
            b:Click()
            assert.equal(0, done)
            assert.equal("Sure?", b:GetText())
            assert.is_true(W.Armed(b))
            WowStub.state.now = WowStub.state.now + 2
            b:Click()
            assert.equal(1, done)
            assert.equal("Remove", b:GetText())
            assert.is_false(W.Armed(b))
        end)

        it("too late: the second press asks again; the timer puts the label back", function()
            b:Click()
            WowStub.state.now = WowStub.state.now + 4
            b:Click()
            assert.equal(0, done, "past 3 seconds: a new first press")
            assert.equal("Sure?", b:GetText())
            WowStub.runTimers(3)
            assert.equal("Remove", b:GetText())
            assert.is_false(W.Armed(b))
        end)

        it("the highlight moving to another button or the window closing cancels it", function()
            b:Click()
            ns.Nav.Select(_G.MailworthyFriendsDone)
            assert.is_false(W.Armed(b))
            assert.equal("Remove", b:GetText())
            b:Click()
            ns.Nav.Select(b) -- moving onto itself keeps it
            assert.is_true(W.Armed(b))
            ns.RoutesUI.Frame():Hide()
            assert.is_false(W.Armed(b))
            b:Click()
            b:Click()
            assert.equal(1, done)
        end)

        it("a new label waits until the button is not asking", function()
            b:Click()
            W.SetConfirmText(b, "Send again")
            assert.equal("Sure?", b:GetText())
            W.Disarm(b)
            assert.equal("Send again", b:GetText())
        end)
    end)

    it("the Mail routing list's guild line says where the guild rules stand", function()
        local text = ns.RoutesUI.GuildLineText
        assert.same({ "Switched off (/mw feature guildTemplate on).", nil }, { text(false, "Guildies", nil) })
        assert.same({ "Not in a guild.", nil }, { text(true, nil, nil) })
        assert.same({ "No guild template yet.", nil }, { text(true, "Guildies", nil) })
        assert.same({ "From Gm Name: 0 rules |cff33ff99(new)|r", "Use guild rules" },
            { text(true, "Guildies", { from = "Gm Name", rules = {} }) })
        assert.same({ "From Gm Name: 1 rule", "Guild rules: on" },
            { text(true, "Guildies", { from = "Gm Name", use = true, rules = { {} } }) })
        assert.same({ "From the mark: 2 rules", "Guild rules: off" },
            { text(true, "Guildies", { from = "Gm Name", use = false, rules = { {}, {} } }, "the mark") })
    end)
end)
