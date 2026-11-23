-- Payback ideas (phase 3 of docs/RECOMMENDATIONS.md, media/recommendations-prototype.html; operator,
-- 2026-11-22: "if the profession can craft some item thats useful to send back to the original sender ...
-- encourage paybacks ... so that the 'debt' is slowly cleared").
--
-- Two halves, each on its own player's Mailworthy:
--   The sender's: after a counted mail to another player (Ledger.RecordSent), a short **needs note** goes
--     to that player's character, whispered with the mail's values (LedgerWire's outbox, the same online
--     check): this character's level, class, bag sizes and the ammo its ranged weapon fires. Facts only;
--     Settings > "Tell crafters what I could use" (on by default) turns it off.
--   The crafter's: what its own professions make (TierCheck.MyCrafts), matched against the note of each
--     player it owes (Ledger.Debts) by fixed checks (Paybacks.Ideas): a bag with more slots than their
--     smallest, the ammo their ranged weapon fires for their level. The ideas show at the mailbox under
--     the owed notice (MailBanners.lua) and in chat when the profession window opens. Mailworthy never
--     crafts: once the item is in the bags, its row's pick button offers **<sender>** after Me (a
--     payback for this visit, off until picked), mailed with the subject "Mailworthy: made for you
--     (Woolen Bag)". The ledger counts it as any mail; with no auction price it counts its materials,
--     never more than what's owed (a payback clears a debt, never makes one; the receiver caps it too).
--
-- Switch: /mw feature paybacks off (no note sent, none read, no ideas, no payback pick).
local _, ns = ...

local Paybacks = {}
ns.Paybacks = Paybacks

local Util = ns.Util
local call = Util.Call
local clean = function(name) return ns.Routes.Clean(name) end

Paybacks.ROUTE = "payback"     -- the verdict route of a picked payback
Paybacks.NEEDS_DAYS = 30       -- a needs note is kept this long
Paybacks.LEVEL_BAND = 10       -- ammo: required level at or under theirs, no more than this under
Paybacks.CONTAINER = 1         -- Enum.ItemClass.Container
Paybacks.BAG = 0               -- its subclass for a plain bag (not a soul, herb or enchanting bag)
Paybacks.MAX_IDEAS = 3

function Paybacks.On() return ns.Features.On("paybacks") and ns.Ledger.On() end

--- Send the needs note: Settings > "Tell crafters what I could use" (on by default).
function Paybacks.ShareNeeds() return Paybacks.On() and not ns.Config.Flag("hideNeeds") end

local function store()
    local s = ns.Ledger.Store()
    s.needs = Util.Table(s.needs)
    return s.needs
end

-- The needs note ---------------------------------------------------------------------------------

--- This character's facts for the note: { level, class, bags = { slots of bags 1-4, 0 for an empty slot },
--- fires (2 arrows, 3 bullets, or nil) }.
function Paybacks.MyNeeds()
    local container = rawget(_G, "C_Container")
    local numSlots = type(container) == "table" and container.GetContainerNumSlots or rawget(_G, "GetContainerNumSlots")
    local bags = {}
    for bag = 1, 4 do bags[bag] = tonumber((call(numSlots, bag))) or 0 end
    return { level = tonumber((call(rawget(_G, "UnitLevel"), "player"))), class = ns.Classes.Mine(), bags = bags,
        fires = ns.Ammo.Equipped() }
end

--- Pure: "N2|<from>|<to>|<send time>|<level>|<CLASS>|<b1>,<b2>,<b3>,<b4>|<fires or 0>".
function Paybacks.EncodeNeeds(from, to, at, needs)
    local bags = {}
    for i = 1, 4 do bags[i] = tostring(math.max(0, math.floor(tonumber(needs.bags and needs.bags[i]) or 0))) end
    return string.format("N%d|%s|%s|%d|%d|%s|%s|%d", ns.Comms.VERSION, tostring(from), tostring(to), math.floor(at),
        math.floor(tonumber(needs.level) or 0), tostring(needs.class or "-"), table.concat(bags, ","),
        tonumber(needs.fires) or 0)
