-- The decision rule (docs/PLAN.md "Decision rule"): mail an item to the bank
-- alt when the auction house (after cut, deposit and postage) or disenchanting
-- beats the vendor by at least the minimum gain; otherwise it stays in the bags.
-- Pure: no WoW API calls, so every case is a busted spec.
--
-- An item is every stack of one item link in the bags (so one item never
-- splits into "mail 20, keep 3"). Measured on Forever (2026-10-13):
--   deposit = floor(vendor value of the listing x 5%) x 1 / 4 / 12 for 2h / 8h / 24h
--   postage = 30c per attached stack
local _, ns = ...

local Valuation = {}
ns.Valuation = Valuation

Valuation.DEPOSIT_RATE = 0.05
Valuation.MEDIAN_DAYS = 3        -- the smoothed price: median of the last 3 scanned days
Valuation.LAUNCH_EPOCH = 1793833200 -- Forever launch: 2026-11-04 15:00 PST (docs/ALGORITHM-RESEARCH.md)
Valuation.FRESH_REALM_DAYS = 14  -- launch days 0-13: unpriced white trade goods are mailed
Valuation.TRADE_GOODS = 7        -- item class: cloth, ore, herbs, leather, enchanting materials...
Valuation.INEXACT_HAIRCUT = 0.10 -- off an inexact price (Auctionator matched a similar name)
Valuation.DEPOSIT_MULTIPLIER = { 1, 4, 12 } -- AH durations 1 / 2 / 3 = 2h / 8h / 24h
Valuation.DURATION_HOURS = { 2, 8, 24 }

Valuation.DEFAULTS = {
    duration = 3,         -- 24h listing (operator, 2026-10-13)
    relistFactor = 1.0,   -- deposits counted in full (the game refunds them on a sale)
    cut = 0.05,           -- AH cut, until a sale mail confirms it
    postage = 30,         -- copper per attached stack
    minGain = 500,        -- 5s ...
    minGainPct = 0.25,    -- ... and 25% of the vendor value, both
    maxAgeDays = 7,       -- older Auctionator prices don't count
    disenchant = false,   -- Valuation.Settings switches it on when Disenchantry is installed
}

--- Pure: days since the realm launched (0 before launch and on launch day). `now` is
--- the server time; `firstSeen` the first server time Mailworthy saw this realm, which
--- stands in for the launch of any realm that opens later than Forever's first wave.
function Valuation.ServerDay(now, firstSeen)
    now = tonumber(now)
    if not now then return nil end
    local launch = Valuation.LAUNCH_EPOCH
    if tonumber(firstSeen) and firstSeen < launch then launch = firstSeen end
    return math.max(0, math.floor((now - launch) / 86400))
end

--- Pure: research 4.2. With Auctionator installed but no price for this item yet, a white
--- trade good is mailed during the first FRESH_REALM_DAYS launch days: cloth, ore, herbs and
--- leather always sell on a fresh realm, and in launch week almost nothing has a price.
function Valuation.FreshRealmDefault(item, price, settings)
    return type(price) == "table" and price.ah == nil
        and item.quality == 1 and item.classID == Valuation.TRADE_GOODS
        and tonumber(settings.serverDay) ~= nil and settings.serverDay < Valuation.FRESH_REALM_DAYS
end

--- Settings for a scan: saved values over the defaults. The disenchant default
--- follows Disenchantry until the player sets it (then their choice sticks).
function Valuation.Settings(saved, disenchantryInstalled)
    local s = {}
    for k, v in pairs(Valuation.DEFAULTS) do s[k] = v end
    s.disenchant = disenchantryInstalled == true
    for k, v in pairs(type(saved) == "table" and saved or {}) do
        if Valuation.DEFAULTS[k] ~= nil and type(v) == type(Valuation.DEFAULTS[k]) then s[k] = v end
    end
    if not Valuation.DEPOSIT_MULTIPLIER[s.duration] then s.duration = Valuation.DEFAULTS.duration end
    return s
end

function Valuation.Deposit(vendorUnit, count, duration)
    local mult = Valuation.DEPOSIT_MULTIPLIER[duration] or Valuation.DEPOSIT_MULTIPLIER[Valuation.DEFAULTS.duration]
    return math.floor((vendorUnit or 0) * (count or 0) * Valuation.DEPOSIT_RATE) * mult
end

-- Profession tools stay in the bags whatever they'd sell for (the v0.2.0 scan
-- listed a Fishing Pole to mail). Classic item IDs; fishing poles also by class
-- (weapon, subclass 20).
Valuation.TOOLS = {
    [2901] = "Mining Pick", [5956] = "Blacksmith Hammer", [7005] = "Skinning Knife",
    [4471] = "Flint and Tinder", [6219] = "Arclight Spanner", [10498] = "Gyromatic Micro-Adjustor",
    [6218] = "Runed Copper Rod", [6339] = "Runed Silver Rod", [11130] = "Runed Golden Rod",
    [11145] = "Runed Truesilver Rod", [16207] = "Runed Arcanite Rod", [6256] = "Fishing Pole",
}
Valuation.FISHING_POLE_SUBCLASS = 20

