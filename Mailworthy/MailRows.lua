-- The mail window's two lists (MailWindow.lua): Mailing (icon, item, chip, gain) and Staying in your
-- bags (item, why), a pager each, and on a row a binding could take, its pick button.
--
-- A row is one button: a press locks the item (it stays in the bags) or unlocks it. The pick button
-- (Routes.Pick; operator, 2026-11-14) says where the item goes this mailbox visit, cycling Me (its
-- own verdict; "Here" on a bank-here row) -> Alt (a bank-here row: the bank alt; operator, 2026-11-21)
-- -> each friend binding that takes it -> each guild rule that takes it. Mouse: click
-- it. Controller: one D-pad stop per row (UX review U4): Square on the highlighted row moves its pick
-- on (UI.PadPick, PadKey "window" set); the pick button is not a D-pad stop of its own (Nav.Skip).
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared
local W = ns.Widgets
local P = ns.Palette

-- The chips on the Mailing rows: { text, r, g, b }, each in its bag tag's colour with its letters
-- (Palette.lua: the tag, the glow, the chip and the tooltip agree; operator, 2026-11-13).
local function paletteChip(text, entry) return { text, entry.bg[1], entry.bg[2], entry.bg[3] } end
UI.CHIPS = {
    ah = paletteChip("AH auction", P.AH),
    de = paletteChip("DE disenchant", P.DE),
    common = paletteChip("Common", P.COMMON),
    bank = paletteChip("BA bank", P.BA), -- mailed to the bank alt to bank there
    noprice = paletteChip("No price", P.NOPRICE), -- no auction price yet: the bank alt holds it (2026-11-08)
    vendor = paletteChip("V vendor", P.V), -- a V item mailed because "Send: V" is on
    friend = paletteChip("to a friend", P.F), -- the chip says "to <first name>", in F's colour
    ["return"] = paletteChip("back to sender", P.R), -- the chip says "back to <first name>", in R's colour
    pinned = paletteChip("BA pinned", P.BA), -- a bank pin (Pins.lua) to the bank alt: its tag and glow's colour
}

--- The chip for a result: a pinned item's own, else its route's.
function UI.ChipFor(r)
    return (r.pinned and UI.CHIPS.pinned) or UI.CHIPS[r.route] or UI.CHIPS.common
end