end

--- Pure: the body of an "N" message (after "N2|"), or nil: { from, to, at, level, class, bags, fires }.
--- Every field is checked; anything odd drops it.
function Paybacks.DecodeNeeds(rest)
    local from, to, at, level, class, b1, b2, b3, b4, fires = tostring(rest):match(
        "^([^|]+)|([^|]+)|(%d+)|(%d+)|([%u%-]+)|(%d+),(%d+),(%d+),(%d+)|(%d)$")
    from, to = from and clean(from), to and clean(to)
    if not from or not to or #from > ns.Comms.MAX_NAME or #to > ns.Comms.MAX_NAME then return nil end
    level = tonumber(level)
    if not level or level < 1 or level > 100 then return nil end
    local bags = { tonumber(b1), tonumber(b2), tonumber(b3), tonumber(b4) }
    for _, n in ipairs(bags) do if n > 64 then return nil end end
    fires = tonumber(fires)
    if fires ~= 0 and fires ~= 2 and fires ~= 3 then return nil end
    return { from = from, to = to, at = tonumber(at), level = level, class = class ~= "-" and class or nil, bags = bags,
        fires = fires ~= 0 and fires or nil }
end

local sentToday = {} -- recipient -> true: one note a session each

--- After a counted mail to another player (Ledger.RecordSent): the needs note goes with its values.
function Paybacks.AfterSend(entry)
    if not Paybacks.ShareNeeds() or type(entry) ~= "table" or not entry.counted or entry.dir ~= "sent" then return end
    local to = clean(entry.other)
    if not to or sentToday[to:lower()] or #(entry.items or {}) == 0 then return end
    sentToday[to:lower()] = true
    local ok, needs = pcall(Paybacks.MyNeeds)
    if not ok or type(needs) ~= "table" or not needs.level then return end
    ns.Ledger.internal.queueFor(to, entry.at, { Paybacks.EncodeNeeds(entry.char or ns.PlayerName(), to, entry.at, needs) })
    ns.Log.Add("paybacks", "needs note queued for %s", to)
end

--- A needs note whispered to this account: kept when it comes from the character it names and is for one
--- of this account's characters (a stranger can't speak for someone else), newest per sender.
function Paybacks.HearNeeds(whisperer, msg)
    whisperer = clean(whisperer)
    if not whisperer or type(msg) ~= "table" or not Paybacks.On() then return nil end
    if msg.from:lower() ~= whisperer:lower() or not ns.Ledger.IsOwn(msg.to) then return nil end
    local now = Util.Now()
    if not msg.at or msg.at > now + 600 or msg.at < now - Paybacks.NEEDS_DAYS * 86400 then return nil end
    local key = msg.from:lower()
    local old = store()[key]
    if type(old) == "table" and (tonumber(old.at) or 0) > msg.at then return nil end
    store()[key] = { name = msg.from, to = msg.to, at = msg.at, level = msg.level, class = msg.class, bags = msg.bags,
        fires = msg.fires }
    ns.Log.Add("paybacks", "needs note from %s (level %d)", msg.from, msg.level)
    if ns.MailWindow and ns.MailWindow.RefreshIfShown then ns.MailWindow.RefreshIfShown() end
    return msg
end

--- The notes kept, by lower-case sender: { name, to, at, level, class, bags, fires }. Old ones are dropped.
function Paybacks.Needs()
    local now, out = Util.Now(), {}
    for key, n in pairs(store()) do
        if type(n) == "table" and (tonumber(n.at) or 0) >= now - Paybacks.NEEDS_DAYS * 86400 then out[key] = n
        else store()[key] = nil end
    end
    return out
end

