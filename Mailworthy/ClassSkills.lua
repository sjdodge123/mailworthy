-- Class skills (a CurseForge comment, 2026-11-20: "Could you add the option to send lockboxes to a
-- rogue friend/alt?"; operator, same day: "Lock boxes can route to rouges for training ...
-- comprehension items to mages(class specific profession)"). Two classes have a skill of their own
-- that levels on items anyone can loot: a rogue's Lockpicking on locked lockboxes, a mage's
-- Comprehension on scrolls. A class binding (Routes, "Rogue items to Bob") takes them like a
-- profession binding takes its materials: whatever their price, under the binding's cap when there is
-- one (operator: "Like profession mats"). On a rogue or a mage itself they stay in the bags, like a
-- profession's materials ("Yes, they stay"). Without a binding the normal rule applies, as before.
--
-- How an item is known:
-- 1. Lockboxes: Classic's by item ID (LOCKBOXES; each checked against Wowhead Classic's tooltip,
--    2026-11-20: all say "Locked" and "Requires Lockpicking (N)", none binds; no API, so it holds
--    before item data loads), or the tooltip's "Locked" line (LOCKED), or its "Requires Lockpicking
--    (N)" line (ITEM_MIN_SKILL).
-- 2. Comprehension scrolls: the tooltip's "Requires Comprehension (N)" line (ITEM_MIN_SKILL).
-- The tooltip is C_TooltipInfo.GetItemByID (TooltipInfoDocumentation.lua on Forever, as Classes.lua
-- and Conjured.lua read it). Forever's global strings aren't in the source mirror, so LOCKED and
-- ITEM_MIN_SKILL are nil-checked with the English text as the fallback, and the skill's name is
-- compared in English (README "Beta unknowns"; /mw report says what was found). Every call is
-- pcall'd. A "neither" answer is remembered only once the item's data is loaded
-- (C_Item.IsItemDataCachedByID), and forgotten at each mailbox visit.
--
-- A lockbox someone already picked (unlocked, not opened yet) trains nobody: its bag slot's own
-- tooltip (C_TooltipInfo.GetBagItem, same documentation) has no "Locked" line any more. It is then
-- no lockbox for a binding or for a rogue's keep, and follows the normal rule as before.
local _, ns = ...

local ClassSkills = {}
ns.ClassSkills = ClassSkills

ClassSkills.LOCKPICKING = "lockpicking"
ClassSkills.COMPREHENSION = "comprehension"

-- id -> the class that has the skill, the skill's English name (what ITEM_MIN_SKILL names), and
-- what its items are called on a row ("Lockboxes go to Bob").
ClassSkills.SKILLS = {
    lockpicking = { class = "ROGUE", name = "Lockpicking", items = "lockboxes" },
    comprehension = { class = "MAGE", name = "Comprehension", items = "Comprehension scrolls" },
}
ClassSkills.ORDER = { "comprehension", "lockpicking" }

ClassSkills.LOCKED = "Locked"              -- LOCKED in English
ClassSkills.MIN_SKILL = "Requires %s (%d)" -- ITEM_MIN_SKILL in English

-- Classic's lockboxes, junkboxes and locked chests (tradeable, "Locked", "Requires Lockpicking").
ClassSkills.LOCKBOXES = {
    [4632] = "Ornate Bronze Lockbox", [4633] = "Heavy Bronze Lockbox", [4634] = "Iron Lockbox",
    [4636] = "Strong Iron Lockbox", [4637] = "Steel Lockbox", [4638] = "Reinforced Steel Lockbox",
    [5758] = "Mithril Lockbox", [5759] = "Thorium Lockbox", [5760] = "Eternium Lockbox",
    [16882] = "Battered Junkbox", [16883] = "Worn Junkbox", [16884] = "Sturdy Junkbox", [16885] = "Heavy Junkbox",
    [6354] = "Small Locked Chest", [6355] = "Sturdy Locked Chest", [13875] = "Ironbound Locked Chest",
    [13918] = "Reinforced Locked Chest",
}

