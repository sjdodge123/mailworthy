-- Who the mail window's list goes to (MailWindow.lua): "To:" with the bank alt (Skip once beside it,
-- or Choose bank alt... without one, or Bank alt summary... on the bank alt), a line for each other
-- recipient (folded into "+N more" past UI.TO_LINES), and Return to sender, which adds the players
-- who mailed this character an item as recipients for the visit (Returns.lua). AGENTS Safety: every
-- recipient is named here before Send.
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared
local W = ns.Widgets

--- Pure: the last "To:" line when more recipients mail than lines show: every one of them still
--- named (operator, 2026-11-08: "any new recipient should be shown even if its a return to sender").
--- `recipients` from UI.Recipients; lines from `from` on are folded into this one, UI.FOLD_NAMES
--- names a row, so a long list wraps instead of running off the window (Codex review). Returns the
--- text and how many rows it takes.
UI.FOLD_NAMES = 4
--- `decorate(name, firstName)` (optional) dresses each name (the Mailworthy mark).
function UI.MoreRecipientsText(recipients, from, decorate)
    local names = {}
    for i = from, #recipients do
        local name = recipients[i].name
        names[#names + 1] = decorate and decorate(name, S.firstName(name)) or S.firstName(name)
    end
    local rows = {}
    for i = 1, #names, UI.FOLD_NAMES do
        rows[#rows + 1] = table.concat(names, ", ", i, math.min(i + UI.FOLD_NAMES - 1, #names))
    end
    local text = string.format("+ %d more: %s (see Mailing)", #names, table.concat(rows, ",\n"))
    return "|cffaaaaaa" .. text:gsub("\n", "|r\n|cffaaaaaa") .. "|r", math.max(1, #rows)
end

local function mailsText(n) return string.format("%d mail%s", n, n == 1 and "" or "s") end

--- Pure: who this scan mails to, one line each, the bank alt first: { { name, note, bank }, ... }.
--- `totals` from Bags.Evaluate (recipients, byRecipient). With nothing to mail: the bank alt
--- alone, as before. With more than one recipient each note says what they get and how many
--- mails (operator, 2026-11-06: "when sending to multiple people ... the receiver is made clear").
--- `skipped`: the bank alt is skipped this visit; its line stays first, so Undo skip sits beside it.
function UI.Recipients(totals, bankAlt, isBankAlt, skipped)
    local recipients = totals and totals.recipients or {}
    local several = #recipients > 1
    local lines = {}
    local function bankLine(each)
        local note = isBankAlt and "sell it here" or (bankAlt and "your bank alt" or "optional")
        if skipped and bankAlt and not isBankAlt then note = "your bank alt · skipped this time" end
        if several and each and bankAlt and not isBankAlt then note = note .. " · " .. mailsText(each.mails) end
        local name = isBankAlt and "|cffaaaaaaThis is your bank alt: what's worth selling stays|r"
            or bankAlt or "|cffaaaaaaNo bank alt: what's worth selling stays|r"
        lines[#lines + 1] = { name = name, note = note, bank = true }
    end
    if #recipients == 0 or (skipped and bankAlt) then bankLine() end
    for _, to in ipairs(recipients) do
        local each = totals.byRecipient and totals.byRecipient[to] or { mails = 0, what = {} }
        if to == "" then
            bankLine(each)
        else
            local what = #each.what > 0 and table.concat(each.what, ", ") or "a binding"
            lines[#lines + 1] = { name = to, note = what .. (each.crafter and " (their crafter)" or "")
                .. (several and (" · " .. mailsText(each.mails)) or "") }
        end
    end
    return lines
end

--- At login: "To:", its note and the recipient lines under it.
function S.CreateTo()
    local frame = S.frame
    S.toName = W.Label(frame, "GameFontHighlightLarge")
    S.toName:SetPoint("TOPLEFT", 24, -48)
    S.toNote = W.Label(frame, "GameFontDisableSmall")
    S.toNote:SetPoint("TOPRIGHT", -26, -52)
    for i = 1, UI.TO_LINES do
        local name = W.Label(frame, "GameFontHighlight")
        local note = W.Label(frame, "GameFontDisableSmall")
        name:SetWidth(S.WIDTH - 76) -- never past the window's edge
        name:SetJustifyH("LEFT")
        name:Hide()
        note:Hide()
        S.toLines[i] = { name = name, note = note }
    end
end

--- At login: the buttons on the "To:" line, one at a time in the same spot.
function S.CreateToButtons()
    local frame = S.frame
    -- On the bank alt, where Skip once doesn't apply: the summary of what to sell (BankAlt.lua).
    S.summaryButton = W.Button(frame, "Bank alt summary...", 150, function() ns.BankAlt.ShowWindow(frame) end,
        "MailworthyMailSummary")
    S.summaryButton:Hide()
    -- Skip once for the bank alt too (operator, 2026-11-08): its share stays this visit, bindings go.
    S.skipAltButton = W.Button(frame, "Skip once", 84, function()
        if ns.Mailer.Busy() then return end
        ns.Mailer.Dismiss()
        ns.Bags.SkipBankAlt(not ns.Bags.BankAltSkipped())
        UI.Refresh()
    end, "MailworthyMailSkipBankAlt")
    S.skipAltButton:Hide()
    -- No bank alt yet: the way to pick one, where Skip once would sit (QoL pass, 2026-11-09).
    S.chooseAltButton = W.Button(frame, "Choose bank alt...", 150, function()
        ns.SettingsUI.Show(frame, "pick")
    end, "MailworthyMailChooseAlt")
    S.chooseAltButton:Hide()
end

--- "To:" and the recipient lines for a scan. Returns { to = lines shown, toRows = extra rows the
--- folded last line wraps onto }.
function S.FillTo(result, ctx)
    local at, bankAlt, isBankAlt = S.at, ctx.bankAlt, ctx.isBankAlt
    local recipients = UI.Recipients(result.totals, bankAlt, isBankAlt, ctx.skipped)
    -- The bank alt's line names it only when there is one ("No bank alt" otherwise).
    local function lineName(r)
        local who = r.bank and not isBankAlt and bankAlt or (not r.bank and r.name) or nil
        return who and S.withMark(who, r.name) or r.name
    end
    S.toName:SetText("|cffffd100To:|r " .. lineName(recipients[1]))
    S.toNote:SetText(recipients[1].note)
    local canSkip = recipients[1].bank and bankAlt ~= nil and not isBankAlt and not ctx.busy
    S.skipAltButton:SetText(ctx.skipped and "Undo skip" or "Skip once")
    W.SetToggled(S.skipAltButton, ctx.skipped)
    if canSkip then S.skipAltButton:Show() else S.skipAltButton:Hide() end
    at(S.skipAltButton, -20, -44, "TOPRIGHT")
    if isBankAlt then S.summaryButton:Show() else S.summaryButton:Hide() end
    at(S.summaryButton, -20, -44, "TOPRIGHT")
    local canChoose = recipients[1].bank and bankAlt == nil and not isBankAlt and not ctx.busy
    if canChoose then S.chooseAltButton:Show() else S.chooseAltButton:Hide() end
    at(S.chooseAltButton, -20, -44, "TOPRIGHT")
    at(S.toNote, (canChoose or isBankAlt) and -178 or canSkip and -112 or -26, -52, "TOPRIGHT")
    local more, foldRows = 0, 1
    for i, line in ipairs(S.toLines) do
        local r = recipients[i + 1]
        if r and i == UI.TO_LINES and #recipients > UI.TO_LINES + 1 then
            local text
            text, foldRows = UI.MoreRecipientsText(recipients, UI.TO_LINES + 1, S.withMark)
            line.name:SetText(text)
            line.note:SetText("")
        elseif r then
            line.name:SetText(lineName(r))
            line.note:SetText(r.note)
        end
        if r then
            line.name:Show()
            line.note:Show()
            more = more + 1
        else
            line.name:Hide()
            line.note:Hide()
        end
    end
    return { to = more, toRows = foldRows - 1 }
end

--- Pure: the chat line after Return to sender is pressed: `on`, and the scan's recipients of
--- returned items (Bags totals) as { name = stacks }.
function UI.ReturnsText(on, back)
    if not on then return "Return to sender off: the list is back to normal." end
    local names, stacks = {}, 0
    for name, n in pairs(back or {}) do
        names[#names + 1] = S.firstName(name)
        stacks = stacks + n
    end
    table.sort(names)
    if #names == 0 then
        return "Return to sender on: nothing in your bags was mailed to you by another character "
            .. "(Mailworthy counts what you took from the mailbox since its mail ledger came in)."
    end
    return string.format("Return to sender on: %d stack%s back to %s. Check the list, then press Send.", stacks,
        stacks == 1 and " goes" or "s go", table.concat(names, ", "))
end

--- The Return to sender button (mouse, or Cross on it): on for this visit, or back to normal.
function UI.ToggleReturns()
    if ns.Mailer.Busy() or not ns.Returns.Available() then return end
    ns.lastCommand = "Mailworthy Return to sender"
    ns.Mailer.Dismiss()
    local on = ns.Returns.Toggle()
    S.pages.mail, S.pages.stay = 1, 1
    UI.Refresh()
    local back = {}
    for _, item in ipairs(S.result and S.result.mail or {}) do
        if item.result.route == "return" then back[item.result.to] = (back[item.result.to] or 0) + item.stacks end
    end
    ns.Print(UI.ReturnsText(on, back))
end

--- The Return to sender button (MailSend's button row): lit while on; shown only when something in
--- the bags was mailed here by another player (or it is on): solo players who only mail a bank alt
--- never see it.
function S.FillReturn(result, ctx)
    local button = S.returnButton
    button:SetText(ns.Returns.On() and "Return to sender: on" or "Return to sender")
    W.SetToggled(button, ns.Returns.On())
    local returnable = ns.Returns.Available()
        and (ns.Returns.On() or ns.Returns.Due(ns.Util.Call(ns.Returns.Current), result))
    if returnable then button:Show() else button:Hide() end
    if ctx.busy then button:Disable() else button:Enable() end
end
