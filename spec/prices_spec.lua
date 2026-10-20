-- Prices.History: Auctionator's per-day price history, read from its database
-- (not the stable API), guarded so that anything odd is "no history".
local loadAddon = require("spec.support.load_addon")

describe("prices", function()
    local P
    local link = WowStub.link(2589, "Linen Cloth")

    local function auctionator(history, keyFn)
        _G.Auctionator = {
            API = { v1 = {
                GetAuctionPriceByItemLink = function() return 40 end,
                GetAuctionAgeByItemLink = function() return 1 end,
                IsAuctionDataExactByItemLink = function() return false end,
                GetDisenchantPriceByItemLink = function() return nil end,
            } },
            Database = { GetPriceHistory = function(self, key)
                assert.equal(_G.Auctionator.Database, self, "called as a method")
                return history[key]
            end },
            Utilities = { BasicDBKeyFromLink = keyFn or function(l) return l:match("item:(%d+)") end },
        }
    end

    before_each(function() P = loadAddon().Prices end)
    after_each(function() _G.Auctionator = nil end)

    describe("History", function()
        it("is nil without Auctionator, without its database, or for an unknown item", function()
            assert.is_nil(P.History(link))
            _G.Auctionator = { API = { v1 = {} } }
            assert.is_nil(P.History(link))
            auctionator({})
            assert.is_nil(P.History(link))
        end)

        it("maps Auctionator's rows (rawDay, minSeen, maxSeen, available), newest first, 21 days at most", function()
            local rows = {}
            for d = 1, 30 do rows[#rows + 1] = { rawDay = d, minSeen = d, maxSeen = d + 5, available = d * 10, date = "x" } end
            auctionator({ ["2589"] = rows })
            local h = P.History(link)
            assert.equal(21, #h)
            assert.same({ day = 30, minSeen = 30, maxSeen = 35, available = 300 }, h[1])
            assert.same({ day = 10, minSeen = 10, maxSeen = 15, available = 100 }, h[21])
        end)

        it("drops rows without a day and survives errors in Auctionator", function()
            auctionator({ ["2589"] = { { rawDay = 3, maxSeen = 9 }, "junk", { minSeen = 1 } } })
            assert.same({ { day = 3, minSeen = nil, maxSeen = 9, available = nil } }, P.History(link))
            auctionator({}, function() error("boom") end)
            assert.is_nil(P.History(link))
            _G.Auctionator.Utilities.BasicDBKeyFromLink = function() return "2589" end
            _G.Auctionator.Database.GetPriceHistory = function() error("boom") end
            assert.is_nil(P.History(link))
        end)
    end)

    describe("Lookup", function()
        it("carries the history, the last day's quantity and a three-state exactness", function()
            auctionator({ ["2589"] = { { rawDay = 1, maxSeen = 50, available = 20 }, { rawDay = 2, maxSeen = 60, available = 900 } } })
            local p = P.Lookup(link)
            assert.equal(40, p.ah)
            assert.equal(false, p.exact)
            assert.equal(900, p.available)
            assert.equal(2, p.history[1].day)
            _G.Auctionator.API.v1.IsAuctionDataExactByItemLink = nil
            assert.is_nil(P.Lookup(link).exact, "unknown when Auctionator can't say")
            _G.Auctionator.API.v1.IsAuctionDataExactByItemLink = function() return true end
            assert.equal(true, P.Lookup(link).exact)
        end)
    end)
end)
