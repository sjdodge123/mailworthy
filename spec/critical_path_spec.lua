-- CRITICAL PATH: the shipping gate. Every build must still mail, safely, the way a
-- player does it: a mailbox visit with a realistic bag, the mouse (the Mailworthy button or
-- the Send Mail tab alone) and the controller,
-- with and without Auctionator, with TradeSkillMaster alone and with both, items with no auction
-- price yet (to the bank alt), with a binding (a profession's or a class's, recipes to their
-- profession's, a rogue's lockboxes and a mage's Comprehension scrolls to their class's), with a
-- guild template (its mail tagged in the log and counted for the guild
-- contributions, nobody else's, never mail to the player's own characters; guildmates' shared counts
-- change nothing mailed), without a bank alt or with it skipped for the visit, with
-- Return to sender (on a main and on the bank alt itself), with a hunter's ammo (the type the equipped
-- bow fires stays, pinned or mailed by someone else), and on SavedVariables an older build
-- left behind (an early alpha's, and v0.30.0's guild template with a full mail log). CI runs this
-- file on its own before the rest, and a tag can't publish unless it passes.
--
-- These tests check outcomes, not tuning: what was previewed is exactly what was sent,
-- to exactly the recipients shown, and the AGENTS.md safety rules hold for every mail.
-- The mail log (Ledger.lua, the record players export to show where items went) holds
-- exactly what was sent: one entry per mail, same recipient, same stacks.
-- Thresholds and prices are other specs' business. Don't loosen an assertion here to
-- make a change pass: a red test here means a player's mail would break.
local loadAddon = require("spec.support.load_addon")

local BANK_ALT = "Roknua Themicrulah"
local BOB = "Bob Surname"
local ENCHANTING = 333
local REALM_KEY = "Classic Beta PvP|Alliance"

-- Items that must never leave the bags whatever they're worth (AGENTS.md "Safety").
local HARD_KEEPS = {
    [6948] = "soulbound (Hearthstone)",
    [6125] = "soulbound green",
    [5022] = "quest item",
    [2775] = "locked by the player",
    [2901] = "profession tool",
    [4306] = "in use (locked by the game)",
    [1081] = "an active quest's objective (Crisp Spider Meat for Redridge Goulash)",
    [7976] = "locked by the player, no auction price (Plans: Locked Recipe)",
    [7977] = "soulbound, no auction price (Bound Recipe)",
    [5512] = "conjured (Minor Healthstone: white, no auction price; operator, 2026-11-10)",
    [3030] = "ammo for the equipped bow (Razor Arrow; the ammo cases equip one; operator, 2026-11-14)",
}

--- A level-20ish character's bags on a fresh realm: trade goods, a BoE green, junk,
--- a quest item, soulbound gear, a tool, a locked item, a conjured item, the reagent bag in use, and
--- enough priced stacks for two mails. Returns the Auctionator price table.
local function fillBags()
    local S, item = WowStub.state, WowStub.item
    local prices = {}
    local function put(bag, slot, it, price)
        WowStub.setBag(bag, slot, it)
        if price then prices[it.hyperlink] = price end
    end
    S.numSlots[5] = 4 -- the reagent bag (v0.5.1 ignored it)
    put(0, 1, item(6948, "Hearthstone", { bound = true, sell = 0, class = 15 }))
    put(0, 2, item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }), 174)
    put(0, 3, item(5022, "Bundle of Letters", { quest = true, class = 12 }), 9000)
    put(0, 4, item(2775, "Silver Ore", { count = 5, sell = 75, class = 7, subclass = 7 }), 9000)
    put(0, 5, item(2901, "Mining Pick", { sell = 16, class = 2, subclass = 14 }), 9000)
    put(0, 6, item(6125, "Brawler's Pants", { bound = true, quality = 2, sell = 300, class = 4, level = 20 }), 9000)
    put(0, 7, item(4865, "Ruined Pelt", { quality = 0, sell = 12, class = 15 }))
    put(0, 8, item(6515, "Spellbinder Robes", { quality = 2, sell = 300, class = 4, level = 20 }), 5000)
    put(0, 9, item(2318, "Light Leather", { count = 10, sell = 3, class = 7, subclass = 6 })) -- no price yet
    put(0, 10, item(858, "Lesser Healing Potion", { count = 5, sell = 5, class = 0 }))        -- no price
    local inUse = item(4306, "Silk Cloth", { count = 10, sell = 38, class = 7, subclass = 5 })
    inUse.isLocked = true -- picked up / being traded: the game's own lock
    put(0, 11, inUse, 9000)
    -- A plain trade good an active quest asks for (operator, 2026-11-08): worth listing, never mailed.
    put(0, 12, item(1081, "Crisp Spider Meat", { count = 5, sell = 250, class = 7, subclass = 8 }), 9000)
    S.quests = { { title = "Redridge Goulash", objectives = { { text = "Crisp Spider Meat: 5/5", type = "item" } } } }
    -- A warlock's Healthstone (operator, 2026-11-10: it was on the list for the bank alt): conjured, never mailed.
    put(0, 15, item(5512, "Minor Healthstone", { sell = 0, class = 0 }))
    put(5, 1, item(2592, "Wool Cloth", { count = 20, sell = 33, class = 7, subclass = 5 }), 9000)
    for i = 1, 10 do -- bags 1 and 2: ten priced stacks, so the run needs a second mail
        local bag, slot = i <= 4 and 1 or 2, i <= 4 and i or i - 4
        put(bag, slot, item(3000 + i, "Ore " .. i, { count = 5, sell = 5, class = 7, subclass = 7 }), 500)
    end
    -- The game's combined bags as Forever has them (v0.22.0 errored on this at every login and
    -- mailbox visit): buttons for the slots laid out so far, a size that counts every slot.
    local combined = ContainerFrameCombinedBags
    combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2), WowStub.itemButton(0, 4) }
    combined.size = 36
    return prices
end

local function useAuctionator(prices)
    _G.Auctionator = { API = { v1 = {
        GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
        GetAuctionAgeByItemLink = function() return 0 end,
    } } }
end

