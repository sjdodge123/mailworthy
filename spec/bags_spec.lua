-- Bag scan and /mw scan: stacks grouped per item, locks and game state applied,
-- prices from Auctionator (or the common-items rule without it), a report a
-- player can check by hand, and nothing attached or sent.
local loadAddon = require("spec.support.load_addon")

describe("bag scan", function()
    local ns, prices

    local function byName(list, name)
        for _, item in ipairs(list) do
            if item.link:find("[" .. name .. "]", 1, true) then return item end
        end
    end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(caller, l)
                assert.equal("Mailworthy", caller)
                return prices[l]
            end,
            GetAuctionAgeByItemLink = function() return 0 end,
            IsAuctionDataExactByItemLink = function() return true end,
            GetDisenchantPriceByItemLink = function() return nil end,
        } } }
        -- Copper Ore in two stacks, vendor 5c; AH 50c each
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 }))
        WowStub.setBag(1, 2, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        prices[WowStub.link(2770, "Copper Ore")] = 50
        -- Linen Cloth: PLAN's example, not worth it
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 40
        -- soulbound, quest, unpriced
        WowStub.setBag(0, 3, WowStub.item(6948, "Hearthstone", { bound = true, sell = 0 }))
        WowStub.setBag(0, 4, WowStub.item(1234, "Quest Thing", { quest = true }))
        WowStub.setBag(2, 1, WowStub.item(2835, "Rough Stone", { count = 10, sell = 2 }))
    end)

    after_each(function()
        _G.Auctionator = nil
        _G.DisenchantryDB = nil
    end)

    it("groups every stack of an item, and values each item once", function()
        local result = ns.Bags.Evaluate()
        local ore = byName(result.mail, "Copper Ore")
        assert.equal(25, ore.count)
        assert.equal(2, ore.stacks)
        -- 1250 x 0.95 = 1187; deposit floor(125 x 5%) x 12 = 72; postage 2 x 30
        assert.equal(1187 - 72 - 60, ore.result.ahNet)
        assert.equal(1187 - 72 - 60 - 125, ore.result.gain)
        assert.equal(1, #result.mail)
        assert.equal("not worth it", byName(result.keep, "Linen Cloth").result.reason)
        assert.equal("soulbound", byName(result.unmailable, "Hearthstone").result.reason)
        assert.equal("quest item", byName(result.unmailable, "Quest Thing").result.reason)
        assert.is_nil(byName(result.keep, "Hearthstone"), "never-mailable items aren't in the keep list")
        assert.equal("no price", byName(result.keep, "Rough Stone").result.reason)
        assert.same({ items = 25, stacks = 2, mails = 1, gain = 930, postage = 60 }, result.totals)
    end)

    it("keeps locked items (every stack) and stacks the game has locked", function()
        ns.Locks.ToggleItem(2770, "link", "spec")
        local result = ns.Bags.Evaluate()
        assert.equal(0, #result.mail)
        assert.equal("locked", byName(result.keep, "Copper Ore").result.reason)
        ns.Locks.ToggleItem(2770, "link", "spec")
        WowStub.state.bags[1][2].isLocked = true -- e.g. being moved
        result = ns.Bags.Evaluate()
        assert.equal(20, byName(result.mail, "Copper Ore").count, "the free stack still goes")
        assert.equal("in use", byName(result.keep, "Copper Ore").result.reason)
    end)

    it("without Auctionator: mails white items, keeps the rest", function()
        _G.Auctionator = nil
        WowStub.setBag(2, 2, WowStub.item(1000, "Grey Junk", { quality = 0 }))
        WowStub.setBag(2, 3, WowStub.item(1001, "Green Ring", { quality = 2, class = 4 }))
        local result = ns.Bags.Evaluate()
        assert.is_false(result.priced)
        assert.equal("common", byName(result.mail, "Copper Ore").result.route)
        assert.truthy(byName(result.mail, "Linen Cloth"))
        assert.truthy(byName(result.mail, "Rough Stone"))
        assert.equal("junk (no price data)", byName(result.keep, "Grey Junk").result.reason)
        assert.equal("uncommon or better (no price data)", byName(result.keep, "Green Ring").result.reason)
        assert.equal("soulbound", byName(result.unmailable, "Hearthstone").result.reason)
    end)

    it("uses saved settings and switches disenchant on when Disenchantry is installed", function()
        assert.is_false(ns.Bags.CurrentSettings().disenchant)
        _G.DisenchantryDB = {}
        assert.is_true(ns.Bags.CurrentSettings().disenchant)
        MailworthyDB.settings = { duration = 1, disenchant = false }
        local s = ns.Bags.CurrentSettings()
        assert.equal(1, s.duration)
        assert.is_false(s.disenchant)
        -- the 2h deposit is floor(125 x 5%) = 6
        assert.equal(6, byName(ns.Bags.Evaluate().mail, "Copper Ore").result.deposit)
    end)

    it("keeps profession tools whatever they'd sell for (v0.2.0 listed a Fishing Pole)", function()
        WowStub.setBag(2, 2, WowStub.item(2901, "Mining Pick", { sell = 2 }))
        WowStub.setBag(2, 3, WowStub.item(6365, "Strong Fishing Pole", { sell = 50, class = 2 }))
        WowStub.state.bags[2][3].subclass = 20
        prices[WowStub.link(2901, "Mining Pick")] = 100000
        prices[WowStub.link(6365, "Strong Fishing Pole")] = 100000
        local result = ns.Bags.Evaluate()
        assert.equal("profession tool", byName(result.keep, "Mining Pick").result.reason)
        assert.equal("profession tool", byName(result.keep, "Strong Fishing Pole").result.reason)
    end)

    it("shows the vendor total for items kept before pricing (v0.2.0 printed '= 0c')", function()
        ns.Locks.ToggleItem(2589, "link", "spec")
        ns.HandleSlash("scan")
        local text = ns.Report.Text()
        assert.truthy(text:find("KEEP [Linen Cloth] x20: locked - vendor 10c each = 2s", 1, true), text)
    end)

    it("a failing price call is no price, never a crash", function()
        Auctionator.API.v1.GetAuctionPriceByItemLink = function() error("boom") end
        local result = ns.Bags.Evaluate()
        assert.equal(0, #result.mail)
        assert.equal("no price", byName(result.keep, "Copper Ore").result.reason)
    end)

    it("/mw scan shows the workings in the copy box and sends nothing", function()
        ns.HandleSlash("scan")
        local text = ns.Report.Text()
        local function has(s) assert.truthy(text:find(s, 1, true), "missing: " .. s .. "\n" .. text) end
        has("prices: Auctionator")
        has("settings: 24h listing (deposit x12), AH cut 5%, postage 30c per stack, min gain 5s and 25%, "
            .. "disenchant off, max price age 7 days")
        has("total: 25 items (2 stacks) in 1 mail(s), 9s 30c more than vendoring, postage 60c")
        has("MAIL AH [Copper Ore] x25 (2 stacks): auction house - vendor 5c each = 1s 25c; AH 50c each, 0 days old; "
            .. "AH net 10s 55c (cut 5%, deposit 72c, postage 60c); gain 9s 30c (needs 5s)")
        has("KEEP [Linen Cloth] x20: not worth it - vendor 10c each = 2s; AH 40c each, 0 days old; "
            .. "AH net 6s 10c (cut 5%, deposit 1s 20c, postage 30c); gain 4s 10c (needs 5s)")
        has("NOT MAILABLE (soulbound or quest, not listed in the window): [Hearthstone] x1, [Quest Thing] x1")
        assert.same({}, WowStub.state.attached)
        assert.same({}, WowStub.state.sent)
        assert.same({}, WowStub.state.used)
        local log = table.concat(ns.Log.Lines(), "\n")
        assert.truthy(log:find("[scan] 1 to mail (2 stacks, 1 mails, gain 9s 30c), 2 kept", 1, true), log)
    end)
end)