function Valuation.IsTool(item)
    return Valuation.TOOLS[item.itemID] ~= nil
        or (item.classID == 2 and item.subclassID == Valuation.FISHING_POLE_SUBCLASS)
end

--- Soulbound and quest items can never be mailed: the window doesn't list them.
function Valuation.Unmailable(result)
    return result.action == "keep" and (result.reason == "soulbound" or result.reason == "quest item")
end

--- Armor (class 4) or weapon (class 2), uncommon or better.
function Valuation.CanDisenchant(item)
    return (item.classID == 2 or item.classID == 4) and (item.quality or 0) >= 2
end

--- The unit price an item is valued at (docs/ALGORITHM-RESEARCH.md 4.1 / 4.7): the median
--- of the highest minimum buyout over the last MEDIAN_DAYS scanned days, so one 1c undercut
--- in the latest scan can't flip a verdict; the last scan's price when there are fewer than
--- two days of history. An inexact price loses INEXACT_HAIRCUT. Returns copper (nil without
--- a price) and the number of scanned days behind it (1 = the last scan alone).
function Valuation.SmoothedPrice(price)
    if type(price) ~= "table" or price.ah == nil then return nil, 0 end
    local days = {}
    for _, row in ipairs(type(price.history) == "table" and price.history or {}) do
        if type(row) == "table" and row.maxSeen then days[#days + 1] = row.maxSeen end
        if #days == Valuation.MEDIAN_DAYS then break end
    end
    local unit, scans = price.ah, 1
    local n = #days
    if n >= 2 then
        table.sort(days)
        unit = n % 2 == 1 and days[(n + 1) / 2] or math.floor((days[n / 2] + days[n / 2 + 1]) / 2)
        scans = n
    end
    if price.exact == false then unit = math.floor(unit * (1 - Valuation.INEXACT_HAIRCUT)) end
    return unit, scans
end

function Valuation.Threshold(vendorTotal, settings)
    return math.max(settings.minGain, math.ceil(vendorTotal * settings.minGainPct))
end

local function keep(reason, extra)
    local r = extra or {}
    r.action, r.reason = "keep", reason
    return r
end

--- item: { link, itemID, count, stacks, quality, classID, vendor (copper per unit; nil = not
---   loaded yet), bound, quest, inUse (locked by the game), locked (Mailworthy lock) }
--- price: nil when there's no price source at all (no Auctionator); else
---   { ah = copper per unit or nil, age = days or nil, de = copper per item or nil }
---   history = Prices.History rows (optional), exact = true / false / nil }
--- Returns { action = "mail" | "keep", route = "ah" | "de" | "common" (mail only), reason,
---   vendor, deposit, postage, ahUnit (the smoothed unit price), scans (days behind it),
---   ahNet, deNet, gain, threshold } (copper, totals for the item).
function Valuation.Evaluate(item, price, settings)
    settings = settings or Valuation.DEFAULTS
    if item.locked then return keep("locked") end
    if item.bound then return keep("soulbound") end
    if item.quest then return keep("quest item") end
    if item.inUse then return keep("in use") end
    if Valuation.IsTool(item) then return keep("profession tool") end
    if item.vendor == nil then return keep("item info not loaded yet") end

    local n = item.count or 1
    local vendor = item.vendor * n
    local postage = settings.postage * (item.stacks or 1)

    if price == nil then
        -- No price source: mail plain white (common) items, keep the rest (operator, 2026-10-13).
        if item.quality == 1 then
            return { action = "mail", route = "common", reason = "common item (no price data)",
                vendor = vendor, postage = postage }
        end
        return keep(item.quality == 0 and "junk (no price data)" or "uncommon or better (no price data)",
            { vendor = vendor })
    end

    local r = { vendor = vendor, postage = postage }
    local stale = price.ah ~= nil and price.age ~= nil and price.age > settings.maxAgeDays
    if price.ah ~= nil and not stale then
        r.ahUnit, r.scans = Valuation.SmoothedPrice(price)
        r.deposit = Valuation.Deposit(item.vendor, n, settings.duration)
        r.ahNet = math.floor(r.ahUnit * n * (1 - settings.cut)) - math.floor(r.deposit * settings.relistFactor) - postage
    end
    if settings.disenchant and price.de ~= nil and Valuation.CanDisenchant(item) then
        r.deNet = math.floor(price.de * n) - postage
    end
    if r.ahNet == nil and r.deNet == nil then
        if stale then return keep(string.format("price too old (%d days)", price.age), r) end
        if Valuation.FreshRealmDefault(item, price, settings) then
            return { action = "mail", route = "common", reason = "common trade good (fresh realm, no price yet)",
                vendor = vendor, postage = postage }
        end
        return keep("no price", r)
    end

    local best, route = r.ahNet, "ah"
    if r.deNet ~= nil and (best == nil or r.deNet > best) then best, route = r.deNet, "de" end
    r.gain = best - vendor
    r.threshold = Valuation.Threshold(vendor, settings)
    if r.gain >= r.threshold then
        r.action, r.route = "mail", route
        r.reason = route == "ah" and "auction house" or "disenchant"
        return r
    end
    return keep("not worth it", r)
end

--- "1g 2s 3c", "-45c", "0c".
function Valuation.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return sign .. table.concat(parts, " ")
end