--- Pure: a row's item has a pick button: a binding could take it (`item.choices`), or it is banked here
--- and the bank alt could (`item.alt`: Routes.AltOffered; operator, 2026-11-21: Here / Alt).
function UI.HasPick(item)
    return type(item) == "table" and (#(item.choices or {}) > 0 or item.alt == true)
end

--- Pure: a bank-here pin's keep (not a BA pin held this visit).
function UI.PinnedHere(r)
    return r.pinned == true and ns.Valuation.Is(r, ns.Valuation.K.pinHere)
end

--- Pure: the Staying row's reason in the colour of the tag the bags show for it: BH (bank it here:
--- a bank-here pin, this character's crafting) in BH's teal, "BH " in front; the rest as it is.
function UI.StayText(r)
    local text = UI.StayReason(r)
    if r.vendorPin then return P.Hex(P.V.fg) .. "V " .. text .. "|r" end
    if UI.PinnedHere(r) or ns.Valuation.BankForCraft(r) then
        return P.Hex(P.BH.fg) .. "BH " .. text .. "|r"
    end
    return text
end

--- Pure: "|cffRRGGBB" + name from an item link (no brackets), or the link as is.
function UI.ItemText(link, count, stacks)
    local color, name = tostring(link):match("|c(%x%x%x%x%x%x%x%x).-%[(.-)%]")
    local text = name and ("|c" .. color .. name .. "|r") or tostring(link)
    if count and count > 1 then text = text .. " |cffaaaaaax" .. count .. "|r" end
    if stacks and stacks > 1 then text = text .. " |cff888888(" .. stacks .. " stacks)|r" end
    return text
end

UI.LOCKED_COLOR = "|cff4da6ff" -- the bags' lock-glow blue

--- Pure: the Staying header's count, with how many of them are locked (listed first).
function UI.StayCountText(items, locked)
    local text = string.format("%d item%s", items, items == 1 and "" or "s")
    if locked > 0 then text = string.format("%s%d locked|r · %s", UI.LOCKED_COLOR, locked, text) end
    return text
end

--- Pure: a player-facing reason for an item that stays, without the advice (UI.StayReason).
function UI.WhyKept(r)
    local money = S.money
    if r.held then -- the bank alt's share, held (none set, or skipped this visit): Bags.HoldReason
        local chip = UI.ChipFor(r)
        return string.format("%s%s: %s", chip[1], r.gain and (" +" .. money(r.gain)) or "", r.held)
    end
    if r.quest then return r.quest .. " needs it" end
    local V, K = ns.Valuation, ns.Valuation.K
    if V.Is(r, K.notWorth) then
        if (r.gain or 0) <= 0 then return "sells better at a vendor" end
        return string.format("only %s more than a vendor (needs %s)", money(r.gain), money(r.threshold))
    end
    if V.Is(r, K.priceFailed) then return "the price lookup failed" end
    if V.Is(r, K.noPrice) then return r.failed and "the price lookup failed" or "no auction price yet" end
    if V.Is(r, K.locked) then return "locked (press to unlock)" end
    if V.Is(r, K.ammo) then return "ammo for your ranged weapon" end
    if V.Is(r, K.junk) then return "junk: sell it at a vendor" end
    if V.Is(r, K.trash) then return "vendor trash: sell it at a vendor" end
    if V.Is(r, K.uncommon) then return "uncommon: needs auction prices" end
    if r.untilSkill then return r.reason .. " (until skill " .. r.untilSkill .. ")" end
    if r.window then
        return string.format("%s (%s still %s)", r.reason, tostring(r.window.recipe),
            ns.TierCheck.COLORS[r.window.difficulty] or "in use")
    end
    if r.convert then return string.format("convert it: %d make a %s (pays more)", r.convert.count, r.convert.name) end
    return r.reason
end

--- Pure: a player-facing reason for an item that stays; one kept for this character's own crafting
--- says to bank it (operator, 2026-11-11), as the bag tag's B does.
function UI.StayReason(r)
    if ns.Valuation.BankForCraft(r) then return "bank it: " .. UI.WhyKept(r) end
    return UI.WhyKept(r)
end

local function toggleLock(row)
    if row.item and not ns.Mailer.Busy() then
        -- A fresh lock goes to the top of Staying (locked items first): show that page.
        if not ns.Locks.IsItemLocked(row.item.itemID) then S.pages.stay = 1 end
        ns.Mailer.Dismiss() -- the list changes: the last run's receipt no longer describes it
        ns.Locks.ToggleItem(row.item.itemID, row.item.link, "Mailworthy window")
    end
end

local function rowButton(name, parent, height)
    local b = CreateFrame("Button", name, parent)
    b:SetHeight(height)
    b:SetPoint("LEFT", 16, 0)
    b:SetPoint("RIGHT", -16, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    return b, bg
end

-- A suggestion's rows, lit while its button has the mouse or the controller's highlight
-- (MailSuggestions.lua): a gold wash over the row, on the row's own texture.
local litLinks = nil -- link -> true, or nil

local function litTexture(b)
    local t = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetAllPoints()
    t:SetColorTexture(1, 0.82, 0, 0.18)
    t:Hide()
    return t
end

local function applyLit(row)
    if not row.lit then return end
    if litLinks and row.item and litLinks[row.item.link] then row.lit:Show() else row.lit:Hide() end
end

--- Light the list rows holding `items` (each { link }), or none (nil).
function S.LightRows(items)
    if items and #items > 0 then
        litLinks = {}
        for _, item in ipairs(items) do
            if item.link then litLinks[item.link] = true end
        end
    else
        litLinks = nil
    end
    for _, row in ipairs(S.mailRows) do applyLit(row) end
    for _, row in ipairs(S.stayRows) do applyLit(row) end
end

--- Is the row with this item ID lit (specs)?
function UI.RowLit(itemID)
    for _, rowsOf in ipairs({ S.mailRows, S.stayRows }) do
        for _, row in ipairs(rowsOf) do
            if row.button:IsShown() and row.item and row.item.itemID == itemID then
                return row.lit ~= nil and row.lit:IsShown()
            end
        end
    end
    return false
end

-- A row's pick moves on (its button by mouse, Square on the row by controller). Never during a send.
local function cyclePick(row)
    local item = row.item
    if not item or ns.Mailer.Busy() or not UI.HasPick(item) then return false end
    local nextState = ns.Routes.NextPick(item.pickState or ns.Routes.MINE, item.choices, item.alt)
    ns.lastCommand = "Mailworthy pick"
    ns.Mailer.Dismiss() -- the list changes: the last run's receipt no longer describes it
    ns.Routes.Pick(item.link, nextState)
    ns.Log.Add("routes", "picked %s for %s", ns.Routes.PickLabel(nextState, item.choices, item.bankHere),
        tostring(item.link))
    UI.Refresh()
    return true
end

--- The shown pick button of the row holding `itemID` (either list), or nil.
function UI.PickFor(itemID)
    for button, row in pairs(S.pickOf) do
        if button:IsShown() and row.button:IsShown() and row.item and row.item.itemID == itemID then return button end
    end
    return nil
end

--- The shown row button holding `itemID` (either list), or nil.
function UI.RowFor(itemID)
    for _, rows in ipairs({ S.mailRows, S.stayRows }) do
        for _, row in ipairs(rows) do
            if row.button:IsShown() and row.item and row.item.itemID == itemID then return row.button end
        end
    end
    return nil
end

--- Is a pick button showing on any row (the controller legend then says what Square does)?
function S.AnyPick()
    for button, row in pairs(S.pickOf) do
        if button:IsShown() and row.button:IsShown() then return true end
    end
    return false
end

-- The row now showing the item with `link`, its list turned to the page that holds it (a pick
-- can move an item from Staying to Mailing), or nil.
local function rowShowing(link)
    local lists = { { page = "mail", items = "mail", rows = S.mailRows }, { page = "stay", items = "keep", rows = S.stayRows } }
    -- The row with the pick first: what goes back to its sender (Return to sender) shares the link and
    -- has none (Codex review, 2026-11-21: Square then landed on it and did nothing).
    for _, wantPick in ipairs({ true, false }) do
        for _, list in ipairs(lists) do
            for _, row in ipairs(list.rows) do
                if row.button:IsShown() and row.item and row.item.link == link
                    and (not wantPick or UI.HasPick(row.item)) then
                    return row.button
                end
            end
        end
    end
    for _, wantPick in ipairs({ true, false }) do
        for _, list in ipairs(lists) do
            for i, item in ipairs(S.result and S.result[list.items] or {}) do
                if item.link == link and (not wantPick or UI.HasPick(item)) then
                    S.pages[list.page] = math.floor((i - 1) / #list.rows) + 1
                    UI.Refresh(true)
                    return list.rows[(i - 1) % #list.rows + 1].button
                end
            end
        end
    end
    return nil
end

--- Square on the controller's highlighted row (PadKey "window" set, switch padPick): its pick moves
--- on, as a click on the row's pick button does, and the highlight follows the item to its row.
--- Nothing on a row without a pick, nor while a send runs. Returns true when it picked.
function UI.PadPick()
    local row = S.rowOf[ns.Nav.Current()]
    if not (row and row.item and S.frame and S.frame:IsVisible()) then return false end
    local link = row.item.link
    if not cyclePick(row) then return false end
    local now = rowShowing(link)
    if now and now:IsVisible() then ns.Nav.Select(now) end
    return true
end

local function pickButton(row, parent, name, height)
    row.pick = W.Button(parent, "Me", 56, function() cyclePick(row) end, name)
    row.pick:SetHeight(height)
    row.pick:SetScript("OnEnter", function() S.showPickTip(row) end)
    row.pick:SetScript("OnLeave", function()
        if type(GameTooltip) == "table" and GameTooltip:GetOwner() == row.pick then GameTooltip:Hide() end
    end)
    row.pick:Hide()
    -- One D-pad stop per row: Square picks on the row (switch padPick; off, the button is a stop again).
    if ns.Features.On("padPick") then ns.Nav.Skip(row.pick) end
    S.pickOf[row.pick] = row
end

--- A row's pick button for its item: shown when a binding could take it, or the bank alt a bank-here
--- item (Alt), named for its state, lit when the player picked it.
local function fillPick(row, item)
    if not row.pick then return end
    if not UI.HasPick(item) then
        row.pick:Hide()
        return
    end
    row.pick:SetText(ns.Routes.PickLabel(item.pickState, item.choices, item.bankHere))
    W.SetToggled(row.pick, item.result and item.result.picked == true)
    row.pick:Show()
end

local function createMailRows()
    for i = 1, UI.MAIL_ROWS do
        local row = {}
        local b, bg = rowButton("MailworthyMailRow" .. i, S.frame, S.MAIL_ROW - 2)
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
        row.button = b
        row.lit = litTexture(b)
        row.icon = b:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 8, 0)
        row.name = W.Label(b, "GameFontHighlight")
        row.name:SetPoint("LEFT", 40, 0)
        row.name:SetWidth(200)
        row.name:SetJustifyH("LEFT")
        row.chipBg = b:CreateTexture(nil, "BORDER")
        row.chipBg:SetSize(84, 16)
        row.chipBg:SetPoint("LEFT", 250, 0)
        row.chip = W.Label(b, "GameFontHighlightSmall")
        row.chip:SetPoint("CENTER", row.chipBg, "CENTER")
        row.gain = W.Label(b, "GameFontHighlight")
        row.gain:SetPoint("RIGHT", -8, 0)
        b:SetScript("OnClick", function() toggleLock(row) end)
        b:SetScript("OnEnter", function() S.showTooltip(row) end)
        b:SetScript("OnLeave", function() S.leaveRow(row) end)
        pickButton(row, b, "MailworthyMailPick" .. i, 18)
        row.pick:SetPoint("LEFT", 340, 0)
        b:Hide()
        S.rowOf[b] = row
        S.mailRows[i] = row
    end
end

local function createStayRows()
    for i = 1, UI.STAY_ROWS do
        local row = {}
        local b, bg = rowButton("MailworthyStayRow" .. i, S.frame, S.STAY_ROW - 1)
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.02 or 0.05)
        row.button = b
        row.lit = litTexture(b)
        row.name = W.Label(b, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetWidth(220)
        row.name:SetJustifyH("LEFT")
        row.reason = W.Label(b, "GameFontHighlightSmall")
        row.reason:SetPoint("LEFT", 236, 0)
        row.reason:SetWidth(186)
        row.reason:SetJustifyH("LEFT")
        row.reason:SetTextColor(0.55, 0.75, 1)
        b:SetScript("OnClick", function() toggleLock(row) end)
        b:SetScript("OnEnter", function() S.showTooltip(row) end)
        b:SetScript("OnLeave", function() S.leaveRow(row) end)
        pickButton(row, b, "MailworthyStayPick" .. i, 16)
        row.pick:SetPoint("RIGHT", -4, 0)
        b:Hide()
        row.staying = true
        S.rowOf[b] = row
        S.stayRows[i] = row
    end
end

-- A list's pager: "<" and "2/5  >", each a button (QoL pass, 2026-11-09: two-way; forward-only
-- before). Past the last page comes the first, before the first the last.
local function pageButton(name, list)
    local function turn(by)
        local rows = list == "mail" and UI.MAIL_ROWS or UI.STAY_ROWS
        local items = S.result and S.result[list == "mail" and "mail" or "keep"] or {}
        local count = math.max(1, math.ceil(#items / rows))
        S.pages[list] = (S.pages[list] - 1 + by) % count + 1
        UI.Refresh(true)
    end
    local b = W.Button(S.frame, "", 70, function() turn(1) end, name)
    b:Hide()
    W.PagerBack(S.frame, b, name .. "Back", function() turn(-1) end)
    return b
end

--- At login: both lists, their headings and pagers.
function S.CreateLists()
    local frame = S.frame
    S.mailHead = W.Label(frame, "GameFontNormal")
    S.mailHead:SetText("Mailing")
    S.mailHint = W.Label(frame, "GameFontDisableSmall")
    S.mailHint:SetText("press an item to keep it in your bags")
    S.mailCount = W.Label(frame, "GameFontHighlightSmall")
    S.mailPage = pageButton("MailworthyMailPage", "mail")
    S.mailEmpty = W.Label(frame, "GameFontDisableSmall")
    S.mailEmpty:SetText("Nothing worth mailing in your bags right now.")
    createMailRows()

    S.stayHead = W.Label(frame, "GameFontNormal")
    S.stayHead:SetText("Staying in your bags")
    S.stayCount = W.Label(frame, "GameFontHighlightSmall")
    S.stayPage = pageButton("MailworthyStayPage", "stay")
    createStayRows()
end

--- Fill the shown rows of a list from its page; returns how many show.
local function fillList(rows, items, page, perPage, fill)
    local first = (page - 1) * perPage
    local shown = 0
    for i, row in ipairs(rows) do
        local item = items[first + i]
        row.item = item
        applyLit(row)
        if item then
            fill(row, item)
            row.button:Show()
            shown = shown + 1
        else
            row.button:Hide()
        end
    end
    return shown
end

local function fillMailRow(row, item)
    local chip = UI.ChipFor(item.result)
    row.icon:SetTexture(item.icon)
    row.name:SetText(UI.ItemText(item.link, item.count, item.stacks))
    local to = item.result.to and S.firstName(item.result.to)
    row.chip:SetText(to and ((item.result.route == "return" and "back to " or "to ") .. to) or chip[1])
    row.chipBg:SetColorTexture(chip[2], chip[3], chip[4], 0.9)
    row.gain:SetText(item.result.gain and ("+" .. S.money(item.result.gain)) or "")
    fillPick(row, item)
end

local function fillStayRow(row, item)
    row.name:SetText(UI.ItemText(item.link, item.count))
    local reason = UI.StayText(item.result)
    if ns.Valuation.Is(item.result, ns.Valuation.K.locked) then reason = UI.LOCKED_COLOR .. reason .. "|r" end
    row.reason:SetText(reason)
    fillPick(row, item)
end

local function pageLabel(button, list, rows)
    local count = math.ceil(#list / rows)
    if count <= 1 then
        button:Hide()
        return
    end
    button:SetText(string.format("%d/%d  >", math.min(S.pages[button == S.mailPage and "mail" or "stay"], count), count))
    button:Show()
end

--- Both lists from the scan: headings, rows, pagers, the hint and the empty line. Returns how many
--- Mailing and Staying rows show.
function S.FillLists(result, ctx)
    local t = result.totals
    for list, n in pairs({ mail = UI.MAIL_ROWS, stay = UI.STAY_ROWS }) do
        local items = result[list == "mail" and "mail" or "keep"]
        if S.pages[list] > math.max(1, math.ceil(#items / n)) then S.pages[list] = 1 end
    end
    S.mailCount:SetText(string.format("%d item%s · %d mail%s", t.items, t.items == 1 and "" or "s",
        t.mails, t.mails == 1 and "" or "s"))
    S.stayCount:SetText(UI.StayCountText(#result.keep, result.locked or 0))
    local mail = fillList(S.mailRows, result.mail, S.pages.mail, UI.MAIL_ROWS, fillMailRow)
    local stay = fillList(S.stayRows, result.keep, S.pages.stay, UI.STAY_ROWS, fillStayRow)
    pageLabel(S.mailPage, result.mail, UI.MAIL_ROWS)
    pageLabel(S.stayPage, result.keep, UI.STAY_ROWS)
    -- The hint gives way to the pager on a long list (they share the heading line).
    if mail > 0 and not S.mailPage:IsShown() then S.mailHint:Show() else S.mailHint:Hide() end
    S.mailEmpty:SetText(UI.EmptyText(ctx.bankAlt ~= nil or ctx.isBankAlt))
    if mail > 0 then S.mailEmpty:Hide() else S.mailEmpty:Show() end
    for _, w in ipairs({ S.stayHead, S.stayCount }) do
        if stay > 0 then w:Show() else w:Hide() end
    end
    return mail, stay
end
