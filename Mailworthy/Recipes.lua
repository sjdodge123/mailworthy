-- Recipes this character already knows (operator, 2026-11-14: "already known crafting recipes
-- should continue down regular routing rules. currently i have an already known recipe that is
-- saying to keep because I'm a cook"): a profession binding saved for all the account's characters
-- that names this one keeps its recipes here (Routes.Force, "for this character"); a recipe this
-- character has learned is no use to it, so that binding doesn't take it (Routes.Divert) and it
-- goes where the regular rules send it (a friend's binding, the bank alt, ...).
--
-- How it is known: the item tooltip's "Already known" line. C_TooltipInfo.GetItemByID
-- (TooltipInfoDocumentation.lua on Forever, as Conjured.lua reads it) builds the tooltip for this
-- character; the line has no type of its own (TooltipInfoSharedDocumentation.lua), so its text is
-- compared with ITEM_SPELL_KNOWN (a global string Forever's own trainer UI uses,
-- Blizzard_TrainerUI.lua), the English "Already known" when it is missing (README "Beta unknowns";
-- /mw report says what was found). Every call is pcall'd; no answer is "not known", so the binding
-- keeps the recipe as before. Answers are remembered for one mailbox visit (MAIL_SHOW forgets them);
-- a "not known" only once the item's data is loaded, and only until the next bag update (learning a
-- recipe uses its item up, so a copy left in the bags is read again).
local _, ns = ...

local Recipes = {}
ns.Recipes = Recipes

Recipes.LABEL = "Already known" -- ITEM_SPELL_KNOWN in English

-- itemID -> true (the tooltip has the line) / false (it doesn't, and the item's data was loaded)
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

--- Pure: is this tooltip line the "Already known" line? `label` is ITEM_SPELL_KNOWN (the client's
--- own text); colour codes (|cAARRGGBB, |cnNAME:) and spaces around it don't count.
function Recipes.IsKnownLine(text, label)
    if type(text) ~= "string" then return false end
    label = type(label) == "string" and label ~= "" and label or Recipes.LABEL
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]+:", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    return plain == label
end

-- Is the item's data loaded, so its tooltip is whole? Unknown (no such call) counts as no.
local function loaded(itemID)
    local items = rawget(_G, "C_Item")
    return type(items) == "table" and call(items.IsItemDataCachedByID, itemID) == true
end

--- Does this character already know the recipe (its tooltip says "Already known")? false when it
--- doesn't, or when the tooltip can't be read.
function Recipes.Known(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    if cache[itemID] ~= nil then return cache[itemID] end
    local info = rawget(_G, "C_TooltipInfo")
    local data = type(info) == "table" and call(info.GetItemByID, itemID) or nil
    if type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    local label = rawget(_G, "ITEM_SPELL_KNOWN")
    for _, line in ipairs(data.lines) do
        if Recipes.IsKnownLine(lineText(line), label) then
            cache[itemID] = true
            return true
        end
    end
    if #data.lines > 0 and loaded(itemID) then cache[itemID] = false end
    return false
end

--- Forget what the tooltips said: every answer, or (`unknownOnly`) the "not known" ones.
function Recipes.Forget(unknownOnly)
    if not unknownOnly then cache = {} return end
    for itemID, known in pairs(cache) do
        if known == false then cache[itemID] = nil end
    end
end

--- /mw report: whether the client has the tooltip's text, and which recipes in the bags it knows.
function Recipes.ReportLines()
    local label = rawget(_G, "ITEM_SPELL_KNOWN")
    local names, seen = {}, {}
    for _, s in ipairs(ns.Bags.Slots()) do
        if not seen[s.itemID] then
            seen[s.itemID] = true
            local classID, subclassID = ns.Prices.ClassID(s.link)
            if ns.Valuation.RecipeProfession({ classID = classID, subclassID = subclassID }) and Recipes.Known(s.itemID) then
                names[#names + 1] = tostring(s.link)
            end
        end
    end
    return { string.format("known recipes (regular rules, never a binding to this character): %s; in your bags: %s",
        type(label) == "string" and ("ITEM_SPELL_KNOWN = \"" .. label .. "\"")
            or "no ITEM_SPELL_KNOWN text, comparing with \"" .. Recipes.LABEL .. "\"",
        #names > 0 and table.concat(names, ", ") or "none") }
end

-- Each mailbox visit asks the tooltips again, once, and the bag tags' cached verdicts with them.
ns.On("MAIL_SHOW", function()
    Recipes.Forget()
    ns.Bags.InputsChanged("recipes", true)
end)
-- Learning a recipe uses its item up: the bag update that follows asks the "not known" ones again, so
-- another copy left in the bags is tagged as known (Codex review, 2026-11-14). Registered before
-- BankAlt's handler (Recipes.lua loads first, ns.Fire runs handlers in order), which redraws the tags.
ns.On("BAG_UPDATE_DELAYED", function() Recipes.Forget(true) end)
