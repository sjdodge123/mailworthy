-- Suggested bindings (docs/RECOMMENDATIONS.md, media/recommendations-prototype.html; operator, 2026-11-22):
-- the crafters around the player (their group, their own characters: Routes.Suggestions) who'd use some
-- of what's in the bags. This file keeps what the suggestions remember and says away from the mailbox;
-- the block in the mailbox window is MailSuggestions.lua.
--
--   - Folded: the block shrinks to one line, remembered for the account (MailworthyDB.suggestFolded).
--   - Seen: a suggestion the player has looked at (folded the block over it, or answered it)
--     (MailworthyDB.suggestSeen[realm|faction]["name|profession"]). One not seen yet opens a folded block
--     and is listed first.
--   - Not now: hidden for this mailbox visit (cleared at MAIL_CLOSED).
--   - Off: Settings > "Suggestions: off" (Config flag hideSuggestions) or /mw feature crafterOffer off.
--   - Away from the mailbox, one chat line per player and profession a session when a crafter in the
--     group could use something in the bags ("Dorn Ashby is in your group: their Engineering could use
--     your Copper Bar x10 and Rough Stone x20 at your next mailbox."). Never in combat; nothing is
--     mailed or bound by it.
local _, ns = ...

local Suggest = {}
ns.Suggest = Suggest

local Util = ns.Util

Suggest.DELAY = 3 -- seconds after a group change or a hello before the chat line's check
Suggest.ITEMS_SHOWN = 2 -- items named in a line before "and N more"

--- Suggestions show at all: the switch and the Settings choice.
function Suggest.On()
    return ns.Features.On("crafterOffer") and not ns.Config.Flag("hideSuggestions")
end

local function seenStore() return Util.Store(MailworthyDB, "suggestSeen", (Util.RealmKey())) end

--- Pure: a suggestion's key, "name|profession" (lower-case name).
function Suggest.Key(s) return tostring(s.name):lower() .. "|" .. tostring(tonumber(s.profession)) end

function Suggest.Seen(s) return seenStore()[Suggest.Key(s)] == true end

function Suggest.MarkSeen(list)
    local store = seenStore()
    for _, s in ipairs(list or {}) do store[Suggest.Key(s)] = true end
end

function Suggest.Folded() return MailworthyDB.suggestFolded == true end

function Suggest.SetFolded(on)
    MailworthyDB.suggestFolded = on and true or nil
    ns.Log.Add("suggest", "block %s", on and "folded" or "unfolded")
end

local notNow = false

--- Not now: no suggestions until the mailbox closes.
function Suggest.NotNow()
    notNow = true
    ns.Log.Add("suggest", "not now (this visit)")
end

function Suggest.Hidden() return notNow end

--- Pure: `list` with the ones `isNew(s)` says yes to first (each part in its order); second return:
--- whether any is new.
function Suggest.Order(list, isNew)
    local fresh, rest = {}, {}
    for _, s in ipairs(list or {}) do
        if isNew(s) then fresh[#fresh + 1] = s else rest[#rest + 1] = s end
    end
    local any = #fresh > 0
    for _, s in ipairs(rest) do fresh[#fresh + 1] = s end
    return fresh, any
end

--- Pure: "Wool Cloth x40 and Linen Cloth x18", "A x1, B x2 and 3 more" (items: { link, count }).
function Suggest.ItemsText(items, max)
    max = max or Suggest.ITEMS_SHOWN
    local parts = {}
    for i, item in ipairs(items or {}) do
        if i > max then
            parts[#parts + 1] = string.format("%d more", #items - max)
            break
        end
        local name = Util.LinkName(item.link) or "an item"
        parts[#parts + 1] = (tonumber(item.count) or 1) > 1 and (name .. " x" .. item.count) or name
    end
    return Util.ListText(parts, "nothing")
end

--- Pure: the chat line for a crafter in the group.
function Suggest.JoinText(s)
    return string.format("%s is in your group: their %s could use your %s at your next mailbox.", s.name,
        tostring(ns.Routes.ProfessionName(s.profession)), Suggest.ItemsText(s.items))
end

-- The chat line, away from the mailbox ------------------------------------------------------------

local announced = {} -- Suggest.Key -> true, this session
local pending, waitCombat, atMailbox = false, false, false

local function inCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() == true end

local function mailboxOpen()
    if atMailbox then return true end
    local frame = rawget(_G, "MailFrame") -- read only
    return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() == true
end

--- Value the bags and say, once a session, which crafter in the group could use what.
function Suggest.JoinCheck()
    pending = false
    if not Suggest.On() or mailboxOpen() then return end
    if inCombat() then
        waitCombat = true -- PLAYER_REGEN_ENABLED checks again
        return
    end
    if next(ns.Routes.GroupNames()) == nil then return end
    local ok, scan = pcall(ns.Bags.Evaluate, ns.Bags.Settings())
    if not ok then
        ns.Log.Add("suggest", "scan error: %s", tostring(scan))
        return
    end
    local okList, list = pcall(ns.Routes.Suggestions, scan, ns.Config.BankAlt())
    if not okList then
        ns.Log.Add("suggest", "suggestions error: %s", tostring(list))
        return
    end
    for _, s in ipairs(list) do
        local key = Suggest.Key(s)
        if s.party and not announced[key] then
            announced[key] = true
            ns.Log.Add("suggest", "said: %s for %s (%d rows)", tostring(s.profession), s.name, s.count)
            ns.Print(Suggest.JoinText(s))
        end
    end
end

local function schedule()
    if pending or not Suggest.On() then return end
    pending = true
    Util.After(Suggest.DELAY, Suggest.JoinCheck)
end

--- For specs: forget what was said this session.
function Suggest.Reset()
    announced, pending, waitCombat, notNow = {}, false, false, false
end

-- At the mailbox, the suggestions follow the group (Codex review, 2026-11-22: a new party member's
-- profession showed only after something else redrew the window). The list on screen is read again; never mid-send.
local function redrawMailbox()
    if atMailbox and ns.MailWindow and not ns.Mailer.Busy() then ns.MailWindow.RefreshIfShown() end
end

local lastGroup -- the group's names, joined: GROUP_ROSTER_UPDATE fires for much more than joins
ns.On("GROUP_ROSTER_UPDATE", function()
    local names = {}
    for name in pairs(ns.Routes.GroupNames()) do names[#names + 1] = name end
    table.sort(names)
    local key = table.concat(names, ",")
    if key == lastGroup then return end
    lastGroup = key
    redrawMailbox()
    if key ~= "" then schedule() end
end)
-- A party member's hello names their professions (Comms): check again.
ns.Comms.OnPeersChanged(function()
    if lastGroup and lastGroup ~= "" then
        redrawMailbox()
        schedule()
    end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if waitCombat then
        waitCombat = false
        schedule()
    end
end)
ns.On("MAIL_SHOW", function() atMailbox = true end)
ns.On("MAIL_CLOSED", function()
    atMailbox = false
    notNow = false
end)