ns.Comms.Register("N", {
    kind = "needs",
    module = "Paybacks",
    channels = { WHISPER = true },
    decode = function(rest)
        local needs = Paybacks.DecodeNeeds(rest)
        return needs and { needs = needs } or nil
    end,
    hear = function(name, msg) return Paybacks.HearNeeds(name, msg.needs) end,
})

-- Item facts -------------------------------------------------------------------------------------

local facts = {} -- itemID -> { name, classID, subclassID, minLevel, slots } once the client has it

--- Pure: the slot count in a bag's tooltip line ("8 Slot Bag"; CONTAINER_SLOTS = "%d Slot %s"), or nil.
function Paybacks.SlotsFromLine(text, format)
    if type(text) ~= "string" then return nil end
    local pattern = type(format) == "string" and ("^" .. format:gsub("%%d", "(%%d+)"):gsub("%%s", ".+") .. "$") or nil
    local n = pattern and text:match(pattern) or text:match("^(%d+) Slot")
    return tonumber(n)
end

local function tooltipSlots(itemID)
    local info = rawget(_G, "C_TooltipInfo")
    local data = type(info) == "table" and call(info.GetItemByID, itemID) or nil
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and (line.leftText or (type(line.args) == "table" and line.args[2]
            and line.args[2].stringVal)) or nil
        local n = Paybacks.SlotsFromLine(text, rawget(_G, "CONTAINER_SLOTS"))
        if n then return n end
    end
    return nil
end