--- TradeSkillMaster's public API (TSM_API) with the same prices as its realm AuctionDB
--- "DBMinBuyout"; raises on anything but a TSM item string, as TSM's own does.
--- Returns the list of calls made.
local function useTSM(prices)
    local byID, calls = {}, {}
    for l, v in pairs(prices) do byID["i:" .. l:match("item:(%d+)")] = v end
    _G.TSM_API = {
        ToItemString = function(l) return "i:" .. assert(l:match("item:(%d+)")) end,
        IsCustomPriceValid = function(source) return source == "DBMinBuyout" or source == "DBMarket" end,
        GetCustomPriceValue = function(source, itemString)
            assert(type(itemString) == "string" and itemString:find("^i:%d+$"), "not a TSM item string")
            calls[#calls + 1] = { source = source, id = itemString:match("^i:(%d+)$") }
            if source == "DBMinBuyout" and byID[itemString] then return byID[itemString] end
            return nil, "No value was returned by the custom price for the specified item."
        end,
    }
    return calls
end

local function mailbox()
    MailFrame:Show()
    SendMailFrame:Show()
end

--- itemID -> recipient, as the window previewed it.
local function previewed(ns)
    local out = {}
    for _, it in ipairs(ns.MailWindow.Result().mail) do out[it.itemID] = it.result.to or BANK_ALT end
    return out
end

--- Answer every mail the way the server does until the mailer is done.
local function deliver(ns)
    for _ = 1, 20 do
        WowStub.runTimers()
        if not ns.Mailer.Busy() then return end
        ns.Fire("MAIL_SEND_SUCCESS")
    end
    error("the mailer never finished")
end

--- The AGENTS.md safety rules, checked on every mail that went out, and the preview
--- delivered in full: each previewed item went to its previewed recipient, nothing else went.
local function assertSafeAndComplete(ns, preview, allowed)
    local sent, carried = WowStub.state.sent, WowStub.state.sentItems
    assert.is_true(#sent > 0, "nothing was mailed")
    local got = {}
    for i, mail in ipairs(sent) do
        assert.is_true(allowed[mail.name] == true, "mail " .. i .. " went to " .. tostring(mail.name))
        assert.equal(0, mail.money, "mail " .. i .. " carried money")
        assert.equal(0, mail.cod, "mail " .. i .. " was COD")
        assert.equal("", mail.body, "mail " .. i .. " has text: a letter the recipient has to delete")
        assert.is_true(mail.count <= 12)
        for _, it in ipairs(carried[i]) do
            assert.is_nil(HARD_KEEPS[it.itemID], "mailed a hard keep: " .. tostring(HARD_KEEPS[it.itemID]))
            assert.is_false(it.bound, "mailed a soulbound item " .. it.itemID)
            assert.is_false(it.quest, "mailed a quest item " .. it.itemID)
            assert.is_false(ns.Locks.IsItemLocked(it.itemID), "mailed a locked item " .. it.itemID)
            assert.equal(preview[it.itemID], mail.name, "item " .. it.itemID .. " went to the wrong recipient")
            got[it.itemID] = true
        end
    end
    for itemID in pairs(preview) do assert.is_true(got[itemID], "previewed but not mailed: " .. itemID) end
    local logged = {}
    for _, e in ipairs(ns.Ledger.Store().log) do
        if e.dir == "sent" then logged[#logged + 1] = e end
    end
    assert.equal(#sent, #logged, "the mail log doesn't hold one entry per mail sent")
    for i, mail in ipairs(sent) do
        assert.equal(mail.name, logged[i].other, "mail " .. i .. " is logged to the wrong recipient")
        assert.equal(#carried[i], #logged[i].items, "mail " .. i .. " is logged with the wrong stacks")
        for j, it in ipairs(carried[i]) do
            assert.equal(it.itemID, logged[i].items[j].itemID, "mail " .. i .. " stack " .. j)
            assert.equal(it.count, logged[i].items[j].count, "mail " .. i .. " stack " .. j)
        end
    end
end

local function assertQuiet(ns)
    for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    assert.same({}, MailworthyDB.blocked, "a blocked action was blamed on Mailworthy")
    assert.equal(0, WowStub.focusCalls, "SetFocus was called")
    assert.equal(0, WowStub.tabClicks, "Mailworthy switched mail tabs")
end

describe("critical path: mailing", function()
    local ns, prices

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(BANK_ALT)
        prices = fillBags()
        useAuctionator(prices)
        ns.Locks.ToggleItem(2775, WowStub.link(2775, "Silver Ore"), "spec")
    end)
    after_each(function()
        assertQuiet(ns)
        _G.Auctionator, _G.TSM_API, _G.DisenchantValueAPI, _G.TSM_APPHELPER_LOAD_DATA = nil, nil, nil, nil
    end)

    it("the .toc loads every addon file and only files that exist", function()
        local listed = {}
        for line in io.lines("Mailworthy/Mailworthy.toc") do
            if line:match("%.lua$") then listed[line] = true end
            if line:match("^## Interface:") then assert.equal("## Interface: 16001", line) end
        end
        local pipe = assert(io.popen("ls Mailworthy"))
        for file in pipe:lines() do
            if file:match("%.lua$") then
                assert.is_true(listed[file] == true, file .. " is not in Mailworthy.toc: the game would never load it")
                listed[file] = nil
            end
        end
        pipe:close()
        assert.is_nil(next(listed), "the .toc lists a file that doesn't exist")
    end)

    it("mouse: Mailworthy button, Send, every previewed item reaches the bank alt and nothing else leaves", function()
        ns.Fire("MAIL_SHOW")
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        local preview = previewed(ns)
        assert.truthy(preview[6515], "a priced BoE green goes")
        assert.truthy(preview[2592], "the reagent bag is scanned")
        assert.truthy(preview[3010], "the last bag's items go")
        assert.is_true(_G.MailworthyMailSend:IsShown())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assert.is_true(#WowStub.state.sent >= 2, "more than 12 stacks: the run chains a second mail")
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assert.truthy(ns.Mailer.Status():find("^Sent %d+ mail"), ns.Mailer.Status())
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.equal(0, #ns.MailWindow.Result().mail, "after sending, the window has nothing left to mail")
        ns.Fire("MAIL_CLOSED")
    end)

    it("the Send Mail tab opens the window by itself; on the Inbox Send is greyed out and sends nothing", function()
        -- operator, 2026-11-08: "when you click send mail mailworthy should open ... greyed out with a
        -- 'click send mail' text ... flip to the standard send to button"
        local watcher = _G.MailworthyTabWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.3) end
        ns.Fire("MAIL_SHOW")
        MailFrame:Show()
        InboxFrame:Show()
        _G.MailworthyInboxButton:Click()
        assert.equal("Click Send Mail", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent, "nothing goes from the Inbox")
        ns.MailWindow.Frame():Hide()
        tick()
        InboxFrame:Hide()
        SendMailFrame:Show() -- the player clicks the Send Mail tab, nothing else
        tick()
        assert.is_true(ns.MailWindow.Frame():IsVisible())
        assert.equal("Send to Roknua", _G.MailworthyMailSend:GetText())
        local preview = previewed(ns)
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("controller: Triangle opens the window, Send is a D-pad target, Cross sends", function()
        WowStub.state.gamepadUI = true
        ns.Fire("MAIL_SHOW")
        mailbox()
        WowStub.state.activeFrame = MailFrame
        local watcher = _G.MailworthyPadWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
        local function press(name)
            WowStub.state.now = WowStub.state.now + 1
            _G[name]:Click()
            tick()
        end
        tick()
        press("MailworthyPadTriangle")
        assert.is_true(ns.MailWindow.Frame():IsShown())
        local preview = previewed(ns)
        assert.equal("CLICK MailworthyPadCross:LeftButton", WowStub.state.bindings.PAD1, "Cross isn't bound")
        press("MailworthyPadDown")
        assert.truthy(ns.Nav.Current(), "the D-pad doesn't move the highlight")
        -- The stub has no layout, so which press lands on Send is nav_spec's job (fixed
        -- coordinates); here Send must be a controller target and Cross must press it.
        local reachable = false
        for _, c in ipairs(ns.Nav.Candidates()) do reachable = reachable or c.button == _G.MailworthyMailSend end
        assert.is_true(reachable, "Send isn't a controller target")
        ns.Nav.Select(_G.MailworthyMailSend)
        press("MailworthyPadCross")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("check error", 1, true), line) end
    end)

    it("without Auctionator only unlocked, tradeable white items are mailed", function()
        _G.Auctionator = nil
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[6515], "a green stays without prices")
        assert.is_nil(preview[4865], "junk stays without prices")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        for i in ipairs(WowStub.state.sent) do
            for _, it in ipairs(WowStub.state.sentItems[i]) do assert.equal(1, it.quality, "item " .. it.itemID) end
        end
    end)

    it("with Auctionator an unpriced item goes to the bank alt on any launch day; junk and hard keeps stay", function()
        -- Rule changed on purpose (operator, 2026-11-08): "going to the bank alt on no data is better than
        -- holding on the main". Was: an unpriced item stays, except a white trade good in launch days 0-13.
        local function unpricedHardKeeps()
            local locked = WowStub.item(7976, "Plans: Locked Recipe", { quality = 2, sell = 450, class = 9, subclass = 4 })
            WowStub.setBag(1, 4, locked)
            ns.Locks.ToggleItem(7976, locked.hyperlink, "spec")
            WowStub.setBag(2, 5, WowStub.item(7977, "Bound Recipe", { bound = true, quality = 2, sell = 450, class = 9, subclass = 4 }))
        end
        unpricedHardKeeps()
        local launchWeek = WowStub.state.serverTime
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 30 * 86400
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[858], "an unpriced potion goes to the bank alt")
        assert.equal(BANK_ALT, preview[2318], "an unpriced staple trade good goes, past launch day 13 too")
        assert.is_nil(preview[4865], "unpriced grey junk stays for the vendor")
        assert.is_nil(preview[7976], "a locked unpriced recipe stays")
        assert.is_nil(preview[7977], "a soulbound unpriced recipe stays")
        assert.is_nil(preview[1081], "what a quest needs stays")
        WowStub.state.serverTime = launchWeek
        ns.MailWindow.Refresh()
        preview = previewed(ns)
        assert.equal(BANK_ALT, preview[858], "launch week the same")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("a stale price (older than 7 days) goes to the bank alt like no price; a hard keep with one still stays", function()
        -- operator, 2026-11-08: "Stale prices go too" (rule changed on purpose; was: it stays)
        local green = WowStub.link(6515, "Spellbinder Robes")
        local stale = { [green] = true, [WowStub.link(2775, "Silver Ore")] = true, [WowStub.link(5022, "Bundle of Letters")] = true }
        Auctionator.API.v1.GetAuctionAgeByItemLink = function(_, l) return stale[l] and 9 or 0 end
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[6515], "the green with a 9-day-old price goes to the bank alt")
        assert.is_nil(preview[2775], "locked, stale: stays")
        assert.is_nil(preview[5022], "a quest item, stale: stays")
        for _, it in ipairs(ns.MailWindow.Result().mail) do
            if it.itemID == 6515 then
                assert.equal("noprice", it.result.route)
                assert.is_nil(it.result.gain, "the old price isn't used")
            end
        end
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("with Auctionator but no bank alt (or skipped): an unpriced item stays, as the rest of its share", function()
        MailworthyDB.bankAlts = {}
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        ns.Routes.Add(BOB, ENCHANTING)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[858], "no bank alt: the unpriced potion stays")
        assert.is_nil(preview[2318], "no bank alt: the unpriced staple stays")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BOB] = true })
    end)

    it("a recipe goes to the friend bound to its profession, unpriced or under the cap; at the cap to the bank alt", function()
        -- operator, 2026-11-08: "recipes should go to their respective profession mappings or default to
        -- the bank alt if no AH data is found"
        local SMITH = "Smith Anvil"
        local hammer = WowStub.item(7975, "Plans: Iridescent Hammer", { quality = 2, sell = 450, class = 9, subclass = 4 })
        local pants = WowStub.item(7978, "Plans: Pricey Pants", { quality = 3, sell = 450, class = 9, subclass = 4 })
        local tailor = WowStub.item(7979, "Pattern: Some Robe", { quality = 2, sell = 450, class = 9, subclass = 2 })
        WowStub.setBag(2, 5, hammer)    -- no auction price
        WowStub.setBag(2, 6, pants)
        prices[pants.hyperlink] = 90000  -- 9g: at or above the 10s default cap
        WowStub.setBag(1, 4, tailor)    -- no Tailoring binding, no price
        ns.Routes.Add(SMITH, 164)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(SMITH, preview[7975], "the unpriced Blacksmithing recipe goes to the blacksmith friend")
        assert.equal(BANK_ALT, preview[7978], "at or above the cap: the normal rule, the bank alt for the AH")
        assert.equal(BANK_ALT, preview[7979], "no binding for Tailoring, no price: the bank alt")
        prices[pants.hyperlink] = 500  -- 5s: under the cap (10s for a new binding; operator, 2026-11-11)
        ns.MailWindow.Refresh()
        preview = previewed(ns)
        assert.equal(SMITH, preview[7978], "under the cap: the friend")
        -- Codex review: a failed price call mails nothing, a stale price over the cap doesn't reach the friend
        local broken = WowStub.item(7980, "Plans: Broken Lookup", { quality = 2, sell = 450, class = 9, subclass = 4 })
        local old = WowStub.item(7981, "Plans: Old Price", { quality = 3, sell = 450, class = 9, subclass = 4 })
        WowStub.setBag(2, 4, broken)
        WowStub.setBag(2, 3, old)
        prices[old.hyperlink] = 90000
        local v1 = Auctionator.API.v1
        local lookup = v1.GetAuctionPriceByItemLink
        v1.GetAuctionPriceByItemLink = function(c, l)
            if l == broken.hyperlink then error("boom") end
            return lookup(c, l)
        end
        v1.GetAuctionAgeByItemLink = function(_, l) return l == old.hyperlink and 9 or 0 end
        ns.MailWindow.Refresh()
        preview = previewed(ns)
        assert.is_nil(preview[7980], "the price call failed: it stays, binding or not")
        assert.equal(BANK_ALT, preview[7981], "a 9g price 9 days old still caps it: the bank alt, not the friend")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [SMITH] = true })
    end)

    it("a class binding never takes an unpriced item, even one worth disenchanting: it goes to the bank alt", function()
        WowStub.setBag(0, 13, WowStub.item(211234, "Scroll: VOCE WELL", { sell = 15, class = 0 }))
        WowStub.state.itemClasses[211234] = "Mage"
        -- Codex review: a disenchant value alone (route "de") isn't an auction price
        WowStub.setBag(0, 14, WowStub.item(211235, "Mage Robe", { quality = 2, sell = 100, class = 4, level = 20 }))
        WowStub.state.itemClasses[211235] = "Mage"
        _G.DisenchantValueAPI = { GetValue = function(l) return l:find("Mage Robe", 1, true) and 5000 or nil end }
        ns.Routes.Add(BOB, "MAGE")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[211234])
        assert.equal(BANK_ALT, preview[211235], "disenchant pays, no auction price: the bank alt")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        _G.DisenchantValueAPI = nil
    end)

    it("without a price source a staple trade good goes whatever its quality; other non-white items stay", function()
        _G.Auctionator = nil
        WowStub.setBag(2, 5, WowStub.item(10938, "Lesser Magic Essence", { count = 2, quality = 2, sell = 4, class = 7, subclass = 12 }))
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[10938])
        assert.is_nil(preview[6515], "a green that isn't a staple stays without prices")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        for i in ipairs(WowStub.state.sent) do
            for _, it in ipairs(WowStub.state.sentItems[i]) do
                assert.is_true(it.quality == 1 or ns.Valuation.STAPLES[it.itemID] ~= nil, "item " .. it.itemID)
            end
        end
    end)

    it("TradeSkillMaster alone: its prices count like Auctionator's, an unpriced item stays", function()
        -- AGENTS.md Safety "with Auctionator" = with an auction price source (Prices.Source).
        _G.Auctionator = nil
        useTSM(prices)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.truthy(preview[6515], "a priced BoE green goes")
        -- operator, 2026-11-08 (rule changed on purpose; was: an unpriced potion stays)
        assert.equal(BANK_ALT, preview[858], "an unpriced potion goes to the bank alt")
        assert.truthy(preview[2318], "an unpriced staple trade good goes")
        assert.is_nil(preview[4865], "junk without a price stays")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("TradeSkillMaster alone: unpriced items go on any launch day; when its price call fails, they stay", function()
        -- operator, 2026-11-08 (rule changed on purpose; was: past launch day 13 an unpriced item stays)
        _G.Auctionator = nil
        useTSM(prices)
        local launchWeek = WowStub.state.serverTime
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 30 * 86400
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(BANK_ALT, previewed(ns)[2318], "past launch day 13 it goes to the bank alt")
        WowStub.state.serverTime = launchWeek
        ns.MailWindow.Refresh()
        assert.truthy(previewed(ns)[2318], "launch week the same")
        _G.TSM_API.GetCustomPriceValue = function() error("boom") end
        -- and not for a disenchant value either (Codex review, 2026-11-08)
        _G.DisenchantValueAPI = { GetValue = function(l) return l:find("Spellbinder Robes", 1, true) and 50000 or nil end }
        ns.MailWindow.Refresh()
        assert.same({}, previewed(ns), "a failing price call is never 'no price yet': nothing goes")
        _G.DisenchantValueAPI = nil
    end)

    -- operator, 2026-11-17 (rule changed on purpose; was: Auctionator's prices decide, TSM never asked):
    -- "it shouldnt be a fixed rule, it should be whichever addon has the most up to date scan data", per item.
    it("Auctionator and TradeSkillMaster both installed: each item priced by the fresher of the two", function()
        local tsmPrices = {}
        for l in pairs(prices) do tsmPrices[l] = 1 end -- TSM would call everything worthless
        local potion = WowStub.link(858, "Lesser Healing Potion")
        tsmPrices[potion] = 90000 -- and the potion, which Auctionator has no price for, a fortune
        local calls = useTSM(tsmPrices)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.truthy(preview[6515], "Auctionator's price for the green, scanned today")
        assert.equal(BANK_ALT, preview[858], "TSM's price for what Auctionator has none for")
        for _, it in ipairs(ns.MailWindow.Result().mail) do
            if it.itemID == 858 then assert.equal("ah", it.result.route, "priced by TSM") end
        end
        local pricedToday = {}
        for l in pairs(prices) do pricedToday[l:match("item:(%d+)")] = true end
        assert.is_true(#calls > 0, "TSM asked for the potion")
        for _, c in ipairs(calls) do
            assert.is_nil(pricedToday[c.id], "TSM asked for " .. c.id .. ", which Auctionator priced today")
        end
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("both installed: TSM's realm data, fresher than an old Auctionator scan, prices the item; a failing TSM changes nothing", function()
        local api = _G.Auctionator.API.v1
        api.GetAuctionAgeByItemLink = function() return 12 end -- Auctionator last scanned 12 days ago
        _G.TSM_APPHELPER_LOAD_DATA = function() end
        assert.is_true(ns.Prices.WatchTSMData())
        _G.TSM_APPHELPER_LOAD_DATA(ns.Prices.TSM_REALM_TAG, GetRealmName() .. "-" .. UnitFactionGroup("player"),
            "return {downloadTime=" .. (os.time() - 86400) .. ",fields={},data={}}")
        local tsmPrices = {}
        for l, v in pairs(prices) do tsmPrices[l] = v end
        useTSM(tsmPrices)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.truthy(preview[6515], "the green goes on TSM's day-old price")
        for _, it in ipairs(ns.MailWindow.Result().mail) do
            if it.itemID == 6515 then
                assert.equal("ah", it.result.route, "not 'auction price too old'")
                assert.equal("TSM", it.price.source)
            end
        end
        _G.TSM_API.GetCustomPriceValue = function() error("boom") end
        ns.MailWindow.Refresh()
        for _, it in ipairs(ns.MailWindow.Result().mail) do
            assert.equal("Auctionator", it.price.source, "TSM failing: Auctionator's old prices, as without TSM")
        end
        preview = previewed(ns)
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("a binding: the friend gets their profession's materials, the bank alt the rest, nobody else", function()
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3 -- the rule alone would keep it
        ns.Routes.Add(BOB, ENCHANTING)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940])
        assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    -- rl-companion, 2026-11-14: Cooking bound to Rok Androl from another alt ("all my characters"), then
    -- Androl at the mailbox: the binding named Androl himself, and every press said "Can't send: a
    -- binding points at this character". On the bound character its materials stay; the rest still goes.
    it("a binding saved for all characters, at the bound character's own mailbox: its items stay, Send works", function()
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        local _, realm, faction = ns.Characters.Current()
        MailworthyDB.routes = { [realm .. "|" .. faction] = { { to = ns.PlayerName(), profession = ENCHANTING } } }
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[10940], "this character's own binding mailed its materials")
        local stays = false
        for _, it in ipairs(ns.MailWindow.Result().keep) do stays = stays or it.itemID == 10940 end
        assert.is_true(stays, "the bound materials are listed as staying")
        assert.truthy(next(preview), "the bank alt's share is still on the list")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("a bank pin (mouse): the pinned item goes to the bank alt, not to a binding's friend; a pinned hard keep stays", function()
        -- Pins.lua: "always bank this". Junk the rule keeps, a material a binding would take, and three
        -- hard keeps the player pinned by mistake.
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        ns.Routes.Add(BOB, ENCHANTING)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(previewed(ns)[4865], "junk stays until it is pinned")
        assert.equal(BOB, previewed(ns)[10940], "the binding takes the dust until it is pinned")
        WowStub.state.mods = { alt = true, ctrl = true }
        for _, at in ipairs({ { 0, 7 }, { 2, 6 }, { 0, 1 }, { 0, 3 }, { 0, 4 } }) do -- pelt, dust, Hearthstone, quest item, locked ore
            -- This build's own click handler: the global hook is shared by every addon load in this file.
            ns.Pins.OnModifiedItemClick("link", WowStub.itemLocation(at[1], at[2]))
        end
        WowStub.state.mods = {}
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[4865], "the pinned junk goes to the bank alt")
        assert.equal(BANK_ALT, preview[10940], "the pinned dust goes to the bank alt, not to the friend")
        assert.is_nil(preview[6948], "a pinned soulbound item stays")
        assert.is_nil(preview[5022], "a pinned quest item stays")
        assert.is_nil(preview[2775], "a pinned locked item stays")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("a bank pin (controller): R3 on the selected bag item, then Send mails it as previewed", function()
        WowStub.state.gamepadUI = true
        ns.Fire("MAIL_SHOW")
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
        local function press(name)
            WowStub.state.now = WowStub.state.now + 1
            _G[name]:Click()
            tick()
        end
        WowStub.state.activeFrame = ContainerFrameCombinedBags
        tick()
        assert.equal("CLICK MailworthyPadPin:LeftButton", WowStub.state.bindings.PADRSTICK, "R3 isn't bound in the bags")
        WowStub.state.navButton = WowStub.itemButton(0, 7) -- Ruined Pelt: junk, stays by the rule
        press("MailworthyPadPin")
        WowStub.state.activeFrame = MailFrame
        tick()
        press("MailworthyPadTriangle")
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[4865], "the pinned junk goes to the bank alt")
        ns.Nav.Select(_G.MailworthyMailSend)
        press("MailworthyPadCross")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("a bank pin without Auctionator: the pinned green and junk go to the bank alt; unpinned, they stay", function()
        -- Rule changed on purpose (operator, 2026-11-13: "Pins override them"): a pin overrides the
        -- no-price-source rule (whites and staples only) and grey junk staying; never a hard keep.
        _G.Auctionator = nil
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(previewed(ns)[6515], "a green stays without prices until it is pinned")
        assert.is_nil(previewed(ns)[4865], "junk stays without prices until it is pinned")
        for _, id in ipairs({ 6515, 4865, 6948, 2775 }) do -- the green, junk, the Hearthstone, the locked ore
            ns.Pins.Set(id, WowStub.link(id, "item " .. id), ns.Pins.BANK, "spec")
        end
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[6515], "the pinned green goes to the bank alt")
        assert.equal(BANK_ALT, preview[4865], "the pinned junk goes to the bank alt")
        assert.is_nil(preview[6948], "a pinned soulbound item stays")
        assert.is_nil(preview[2775], "a pinned locked item stays")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("bank-here pins (Settings > Pinned items, per character): pinned items stay, the rest goes; switched back, they go", function()
        -- Operator, 2026-11-13: Ctrl+Alt+click's pin either goes to the bank alt (BA) or stays to bank here (BH).
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        ns.Routes.Add(BOB, ENCHANTING)
        ns.Pins.Set(4865, WowStub.link(4865, "Ruined Pelt"), ns.Pins.BANK, "spec")
        ns.Pins.Set(10940, WowStub.link(10940, "Strange Dust"), ns.Pins.BANK, "spec")
        ns.SettingsUI.Show()
        _G.MailworthySettingsPins:Click() -- by mouse: bank here on this character
        assert.equal(ns.Pins.HERE, ns.Pins.Mode())
        ns.SettingsUI.Frame():Hide()
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[4865], "the pinned junk stays, to bank here")
        assert.is_nil(preview[10940], "the pinned dust stays: not to the bank alt, not to the binding's friend")
        assert.equal(BANK_ALT, preview[2770], "the rest goes as usual")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assert.is_true(WowStub.state.bags[0][7] ~= nil, "the pelt is still in the bags")
        -- Switched back (BA): the pins go to the bank alt again.
        ns.Pins.SetMode(ns.Pins.BANK, "spec")
        mailbox()
        _G.MailworthyMailButton:Click()
        preview = previewed(ns)
        assert.equal(BANK_ALT, preview[4865], "pins go to the bank alt again (its preview; one send per case)")
        assert.equal(BANK_ALT, preview[10940])
    end)

    it("a bank pin on what this character's profession uses: the pin wins (warned once), it goes to the bank alt", function()
        -- Operator, 2026-11-13: "a bank pin is a hard decision by the user and needs to be honored".
        WowStub.state.professions = { { index = 1, name = "Enchanting", rank = 60, maxRank = 150, skillLine = ENCHANTING } }
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 300
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(previewed(ns)[10940], "kept for this character's Enchanting until it is pinned")
        ns.Pins.Set(10940, WowStub.link(10940, "Strange Dust"), ns.Pins.BANK, "spec")
        assert.is_true(ns.PinWarning.Frame():IsShown(), "the warning")
        _G.MailworthyPinWarningOK:Click()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[10940], "the pin wins")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("a vendor pin: the pinned items never leave, priced, soulbound or wanted by a binding", function()
        -- shindo107's feat/vendor-pin: "always vendor this". A green the rule would mail for the auction
        -- house, a soulbound green, and a material a binding would take: all three stay, tagged V.
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        ns.Routes.Add(BOB, ENCHANTING)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(BANK_ALT, previewed(ns)[6515], "the green goes until it is pinned")
        for _, pin in ipairs({ { 6515, "Spellbinder Robes" }, { 6125, "Brawler's Pants" }, { 10940, "Strange Dust" } }) do
            ns.Pins.Set(pin[1], WowStub.link(pin[1], pin[2]), ns.Pins.VENDOR, "spec")
        end
        local preview = previewed(ns)
        assert.is_nil(preview[6515], "the vendor-pinned green stays")
        assert.is_nil(preview[6125], "the vendor-pinned soulbound green stays")
        assert.is_nil(preview[10940], "the vendor-pinned dust stays: the binding doesn't take it")
        local tagged = {}
        for _, it in ipairs(ns.MailWindow.Result().keep) do tagged[it.itemID] = ns.BankAlt.Verdict(it) end
        assert.equal("v", tagged[6515])
        assert.equal("v", tagged[6125])
        assert.equal("v", tagged[10940])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("no bank alt: a pinned item stays in the bags like the rest of the bank alt's share", function()
        MailworthyDB.bankAlts = {}
        ns.Pins.Set(4865, WowStub.link(4865, "Ruined Pelt"), ns.Pins.BANK, "spec")
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(0, #ns.MailWindow.Result().mail, "nobody to mail to")
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent)
    end)

    it("a class binding: the mage friend gets the mage-only scroll, the bank alt the rest, nobody else", function()
        -- operator, 2026-11-08: "this is a mage only item, id like to be able to friend mail these types of items too"
        WowStub.setBag(0, 13, WowStub.item(211234, "Scroll: VOCE WELL", { sell = 15, class = 0 }))
        prices[WowStub.link(211234, "Scroll: VOCE WELL")] = 100
        WowStub.state.itemClasses[211234] = "Mage"
        WowStub.state.itemClasses[6515] = "Paladin" -- another class's item: not the mage's
        ns.Routes.Add(BOB, "MAGE")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[211234])
        assert.equal(BANK_ALT, preview[6515])
        assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    -- A CurseForge comment and the operator, 2026-11-20: "Lock boxes can route to rouges for training
    -- ... comprehension items to mages(class specific profession)"; "Like profession mats".
    local function classSkillItems()
        local S = WowStub.state
        WowStub.setBag(0, 13, WowStub.item(4634, "Iron Lockbox", { quality = 2, sell = 0, class = 15 })) -- no price
        S.tooltipLines[4634] = { "Locked", "Requires Lockpicking (70)" }
        WowStub.setBag(0, 14, WowStub.item(211234, "Scroll: VOCE WELL", { quality = 2, sell = 15, class = 0 })) -- no price
        S.itemClasses[211234] = "Mage"
        S.tooltipLines[211234] = { "Requires Comprehension (15)" }
        -- a lockbox the player locked, a soulbound one, and one already picked (unlocked)
        WowStub.setBag(0, 16, WowStub.item(7976, "Plans: Locked Recipe", { quality = 2, sell = 0, class = 15 }))
        S.tooltipLines[7976] = { "Locked", "Requires Lockpicking (1)" }
        ns.Locks.ToggleItem(7976, WowStub.link(7976, "Plans: Locked Recipe"), "spec")
        WowStub.setBag(0, 17, WowStub.item(7977, "Bound Recipe", { quality = 2, sell = 0, class = 15, bound = true }))
        S.tooltipLines[7977] = { "Locked", "Requires Lockpicking (1)" }
        WowStub.setBag(0, 18, WowStub.item(5758, "Mithril Lockbox", { quality = 2, sell = 0, class = 15 }))
        S.tooltipLines[5758] = { "Locked", "Requires Lockpicking (175)" }
        S.opened["0:18"] = true
    end

    it("a class binding's skill items (mouse): lockboxes to the rogue, Comprehension scrolls to the mage, unpriced too", function()
        local ROGUE, MAGE = BOB, "Sadie Ember"
        classSkillItems()
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[4634], "no binding: the normal rule, as before")
        assert.equal(BANK_ALT, preview[211234])
        ns.Routes.Add(ROGUE, "ROGUE")
        ns.Routes.Add(MAGE, "MAGE")
        ns.MailWindow.Refresh()
        preview = previewed(ns)
        assert.equal(ROGUE, preview[4634], "a locked lockbox with no auction price: the rogue")
        assert.equal(MAGE, preview[211234], "a Comprehension scroll with no auction price: the mage")
        assert.equal(BANK_ALT, preview[5758], "already unlocked: it trains nobody, the normal rule")
        assert.is_nil(preview[7976], "locked by the player: it stays")
        assert.is_nil(preview[7977], "soulbound: it stays")
        assert.equal(BANK_ALT, preview[6515], "a plain green: not a class skill's item")
        local shown = {} -- every recipient is on a "To:" line before Send (AGENTS.md Safety)
        for _, to in ipairs(ns.MailWindow.Result().totals.recipients) do shown[to == "" and BANK_ALT or to] = true end
        assert.same({ [BANK_ALT] = true, [ROGUE] = true, [MAGE] = true }, shown)
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [ROGUE] = true, [MAGE] = true })
    end)

    it("a class binding's skill items without Auctionator (controller): the green lockbox goes to the rogue, other greens stay", function()
        _G.Auctionator = nil
        classSkillItems()
        ns.Routes.Add(BOB, "ROGUE")
        WowStub.state.gamepadUI = true
        ns.Fire("MAIL_SHOW")
        mailbox()
        WowStub.state.activeFrame = MailFrame
        local watcher = _G.MailworthyPadWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
        local function press(name)
            WowStub.state.now = WowStub.state.now + 1
            _G[name]:Click()
            tick()
        end
        tick()
        press("MailworthyPadTriangle")
        local preview = previewed(ns)
        assert.equal(BOB, preview[4634])
        assert.is_nil(preview[211234], "no mage binding, no price source: the green scroll stays")
        assert.is_nil(preview[5758], "already unlocked: a green with no price source stays")
        assert.is_nil(preview[6515], "a green with no price source stays")
        assert.is_nil(preview[7976])
        assert.is_nil(preview[7977])
        ns.Nav.Select(_G.MailworthyMailSend)
        press("MailworthyPadCross")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    it("a rogue at the mailbox: its own locked lockboxes stay, a binding to another rogue or not; the rest goes", function()
        WowStub.state.class = { "Rogue", "ROGUE", 4 }
        classSkillItems()
        ns.Routes.Add(BOB, "ROGUE")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[4634], "me first: this rogue's own lockbox stays")
        assert.equal(BANK_ALT, preview[211234], "a mage's scroll: the normal rule")
        assert.equal(BANK_ALT, preview[2770])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("two bindings on one material: lowest skill first, and a recipient that changes after the preview holds Send", function()
        -- operator, 2026-11-07: Blacksmithing and Engineering both take metal and stone, "Lowest skill
        -- first". Codex review: a skill heard between the preview and Send must not move mail unseen.
        local SMITH, ENGINEER = "Smith Anvil", "Jold Ark"
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = SMITH, online = true, professions = { 164 }, ranks = { 60 } },
            { name = ENGINEER, online = true, professions = { 202 }, ranks = { 100 } } } }
        ns.Routes.Add(SMITH, 164)
        ns.Routes.Add(ENGINEER, 202)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(SMITH, previewed(ns)[2770], "Copper Ore: the blacksmith (60) is lower than the engineer (100)")
        WowStub.state.guild.members[1].ranks = { 110 } -- the roster updates; the window hasn't redrawn
        _G.MailworthyMailSend:Click()
        assert.is_false(ns.Mailer.Busy(), "nothing goes while a recipient differs from the list shown")
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent)
        assert.truthy(table.concat(WowStub.printed, "\n"):find("Not sent: Copper Ore now goes to Jold instead of Smith", 1, true))
        local preview = previewed(ns)
        assert.equal(ENGINEER, preview[2770], "the list now shows the engineer")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [ENGINEER] = true })
    end)

    it("vendor trash (mouse): a grey item a vendor buys stays whatever the auction house lists it for", function()
        -- Rule added on purpose (operator, 2026-11-20): "there is a build in button on the vendor to
        -- 'sell trash' and it sells all trash. Those items shouldnt be suggested to AH even if the
        -- price is favorable. those dont sell". Before, a grey item with a current auction price was
        -- priced like any other and mailed for the auction house.
        prices[WowStub.link(4865, "Ruined Pelt")] = 9000 -- 90s at auction, 12c at a vendor
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[4865], "priced grey junk stays for the vendor")
        assert.equal(BANK_ALT, preview[2770], "the ore still goes for the auction house")
        -- The Vendor send switch never mails it either ("Grey junk stays").
        ns.SettingsUI.Show(ns.MailWindow.Frame())
        _G.MailworthySettingsSendVendor:Click()
        ns.SettingsUI.Frame():Hide()
        preview = previewed(ns)
        assert.is_nil(preview[4865], "Vendor on: priced grey junk still stays")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        for i in ipairs(WowStub.state.sent) do
            for _, it in ipairs(WowStub.state.sentItems[i]) do assert.are_not.equal(4865, it.itemID, "mailed vendor trash") end
        end
    end)

    it("vendor trash (controller): it stays off the list; bank-pinned, it goes to the bank alt", function()
        -- Operator, 2026-11-13: "Pins override them" (a bank pin mails grey junk too).
        prices[WowStub.link(4865, "Ruined Pelt")] = 9000
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        watcher.scripts.OnUpdate(watcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        watcher.scripts.OnUpdate(watcher, 0.2)
        assert.is_nil(previewed(ns)[4865], "priced grey junk stays for the vendor")
        ns.Pins.Set(4865, WowStub.link(4865, "Ruined Pelt"), ns.Pins.BANK, "spec")
        ns.MailWindow.Refresh()
        watcher.scripts.OnUpdate(watcher, 0.2)
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[4865], "the pinned pelt goes to the bank alt")
        ns.Nav.Select(_G.MailworthyMailSend)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("Send by tag (mouse): Vendor on mails what a vendor beats, never junk; Auction off keeps the auction items", function()
        -- shindo107's feat/craft-mats-to-alt: "V" on sends what the auction house prices under a vendor,
        -- so the bank alt can sell it. "Grey junk stays" and "an item whose price call failed stays"
        -- (AGENTS.md Safety) hold whatever the switch says (2026-11-13: the branch mailed junk).
        WowStub.setBag(2, 6, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 13, class = 7, subclass = 5 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 14 -- a vendor pays more: V
        mailbox()
        _G.MailworthyMailButton:Click()
        local before = previewed(ns)
        assert.is_nil(before[4865], "junk stays by default")
        assert.equal(BANK_ALT, before[2770], "the ore goes for the auction house by default")
        ns.SettingsUI.Show(ns.MailWindow.Frame())
        _G.MailworthySettingsSendVendor:Click()
        _G.MailworthySettingsSendAuction:Click()
        ns.SettingsUI.Frame():Hide()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2589], "Vendor on: the linen a vendor beats goes to the bank alt")
        assert.is_nil(preview[4865], "grey junk stays, Vendor on or not")
        assert.is_nil(preview[2770], "Auction off: the ore stays")
        assert.is_nil(preview[6515], "Auction off: the priced green stays")
        assert.equal(BANK_ALT, preview[2318], "an unpriced item has no tag: it goes as before")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("Send by tag (controller): Cross on the V switch in the settings, then Send mails as previewed", function()
        WowStub.setBag(2, 6, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 13, class = 7, subclass = 5 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 14
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        watcher.scripts.OnUpdate(watcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        watcher.scripts.OnUpdate(watcher, 0.2)
        ns.SettingsUI.Show(ns.MailWindow.Frame())
        watcher.scripts.OnUpdate(watcher, 0.2)
        assert.is_true(_G.MailworthySettingsSendVendor:IsShown())
        ns.Nav.Select(_G.MailworthySettingsSendVendor)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        assert.equal("V: on", _G.MailworthySettingsSendVendor:GetText())
        ns.SettingsUI.Frame():Hide()
        watcher.scripts.OnUpdate(watcher, 0.2)
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2589], "the linen goes to the bank alt")
        assert.is_nil(preview[4865], "grey junk stays")
        ns.Nav.Select(_G.MailworthyMailSend)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("Send by tag with Vendor on but no price source: junk and non-white items still stay", function()
        _G.Auctionator = nil
        ns.Config.Set("sendVendor", true)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[4865], "junk stays without prices, whatever the switch says")
        assert.is_nil(preview[6515], "a green stays without prices")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        for i in ipairs(WowStub.state.sent) do
            for _, it in ipairs(WowStub.state.sentItems[i]) do assert.equal(1, it.quality, "item " .. it.itemID) end
        end
    end)

    it("my professions' materials on my bank alt (mouse): previewed to the bank alt, then exactly that is sent", function()
        -- A new way to mail, behind a setting that is off by default: what this character's own
        -- crafting needs is kept here unless the player picks "on my bank alt" in the settings.
        WowStub.state.professions[2] = { index = 9, name = "Leatherworking", rank = 30, maxRank = 75, skillLine = 165 }
        prices[WowStub.link(2318, "Light Leather")] = 25
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(previewed(ns)[2318], "by default the leatherworker's leather stays")
        ns.SettingsUI.Show(ns.MailWindow.Frame())
        _G.MailworthySettingsMats:Click() -- off
        _G.MailworthySettingsMats:Click() -- on my bank alt
        assert.truthy(_G.MailworthySettingsMats:GetText():find("on my bank alt", 1, true))
        ns.SettingsUI.Frame():Hide()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2318], "the leather goes to the bank alt")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("my professions' materials on my bank alt (controller): Cross on the switch, then Send mails as previewed", function()
        WowStub.state.professions[2] = { index = 9, name = "Leatherworking", rank = 30, maxRank = 75, skillLine = 165 }
        prices[WowStub.link(2318, "Light Leather")] = 25
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        watcher.scripts.OnUpdate(watcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        watcher.scripts.OnUpdate(watcher, 0.2)
        ns.SettingsUI.Show(ns.MailWindow.Frame())
        watcher.scripts.OnUpdate(watcher, 0.2)
        ns.Nav.Select(_G.MailworthySettingsMats)
        for _ = 1, 2 do
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCross:Click()
        end
        assert.truthy(_G.MailworthySettingsMats:GetText():find("on my bank alt", 1, true))
        ns.SettingsUI.Frame():Hide()
        watcher.scripts.OnUpdate(watcher, 0.2)
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2318])
        ns.Nav.Select(_G.MailworthyMailSend)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("my professions' materials on my bank alt: the B switch off, or no bank alt, and they stay", function()
        WowStub.state.professions[2] = { index = 9, name = "Leatherworking", rank = 30, maxRank = 75, skillLine = 165 }
        prices[WowStub.link(2318, "Light Leather")] = 25
        ns.Config.Set("matsToBankAlt", true)
        ns.Config.Set("sendBank", false)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[2318], "Send by tag B off: the banked materials stay")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        ns.Config.Set("sendBank", true)
        ns.Config.ClearBankAlt()
        ns.MailWindow.Refresh()
        assert.is_nil(previewed(ns)[2318], "no bank alt: nowhere to send them")
    end)

    it("a bank alt picked after the preview holds Send until the list shows it (Codex review)", function()
        local NEW = "Newbank Alt"
        mailbox()
        _G.MailworthyMailButton:Click()
        ns.Config.SetBankAlt(NEW) -- Settings beside the mail window; the list still names the old one
        _G.MailworthyMailSend:Click()
        assert.is_false(ns.Mailer.Busy(), "nothing goes to a bank alt the list didn't name")
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent)
        local preview = previewed(ns)
        for id in pairs(preview) do preview[id] = preview[id] == BANK_ALT and NEW or preview[id] end
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [NEW] = true })
    end)

    it("no bank alt: the window opens, its share stays in the bags, and only the binding's friend gets mail", function()
        -- operator, 2026-11-08: "dont require a bank alt to use mailworthy"
        MailworthyDB.bankAlts = {}
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        prices[WowStub.link(6515, "Spellbinder Robes")] = 900 -- 9s: under the binding's 10s default cap (2026-11-11)
        ns.Routes.Add(BOB, ENCHANTING)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown(), "no bank alt: the window, not the settings")
        local preview = previewed(ns)
        assert.same({ [10940] = BOB, [6515] = BOB }, preview, "only the binding's (dust, and the green to disenchant)")
        assert.equal("Send to Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BOB] = true })
    end)

    it("Skip once for the bank alt: its share stays this visit, the binding still goes", function()
        -- operator, 2026-11-08: "Players should be able to click skip once for their bank alt sends too"
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        prices[WowStub.link(6515, "Spellbinder Robes")] = 900 -- 9s: under the binding's 10s default cap (2026-11-11)
        ns.Routes.Add(BOB, ENCHANTING)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(BANK_ALT, previewed(ns)[2592])
        _G.MailworthyMailSkipBankAlt:Click()
        assert.equal("Undo skip", _G.MailworthyMailSkipBankAlt:GetText())
        local preview = previewed(ns)
        assert.same({ [10940] = BOB, [6515] = BOB }, preview)
        assert.equal("Send to Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BOB] = true })
        ns.Fire("MAIL_CLOSED")
        mailbox()
        ns.MailWindow.Show("send")
        assert.equal(BANK_ALT, previewed(ns)[2592], "the next visit mails the bank alt again")
    end)

    --- The guild master's template (Guild.lua) arrives over the guild channel: Enchanting to Bob.
    local function guildTemplate()
        local gm = "Guild Master"
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = gm, rank = 0, online = true }, { name = BOB, rank = 3, online = true } } }
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3 -- the rule alone would keep it
        -- passed on by a plain member: any guild member may hand on a copy (operator, 2026-11-07)
        for _, m in ipairs(ns.Guild.Encode(WowStub.state.serverTime - 60, gm, { { profession = ENCHANTING, to = BOB } })) do
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", m, "GUILD", BOB)
        end
    end

    it("a guild template: nothing goes to the guild until the player turns it on, then only the shown recipients", function()
        guildTemplate()
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(previewed(ns)[10940], "a template the player hasn't turned on mails nothing")
        ns.SettingsUI.Show()
        -- The Guild window: Settings > Mail routing... > Guild... (2026-11-07: into the settings; 2026-11-22: under
        -- Mail routing, operator: "go with B, move them, call it Mail routing")
        _G.MailworthySettingsRouting:Click()
        _G.MailworthyFriendsGuild:Click()
        assert.is_true(_G.MailworthyFriendsGuildRules:IsShown())
        _G.MailworthyFriendsGuildRules:Click() -- "Use guild rules"
        ns.MailWindow.Refresh()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940])
        assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    --- Guild contributions (Contributions.lua, Raid Ledger ROK-2148): only a guild rule's mail is tagged
    --- in the log and counted, in stack units, for the sending character; MailworthyAPI says the same.
    local function assertGuildCounted(rulesTo)
        local units = 0 -- every stack the guild rule's mails carried (Enchanting takes green gear too)
        for i, mail in ipairs(WowStub.state.sent) do
            if rulesTo[mail.name] then
                for _, it in ipairs(WowStub.state.sentItems[i]) do units = units + it.count end
            end
        end
        assert.is_true(units > 0)
        local me = ns.PlayerName()
        local key = "Classic Beta PvP|Alliance|Bank Of Azeroth"
        for _, e in ipairs(ns.Ledger.Store().log) do
            if e.dir == "sent" and e.subject ~= "old" then
                if rulesTo[e.other] then
                    assert.equal("guild", e.scope, "a guild rule's mail to " .. e.other .. " isn't tagged")
                    assert.equal(ENCHANTING, e.guild.profession)
                    assert.equal(ns.Guild.Template().rev, e.guild.rev)
                else
                    assert.is_nil(e.scope, "mail to " .. e.other .. " is tagged as a guild rule's")
                    assert.is_nil(e.guild, "mail to " .. e.other .. " is tagged as a guild rule's")
                end
            end
        end
        local now = WowStub.state.serverTime
        local counted = MailworthyDB.guildGiven[key][me:lower()]
        assert.equal(units, counted.total)
        local export = MailworthyAPI.v1.GetGuildExport()
        -- asOf (Raid Ledger's contract delta, operator 2026-11-08 "Yes, share in hellos"): own givers carry generatedAt.
        assert.same({ { characterName = me, itemsAllTime = units, countingSince = counted.since, asOf = export.generatedAt,
            days = { { day = math.floor(now / 86400), items = units } } } }, export.givers)
        assert.equal(ns.Guild.Template().rev, export.template.rev)
    end

    it("a guild rule's mail is tagged and counted for the guild; the bank alt's and a binding's aren't", function()
        guildTemplate()
        ns.Guild.SetUse(true)
        prices[WowStub.link(2592, "Wool Cloth")] = 900 -- 9s each: under the binding's 10s default cap (2026-11-11)
        ns.Routes.Add("Cara Friend", 197) -- a personal Tailoring binding: its Wool Cloth is never counted
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940])
        assert.equal("Cara Friend", preview[2592])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true, ["Cara Friend"] = true })
        assertGuildCounted({ [BOB] = true })
    end)

    -- Raid Ledger can't tell which characters share an account, so Mailworthy leaves mail to the
    -- player's own characters out of the counts (operator, 2026-11-08), even when that alt is the
    -- guild's profession master. It is still mailed (the rule is on and shown) and still tagged.
    it("a guild rule naming one of the player's own characters: mailed as shown, never counted", function()
        local ALT = "Alty Alterson"
        MailworthyDB.characters["Alty Alterson|Classic Beta PvP|Alliance"] = { name = ALT,
            realm = "Classic Beta PvP", faction = "Alliance", class = "MAGE", level = 10 }
        local gm = "Guild Master"
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = gm, rank = 0, online = true }, { name = ALT, rank = 3 }, { name = BOB, rank = 3, online = true } } }
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        for _, m in ipairs(ns.Guild.Encode(WowStub.state.serverTime - 60, gm, { { profession = ENCHANTING, to = ALT } })) do
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", m, "GUILD", BOB)
        end
        ns.Guild.SetUse(true)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(ALT, preview[10940])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [ALT] = true })
        local tagged = false
        for _, e in ipairs(ns.Ledger.Store().log) do
            if e.dir == "sent" and e.other == ALT then tagged = e.scope == "guild" end
        end
        assert.is_true(tagged, "the mail to the alt is still logged as a guild rule's")
        assert.is_nil(MailworthyDB.guildGiven["Classic Beta PvP|Alliance|Bank Of Azeroth"], "mail to an own alt was counted")
        local export = MailworthyAPI.v1.GetGuildExport()
        assert.is_nil(export.givers, "an own alt's mail reached the export")
        assert.same({ { professionSkillLineId = ENCHANTING, recipientName = ALT } }, export.template.rules)
    end)

    -- Shared in hellos (operator, 2026-11-08: "Yes, share in hellos"): a guildmate's counts are information
    -- only. What they say never changes what is previewed or sent; the export carries them after ours.
    it("a guildmate's shared counts change nothing mailed; the export carries them after this account's", function()
        guildTemplate()
        ns.Guild.SetUse(true)
        local now = WowStub.state.serverTime
        for _, m in ipairs(ns.Contributions.Encode({ total = 500, since = now - 86400,
            days = { [math.floor(now / 86400)] = 500 } }, now - 30)) do
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", m, "GUILD", BOB)
        end
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
        local givers = MailworthyAPI.v1.GetGuildExport().givers
        assert.equal(2, #givers)
        assert.equal(ns.PlayerName(), givers[1].characterName)
        assert.same({ characterName = BOB, itemsAllTime = 500, countingSince = now - 86400, asOf = now - 30,
            days = { { day = math.floor(now / 86400), items = 500 } } }, givers[2])
    end)

    -- Operator, 2026-11-14: "Make me a profit/level my professions first, then the same to my friend rules,
    -- then the same to my guild rules", and a button on each row that toggles the item between those for
    -- the visit ("with 2 clicks it would actually route the copper bar to Jold for that round of sending";
    -- "my click wins" over the cap). A Copper Bar this character's Blacksmithing uses: a friend's
    -- Blacksmithing binding and the guild's Engineering rule both take metal.
    local SMITH, JOLD = "Sadie Smith", "Jold Ark"
    local function pickSetup()
        WowStub.state.professions = { { index = 1, name = "Blacksmithing", rank = 50, maxRank = 150, skillLine = 164 } }
        WowStub.setBag(2, 6, WowStub.item(2840, "Copper Bar", { count = 10, sell = 10, class = 7, subclass = 7 }))
        prices[WowStub.link(2840, "Copper Bar")] = 900 -- 9s each: over the guild rule's 5s cap
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = "Guild Master", rank = 0, online = true }, { name = JOLD, rank = 3, online = true } } }
        for _, m in ipairs(ns.Guild.Encode(WowStub.state.serverTime - 60, "Guild Master",
            { { profession = 202, to = JOLD, cap = 500 } })) do
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", m, "GUILD", JOLD)
        end
        ns.Guild.SetUse(true)
        ns.Routes.Add(SMITH, 164, { cap = 100000 })
    end
    local function stays(itemID)
        for _, it in ipairs(ns.MailWindow.Result().keep) do
            if it.itemID == itemID then return true end
        end
        return false
    end

    -- Operator, 2026-11-21: a bank-here row (BH: the bar this character's Blacksmithing uses) names its own
    -- rule "Here", and Alt, after it, mails it to the bank alt this visit; then the bindings, as before.
    it("row picks (mouse): me first (Here), then a click to the bank alt, the friend, the guild, and exactly that is sent", function()
        pickSetup()
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(previewed(ns)[2840], "this character's Blacksmithing comes first: the bar stays")
        assert.is_true(stays(2840))
        local pick = ns.MailWindow.PickFor(2840)
        assert.truthy(pick, "the staying row has its pick button")
        assert.equal("Here", pick:GetText(), "a bank-here row: its own rule is Here")
        pick:Click()
        assert.equal(BANK_ALT, previewed(ns)[2840], "one click: Alt, the bank alt")
        assert.equal("Alt", ns.MailWindow.PickFor(2840):GetText())
        ns.MailWindow.PickFor(2840):Click()
        assert.equal(SMITH, previewed(ns)[2840], "two clicks: the friend's binding")
        assert.equal("Friend", ns.MailWindow.PickFor(2840):GetText())
        ns.MailWindow.PickFor(2840):Click()
        assert.equal(JOLD, previewed(ns)[2840], "three clicks: the guild rule, over its 5s cap")
        assert.equal("Guild", ns.MailWindow.PickFor(2840):GetText())
        ns.MailWindow.PickFor(2840):Click()
        assert.is_nil(previewed(ns)[2840], "four: back to Here")
        assert.equal("Here", ns.MailWindow.PickFor(2840):GetText())
        ns.MailWindow.PickFor(2840):Click()
        ns.MailWindow.PickFor(2840):Click()
        ns.MailWindow.PickFor(2840):Click()
        local preview = previewed(ns)
        assert.equal(JOLD, preview[2840])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [JOLD] = true })
        ns.Fire("MAIL_CLOSED")
        assert.is_nil(ns.Routes.Picked(WowStub.link(2840, "Copper Bar")), "a pick lasts one mailbox visit")
    end)

    -- UX review U4 (2026-11-15): one D-pad stop per row. The controller picks with Square on the
    -- highlighted row (before: the D-pad reached the row's pick button and Cross pressed it).
    it("row picks (controller): Square on the highlighted row picks, then Send mails as previewed", function()
        pickSetup()
        WowStub.state.gamepadUI = true
        ns.Fire("MAIL_SHOW")
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
        local function press(name)
            WowStub.state.now = WowStub.state.now + 1
            _G[name]:Click()
            tick()
        end
        WowStub.state.activeFrame = MailFrame
        tick()
        press("MailworthyPadTriangle")
        assert.is_true(stays(2840))
        assert.equal("CLICK MailworthyPadSquare:LeftButton", WowStub.state.bindings.PAD3)
        local pick = ns.MailWindow.PickFor(2840)
        for _, c in ipairs(ns.Nav.Candidates()) do
            assert.are_not.equal(pick, c.button, "the row's pick button is not a D-pad stop of its own")
        end
        ns.Nav.Select(ns.MailWindow.RowFor(2840))
        press("MailworthyPadSquare")
        assert.equal(BANK_ALT, previewed(ns)[2840], "Square on the row: Alt, the bank alt (a bank-here row)")
        assert.equal(ns.MailWindow.RowFor(2840), ns.Nav.Current(), "the highlight follows the item to its row")
        press("MailworthyPadSquare")
        assert.equal(SMITH, previewed(ns)[2840], "Square again: the friend's binding")
        assert.equal(ns.MailWindow.RowFor(2840), ns.Nav.Current(), "the highlight follows the item to its row")
        press("MailworthyPadSquare")
        local preview = previewed(ns)
        assert.equal(JOLD, preview[2840])
        ns.Nav.Select(_G.MailworthyMailSend)
        press("MailworthyPadCross")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [JOLD] = true })
    end)

    -- Operator, 2026-11-14: "i dont yet have leather working but i plan on picking it up but its defaulting
    -- to my guild rule". A binding to yourself, made in the friends window, keeps the leather here; the
    -- guild's Leatherworking rule is left out (personal wins) and nothing goes to its leatherworker.
    it("a binding to yourself (friends window): the guild's rule for it is left out and its materials stay", function()
        local SHAM = "Sham Bie"
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = "Guild Master", rank = 0, online = true }, { name = SHAM, rank = 3, online = true } } }
        for _, m in ipairs(ns.Guild.Encode(WowStub.state.serverTime - 60, "Guild Master", { { profession = 165, to = SHAM } })) do
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", m, "GUILD", SHAM)
        end
        ns.Guild.SetUse(true)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(SHAM, previewed(ns)[2318], "the guild's rule takes the Light Leather")
        ns.RoutesUI.Show()
        _G.MailworthyFriendsAdd:Click() -- the window opens on its list (2026-11-22)
        assert.truthy(_G.MailworthyFriendsPick1:GetText():find("you", 1, true), "you are first in the list")
        _G.MailworthyFriendsPick1:Click()
        for i, o in ipairs(ns.RoutesUI.Options(ns.RoutesUI.Picked())) do
            if o.id == 165 then _G["MailworthyFriendsProfession" .. i]:Click() end
        end
        assert.is_true(ns.Routes.IsMe(ns.Routes.List()[1].to), "bound to this character")
        ns.RoutesUI.Frame():Hide()
        ns.MailWindow.Refresh()
        local preview = previewed(ns)
        assert.is_nil(preview[2318], "the leather stays with you")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("row picks never move a hard keep or a pin", function()
        pickSetup()
        ns.Locks.ToggleItem(2840, WowStub.link(2840, "Copper Bar"), "spec")
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(ns.MailWindow.PickFor(2840), "a locked item has no pick button")
        assert.is_nil(ns.MailWindow.PickFor(6125), "nor does soulbound gear")
        ns.Locks.ToggleItem(2840, WowStub.link(2840, "Copper Bar"), "spec")
        ns.Pins.Set(2840, WowStub.link(2840, "Copper Bar"), ns.Pins.BANK, "spec")
        if ns.PinWarning.Frame():IsShown() then _G.MailworthyPinWarningOK:Click() end
        ns.MailWindow.Refresh()
        assert.is_nil(ns.MailWindow.PickFor(2840), "a pinned item has no pick button")
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2840], "the pin wins")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    -- Operator, 2026-11-21: what this character banks itself (BH: its profession still uses it, or a bank-here
    -- pin) keeps its row, and the row's pick button (the same as Me / Friend / Guild) goes Here -> Alt: Alt
    -- mails it to the bank alt this visit, as a bank pin would.
    local function bankHereSetup()
        WowStub.state.professions = { { index = 1, name = "Blacksmithing", rank = 50, maxRank = 150, skillLine = 164 } }
        WowStub.setBag(2, 6, WowStub.item(2840, "Copper Bar", { count = 10, sell = 10, class = 7, subclass = 7 }))
        prices[WowStub.link(2840, "Copper Bar")] = 900
        ns.Pins.SetMode(ns.Pins.HERE, "spec")
        ns.Pins.Set(2318, WowStub.link(2318, "Light Leather"), ns.Pins.BANK, "spec") -- bank here: the setting
    end

    it("Here / Alt (mouse): a profession's material and a bank-here pin go to the bank alt on Alt, as previewed", function()
        bankHereSetup()
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[2840], "Blacksmithing keeps the bar: it stays, to bank here")
        assert.is_nil(preview[2318], "the bank-here pin stays")
        assert.is_true(stays(2840))
        assert.is_true(stays(2318))
        assert.equal("Here", ns.MailWindow.PickFor(2840):GetText(), "the row's own rule is Here")
        assert.equal("Here", ns.MailWindow.PickFor(2318):GetText())
        ns.MailWindow.PickFor(2840):Click()
        ns.MailWindow.PickFor(2318):Click()
        assert.equal("Alt", ns.MailWindow.PickFor(2840):GetText())
        assert.equal("Alt", ns.MailWindow.PickFor(2318):GetText())
        preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2840], "Alt: the bar to the bank alt")
        assert.equal(BANK_ALT, preview[2318], "Alt: the pinned leather to the bank alt")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        ns.Fire("MAIL_CLOSED")
        assert.is_nil(ns.Routes.Picked(WowStub.link(2840, "Copper Bar")), "Alt lasts one mailbox visit")
    end)

    it("Here / Alt (controller) without Auctionator: Square on a bank-here pin's row, then Send mails as previewed", function()
        _G.Auctionator = nil
        ns.Pins.SetMode(ns.Pins.HERE, "spec")
        ns.Pins.Set(6515, WowStub.link(6515, "Spellbinder Robes"), ns.Pins.BANK, "spec") -- a green: like a bank pin
        WowStub.state.gamepadUI = true
        ns.Fire("MAIL_SHOW")
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
        local function press(name)
            WowStub.state.now = WowStub.state.now + 1
            _G[name]:Click()
            tick()
        end
        WowStub.state.activeFrame = MailFrame
        tick()
        press("MailworthyPadTriangle")
        assert.is_true(stays(6515), "the pinned green stays, to bank here")
        ns.Nav.Select(ns.MailWindow.RowFor(6515))
        press("MailworthyPadSquare")
        assert.equal(BANK_ALT, previewed(ns)[6515], "Square on the row: Alt, the bank alt")
        assert.equal(ns.MailWindow.RowFor(6515), ns.Nav.Current(), "the highlight follows the item to its row")
        local preview = previewed(ns)
        assert.is_nil(preview[6125], "soulbound gear still stays")
        ns.Nav.Select(_G.MailworthyMailSend)
        press("MailworthyPadCross")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("Here / Alt: no Alt with the bank alt skipped or on the bank alt, nor on a locked item; Alt still sends as shown", function()
        bankHereSetup()
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.truthy(ns.MailWindow.PickFor(2840))
        ns.Locks.ToggleItem(2840, WowStub.link(2840, "Copper Bar"), "spec")
        assert.is_nil(ns.MailWindow.PickFor(2840), "a locked item has no pick button")
        ns.Locks.ToggleItem(2840, WowStub.link(2840, "Copper Bar"), "spec")
        ns.MailWindow.PickFor(2840):Click()
        assert.equal(BANK_ALT, previewed(ns)[2840])
        _G.MailworthyMailSkipBankAlt:Click()
        assert.is_nil(ns.MailWindow.PickFor(2840), "the bank alt skipped: no Alt, and no binding takes it")
        assert.is_nil(previewed(ns)[2840], "the Alt pick stays in the bags with the rest of the share")
        _G.MailworthyMailSkipBankAlt:Click()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2840], "undone: Alt again")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        ns.Fire("MAIL_CLOSED")
        ns.Config.SetBankAltHere()
        mailbox()
        ns.MailWindow.Show("send")
        assert.is_nil(ns.MailWindow.PickFor(2840), "on the bank alt: Here is the bank, no Alt")
        assert.is_nil(ns.MailWindow.PickFor(2318))
        assert.is_nil(previewed(ns)[2840])
    end)

    it("a guild template turned off in one press: only the bank alt gets mail", function()
        guildTemplate()
        ns.Guild.SetUse(true)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(BOB, previewed(ns)[10940])
        _G.MailworthyMailGuildRules:Click() -- "Guild rules: on" -> off
        local preview = previewed(ns)
        assert.is_nil(preview[10940])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    --- What this character took out of the mailbox (the mail ledger records each take): MAIN mailed
    --- it the Ore 1 stack; BOB the Wool Cloth, and the locked Silver Ore and the quest's Crisp Spider
    --- Meat, which must stay whatever Return to sender says.
    local MAIN = "Mainly Mains"
    local function taken()
        local function mail(from, items)
            local list = {}
            for _, it in ipairs(items) do list[#list + 1] = { itemID = it[1], name = it[2], count = it[3] } end
            WowStub.state.inbox = { { sender = from, subject = "for you", daysLeft = 29.9, items = list } }
            for a, it in ipairs(items) do
                TakeInboxItem(1, a)
                ns.Fire("MAIL_SUCCESS", it[1])
            end
        end
        ns.Fire("MAIL_SHOW")
        mail(MAIN, { { 3001, "Ore 1", 5 } })
        mail(BOB, { { 2592, "Wool Cloth", 20 }, { 2775, "Silver Ore", 5 }, { 1081, "Crisp Spider Meat", 5 } })
        WowStub.state.inbox = {}
        WowStub.runTimers(2)
    end

    --- Every return recipient is shown before Send (operator, 2026-11-08: "any new recipient should be
    --- shown even if its a return to sender"): a "To:" line each.
    local function assertReturnsShown()
        local lines = table.concat(ns.MailWindow.Texts().to, "\n")
        for _, item in ipairs(ns.MailWindow.Result().mail) do
            if item.result.route == "return" then
                assert.truthy(lines:find(item.result.to, 1, true), item.result.to .. " has no To: line")
            end
        end
    end

    --- Every mail that went back carries the return subject (Mailer.Subject, Mailer.RETURN_WHAT).
    local function assertReturnSubjects(to)
        for _, mail in ipairs(WowStub.state.sent) do
            if to[mail.name] then
                assert.truthy(mail.subject:find("returned to you", 1, true), mail.subject)
            end
        end
    end

    it("Return to sender (mouse): what others mailed goes back to them, hard keeps stay, the bank alt gets the rest", function()
        -- operator, 2026-11-08: "a button that just allows me to 'queue up' a return to sender list ...
        -- available to everyone, not just bank alts. clicking it again returns it to normal mode"
        taken()
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(BANK_ALT, previewed(ns)[2592], "off: the Wool Cloth goes the usual way")
        _G.MailworthyMailReturn:Click()
        assert.is_true(ns.Widgets.IsToggled(_G.MailworthyMailReturn), "the toggle is lit while on")
        local preview = previewed(ns)
        assert.equal(BOB, preview[2592])
        assert.equal(MAIN, preview[3001])
        assert.equal(BANK_ALT, preview[6515], "what nobody mailed still goes to the bank alt")
        assert.is_nil(preview[2775], "a locked item stays, Return to sender or not")
        assert.is_nil(preview[1081], "what a quest needs stays")
        assertReturnsShown()
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true, [MAIN] = true })
        assertReturnSubjects({ [BOB] = true, [MAIN] = true })
        ns.Fire("MAIL_CLOSED")
        assert.is_false(ns.Returns.On(), "off again at the next visit")
    end)

    it("Return to sender and a row pick: what goes back has no pick button, and goes back", function()
        taken()
        ns.Routes.Add("Ann Other", 197) -- a Tailoring binding that would take the Wool Cloth
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.truthy(ns.MailWindow.PickFor(2592), "off: the Wool Cloth's row can be picked")
        _G.MailworthyMailReturn:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[2592], "on: it goes back to Bob")
        assert.is_nil(ns.MailWindow.PickFor(2592), "Return to sender wins: no pick button on it")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true, [MAIN] = true })
    end)

    it("Return to sender and a bank pin: Return to sender wins, the pinned item goes back to who mailed it", function()
        -- operator, 2026-11-13: "return to sender should win" (Codex review asked which wins).
        taken()
        ns.Pins.Set(2592, WowStub.link(2592, "Wool Cloth"), ns.Pins.BANK, "spec") -- Bob mailed it
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(BANK_ALT, previewed(ns)[2592], "Return to sender off: the pin sends it to the bank alt")
        _G.MailworthyMailReturn:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[2592], "on: back to Bob, pinned or not")
        assert.equal(MAIN, preview[3001])
        assertReturnsShown()
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true, [MAIN] = true })
        assertReturnSubjects({ [BOB] = true, [MAIN] = true })
    end)

    it("Return to sender and a bank-here pin: Return to sender still wins", function()
        -- Operator, 2026-11-13: "Return wins" for a bank-here pin too.
        taken()
        ns.Pins.Set(2592, WowStub.link(2592, "Wool Cloth"), ns.Pins.BANK, "spec") -- Bob mailed it
        ns.Pins.SetMode(ns.Pins.HERE, "spec")
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(previewed(ns)[2592], "Return to sender off: the pin keeps it here")
        _G.MailworthyMailReturn:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[2592], "on: back to Bob, pinned or not")
        assertReturnsShown()
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true, [MAIN] = true })
    end)

    it("Return to sender and a vendor pin: Return to sender still wins, like over every pin", function()
        taken()
        ns.Pins.Set(2592, WowStub.link(2592, "Wool Cloth"), ns.Pins.VENDOR, "spec") -- Bob mailed it
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(previewed(ns)[2592], "Return to sender off: the vendor pin keeps it")
        _G.MailworthyMailReturn:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[2592], "on: back to Bob, pinned or not")
        assertReturnsShown()
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true, [MAIN] = true })
    end)

    it("Return to sender pressed twice: back to normal, nothing goes back", function()
        taken()
        mailbox()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailReturn:Click()
        _G.MailworthyMailReturn:Click()
        assert.is_false(ns.Widgets.IsToggled(_G.MailworthyMailReturn))
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2592])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("Return to sender on the bank alt (controller): only the senders get mail, its own share stays", function()
        -- operator, 2026-11-08: "mailworthy bank alt view should still allow mail automation, it should
        -- default to returning to sender"
        taken()
        ns.Config.SetBankAltHere()
        WowStub.state.gamepadUI = true
        mailbox()
        WowStub.state.activeFrame = MailFrame
        local watcher = _G.MailworthyPadWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
        local function press(name)
            WowStub.state.now = WowStub.state.now + 1
            _G[name]:Click()
            tick()
        end
        tick()
        press("MailworthyPadTriangle")
        assert.is_true(ns.MailWindow.Frame():IsShown(), "the bank alt's Triangle opens the window")
        assert.is_nil(next(previewed(ns)), "nothing to mail from the bank alt until Return to sender")
        local reachable = false
        for _, c in ipairs(ns.Nav.Candidates()) do reachable = reachable or c.button == _G.MailworthyMailReturn end
        assert.is_true(reachable, "Return to sender isn't a controller target")
        ns.Nav.Select(_G.MailworthyMailReturn)
        press("MailworthyPadCross")
        local preview = previewed(ns)
        assert.same({ [2592] = BOB, [3001] = MAIN }, preview)
        assertReturnsShown()
        ns.Nav.Select(_G.MailworthyMailSend)
        press("MailworthyPadCross")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BOB] = true, [MAIN] = true })
        assertReturnSubjects({ [BOB] = true, [MAIN] = true })
    end)

    --- A hunter with a bow: a priced stack of arrows (worth listing) and unpriced bullets in the bags.
    local function ammoBags()
        WowStub.equipRanged(WowStub.item(2504, "Worn Shortbow", { class = 2, subclass = 2 }))
        local arrows = WowStub.item(3030, "Razor Arrow", { count = 200, sell = 0, class = 6, subclass = 2 })
        WowStub.setBag(0, 16, arrows)
        prices[arrows.hyperlink] = 25 -- 50s a stack: clears the minimum gain
        WowStub.setBag(0, 17, WowStub.item(3033, "Solid Shot", { count = 200, sell = 0, class = 6, subclass = 3 }))
    end

    -- `kind`: the verdict's kind (Valuation.KINDS), not its wording (verdict_kinds_spec rewords them all).
    local function staysAs(itemID, kind)
        for _, item in ipairs(ns.MailWindow.Result().keep) do
            if item.itemID == itemID then return assert.equal(kind, item.result.kind) end
        end
        error("item " .. itemID .. " isn't on the Staying list")
    end

    it("ammo (mouse): the arrows the bow fires stay, bank-pinned and mailed by Bob too; the bullets go", function()
        -- operator, 2026-11-14: ammo is a hard keep, "Matching type only"
        ammoBags()
        ns.Fire("MAIL_SHOW")
        WowStub.state.inbox = { { sender = BOB, subject = "for you", daysLeft = 29.9,
            items = { { itemID = 3030, name = "Razor Arrow", count = 200 } } } }
        TakeInboxItem(1, 1)
        ns.Fire("MAIL_SUCCESS", 3030)
        WowStub.state.inbox = {}
        WowStub.runTimers(2)
        ns.Pins.Set(3030, WowStub.link(3030, "Razor Arrow"), ns.Pins.BANK, "spec")
        mailbox()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailReturn:Click()
        assert.is_true(ns.Returns.On())
        local preview = previewed(ns)
        assert.is_nil(preview[3030], "the bow's arrows stay: pinned, priced and mailed by Bob")
        staysAs(3030, "ammo")
        assert.equal(BANK_ALT, preview[3033], "a bow doesn't fire bullets: they go like any unpriced item")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    it("ammo (controller) without Auctionator: Cross on Send mails the bullets, never the bow's arrows", function()
        _G.Auctionator = nil
        ammoBags()
        WowStub.state.gamepadUI = true
        ns.Fire("MAIL_SHOW")
        mailbox()
        WowStub.state.activeFrame = MailFrame
        local watcher = _G.MailworthyPadWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
        local function press(name)
            WowStub.state.now = WowStub.state.now + 1
            _G[name]:Click()
            tick()
        end
        tick()
        press("MailworthyPadTriangle")
        local preview = previewed(ns)
        assert.is_nil(preview[3030], "white arrows the bow fires stay without a price source")
        staysAs(3030, "ammo")
        assert.equal(BANK_ALT, preview[3033], "white bullets go, as any white item without a price source")
        ns.Nav.Select(_G.MailworthyMailSend)
        press("MailworthyPadCross")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    --- The mails that went, checked against the preview (a run that was stopped or refused went
    --- only part of the way): what each carried was previewed for that recipient, and the log
    --- holds exactly those mails.
    local function assertSafeSoFar(preview, allowed, mails)
        assert.equal(mails, #WowStub.state.sent)
        local partial = {}
        for _, carried in ipairs(WowStub.state.sentItems) do
            for _, it in ipairs(carried) do partial[it.itemID] = preview[it.itemID] or "not previewed" end
        end
        if mails > 0 then return assertSafeAndComplete(ns, partial, allowed) end
        for _, e in ipairs(ns.Ledger.Store().log) do assert.are_not.equal("sent", e.dir, "logged a mail that never went") end
    end

    it("Stop mid-run (mouse): the mail on its way is counted, no later mail goes, the log holds exactly what went", function()
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        local send = _G.MailworthyMailSend
        send:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent, "the first mail is with the game")
        send:Click() -- Stop
        assert.is_true(ns.Mailer.Busy(), "it waits for the game's answer for the mail it can't call back")
        ns.Fire("MAIL_SEND_SUCCESS")
        for _ = 1, 3 do
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        assert.is_false(ns.Mailer.Busy())
        assert.equal(0, #WowStub.state.attached, "nothing left on the send tab")
        assertSafeSoFar(preview, { [BANK_ALT] = true }, 1)
        assert.truthy(ns.Mailer.Status():find("^Stopped after 1 of %d+ mail%(s%): stopped by you"), ns.Mailer.Status())
        assert.is_true(#ns.MailWindow.Result().mail > 0, "the rest is still on the list")
        -- A second press of Send mails the rest, as previewed.
        local rest = previewed(ns)
        send:Click()
        deliver(ns)
        for itemID, to in pairs(rest) do preview[itemID] = to end
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("combat with a mail on its way: the run stops, and the mail the game then confirms is in the log", function()
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent)
        ns.Fire("PLAYER_REGEN_DISABLED")
        assert.is_false(ns.Mailer.Busy())
        ns.Fire("MAIL_SEND_SUCCESS")
        for _ = 1, 3 do
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        assertSafeSoFar(preview, { [BANK_ALT] = true }, 1)
    end)

    it("Stop before the first mail leaves (controller): everything attached goes back, nothing is mailed or logged", function()
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        watcher.scripts.OnUpdate(watcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        watcher.scripts.OnUpdate(watcher, 0.2)
        local preview = previewed(ns)
        ns.Nav.Select(_G.MailworthyMailSend)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click() -- Send
        assert.is_true(ns.Mailer.Busy())
        assert.is_true(#WowStub.state.attached > 0)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click() -- Stop
        assert.is_false(ns.Mailer.Busy())
        assert.equal(0, #WowStub.state.attached)
        for _ = 1, 3 do
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        assertSafeSoFar(preview, { [BANK_ALT] = true }, 0)
    end)

    it("short on postage: Send is greyed out and nothing is sent, by the button or by the mailer itself", function()
        WowStub.state.gold = 31 -- one stack's postage; the list needs far more
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        local send = _G.MailworthyMailSend
        assert.is_false(send:IsEnabled())
        assert.truthy(tostring(send.text):find("^Postage: "), tostring(send.text))
        send:Click()
        assert.is_false(ns.Mailer.Start(ns.MailWindow.Result().mail, BANK_ALT))
        for _ = 1, 3 do
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        assertSafeSoFar(preview, { [BANK_ALT] = true }, 0)
        assert.equal(0, #WowStub.state.attached)
        -- With the money, the same list goes as previewed.
        WowStub.state.gold = 100000
        ns.Fire("PLAYER_MONEY")
        assert.is_true(send:IsEnabled())
        send:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("money that runs out mid-run: the mail being built is given back, only the mails paid for went", function()
        WowStub.state.gold = 100000
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent)
        WowStub.state.gold = 1 -- spent elsewhere while the first mail was on its way
        ns.Fire("MAIL_SEND_SUCCESS")
        for _ = 1, 3 do
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        assert.is_false(ns.Mailer.Busy())
        assert.equal(0, #WowStub.state.attached)
        assertSafeSoFar(preview, { [BANK_ALT] = true }, 1)
        assert.truthy(ns.Mailer.Status():find("postage for mail 2", 1, true), ns.Mailer.Status())
    end)

    -- The money reserve (operator, 2026-11-14: "mailworthy won't spend your last money on mailing
    -- items, you should always have a reserve of 5s"): postage never leaves less than 5s.
    local function postageOf(mail)
        local need = 0
        for _, item in ipairs(mail) do need = need + item.result.postage end
        return need
    end

    it("a 5s reserve: enough for the postage alone sends nothing; postage and 5s sends what was previewed", function()
        WowStub.state.gold = 100000
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        local need = postageOf(ns.MailWindow.Result().mail)
        assert.truthy(need > 0)
        WowStub.state.gold = need + ns.Mailer.RESERVE - 1
        ns.Fire("PLAYER_MONEY")
        local send = _G.MailworthyMailSend
        assert.is_false(send:IsEnabled())
        assert.truthy(tostring(send.text):find("^Postage: "), tostring(send.text))
        send:Click()
        assert.is_false(ns.Mailer.Start(ns.MailWindow.Result().mail, BANK_ALT))
        for _ = 1, 3 do
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        assertSafeSoFar(preview, { [BANK_ALT] = true }, 0)
        assert.equal(0, #WowStub.state.attached)
        WowStub.state.gold = need + ns.Mailer.RESERVE
        ns.Fire("PLAYER_MONEY")
        assert.is_true(send:IsEnabled())
        send:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("a 5s reserve mid-run: once a mail's postage would leave less than 5s, it is given back and the run stops", function()
        WowStub.state.gold = 100000
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent)
        -- Spent elsewhere while the first mail was on its way: enough for any postage, not for 5s on top.
        WowStub.state.gold = ns.Mailer.RESERVE + WowStub.state.postage - 1 -- one stack's postage, 1c short of 5s on top
        ns.Fire("MAIL_SEND_SUCCESS")
        for _ = 1, 3 do
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        assert.is_false(ns.Mailer.Busy())
        assert.equal(0, #WowStub.state.attached)
        assertSafeSoFar(preview, { [BANK_ALT] = true }, 1)
        assert.truthy(ns.Mailer.Status():find("postage for mail 2", 1, true), ns.Mailer.Status())
        assert.truthy(ns.Mailer.Status():find("keeps 5s", 1, true), ns.Mailer.Status())
    end)

    -- A crafter of your own (QoL pass F, 2026-11-09): the window offers a binding to a known
    -- character of this account. A new way a recipient gets added, so: only once the player
    -- pressed Bind, only as previewed after that, and never when the offer was left or declined.
    local SADIE = "Sadie Ember"
    local function ownEnchanter()
        MailworthyDB.characters[ns.Characters.Key(SADIE, "Classic Beta PvP", "Alliance")] = {
            name = SADIE, realm = "Classic Beta PvP", faction = "Alliance", class = "MAGE", level = 30,
            professions = { { name = "Enchanting", skillLine = ENCHANTING, rank = 140 } },
        }
        -- 9s: under the 10s cap the offered binding starts with (operator, 2026-11-11; it was 5g)
        prices[WowStub.link(6515, "Spellbinder Robes")] = 900
    end
    local function sentTo(name)
        local n = 0
        for _, mail in ipairs(WowStub.state.sent) do if mail.name == name then n = n + 1 end end
        return n
    end

    it("an own-crafter offer accepted (mouse): previewed to that character, then exactly that is sent", function()
        ownEnchanter()
        mailbox()
        _G.MailworthyMailButton:Click()
        local offer = ns.MailWindow.Offer()
        assert.truthy(offer, "the green robes would go to this account's enchanter")
        assert.equal(SADIE, offer.name)
        for _, to in pairs(previewed(ns)) do assert.are_not.equal(SADIE, to, "offered, not bound: nothing goes there yet") end
        _G.MailworthyMailOfferBind:Click()
        local preview = previewed(ns)
        assert.equal(SADIE, preview[6515], "the list shows the robes going to her before anything is sent")
        for _, item in ipairs(offer.items) do assert.equal(SADIE, preview[item.itemID]) end
        local toSadie = 0
        for _, to in pairs(preview) do if to == SADIE then toSadie = toSadie + 1 end end
        assert.equal(offer.count, toSadie, "Bind took what the offer said, no more")
        assert.truthy(table.concat(ns.MailWindow.Texts().to, "\n"):find(SADIE, 1, true), "named on a To: line")
        assert.is_nil(ns.MailWindow.Offer(), "bound: no second offer for the same profession")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [SADIE] = true })
        assert.is_true(sentTo(SADIE) >= 1)
    end)

    it("an own-crafter offer accepted (controller): Cross on Bind, then Send mails as previewed", function()
        ownEnchanter()
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        watcher.scripts.OnUpdate(watcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        watcher.scripts.OnUpdate(watcher, 0.2)
        assert.is_true(_G.MailworthyMailOfferBind:IsShown())
        ns.Nav.Select(_G.MailworthyMailOfferBind)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        local preview = previewed(ns)
        assert.equal(SADIE, preview[6515])
        ns.Nav.Select(_G.MailworthyMailSend)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [SADIE] = true })
    end)

    it("an own-crafter offer left alone, or declined: nothing ever goes to that character", function()
        ownEnchanter()
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.truthy(ns.MailWindow.Offer())
        local preview = previewed(ns)
        _G.MailworthyMailSend:Click() -- the offer is on screen and was not pressed
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assert.equal(0, sentTo(SADIE))
        assert.equal(0, ns.Routes.Count(), "no binding was made")
        -- Declined: gone for good for that character and profession, and still nothing goes there.
        WowStub.setBag(0, 8, WowStub.item(6515, "Spellbinder Robes", { quality = 2, sell = 300, class = 4, level = 20 }))
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.truthy(ns.MailWindow.Offer())
        _G.MailworthyMailOfferNot:Click()
        assert.is_nil(ns.MailWindow.Offer())
        assert.is_false(_G.MailworthyMailOfferBind:IsShown())
        preview = previewed(ns)
        assert.equal(BANK_ALT, preview[6515])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assert.equal(0, sentTo(SADIE))
        assert.equal(0, ns.Routes.Count())
    end)

    -- Suggested bindings (operator, 2026-11-22; docs/RECOMMENDATIONS.md): a crafter in the group is offered
    -- a short-lived binding, "While grouped", an alt "This visit". A new way a recipient gets added, so:
    -- only once pressed, only as previewed after that, never past a hard keep (the Silk Cloth in use), and
    -- gone once they leave the group or the visit is over.
    local GRACE = "Grace Thorn"
    local function tailorInGroup()
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = GRACE, level = 26, online = true, professions = { 197 }, ranks = { 80 } } } }
        WowStub.state.group = { members = { { name = GRACE, online = true } } }
        -- Linen under the 10s cap; the Wool Cloth (90s each) is over it and follows the normal rule.
        WowStub.setBag(0, 13, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10, class = 7, subclass = 5 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 40
    end
    local function countTo(preview, name)
        local n = 0
        for _, to in pairs(preview) do if to == name then n = n + 1 end end
        return n
    end

    it("a group member's suggestion taken While grouped (mouse): previewed to them, then exactly that is sent", function()
        tailorInGroup()
        mailbox()
        _G.MailworthyMailButton:Click()
        local suggestion = ns.MailWindow.Offer()
        assert.truthy(suggestion, "the linen would go to the tailor in the group")
        assert.equal(GRACE, suggestion.name)
        assert.equal("While grouped", _G.MailworthyMailOfferVisit.text)
        assert.equal(0, countTo(previewed(ns), GRACE), "suggested, not bound: nothing goes there yet")
        _G.MailworthyMailOfferVisit:Click()
        local preview = previewed(ns)
        assert.equal(GRACE, preview[2589], "the list shows the linen going to her before anything is sent")
        assert.equal(BANK_ALT, preview[2592], "the wool is over the cap: the normal rule")
        assert.is_nil(preview[4306], "the Silk Cloth in use never goes")
        assert.equal(suggestion.count, countTo(preview, GRACE), "it took what the suggestion said, no more")
        assert.truthy(table.concat(ns.MailWindow.Texts().to, "\n"):find(GRACE, 1, true), "named on a To: line")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [GRACE] = true })
        assert.is_true(sentTo(GRACE) >= 1)
        assert.equal(0, ns.Routes.Count() - #ns.Routes.Temp(), "nothing saved: it lasts while grouped")
    end)

    it("a group member's suggestion taken While grouped (controller): Cross on it, then Send mails as previewed", function()
        tailorInGroup()
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        watcher.scripts.OnUpdate(watcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        watcher.scripts.OnUpdate(watcher, 0.2)
        assert.is_true(_G.MailworthyMailOfferVisit:IsShown())
        ns.Nav.Select(_G.MailworthyMailOfferVisit)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        local preview = previewed(ns)
        assert.equal(GRACE, preview[2589])
        ns.Nav.Select(_G.MailworthyMailSend)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [GRACE] = true })
    end)

    it("a While grouped binding ends when they leave the group: nothing goes to them after", function()
        tailorInGroup()
        mailbox()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailOfferVisit:Click()
        assert.equal(GRACE, previewed(ns)[2589])
        WowStub.state.group = nil -- she left before Send
        ns.Fire("GROUP_ROSTER_UPDATE")
        assert.equal(0, #ns.Routes.Temp())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assert.equal(0, sentTo(GRACE), "nothing to a player no longer bound")
        ns.MailWindow.Refresh()
        assert.equal(0, countTo(previewed(ns), GRACE))
    end)

    it("a group member leaving mid-send: the run pressed finishes as previewed, then the binding ends (Codex review)", function()
        tailorInGroup()
        mailbox()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailOfferVisit:Click()
        local preview = previewed(ns)
        assert.equal(GRACE, preview[2589])
        _G.MailworthyMailSend:Click()
        assert.is_true(ns.Mailer.Busy())
        WowStub.state.group = nil
        ns.Fire("GROUP_ROSTER_UPDATE")
        assert.equal(1, #ns.Routes.Temp(), "nothing changes the list during a run")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [GRACE] = true })
        assert.equal(0, #ns.Routes.Temp(), "ended once the run was over")
        ns.MailWindow.Refresh()
        assert.equal(0, countTo(previewed(ns), GRACE))
    end)

    it("a suggestion left alone, or Not now: nothing goes to the group member", function()
        tailorInGroup()
        mailbox()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailSuggestNotNow:Click()
        assert.is_nil(ns.MailWindow.Offer())
        local preview = previewed(ns)
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assert.equal(0, sentTo(GRACE))
        assert.equal(0, ns.Routes.Count())
    end)

    it("an alt's suggestion taken This visit: sent as previewed, and over when the mailbox closes", function()
        ownEnchanter()
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal("This visit", _G.MailworthyMailOfferVisit.text)
        _G.MailworthyMailOfferVisit:Click()
        local preview = previewed(ns)
        assert.equal(SADIE, preview[6515])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [SADIE] = true })
        ns.Fire("MAIL_CLOSED")
        assert.equal(0, ns.Routes.Count(), "this visit is over: no binding left")
    end)

    -- Paybacks (operator, 2026-11-22; Paybacks.lua): something this character made that a player it owes could
    -- use (their Mailworthy's needs note: Bob's bags hold 6, this bag holds 8). A new recipient kind, so: off
    -- until the row's pick names Bob, only as previewed, never past a hard keep, nothing to Bob when left alone.
    local function paybackSetup()
        ns.Ledger.Store().players["bob surname"] = { name = BOB, received = 17400, sent = 0, inItems = {}, outItems = {}, at = 1 }
        MailworthyDB.tierCheck = { [ns.Characters.Key(ns.Characters.Current())] = { [197] = { rank = 100,
            crafts = { [5763] = { recipe = "Woolen Bag", reagents = { [2997] = 3, [2320] = 1 } } } } } }
        ns.Comms.Hear(BOB, ns.Paybacks.EncodeNeeds(BOB, ns.PlayerName(), WowStub.state.serverTime,
            { level = 24, class = "HUNTER", bags = { 6, 6, 6, 6 } }), "WHISPER")
        WowStub.setBag(0, 14, WowStub.item(5763, "Woolen Bag", { class = 1, subclass = 0, sell = 50 }))
        WowStub.state.tooltipLines[5763] = { "8 Slot Bag" }
    end
    local function pageTo(itemID) -- the bag's row may be on a later page of the Mailing list
        for _ = 1, 5 do
            if ns.MailWindow.PickFor(itemID) then return end
            _G.MailworthyMailPage:Click()
        end
    end
    local function paybackSubject()
        for _, mail in ipairs(WowStub.state.sent) do
            if mail.name == BOB then return mail.subject end
        end
    end

    it("a payback picked (mouse): previewed to the player owed, sent as previewed, its subject says so", function()
        paybackSetup()
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.are_not.equal(BOB, previewed(ns)[5763], "off until picked")
        pageTo(5763)
        local pick = ns.MailWindow.PickFor(5763)
        assert.truthy(pick, "the bag's row has the pick button")
        pick:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[5763], "picked: to Bob, in the list before anything is sent")
        assert.truthy(table.concat(ns.MailWindow.Texts().to, "\n"):find(BOB, 1, true), "named on a To: line")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
        assert.truthy(tostring(paybackSubject()):find("^Mailworthy: made for you"), tostring(paybackSubject()))
    end)

    it("a payback picked (controller): Square on the row, then Send mails as previewed", function()
        paybackSetup()
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        local function press(name)
            WowStub.state.now = WowStub.state.now + 1
            _G[name]:Click()
            watcher.scripts.OnUpdate(watcher, 0.2)
        end
        watcher.scripts.OnUpdate(watcher, 0.2)
        press("MailworthyPadTriangle")
        pageTo(5763)
        ns.Nav.Select(ns.MailWindow.RowFor(5763))
        press("MailworthyPadSquare")
        local preview = previewed(ns)
        assert.equal(BOB, preview[5763])
        ns.Nav.Select(_G.MailworthyMailSend)
        press("MailworthyPadCross")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    it("a payback left alone, or on a locked item: nothing goes to the player owed", function()
        paybackSetup()
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assert.equal(0, sentTo(BOB))
        WowStub.setBag(0, 14, WowStub.item(5763, "Woolen Bag", { class = 1, subclass = 0, sell = 50 }))
        ns.Locks.ToggleItem(5763, WowStub.link(5763, "Woolen Bag"), "spec")
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.is_nil(ns.MailWindow.PickFor(5763), "locked: no pick")
        assert.is_nil(previewed(ns)[5763])
    end)

    -- A binding's price cap and an Enchanting binding's Gear switch (operator, 2026-11-11). Neither adds
    -- a recipient: they only move an item from the friend back to the normal rule. So: what the
    -- preview shows after the change is exactly what is sent, and nobody else gets mail.
    it("a new binding starts with a 10s cap: what sells for 10s or more each follows the normal rule", function()
        -- operator, 2026-11-11: "i think 10s is a good default option to start" (it was 5g)
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        local bob = ns.Routes.Add(BOB, ENCHANTING)
        assert.equal(1000, bob.cap)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940], "3c each: under the cap, to the friend")
        assert.equal(BANK_ALT, preview[6515], "the green sells for 50s: at or above the cap, the bank alt for the AH")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    --- Dust, the fixture's robes (50s at auction, 9s disenchanted: they sell for more) and a cloak
    --- (5s at auction, 40s disenchanted: worth disenchanting), with a disenchant addon's values.
    local function gearBags()
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        local cloak = WowStub.item(6516, "Bandit Cloak", { quality = 2, sell = 206, class = 4, level = 18 })
        WowStub.setBag(2, 5, cloak)
        prices[cloak.hyperlink] = 500
        local de = { [6515] = 900, [6516] = 4000 }
        _G.DisenchantValueAPI = { GetValue = function(l) return de[tonumber(tostring(l):match("item:(%d+)"))] end }
    end

    it("an Enchanting binding's Gear switch (mouse): gear that sells for more goes the normal way, the rest to the friend", function()
        gearBags()
        ns.Routes.Add(BOB, ENCHANTING, { cap = 10000 })
        mailbox()
        _G.MailworthyMailButton:Click()
        local before = previewed(ns)
        assert.equal(BOB, before[6515], "the switch off: every green goes to the enchanter, as before")
        assert.equal(BOB, before[6516])
        ns.RoutesUI.Show()
        _G.MailworthyFriendsGear1:Click()
        local preview = previewed(ns) -- the mailbox window redrew with the press
        assert.equal(BANK_ALT, preview[6515], "the robes sell for more than they disenchant for")
        assert.equal(BOB, preview[6516], "the cloak is worth disenchanting")
        assert.equal(BOB, preview[10940], "dust goes whatever the switch says")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    it("an Enchanting binding's Gear switch (controller): Cross on the switch, then Send mails as previewed", function()
        gearBags()
        ns.Routes.Add(BOB, ENCHANTING, { cap = 10000 })
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        watcher.scripts.OnUpdate(watcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        watcher.scripts.OnUpdate(watcher, 0.2)
        ns.RoutesUI.Show(ns.MailWindow.Frame())
        watcher.scripts.OnUpdate(watcher, 0.2)
        assert.is_true(_G.MailworthyFriendsGear1:IsShown())
        ns.Nav.Select(_G.MailworthyFriendsGear1)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        assert.equal("Gear: only when disenchanting pays more", _G.MailworthyFriendsGear1:GetText())
        ns.RoutesUI.Frame():Hide()
        watcher.scripts.OnUpdate(watcher, 0.2)
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[6515])
        assert.equal(BOB, preview[6516])
        ns.Nav.Select(_G.MailworthyMailSend)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    it("a guild template whose Enchanting rule has the Gear switch on: the same, for the guild's enchanter", function()
        -- operator, 2026-11-11: "guild master sets it per rule"
        guildTemplate()
        gearBags()
        for _, m in ipairs(ns.Guild.Encode(WowStub.state.serverTime - 30, "Guild Master",
            { { profession = ENCHANTING, to = BOB, gear = "de" } })) do
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", m, "GUILD", BOB)
        end
        assert.equal("de", ns.Guild.Template().rules[1].gear)
        mailbox()
        _G.MailworthyMailButton:Click()
        for _, to in pairs(previewed(ns)) do assert.equal(BANK_ALT, to, "not turned on: nothing goes to the guild") end
        ns.Guild.SetUse(true)
        ns.MailWindow.Refresh()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[6515], "the robes sell for more than they disenchant for")
        assert.equal(BOB, preview[6516])
        assert.equal(BOB, preview[10940])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
        assertGuildCounted({ [BOB] = true })
    end)

    -- Another addon's author, 2026-11-20: since a client patch GetRealmName() returned "". The bank
    -- alt and the bindings are saved per realm, so a blank name must neither lose them nor let two
    -- realms share them (Characters.Realm).
    it("the game gives no realm name (mouse): the saved bank alt still gets the mail, as previewed", function()
        for _, blank in ipairs({ "", false }) do
            WowStub.state.realm = blank or nil
            assert.equal(BANK_ALT, ns.Config.BankAlt(), "the bank alt saved under the realm's name is still found")
        end
        ns.Fire("PLAYER_LOGIN") -- a login with no realm name
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2770])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assert.is_nil(MailworthyDB.bankAlts["|Alliance"], "nothing saved under a blank realm")
        assert.is_nil(MailworthyDB.bankAlts["nil|Alliance"])
    end)

    it("no realm name on data an older build saved (controller): the realm comes from the account's characters", function()
        MailworthyCharDB.realm, MailworthyDB.realmIDs = nil, nil -- v0.44.1 and older saved neither
        WowStub.state.realm = ""
        WowStub.state.guid = "Player-91-0ABCDEF0"
        ns.Fire("PLAYER_LOGIN")
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        mailbox()
        local watcher = _G.MailworthyPadWatcher
        watcher.scripts.OnUpdate(watcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        watcher.scripts.OnUpdate(watcher, 0.2)
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2770], "the bank alt of the realm this character is recorded on")
        ns.Nav.Select(_G.MailworthyMailSend)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("no realm name on a character never seen: a bank alt of one realm is never used on another", function()
        -- Before, every unnamed realm shared the key "|Alliance": a bank alt picked on one was mailed
        -- to on the other, where that name may be a stranger.
        local function newCharacter(name, guid)
            MailworthyCharDB.realm = nil -- its own SavedVariables: never seen on any realm
            WowStub.state.name, WowStub.state.realm, WowStub.state.guid = name, "", guid
            ns.Fire("PLAYER_LOGIN")
        end
        newCharacter("New Here", "Player-77-0ABCDEF0") -- a server this account never saw with a name
        assert.is_nil(ns.Config.BankAlt(), "the known realm's bank alt is not this realm's")
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.same({}, previewed(ns), "no bank alt: its share stays")
        assert.is_false(_G.MailworthyMailSend:IsEnabled())
        ns.Fire("MAIL_CLOSED")
        ns.Config.SetBankAlt("Stranger Elsewhere") -- picked on the unnamed realm 77
        newCharacter("New There", "Player-78-0ABCDEF0") -- another unnamed realm
        assert.is_nil(ns.Config.BankAlt(), "realm 77's bank alt is never realm 78's")
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.same({}, previewed(ns))
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent, "nothing was mailed")
        -- A new character on the server the account knows by name finds that realm's bank alt.
        ns.Fire("MAIL_CLOSED")
        WowStub.state.name, WowStub.state.realm, WowStub.state.guid = "Rettana Quilwrit", "Classic Beta PvP", "Player-91-0ABCDEF0"
        ns.Fire("PLAYER_LOGIN")
        newCharacter("New Sibling", "Player-91-0ABCDEF0")
        assert.equal(BANK_ALT, ns.Config.BankAlt())
    end)

    it("no realm name, ever (mouse): a new character mails to the realm's bank alt once a recorded one has logged in", function()
        -- Operator, 2026-11-20, once build 71037 was read giving "" on their client ("Yes, fix it"):
        -- the game never names the realm there, so a recorded character vouches for its server ID's
        -- realm (Characters.Realm, 4b.). Before, a new character got a placeholder realm and no bank alt.
        MailworthyCharDB.realm, MailworthyDB.realmIDs, MailworthyDB.realmServers = nil, {}, {}
        WowStub.state.realm, WowStub.state.guid = "", "Player-6935-00C3240F"
        ns.Fire("PLAYER_LOGIN") -- the recorded character, as an older build saved it
        assert.equal(BANK_ALT, ns.Config.BankAlt())
        MailworthyCharDB.realm = nil -- the new character's own saved variables
        WowStub.state.name, WowStub.state.guid = "New Here", "Player-6935-00BBBBBB"
        ns.Fire("PLAYER_LOGIN")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BANK_ALT, preview[2770], "the bank alt of the realm its server ID is on")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        -- Another server ID is another realm: nothing goes to that bank alt from there.
        ns.Fire("MAIL_CLOSED")
        MailworthyCharDB.realm = nil
        WowStub.state.name, WowStub.state.guid = "New Elsewhere", "Player-7000-00CCCCCC"
        ns.Fire("PLAYER_LOGIN")
        assert.is_nil(ns.Config.BankAlt())
    end)

    it("bags that change after the preview: Send re-reads them, and a slot that changes mid-run is skipped", function()
        local pants = function() return WowStub.item(6125, "Brawler's Pants", { bound = true, quality = 2, sell = 300, class = 4 }) end
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        WowStub.setBag(0, 8, pants()) -- before Send: the green's slot now holds a soulbound item
        preview[6515] = nil
        local plan = ns.Mailer.Plan(ns.Bags.Evaluate().mail, BANK_ALT)
        assert.is_true(#plan >= 2)
        local later = plan[#plan].stacks[1] -- a stack the last mail would carry
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent)
        WowStub.setBag(later.bag, later.slot, pants()) -- mid-run: that slot changes too
        preview[later.itemID] = nil
        ns.Fire("MAIL_SEND_SUCCESS")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assert.equal(1, ns.Mailer.state.skipped, "only the mid-run change is a skip; Send's re-read caught the first")
    end)
end)

describe("critical path: an older build's SavedVariables", function()
    -- What a player upgrading from an early alpha carries: the discovery self-test,
    -- slot locks (alpha3/alpha4), a 30-day-old mail record, and none of the tables
    -- later builds added (routes, peers, fresh, realms, tierCheck, features).
    local function oldSaved()
        return {
            db = {
                selftest = { answers = { U1 = "yes" }, log = { "old line" } },
                settings = { minGain = 500, duration = 2 },
                bankAlts = { [REALM_KEY] = BANK_ALT },
                names = { { name = BANK_ALT, realm = "Classic Beta PvP", faction = "Alliance" } },
                characters = { ["Roknua Themicrulah|Classic Beta PvP|Alliance"] = { name = BANK_ALT,
                    realm = "Classic Beta PvP", faction = "Alliance", class = "WARRIOR", level = 5 } },
                mailed = { [2770] = { at = 1700000000, route = "ah" } },
                blocked = {},
                log = {},
            },
            charDB = { lockedSlots = { ["0:4"] = true } }, -- the Silver Ore's slot
        }
    end

    it("loads, logs in, keeps the old lock, and mails", function()
        local ns = loadAddon(oldSaved())
        local prices = fillBags() -- the bags are there before login, as in game
        useAuctionator(prices)
        ns.Fire("ADDON_LOADED", "Mailworthy")
        ns.Fire("PLAYER_LOGIN")
        assert.is_true(ns.Locks.IsItemLocked(2775), "the alpha slot lock became an item lock")
        assert.is_nil(MailworthyDB.selftest, "the discovery self-test data is dropped")
        assert.equal(BANK_ALT, ns.Config.BankAlt())
        ns.Fire("MAIL_SHOW")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_not_nil(next(preview))
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assertQuiet(ns)
        local report = ns.Report.Build()
        assert.truthy(report:find(BANK_ALT, 1, true), "/mw report still builds")
        assert.is_nil(MailworthyAPI.v1.GetGuildExport(), "no guild: the export is nil, not an error")
        assert.is_nil(next(MailworthyDB.guildGiven), "nothing counted without a guild rule")
        _G.Auctionator = nil
    end)

    -- A binding saved before the Gear switch and the 10s default (2026-11-11): it has no `gear`
    -- field and its own cap. Nothing about it changes: it takes every green piece under its cap.
    it("a binding saved before the Gear switch keeps its 5g cap and still takes every green piece", function()
        local saved = oldSaved()
        saved.db.routes = { [REALM_KEY] = { { to = BOB, profession = ENCHANTING, cap = 50000, at = 1700000000 } } }
        local ns = loadAddon(saved)
        local prices = fillBags()
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        useAuctionator(prices)
        -- the robes sell for 50s and disenchant for 9s: only a binding with the switch on would leave them
        _G.DisenchantValueAPI = { GetValue = function(l) return tostring(l):find("item:6515", 1, true) and 900 or nil end }
        finally(function() _G.Auctionator, _G.DisenchantValueAPI = nil, nil end)
        ns.Fire("ADDON_LOADED", "Mailworthy")
        ns.Fire("PLAYER_LOGIN")
        local binding = ns.Routes.List()[1]
        assert.equal(50000, binding.cap, "a saved binding keeps the cap it has")
        assert.is_nil(binding.gear, "and the switch is off")
        ns.Fire("MAIL_SHOW")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940])
        assert.equal(BOB, preview[6515], "under its 5g cap, the switch off: to the enchanter, as before")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
        assertQuiet(ns)
    end)

    -- A guild template taken by a build from before the Gear switch: it stored the Enchanting rule's
    -- cap as it travelled (odd = the switch on, Guild.WireCap) with no `gear` field. After the update
    -- that copy is read as the switch on (Guild.ReadSaved; Codex review, 2026-11-11).
    it("a guild template saved by a build from before the Gear switch: its odd cap is the switch, on", function()
        local saved = oldSaved()
        local rev = 1791900000 - 3600
        saved.db.guildTemplates = { [REALM_KEY .. "|Bank Of Azeroth"] = { rev = rev, from = "Guild Master", at = rev,
            use = true, rules = { { profession = ENCHANTING, to = BOB, cap = 100001 } } } }
        local ns = loadAddon(saved)
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = "Guild Master", rank = 0, online = true }, { name = BOB, rank = 3, online = true } } }
        local prices = fillBags()
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        useAuctionator(prices)
        -- the robes sell for 50s (under the rule's 10g cap) and disenchant for 9s
        _G.DisenchantValueAPI = { GetValue = function(l) return tostring(l):find("item:6515", 1, true) and 900 or nil end }
        finally(function() _G.Auctionator, _G.DisenchantValueAPI = nil, nil end)
        ns.Fire("ADDON_LOADED", "Mailworthy")
        ns.Fire("PLAYER_LOGIN")
        local rule = ns.Routes.List()[1]
        assert.equal("de", rule.gear)
        assert.equal(100000, rule.cap)
        ns.Fire("MAIL_SHOW")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940])
        assert.equal(BANK_ALT, preview[6515], "the switch is on: the robes sell for more than they disenchant for")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
        assertQuiet(ns)
    end)

    -- v0.30.0 (before guild contributions): a guild template in use and a full mail log with no
    -- guild tags. The next guild rule's mail is tagged and counted; nothing earlier is, and the
    -- count outlives the log's pruning.
    it("v0.30.0's guild template and full mail log: the next guild rule's mail is tagged and counted", function()
        local saved = oldSaved()
        local rev = 1791900000 - 3600
        saved.db.guildTemplates = { [REALM_KEY .. "|Bank Of Azeroth"] = { rev = rev, from = "Guild Master", at = rev,
            use = true, rules = { { profession = ENCHANTING, to = BOB, cap = 50000 } } } }
        local log = {}
        for i = 1, 2000 do
            log[i] = { id = i, at = rev - i, dir = "received", char = "Rettana Quilwrit", other = "Someone Else",
                subject = "old", items = { { itemID = 10940, name = "Strange Dust", count = 1 } }, money = 0, cod = 0 }
        end
        saved.db.ledger = { [REALM_KEY] = { log = log, players = {}, expect = {}, outbox = {}, nextId = 0 } }
        local ns = loadAddon(saved)
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = "Guild Master", rank = 0, online = true }, { name = BOB, rank = 3, online = true } } }
        local prices = fillBags()
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        useAuctionator(prices)
        ns.Fire("ADDON_LOADED", "Mailworthy")
        ns.Fire("PLAYER_LOGIN")
        assert.same({}, MailworthyDB.guildGiven, "the counters start empty: nothing before this build is counted")
        assert.same({}, MailworthyDB.guildHeard, "no guildmate's counts before this build")
        ns.Fire("MAIL_SHOW")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
        assert.equal(ns.Ledger.LOG_MAX, #ns.Ledger.Store().log, "the log is pruned to its cap")
        local key = REALM_KEY .. "|Bank Of Azeroth"
        local units = 0
        for i, mail in ipairs(WowStub.state.sent) do
            if mail.name == BOB then
                for _, it in ipairs(WowStub.state.sentItems[i]) do units = units + it.count end
            end
        end
        assert.is_true(units >= 20, "the Strange Dust went to Bob")
        for _, e in ipairs(ns.Ledger.Store().log) do
            if e.dir == "sent" then
                assert.equal(e.other == BOB and "guild" or nil, e.scope, "mail to " .. e.other)
                if e.other == BOB then assert.equal(rev, e.guild.rev) end
            end
        end
        assert.equal(units, MailworthyDB.guildGiven[key]["rettana quilwrit"].total)
        for i = 1, ns.Ledger.LOG_MAX do ns.Ledger.Add({ dir = "received", other = "Someone Else", subject = "new " .. i }) end
        for _, e in ipairs(ns.Ledger.Store().log) do assert.is_nil(e.guild, "the tagged mail should have been pruned") end
        assert.equal(units, MailworthyAPI.v1.GetGuildExport().givers[1].itemsAllTime, "the count outlives the log")
        assertQuiet(ns)
        _G.Auctionator = nil
    end)
end)
