-- The mail window's notices, over the bindings block (MailWindow.lua): each is a label and 0-2
-- buttons on its right, shown only when it has something to say (UX review A5: one helper for all).
--   stale  prices are old: rescan Auctionator (Stale.lua)
--   owed   pay back: what another player mailed this account beyond what it mailed back (Ledger.lua),
--          with Ledger...; only this side ever shows
--   offer  a crafter of your own takes some of the list (Routes.Offer): Bind, and "Not for <name>"
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

local stale, owed, offerBanner
local offer -- the own-crafter binding on offer (Routes.Offer), or nil

function S.CreateBanners()
    stale = banner({ height = 32, labelY = 0, buttonY = 0 })
    owed = banner({ height = 30, labelY = -2, buttonY = 4, buttons = {
        { "Ledger...", 90, function() ns.LedgerUI.Show(S.frame) end, "MailworthyMailLedger" } } })
    offerBanner = banner({ height = 40, labelY = 2, buttonY = 2, buttons = {
        { "Bind", 60, function() UI.AcceptOffer() end, "MailworthyMailOfferBind" },
        { "Not for them", 140, function() UI.DeclineOffer() end, "MailworthyMailOfferNot" } } })
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

--- Pure: the own-crafter offer's line (Routes.Offer): "Sadie Ember is your enchanter (skill 140).
--- Send them the 3 items that disenchant instead?"
function UI.OfferText(o)
    local craft = ns.Routes.CRAFTER[o.profession]
    local who = craft and string.format("%s is your %s", o.name, craft)
        or string.format("%s has %s", o.name, tostring(ns.Routes.ProfessionName(o.profession)))
    local what = string.format("%d item%s %s", o.count, o.count == 1 and "" or "s",
        -- "that disenchant" only when every one is gear: dust and recipes are not disenchanted.
        o.profession == ns.Routes.ENCHANTING and o.gearOnly and (o.count == 1 and "that disenchants" or "that disenchant")
            or "they craft with")
    return string.format("|cffffd100%s|r%s. Send them the %s instead?", who,
        o.skill and string.format(" (skill %d)", o.skill) or "", what)
end

--- Bind (mouse, or Cross on it): the offer becomes an ordinary personal binding, and the list
--- redraws with its items going "to <name>" before anything is sent.
function UI.AcceptOffer()
    if not offer or ns.Mailer.Busy() then return end
    ns.lastCommand = "Mailworthy offer Bind"
    local o = offer
    local route, why = ns.Routes.Add(o.name, o.profession)
    if route then
        ns.Print(string.format("Bound: %s to %s. Check the list, then press Send. Remove it under Bindings or Friends...",
            ns.Routes.What(route), o.name))
    else
        ns.Print("Not bound: " .. tostring(why) .. ".")
    end
    ns.Mailer.Dismiss()
    UI.Refresh()
end

--- "Not for <name>": this character and profession are never offered again.
function UI.DeclineOffer()
    if not offer then return end
    ns.Routes.DismissOffer(offer.name, offer.profession)
    ns.Log.Add("ui", "offer declined: %s for %s", tostring(offer.profession), tostring(offer.name))
    UI.Refresh(true)
end

--- The binding on offer right now, for specs and the report.
function UI.Offer() return offer end

--- The notices for a scan; sets `shown.stale`, `shown.owed`, `shown.offer` (UI.Layout).
function S.FillBanners(result, ctx, shown)
    local okStale, nudge = pcall(ns.Stale.Current)
    shown.stale = setBanner(stale, okStale and ns.Stale.Text(nudge) or nil)
    shown.owed = setBanner(owed, UI.OwedText(ns.Ledger.On() and ns.Ledger.Debts() or {}))
    -- The own-crafter offer: not while a send runs, nor with the switch off.
    offer = nil
    if ns.Features.On("crafterOffer") and not ctx.busy then
        local okOffer, found = pcall(ns.Routes.Offer, result, ctx.bankAlt)
        if okOffer then offer = found else ns.Log.Add("ui", "offer error: %s", tostring(found)) end
    end
    shown.offer = setBanner(offerBanner, offer and UI.OfferText(offer) or nil,
        offer and { nil, "Not for " .. S.firstName(offer.name) } or nil)
end

--- Place the notices that show from `y` down (UI.Layout); returns the y under them.
function S.LayoutBanners(y, n)
    if n.stale then y = placeBanner(stale, y) end
    if n.owed then y = placeBanner(owed, y) end
    if n.offer then y = placeBanner(offerBanner, y) end
    return y
end
