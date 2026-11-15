-- The friends window (/mw friends, the settings' Friends button, the Mailworthy
-- window's Friends button; media/ux-pass-prototype.png), one view at a time:
--   list: the player's own bindings (then Guild... and Mail ledger...), each with its price cap stepper, scope (all my
--     characters / this character), for an Enchanting binding its Gear switch on a third line
--     ("Gear: all green and blue" / "Gear: only when disenchanting pays more";
--     media/disenchant-binding-prototype.png), where the mail goes (the friend, or the
--     character of theirs that has the profession, as their own Mailworthy
--     reported) and Remove; then "Add a binding...";
--   add, step 1: pick a player (party, guild, own characters, Mailworthy users;
--     online first; their professions shown); step 2: pick the profession (theirs
--     suggested). Binding saves and returns to the list; Back goes one step back.
--     For a guild rule, step 1 lists this character and the guild's members only and
--     the rule goes to the draft, back in the guild view;
--   guild (/mw guild, the settings' Guild button; 2026-11-07: "I want a new button for
--     guild inside the mailworthy settings, seems weird its in the friends tab"): who
--     shared the guild's template, "Guild rules: on / off" in one press, and its rules
--     (why one is left out here); for the guild master and officers (Guild.lua) the
--     rules being edited, each with its cap stepper and Remove (the Enchanting rule with its
--     Gear switch too; a member reads it on the rule's cap line), "Add a rule...",
--     "Publish to guild".
-- With no bindings and no guild template it opens straight on step 1. Every control is a
-- button, so the controller drives it (PadKey "settings" set, Nav); nothing needs typing.
local _, ns = ...


local UI = {}
ns.RoutesUI = UI

UI.BINDING_ROWS, UI.CANDIDATE_ROWS, UI.PROFESSION_ROWS = 4, 6, 9
local WIDTH = 560
local BIND_ROW, LIST_ROW = 50, 26
local GEAR_LINE = 26     -- an Enchanting row's third line: the Gear switch
local CAP_WIDTH = 220
local BIND_TOP = -92
local GUILD_LINE = -66   -- the guild template line in the guild view
local GUILD_HELP = -96   -- what the rules do, under it
local GUILD_TOP = -138   -- the first rule row in the guild view
local LIST_TOP = -72
UI.TITLE = { friends = "Send materials to friends", guild = "Guild materials" }

local W = ns.Widgets

local win, frame, views, bindHead, stepLabel, chosenLabel, emptyBindings, bindPager, candPager, refreshButton
local addButton, backButton, doneButton, ledgerButton, guildButton, hint
local guildLabel, guildToggle, publishButton
local bindingRows, candidateRows, professionRows = {}, {}, {}
local candidates, picked = {}, nil
local view = "list"
local guildFromList = false -- the guild view was opened from the list (its Guild... button): Back returns there
local marked -- a name on screen carries the Mailworthy mark: the footer says what it means
local target = "me" -- what the add view makes: "me" (a binding) or "guild" (a template rule)

function UI.Frame() return frame end
--- The line under the step label (the picked player, or the guild view's help).
function UI.ChosenLabel() return chosenLabel end
function UI.Picked() return picked end
--- "list" (the bindings), "add" (step 1: a player; step 2, once picked: the profession) or
--- "guild" (the guild template: on / off, its rules; the editor for the guild master and officers).
function UI.View() return view end
--- Whether a name in the current view carries the Mailworthy mark (its key is in the footer).
function UI.Marked() return marked end
--- The footer line (the mark's key, the controller legend), for specs.
function UI.Footer() return win and win.legend:GetText() end
--- What the add view makes: "me" (a binding) or "guild" (a guild template rule).
function UI.Target() return target end
--- The buttons each view shows (Widgets.Views), for specs.
function UI.Views() return views end

local function setHint(text) if hint then hint:SetText(text or "") end end

-- `text` (default: the name) with the Mailworthy mark when `name` runs Mailworthy (Comms.Mark).
local function withMark(name, text)
    local out, m = ns.Comms.Mark(name, text)
    marked = marked or m
    return out
end

local function at(widget, x, y, point) win.at(widget, x, y, point) end

--- Pure: the cap as the rule it is: "10s each or more: to my bank alt", or "no price cap".
function UI.CapText(route)
    if not route.cap then return "no price cap" end
    return ns.Valuation.Money(route.cap) .. " each or more: to my bank alt"
end

--- Pure: a guild rule in force has no buttons: its cap line also says the Gear switch when the
--- guild set it ("10s each or more: to my bank alt; gear only when disenchanting pays more").
function UI.GuildCapText(rule)
    local text = UI.CapText(rule)
    if ns.Routes.TakesGear(rule) and rule.gear == ns.Routes.GEAR_DE then
        text = text .. "; gear only when disenchanting pays more"
    end
    return text
end

--- Pure: what the footer says after a press on a binding's Gear switch (short: the list view's
--- footer line is narrow) or on a draft rule's.
function UI.GearHint(route, draft)
    local on = route and route.gear == ns.Routes.GEAR_DE
    if draft then
        return (on and "Enchanting: gear only when disenchanting pays more." or "Enchanting: all green and blue gear.")
            .. " Publish to guild to send the change."
    end
    return on and "Other gear follows your normal rule." or "All green and blue gear goes."
end

--- What the bound player mailed this account beyond what it mailed back (Ledger.lua), as a
--- grey suffix for their binding row, or "" (only this side ever shows).
function UI.OwedText(name)
    if not ns.Ledger.On() then return "" end
    local net = ns.Ledger.Net(name)
    if net <= 0 then return "" end
    return " |cffaaaaaa(you've received " .. ns.Valuation.Money(net) .. " more from them)|r"
end

--- Pure: the guild template line's text and its toggle's ("Guild rules: on" / "off" / "Use guild
--- rules" before the player chose), or nil toggle when there is no template. `fromText` shows in
--- place of the author's name (with the Mailworthy mark).
function UI.GuildText(template, canPublish, fromText)
    if not template then
        return canPublish and "No guild template yet: add a rule for each profession, then Publish to guild."
            or "No guild template yet: your guild master or an officer makes it here.", nil
    end
    local n = #(template.rules or {})
    local text = string.format("Guild template from %s: %d rule%s", fromText or tostring(template.from), n, n == 1 and "" or "s")
    if template.use == nil then return text .. " |cff33ff99(new)|r", "Use guild rules" end
    return text, template.use and "Guild rules: on" or "Guild rules: off"
end

-- A binding row's buttons act on what the row shows: row.kind "route" (a binding: Routes),
-- "draft" (a guild template rule being edited: Guild), "guild" (a guild rule in force: no buttons).
local function createBindingRows()
    for i = 1, UI.BINDING_ROWS do
        local row = {}
        row.text = W.Label(frame, "GameFontHighlight")
        row.text:SetWidth(420)
        row.text:SetJustifyH("LEFT")
        -- Two presses (UX review U7): "Sure?" for 3 seconds, the second press removes.
        row.remove = W.ConfirmButton(frame, "Remove", "Sure?", 80, function()
            if not row.key then return end
            if row.kind == "draft" then
                ns.Guild.DraftRemove(row.key)
                setHint("Rule removed. Publish to guild to send the change.")
                UI.Refresh()
            elseif ns.Routes.Remove(row.key) then
                setHint("Binding removed.")
                UI.Refresh()
                ns.MailWindow.RefreshIfShown()
            end
        end, "MailworthyFriendsRemove" .. i, function()
            setHint(row.kind == "draft" and "Press Remove again to take this rule out of the draft."
                or "Press Remove again to remove this binding.")
            UI.Refresh()
        end)
        row.cap = W.Label(frame, "GameFontHighlightSmall")
        row.cap:SetWidth(CAP_WIDTH)
        row.cap:SetJustifyH("LEFT")
        local function step(dir)
            if not row.key then return end
            if row.kind == "draft" then ns.Guild.DraftStepCap(row.key, dir) else ns.Routes.StepCap(row.key, dir) end
            UI.Refresh()
        end
        row.capDown = W.Button(frame, "-", 26, function() step(-1) end, "MailworthyFriendsCapDown" .. i)
        row.capUp = W.Button(frame, "+", 26, function() step(1) end, "MailworthyFriendsCapUp" .. i)
        row.scope = W.Button(frame, "", 150, function()
            if row.key and row.kind == "route" then ns.Routes.ToggleScope(row.key) end
            UI.Refresh()
        end, "MailworthyFriendsScope" .. i)
        -- The Gear switch (an Enchanting binding or draft rule only): one press, the text is the rule.
        row.gear = W.Button(frame, "", 300, function()
            if not row.key then return end
            if row.kind == "draft" then
                if not ns.Guild.DraftToggleGear(row.key) then return end
                for _, r in ipairs(ns.Guild.Draft() or {}) do
                    if tonumber(r.profession) == tonumber(row.key) then setHint(UI.GearHint(r, true)) end
                end
            elseif row.kind == "route" then
                if not ns.Routes.ToggleGear(row.key) then return end
                setHint(UI.GearHint(ns.Routes.Get(row.key)))
                ns.MailWindow.RefreshIfShown()
            end
            UI.Refresh()
        end, "MailworthyFriendsGear" .. i)
        row.widgets = { row.text, row.remove, row.cap, row.capDown, row.capUp, row.scope, row.gear }
        bindingRows[i] = row
    end
    emptyBindings = W.Label(frame, "GameFontHighlightSmall")
    emptyBindings:SetWidth(WIDTH - 56)
    emptyBindings:SetJustifyH("LEFT")
    bindPager = W.Pager(frame, "MailworthyFriendsBindPage", function() UI.Refresh() end)
    addButton = W.Button(frame, "Add a binding...", 140, function()
        target = view == "guild" and "guild" or "me"
        view, picked = "add", nil
        setHint("")
        UI.Reload(target == "guild" and "guild rule" or "binding")
        UI.Refresh()
    end, "MailworthyFriendsAdd")
end

local function placeRow(row, y)
    at(row.text, 28, y - 4)
    at(row.remove, -24, y, "TOPRIGHT")
    at(row.cap, 28, y - 28)
    at(row.capDown, 252, y - 24)
    at(row.capUp, 282, y - 24)
    at(row.scope, -24, y - 24, "TOPRIGHT")
    at(row.gear, 24, y - 24 - GEAR_LINE)
end

local function createGuild()
    guildLabel = W.Label(frame, "GameFontHighlight")
    guildLabel:SetWidth(WIDTH - 56 - 160)
    guildLabel:SetJustifyH("LEFT")
    guildToggle = W.Button(frame, "", 140, function()
        local was = ns.Guild.InUse()
        if ns.Guild.ToggleUse() then
            setHint(was and "Guild rules off: your materials no longer follow the guild template."
                or "Guild rules on: the guild's rules apply after your own bindings and professions.")
            ns.MailWindow.RefreshIfShown()
            local settings = ns.SettingsUI.Frame()
            if settings and settings:IsShown() then ns.SettingsUI.Refresh() end
        end
        UI.Refresh()
    end, "MailworthyFriendsGuildRules")
    -- Two presses (UX review U7): it goes to every member of the guild.
    publishButton = W.ConfirmButton(frame, "Publish to guild", "Sure?", 150, function()
        local ok, err = ns.Guild.Publish()
        if not ok then
            setHint("|cffff8040Not published: " .. tostring(err) .. ".|r")
        else
            local text = "Guild template published: " .. ns.Guild.RulesText(ns.Guild.Template().rules) .. "."
            setHint(text)
            ns.Print(text .. " Members who turn the guild rules on mail these materials.")
        end
        UI.Refresh()
    end, "MailworthyFriendsPublish", function()
        setHint("Press again to send these rules to every member of your guild.")
        UI.Refresh()
    end)
end

local function createAdd()
    stepLabel = W.Label(frame, "GameFontHighlight")
    stepLabel:SetPoint("TOPLEFT", 28, -46)
    stepLabel:SetWidth(WIDTH - 250)
    stepLabel:SetJustifyH("LEFT")
    refreshButton = W.Button(frame, "Refresh list", 100, function()
        UI.Reload("refresh")
        UI.Refresh()
    end, "MailworthyFriendsRefresh")
    refreshButton:SetPoint("TOPRIGHT", -24, -42)
    candPager = W.Pager(frame, "MailworthyFriendsPage", function() UI.Refresh() end)
    chosenLabel = W.Label(frame, "GameFontHighlightSmall")
    chosenLabel:SetPoint("TOPLEFT", 28, LIST_TOP - 2)
    chosenLabel:SetWidth(WIDTH - 56)
    chosenLabel:SetJustifyH("LEFT")
    for i = 1, UI.CANDIDATE_ROWS do
        local b = W.Button(frame, "", WIDTH - 48, function() UI.Pick(i) end, "MailworthyFriendsPick" .. i)
        b:SetPoint("TOPLEFT", 24, LIST_TOP - (i - 1) * LIST_ROW)
        b:Hide()
        candidateRows[i] = b
    end
    for i = 1, UI.PROFESSION_ROWS do
        local b = W.Button(frame, "", WIDTH - 48, function() UI.Bind(i) end, "MailworthyFriendsProfession" .. i)
        b:SetPoint("TOPLEFT", 24, LIST_TOP - 24 - (i - 1) * LIST_ROW)
        b:Hide()
        professionRows[i] = b
    end
    backButton = W.Button(frame, "Back", 100, function()
        if view == "add" and picked then
            picked = nil
        elseif view == "add" and target == "guild" then
            view = "guild"
        else
            view = "list"
        end
        setHint("")
        UI.Refresh()
    end, "MailworthyFriendsBack")
end

function UI.Create()
    if frame then return frame end
    win = W.Shell({ name = "MailworthyFriendsFrame", width = WIDTH, height = 400, title = UI.TITLE.friends,
        sub = "Each binding mails a profession's materials to one player, every time, until you remove it.",
        log = "friends window", refresh = function() UI.Refresh() end })
    frame = win.frame
    bindHead = W.Label(frame, "GameFontNormal")
    bindHead:SetText("Bindings")
    createBindingRows()
    createGuild()
    createAdd()
    hint = W.Label(frame, "GameFontHighlightSmall")
    hint:SetJustifyH("LEFT")
    hint:SetWidth(WIDTH - 56)
    doneButton = win.Done("MailworthyFriendsDone")
    ledgerButton = W.Button(frame, "Mail ledger...", 120, function() ns.LedgerUI.Show(frame) end, "MailworthyFriendsLedger")
    -- The guild view from the list (UX review U1: Settings' "Friends and guild..." opens this window).
    guildButton = W.Button(frame, "Guild...", 160, function() UI.OpenGuild(true) end, "MailworthyFriendsGuild")
    local pooled = { emptyBindings, bindPager.next, candPager.next, refreshButton, guildToggle, publishButton,
        addButton, backButton }
    for _, row in ipairs(bindingRows) do
        for _, w in ipairs(row.widgets) do pooled[#pooled + 1] = w end
    end
    for _, b in ipairs(candidateRows) do pooled[#pooled + 1] = b end
    for _, b in ipairs(professionRows) do pooled[#pooled + 1] = b end
    views = W.Views({
        list = { win.sub, bindHead, addButton, guildButton, ledgerButton, doneButton },
        guild = { stepLabel, guildLabel, chosenLabel, doneButton },
        add = { stepLabel, chosenLabel, backButton, doneButton },
    }, pooled)
    views.Show("list")
    return frame
end

--- Re-read who can be bound (the roster is asked for and other Mailworthys are asked to say
--- hello). For a guild rule: this character (its author), then guild members only.
local function gather(reason)
    candidates = ns.Routes.Candidates()
    -- You first (2026-11-14): bind a profession to yourself, one you have or plan to pick up.
    local me = ns.Routes.Me()
    if me and target ~= "guild" then table.insert(candidates, 1, me) end
    if target == "guild" then
        local members = { ns.Routes.Me() }
        for _, c in ipairs(candidates) do
            if c.sources.guild then members[#members + 1] = c end
        end
        candidates = members
    end
    ns.Log.Add("ui", "friends window: %d candidates (%s)", #candidates, tostring(reason))
end

function UI.Reload(reason)
    ns.Routes.RequestRoster()
    if ns.Comms then ns.Comms.Ask() end
    gather(reason)
end

function UI.Candidates() return candidates end

local function show(widgets, on)
    for _, w in ipairs(widgets) do
        if on then w:Show() else w:Hide() end
    end
end

--- Rows for `list` from `top`; `kindOf(r)` names each row's kind. Returns the y below the last row,
--- and below the pager, which sits under the list's last row when there is more than one page
--- (UX review U5: never on the heading line the D-pad has to walk back up to).
local function fillRows(list, top, kindOf, emptyText)
    local _, _, first = bindPager.Clamp(#list, UI.BINDING_ROWS)
    local shown, y = 0, top
    for i, row in ipairs(bindingRows) do
        local r = list[first + i]
        local kind = r and kindOf(r) or nil
        local key = r and (kind == "draft" and r.profession or r.key) or nil
        if key ~= row.key or kind ~= row.kind then W.Disarm(row.remove) end -- the row shows another one now
        row.kind, row.key = kind, key
        show(row.widgets, false)
        if r then
            placeRow(row, y)
            if row.kind == "draft" then
                local me = tostring(r.to):lower() == tostring(ns.PlayerName()):lower()
                row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. withMark(r.to) .. "|r"
                    .. (me and " |cffaaaaaa(you)|r" or ""))
            elseif row.kind == "guild" then
                local why = ns.Guild.Why(r, ns.Routes.Personal(), ns.Characters.Professions(), ns.PlayerName())
                row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. withMark(r.to) .. "|r"
                    .. (why and (" |cffaaaaaa(not here: " .. why .. ")|r") or ""))
            else
                local to, crafter = ns.Routes.Recipient(r)
                row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. withMark(r.to) .. "|r"
                    .. (crafter and (" |cffaaaaaa(delivered to " .. withMark(to) .. ")|r") or "") .. UI.OwedText(r.to))
            end
            -- A guild rule in force has no buttons: its cap line is wider and says the Gear switch.
            row.cap:SetWidth(row.kind == "guild" and (WIDTH - 56) or CAP_WIDTH)
            row.cap:SetText(row.kind == "guild" and UI.GuildCapText(r) or UI.CapText(r))
            row.scope:SetText(ns.Routes.SCOPES[r.scope] or tostring(r.scope))
            show({ row.text, row.cap }, true)
            show({ row.remove, row.capDown, row.capUp }, row.kind ~= "guild")
            show({ row.scope }, row.kind == "route")
            local gear = row.kind ~= "guild" and ns.Routes.GearText(r) or nil
            if gear then
                row.gear:SetText(gear)
                W.SetToggled(row.gear, r.gear == ns.Routes.GEAR_DE)
                row.gear:Show()
            end
            shown = shown + 1
            y = y - BIND_ROW - (gear and GEAR_LINE or 0)
        end
    end
    if #list == 0 then
        emptyBindings:SetText(emptyText)
        at(emptyBindings, 28, top - 4)
        emptyBindings:Show()
    else
        emptyBindings:Hide()
    end
    y = y - (shown == 0 and 30 or 0)
    if bindPager.Update() then
        at(bindPager.next, -24, y + 2, "TOPRIGHT")
        y = y - 28
    end
    return y
end

--- The hint on its own line above the bottom row (when it says something); returns the bottom row's y.
local function hintLine(y)
    local text = hint:GetText()
    if text and text ~= "" then
        at(hint, 28, y - 6)
        hint:Show()
        return y - 44
    end
    hint:Hide()
    return y - 10
end

--- Pure: what the guild view says under the template line.
function UI.GuildHelp(canPublish)
    if canPublish then
        return "Members who turn the guild rules on mail each profession's own materials to the player named "
            .. "(you too). Their own bindings and professions come first."
    end
    return "With the guild rules on, each profession's own materials go to the player named. "
        .. "Your own bindings and professions come first."
end

--- The guild view's head: the template line with its one-press toggle, then what the rules do.
local function fillGuildHead(canPublish)
    local name = ns.Guild.Mine()
    stepLabel:SetText("|cffffd100Guild template|r" .. (name and (" for " .. name) or ""))
    local text, toggle
    if not ns.Guild.On() then
        text = "The guild template is switched off (/mw feature guildTemplate on)."
    elseif not name then
        text = "Not in a guild (or the game hasn't said which yet)."
    else
        local template = ns.Guild.Template()
        text, toggle = UI.GuildText(template, canPublish, template and withMark(template.from) or nil)
    end
    guildLabel:SetText(text)
    at(guildLabel, 28, GUILD_LINE - 4)
    guildLabel:Show()
    if toggle then
        guildToggle:SetText(toggle)
        W.SetToggled(guildToggle, ns.Guild.InUse())
        at(guildToggle, -24, GUILD_LINE, "TOPRIGHT")
        guildToggle:Show()
    else
        guildToggle:Hide()
    end
    chosenLabel:SetText(name and ns.Guild.On() and UI.GuildHelp(canPublish) or "")
    at(chosenLabel, 28, GUILD_HELP)
    chosenLabel:Show()
end

local function fillCandidates()
    local _, _, first = candPager.Clamp(#candidates, UI.CANDIDATE_ROWS)
    local shown = 0
    for i, b in ipairs(candidateRows) do
        local c = candidates[first + i]
        if c then
            b:SetText(ns.Routes.CandidateText(c, withMark(c.name)))
            b:Show()
            shown = shown + 1
        else
            b:Hide()
        end
    end
    refreshButton:Show()
    if #candidates == 0 then
        stepLabel:SetText("|cffaaaaaa1 of 2|r  Nobody to " .. (target == "guild" and "name yet" or "bind yet"))
        chosenLabel:SetText(target == "guild" and "The guild roster may take a moment: press Refresh list."
            or ("Join a group, be in a guild (the roster may take a moment), or log in on another of "
            .. "your characters once, then press Refresh list."))
        chosenLabel:Show()
        return LIST_TOP - 40
    end
    stepLabel:SetText("|cffaaaaaa1 of 2|r  |cffffd100" .. (target == "guild" and "Which guild member gets them?"
        or "Who should get your materials?") .. "|r")
    return LIST_TOP - shown * LIST_ROW
end

--- Step 2's choices for the picked player: their class's items first when their class is known
--- (operator, 2026-11-08: a mage-only scroll to a mage friend; not for guild rules, which are
--- per profession), then every crafting profession. { { id, class, text, suggested }, ... }.
function UI.Options(candidate, forGuild)
    local list = {}
    local class = candidate and ns.Classes.Token(candidate.class)
    if class and not forGuild then
        local name = ns.Classes.Name(class)
        list[#list + 1] = { class = class, suggested = true,
            text = string.format("%s items (only a %s can use them)", name, name:lower()) }
    end
    local suggested = {}
    for _, p in ipairs(candidate and ns.Routes.Suggested(candidate) or {}) do suggested[p.id] = true end
    for _, p in ipairs(ns.Routes.Professions()) do
        list[#list + 1] = { id = p.id, text = p.name .. " (" .. p.mats .. ")", suggested = suggested[p.id] == true }
    end
    return list
end

local function fillProfessions()
    stepLabel:SetText("|cffaaaaaa2 of 2|r  |cffffd100What should "
        .. withMark(picked.name, tostring(picked.name):match("^(%S+)") or picked.name)
        .. " get" .. (target == "guild" and " from the guild" or "") .. "?|r")
    chosenLabel:SetText(ns.Routes.CandidateText(picked, withMark(picked.name)))
    chosenLabel:Show()
    local shown = 0
    local options = UI.Options(picked, target == "guild")
    for i, b in ipairs(professionRows) do
        local p = options[i]
        if p then
            b:SetText(p.text)
            W.SetToggled(b, p.suggested) -- suggested: the green fill (UX review U6: one way to show it)
            b:Show()
            shown = shown + 1
        else
            b:Hide()
        end
    end
    if hint:GetText() == nil or hint:GetText() == "" then
        setHint("Over the cap (" .. ns.Valuation.Money(ns.Routes.DEFAULT_CAP) .. " each to start) a material goes to "
            .. "your bank alt instead.")
    end
    return LIST_TOP - 24 - shown * LIST_ROW
end

--- Show the widgets of the current view, place the footer under the last row, size the window.
function UI.Refresh()
    if not frame then return end
    local list, guild, add = view == "list", view == "guild", view == "add"
    marked = false
    win.title:SetText((guild or (add and target == "guild")) and UI.TITLE.guild or UI.TITLE.friends)
    views.Show(view)
    local y
    if list then
        local top = BIND_TOP
        at(bindHead, 20, top + 22)
        y = fillRows(ns.Routes.Personal(), top, function() return "route" end,
            "None yet: press Add a binding to pick a player, then the profession whose materials they get.")
        addButton:SetText("Add a binding...")
        addButton:Show()
        guildButton:SetText(ns.SettingsUI.GuildButtonText(ns.Guild.On() and ns.Guild.Mine() ~= nil,
            ns.Guild.On() and ns.Guild.Template()))
        y = hintLine(y)
        at(addButton, 24, y)
        at(guildButton, 172, y)
        at(ledgerButton, -134, y, "TOPRIGHT")
        at(doneButton, -24, y, "TOPRIGHT")
    elseif guild then
        local canPublish = ns.Guild.On() and ns.Guild.CanPublish()
        fillGuildHead(canPublish)
        local template = ns.Guild.On() and ns.Guild.Template() or nil
        if canPublish then
            y = fillRows(ns.Guild.Draft() or {}, GUILD_TOP, function() return "draft" end,
                "No rules yet: press Add a rule to pick yourself or a guild member, then the profession whose "
                .. "materials they get.")
        else
            y = fillRows(template and template.rules or {}, GUILD_TOP, function() return "guild" end,
                template and "This template has no rules." or "")
        end
        y = hintLine(y)
        if canPublish then
            addButton:SetText("Add a rule...")
            W.SetConfirmText(publishButton, ns.Guild.DraftChanged() and "Publish to guild" or "Send again")
            at(addButton, 24, y)
            at(publishButton, 174, y)
            show({ addButton, publishButton }, true)
        end
        if guildFromList then
            at(backButton, -134, y, "TOPRIGHT")
            backButton:Show()
        end
        at(doneButton, -24, y, "TOPRIGHT")
    else
        at(chosenLabel, 28, LIST_TOP - 2) -- the guild view moves it under its template line
        if picked then
            y = fillProfessions()
        else
            chosenLabel:Hide()
            y = fillCandidates()
        end
        y = hintLine(y)
        -- Step 1's pager on the bottom row, left of Back (UX review U5: never on the heading line).
        if not picked and candPager.Update() then at(candPager.next, -134 - 100 - 8, y, "TOPRIGHT") end
        at(backButton, -134, y, "TOPRIGHT")
        backButton:Show()
        at(doneButton, -24, y, "TOPRIGHT")
    end
    win.Finish(y, marked)
end

--- Step 1: a player.
function UI.Pick(i)
    local c = candidates[(candPager.page - 1) * UI.CANDIDATE_ROWS + i]
    if not c then return end
    picked = c
    setHint("")
    UI.Refresh()
end


--- Step 2: the profession; a binding is saved for all the account's characters here, a
--- guild rule goes to the draft (published with Publish to guild).
function UI.Bind(i)
    local p = picked and UI.Options(picked, target == "guild")[i]
    if not p or not picked then return end
    if target == "guild" and not p.class then
        local rule, err = ns.Guild.DraftAdd(picked.name, p.id)
        if not rule then
            setHint("|cffff8040Not added: " .. tostring(err) .. ".|r")
            return
        end
        setHint(string.format("%s to %s%s. Publish to guild to send it.", ns.Routes.What(rule), rule.to,
            err and (" (was " .. tostring(err) .. ")") or ""))
        picked, view = nil, "guild"
        UI.Refresh()
        return
    end
    local route, err = ns.Routes.Add(picked.name, p.class or p.id)
    if not route then
        setHint("|cffff8040Not bound: " .. tostring(err) .. ".|r")
        return
    end
    local text = ns.Routes.IsMe(route.to)
        and string.format("%s now stay with you%s. Remove it any time.", ns.Routes.What(route),
            route.scope == "character" and "" or ": your other characters mail them here")
        or string.format("%s now go to %s. Remove it any time; at the mailbox, Skip once drops it for one visit.",
            ns.Routes.What(route), route.to)
    setHint(text)
    ns.Print(text)
    picked, view = nil, "list"
    UI.Refresh()
    ns.MailWindow.RefreshIfShown()
end

--- `opener`: the Mailworthy window whose button opened it (placed beside that), or nil (centred).
--- `startView`: "list" opens on the bindings even with none (Settings' "Friends and guild...": the
--- list has Guild... and Mail ledger...); otherwise no bindings opens on step 1.
function UI.Show(opener, startView)
    if not frame then UI.Create() end
    win.Show(opener, function()
        picked, target, guildFromList = nil, "me", false
        view = (startView == "list" or #ns.Routes.Personal() > 0) and "list" or "add"
        bindPager.page, candPager.page = 1, 1
        setHint("")
        UI.Reload("shown")
    end)
end

--- The guild view: the template, on / off, and for the guild master and officers its editor.
--- `fromList`: opened from this window's list (its Back returns there).
function UI.OpenGuild(fromList)
    picked, target, view, guildFromList = nil, "guild", "guild", fromList == true
    bindPager.page, candPager.page = 1, 1
    setHint("")
    ns.Routes.RequestRoster()
    if ns.Guild.On() and not ns.Guild.Template() then ns.Guild.Ask("guild window") end
    UI.Refresh()
    ns.Log.Add("ui", "guild window shown")
end

--- The guild view (/mw guild, the settings' Guild button). `opener` as for UI.Show.
function UI.ShowGuild(opener)
    if not frame then UI.Create() end
    W.PlaceBeside(frame, opener)
    UI.OpenGuild(false)
    frame:Show()
    frame:Raise()
end

function UI.Toggle()
    if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

function UI.RefreshIfShown()
    if frame and frame:IsShown() then UI.Refresh() end
end

local function reloadIfShown(reason)
    if frame and frame:IsShown() and view == "add" and not picked then
        gather(reason)
        UI.Refresh()
    end
end

ns.On("PLAYER_LOGIN", function() UI.Create() end)
ns.On("GUILD_ROSTER_UPDATE", function() reloadIfShown("roster") end)
ns.On("GROUP_ROSTER_UPDATE", function() reloadIfShown("group") end)
ns.On("CHAT_MSG_ADDON", function(prefix)
    if ns.Comms and prefix == ns.Comms.PREFIX then reloadIfShown("hello") end
end)
-- Any other view: a new Mailworthy user can be a name on screen (Comms.Mark).
ns.Comms.OnMarksChanged(function()
    if frame and frame:IsShown() and not (view == "add" and not picked) then UI.Refresh() end
end)
