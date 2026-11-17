-- Price sources. Auctionator (optional) gives auction prices from its own scans;
-- Mailworthy never scans the AH itself. Disenchant values, in this order: Siz
-- DisenchantValue (optional; its documented API for other addons,
-- DisenchantValueAPI.GetValue(link) = copper per item or nil, learned from the
-- player's own disenchants), then the era disenchant tables priced with
-- Auctionator's material prices (Disenchant.lua: the same number Disenchantry's
-- tooltip shows, since Disenchantry has no API; labelled "Disenchantry" when it
-- is installed), then Auctionator's own disenchant call (never seen returning a
-- value on Forever). Vendor prices come from the item info. Confirmed on Forever
-- (Auctionator 340/341, 2026-10-13): the API.v1 calls below exist and return
-- prices after a scan (age 0, exact). Every call is guarded: a missing or failing
-- call is "no price", never a guess.
--
-- TradeSkillMaster (optional, 2026-11-08, a CurseForge request) is the other auction price
-- source: its public TSM_API (TSM 4.x Core/API.lua; TSM 4.15 ships a Forever build):
-- TSM_API.ToItemString(link) -> "i:12345", TSM_API.GetCustomPriceValue(source, itemString)
-- -> copper or nil, errorMessage (nil + message both for "no data" and for an invalid
-- source, so TSM_API.IsCustomPriceValid(source) tells them apart). Sources read: this realm's
-- AuctionDB "DBMinBuyout" (lowest buyout at TSM's last data) and "DBMarket" (its market
-- value). Never region sources: the item sells on this realm's AH. With both installed, each item
-- is priced by whichever has the more up-to-date data for it (operator, 2026-11-17: "it shouldnt be
-- a fixed rule, it should be whichever addon has the most up to date scan data"; per item; was:
-- Auctionator always, TSM never asked): Auctionator's age for that item against the age of TSM's
-- realm data (Prices.TSMAge), a tie to Auctionator (its exactness and daily history feed the rule).
-- TSM's public API gives no age: it is read from the realm data TSM's AppHelper loads (WatchTSMData).
local _, ns = ...

local Prices = {}
ns.Prices = Prices

Prices.CALLER = "Mailworthy"

local call = ns.Util.Call

