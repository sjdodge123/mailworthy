-- The friends window (/mw friends, the settings' "Send materials to friends"
-- button, the Mailworthy window's button): the bindings in force, each with its
-- price cap stepper, scope (all my characters / this character), delivery (to
-- them / to their bank alt, when their Mailworthy has said which) and Remove;
-- then "Add a binding" in two presses: pick a player (party, guild, own
-- characters, Mailworthy users; online first; their professions shown), then
-- pick the profession (theirs suggested). Every control is a button, so the
-- controller drives it (PadKey "settings" set, Nav); nothing needs typing.
local _, ns = ...

local UI = {}
ns.RoutesUI = UI

UI.BINDING_ROWS, UI.CANDIDATE_ROWS, UI.PROFESSION_ROWS = 4, 6, 8
local WIDTH = 560
local BIND_ROW, LIST_ROW = 50, 26
local BIND_TOP = -98
local ADD_TOP = BIND_TOP - UI.BINDING_ROWS * BIND_ROW - 8
local LIST_TOP = ADD_TOP - 46
local HEIGHT = -LIST_TOP + UI.CANDIDATE_ROWS * LIST_ROW + 96

local W = ns.Widgets

local frame, stepLabel, emptyBindings, bindPage, candPage, refreshButton, backButton, hint, legend
local bindingRows, candidateRows, professionRows = {}, {}, {}
local pages = { bind = 1, cand = 1 }
local candidates, picked = {}, nil

function UI.Frame() return frame end
function UI.Picked() return picked end

local function selected(text, on)
    return on and ("|cff33ff99> " .. text .. " <|r") or text
end

local function setHint(text) if hint then hint:SetText(text or "") end end

local function pageOf(list, rows, key)
    local count = math.max(1, math.ceil(#list / rows))
    if pages[key] > count then pages[key] = 1 end
    return pages[key], count
end

local function createBindingRows()
    for i = 1, UI.BINDING_ROWS do
        local row = {}
        local y = BIND_TOP - (i - 1) * BIND_ROW
        row.text = W.Label(frame, "GameFontHighlight")
        row.text:SetPoint("TOPLEFT", 28, y - 4)
        row.text:SetWidth(420)
        row.text:SetJustifyH("LEFT")
        row.remove = W.Button(frame, "Remove", 80, function()
            if row.key and ns.Routes.Remove(row.key) then
                setHint("Binding removed.")
                UI.Refresh()
                ns.MailWindow.RefreshIfShown()
            end
        end, "MailworthyFriendsRemove" .. i)
        row.remove:SetPoint("TOPRIGHT", -24, y)
        row.cap = W.Label(frame, "GameFontHighlightSmall")
        row.cap:SetPoint("TOPLEFT", 28, y - 28)
        row.cap:SetWidth(196)
        row.cap:SetJustifyH("LEFT")
        row.capDown = W.Button(frame, "-", 26, function()
            if row.key then ns.Routes.StepCap(row.key, -1) end
            UI.Refresh()
        end, "MailworthyFriendsCapDown" .. i)
        row.capDown:SetPoint("TOPLEFT", 228, y - 24)
        row.capUp = W.Button(frame, "+", 26, function()
            if row.key then ns.Routes.StepCap(row.key, 1) end
            UI.Refresh()
        end, "MailworthyFriendsCapUp" .. i)
        row.capUp:SetPoint("TOPLEFT", 258, y - 24)
        row.scope = W.Button(frame, "", 136, function()
            if row.key then ns.Routes.ToggleScope(row.key) end
            UI.Refresh()
        end, "MailworthyFriendsScope" .. i)
        row.scope:SetPoint("TOPLEFT", 294, y - 24)
        row.via = W.Button(frame, "", 100, function()
            local r = row.key and ns.Routes.Get(row.key)
            if r then ns.Routes.SetViaAlt(row.key, not r.viaAlt) end
            UI.Refresh()
            ns.MailWindow.RefreshIfShown()
        end, "MailworthyFriendsVia" .. i)
        row.via:SetPoint("TOPLEFT", 436, y - 24)
        bindingRows[i] = row
    end
    emptyBindings = W.Label(frame, "GameFontHighlightSmall")
    emptyBindings:SetPoint("TOPLEFT", 28, BIND_TOP - 4)
    emptyBindings:SetWidth(WIDTH - 56)
    emptyBindings:SetJustifyH("LEFT")
    emptyBindings:SetText("None yet. Pick a player below, then the profession whose materials they should get.")
    bindPage = W.Button(frame, "", 70, function()
        pages.bind = pages.bind + 1
        UI.Refresh()
    end, "MailworthyFriendsBindPage")
    bindPage:SetPoint("TOPRIGHT", -24, BIND_TOP + 26)
end

local function createAdd()
    local h = W.Label(frame, "GameFontNormal")
    h:SetPoint("TOPLEFT", 20, ADD_TOP)
    h:SetText("Add a binding")
    stepLabel = W.Label(frame, "GameFontHighlight")
    stepLabel:SetPoint("TOPLEFT", 28, ADD_TOP - 22)
    stepLabel:SetWidth(WIDTH - 56)
    stepLabel:SetJustifyH("LEFT")
    refreshButton = W.Button(frame, "Refresh list", 100, function()
        UI.Reload("refresh")
        UI.Refresh()
    end, "MailworthyFriendsRefresh")
    refreshButton:SetPoint("TOPRIGHT", -24, ADD_TOP + 4)
    candPage = W.Button(frame, "", 70, function()
        pages.cand = pages.cand + 1
        UI.Refresh()
    end, "MailworthyFriendsPage")
    candPage:SetPoint("TOPRIGHT", -130, ADD_TOP + 4)
    for i = 1, UI.CANDIDATE_ROWS do
        local b = W.Button(frame, "", WIDTH - 48, function() UI.Pick(i) end, "MailworthyFriendsPick" .. i)
        b:SetPoint("TOPLEFT", 24, LIST_TOP - (i - 1) * LIST_ROW)
        b:Hide()
        candidateRows[i] = b
    end
    for i = 1, UI.PROFESSION_ROWS do
        local b = W.Button(frame, "", 250, function() UI.Bind(i) end, "MailworthyFriendsProfession" .. i)
        b:SetPoint("TOPLEFT", 24 + ((i - 1) % 2) * 262, LIST_TOP - math.floor((i - 1) / 2) * LIST_ROW)
        b:Hide()
        professionRows[i] = b
    end
    backButton = W.Button(frame, "Back", 80, function()
        picked = nil
        setHint("")
        UI.Refresh()
    end, "MailworthyFriendsBack")
    backButton:SetPoint("TOPLEFT", 24, LIST_TOP - 4 * LIST_ROW - 4)
    backButton:Hide()
end

function UI.Create()
    if frame then return frame end
    frame = W.Window("MailworthyFriendsFrame", WIDTH, HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetPoint("CENTER")
    local title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Send materials to friends")
    local sub = W.Label(frame, "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 28, -44)
    sub:SetWidth(WIDTH - 56)
    sub:SetJustifyH("LEFT")
    sub:SetText("A binding mails everything a profession uses to one player, every time, until you remove it. "
        .. "Locked items still stay. A material the market suddenly wants (the price cap) goes to your bank alt instead.")
    local h = W.Label(frame, "GameFontNormal")
    h:SetPoint("TOPLEFT", 20, BIND_TOP + 22)
    h:SetText("Bindings")
    createBindingRows()
    createAdd()
    hint = W.Label(frame, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 28, 44)
    hint:SetWidth(WIDTH - 180)
    hint:SetJustifyH("LEFT")
    W.Button(frame, "Done", 100, function() frame:Hide() end, "MailworthyFriendsDone")
        :SetPoint("BOTTOMRIGHT", -24, 40)
    legend = W.Label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", 0, 18)
    ns.Nav.Attach(frame)
    ns.Log.Add("ui", "friends window created")
    return frame
end

--- Re-read who can be bound (the roster is asked for and other Mailworthys are asked to say hello).
function UI.Reload(reason)
    ns.Routes.RequestRoster()
    if ns.Comms then ns.Comms.Ask() end
    candidates = ns.Routes.Candidates()
    ns.Log.Add("ui", "friends window: %d candidates (%s)", #candidates, tostring(reason))
end

function UI.Candidates() return candidates end

local function fillBindings()
    local list = ns.Routes.List()
    local page, count = pageOf(list, UI.BINDING_ROWS, "bind")
    local first = (page - 1) * UI.BINDING_ROWS
    for i, row in ipairs(bindingRows) do
        local r = list[first + i]
        row.key = r and r.key or nil
        local widgets = { row.text, row.remove, row.cap, row.capDown, row.capUp, row.scope, row.via }
        if r then
            local to, viaAlt = ns.Routes.Recipient(r)
            local peer = ns.Comms and ns.Comms.Peer(r.to)
            row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. r.to .. "|r"
                .. (viaAlt and (" |cffaaaaaa(their bank alt " .. to .. ")|r") or ""))
            row.cap:SetText(ns.Routes.CapText(r))
            row.scope:SetText(ns.Routes.SCOPES[r.scope] or r.scope)
            local altKnown = peer and peer.bankAlt
            row.via:SetText(r.viaAlt and (altKnown and "To their alt" or "Alt unknown") or "To them")
            for _, w in ipairs(widgets) do w:Show() end
            if not altKnown and not r.viaAlt then row.via:Hide() end
        else
            for _, w in ipairs(widgets) do w:Hide() end
        end
    end
    if #list == 0 then emptyBindings:Show() else emptyBindings:Hide() end
    if count > 1 then
        bindPage:SetText(string.format("%d/%d  >", page, count))
        bindPage:Show()
    else
        bindPage:Hide()
    end
end

local function fillCandidates()
    local page, count = pageOf(candidates, UI.CANDIDATE_ROWS, "cand")
    local first = (page - 1) * UI.CANDIDATE_ROWS
    for i, b in ipairs(candidateRows) do
        local c = candidates[first + i]
        if c then
            b:SetText(ns.Routes.CandidateText(c))
            b:Show()
        else
            b:Hide()
        end
    end
    if count > 1 then
        candPage:SetText(string.format("%d/%d  >", page, count))
        candPage:Show()
    else
        candPage:Hide()
    end
    for _, b in ipairs(professionRows) do b:Hide() end
    backButton:Hide()
    refreshButton:Show()
    if #candidates == 0 then
        stepLabel:SetText("Nobody to bind yet: join a group, be in a guild (the roster may take a moment), "
            .. "or log in on another of your characters once.")
    else
        stepLabel:SetText("Who should get your materials?")
    end
end

local function fillProfessions()
    local suggested = {}
    for _, p in ipairs(ns.Routes.Suggested(picked)) do suggested[p.id] = true end
    local names = {}
    for _, p in ipairs(ns.Routes.Suggested(picked)) do names[#names + 1] = p.name end
    stepLabel:SetText("What should " .. picked.name .. " get?"
        .. (#names > 0 and (" Suggested: " .. table.concat(names, ", ") .. ".") or " (no crafting profession known)"))
    for i, b in ipairs(professionRows) do
        local p = ns.Routes.Professions()[i]
        if p then
            b:SetText(selected(p.name .. " (" .. p.mats .. ")", suggested[p.id] == true))
            b:Show()
        else
            b:Hide()
        end
    end
    for _, b in ipairs(candidateRows) do b:Hide() end
    candPage:Hide()
    refreshButton:Hide()
    backButton:Show()
end

function UI.Refresh()
    if not frame then return end
    fillBindings()
    if picked then fillProfessions() else fillCandidates() end
    legend:SetText(ns.MailButton.GamepadUI() and W.Legend() or "")
end

--- Step 1: a player.
function UI.Pick(i)
    local c = candidates[(pages.cand - 1) * UI.CANDIDATE_ROWS + i]
    if not c then return end
    picked = c
    setHint("")
    UI.Refresh()
end

--- Step 2: the profession; the binding is saved for all the account's characters here.
function UI.Bind(i)
    local p = ns.Routes.Professions()[i]
    if not p or not picked then return end
    local route, err = ns.Routes.Add(picked.name, p.id)
    if not route then
        setHint("|cffff8040Not bound: " .. tostring(err) .. ".|r")
        return
    end
    local text = string.format("%s now go to %s. Remove it any time; at the mailbox, Skip once drops it for one visit.",
        ns.Routes.What(route), route.to)
    setHint(text)
    ns.Print(text)
    picked = nil
    UI.Refresh()
    ns.MailWindow.RefreshIfShown()
end

function UI.Show()
    if not frame then UI.Create() end
    picked = nil
    pages.bind, pages.cand = 1, 1
    setHint("")
    UI.Reload("shown")
    UI.Refresh()
    frame:Show()
    frame:Raise()
    ns.Log.Add("ui", "friends window shown")
end

function UI.Toggle()
    if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

local function reloadIfShown(reason)
    if frame and frame:IsShown() and not picked then
        candidates = ns.Routes.Candidates()
        ns.Log.Add("ui", "friends window: %d candidates (%s)", #candidates, reason)
        UI.Refresh()
    end
end

ns.On("PLAYER_LOGIN", function() UI.Create() end)
ns.On("GUILD_ROSTER_UPDATE", function() reloadIfShown("roster") end)
ns.On("GROUP_ROSTER_UPDATE", function() reloadIfShown("group") end)
ns.On("CHAT_MSG_ADDON", function(prefix)
    if ns.Comms and prefix == ns.Comms.PREFIX then reloadIfShown("hello") end
end)
