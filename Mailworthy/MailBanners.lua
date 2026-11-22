-- The mail window's notices, over the bindings block (MailWindow.lua): each is a label and 0-2
-- buttons on its right, shown only when it has something to say (UX review A5: one helper for all).
--   stale  prices are old: rescan Auctionator (Stale.lua)
--   owed   pay back: what another player mailed this account beyond what it mailed back (Ledger.lua),
--          with Mail ledger...; only this side ever shows. Under it (2026-11-22, phase 2 of
--          docs/RECOMMENDATIONS.md): a meter of what's been paid back so far, a lighter part for what this
--          Send would pay them (the list's mail to that player, at this character's values), and
--          Mark part paid (an amount, - / +, two presses) for paying another way
-- Under them, the payback ideas (MailIdeas.lua) and the suggested bindings (MailSuggestions.lua: crafters in
-- the group and your own characters).
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared
local W = ns.Widgets

local GAP = 4 -- between a notice's buttons

--- A notice: `def` = { height, labelY, buttonY, buttons = { { text, width, onClick, name }, ... } }.
--- Created at login, hidden.
local function banner(def)
    local b = { def = def, buttons = {} }
    local used = 0
    for i, spec in ipairs(def.buttons or {}) do
        b.buttons[i] = W.Button(S.frame, spec[1], spec[2], spec[3], spec[4])
        b.buttons[i]:Hide()
        used = used + spec[2] + (i > 1 and GAP or 0)
    end
    b.label = W.Label(S.frame, "GameFontHighlightSmall")
    b.label:SetWidth(S.WIDTH - 48 - (used > 0 and used + 12 or 0))
    b.label:SetJustifyH("LEFT")
    b.label:Hide()
    return b
end

--- Show `text` (nil: hide the notice); `texts` (optional) renames its buttons. Returns whether it shows.
local function setBanner(b, text, texts)
    b.label:SetText(text or "")
    for i, button in ipairs(b.buttons) do
        if texts and texts[i] then button:SetText(texts[i]) end
    end
    for _, w in ipairs({ b.label, unpack(b.buttons) }) do
        if text then w:Show() else w:Hide() end
    end
    return text ~= nil
end

--- Place a shown notice with its top at `y`; returns the y under it.
local function placeBanner(b, y)
    S.at(b.label, 24, y + b.def.labelY)
    local x = -24
    for i = #b.buttons, 1, -1 do
        S.at(b.buttons[i], x, y + b.def.buttonY, "TOPRIGHT")
        x = x - b.def.buttons[i][2] - GAP
    end
    return y - b.def.height
end

local stale, owed
local meter = {}  -- bg, paid, next (textures), sub (label), less, part, more (buttons)
local METER_HEIGHT = 8
local owedName, partAmount -- the player the notice is about, and the part-paid amount on it

function S.CreateBanners()
    stale = banner({ height = 32, labelY = 0, buttonY = 0 })
    owed = banner({ height = 30, labelY = -2, buttonY = 4, buttons = {
        { "Mail ledger...", 110, function() ns.LedgerUI.Show(S.frame) end, "MailworthyMailLedger" } } })
    local frame = S.frame
    meter.bg = frame:CreateTexture(nil, "ARTWORK")
    meter.bg:SetColorTexture(0.07, 0.05, 0.08, 0.9)
    meter.paid = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    meter.paid:SetColorTexture(0.71, 0.42, 0.82, 0.95)
    meter.next = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    meter.next:SetColorTexture(0.56, 0.9, 0.69, 0.85)
    for _, t in ipairs({ meter.bg, meter.paid, meter.next }) do t:SetHeight(METER_HEIGHT) end
    meter.sub = W.Label(frame, "GameFontHighlightSmall")
    meter.sub:SetJustifyH("LEFT")
    meter.less = W.Button(frame, "-", 24, function() UI.StepPart(-1) end, "MailworthyMailPartLess")
    meter.part = W.ConfirmButton(frame, "Part paid", "Sure?", 120, function() UI.MarkPartPaid() end, "MailworthyMailPartPaid")
    meter.more = W.Button(frame, "+", 24, function() UI.StepPart(1) end, "MailworthyMailPartMore")
    W.Tip(meter.part, "Mark part paid", function()
        return string.format("Paid %s back another way (an enchant in person, a trade, gold)? Press twice: what you owe goes down by %s.",
            tostring(owedName), ns.Valuation.Money(partAmount or 0))
    end)
    W.Tip(meter.less, "Less", "5s less to mark as paid.")
    W.Tip(meter.more, "More", "5s more to mark as paid (never more than you owe).")
    for _, w in pairs(meter) do w:Hide() end
    S.CreateIdeas()
    S.CreateSuggestions()
end

--- Pure: the copper this Send would pay `owner` back: the list's mail to that player (any character
--- of theirs, `ownerOf`) at this character's values (`valueOf(link)`: a unit value or nil, as the
--- ledger records a send). Unpriced items count nothing.
function UI.SendShare(mail, owner, ownerOf, valueOf)
    local total = 0
    if not owner then return 0 end
    for _, item in ipairs(mail or {}) do
        local to = item.result and item.result.to
        if to and tostring(ownerOf(to)):lower() == tostring(owner):lower() then
            local unit = valueOf(item.link)
            if unit then total = total + unit * (tonumber(item.count) or 1) end
        end
    end
    return total
end