--- Like call, but says whether the call happened: ok, results...
local function try(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function copper(value)
    value = tonumber(value)
    return value and value >= 0 and value or nil
end

function Prices.Auctionator()
    local api = rawget(_G, "Auctionator")
    api = type(api) == "table" and type(api.API) == "table" and api.API.v1
    return type(api) == "table" and type(api.GetAuctionPriceByItemLink) == "function" and api or nil
end

--- TradeSkillMaster's public API table (TSM_API with GetCustomPriceValue), or nil.
function Prices.TSM()
    local api = rawget(_G, "TSM_API")
    return type(api) == "table" and type(api.GetCustomPriceValue) == "function" and api or nil
end

Prices.SOURCE_NAME = { Auctionator = "Auctionator", TSM = "TradeSkillMaster" }

--- The auction price source in use: "Auctionator" (first when both are installed: TSM prices an
--- item only where its data is fresher, Prices.Lookup), "TSM", or nil.
--- Any source counts as "with Auctionator" in the AGENTS.md Safety rules: an item it has no
--- price for goes to the bank alt (2026-11-08); with none, only unlocked, tradeable white items
--- and the staple trade goods are mailed.
function Prices.Source()
    if Prices.Auctionator() then return "Auctionator" end
    if Prices.TSM() then return "TSM" end
    return nil
end

--- What to call the source in the settings, `/mw scan` and `/mw report`: "Auctionator",
--- "TradeSkillMaster", "Auctionator + TSM (whichever is fresher per item)", or nil.
function Prices.SourceText()
    local source = Prices.Source()
    if not source then return nil end
    if source == "Auctionator" and Prices.TSM() then return "Auctionator + TSM (whichever is fresher per item)" end
    return Prices.SOURCE_NAME[source]
end

-- TSM's data age (2026-11-17). TSM_API has no scan time (TSM 4.14 Core/API.lua). TSM keeps it
-- privately: TradeSkillMaster_AppHelper's AppData.lua, written by TSM's desktop app, hands each
-- block to the global TSM_APPHELPER_LOAD_DATA(tag, realmOrRegion, data), the realm's prices under
-- tag "AUCTIONDB_NON_COMMODITY_DATA" as "return {downloadTime=<unix time>,fields=...,data=...}"
-- (LibTSMApp/Source/Service/AppHelper.lua; Core/Service/AuctionDB/Core.lua keeps that time as
-- realmUpdateTime). A post-hook on that global sees the blocks when it is installed before AppHelper
-- loads: TradeSkillMaster is in our OptionalDeps, so its global exists when this file runs, and
-- AppHelper (which needs TradeSkillMaster, not us) loads after "Mailworthy" alphabetically. How
-- AppHelper calls the global is not verified (README "Beta unknowns"): without a time, TSM's age
-- is unknown and TSM prices only what Auctionator has no current price for. Switch: /mw feature tsmAge.
Prices.TSM_REALM_TAG = "AUCTIONDB_NON_COMMODITY_DATA"
local tsmData = { hooked = false, why = "TSM not loaded", times = {} } -- times: lower-case realm -> unix time

--- The hook: one AppHelper data block. Only the realm price blocks' download time is kept.
function Prices.OnTSMData(tag, realmOrRegion, data)
    if tag ~= Prices.TSM_REALM_TAG or type(realmOrRegion) ~= "string" or type(data) ~= "string" then return end
    local at = tonumber(data:sub(1, 200):match("downloadTime%s*=%s*(%d+)"))
    if not at then return end
    local key = realmOrRegion:lower()
    if not tsmData.times[key] or at > tsmData.times[key] then tsmData.times[key] = at end
end

--- Post-hook TSM_APPHELPER_LOAD_DATA (see above). Runs when this file loads; true when hooked.
function Prices.WatchTSMData()
    if tsmData.hooked then return true end
    if type(rawget(_G, "TSM_APPHELPER_LOAD_DATA")) ~= "function" then
        tsmData.why = "TSM's AppHelper loader not found"
        return false
    end
    local ok, err = pcall(hooksecurefunc, "TSM_APPHELPER_LOAD_DATA", function(...)
        pcall(Prices.OnTSMData, ...)
    end)
    if not ok then
        tsmData.why = "hook failed: " .. tostring(err)
        return false
    end
    tsmData.hooked, tsmData.why = true, "watching TSM's AppHelper data"
    return true
end

--- Auctionator's scan day for a unix time: whole days since its SCAN_DAY_0 (local midnight, Jan 1
--- 2020), the count its item ages are in, so an age from TSM compares with one from Auctionator.
function Prices.ScanDay(at)
    local a = rawget(_G, "Auctionator")
    local day0 = type(a) == "table" and type(a.Constants) == "table" and tonumber(a.Constants.SCAN_DAY_0)
        or call(time, { year = 2020, month = 1, day = 1, hour = 0 }) or 0
    return math.floor(((tonumber(at) or 0) - day0) / 86400)
end

--- This realm's TSM data time (unix) or nil, and why not.
function Prices.TSMDataTime()
    if not ns.Features.On("tsmAge") then return nil, "off (/mw feature tsmAge on, then /reload)" end
    if not tsmData.hooked then return nil, tsmData.why end
    local realm = call(GetRealmName)
    if type(realm) ~= "string" then return nil, "realm name not known yet" end
    -- TSM names a realm "Realm", or "Realm-Faction" where each faction has its own auction house.
    local faction = call(UnitFactionGroup, "player")
    local at = tsmData.times[realm:lower()]
    local own = type(faction) == "string" and tsmData.times[(realm .. "-" .. faction):lower()]
    if own and (not at or own > at) then at = own end
    if not at then return nil, next(tsmData.times) and "no TSM data for this realm" or "no TSM realm data loaded" end
    return at
