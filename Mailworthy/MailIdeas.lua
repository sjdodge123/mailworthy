-- The mail window's payback ideas (Paybacks.lua; docs/RECOMMENDATIONS.md, media/recommendations-prototype.html
-- view 2; operator, 2026-11-22): under the owed notice, for a player this account owes who left a needs note,
-- what this character's own professions make that they could use ("Woolen Bag: Aldric's smallest bag holds 6;
-- this one holds 8"), each with its materials and how many the bags have enough for, and "Not for <name>".
-- A heading with Fold (remembered) and up to three rows. Mailworthy never crafts: once the item is in the
-- bags, its row's pick button offers the player after Me (a payback for this visit).
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared
local W = ns.Widgets

UI.IDEA_ROWS = 3
S.IDEA_HEAD, S.IDEA_ROW = 24, 34
local NOT_WIDTH = 124

local head = {}  -- fold, label
local rows = {}  -- { label, notFor, idea }
local shownFor   -- the player the ideas on screen are for
local shownList = {}

function UI.Ideas() return shownList, shownFor end

local function nameOf(itemID)
    local f = ns.Paybacks.Facts(itemID)
    return f and f.name or ("item " .. tostring(itemID))
end

--- Pure: an idea's line. "Woolen Bag: Aldric's smallest bag holds 6; this one holds 8 (up to 4). Each: 3 Bolt
--- of Woolen Cloth, 1 Coarse Thread; you have enough for 4." `nameOf(itemID)`: an item's name.
function UI.IdeaText(idea, nameOf_)
    local parts = {}
    local ids = {}
    for id in pairs(idea.reagents or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do parts[#parts + 1] = idea.reagents[id] .. " " .. nameOf_(id) end
    local want = idea.want and idea.want > 1 and string.format(" (up to %d)", idea.want) or ""
    local can
    if idea.canMake > 0 then
        can = string.format("you have enough for %d", math.min(idea.canMake, idea.want or idea.canMake))
    else
        local missing = {}
        for _, m in ipairs(idea.missing or {}) do missing[#missing + 1] = m.need .. " " .. nameOf_(m.itemID) end
        table.sort(missing)
        can = "|cffff6b5bmissing " .. ns.Util.ListText(missing, "materials") .. "|r"
    end
    return string.format("|cffffd100%s|r: %s%s. Each: %s; %s.", idea.name, idea.why, want,
        #parts > 0 and table.concat(parts, ", ") or "?", can)
end

function S.CreateIdeas()
    local frame = S.frame
    head.fold = W.Button(frame, "-", 24, function()
        MailworthyDB.ideasFolded = not MailworthyDB.ideasFolded or nil
        UI.Refresh(true)
    end, "MailworthyMailIdeasFold")
    W.Tip(head.fold, "Fold", "Fold the payback ideas to one line, or open them.")
    head.label = W.Label(frame, "GameFontHighlightSmall")
    head.label:SetJustifyH("LEFT")
    for _, w in pairs(head) do w:Hide() end
    for i = 1, UI.IDEA_ROWS do
        local row = {}
        row.label = W.Label(frame, "GameFontHighlightSmall")
        row.label:SetJustifyH("LEFT")
        row.label:SetWidth(S.WIDTH - 52 - NOT_WIDTH - 8)
        row.notFor = W.Button(frame, "Not for them", NOT_WIDTH, function()
            if not row.idea or not shownFor then return end
            ns.Paybacks.Decline(shownFor, row.idea.itemID)
            ns.Log.Add("ui", "payback idea declined: %s for %s", tostring(row.idea.itemID), tostring(shownFor))
            UI.Refresh(true)
        end, "MailworthyMailIdeaNot" .. i)
        W.Tip(row.notFor, "Not for them", "Never suggest this item for this player again.")
        row.label:Hide()
        row.notFor:Hide()
        rows[i] = row
    end
end

--- The block for a scan; sets `shown.ideas` = { rows, folded } or nil (UI.Layout).
function S.FillIdeas(_, _, shown)
    for _, w in pairs(head) do w:Hide() end
    for _, row in ipairs(rows) do
        row.idea = nil
        row.label:Hide()
        row.notFor:Hide()
    end
    shown.ideas, shownFor, shownList = nil, nil, {}
    if not ns.Paybacks.On() then return end
    local ok, list = pcall(ns.Paybacks.ForDebts)
    if not ok then
        ns.Log.Add("ui", "payback ideas error: %s", tostring(list))
        return
    end
    local d
    for _, entry in ipairs(list) do
        if #entry.ideas > 0 then d = entry break end
    end
    if not d then return end
    shownFor, shownList = d.name, d.ideas
    local first = d.name:match("^(%S+)") or d.name
    local folded = MailworthyDB.ideasFolded == true
    head.fold:SetText(folded and "+" or "-")
    if folded then
        local names = {}
        for _, idea in ipairs(d.ideas) do names[#names + 1] = idea.name end
        head.label:SetText(string.format("|cffd99bf0Payback ideas for %s|r (%d): %s", first, #d.ideas, ns.Util.ListText(names, "")))
    else
        head.label:SetText(string.format("|cffd99bf0Payback ideas for %s|r: what you make that they could use", first))
    end
    head.fold:Show()
    head.label:Show()
    local n = 0
    if not folded then
        for i, row in ipairs(rows) do
            local idea = d.ideas[i]
            if idea then
                row.idea = idea
                row.label:SetText(UI.IdeaText(idea, nameOf))
                row.notFor:SetText("Not for " .. first)
                row.label:Show()
                row.notFor:Show()
                n = n + 1
            end
        end
    end
    shown.ideas = { rows = n, folded = folded }
end

--- Place the block from `y` down (MailBanners); returns the y under it.
function S.LayoutIdeas(y, n)
    local b = n.ideas
    if not b then return y end
    S.at(head.fold, 22, y + 2)
    S.at(head.label, 52, y - 2)
    head.label:SetWidth(S.WIDTH - 52 - 24)
    y = y - S.IDEA_HEAD
    for i = 1, b.rows do
        S.at(rows[i].label, 28, y)
        S.at(rows[i].notFor, -24, y + 2, "TOPRIGHT")
        y = y - S.IDEA_ROW
    end
    return y - 4
end
