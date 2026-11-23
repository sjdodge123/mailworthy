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
Paybacks.ARMOR, Paybacks.WEAPON, Paybacks.QUIVER, Paybacks.CONSUMABLE = 4, 2, 11, 0 -- Enum.ItemClass
Paybacks.POTION, Paybacks.FOOD, Paybacks.BANDAGE = 1, 5, 7 -- Enum.ItemConsumableSubclass

-- The rest of the table (docs/RECOMMENDATIONS.md section 2; operator, 2026-11-22: "build the rest of the table").
-- An equipment slot by the item's equip location (INVSLOT_*): the slots a crafted piece can fill.
Paybacks.SLOT_OF = { INVTYPE_HEAD = 1, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
    INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_CLOAK = 15 }
Paybacks.GEAR_SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15 }
Paybacks.SLOT_NAMES = { [1] = "head", [3] = "shoulders", [4] = "shirt", [5] = "chest", [6] = "waist", [7] = "legs",
    [8] = "feet", [9] = "wrists", [10] = "hands", [15] = "back" }
Paybacks.MAIN_HAND, Paybacks.RANGED_SLOT = 16, 18
-- Enum.ItemWeaponSubclass: what a sharpening stone (a blade) or a weightstone (a blunt weapon) is for.
Paybacks.BLADE = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [15] = true } -- axes, polearm, swords, dagger
Paybacks.BLUNT = { [4] = true, [5] = true, [10] = true } -- maces, staff
Paybacks.RANGED = { [2] = "bow", [3] = "gun", [18] = "crossbow", [19] = "wand", [16] = "thrown" }
-- Blacksmithing's stones and Engineering's scopes, by item ID (Classic's; neither has a class of its own).
Paybacks.SHARPENING = { [2862] = true, [2863] = true, [2871] = true, [7964] = true, [12404] = true, [18262] = true }
Paybacks.WEIGHTSTONE = { [3239] = true, [3240] = true, [3241] = true, [7965] = true, [12643] = true }
Paybacks.SCOPES = { [4405] = true, [4406] = true, [4407] = true, [10546] = true, [10548] = true }
-- Alchemy's healing and mana potions (Classic's IDs): a mana potion only for a class with mana.
Paybacks.HEALING = { [118] = true, [858] = true, [929] = true, [1710] = true, [3928] = true, [13446] = true }
Paybacks.MANA = { [2455] = true, [3385] = true, [3827] = true, [6149] = true, [13443] = true, [13444] = true }
Paybacks.NO_MANA = { WARRIOR = true, ROGUE = true }
Paybacks.WAND_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true }
-- The order ideas are listed in, best first.
Paybacks.KIND_ORDER = { bag = 1, quiver = 2, armor = 3, wand = 4, scope = 5, stone = 6, ammo = 7, potion = 8, food = 9,
    bandage = 10 }

--- Pure: the armor subclass a class wears best at a level (Enum.ItemArmorSubclass: 1 cloth, 2 leather, 3 mail,
--- 4 plate): warriors and paladins wear plate from 40 (mail before), hunters and shamans mail from 40
--- (leather before), rogues and druids leather, the others cloth. nil for an unknown class.
function Paybacks.ArmorFor(class, level)
    level = tonumber(level) or 0
    if class == "WARRIOR" or class == "PALADIN" then return level >= 40 and 4 or 3 end
    if class == "HUNTER" or class == "SHAMAN" then return level >= 40 and 3 or 2 end
    if class == "ROGUE" or class == "DRUID" then return 2 end
    if class == "MAGE" or class == "PRIEST" or class == "WARLOCK" then return 1 end
    return nil
end
Paybacks.ARMOR_NAMES = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate" }

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

-- The gear note (2026-11-22, the rest of the table): what the needs note doesn't carry, in a kind of its own so
-- the N2 note stays as it was and an older Mailworthy drops only this one.

local function weaponClass(itemID)
    if not itemID then return nil end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
    local _, _, _, _, _, classID, subclassID = call(instant, itemID)
    return tonumber(classID), tonumber(subclassID)
end

