-- The mail window's notices, over the bindings block (MailWindow.lua): each is a label and 0-2
-- buttons on its right, shown only when it has something to say (UX review A5: one helper for all).
--   stale  prices are old: rescan Auctionator (Stale.lua)
--   owed   pay back: what another player mailed this account beyond what it mailed back (Ledger.lua),
--          with Mail ledger...; only this side ever shows
-- Under them, the suggested bindings (MailSuggestions.lua: crafters in the group and your own characters).
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

function S.CreateBanners()
    stale = banner({ height = 32, labelY = 0, buttonY = 0 })
    owed = banner({ height = 30, labelY = -2, buttonY = 4, buttons = {
        { "Mail ledger...", 110, function() ns.LedgerUI.Show(S.frame) end, "MailworthyMailLedger" } } })
    S.CreateSuggestions()
end

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
    shown.owed = setBanner(owed, UI.OwedText(ns.Ledger.On() and ns.Ledger.Debts() or {}))
    -- The suggested bindings: not while a send runs, nor with the switch or the setting off.
    S.FillSuggestions(result, ctx, shown)
end

--- Place the notices that show from `y` down (UI.Layout); returns the y under them.
function S.LayoutBanners(y, n)
    if n.stale then y = placeBanner(stale, y) end
    if n.owed then y = placeBanner(owed, y) end
    return S.LayoutSuggestions(y, n)
end
