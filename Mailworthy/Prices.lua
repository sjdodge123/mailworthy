-- Price sources. Auctionator (optional) gives auction and disenchant prices from
-- its own scans; Mailworthy never scans the AH itself. Vendor prices come from
-- the item info. Confirmed on Forever (Auctionator 340/341, 2026-10-13): the
-- API.v1 calls below exist and return prices after a scan (age 0, exact).
-- Every call is guarded: a missing or failing call is "no price", never a guess.
local _, ns = ...

local Prices = {}
ns.Prices = Prices

Prices.CALLER = "Mailworthy"

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
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

--- Disenchantry has no price data; it only switches the disenchant comparison on by default.
function Prices.DisenchantryInstalled()
    local addons = rawget(_G, "C_AddOns")
    if type(addons) == "table" and call(addons.IsAddOnLoaded, "Disenchantry") then return true end
    return rawget(_G, "DisenchantryDB") ~= nil
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

--- Auction data for one item link, or nil when there's no price source at all.
--- { ah = copper per unit (last scan's minimum buyout), age = days since seen, exact = true / false /
---   nil (unknown), de = copper per item, history = Prices.History(link), available = units listed
---   at the last scanned day }; any may be nil.
function Prices.Lookup(link)
    local api = Prices.Auctionator()
    if not api then return nil end
    local exact = call(api.IsAuctionDataExactByItemLink, Prices.CALLER, link)
    if exact ~= nil then exact = exact == true end
    local history = Prices.History(link)
    return {
        ah = copper(call(api.GetAuctionPriceByItemLink, Prices.CALLER, link)),
        age = tonumber((call(api.GetAuctionAgeByItemLink, Prices.CALLER, link))),
        exact = exact,
        de = copper(call(api.GetDisenchantPriceByItemLink, Prices.CALLER, link)),
        history = history,
        available = history and history[1].available or nil,
        source = "Auctionator",
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