-- itemID -> a skill id (the tooltip names it) / false (it doesn't, and the item's data was loaded)
local cache = {}

local call = ns.Util.Call

-- The text of a tooltip data line (surfaced field, or the args of an older client).
local function lineText(line)
    if type(line) ~= "table" then return nil end
    if type(line.leftText) == "string" then return line.leftText end
    for _, arg in ipairs(type(line.args) == "table" and line.args or {}) do
        if type(arg) == "table" and arg.field == "leftText" then return arg.stringVal end
    end
    return nil
end

-- A line's text without colour codes (|cAARRGGBB, |cnNAME:) or spaces around it.
local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]+:", ""):gsub("|r", ""):match("^%s*(.-)%s*$"))
end

--- Pure: a Lua pattern for the client's "Requires %s (%d)" (ITEM_MIN_SKILL; "%1$s" forms too),
--- capturing the skill's name.
function ClassSkills.SkillPattern(format)
    format = type(format) == "string" and format:find("%%%d*%$?s") and format or ClassSkills.MIN_SKILL
    local p = format:gsub("%%%d+%$", "%%"):gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    return "^" .. p:gsub("%%s", "(.-)"):gsub("%%d", "%%d+") .. "$"
end

-- A line's parts: the two texts may share one line ("Locked", a line break, "Requires Lockpicking (1)").
local function split(text)
    local list = {}
    for part in plain(text):gmatch("[^\r\n]+") do list[#list + 1] = part:match("^%s*(.-)%s*$") end
    return list
end

--- Pure: is this tooltip line the "Locked" line? `label` is LOCKED (the client's own text).
function ClassSkills.IsLockedLine(text, label)
    if type(text) ~= "string" then return false end
    label = type(label) == "string" and label ~= "" and label or ClassSkills.LOCKED
    for _, part in ipairs(split(text)) do
        if part == label then return true end
    end
    return false
end

--- Pure: the class skill a tooltip's lines name ("lockpicking" / "comprehension"), or nil.
--- `texts`: the lines' texts; `locked`: LOCKED; `minSkill`: ITEM_MIN_SKILL.
function ClassSkills.Read(texts, locked, minSkill)
    local pattern = ClassSkills.SkillPattern(minSkill)
    local found
    for _, text in ipairs(texts or {}) do
        if type(text) == "string" then
            if ClassSkills.IsLockedLine(text, locked) then return ClassSkills.LOCKPICKING end
            for _, part in ipairs(split(text)) do
                local name = part:match(pattern)
                for _, id in ipairs(ClassSkills.ORDER) do
                    if name and name:lower() == ClassSkills.SKILLS[id].name:lower() then found = found or id end
                end
            end
        end
    end
    return found
end

-- Is the item's data loaded, so its tooltip is whole? Unknown (no such call) counts as no.
local function loaded(itemID)
    local items = rawget(_G, "C_Item")
    return type(items) == "table" and call(items.IsItemDataCachedByID, itemID) == true
end

local function texts(data)
    local list = {}
    for _, line in ipairs(data.lines) do list[#list + 1] = lineText(line) or false end
    return list
end

--- Pure: is this item ID one of Classic's lockboxes?
function ClassSkills.Known(itemID)
    return ClassSkills.LOCKBOXES[tonumber(itemID) or -1] ~= nil
end

--- The class skill an item trains ("lockpicking" for a lockbox, "comprehension" for a mage's
--- scroll), or false. A "neither" is asked again next time until the item's data is loaded.
function ClassSkills.Of(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    if ClassSkills.Known(itemID) then return ClassSkills.LOCKPICKING end
    if cache[itemID] ~= nil then return cache[itemID] end
    local info = rawget(_G, "C_TooltipInfo")
    local data = type(info) == "table" and call(info.GetItemByID, itemID) or nil
    if type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    local id = ClassSkills.Read(texts(data), rawget(_G, "LOCKED"), rawget(_G, "ITEM_MIN_SKILL"))
    if id then
        cache[itemID] = id
        return id
    end
    if #data.lines > 0 and loaded(itemID) then cache[itemID] = false end
    return false
end

--- Is the lockbox in this bag slot already unlocked: its own tooltip, read whole, has no "Locked"
--- line? false when it can't be told (no such call, the tooltip not loaded yet): it counts as locked.
function ClassSkills.Opened(bag, slot, itemID)
    local info = rawget(_G, "C_TooltipInfo")
    local data = type(info) == "table" and call(info.GetBagItem, bag, slot) or nil
    if type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines == 0 or not loaded(itemID) then return false end
    local label = rawget(_G, "LOCKED")
    for _, line in ipairs(data.lines) do
        if ClassSkills.IsLockedLine(lineText(line), label) then return false end
    end
    return true
end

--- The class skill a bag item (Bags.Group's shape: itemID, slots) trains right now, or nil: a
--- lockbox only while every one of its slots is still locked.
function ClassSkills.For(item)
    local id = ClassSkills.Of(item.itemID)
    if not id then return nil end
    if id == ClassSkills.LOCKPICKING then
        for _, s in ipairs(item.slots or {}) do
            if ClassSkills.Opened(s.bag, s.slot, item.itemID) then return nil end
        end
    end
    return id
end

--- Pure: the skill ids of a class token ("ROGUE" -> { "lockpicking" }).
function ClassSkills.OfClass(class)
    local list = {}
    for _, id in ipairs(ClassSkills.ORDER) do
        if class ~= nil and ClassSkills.SKILLS[id].class == class then list[#list + 1] = id end
    end
    return list
end

--- Pure: what a class binding takes beside the class-only items ("lockboxes" for "ROGUE"), or nil.
function ClassSkills.ItemsText(class)
    local parts = {}
    for _, id in ipairs(ClassSkills.OfClass(class)) do parts[#parts + 1] = ClassSkills.SKILLS[id].items end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

--- How an item is known: "item ID", "tooltip", or nil when it trains no class skill.
function ClassSkills.How(itemID)
    if ClassSkills.Known(itemID) then return "item ID" end
    return ClassSkills.Of(itemID) and "tooltip" or nil
end

--- /mw report: whether the client has the tooltip's texts, and what in the bags trains a class skill.
function ClassSkills.ReportLines()
    local locked, minSkill = rawget(_G, "LOCKED"), rawget(_G, "ITEM_MIN_SKILL")
    local names = {}
    for _, item in ipairs(ns.Bags.Group(ns.Bags.Slots())) do
        local id, how = ClassSkills.Of(item.itemID), ClassSkills.How(item.itemID)
        if id and how then
            local opened = id == ClassSkills.LOCKPICKING and ClassSkills.For(item) == nil
            names[#names + 1] = string.format("%s (%s, %s%s)", tostring(item.link), ClassSkills.SKILLS[id].name, how,
                opened and ", already unlocked: the normal rule" or "")
        end
    end
    return { string.format("class skills (lockboxes, Comprehension scrolls): %s, %s; in your bags: %s",
        type(locked) == "string" and ("LOCKED = \"" .. locked .. "\"")
            or "no LOCKED text, comparing with \"" .. ClassSkills.LOCKED .. "\"",
        type(minSkill) == "string" and ("ITEM_MIN_SKILL = \"" .. minSkill .. "\"")
            or "no ITEM_MIN_SKILL text, comparing with \"" .. ClassSkills.MIN_SKILL .. "\"",
        #names > 0 and table.concat(names, ", ") or "none") }
end

--- Forget what the tooltips said ("neither" only, by default: a found line stays found).
function ClassSkills.Forget(all)
    if all then cache = {} return end
    for itemID, id in pairs(cache) do
        if id == false then cache[itemID] = nil end
    end
end

-- Each mailbox visit asks the tooltips again, once.
ns.On("MAIL_SHOW", function() ClassSkills.Forget() end)
