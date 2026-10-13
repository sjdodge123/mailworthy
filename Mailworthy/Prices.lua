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

--- Auction data for one item link, or nil when there's no price source at all.
--- { ah = copper per unit, age = days since seen, exact = bool, de = copper per item }; any may be nil.
function Prices.Lookup(link)
    local api = Prices.Auctionator()
    if not api then return nil end
    return {
        ah = copper(call(api.GetAuctionPriceByItemLink, Prices.CALLER, link)),
        age = tonumber((call(api.GetAuctionAgeByItemLink, Prices.CALLER, link))),
        exact = call(api.IsAuctionDataExactByItemLink, Prices.CALLER, link) == true,
        de = copper(call(api.GetDisenchantPriceByItemLink, Prices.CALLER, link)),
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

--- Item class (2 = weapon, 4 = armor) without needing the item cached.
function Prices.ClassID(link)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    return tonumber((select(6, call(instant, link))))
end
