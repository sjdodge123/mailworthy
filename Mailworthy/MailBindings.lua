-- The mail window's bindings block (Routes; MailWindow.lua): shown only while there are bindings.
-- One row each with Skip once (this mailbox visit) and Remove, under a "Bindings" heading with the way into the friends
-- window. The mail list below shows where each item goes. A guild template's rules (Guild.lua) are
-- rows too, with Skip once but no Remove; while any shows, "Guild rules: on" on the heading turns
-- them all off in one press (operator, 2026-11-07).
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared
local W = ns.Widgets

--- A binding row's text while it shows, for specs.
function UI.RouteLine(i) return S.routeRows[i] and S.routeRows[i].text:IsShown() and S.routeRows[i].text:GetText() or nil end

--- At login: the heading and its Friends... and Guild rules buttons.
function S.CreateBindingsHead()
    local frame = S.frame
    S.routesHead = W.Label(frame, "GameFontNormal")
    S.routesHead:SetText("Bindings")
    S.friendsButton = W.Button(frame, "Friends...", 90, function() ns.RoutesUI.Show(frame) end, "MailworthyMailFriends")
    S.guildButton = W.Button(frame, "Guild rules: on", 130, function()
        if ns.Guild.SetUse(false) then
            ns.Print("Guild rules off: your materials no longer follow the guild template. "
                .. "Turn them back on with /mw guild.")
        end
        UI.Refresh()
    end, "MailworthyMailGuildRules")
    S.guildButton:Hide()
end

--- At login: the binding rows.
function S.CreateBindingRows()
    local frame = S.frame
    for i = 1, UI.ROUTE_ROWS do
        local row = {}
        row.text = W.Label(frame, "GameFontHighlightSmall")
        row.text:SetWidth(300)
        row.text:SetJustifyH("LEFT")
        row.skip = W.Button(frame, "Skip once", 84, function()
            if not row.key or ns.Mailer.Busy() then return end
            ns.Mailer.Dismiss()
            if ns.Routes.Skipped(row.key) then ns.Routes.Unskip(row.key) else ns.Routes.SkipOnce(row.key) end
            UI.Refresh()
        end, "MailworthyMailSkip" .. i)
        row.remove = W.Button(frame, "Remove", 74, function()
            if row.key and ns.Routes.Remove(row.key) then
                ns.Print("Binding removed.")
                UI.Refresh()
            end
        end, "MailworthyMailUnbind" .. i)
        row.text:Hide()
        row.skip:Hide()
        row.remove:Hide()
        S.routeRows[i] = row
    end
end

--- Pure: the last row when more bindings apply than show. Own bindings come first in the list,
--- so when the first hidden one is a guild rule, all the hidden ones are: those are in the Guild
--- window, not Friends (2026-11-07, Codex review).
function UI.MoreText(n, guildOnly)
    return string.format("|cffaaaaaa+ %d more: %s|r", n, guildOnly and "guild rules, /mw guild" or "press Friends...")
end

--- Pure: a binding row's grey tags: "(guild, skill 120)", "(skill 120)", "(guild)" or "". The skill
--- shows why a material past it stays (2026-11-07: "i'm not sure hiphop is on linen anymore").
function UI.RouteTags(guild, skill)
    local tags = {}
    if guild then tags[#tags + 1] = "guild" end
    if skill then tags[#tags + 1] = "skill " .. tostring(skill) end
    return #tags > 0 and (" |cff888888(" .. table.concat(tags, ", ") .. ")|r") or ""
end

--- Fill the binding rows; returns how many rows show (0: the block is hidden).
function S.FillBindings()
    local list = ns.Routes.List()
    local shown = 0
    for i, row in ipairs(S.routeRows) do
        local r = list[i]
        row.key = r and r.key or nil
        if r and i == UI.ROUTE_ROWS and #list > UI.ROUTE_ROWS then
            row.text:SetText(UI.MoreText(#list - UI.ROUTE_ROWS + 1, r.scope == "guild"))
            row.key = nil
            row.skip:Hide()
            row.remove:Hide()
        elseif r then
            local to, crafter = ns.Routes.Recipient(r)
            local skipped = ns.Routes.Skipped(r.key)
            row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. S.withMark(to, S.firstName(to)) .. "|r"
                .. (crafter and (" |cff888888(" .. S.withMark(r.to, S.firstName(r.to) .. "'s crafter") .. ")|r") or "")
                .. UI.RouteTags(r.scope == "guild", ns.Routes.Skill(r))
                .. (skipped and " |cff888888skipped this time|r" or ""))
            row.skip:SetText(skipped and "Undo skip" or "Skip once")
            W.SetToggled(row.skip, skipped)
            row.skip:Show()
            if r.scope == "guild" then row.remove:Hide() else row.remove:Show() end
        end
        if r then
            row.text:Show()
            shown = shown + 1
        else
            row.text:Hide()
            row.skip:Hide()
            row.remove:Hide()
        end
    end
    local guild = false
    for _, r in ipairs(list) do guild = guild or r.scope == "guild" end
    if shown > 0 then
        S.routesHead:Show()
        S.friendsButton:Show()
    else
        S.routesHead:Hide()
        S.friendsButton:Hide()
    end
    if guild then S.guildButton:Show() else S.guildButton:Hide() end
    W.SetToggled(S.guildButton, guild) -- "Guild rules: on" shows only while they are
    return shown
end