--- What the checks need to know of an item, or nil while the client hasn't loaded it.
function Paybacks.Facts(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if facts[itemID] then return facts[itemID] end
    local getInfo = (C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
    local name, _, _, _, minLevel, _, _, _, _, _, _, classID, subclassID = call(getInfo, itemID)
    if not name then return nil end
    local f = { name = name, minLevel = tonumber(minLevel) or 0, classID = tonumber(classID), subclassID = tonumber(subclassID) }
    if f.classID == Paybacks.CONTAINER and f.subclassID == Paybacks.BAG then
        f.slots = tooltipSlots(itemID)
        if not f.slots then return nil end -- not known yet: no idea rather than a wrong one
    end
    facts[itemID] = f
    return f
end

-- Matching (pure) -----------------------------------------------------------------------------------

local function smallestBag(bags)
    local small, count = nil, 0
    for _, n in ipairs(bags or {}) do
        n = tonumber(n) or 0
        if not small or n < small then small = n end
        count = count + 1
    end
    return small, count
end

--- Pure: the payback ideas for one player's needs note. `crafts`: TierCheck.MyCrafts; `factsOf(itemID)`:
--- Paybacks.Facts; `have(itemID)`: how many the bags hold. Returns ideas (best first, at most MAX_IDEAS):
--- { itemID, name, kind = "bag" / "ammo", slots, want, why, reagents, canMake, missing = { { itemID, need } } },
--- and "not suggested" notes: { { name, why } }.
function Paybacks.Ideas(needs, crafts, factsOf, have)
    local ideas, notes = {}, {}
    if type(needs) ~= "table" then return ideas, notes end
    local small = smallestBag(needs.bags)
    local first = tostring(needs.name or "they"):match("^(%S+)") or "they"
    for itemID, craft in pairs(crafts or {}) do
        local f = factsOf(itemID)
        local idea
        if f and f.classID == Paybacks.CONTAINER and f.subclassID == Paybacks.BAG and f.slots and small then
            local want = 0
            for _, n in ipairs(needs.bags or {}) do if (tonumber(n) or 0) < f.slots then want = want + 1 end end
            if want > 0 then
                idea = { kind = "bag", slots = f.slots, want = want,
                    why = small == 0 and string.format("%s has an empty bag slot; this one holds %d", first, f.slots)
                        or string.format("%s's smallest bag holds %d; this one holds %d", first, small, f.slots) }
            else
                notes[#notes + 1] = { name = f.name, why = string.format("%d slots: no bigger than %s's", f.slots, first) }
            end
        elseif f and f.classID == ns.Ammo.PROJECTILE then
            local level = tonumber(needs.level) or 0
            if needs.fires and f.subclassID == needs.fires and f.minLevel <= level and f.minLevel >= level - Paybacks.LEVEL_BAND then
                idea = { kind = "ammo", want = 1, minLevel = f.minLevel,
                    why = string.format("%s's ranged weapon fires %s", first, ns.Ammo.NAMES[needs.fires] or "it") }
            elseif not needs.fires then
                notes[#notes + 1] = { name = f.name, why = first .. " has no bow or gun equipped" }
            end
        end
        if idea then
            idea.itemID, idea.name, idea.reagents = itemID, f.name, craft.reagents or {}
            local can, missing = math.huge, {}
            for rid, need in pairs(idea.reagents) do
                local got = tonumber(have(rid)) or 0
                can = math.min(can, math.floor(got / math.max(1, need)))
                if got < need then missing[#missing + 1] = { itemID = rid, need = need - got } end
            end
            idea.canMake = can == math.huge and 0 or can
            idea.missing = missing
            ideas[#ideas + 1] = idea
        end
    end
    table.sort(ideas, function(a, b)
        if a.kind ~= b.kind then return a.kind == "bag" end
        if (a.slots or 0) ~= (b.slots or 0) then return (a.slots or 0) > (b.slots or 0) end
        if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) > (b.minLevel or 0) end
        return a.itemID < b.itemID
    end)
    while #ideas > Paybacks.MAX_IDEAS do table.remove(ideas) end
    table.sort(notes, function(a, b) return a.name < b.name end)
    return ideas, notes
end

-- "Not for <name>": an idea never shown for that player again ---------------------------------------

local function declined() return Util.Store(MailworthyDB, "paybackDeclined", (Util.RealmKey())) end
local function declineKey(name, itemID) return tostring(name):lower() .. "|" .. tostring(tonumber(itemID)) end
function Paybacks.Decline(name, itemID) declined()[declineKey(name, itemID)] = true end
function Paybacks.Declined(name, itemID) return declined()[declineKey(name, itemID)] == true end

-- Who an idea is for ------------------------------------------------------------------------------

--- How many of `itemID` the bags hold.
function Paybacks.Have(itemID)
    local n = 0
    for _, slot in ipairs(ns.Bags.Slots()) do
        if tonumber(slot.itemID) == tonumber(itemID) then n = n + (tonumber(slot.count) or 1) end
    end
    return n
end

--- The players this account owes who left a needs note, most owed first, each with its ideas:
--- { { name (the character that mailed), owner, net, needs, ideas, notes } }.
function Paybacks.ForDebts()
    if not Paybacks.On() then return {} end
    local needs, crafts = Paybacks.Needs(), ns.TierCheck.MyCrafts()
    if next(crafts) == nil or next(needs) == nil then return {} end
    local counts = {}
    for _, slot in ipairs(ns.Bags.Slots()) do
        local id = tonumber(slot.itemID)
        if id then counts[id] = (counts[id] or 0) + (tonumber(slot.count) or 1) end
    end
    local out = {}
    for _, d in ipairs(ns.Ledger.Debts()) do
        for _, n in pairs(needs) do
            if tostring(ns.Ledger.Owner(n.name)):lower() == tostring(d.name):lower() then
                local ideas, notes = Paybacks.Ideas(n, crafts, Paybacks.Facts, function(id) return counts[id] or 0 end)
                local kept = {}
                for _, idea in ipairs(ideas) do
                    if not Paybacks.Declined(n.name, idea.itemID) then kept[#kept + 1] = idea end
                end
                out[#out + 1] = { name = n.name, owner = d.name, net = d.net, needs = n, ideas = kept, notes = notes }
            end
        end
    end
    return out
end

--- For a bag scan (Bags.Evaluate, once): itemID -> the payback pick route for it, for the player owed most
--- whose note it matches: { key, to, payback = true, scope = "payback", label, owner }.
function Paybacks.Targets()
    local out = {}
    local ok, list = pcall(Paybacks.ForDebts)
    if not ok then
        ns.Log.Add("paybacks", "ideas error: %s", tostring(list))
        return out
    end
    for _, d in ipairs(list) do -- most owed first: the first player an item matches keeps it
        for _, idea in ipairs(d.ideas) do
            if not out[idea.itemID] then
                out[idea.itemID] = { key = Paybacks.ROUTE .. "|" .. d.name:lower(), to = d.name, owner = d.owner,
                    payback = true, scope = Paybacks.ROUTE, label = d.name:match("^(%S+)") or d.name, itemName = idea.name }
            end
        end
    end
    return out
end

--- The payback pick for an item (Bags' decide): its route, or nil. Never past a hard keep, a pin, a failed
--- price call or what this character's own professions keep (Routes.Divertible), nor item data not loaded.
function Paybacks.ChoiceFor(item, verdict, price, targets)
    local route = targets and item and targets[tonumber(item.itemID)]
    if not route or not ns.Routes.Divertible(verdict, price) then return nil end
    if ns.Valuation.Is(verdict, ns.Valuation.K.notLoaded) then return nil end
    return route
end

--- The mail verdict of a picked payback.
function Paybacks.Result(item, route, settings)
    local n = item.count or 1
    return {
        action = "mail", route = Paybacks.ROUTE, to = route.to, key = route.key, payback = true,
        what = "made for you (" .. tostring(route.itemName or ns.Util.LinkName(item.link) or "an item") .. ")",
        reason = "made for " .. tostring(route.to) .. ": a payback",
        vendor = (item.vendor or 0) * n, postage = (settings and settings.postage or 30) * (item.stacks or 1),
    }
end

--- What one of `itemID` is worth in materials at this character's prices (copper), or nil: none of its
--- reagents priced, or not something this character makes. A craft that makes several (200 rounds of ammo)
--- shares its materials among them (Codex review, 2026-11-22).
function Paybacks.MaterialsValue(itemID)
    local craft = ns.TierCheck.MyCrafts()[tonumber(itemID) or -1]
    if not craft then return nil end
    local total, any = 0, false
    local getInfo = (C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
    for rid, need in pairs(craft.reagents or {}) do
        local _, link = call(getInfo, rid) -- the price sources want an item link
        local unit = ns.Ledger.UnitValue(link or ("item:" .. rid))
        if unit then total, any = total + unit * need, true end
    end
    return any and math.floor(total / math.max(1, tonumber(craft.yield) or 1)) or nil
end

-- The reminder at the profession window --------------------------------------------------------------

local reminded = {} -- "name|itemID" -> true, this session

--- One chat line a session per idea that can be made right now.
function Paybacks.Remind()
    if not Paybacks.On() or call(rawget(_G, "InCombatLockdown")) then return end
    for _, d in ipairs(Paybacks.ForDebts()) do
        local parts = {}
        for _, idea in ipairs(d.ideas) do
            local key = d.name:lower() .. "|" .. idea.itemID
            if idea.canMake > 0 and not reminded[key] then
                reminded[key] = true
                parts[#parts + 1] = string.format("%s (materials for %d)", idea.name, math.min(idea.canMake, idea.want))
            end
        end
        if #parts > 0 then
            ns.Print(string.format("Payback idea for %s: %s. Make it, then pick %s on its row at the mailbox.", d.name,
                Util.ListText(parts, ""), d.name:match("^(%S+)") or d.name))
        end
    end
end

function Paybacks.Reset() reminded, sentToday, facts = {}, {}, {} end

local function remindSoon() Util.After(2, Paybacks.Remind) end -- after TierCheck has read the window
ns.On("TRADE_SKILL_SHOW", remindSoon)
ns.On("CRAFT_SHOW", remindSoon)
