-- Bag scan: every stack in the backpack and bags 1-4 becomes item facts,
-- grouped per item link (all stacks of an item go or stay together), then
-- valued by Valuation. `/mw scan` shows the result and sends nothing.
local _, ns = ...

local Bags = {}
ns.Bags = Bags

Bags.ATTACHMENTS = 12 -- per mail (ATTACHMENTS_MAX_SEND, measured)

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

--- One entry per occupied bag slot.
function Bags.Slots()
    local slots = {}
    local container = C_Container or {}
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        for slot = 1, tonumber((call(container.GetContainerNumSlots, bag))) or 0 do
            local info = call(container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.hyperlink then
                local quest = call(container.GetContainerItemQuestInfo, bag, slot)
                slots[#slots + 1] = {
                    bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                    count = tonumber(info.stackCount) or 1, quality = tonumber(info.quality),
                    bound = info.isBound == true, inUse = info.isLocked == true, noValue = info.hasNoValue == true,
                    quest = type(quest) == "table" and quest.isQuestItem == true, icon = info.iconFileID,
                }
            end
        end
    end
    return slots
end

--- Stacks of the same link (and same bound / in-use state) become one item.
function Bags.Group(slots)
    local items, byKey = {}, {}
    for _, s in ipairs(slots) do
        local key = table.concat({ s.link, tostring(s.bound), tostring(s.inUse) }, "|")
        local item = byKey[key]
        if not item then
            item = { link = s.link, itemID = s.itemID, quality = s.quality, bound = s.bound, inUse = s.inUse,
                quest = s.quest, noValue = s.noValue, icon = s.icon, count = 0, stacks = 0, slots = {} }
            byKey[key] = item
            items[#items + 1] = item
        end
        item.count = item.count + s.count
        item.stacks = item.stacks + 1
        item.quest = item.quest or s.quest
        item.slots[#item.slots + 1] = { bag = s.bag, slot = s.slot, count = s.count }
    end
    return items
end

function Bags.CurrentSettings()
    return ns.Config.Values()
end

--- Scan and value the bags. Returns { settings, priced, mail = {items}, keep = {items},
--- unmailable = {items} (soulbound / quest: never listed in the window), totals }.
function Bags.Evaluate(settings)
    settings = settings or Bags.CurrentSettings()
    if settings.serverDay == nil then settings.serverDay = ns.Config.ServerDay() end
    local priced = ns.Prices.Auctionator() ~= nil
    local result = { settings = settings, priced = priced, mail = {}, keep = {}, unmailable = {},
        totals = { items = 0, stacks = 0, mails = 0, gain = 0, postage = 0 } }
    for _, item in ipairs(Bags.Group(Bags.Slots())) do
        item.locked = ns.Locks.IsItemLocked(item.itemID)
        item.classID, item.subclassID = ns.Prices.ClassID(item.link)
        item.vendor = item.noValue and 0 or ns.Prices.Vendor(item.link)
        item.price = priced and ns.Prices.Lookup(item.link) or nil
        item.result = ns.Valuation.Evaluate(item, item.price, settings)
        if item.result.action == "mail" then
            table.insert(result.mail, item)
            local t = result.totals
            t.items, t.stacks = t.items + item.count, t.stacks + item.stacks
            t.gain = t.gain + (item.result.gain or 0)
            t.postage = t.postage + item.result.postage
        elseif ns.Valuation.Unmailable(item.result) then
            table.insert(result.unmailable, item)
        else
            table.insert(result.keep, item)
        end
    end
    result.totals.mails = math.ceil(result.totals.stacks / Bags.ATTACHMENTS)
    local function byGain(a, b)
        local ga, gb = a.result.gain or -math.huge, b.result.gain or -math.huge
        if ga ~= gb then return ga > gb end
        return a.link < b.link
    end
    table.sort(result.mail, byGain)
    table.sort(result.keep, byGain)
    return result
end

-- Report ---------------------------------------------------------------------

local money = function(c) return ns.Valuation.Money(c) end

local ROUTE = { ah = "AH", de = "DE", common = "COMMON" }

local function itemName(item)
    local name = item.link:match("%[(.-)%]") or item.link
    return string.format("[%s] x%d%s", name, item.count, item.stacks > 1 and (" (" .. item.stacks .. " stacks)") or "")
end

-- The numbers behind a verdict, so it can be checked by hand.
local function workings(item, settings)
    local r, p, parts = item.result, item.price, {}
    if item.vendor ~= nil then
        parts[#parts + 1] = "vendor " .. money(item.vendor) .. " each = " .. money(r.vendor or item.vendor * item.count)
    end
    if p and p.ah then
        local text = "AH " .. money(r.ahUnit or p.ah) .. " each"
        if (r.scans or 1) > 1 then
            text = text .. string.format(" (%d-day median; last scan %s)", r.scans, money(p.ah))
        end
        if p.age then text = text .. ", " .. p.age .. " days old" end
        if p.exact == false then text = text .. " (not exact, -10%)" end
        parts[#parts + 1] = text
    end
    if r.ahNet then
        parts[#parts + 1] = string.format("AH net %s (cut %d%%, deposit %s, postage %s)", money(r.ahNet),
            math.floor(settings.cut * 100 + 0.5), money(r.deposit), money(r.postage))
    end
    if p and p.de then parts[#parts + 1] = "disenchant " .. money(p.de) .. " each" end
    if r.deNet then parts[#parts + 1] = "DE net " .. money(r.deNet) end
    if r.gain then parts[#parts + 1] = string.format("gain %s (needs %s)", money(r.gain), money(r.threshold)) end
    return table.concat(parts, "; ")
end

function Bags.Report(result)
    local s, t = result.settings, result.totals
    local lines = {
        string.format("Mailworthy %s scan at %s (sends nothing)", ns.VERSION, date("%Y-%m-%d %H:%M")),
        "bank alt: " .. tostring(ns.Config.BankAlt() or "none set (/mw settings)"),
        "prices: " .. (result.priced and "Auctionator" or "none (no Auctionator: mailing common items)")
            .. ((result.priced and (s.serverDay or math.huge) < ns.Valuation.FRESH_REALM_DAYS)
                and " (fresh realm: unpriced white trade goods are mailed)" or ""),
        string.format("settings: %dh listing (deposit x%d), AH cut %d%%, postage %s per stack, "
            .. "min gain %s and %d%%, disenchant %s, max price age %d days, launch day %s",
            ns.Valuation.DURATION_HOURS[s.duration], ns.Valuation.DEPOSIT_MULTIPLIER[s.duration],
            math.floor(s.cut * 100 + 0.5), money(s.postage), money(s.minGain), math.floor(s.minGainPct * 100 + 0.5),
            s.disenchant and "on" or "off", s.maxAgeDays, tostring(s.serverDay)),
        string.format("total: %d items (%d stacks) in %d mail(s), %s more than vendoring, postage %s",
            t.items, t.stacks, t.mails, money(t.gain), money(t.postage)),
    }
    for _, item in ipairs(result.mail) do
        local w = workings(item, s)
        lines[#lines + 1] = string.format("MAIL %s %s: %s%s", ROUTE[item.result.route] or "?", itemName(item),
            item.result.reason, w ~= "" and (" - " .. w) or "")
    end
    for _, item in ipairs(result.keep) do
        local w = workings(item, s)
        lines[#lines + 1] = string.format("KEEP %s: %s%s", itemName(item), item.result.reason, w ~= "" and (" - " .. w) or "")
    end
    if #result.unmailable > 0 then
        local names = {}
        for _, item in ipairs(result.unmailable) do names[#names + 1] = itemName(item) end
        lines[#lines + 1] = "NOT MAILABLE (soulbound or quest, not listed in the window): " .. table.concat(names, ", ")
    end
    return table.concat(lines, "\n")
end

function Bags.Scan()
    local result = Bags.Evaluate()
    local t = result.totals
    ns.Log.Add("scan", "%d to mail (%d stacks, %d mails, gain %s), %d kept, prices %s", #result.mail, t.stacks,
        t.mails, money(t.gain), #result.keep, result.priced and "Auctionator" or "none")
    ns.Print(string.format("would mail %d items (%d stacks, %d mail(s)), %s more than vendoring; keeps %d. Details in the window.",
        t.items, t.stacks, t.mails, money(t.gain), #result.keep))
    ns.Report.Show(Bags.Report(result), "Mailworthy scan (sends nothing)")
    return result
end