end

--- Days since TSM's realm data was downloaded, in Auctionator's scan days; nil when unknown.
function Prices.TSMAge()
    local at = Prices.TSMDataTime()
    if not at then return nil end
    local now = call(time)
    if not now or at > now + 86400 then return nil end -- a time from the future: don't trust it
    return math.max(0, Prices.ScanDay(now) - Prices.ScanDay(at))
end

--- /mw report: TSM's data age, or why it isn't known (nil without TSM).
function Prices.TSMAgeText()
    if not Prices.TSM() then return nil end
    local age = Prices.TSMAge()
    if age then return string.format("TSM realm data %d day%s old", age, age == 1 and "" or "s") end
    local _, why = Prices.TSMDataTime()
    return "TSM data age unknown (" .. tostring(why) .. ")"
end

--- TSM's item string for a link ("i:12345", with its bonus / random parts when TSM keeps
--- them); falls back to "i:<item ID>" read from the link when ToItemString can't say.
function Prices.TSMItemString(link)
    local api = Prices.TSM()
    if not api or type(link) ~= "string" then return nil end
    local s = call(api.ToItemString, link)
    if type(s) == "string" and s:find("^[ip]:%d+") then return s end
    local id = link:match("item:(%d+)") or link:match("^i:(%d+)")
    return id and ("i:" .. id) or nil
end

local tsmValid = {} -- source -> true once IsCustomPriceValid said so (a "no" is asked again)