--- Pure: the meter's line, "Paid back 25s of 1g 74s · this Send pays 70s more, 1g 4s left".
function UI.MeterText(paid, total, share, net)
    local m = ns.Valuation.Money
    local text = string.format("Paid back %s of %s", m(paid), m(total))
    if share and share > 0 then
        local pays = math.min(share, net)
        text = text .. string.format(" |cff8ee6b0· this Send pays %s more, %s left|r", m(pays), m(net - pays))
    end
    return text
end

--- - / + on the notice: the part-paid amount, 5s a step, never more than what's owed.
function UI.StepPart(dir)
    if not owedName then return end
    local net = ns.Ledger.Net(owedName)
    partAmount = ns.Ledger.StepPart(partAmount, dir, net)
    W.Disarm(meter.part) -- a new amount: the first press again
    UI.Refresh(true)
end

--- The second press on Part paid: what's owed goes down by the amount (Ledger.MarkPaid).
function UI.MarkPartPaid()
    if not owedName or not partAmount then return end
    local name, amount = owedName, partAmount
    if ns.Ledger.MarkPaid(name, amount) then
        ns.Print(string.format("Marked part paid: %s to %s (in the mail ledger's log).", ns.Valuation.Money(amount), name))
    end
    partAmount = nil
    UI.Refresh(true)
end

--- The notice's player and part-paid amount, and the meter's line, for specs.
function UI.OwedState() return owedName, partAmount end
function UI.MeterLine() return meter.sub and meter.sub:GetText() or "" end

--- The pay-back line for the ledger's debts (Ledger.Debts: most first), or nil; the name carries
--- the Mailworthy mark (Comms.Mark).
function UI.OwedText(debts)
    local d = debts and debts[1]
    if not d then return nil end
    local text = ns.Ledger.DebtText(S.withMark(d.name), d.net)
    if #debts > 1 then text = text .. string.format(" |cffaaaaaa(and %d more)|r", #debts - 1) end
    return text
end

--- The notices for a scan; sets `shown.stale`, `shown.owed`, `shown.suggest` (UI.Layout).
function S.FillBanners(result, ctx, shown)
    local okStale, nudge = pcall(ns.Stale.Current)
    shown.stale = setBanner(stale, okStale and ns.Stale.Text(nudge) or nil)
    local debts = ns.Ledger.On() and ns.Ledger.Debts() or {}
    shown.owed = setBanner(owed, UI.OwedText(debts))
    for _, w in pairs(meter) do w:Hide() end
    local d = debts[1]
    if d then
        if not owedName or owedName:lower() ~= d.name:lower() then
            owedName, partAmount = d.name, nil
            W.Disarm(meter.part)
        end
        local before = partAmount
        partAmount = ns.Ledger.StepPart(partAmount, nil, d.net)
        -- A changed amount (what's owed moved) cancels a first press: the second pays only what was shown
        -- (Codex review, 2026-11-22).
        if before and before ~= partAmount then W.Disarm(meter.part) end
        local paid, total = ns.Ledger.PaidBack(d.name)
        -- While a send runs the list on screen stays as it was but the ledger counts each mail as it
        -- goes: no "this Send pays" then, or it would count what was already sent again (Codex review).
        local share = ctx.busy and 0
            or UI.SendShare(result and result.mail, d.name, ns.Ledger.Owner, ns.Ledger.UnitValue)
        S.owedMeter = { paid = paid, total = total, share = math.min(share, d.net), net = d.net }
        meter.sub:SetText(UI.MeterText(paid, total, share, d.net))
        W.SetConfirmText(meter.part, "Part paid: " .. ns.Valuation.Money(partAmount))
        for _, w in pairs(meter) do w:Show() end
    else
        owedName, partAmount, S.owedMeter = nil, nil, nil
    end
    S.FillIdeas(result, ctx, shown) -- payback ideas (MailIdeas.lua), under the owed notice
    -- The suggested bindings: not while a send runs, nor with the switch or the setting off.
    S.FillSuggestions(result, ctx, shown)
end

--- Place the notices that show from `y` down (UI.Layout); returns the y under them.
function S.LayoutBanners(y, n)
    if n.stale then y = placeBanner(stale, y) end
    if n.owed then
        y = placeBanner(owed, y)
        local m = S.owedMeter
        if m then
            local width = S.WIDTH - 48
            S.at(meter.bg, 24, y + 4)
            meter.bg:SetWidth(width)
            local paidW = m.total > 0 and math.floor(width * m.paid / m.total) or 0
            local nextW = m.total > 0 and math.floor(width * m.share / m.total) or 0
            S.at(meter.paid, 24, y + 4)
            meter.paid:SetWidth(math.max(1, paidW))
            if paidW <= 0 then meter.paid:Hide() end
            S.at(meter.next, 24 + paidW, y + 4)
            meter.next:SetWidth(math.max(1, nextW))
            if nextW <= 0 then meter.next:Hide() end
            y = y - METER_HEIGHT - 2
            S.at(meter.more, -24, y, "TOPRIGHT")
            S.at(meter.part, -24 - 24 - GAP, y, "TOPRIGHT")
            S.at(meter.less, -24 - 24 - GAP - 120 - GAP, y, "TOPRIGHT")
            S.at(meter.sub, 24, y - 4)
            meter.sub:SetWidth(width - 24 - 120 - 24 - 3 * GAP - 8)
            y = y - 28
        end
    end
    y = S.LayoutIdeas(y, n)
    return S.LayoutSuggestions(y, n)
end
