-- Prices.History: Auctionator's per-day price history, read from its database
-- (not the stable API), guarded so that anything odd is "no history"; the
-- disenchant value from Siz DisenchantValue's API, else Auctionator's call; TradeSkillMaster as
-- the auction source when Auctionator isn't installed (TSM_API, its public API).
local loadAddon = require("spec.support.load_addon")

describe("prices", function()
    local P, ns
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

    before_each(function()
        ns = loadAddon()
        P = ns.Prices
    end)
    after_each(function()
        _G.Auctionator, _G.DisenchantValueAPI, _G.DisenchantryDB, _G.TSM_API = nil, nil, nil, nil
        _G.TSM_APPHELPER_LOAD_DATA = nil
    end)

    describe("disenchant addon", function()
        it("is Siz DisenchantValue by its API table, Disenchantry by its saved variables, else none", function()
            assert.is_nil(P.DisenchantAddon())
            assert.is_false(P.DisenchantAddonInstalled())
            _G.DisenchantValueAPI = { GetEraValue = function() end } -- no GetValue: not the API we need
            assert.is_nil(P.DisenchantAddon())
            _G.DisenchantValueAPI = { GetValue = function() return 1000 end }
            assert.equal("Siz DisenchantValue", P.DisenchantAddon())
            assert.is_true(P.DisenchantAddonInstalled())
            _G.DisenchantValueAPI = nil
            _G.DisenchantryDB = {}
            assert.equal("Disenchantry", P.DisenchantAddon())
            assert.is_true(P.DisenchantryInstalled())
        end)

        it("values an item through GetValue, as copper per item; nil, junk or an error is no value", function()
            assert.is_nil(P.DisenchantValueOf(link))
            local asked
            _G.DisenchantValueAPI = { GetValue = function(l) asked = l return 1234 end }
            assert.equal(1234, P.DisenchantValueOf(link))
            assert.equal(link, asked)
            _G.DisenchantValueAPI.GetValue = function() return nil end
            assert.is_nil(P.DisenchantValueOf(link))
            _G.DisenchantValueAPI.GetValue = function() return "junk" end
            assert.is_nil(P.DisenchantValueOf(link))
            _G.DisenchantValueAPI.GetValue = function() error("boom") end
            assert.is_nil(P.DisenchantValueOf(link))
        end)
    end)

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

        it("drops rows without a day, ignores odd numbers and survives errors in Auctionator", function()
            auctionator({ ["2589"] = { { rawDay = 3, maxSeen = 9, minSeen = "abc", available = -4 }, "junk", { minSeen = 1 } } })
            assert.same({ { day = 3, minSeen = nil, maxSeen = 9, available = -4 } }, P.History(link))
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

        it("takes the disenchant value from Siz DisenchantValue first, else Auctionator's call", function()
            auctionator({})
            assert.is_nil(P.Lookup(link).de)
            _G.Auctionator.API.v1.GetDisenchantPriceByItemLink = function() return 300 end
            local p = P.Lookup(link)
            assert.equal(300, p.de)
            assert.equal("Auctionator", p.deSource)
            _G.DisenchantValueAPI = { GetValue = function() return 900 end }
            p = P.Lookup(link)
            assert.equal(900, p.de)
            assert.equal("DisenchantValue", p.deSource)
            _G.DisenchantValueAPI.GetValue = function() error("boom") end
            p = P.Lookup(link)
            assert.equal(300, p.de, "an erroring GetValue falls back to Auctionator")
            assert.equal("Auctionator", p.deSource)
            _G.Auctionator.API.v1.GetDisenchantPriceByItemLink = nil
            p = P.Lookup(link)
            assert.is_nil(p.de)
            assert.is_nil(p.deSource)
        end)

        it("says when the price call itself failed, so it never counts as 'no price yet'", function()
            auctionator({})
            assert.is_nil(P.Lookup(link).failed)
            _G.Auctionator.API.v1.GetAuctionPriceByItemLink = function() error("boom") end
            local p = P.Lookup(link)
            assert.is_nil(p.ah)
            assert.is_true(p.failed)
            _G.Auctionator.API.v1.GetAuctionPriceByItemLink = nil
            assert.is_nil(P.Lookup(link), "no price call at all = no price source: the no-Auctionator rule")
        end)
    end)

    describe("TradeSkillMaster", function()
        -- TSM_API as TSM 4.x's Core/API.lua has it: GetCustomPriceValue checks its arguments and
        -- raises on a bad item string or a colon call; nil + a message for no data or a bad source.
        local values, calls
        local function tsm()
            values, calls = {}, {}
            local api = {}
            api.ToItemString = function(item)
                assert.is_true(item ~= api, "never called with a colon")
                local id = type(item) == "string" and item:match("item:(%d+)")
                return id and ("i:" .. id) or nil
            end
            api.IsCustomPriceValid = function(source)
                return source == "DBMinBuyout" or source == "DBMarket" or source == "DBRecent"
            end
            api.GetCustomPriceValue = function(source, itemString)
                assert.is_true(source ~= api, "never called with a colon")
                if type(itemString) ~= "string" or not itemString:find("^[ip]:%d+") then
                    error("Invalid 'itemString' argument type (must be a TSM item string): " .. tostring(itemString))
                end
                calls[#calls + 1] = source .. " " .. itemString
                if not api.IsCustomPriceValid(source) then return nil, "'" .. source .. "' is not a valid source." end
                local v = values[source .. " " .. itemString]
                if v == nil then return nil, "No value was returned by the custom price for the specified item." end
                return v
            end
            _G.TSM_API = api
            P.ResetTSM()
            return api
        end

        -- operator, 2026-11-17 (rule changed on purpose; was: Auctionator wins, TSM never asked): with
        -- both, each item is priced by whichever has the more up-to-date data.
        it("is the source only when Auctionator isn't installed; with both, not asked while Auctionator is current", function()
            assert.is_nil(P.Source())
            assert.is_nil(P.SourceText())
            assert.is_nil(P.Lookup(link), "no source: the no-Auctionator rule")
            _G.TSM_API = { ToItemString = function() end } -- no GetCustomPriceValue: not the API we need
            assert.is_nil(P.Source())
            tsm()
            assert.equal("TSM", P.Source())
            assert.equal("TradeSkillMaster", P.SourceText())
            auctionator({})
            assert.equal("Auctionator", P.Source())
            assert.equal("Auctionator + TSM (whichever is fresher per item)", P.SourceText())
            values["DBMinBuyout i:2589"] = 9999
            local p = P.Lookup(link)
            assert.equal("Auctionator", p.source)
            assert.equal(40, p.ah, "Auctionator's day-old price, TSM's age unknown")
            assert.is_nil(p.over)
            assert.same({}, calls, "TSM isn't asked when nothing it says could win")
        end)

        it("with both: TSM prices what Auctionator has no price for, or only one past the age limit", function()
            tsm()
            auctionator({})
            local api = _G.Auctionator.API.v1
            values["DBMinBuyout i:2589"] = 55
            api.GetAuctionPriceByItemLink = function() return nil end
            api.GetAuctionAgeByItemLink = function() return nil end
            local p = P.Lookup(link)
            assert.equal("TSM", p.source)
            assert.equal(55, p.ah)
            assert.same({ ah = nil, age = nil }, p.over, "what it replaced: no Auctionator price")
            assert.is_nil(p.age, "TSM's data age unknown")
            api.GetAuctionPriceByItemLink = function() return 40 end
            api.GetAuctionAgeByItemLink = function() return 8 end
            p = P.Lookup(link)
            assert.equal("TSM", p.source, "Auctionator's price is past the 7-day limit")
            assert.same({ ah = 40, age = 8 }, p.over)
            api.GetAuctionAgeByItemLink = function() return 7 end
            assert.equal("Auctionator", P.Lookup(link).source, "at the limit it still counts")
            api.GetAuctionAgeByItemLink = function() return 8 end
            values["DBMinBuyout i:2589"] = nil
            p = P.Lookup(link)
            assert.equal("Auctionator", p.source, "TSM has no price either: Auctionator's stale one, as before")
            assert.equal(8, p.age)
            _G.TSM_API.GetCustomPriceValue = function() error("boom") end
            p = P.Lookup(link)
            assert.equal("Auctionator", p.source, "TSM failing: as if it weren't installed")
            assert.is_nil(p.failed)
            api.GetAuctionPriceByItemLink = function() error("boom") end
            tsm()
            values["DBMinBuyout i:2589"] = 55
            p = P.Lookup(link)
            assert.is_true(p.failed, "Auctionator's call failed: never priced by TSM instead (AGENTS safety)")
            assert.equal("Auctionator", p.source)
        end)

        it("Fresher: the younger price wins, a tie Auctionator's; an unknown age only beats a stale one", function()
            local t = { ah = 50 }
            assert.equal("Auctionator", P.Fresher({ ah = 40, age = 2 }, t, 2, 7), "a tie")
            assert.equal("TSM", P.Fresher({ ah = 40, age = 2 }, t, 1, 7))
            assert.equal("Auctionator", P.Fresher({ ah = 40, age = 1 }, t, 2, 7))
            assert.equal("TSM", P.Fresher({ ah = 40, age = 12 }, t, 9, 7), "both stale: the younger")
            assert.equal("Auctionator", P.Fresher({ ah = 40, age = 9 }, t, 12, 7))
            assert.equal("Auctionator", P.Fresher({ ah = 40, age = 3 }, t, nil, 7), "TSM's age unknown")
            assert.equal("TSM", P.Fresher({ ah = 40, age = 8 }, t, nil, 7))
            assert.equal("Auctionator", P.Fresher({ ah = 40 }, t, 0, 7), "Auctionator's age unknown")
            assert.equal("TSM", P.Fresher({ age = 1 }, t, 30, 7), "no Auctionator price")
            assert.equal("Auctionator", P.Fresher({ ah = 40, failed = true }, t, 0, 7))
            assert.equal("Auctionator", P.Fresher({ failed = true }, t, 0, 7), "a failed call stays failed")
            assert.equal("Auctionator", P.Fresher({}, { failed = true }, 0, 7))
            assert.equal("Auctionator", P.Fresher({}, {}, 0, 7), "TSM has no price")
        end)

        it("reads TSM's realm data age from its AppHelper loader, for this realm and faction only", function()
            tsm()
            assert.is_nil(P.TSMAge())
            assert.equal("TSM data age unknown (TSM's AppHelper loader not found)", P.TSMAgeText())
            local loaded = {}
            _G.TSM_APPHELPER_LOAD_DATA = function(tag) loaded[#loaded + 1] = tag end
            assert.is_true(P.WatchTSMData())
            assert.is_true(P.WatchTSMData(), "once")
            assert.equal("TSM data age unknown (no TSM realm data loaded)", P.TSMAgeText())
            local now = os.time()
            _G.TSM_APPHELPER_LOAD_DATA("AUCTIONDB_NON_COMMODITY_DATA", "Some Other Realm-Alliance",
                "return {downloadTime=" .. now .. ",fields={},data={}}")
            _G.TSM_APPHELPER_LOAD_DATA("AUCTIONDB_REGION_STAT", "US", "return {downloadTime=" .. now .. "}")
            assert.equal(2, #loaded, "TSM's own loader still runs")
            assert.equal("TSM data age unknown (no TSM data for this realm)", P.TSMAgeText())
            _G.TSM_APPHELPER_LOAD_DATA("AUCTIONDB_NON_COMMODITY_DATA", GetRealmName() .. "-" .. UnitFactionGroup("player"),
                "return {downloadTime=" .. (now - 3 * 86400) .. ",fields={},data={}}")
            assert.equal(3, P.TSMAge())
            assert.equal("TSM realm data 3 days old", P.TSMAgeText())
            _G.TSM_APPHELPER_LOAD_DATA("AUCTIONDB_NON_COMMODITY_DATA", GetRealmName(),
                "return {downloadTime=" .. now .. ",fields={},data={}}")
            assert.equal(0, P.TSMAge(), "the newest of the realm's blocks")
            _G.TSM_APPHELPER_LOAD_DATA("AUCTIONDB_NON_COMMODITY_DATA", GetRealmName(), "garbage")
            _G.TSM_APPHELPER_LOAD_DATA(nil, nil, nil)
            assert.equal(0, P.TSMAge(), "odd blocks are ignored")
            values["DBMinBuyout i:2589"] = 45
            assert.equal(0, P.Lookup(link).age, "TSM's price carries its data's age")
            MailworthyDB.features = { tsmAge = false }
            assert.is_nil(P.TSMAge())
            assert.is_nil(P.Lookup(link).age)
            assert.equal("TSM data age unknown (off (/mw feature tsmAge on, then /reload))", P.TSMAgeText())
        end)

        it("with both and TSM's age known: an Auctionator scan older than TSM's data loses to it", function()
            tsm()
            auctionator({})
            _G.TSM_APPHELPER_LOAD_DATA = function() end
            P.WatchTSMData()
            _G.TSM_APPHELPER_LOAD_DATA("AUCTIONDB_NON_COMMODITY_DATA", GetRealmName(),
                "return {downloadTime=" .. os.time() .. ",fields={},data={}}")
            values["DBMinBuyout i:2589"] = 55
            local p = P.Lookup(link)
            assert.equal("TSM", p.source, "Auctionator's price is a day old, TSM's from today")
            assert.equal(0, p.age)
            assert.same({ ah = 40, age = 1 }, p.over)
            _G.Auctionator.API.v1.GetAuctionAgeByItemLink = function() return 0 end
            assert.equal("Auctionator", P.Lookup(link).source, "both today: Auctionator's")
        end)

        it("TSM's price past the age limit is stale, like Auctionator's", function()
            tsm()
            _G.TSM_APPHELPER_LOAD_DATA = function() end
            P.WatchTSMData()
            _G.TSM_APPHELPER_LOAD_DATA("AUCTIONDB_NON_COMMODITY_DATA", GetRealmName(),
                "return {downloadTime=" .. (os.time() - 10 * 86400) .. ",fields={},data={}}")
            values["DBMinBuyout i:2589"] = 500
            local item = { itemID = 858, link = WowStub.link(858, "Lesser Healing Potion"), count = 1, quality = 1, vendor = 10 }
            local r = ns.Valuation.Evaluate(item, P.Lookup(link), ns.Valuation.DEFAULTS)
            assert.equal(ns.Valuation.NO_PRICE, r.route, "auction price too old: to the bank alt")
        end)

        it("prices an item by its TSM item string: the lower of DBMinBuyout and DBMarket", function()
            tsm()
            values["DBMinBuyout i:2589"], values["DBMarket i:2589"] = 45, 60
            local p = P.Lookup(link)
            assert.equal("TSM", p.source)
            assert.equal(45, p.ah)
            assert.equal(45, p.minBuyout)
            assert.equal(60, p.market)
            assert.is_nil(p.failed)
            assert.is_nil(p.age, "TSM's API gives no age")
            assert.is_nil(p.exact)
            assert.is_nil(p.history)
            assert.same({ "DBMinBuyout i:2589", "DBMarket i:2589" }, calls, "realm sources only, never region")
            values["DBMarket i:2589"] = 30
            assert.equal(30, P.Lookup(link).ah, "the market value caps a high minimum buyout")
            values["DBMinBuyout i:2589"] = nil
            assert.equal(30, P.Lookup(link).ah, "nothing listed: the market value")
            values["DBMinBuyout i:2589"], values["DBMarket i:2589"] = 52.6, nil
            assert.equal(53, P.Lookup(link).ah, "whole copper")
        end)

        it("no data is 'no price yet'; an error or a source TSM doesn't know is a failed call", function()
            local api = tsm()
            local p = P.Lookup(link)
            assert.is_nil(p.ah)
            assert.is_nil(p.failed, "TSM has no data for it: no price yet")
            api.GetCustomPriceValue = function() error("boom") end
            p = P.Lookup(link)
            assert.is_nil(p.ah)
            assert.is_true(p.failed)
            tsm()
            _G.TSM_API.IsCustomPriceValid = function() return false, "not a valid source" end
            assert.is_true(P.Lookup(link).failed, "a source TSM doesn't know (no AuctionDB) is never 'no price yet'")
            _G.TSM_API.IsCustomPriceValid = function() error("boom") end
            assert.is_true(P.Lookup(link).failed)
            _G.TSM_API.IsCustomPriceValid = nil
            assert.is_true(P.Lookup(link).failed, "can't tell no data from a bad source: failed")
            tsm()
            values["DBMarket i:2589"] = 70
            _G.TSM_API.IsCustomPriceValid = function(source) return source == "DBMarket" end
            p = P.Lookup(link)
            assert.equal(70, p.ah, "one source answering is a price")
            assert.is_nil(p.failed)
            values["DBMarket i:2589"] = -5
            assert.is_nil(P.Lookup(link).ah, "a negative value is no price")
        end)

        it("one source raising: the other's price counts; with no price there it is a failed call (Codex review)", function()
            local api = tsm()
            local real = api.GetCustomPriceValue
            api.GetCustomPriceValue = function(source, itemString)
                if source == "DBMinBuyout" then error("boom") end
                return real(source, itemString)
            end
            values["DBMarket i:2589"] = 70
            local p = P.Lookup(link)
            assert.equal(70, p.ah)
            assert.is_nil(p.failed)
            values["DBMarket i:2589"] = nil
            p = P.Lookup(link)
            assert.is_nil(p.ah)
            assert.is_true(p.failed, "no data from one, an error from the other: never 'no price yet'")
        end)

        it("asks IsCustomPriceValid again until it says yes, then keeps the yes (Codex review)", function()
            local api = tsm()
            local asked, answer = 0, false
            api.IsCustomPriceValid = function() asked = asked + 1 return answer end
            api.GetCustomPriceValue = function() return nil, "No value was returned" end -- no data
            assert.is_true(P.Lookup(link).failed)
            assert.is_true(P.Lookup(link).failed)
            assert.equal(4, asked, "a no is asked again (both sources, twice)")
            answer = true
            assert.is_nil(P.Lookup(link).failed)
            assert.is_nil(P.Lookup(link).failed)
            assert.equal(6, asked, "a yes is kept")
        end)

        it("prices the disenchant tables' materials, so a green gets a disenchant value with TSM alone", function()
            local green = { quality = 2, level = 20, classID = 4 }
            assert.is_nil(ns.Disenchant.Value(green), "no source: no value")
            local api = tsm()
            api.GetCustomPriceValue = function() return 100 end
            local de = ns.Disenchant.Value(green)
            assert.is_true(type(de) == "number" and de > 0, tostring(de))
        end)

        it("falls back to i:<item ID> when ToItemString fails, and never passes a link as the item string", function()
            local api = tsm()
            values["DBMinBuyout i:2589"] = 45
            api.ToItemString = function() error("boom") end
            assert.equal("i:2589", P.TSMItemString(link))
            assert.equal(45, P.Lookup(link).ah)
            api.ToItemString = function() return "[Linen Cloth]" end
            assert.equal("i:2589", P.TSMItemString(link))
            api.ToItemString = function() return "i:2589::r5" end
            assert.equal("i:2589::r5", P.TSMItemString(link))
            api.ToItemString = function() return nil end
            assert.is_nil(P.TSMItemString("no link"))
            assert.is_nil(P.TSMItemString(nil))
            local p = P.LookupTSM("no link")
            assert.is_nil(p.ah)
            assert.is_true(p.failed, "an item TSM can't name is never 'no price yet'")
        end)

        it("prices materials by item ID for the disenchant tables and leather conversions", function()
            tsm()
            assert.is_nil(P.MaterialPrice(10940))
            values["DBMinBuyout i:10940"] = 25
            assert.equal(25, P.MaterialPrice(10940))
            assert.is_nil(P.MaterialPrice("x"))
            auctionator({})
            _G.Auctionator.API.v1.GetAuctionPriceByItemID = function() return 11 end
            assert.equal(11, P.MaterialPrice(10940), "Auctionator's while it is the source")
            _G.Auctionator.API.v1.GetAuctionPriceByItemID = function() return nil end
            assert.equal(25, P.MaterialPrice(10940), "TSM's where Auctionator has none (2026-11-17)")
        end)

        it("prices materials by the fresher source too, as Lookup does (Codex review, 2026-11-17)", function()
            tsm()
            auctionator({})
            local api = _G.Auctionator.API.v1
            api.GetAuctionPriceByItemID = function() return 10000 end
            local age = 6
            api.GetAuctionAgeByItemID = function() return age end
            values["DBMinBuyout i:10940"] = 10
            assert.equal(10000, P.MaterialPrice(10940), "TSM's age unknown: Auctionator's 6-day price still counts")
            _G.TSM_APPHELPER_LOAD_DATA = function() end
            P.WatchTSMData()
            _G.TSM_APPHELPER_LOAD_DATA("AUCTIONDB_NON_COMMODITY_DATA", GetRealmName(),
                "return {downloadTime=" .. os.time() .. ",fields={},data={}}")
            assert.equal(10, P.MaterialPrice(10940), "TSM's data from today beats a 6-day-old scan")
            age = 0
            assert.equal(10000, P.MaterialPrice(10940), "both today: Auctionator's")
            age = 8
            _G.TSM_API.GetCustomPriceValue = function() error("boom") end
            assert.equal(10000, P.MaterialPrice(10940), "TSM failing: Auctionator's, as without TSM")
        end)
    end)

    -- Auctionator's quiet price writes (operator, 2026-11-16): its Selling tab saves the price of the
    -- item being posted with Database:SetPrice and fires no RegisterForDBUpdate callback.
    describe("price watch", function()
        it("hooks the price database's SetPrice: one callback a delay after a burst of writes", function()
            local saved = {}
            auctionator({})
            _G.Auctionator.Database.SetPrice = function(_, key, price) saved[key] = price end
            local calls = 0
            P.OnWrite(function() calls = calls + 1 end)
            assert.is_true(P.WatchWrites())
            assert.is_true(P.WatchWrites(), "once")
            _G.Auctionator.Database:SetPrice("2589", 30)
            _G.Auctionator.Database:SetPrice("g:2589:5", 30)
            assert.same({ ["2589"] = 30, ["g:2589:5"] = 30 }, saved, "Auctionator's write still happens")
            assert.equal(0, calls, "not at once")
            assert.equal(1, #WowStub.timers, "one redraw for the burst")
            WowStub.runTimers()
            assert.equal(1, calls)
            _G.Auctionator.Database:SetPrice("2589", 28)
            WowStub.runTimers()
            assert.equal(2, calls, "a later write calls again")
            assert.truthy(P.ReportLines()[1]:find("price watch: Auctionator.Database.SetPrice hooked; 3 Auctionator "
                .. "price write(s), 2 redraw(s)", 1, true), P.ReportLines()[1])
        end)

        it("before Auctionator builds its database, hooks the mixin it is copied from", function()
            local mixinCalls = 0
            _G.Auctionator = { DatabaseMixin = { SetPrice = function() mixinCalls = mixinCalls + 1 end } }
            local calls = 0
            P.OnWrite(function() calls = calls + 1 end)
            assert.is_true(P.WatchWrites())
            -- CreateAndInitFromMixin: the mixin's functions copied into the new database.
            local db = {}
            for k, v in pairs(_G.Auctionator.DatabaseMixin) do db[k] = v end
            db:SetPrice("2589", 30)
            WowStub.runTimers()
            assert.equal(1, mixinCalls)
            assert.equal(1, calls)
        end)

        it("nothing without Auctionator or its database, and nothing with the switch off", function()
            assert.is_false(P.WatchWrites())
            assert.truthy(P.ReportLines()[1]:find("price watch: Auctionator not loaded", 1, true))
            _G.Auctionator = { API = { v1 = {} } }
            assert.is_false(P.WatchWrites())
            assert.truthy(P.ReportLines()[1]:find("Auctionator loaded, but no Database.SetPrice", 1, true))
            auctionator({})
            local original = function() end
            _G.Auctionator.Database.SetPrice = original
            MailworthyDB.features.priceWatch = false
            assert.is_false(P.WatchWrites())
            assert.equal(original, _G.Auctionator.Database.SetPrice, "not hooked")
            assert.truthy(P.ReportLines()[1]:find("off (/mw feature priceWatch on", 1, true))
        end)

        it("a callback that errors is logged, and the others still run", function()
            auctionator({})
            _G.Auctionator.Database.SetPrice = function() end
            local calls = 0
            P.OnWrite(function() error("boom") end)
            P.OnWrite(function() calls = calls + 1 end)
            P.WatchWrites()
            _G.Auctionator.Database:SetPrice("2589", 30)
            WowStub.runTimers()
            assert.equal(1, calls)
            local logged = false
            for _, line in ipairs(ns.Log.Lines()) do logged = logged or line:find("price write callback", 1, true) ~= nil end
            assert.is_true(logged)
        end)
    end)
end)