--- One TSM price source for an item string: copper, or nil; second return true when the call
--- failed (it raised, or TSM doesn't know the source), which is never "no price yet".
local function tsmValue(api, source, itemString)
    local ok, value = pcall(api.GetCustomPriceValue, source, itemString)
    if not ok then return nil, true end
    value = copper(value)
    if value ~= nil then return math.floor(value + 0.5), false end
    -- nil comes with a message both for "no data for this item" and for an unknown source:
    -- only a source TSM calls valid makes it "no price yet"; anything else is a failed call.
    if not tsmValid[source] then
        local okValid, valid = try(api.IsCustomPriceValid, source)
        tsmValid[source] = okValid and valid == true or nil
    end
    return nil, not tsmValid[source]
end

--- TSM's unit price for an item string: the lower of DBMinBuyout and DBMarket (the last data's
--- lowest buyout, capped by the market value as Auctionator's last scan is capped by its median),
--- or whichever one there is. Returns unit, failed, minBuyout, market.
function Prices.TSMUnit(itemString)
    local api = Prices.TSM()
    if not api or not itemString then return nil, true end
    local minBuyout, failedMin = tsmValue(api, "DBMinBuyout", itemString)
    local market, failedMarket = tsmValue(api, "DBMarket", itemString)
    local unit = minBuyout
    if market ~= nil and (unit == nil or market < unit) then unit = market end
    return unit, (unit == nil and (failedMin or failedMarket)) or false, minBuyout, market
end

--- Forget what IsCustomPriceValid said (specs; TSM loaded or changed later).
function Prices.ResetTSM() tsmValid = {} end

--- Siz DisenchantValue's API table (DisenchantValueAPI with GetValue), or nil.
--- Detected by the API, not the addon folder name (unverified; README "Beta unknowns").
function Prices.DisenchantValue()
    local api = rawget(_G, "DisenchantValueAPI")
    return type(api) == "table" and type(api.GetValue) == "function" and api or nil
end

--- Disenchant value per item (copper) from Siz DisenchantValue, or nil when it isn't
--- installed, can't value the item, or errors.
function Prices.DisenchantValueOf(link)
    local api = Prices.DisenchantValue()
    if not api then return nil end
    return copper(call(api.GetValue, link))
end

--- Disenchantry (CurseForge project 1704637, back since 2026-10-22): no API, so its
--- values are recomputed by Disenchant.lua; its presence switches the disenchant
--- comparison on by default and names the source.
function Prices.DisenchantryInstalled()
    local addons = rawget(_G, "C_AddOns")
    if type(addons) == "table" and call(addons.IsAddOnLoaded, "Disenchantry") then return true end
    return rawget(_G, "DisenchantryDB") ~= nil
end

--- The disenchant addon that switches the disenchant comparison on by default:
--- "Siz DisenchantValue", "Disenchantry", or nil.
function Prices.DisenchantAddon()
    if Prices.DisenchantValue() then return "Siz DisenchantValue" end
    if Prices.DisenchantryInstalled() then return "Disenchantry" end
    return nil
end

function Prices.DisenchantAddonInstalled()
    return Prices.DisenchantAddon() ~= nil
end

Prices.HISTORY_DAYS = 21 -- Auctionator's default PRICE_HISTORY_DAYS

--- Auctionator's per-day history for one link: { { day, minSeen, maxSeen, available }, ... },
--- newest first, at most HISTORY_DAYS entries; nil when there is none. minSeen / maxSeen
--- are the lowest and highest "minimum buyout" its scans saw that day, available the units
--- listed at the day's biggest scan. This is NOT Auctionator's stable API
--- (Database:GetPriceHistory, Utilities.BasicDBKeyFromLink; README "Beta unknowns"), so
--- every step is guarded and anything odd means "no history".
function Prices.History(link)
    local a = rawget(_G, "Auctionator")
    if type(a) ~= "table" or type(a.Database) ~= "table" or type(a.Utilities) ~= "table" then return nil end
    local key = call(a.Utilities.BasicDBKeyFromLink, link)
    if type(key) ~= "string" and type(key) ~= "number" then return nil end
    local rows = call(a.Database.GetPriceHistory, a.Database, key)
    if type(rows) ~= "table" then return nil end
    local history = {}
    for _, row in ipairs(rows) do
        local day = type(row) == "table" and tonumber(row.rawDay)
        if day then
            history[#history + 1] = { day = day, minSeen = copper(row.minSeen), maxSeen = copper(row.maxSeen),
                available = tonumber(row.available) }
        end
    end
    if #history == 0 then return nil end
    table.sort(history, function(x, y) return x.day > y.day end)
    while #history > Prices.HISTORY_DAYS do history[#history] = nil end
    return history
end

--- The auction price for a material by item ID (copper per unit): Auctionator's, the call
--- Disenchantry uses for its material prices (GetAuctionPriceByItemID, else the link form);
--- TradeSkillMaster's (Prices.TSMUnit) when it is the source.
function Prices.MaterialPrice(itemID)
    if not tonumber(itemID) then return nil end
    local tsmString = "i:" .. math.floor(tonumber(itemID))
    if Prices.Source() == "TSM" then return (Prices.TSMUnit(tsmString)) end
    local api = Prices.Auctionator()
    if not api then return nil end
    local id = tonumber(itemID)
    local price, age
    if type(api.GetAuctionPriceByItemID) == "function" then
        price = copper(call(api.GetAuctionPriceByItemID, Prices.CALLER, id))
        age = tonumber((call(api.GetAuctionAgeByItemID, Prices.CALLER, id)))
    else
        price = copper(call(api.GetAuctionPriceByItemLink, Prices.CALLER, "item:" .. id))
        age = tonumber((call(api.GetAuctionAgeByItemLink, Prices.CALLER, "item:" .. id)))
    end
    -- With TSM installed too, the fresher of the two, as Prices.Lookup (2026-11-17; Codex review: an old
    -- Auctionator material price beat today's TSM data in the disenchant value).
    if not Prices.TSM() then return price end
    local a, maxAge, tsmAge = { ah = price, age = age }, Prices.MaxAgeDays(), Prices.TSMAge()
    if Prices.Fresher(a, { ah = 0 }, tsmAge, maxAge) == "Auctionator" then return price end
    local unit, failed = Prices.TSMUnit(tsmString)
    if Prices.Fresher(a, { ah = unit, failed = failed or nil }, tsmAge, maxAge) == "TSM" then return unit end
    return price
end

--- Quality, item level and class of an item from its info (nil while not loaded).
function Prices.ItemFacts(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, quality, level, _, _, _, _, _, _, _, classID = call(getInfo, link)
    if name == nil then return nil end
    return { quality = tonumber(quality), level = tonumber(level), classID = tonumber(classID) }
end

--- The disenchant value of an item (copper per item) and its source: "DisenchantValue"
--- (Siz DisenchantValue's API), "Disenchantry" (the era tables priced with Auctionator,
--- Disenchantry installed), "tables" (the same without it), "Auctionator" (its own call).
function Prices.DisenchantValueFor(link)
    local de = Prices.DisenchantValueOf(link)
    if de ~= nil then return de, "DisenchantValue" end
    de = ns.Disenchant and ns.Disenchant.Value(Prices.ItemFacts(link))
    if de ~= nil then return de, Prices.DisenchantryInstalled() and "Disenchantry" or "tables" end
    local api = Prices.Auctionator()
    de = api and copper(call(api.GetDisenchantPriceByItemLink, Prices.CALLER, link)) or nil
    if de ~= nil then return de, "Auctionator" end
    return nil, nil
end

--- Auction data for one item link, or nil when there's no price source at all.
--- { ah = copper per unit (last scan's minimum buyout), failed = true when that call errored, age = days since seen, exact = true / false /
---   nil (unknown), de = copper per item, deSource = "DisenchantValue" / "Disenchantry" / "tables" / "Auctionator"
---   (Prices.DisenchantValueFor), history = Prices.History(link),
---   available = units listed at the last scanned day, source = "Auctionator" / "TSM" }; any may be nil.
--- With TradeSkillMaster as the source: ah = Prices.TSMUnit, with minBuyout and market beside
--- it; age = Prices.TSMAge (nil when unknown); exact and history are nil (its public API doesn't
--- give them). With both installed, the fresher one for this item (Prices.Fresher); when TSM's
--- wins, `over` = { ah, age } of the Auctionator price it replaced (ah nil: Auctionator had none).
function Prices.Lookup(link)
    local source = Prices.Source()
    if source == "TSM" then return Prices.LookupTSM(link) end
    local a = Prices.LookupAuctionator(link)
    if not a or not Prices.TSM() then return a end
    local maxAge, tsmAge = Prices.MaxAgeDays(), Prices.TSMAge()
    -- Don't ask TSM when nothing it says could win: Auctionator's call failed, or its price is
    -- current and at least as fresh as TSM's data.
    if Prices.Fresher(a, { ah = 0 }, tsmAge, maxAge) == "Auctionator" then return a end
    local t = Prices.LookupTSM(link)
    if Prices.Fresher(a, t, tsmAge, maxAge) == "Auctionator" then return a end
    t.over = { ah = a.ah, age = a.age }
    return t
end

--- The age limit the verdicts use (Valuation's maxAgeDays, as the player set it).
function Prices.MaxAgeDays()
    local values = ns.Config and ns.Config.Values and call(ns.Config.Values)
    return tonumber(type(values) == "table" and values.maxAgeDays)
        or (ns.Valuation and ns.Valuation.DEFAULTS.maxAgeDays) or 7
end

--- Pure: which of two lookups for one item has the more up-to-date price, "Auctionator" or "TSM".
--- `a` = Auctionator's (its age per item), `t` = TSM's, `tsmAge` = TSM's data age in days (nil:
--- unknown). Auctionator's stays when its call failed (never "no price yet"; AGENTS safety) or TSM
--- has no price (nor when TSM's call failed: then it is as if TSM weren't installed). TSM's wins
--- when Auctionator has no price; when both ages are known, the younger wins, a tie Auctionator;
--- with an age unknown, TSM's wins only over an Auctionator price past the age limit.
function Prices.Fresher(a, t, tsmAge, maxAge)
    if type(a) ~= "table" or a.failed then return "Auctionator" end
    if type(t) ~= "table" or t.failed or t.ah == nil then return "Auctionator" end
    if a.ah == nil then return "TSM" end
    local age = tonumber(a.age)
    if age ~= nil and tsmAge ~= nil then return tsmAge < age and "TSM" or "Auctionator" end
    if age ~= nil and age > (maxAge or 7) then return "TSM" end
    return "Auctionator"
end

--- Auctionator's data for one item link (Prices.Lookup's table, source "Auctionator"), or nil without it.
function Prices.LookupAuctionator(link)
    local api = Prices.Auctionator()
    if not api then return nil end
    local exact = call(api.IsAuctionDataExactByItemLink, Prices.CALLER, link)
    if exact ~= nil then exact = exact == true end
    local history = Prices.History(link)
    local ok, ah = try(api.GetAuctionPriceByItemLink, Prices.CALLER, link)
    local de, deSource = Prices.DisenchantValueFor(link)
    return {
        ah = ok and copper(ah) or nil,
        failed = not ok or nil, -- the price call itself failed: never "no price yet" (AGENTS safety)
        age = tonumber((call(api.GetAuctionAgeByItemLink, Prices.CALLER, link))),
        exact = exact,
        de = de,
        deSource = de ~= nil and deSource or nil,
        history = history,
        available = history and history[1].available or nil,
        source = "Auctionator",
    }
end

-- Auctionator's quiet price writes (operator, 2026-11-16: a green tagged DE at a 24s auction price,
-- another tagged AH at 15s, while Auctionator's own tooltip showed those prices). API.v1's
-- RegisterForDBUpdate fires only after a scan (IncrementalScan / Search PricesProcessed, FullScan
-- ScanComplete). Selecting an item in the Selling tab searches it and saves its lowest price with
-- Auctionator.Database:SetPrice, and fires nothing (Source_ModernAH/Tabs/Selling/Mixins/SaleItem.lua
-- ProcessItemResults / ProcessCommodityResults; posting and the legacy Buy list do the same), so the
-- tags kept the price from before. Read from Auctionator's source (Source/Database/Mixin.lua,
-- Source/Variables/Main.lua): its database is CreateAndInitFromMixin(Auctionator.DatabaseMixin, ...),
-- built at Auctionator's PLAYER_LOGIN, which copies the mixin's SetPrice into it. So a post-hook on
-- the database when it exists, else on the mixin (copied in when Auctionator builds it), sees every
-- write. Not Auctionator's public API: every step is guarded, a write only schedules a redraw (a full
-- scan writes thousands: one redraw WRITE_DELAY after them), and the switch is /mw feature priceWatch.
Prices.WRITE_DELAY = 0.2
local watch = { hooked = false, why = "not installed yet", writes = 0, fired = 0, pending = false, callbacks = {} }

--- Run `fn` (no arguments) once after Auctionator writes prices: WRITE_DELAY after a write, one call
--- for a burst of them.
function Prices.OnWrite(fn)
    if type(fn) == "function" then watch.callbacks[#watch.callbacks + 1] = fn end
end

local function fire()
    watch.pending = false
    watch.fired = watch.fired + 1
    for _, fn in ipairs(watch.callbacks) do
        local ok, err = pcall(fn)
        if not ok then ns.Log.Add("error", "price write callback: %s", tostring(err)) end
    end
end

--- The post-hook: Auctionator saved a price.
function Prices.OnAuctionatorWrite()
    watch.writes = watch.writes + 1
    if watch.pending then return end
    watch.pending = true
    ns.Util.After(Prices.WRITE_DELAY, fire)
end

--- Hook Auctionator's price writes (see above). True when hooked.
function Prices.WatchWrites()
    if watch.hooked then return true end
    if not ns.Features.On("priceWatch") then
        watch.why = "off (/mw feature priceWatch on, then /reload)"
        ns.Log.Add("prices", "price watch %s", watch.why)
        return false
    end
    local atr = rawget(_G, "Auctionator")
    local target, name
    if type(atr) == "table" and type(atr.Database) == "table" and type(atr.Database.SetPrice) == "function" then
        target, name = atr.Database, "Auctionator.Database"
    elseif type(atr) == "table" and type(atr.DatabaseMixin) == "table"
        and type(atr.DatabaseMixin.SetPrice) == "function" then
        target, name = atr.DatabaseMixin, "Auctionator.DatabaseMixin"
    end
    if not target then
        watch.why = type(atr) == "table" and "Auctionator loaded, but no Database.SetPrice" or "Auctionator not loaded"
        ns.Log.Add("prices", "no price watch: %s", watch.why)
        return false
    end
    local ok, err = pcall(hooksecurefunc, target, "SetPrice", function()
        local okWrite, errWrite = pcall(Prices.OnAuctionatorWrite)
        if not okWrite then ns.Log.Add("error", "price watch: %s", tostring(errWrite)) end
    end)
    if not ok then
        watch.why = "hook failed: " .. tostring(err)
        ns.Log.Add("prices", "price watch %s", watch.why)
        return false
    end
    watch.hooked, watch.why = true, name .. ".SetPrice hooked"
    ns.Log.Add("prices", "price watch: %s", watch.why)
    return true
end

--- /mw report: what to look for in game.
function Prices.ReportLines()
    local lines = {}
    local tsm = Prices.TSMAgeText()
    if tsm then
        lines[#lines + 1] = "TSM: " .. tsm .. (Prices.Auctionator() and ("; with Auctionator, each item is priced by "
            .. "the fresher of the two (check: /mw scan names TSM on items Auctionator has no current price for)") or "")
    end
    lines[#lines + 1] = string.format("price watch: %s; %d Auctionator price write(s), %d redraw(s) (check: at the auction house, "
        .. "select an item in Auctionator's Selling tab: its tag and Mailworthy's tooltip line follow the price "
        .. "Auctionator's tooltip shows)", watch.why, watch.writes, watch.fired)
    return lines
end

ns.On("PLAYER_LOGIN", function() Prices.WatchWrites() end)
Prices.WatchTSMData() -- now, before TSM's AppHelper loads its data (see Prices.TSMDataTime)

--- Prices.Lookup with TradeSkillMaster as the source (nil without TSM).
function Prices.LookupTSM(link)
    if not Prices.TSM() then return nil end
    local unit, failed, minBuyout, market = Prices.TSMUnit(Prices.TSMItemString(link))
    local de, deSource = Prices.DisenchantValueFor(link)
    return {
        ah = unit,
        failed = failed or nil, -- the price call itself failed: never "no price yet" (AGENTS safety)
        age = unit ~= nil and Prices.TSMAge() or nil, -- its realm data's age: past the limit, stale
        minBuyout = minBuyout,
        market = market,
        de = de,
        deSource = de ~= nil and deSource or nil,
        source = "TSM",
    }
end

--- Vendor sell price per unit (copper), or nil while the item info isn't loaded.
function Prices.Vendor(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, _, _, _, _, _, _, _, _, sell = call(getInfo, link)
    if name == nil then return nil end
    return copper(sell) or 0
end

--- Item class (2 = weapon, 4 = armor) and subclass, without needing the item cached.
function Prices.ClassID(link)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, _, _, classID, subclassID = call(instant, link)
    return tonumber(classID), tonumber(subclassID)
end
