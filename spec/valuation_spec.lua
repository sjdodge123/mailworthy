-- The decision rule (docs/PLAN.md): AH net (cut, 24h deposit, postage) or
-- disenchant vs vendor, minimum gain 5s and 25%; the no-Auctionator rule; and
-- every reason an item stays in the bags.
local loadAddon = require("spec.support.load_addon")

describe("valuation", function()
    local V, S

    -- 20 Linen Cloth at 10c vendor each, unless overridden.
    local function item(o)
        local t = { link = "[Linen Cloth]", itemID = 2589, count = 20, stacks = 1, quality = 1, classID = 7, vendor = 10 }
        for k, v in pairs(o or {}) do t[k] = v end
        return t
    end

    before_each(function()
        V = loadAddon().Valuation
        S = V.Settings(nil, false)
    end)

    describe("deposit", function()
        it("is floor(vendor value x 5%) x 1 / 4 / 12 for 2h / 8h / 24h (Linen Bandage x20, measured)", function()
            assert.equal(10, V.Deposit(10, 20, 1))
            assert.equal(40, V.Deposit(10, 20, 2))
            assert.equal(120, V.Deposit(10, 20, 3))
        end)

        it("rounds down before multiplying, and is 0 for items without a vendor value", function()
            assert.equal(12, V.Deposit(3, 7, 3), "floor(1.05) x 12")
            assert.equal(0, V.Deposit(0, 20, 3))
        end)

        it("defaults to the 24h listing", function()
            assert.equal(3, S.duration)
            assert.equal(120, V.Deposit(10, 20, nil))
        end)
    end)

    describe("auction house", function()
        it("PLAN's example: gain 4s 10c is under the 5s minimum, so it stays", function()
            local r = V.Evaluate(item(), { ah = 40, age = 0 }, S)
            assert.equal("keep", r.action)
            assert.equal("not worth it", r.reason)
            assert.equal(200, r.vendor)
            assert.equal(120, r.deposit)
            assert.equal(30, r.postage)
            assert.equal(760 - 120 - 30, r.ahNet)
            assert.equal(410, r.gain)
            assert.equal(500, r.threshold)
        end)

        it("mails when the gain reaches 5s", function()
            local r = V.Evaluate(item(), { ah = 60, age = 0 }, S)
            assert.equal("mail", r.action)
            assert.equal("ah", r.route)
            assert.equal(1140 - 120 - 30 - 200, r.gain)
        end)

        it("needs 25% of the vendor value too, when that's more than 5s", function()
            local sword = item({ count = 1, vendor = 10000 })
            assert.equal(2500, V.Threshold(10000, S))
            -- 1g 90s: 18050 - 6000 deposit - 30 postage = 12020, gain 20s 20c < 25s
            assert.equal("keep", V.Evaluate(sword, { ah = 19000 }, S).action)
            -- 2g: 19000 - 6000 - 30 = 12970, gain 29s 70c
            assert.equal("mail", V.Evaluate(sword, { ah = 20000 }, S).action)
        end)

        it("the 24h deposit (x12) can decide it: the same item mails with a 2h listing", function()
            local sword = item({ count = 1, vendor = 10000 })
            assert.equal("keep", V.Evaluate(sword, { ah = 15000 }, S).action)
            local short = V.Settings({ duration = 1 }, false)
            local r = V.Evaluate(sword, { ah = 15000 }, short)
            assert.equal("mail", r.action)
            assert.equal(500, r.deposit)
        end)

        it("postage is 30c per stack", function()
            assert.equal(90, V.Evaluate(item({ stacks = 3 }), { ah = 60 }, S).postage)
        end)

        it("items without a vendor value mail on their AH price alone", function()
            local r = V.Evaluate(item({ count = 1, vendor = 0 }), { ah = 600 }, S)
            assert.equal(0, r.deposit)
            assert.equal(570 - 30, r.gain)
            assert.equal("mail", r.action)
        end)

        it("ignores prices older than 7 days; an unknown age counts", function()
            local r = V.Evaluate(item(), { ah = 60, age = 8 }, S)
            assert.equal("keep", r.action)
            assert.equal("price too old (8 days)", r.reason)
            assert.equal("mail", V.Evaluate(item(), { ah = 60, age = 7 }, S).action)
            assert.equal("mail", V.Evaluate(item(), { ah = 60 }, S).action)
        end)

        it("an item Auctionator has no price for stays", function()
            local r = V.Evaluate(item(), { ah = nil }, S)
            assert.equal("keep", r.action)
            assert.equal("no price", r.reason)
        end)
    end)

    describe("disenchant", function()
        local green
        before_each(function()
            green = item({ count = 1, quality = 2, classID = 4, vendor = 50 })
            S = V.Settings(nil, true)
        end)

        it("is compared only when on, for uncommon+ armor and weapons", function()
            assert.is_true(V.CanDisenchant(green))
            assert.is_true(V.CanDisenchant(item({ quality = 3, classID = 2 })))
            assert.is_false(V.CanDisenchant(item({ quality = 1, classID = 4 })), "white gear")
            assert.is_false(V.CanDisenchant(item({ quality = 2, classID = 7 })), "trade goods")
            local r = V.Evaluate(green, { de = 1000 }, S)
            assert.equal("mail", r.action)
            assert.equal("de", r.route)
            assert.equal(1000 - 30, r.deNet)
            assert.equal(920, r.gain)
            S.disenchant = false
            assert.equal("no price", V.Evaluate(green, { de = 1000 }, S).reason)
        end)

        it("the better of AH and disenchant wins", function()
            -- AH: 950 - floor(2.5) x 12 - 30 = 896; DE: 1970
            assert.equal("de", V.Evaluate(green, { ah = 1000, de = 2000 }, S).route)
            -- AH: 2850 - 24 - 30 = 2796; DE: 970
            assert.equal("ah", V.Evaluate(green, { ah = 3000, de = 1000 }, S).route)
        end)
    end)

    describe("without Auctionator", function()
        it("mails plain white items and keeps grey junk and uncommon or better", function()
            local r = V.Evaluate(item(), nil, S)
            assert.equal("mail", r.action)
            assert.equal("common", r.route)
            assert.equal("junk (no price data)", V.Evaluate(item({ quality = 0 }), nil, S).reason)
            assert.equal("uncommon or better (no price data)", V.Evaluate(item({ quality = 2 }), nil, S).reason)
        end)
    end)

    it("keeps locked, soulbound, quest, in-use and not-yet-loaded items before looking at prices", function()
        local rich = { ah = 100000 }
        assert.equal("locked", V.Evaluate(item({ locked = true, bound = true }), rich, S).reason)
        assert.equal("soulbound", V.Evaluate(item({ bound = true }), rich, S).reason)
        assert.equal("quest item", V.Evaluate(item({ quest = true }), rich, S).reason)
        assert.equal("in use", V.Evaluate(item({ inUse = true }), rich, S).reason)
        local unloaded = item()
        unloaded.vendor = nil
        assert.equal("item info not loaded yet", V.Evaluate(unloaded, rich, S).reason)
        assert.equal("locked", V.Evaluate(item({ locked = true }), nil, S).reason, "also without Auctionator")
    end)

    describe("settings", function()
        it("defaults: 24h, 5% cut, 30c postage, 5s and 25%, 7 days", function()
            assert.same({ duration = 3, relistFactor = 1, cut = 0.05, postage = 30, minGain = 500, minGainPct = 0.25,
                maxAgeDays = 7, disenchant = false }, S)
        end)

        it("disenchant follows Disenchantry until the player sets it", function()
            assert.is_true(V.Settings(nil, true).disenchant)
            assert.is_false(V.Settings({ disenchant = false }, true).disenchant)
            assert.is_true(V.Settings({ disenchant = true }, false).disenchant)
        end)

        it("ignores unknown keys, wrong types and durations that don't exist", function()
            local s = V.Settings({ duration = 9, minGain = "lots", other = 1 }, false)
            assert.equal(3, s.duration)
            assert.equal(500, s.minGain)
            assert.is_nil(s.other)
        end)
    end)

    it("formats money", function()
        assert.equal("0c", V.Money(0))
        assert.equal("45c", V.Money(45))
        assert.equal("4s 10c", V.Money(410))
        assert.equal("1g 5c", V.Money(10005))
        assert.equal("-1s 20c", V.Money(-120))
        assert.equal("3g 20s", V.Money(32000))
    end)
end)
