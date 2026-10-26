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

--- Auctionator's price for a material by item ID (copper per unit), the call Disenchantry
--- uses for its material prices (GetAuctionPriceByItemID, else the link form).
function Prices.MaterialPrice(itemID)
    local api = Prices.Auctionator()
    if not api or not tonumber(itemID) then return nil end
    if type(api.GetAuctionPriceByItemID) == "function" then
        return copper(call(api.GetAuctionPriceByItemID, Prices.CALLER, tonumber(itemID)))
    end
    return copper(call(api.GetAuctionPriceByItemLink, Prices.CALLER, "item:" .. tonumber(itemID)))
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
---   available = units listed at the last scanned day }; any may be nil.
function Prices.Lookup(link)
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
