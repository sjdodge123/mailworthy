-- The bank alt view: AH / DE / V tags on bag slots recomputed with this
-- character's own prices (no postage: nothing is mailed from here), tooltip
-- lines with today's verdict and why it was mailed, and the summary window.
-- Tags are textures / font strings only: the stub errors on any field written
-- on Blizzard's bag buttons.
local loadAddon = require("spec.support.load_addon")

describe("bank alt view", function()
    local ns, combined, prices, postCalls, tooltipLines, displayed

    local function tagOf(button)
        for _, f in ipairs(button.fontStrings) do
            if f:IsShown() then return f.text end
        end
        return nil
    end

    local function hover(link, itemID)
        tooltipLines, displayed = {}, link
        postCalls[0](GameTooltip, { id = itemID })
        return table.concat(tooltipLines, "\n")
    end

    before_each(function()
        ns = loadAddon()
        prices, postCalls, tooltipLines = {}, {}, {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] and prices[l].ah end,
            GetAuctionAgeByItemLink = function() return 0 end,
            IsAuctionDataExactByItemLink = function() return true end,
            GetDisenchantPriceByItemLink = function(_, l) return prices[l] and prices[l].de end,
        } } }
        _G.DisenchantryDB = {}
        _G.Enum = { TooltipDataType = { Item = 0 } }
        _G.TooltipDataProcessor = { AddTooltipPostCall = function(t, fn) postCalls[t] = fn end }
        _G.TooltipUtil = { GetDisplayedItem = function() return "name", displayed end }
        rawset(GameTooltip, "AddLine", function(_, text) table.insert(tooltipLines, text) end)

        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        prices[WowStub.link(2770, "Copper Ore")] = { ah = 174 }
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[WowStub.link(2589, "Linen Cloth")] = { ah = 38 } -- 722 - 60 (half deposit) - 200 = 4s 62c: under 5s
        WowStub.setBag(0, 3, WowStub.item(6360, "Green Ring", { quality = 2, class = 4, sell = 50 }))
        prices[WowStub.link(6360, "Green Ring")] = { de = 1000 }
        WowStub.setBag(0, 4, WowStub.item(6948, "Hearthstone", { bound = true, sell = 0 }))
        combined = ContainerFrameCombinedBags
        combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2), WowStub.itemButton(0, 3),
            WowStub.itemButton(0, 4) }
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Rettana Quilwrit") -- this character is the bank alt
        MailworthyDB.bankAlts["Classic Beta PvP|Alliance"] = "Rettana Quilwrit"
        ns.BankAlt.Redraw()
    end)

    after_each(function()
        _G.Auctionator, _G.DisenchantryDB, _G.Enum, _G.TooltipDataProcessor, _G.TooltipUtil = nil, nil, nil, nil, nil
        rawset(GameTooltip, "AddLine", nil)
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("tags each slot with today's verdict: AH, DE, V; nothing on soulbound items", function()
        combined:UpdateItems()
        assert.equal("AH", tagOf(combined.Items[1]), "Copper Ore: 826 - 6 (half the 12c deposit), no postage, vs 25c")
        assert.equal("V", tagOf(combined.Items[2]), "Linen Cloth: gain 4s 62c, under 5s")
        assert.equal("DE", tagOf(combined.Items[3]))
        assert.is_nil(tagOf(combined.Items[4]))
    end)

    it("counts no postage on the bank alt", function()
        local item
        for _, i in ipairs(ns.BankAlt.Refresh().mail) do if i.itemID == 2770 then item = i end end
        assert.equal(0, item.result.postage)
        assert.equal(826 - 6 - 25, item.result.gain)
    end)

    it("follows a lock at once (a locked item has no tag)", function()
        ns.Locks.ToggleItem(2770, "link", "spec")
        assert.is_nil(tagOf(combined.Items[1]))
    end)

    it("not on other characters unless the setting says every character", function()
        MailworthyDB.bankAlts["Classic Beta PvP|Alliance"] = "Roknua Themicrulah"
        ns.BankAlt.Redraw()
        assert.is_nil(tagOf(combined.Items[1]))
        assert.equal("", hover(WowStub.link(2770, "Copper Ore"), 2770))
        ns.Config.Set("tagsEverywhere", true)
        ns.BankAlt.Redraw()
        assert.equal("AH", tagOf(combined.Items[1]))
    end)

    it("tooltip: today's verdict with the numbers, and why it was mailed", function()
        MailworthyDB.mailed = { [2589] = { route = "ah", gain = 821, at = WowStub.state.serverTime,
            from = "Tilda Quickfoot", to = "Rettana Quilwrit" } }
        local text = hover(WowStub.link(2589, "Linen Cloth"), 2589)
        assert.truthy(text:find("Mailworthy  |cffffffff[Vendor now]|r", 1, true), text)
        assert.truthy(text:find("Auction price today: 38c each (scanned today). After the 5% cut and the deposit "
            .. "that's under your 5s minimum gain, so sell it to a vendor (2s).", 1, true), text)
        assert.truthy(text:find("Mailed for: Auction +8s 21c, " .. date("%b %d", WowStub.state.serverTime)
            .. ", from Tilda Quickfoot", 1, true), text)
        text = hover(WowStub.link(2770, "Copper Ore"), 2770)
        assert.truthy(text:find("Auction price today: 1s 74c each (scanned today). After the 5% cut and the 24h deposit: "
            .. "7s 95c more than a vendor.", 1, true), text)
        assert.is_nil(text:find("Mailed for", 1, true), "never mailed: no such line")
    end)

    it("without Auctionator: no tags, only why it was mailed", function()
        _G.Auctionator = nil
        MailworthyDB.mailed = { [2589] = { route = "common", at = WowStub.state.serverTime, from = "Tilda Quickfoot" } }
        ns.BankAlt.Redraw()
        assert.is_nil(tagOf(combined.Items[2]))
        local text = hover(WowStub.link(2589, "Linen Cloth"), 2589)
        assert.truthy(text:find("Mailed for: Common item, ", 1, true), text)
        assert.is_nil(text:find("price today", 1, true))
    end)

    it("summary: stacks to list, items to disenchant, what's now better at a vendor", function()
        MailworthyDB.mailed = { [2589] = { route = "ah", at = WowStub.state.serverTime } }
        local s = ns.BankAlt.Summary(ns.BankAlt.Refresh())
        assert.same({ stacks = 1, items = 5, gain = 795 }, s.ah)
        assert.same({ stacks = 1, items = 1, gain = 950 }, s.de)
        assert.same({ stacks = 1, items = 20, vendor = 200, wasAuction = 1 }, s.v)
        ns.HandleSlash("summary")
        assert.is_true(MailworthySummaryFrame:IsShown())
    end)

    it("the Mailworthy button on the bank alt opens the summary; the controller drives it anywhere", function()
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.is_true(MailworthySummaryFrame:IsShown())
        assert.is_false(ns.MailWindow.Frame():IsShown())
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = nil
        MailworthyPadWatcher.scripts.OnUpdate(MailworthyPadWatcher, 0.2)
        assert.equal("CLICK MailworthyPadCircle:LeftButton", WowStub.state.bindings.PAD2)
        _G.MailworthyPadCircle:Click()
        assert.is_false(MailworthySummaryFrame:IsShown())
    end)

    it("switches: no tags and no tooltip hook when off", function()
        local ns2 = loadAddon() -- a fresh client: new bags and bag frames
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        local button = WowStub.itemButton(0, 1)
        ContainerFrameCombinedBags.Items = { button }
        ns2.HandleSlash("feature bankAltTags off")
        ns2.HandleSlash("feature tooltipLines off")
        postCalls = {}
        ns2.Fire("PLAYER_LOGIN")
        ns2.Config.SetBankAlt("Rettana Quilwrit")
        ns2.BankAlt.Redraw()
        ContainerFrameCombinedBags:UpdateItems()
        assert.is_nil(tagOf(button))
        assert.is_nil(postCalls[0])
        ns = ns2 -- after_each reads this one's log
    end)
end)

