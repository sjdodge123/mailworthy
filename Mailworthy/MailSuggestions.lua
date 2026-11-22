-- The mail window's suggested bindings (Routes.Suggestions, Suggest.lua; docs/RECOMMENDATIONS.md,
-- media/recommendations-prototype.html; operator, 2026-11-22). It grows the own-crafter offer (QoL pass F)
-- to the player's group: crafters in the party (their Mailworthy's hello, or the guild roster for a guild
-- member) and this account's own characters, each for a profession that would take some of the list.
--
--   - One suggestion: today's one-line offer, no heading ("Not now" beside its buttons).
--   - Several: a heading ("Suggested", fold, More, Not now) over up to three rows, More pages.
--   - Each row: While grouped (a party member: until one of you leaves the group) or This visit (an alt:
--     until the mailbox closes), Bind (an ordinary binding, as the offer's), Not for <name> (never again
--     for that player and profession). Any of them redraws the list before anything is sent: the rows
--     go "to <name>", with a To: line, and the binding shows in the bindings block with Remove.
--   - Fold: one line, remembered; a suggestion not seen yet opens it again, comes first and is tagged "new".
--   - The mouse or the controller's highlight on a row's button lights the list rows it would take.
--   - Never a price on a suggestion (operator: "I want to encourage paying back. if we have the value
--     listed people might think twice").
-- Every button is an ordinary Mailworthy button on this window: the D-pad reaches them (Nav).
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared
local W = ns.Widgets

UI.SUGGEST_ROWS = 3
S.SUGGEST_HEAD, S.SUGGEST_ROW = 24, 50
local GAP = 4
local WIDTH = { fold = 24, more = 84, notNow = 76, short = 104, bind = 56, notFor = 124 }

local head = {}   -- fold, label, more, notNow
local rows = {}   -- { label, short, bind, notFor, s }
local list = {}   -- the suggestions on screen, in order
local page = 1
local rowOfButton = {} -- a row's button -> the row

--- The first suggestion on screen (the offer, as it was), or nil; the whole list, for specs.
function UI.Offer() return list[1] end
function UI.Suggestions() return list end

local function tagsText(s)
    local tags = {}
    if s.sources and s.sources.party then tags[#tags + 1] = "party" end
    if s.sources and s.sources.guild then tags[#tags + 1] = "guild" end
    return #tags > 0 and (" |cff888888(" .. table.concat(tags, ", ") .. ")|r") or ""
end

--- Pure: a suggestion's line. An alt: "Sadie Ember is your enchanter (skill 140). Send them the 3 items
--- that disenchant instead?" (the own-crafter offer's words); a party member: "Grace Thorn (party, guild)
--- is a tailor in your group (skill 125). Send them Wool Cloth x40 and Linen Cloth x18?"
function UI.OfferText(o)
    local craft = ns.Routes.CRAFTER[o.profession]
    local skill = o.skill and string.format(" (skill %d)", o.skill) or ""
    if o.party then
        local who = craft and ("is a " .. craft .. " in your group")
            or ("has " .. tostring(ns.Routes.ProfessionName(o.profession)) .. " and is in your group")
        return string.format("|cffffd100%s|r%s %s%s. Send them %s?", o.name, tagsText(o), who, skill,
            ns.Suggest.ItemsText(o.items))
    end
    local who = craft and string.format("%s is your %s", o.name, craft)
        or string.format("%s has %s", o.name, tostring(ns.Routes.ProfessionName(o.profession)))
    local what = string.format("%d item%s %s", o.count, o.count == 1 and "" or "s",
        -- "that disenchant" only when every one is gear: dust and recipes are not disenchanted.
        o.profession == ns.Routes.ENCHANTING and o.gearOnly and (o.count == 1 and "that disenchants" or "that disenchant")
            or "they craft with")
    return string.format("|cffffd100%s|r%s. Send them the %s instead?", who, skill, what)
end

--- Pure: the heading's line: "Suggested (3): Grace, Brann and Sadie" folded, else
--- "Suggested: 3 crafters around you could use some of this".
function UI.SuggestHeadText(shown, folded)
    if folded then
        local names = {}
        for _, s in ipairs(shown) do names[#names + 1] = S.firstName(s.name) end
        return string.format("|cffffd100Suggested|r (%d): %s", #shown, ns.Util.ListText(names, ""))
    end
    return string.format("|cffffd100Suggested|r: %d crafters around you could use some of this", #shown)
end

--- Pure: the short-lived choice's button text for a suggestion.
function UI.ShortText(s) return s.scope == "group" and "While grouped" or "This visit" end

-- The list rows a suggestion takes light up while its button has the mouse or the highlight.
local function light(row)
    if S.LightRows then S.LightRows(row and row.s and row.s.items or nil) end
end

local function accept(row, forGood)
    local s = row.s
    if not s or ns.Mailer.Busy() then return end
    ns.lastCommand = "Mailworthy suggestion " .. (forGood and "Bind" or UI.ShortText(s))
    ns.Suggest.MarkSeen({ s })
    local route, why
    if forGood then
        route, why = ns.Routes.Add(s.name, s.profession)
    else
        route, why = ns.Routes.AddTemp(s.name, s.profession, s.scope)
    end
    if route then
        local what = ns.Routes.What(route)
        ns.Print(forGood
            and string.format("Bound: %s to %s. Check the list, then press Send. Remove it under Bindings or Mail routing...", what, s.name)
            or string.format("%s to %s %s. Check the list, then press Send.", what, s.name, ns.Routes.TEMP[s.scope]))
    else
        ns.Print("Not bound: " .. tostring(why) .. ".")
    end
    light(nil)
    ns.Mailer.Dismiss()
    UI.Refresh()
end

local function decline(row)
    local s = row.s
    if not s then return end
    ns.Routes.DismissOffer(s.name, s.profession)
    ns.Suggest.MarkSeen({ s })
    ns.Log.Add("ui", "suggestion declined: %s for %s", tostring(s.profession), tostring(s.name))
    light(nil)
    UI.Refresh(true)
end

--- Bind on the first suggestion (the offer's Bind, as it was).
function UI.AcceptOffer() if rows[1] then accept(rows[1], true) end end
--- Not for <name> on the first suggestion.
function UI.DeclineOffer() if rows[1] then decline(rows[1]) end end

local function lit(b, row)
    rowOfButton[b] = row
    b:HookScript("OnEnter", function() light(row) end)
    b:HookScript("OnLeave", function() light(nil) end)
end

--- At login (MailBanners' CreateBanners): the heading and the rows, hidden.
function S.CreateSuggestions()
    local frame = S.frame
    head.fold = W.Button(frame, "-", WIDTH.fold, function()
        local folding = not ns.Suggest.Folded()
        if folding then ns.Suggest.MarkSeen(list) end
        ns.Suggest.SetFolded(folding)
        UI.Refresh(true)
    end, "MailworthyMailSuggestFold")
    W.Tip(head.fold, "Fold", "Fold the suggestions to one line, or open them. A suggestion you haven't seen opens them again.")
    head.label = W.Label(frame, "GameFontHighlightSmall")
    head.label:SetJustifyH("LEFT")
    head.more = W.Button(frame, "More", WIDTH.more, function()
        page = page + 1
        UI.Refresh(true)
    end, "MailworthyMailSuggestMore")
    head.notNow = W.Button(frame, "Not now", WIDTH.notNow, function()
        ns.Suggest.NotNow()
        light(nil)
        UI.Refresh(true)
    end, "MailworthyMailSuggestNotNow")
    W.Tip(head.notNow, "Not now", "Hide the suggestions until you close the mailbox. Settings > Suggestions turns them off.")
    for _, w in pairs(head) do w:Hide() end
    for i = 1, UI.SUGGEST_ROWS do
        local suffix = i == 1 and "" or tostring(i)
        local row = {}
        row.label = W.Label(frame, "GameFontHighlightSmall")
        row.label:SetWidth(S.WIDTH - 52)
        row.label:SetJustifyH("LEFT")
        row.short = W.Button(frame, "This visit", WIDTH.short, function() accept(row, false) end, "MailworthyMailOfferVisit" .. suffix)
        row.bind = W.Button(frame, "Bind", WIDTH.bind, function() accept(row, true) end, "MailworthyMailOfferBind" .. suffix)
        row.notFor = W.Button(frame, "Not for them", WIDTH.notFor, function() decline(row) end, "MailworthyMailOfferNot" .. suffix)
        W.Tip(row.short, "Just for now", function()
            return row.s and row.s.scope == "group" and "Their materials go to them until one of you leaves the group."
                or "Their materials go to them this visit only."
        end)
        W.Tip(row.bind, "Bind", "A binding that stays until you remove it (Bindings or Mail routing...).")
        W.Tip(row.notFor, "Not for them", "Never suggest this player for this profession again.")
        for _, b in ipairs({ row.short, row.bind, row.notFor }) do lit(b, row) end
        for _, w in ipairs({ row.label, row.short, row.bind, row.notFor }) do w:Hide() end
        rows[i] = row
    end
    -- The controller's highlight on a row's button lights its list rows too.
    ns.Nav.OnSelect(function(button)
        local row = button and rowOfButton[button]
        light(row)
    end)
end

local function hideAll()
    for _, w in pairs(head) do w:Hide() end
    for _, row in ipairs(rows) do
        row.s = nil
        for _, w in ipairs({ row.label, row.short, row.bind, row.notFor }) do w:Hide() end
    end
end

local function fillRow(row, s)
    row.s = s
    row.label:SetText(UI.OfferText(s) .. (s.new and "  |cff33ff99new|r" or ""))
    row.short:SetText(UI.ShortText(s))
    row.notFor:SetText("Not for " .. S.firstName(s.name))
    for _, w in ipairs({ row.label, row.short, row.bind, row.notFor }) do w:Show() end
end

--- The block for a scan; sets `shown.suggest` = { head, rows, one } or nil (UI.Layout).
function S.FillSuggestions(result, ctx, shown)
    local found = {}
    if ns.Suggest.On() and not ctx.busy and not ns.Suggest.Hidden() then
        local ok, l = pcall(ns.Routes.Suggestions, result, ctx.bankAlt)
        if ok then found = l else ns.Log.Add("ui", "suggestions error: %s", tostring(l)) end
    end
    for _, s in ipairs(found) do s.new = not ns.Suggest.Seen(s) end -- not looked at yet: tagged, and first
    local any
    found, any = ns.Suggest.Order(found, function(s) return s.new end)
    if any and ns.Suggest.Folded() then
        ns.Suggest.SetFolded(false) -- something new: open again, on its first page
        page = 1
    end
    list = found
    hideAll()
    shown.suggest = nil
    if #list == 0 then return end
    local folded = ns.Suggest.Folded()
    if folded then
        head.fold:SetText("+")
        head.label:SetText(UI.SuggestHeadText(list, true))
        for _, w in ipairs({ head.fold, head.label, head.notNow }) do w:Show() end
        shown.suggest = { head = true, rows = 0 }
        return
    end
    if #list == 1 then
        fillRow(rows[1], list[1])
        head.notNow:Show()
        shown.suggest = { head = false, rows = 1, one = true }
        return
    end
    local pages = math.ceil(#list / UI.SUGGEST_ROWS)
    if page > pages then page = 1 end
    head.fold:SetText("-")
    head.label:SetText(UI.SuggestHeadText(list, false))
    for _, w in ipairs({ head.fold, head.label, head.notNow }) do w:Show() end
    if pages > 1 then
        head.more:SetText(string.format("More (%d/%d)", page, pages))
        head.more:Show()
    end
    local n = 0
    for i = 1, UI.SUGGEST_ROWS do
        local s = list[(page - 1) * UI.SUGGEST_ROWS + i]
        if s then
            fillRow(rows[i], s)
            n = n + 1
        end
    end
    shown.suggest = { head = true, rows = n }
end

--- Place the block from `y` down (MailBanners' LayoutBanners); returns the y under it.
function S.LayoutSuggestions(y, n)
    local sg = n.suggest
    if not sg then return y end
    local at = S.at
    if sg.head then
        at(head.fold, 22, y + 2)
        at(head.label, 22 + WIDTH.fold + 6, y - 2)
        at(head.notNow, -24, y + 2, "TOPRIGHT")
        at(head.more, -24 - WIDTH.notNow - GAP, y + 2, "TOPRIGHT")
        head.label:SetWidth(S.WIDTH - 48 - WIDTH.fold - 6 - WIDTH.notNow - WIDTH.more - 2 * GAP)
        y = y - S.SUGGEST_HEAD
    end
    for i = 1, sg.rows do
        local row = rows[i]
        at(row.label, 28, y)
        local x, by = -24, y - 24
        for _, b in ipairs({ { row.notFor, WIDTH.notFor }, { row.bind, WIDTH.bind }, { row.short, WIDTH.short } }) do
            at(b[1], x, by, "TOPRIGHT")
            x = x - (tonumber(b[1]:GetWidth()) or b[2]) - GAP -- Widgets.Fit may have widened it
        end
        if sg.one then at(head.notNow, x, by, "TOPRIGHT") end
        y = y - S.SUGGEST_ROW
    end
    return y - 4
end