--- This character's gear facts: { main = "blade" / "blunt" / nil, ranged = "bow" / "gun" / "crossbow" / "wand" /
--- "thrown" / nil, quiver (the slots of an equipped quiver or ammo pouch, 0 without), empty = { slot IDs } }.
function Paybacks.MyGear()
    local inv = rawget(_G, "GetInventoryItemID")
    local gear = { quiver = 0, empty = {} }
    local class, sub = weaponClass(tonumber((call(inv, "player", Paybacks.MAIN_HAND))))
    if class == Paybacks.WEAPON then
        gear.main = Paybacks.BLADE[sub] and "blade" or Paybacks.BLUNT[sub] and "blunt" or nil
    end
    class, sub = weaponClass(ns.Ammo.RangedItem())
    if class == Paybacks.WEAPON then gear.ranged = Paybacks.RANGED[sub] end
    local container = rawget(_G, "C_Container")
    local toInv = type(container) == "table" and container.ContainerIDToInventoryID or nil
    local numSlots = type(container) == "table" and container.GetContainerNumSlots or nil
    for bag = 1, 4 do
        local slot = tonumber((call(toInv, bag))) or (19 + bag)
        if weaponClass(tonumber((call(inv, "player", slot)))) == Paybacks.QUIVER then
            gear.quiver = math.max(gear.quiver, tonumber((call(numSlots, bag))) or 0)
        end
    end
    for _, slot in ipairs(Paybacks.GEAR_SLOTS) do
        if call(inv, "player", slot) == nil then gear.empty[#gear.empty + 1] = slot end
    end
    return gear
end

Paybacks.MAINS = { blade = true, blunt = true }
Paybacks.RANGED_WORDS = { bow = true, gun = true, crossbow = true, wand = true, thrown = true }

--- Pure: "E2|<from>|<to>|<send time>|<main: blade|blunt|->|<ranged: bow|gun|crossbow|wand|thrown|->|<quiver slots>|
--- <empty slot IDs, comma-separated, or ->".
function Paybacks.EncodeGear(from, to, at, gear)
    local empty = {}
    for _, slot in ipairs(gear.empty or {}) do empty[#empty + 1] = tostring(math.floor(slot)) end
    return string.format("E%d|%s|%s|%d|%s|%s|%d|%s", ns.Comms.VERSION, tostring(from), tostring(to), math.floor(at),
        Paybacks.MAINS[gear.main] and gear.main or "-", Paybacks.RANGED_WORDS[gear.ranged] and gear.ranged or "-",
        math.max(0, math.floor(tonumber(gear.quiver) or 0)), #empty > 0 and table.concat(empty, ",") or "-")
end

--- Pure: the body of an "E" message (after "E2|"), or nil: { from, to, at, main, ranged, quiver, empty }.
function Paybacks.DecodeGear(rest)
    local from, to, at, main, ranged, quiver, empty = tostring(rest):match(
        "^([^|]+)|([^|]+)|(%d+)|([%a%-]+)|([%a%-]+)|(%d+)|([%d,%-]+)$")
    from, to = from and clean(from), to and clean(to)
    if not from or not to or #from > ns.Comms.MAX_NAME or #to > ns.Comms.MAX_NAME then return nil end
    if main ~= "-" and not Paybacks.MAINS[main] then return nil end
    if ranged ~= "-" and not Paybacks.RANGED_WORDS[ranged] then return nil end
    quiver = tonumber(quiver)
    if quiver > 64 then return nil end
    local slots, valid = {}, {}
    for _, slot in ipairs(Paybacks.GEAR_SLOTS) do valid[slot] = true end
    if empty ~= "-" then
        for n in empty:gmatch("[^,]+") do
            local slot = tonumber(n)
            if not slot or not valid[slot] then return nil end
            slots[#slots + 1] = slot
        end
    end
    return { from = from, to = to, at = tonumber(at), main = main ~= "-" and main or nil,
        ranged = ranged ~= "-" and ranged or nil, quiver = quiver, empty = slots }
end

--- A gear note: kept as the needs note is (from the character it names, for one of this account's), with it.
function Paybacks.HearGear(whisperer, msg)
    whisperer = clean(whisperer)
    if not whisperer or type(msg) ~= "table" or not Paybacks.On() then return nil end
    if msg.from:lower() ~= whisperer:lower() or not ns.Ledger.IsOwn(msg.to) then return nil end
    local now = Util.Now()
    if not msg.at or msg.at > now + 600 or msg.at < now - Paybacks.NEEDS_DAYS * 86400 then return nil end
    local key = msg.from:lower()
    local n = store()[key]
    if type(n) ~= "table" then
        n = { name = msg.from, to = msg.to } -- a gear note first: no needs time yet (Codex review, 2026-11-22)
        store()[key] = n
    end
    if (tonumber(n.gearAt) or 0) > msg.at then return nil end
    n.gearAt, n.main, n.ranged, n.quiver, n.empty = msg.at, msg.main, msg.ranged, msg.quiver, msg.empty
    ns.Log.Add("paybacks", "gear note from %s", msg.from)
    if ns.MailWindow and ns.MailWindow.RefreshIfShown then ns.MailWindow.RefreshIfShown() end
    return msg
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
    local from = entry.char or ns.PlayerName()
    local messages = { Paybacks.EncodeNeeds(from, to, entry.at, needs) }
    local okGear, gear = pcall(Paybacks.MyGear)
    if okGear and type(gear) == "table" then messages[2] = Paybacks.EncodeGear(from, to, entry.at, gear) end
    ns.Ledger.internal.queueFor(to, entry.at, messages)
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
    -- Each note keeps its own time (Codex review, 2026-11-22): a gear note heard first never blocks this one.
    if type(old) == "table" and (tonumber(Paybacks.NeedsAt(old)) or 0) > msg.at then return nil end
    local n = type(old) == "table" and old or {}
    n.name, n.to, n.at, n.needsAt = msg.from, msg.to, msg.at, msg.at
    n.level, n.class, n.bags, n.fires = msg.level, msg.class, msg.bags, msg.fires
    store()[key] = n -- a gear note (HearGear) kept with it stays
    ns.Log.Add("paybacks", "needs note from %s (level %d)", msg.from, msg.level)
    if ns.MailWindow and ns.MailWindow.RefreshIfShown then ns.MailWindow.RefreshIfShown() end
    return msg
end

--- Pure: when a record's needs note came (a record from before 2026-11-22 kept it in `at`), or nil.
function Paybacks.NeedsAt(n)
    return tonumber(n.needsAt) or (n.level and tonumber(n.at)) or nil
end

--- The notes kept, by lower-case sender: { name, to, level, class, bags, fires, main, ranged, quiver, empty }.
--- The needs note and the gear note each count for NEEDS_DAYS from their own time (Codex review, 2026-11-22: a
--- fresh needs note kept an old gear note's slots); a record with neither left is dropped.
function Paybacks.Needs()
    local now, out = Util.Now(), {}
    local since = now - Paybacks.NEEDS_DAYS * 86400
    for key, n in pairs(store()) do
        local needsOK = type(n) == "table" and (Paybacks.NeedsAt(n) or 0) >= since
        local gearOK = type(n) == "table" and (tonumber(n.gearAt) or 0) >= since
        if not needsOK and not gearOK then
            store()[key] = nil
        else
            local copy = { name = n.name, to = n.to }
            if needsOK then copy.level, copy.class, copy.bags, copy.fires = n.level, n.class, n.bags, n.fires end
            if gearOK then copy.main, copy.ranged, copy.quiver, copy.empty = n.main, n.ranged, n.quiver, n.empty end
            out[key] = copy
        end
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
ns.Comms.Register("E", {
    kind = "gear",
    module = "Paybacks",
    channels = { WHISPER = true },
    decode = function(rest)
        local gear = Paybacks.DecodeGear(rest)
        return gear and { gear = gear } or nil
    end,
    hear = function(name, msg) return Paybacks.HearGear(name, msg.gear) end,
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
    local name, _, _, itemLevel, minLevel, _, _, _, equipLoc, _, _, classID, subclassID = call(getInfo, itemID)
    if not name then return nil end
    local f = { name = name, minLevel = tonumber(minLevel) or 0, itemLevel = tonumber(itemLevel) or 0,
        equipLoc = type(equipLoc) == "string" and equipLoc or nil, classID = tonumber(classID), subclassID = tonumber(subclassID) }
    if (f.classID == Paybacks.CONTAINER and f.subclassID == Paybacks.BAG) or f.classID == Paybacks.QUIVER then
        f.slots = tooltipSlots(itemID)
        if not f.slots then return nil end -- not known yet: no idea rather than a wrong one
    end
    facts[itemID] = f
    return f
end

-- Matching (pure) -----------------------------------------------------------------------------------


--- Pure: is an item of required level `minLevel` (else item level `itemLevel`) for a player of `level`? At or
--- under their level (an item level up to 5 over), and no more than LEVEL_BAND under.
function Paybacks.ForLevel(minLevel, itemLevel, level)
    level = tonumber(level) or 0
    local req, slack = tonumber(minLevel) or 0, 0
    if req <= 0 then req, slack = tonumber(itemLevel) or 0, 5 end
    if req <= 0 then return true end -- nothing to go by
    return req <= level + slack and req >= level - Paybacks.LEVEL_BAND
end

-- One check per kind: `idea` (the kind and why, with `score` to pick the best of a kind) or a "not suggested" note.
local function check(itemID, f, needs, first)
    local level = tonumber(needs.level) or 0
    local function forLevel() return Paybacks.ForLevel(f.minLevel, f.itemLevel, level) end
    -- Bags (any profession's).
    if f.classID == Paybacks.CONTAINER and f.subclassID == Paybacks.BAG and f.slots then
        local small = nil
        for _, n in ipairs(needs.bags or {}) do
            n = tonumber(n) or 0
            if not small or n < small then small = n end
        end
        if not small then return nil end
        local want = 0
        for _, n in ipairs(needs.bags or {}) do if (tonumber(n) or 0) < f.slots then want = want + 1 end end
        if want == 0 then return nil, string.format("%d slots: no bigger than %s's", f.slots, first) end
        return { kind = "bag", slots = f.slots, want = want, score = f.slots,
            why = small == 0 and string.format("%s has an empty bag slot; this one holds %d", first, f.slots)
                or string.format("%s's smallest bag holds %d; this one holds %d", first, small, f.slots) }
    end
    -- A quiver (bow, crossbow) or ammo pouch (gun), for a hunter with none or a smaller one (Leatherworking).
    if f.classID == Paybacks.QUIVER and f.slots then
        if needs.class ~= "HUNTER" or not needs.ranged then return nil end
        local wantKind = needs.ranged == "gun" and 3 or (needs.ranged == "bow" or needs.ranged == "crossbow") and 2 or nil
        if f.subclassID ~= wantKind or not forLevel() then return nil end -- by level too (Codex review, 2026-11-22)
        if (tonumber(needs.quiver) or 0) >= f.slots then
            return nil, string.format("%d slots: no bigger than %s's", f.slots, first)
        end
        return { kind = "quiver", slots = f.slots, want = 1, score = f.slots,
            why = (tonumber(needs.quiver) or 0) == 0 and string.format("%s has no %s", first, wantKind == 3 and "ammo pouch" or "quiver")
                or string.format("%s's holds %d; this one holds %d", first, needs.quiver, f.slots) }
    end
    -- Armor, a cloak or a shirt for an empty slot, of the armor the class wears best (cloaks and shirts: any).
    local slot = f.equipLoc and Paybacks.SLOT_OF[f.equipLoc]
    if f.classID == Paybacks.ARMOR and slot and type(needs.empty) == "table" then
        local empty = false
        for _, s in ipairs(needs.empty) do if s == slot then empty = true end end
        if not empty or not forLevel() then return nil end
        local wears = Paybacks.ArmorFor(needs.class, level)
        local any = slot == 15 or slot == 4 -- a cloak or a shirt, whoever wears it
        if not any and f.subclassID ~= wears then
            if wears then return nil, string.format("%s wears %s", first, Paybacks.ARMOR_NAMES[wears]) end
            return nil
        end
        return { kind = "armor", slot = slot, want = 1, score = (f.minLevel > 0 and f.minLevel or f.itemLevel) * 100 + slot,
            why = string.format("%s has nothing on their %s", first, Paybacks.SLOT_NAMES[slot] or "slot") }
    end
    -- A wand for a wand user with an empty ranged slot (Enchanting).
    if f.classID == Paybacks.WEAPON and f.subclassID == 19 then
        if not Paybacks.WAND_CLASSES[needs.class or ""] or needs.ranged or needs.empty == nil or not forLevel() then return nil end
        return { kind = "wand", want = 1, score = f.minLevel, why = string.format("%s has no wand", first) }
    end
    -- The ammo their ranged weapon fires (Engineering), for their level.
    if f.classID == ns.Ammo.PROJECTILE then
        if not needs.fires then return nil, first .. " has no bow or gun equipped" end
        if f.subclassID ~= needs.fires or f.minLevel > level or f.minLevel < level - Paybacks.LEVEL_BAND then return nil end
        return { kind = "ammo", want = 1, minLevel = f.minLevel, score = f.minLevel,
            why = string.format("%s's ranged weapon fires %s", first, ns.Ammo.NAMES[needs.fires] or "it") }
    end
    -- A scope for a bow, crossbow or gun (Engineering).
    if Paybacks.SCOPES[itemID] then
        if needs.ranged ~= "bow" and needs.ranged ~= "gun" and needs.ranged ~= "crossbow" then return nil end
        if not forLevel() then return nil end
        return { kind = "scope", want = 1, score = f.itemLevel, why = string.format("%s has a %s", first, needs.ranged) }
    end
    -- A sharpening stone for a blade, a weightstone for a blunt weapon (Blacksmithing).
    if Paybacks.SHARPENING[itemID] or Paybacks.WEIGHTSTONE[itemID] then
        local fits = (Paybacks.SHARPENING[itemID] and needs.main == "blade") or (Paybacks.WEIGHTSTONE[itemID] and needs.main == "blunt")
        if not fits or not forLevel() then return nil end
        return { kind = "stone", want = 1, score = f.itemLevel,
            why = string.format("%s fights with a %s weapon", first, needs.main == "blade" and "bladed" or "blunt") }
    end
    -- Potions (Alchemy: healing for anyone, mana for a class with mana), food (Cooking), bandages (First Aid).
    if f.classID == Paybacks.CONSUMABLE and forLevel() then
        if f.subclassID == Paybacks.POTION and Paybacks.HEALING[itemID] then
            return { kind = "potion", want = 1, score = f.minLevel * 10 + 1, why = "healing potions for " .. first .. "'s level" }
        end
        if f.subclassID == Paybacks.POTION and Paybacks.MANA[itemID] then
            if Paybacks.NO_MANA[needs.class or ""] or not needs.class then return nil end
            return { kind = "potion", want = 1, score = f.minLevel * 10, why = "mana potions for " .. first .. "'s level" }
        end
        if f.subclassID == Paybacks.FOOD then
            return { kind = "food", want = 1, score = f.minLevel * 1000 + f.itemLevel, why = "food for " .. first .. "'s level" }
        end
        if f.subclassID == Paybacks.BANDAGE then
            return { kind = "bandage", want = 1, score = f.itemLevel, why = "bandages for " .. first .. "'s level" }
        end
    end
    return nil
end

--- Pure: the payback ideas for one player's needs note (with its gear note's fields when one came). `crafts`:
--- TierCheck.MyCrafts; `factsOf(itemID)`: Paybacks.Facts; `have(itemID)`: how many the bags hold. Returns the
--- ideas, the best of each kind (an armor piece per slot), best first, at most MAX_IDEAS:
--- { itemID, name, kind, slots, slot, want, why, reagents, canMake, missing = { { itemID, need } } },
--- and "not suggested" notes: { { name, why } }.
function Paybacks.Ideas(needs, crafts, factsOf, have)
    local ideas, notes = {}, {}
    if type(needs) ~= "table" then return ideas, notes end
    local first = tostring(needs.name or "they"):match("^(%S+)") or "they"
    local best = {} -- kind (or "armor:<slot>") -> idea
    for itemID, craft in pairs(crafts or {}) do
        local f = factsOf(itemID)
        if f then
            local idea, note = check(itemID, f, needs, first)
            if idea then
                idea.itemID, idea.name, idea.reagents = itemID, f.name, craft.reagents or {}
                local key = idea.kind == "armor" and ("armor:" .. idea.slot) or idea.kind
                local was = best[key]
                if not was or idea.score > was.score or (idea.score == was.score and itemID < was.itemID) then best[key] = idea end
            elseif note then
                notes[#notes + 1] = { name = f.name, why = note }
            end
        end
    end
    for _, idea in pairs(best) do
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
    table.sort(ideas, function(a, b)
        local ka, kb = Paybacks.KIND_ORDER[a.kind] or 99, Paybacks.KIND_ORDER[b.kind] or 99
        if ka ~= kb then return ka < kb end
        if a.score ~= b.score then return a.score > b.score end
        return a.itemID < b.itemID
    end)
    while #ideas > Paybacks.MAX_IDEAS do table.remove(ideas) end
    table.sort(notes, function(x, y) if x.name ~= y.name then return x.name < y.name end return x.why < y.why end)
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