describe("vendor tags on a main after sending", function()
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
        } } }
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        prices[WowStub.link(2770, "Copper Ore")] = 174
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 40
        WowStub.setBag(0, 3, WowStub.item(4865, "Ruined Pelt", { quality = 0, count = 2, sell = 5 }))
        WowStub.setBag(0, 4, WowStub.item(6948, "Hearthstone", { bound = true, sell = 0 }))
        combined = ContainerFrameCombinedBags
        combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2), WowStub.itemButton(0, 3),
            WowStub.itemButton(0, 4) }
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah") -- this character is a main
        MailFrame:Show()
        SendMailFrame:Show()
    end)

    after_each(function() _G.Auctionator = nil end)

    local function send()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        ns.Fire("MAIL_SEND_SUCCESS")
        WowStub.runTimers()
        combined:UpdateItems()
    end

    it("no tags before sending", function()
        combined:UpdateItems()
        for _, b in ipairs(combined.Items) do assert.is_nil(tagOf(b)) end
    end)

    it("after Send: V on what a vendor pays more for, grey junk included; nothing else", function()
        send()
        assert.equal(1, #WowStub.state.sent, "the Copper Ore went")
        assert.is_nil(tagOf(combined.Items[1]), "its slot is empty now")
        assert.equal("V", tagOf(combined.Items[2]), "Linen Cloth: the window kept it for the vendor")
        assert.equal("V", tagOf(combined.Items[3]), "grey junk: no auction price, a vendor buys it")
        assert.is_nil(tagOf(combined.Items[4]), "soulbound: nothing to say")
        assert.equal("vendor", ns.BankAlt.Mode())
    end)

    it("uses the window's settings (postage included), so the tags match what it showed", function()
        send()
        local linen = ns.BankAlt.Refresh().keep[1]
        for _, item in ipairs(ns.BankAlt.Refresh().keep) do if item.itemID == 2589 then linen = item end end
        assert.equal(30, linen.result.postage)
    end)

    it("locking an item after the send removes its V at once; unlocking brings it back", function()
        send()
        assert.equal("V", tagOf(combined.Items[2]))
        ns.Locks.ToggleItem(2589, "[Linen Cloth]", "Alt+click") -- "wait, I want to keep that"
        assert.is_nil(tagOf(combined.Items[2]), "no bag update needed")
        ns.Locks.ToggleItem(2589, "[Linen Cloth]", "Alt+click")
        assert.equal("V", tagOf(combined.Items[2]))
        WowStub.state.navButton = WowStub.itemButton(0, 3)
        ns.Locks.ToggleSelectedBagSlot() -- L3 on the grey junk
        assert.is_nil(tagOf(combined.Items[3]))
    end)

    it("a send that fails turns nothing on", function()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        ns.Fire("MAIL_FAILED")
        combined:UpdateItems()
        assert.is_nil(tagOf(combined.Items[2]))
        assert.is_nil(ns.BankAlt.Mode())
    end)

    it("the tooltip says to vendor it, without 'Mailed for' (that's for the bank alt)", function()
        local postCall, lines = nil, {}
        _G.Enum = { TooltipDataType = { Item = 0 } }
        _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
        _G.TooltipUtil = { GetDisplayedItem = function() return "name", WowStub.link(2589, "Linen Cloth") end }
        ns.BankAlt.InstallTooltip()
        rawset(GameTooltip, "AddLine", function(_, text) table.insert(lines, text) end)
        send()
        MailworthyDB.mailed[2589] = { route = "ah", at = WowStub.state.serverTime, from = "Rettana Quilwrit" }
        postCall(GameTooltip, { id = 2589 })
        local text = table.concat(lines, "\n")
        assert.truthy(text:find("[Vendor now]", 1, true), text)
        assert.is_nil(text:find("Mailed for", 1, true))
        rawset(GameTooltip, "AddLine", nil)
        _G.Enum, _G.TooltipDataProcessor, _G.TooltipUtil = nil, nil, nil
    end)
end)
