-- Send, and only what was previewed (MailWindow.lua; AGENTS Safety: "what was previewed must be
-- exactly what was sent"). The button row: Send (Stop while a run is on), Settings, Return to
-- sender. Send re-reads the bags first; if the fresh list sends anything somewhere the list on
-- screen didn't say (UI.Changed), nothing goes: the list now shows where, and a second press sends
-- it. Mailer.Start then re-checks each slot before attaching it and keeps Mailer.RESERVE.
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared
local W = ns.Widgets

--- Pure: the Send button's text: "Send to Roknua", "Send to Roknua, Bob", "Send to Roknua +2".
--- `recipients` lists the scan's recipients ("" = the bank alt); `skipped`: the bank alt is skipped.
function UI.SendText(recipients, bankAlt, isBankAlt, skipped)
    if skipped then bankAlt = nil end
    local firstName = S.firstName
    local names = {}
    for _, to in ipairs(recipients or {}) do
        if to == "" then
            if bankAlt and not isBankAlt then names[#names + 1] = firstName(bankAlt) end
        else
            names[#names + 1] = firstName(to)
        end
    end
    if #names == 0 then return (bankAlt and not isBankAlt) and ("Send to " .. firstName(bankAlt)) or "Send" end
    if #names > 2 then return string.format("Send to %s +%d", names[1], #names - 1) end
    return "Send to " .. table.concat(names, ", ")
end

--- The greyed-out Send button's text on the Inbox (the controller reaches Send Mail with its
--- right shoulder button: R1 / RB, by the player's controller).
function UI.InboxSendText(pad)
    return pad and ("Send Mail tab: " .. ns.Gamepad.Name(ns.Gamepad.SHOULDER_RIGHT)) or "Click Send Mail"
end

--- Pure: the Send button's text and whether it can be pressed (media/qol-prototype.png). `s`:
--- busy (a run is on), stopping (Stop was pressed, a mail is still waiting for its answer),
--- inbox (the Inbox tab shows), pad, mails (items on the mail list), need (the postage, when the
--- player can't pay it and keep Mailer.RESERVE), send (UI.SendText's "Send to ..."). On the Inbox nothing is ever sent
--- or stopped from here (Codex review); a run on shows as "Sending...".
function UI.SendState(s)
    if s.inbox then return s.busy and "Sending..." or UI.InboxSendText(s.pad), false end
    if s.stopping then return "Stopping...", false end
    if s.busy then return "Stop", true end
    if (s.mails or 0) == 0 then return "Nothing to send", false end
    if s.need then return "Postage: " .. S.money(s.need) .. ", keeps " .. S.money(ns.Mailer.RESERVE), false end
    return s.send, true
end

--- Pure: the items of a fresh scan (`fresh`, its mail list, for bank alt `freshAlt`) going
--- somewhere the list on screen (`shown`, drawn for `previewAlt`) didn't say: an item the preview
--- sent elsewhere, or a new one (bags changed) to a player the preview didn't name; the bank alt
--- the list named is always shown ("To: ..."). Items are told apart by link (one item ID can be
--- several items: a green's random suffix), and one item may go to several shown recipients.
--- A binding's recipient can move between the preview and Send without the bags changing (a
--- crafter's skill passes a material, two bindings swap on "lowest skill first"), and so can the
--- bank alt (picked in Settings beside the list) (Codex review, 2026-11-07).
--- `stayed` (the list's Staying items): one of those now in the mail is a change too (a quest
--- abandoned after the preview; Codex review, 2026-11-08), whoever it goes to.
--- How many of an item each recipient gets counts too (Codex review, 2026-11-08): Return to sender
--- splits one item between its sender and the usual recipient by stacks, so stacks moved between
--- the preview and Send would change who gets how many; such an entry has `count` / `wasCount`.
function UI.Changed(shown, fresh, previewAlt, freshAlt, stayed)
    if freshAlt == nil then freshAlt = previewAlt end
    local function key(it) return it.link or it.itemID end
    local function count(it) return tonumber(it.count) or 0 end
    local kept = {}
    for _, it in ipairs(stayed or {}) do kept[key(it)] = true end
    local was, named = {}, { [tostring(previewAlt)] = true }
    for _, it in ipairs(shown or {}) do
        local to = tostring(it.result and it.result.to or previewAlt)
        local k = key(it)
        was[k] = was[k] or {}
        was[k][to] = (was[k][to] or 0) + count(it)
        named[to] = true
    end
    local changed, now, order = {}, {}, {}
    for _, it in ipairs(fresh or {}) do
        local to = tostring(it.result and it.result.to or freshAlt)
        local k = key(it)
        local before = was[k]
        if kept[k] and not before then
            changed[#changed + 1] = { item = it, was = "Staying", to = to }
        elseif (before and not before[to]) or (not before and not named[to]) then
            changed[#changed + 1] = { item = it, was = before and next(before) or nil, to = to }
        elseif before then
            now[k] = now[k] or {}
            if not now[k][to] then
                now[k][to] = { item = it, count = 0 }
                order[#order + 1] = { k, to }
            end
            now[k][to].count = now[k][to].count + count(it)
        end
    end
    for _, o in ipairs(order) do
        local k, to = o[1], o[2]
        local n = now[k][to]
        if n.count ~= was[k][to] then
            changed[#changed + 1] = { item = n.item, was = to, to = to, count = n.count, wasCount = was[k][to] }
        end
    end
    return changed
end

--- Stop (the Send button while a run is on; mouse, or Cross on it).
function UI.Stop()
    if not ns.Mailer.Busy() or UI.OnInbox() then return end
    ns.lastCommand = "Mailworthy Stop"
    ns.Mailer.RequestStop("stopped by you")
end

function UI.Send()
    if not S.result or UI.OnInbox() or ns.Mailer.Busy() then return end
    ns.lastCommand = "Mailworthy Send"
    local shown, alt, stayed = S.result.mail, S.shownAlt, S.result.keep
    UI.Refresh() -- the freshest scan, so the mail list is what's in the bags now
    -- AGENTS Safety: mail goes only to the recipients the player saw. If the fresh scan sends
    -- anything elsewhere, nothing goes: the list now shows where, and a second press sends it.
    local result = S.result
    local changed = UI.Changed(shown, result.mail, alt, ns.Config.BankAlt(), stayed)
    if #changed > 0 then
        local c = changed[1]
        local firstName = S.firstName
        local name = ns.Util.LinkName(c.item.link) or ("item " .. tostring(c.item.itemID))
        local text = c.wasCount and string.format("Not sent: %s to %s is now x%d (the list said x%d). "
                .. "Check the list, then press Send again.", name, firstName(c.to), c.count, c.wasCount)
            or string.format("Not sent: %s now goes to %s%s. Check the list, then press Send again.", name,
                firstName(c.to), c.was == "Staying" and " instead of staying in your bags"
                    or c.was and (" instead of " .. firstName(c.was)) or "")
        ns.Log.Add("mailer", "send held: %d item(s) changed recipient since the preview (%s to %s, was %s)", #changed,
            name, c.to, tostring(c.was))
        ns.Print(text)
        S.totalNote:SetText("|cffff8040" .. text .. "|r")
        return
    end
    ns.Mailer.Start(result.mail, ns.Config.BankAlt(), result.settings)
    UI.Refresh(true)
end

--- At login: the button row under the total box.
function S.CreateButtons()
    local frame = S.frame
    -- Send; while a run is on, the same button is Stop (QoL pass, 2026-11-09).
    S.sendButton = W.Button(frame, "Send", 190, function()
        if ns.Mailer.Busy() then UI.Stop() else UI.Send() end
    end, "MailworthyMailSend")
    S.settingsButton = W.Button(frame, "Settings", 110, function() ns.SettingsUI.Show(frame) end, "MailworthyMailSettings")
    S.returnButton = W.Button(frame, "Return to sender", 150, function() UI.ToggleReturns() end, "MailworthyMailReturn")
end

--- The Send button for a scan: its text and whether it can be pressed (UI.SendState). On the Inbox:
--- mail goes out from the Send Mail tab only, and we never switch tabs ourselves
--- (MailFrameTab_OnClick taints the controller UI). Send is greyed out there and names the
--- tab (operator, 2026-11-08: "the button should be greyed out with a 'click send mail'
--- text"); on Send Mail the watcher redraws it as "Send to ..." and the list follows.
function S.FillSend(result, ctx, need)
    S.renderedInbox = UI.OnInbox()
    local label, enabled = UI.SendState({ busy = ctx.busy, stopping = ns.Mailer.Stopping(), inbox = S.renderedInbox,
        pad = ctx.pad, mails = #result.mail, need = need,
        send = UI.SendText(result.totals.recipients, ctx.bankAlt, ctx.isBankAlt, ctx.skipped) })
    S.sendButton:SetText(label)
    S.sendButton:Show()
    if enabled then S.sendButton:Enable() else S.sendButton:Disable() end
end
