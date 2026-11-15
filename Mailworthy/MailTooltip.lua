-- The mail window's row tooltips (MailWindow.lua): the item's own tooltip plus where it stands and
-- what a press does, for the mouse over a row and for the controller's highlight on it (Nav.OnSelect,
-- with "Press" for "Click" and, on a row with a pick, what Square does); and the pick button's
-- lines. Our own rows and GameTooltip only.
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared
local P = ns.Palette

S.rowOf = {} -- item row button -> row
S.pickOf = {} -- a row's pick button -> row

--- Pure: what a press does after the pick on a row's item (`item.choices`, `item.pickState`):
--- "Guild (to Jold)", "Me".
local function nextPickText(item)
    local choices = item.choices or {}
    local nextState = ns.Routes.NextPick(item.pickState or ns.Routes.MINE, choices)
    local text = ns.Routes.PickLabel(nextState, choices)
    for _, r in ipairs(choices) do
        if r.key == nextState then text = text .. " (to " .. S.firstName(ns.Routes.Recipient(r)) .. ")" end
    end
    return text
end

--- What a row's tooltip adds under the item's own (operator, 2026-11-09: "add a click to
--- lock tooltip to the rows of items being mailed"): where the item stands, then what a press
--- does. `item` is a row's item (a scan entry), `staying` its list, `pad` the controller ("Press"
--- for "Click"), `bankAlt` the saved bank alt. Returns the two lines, and with the controller on a
--- row with a pick a third: what Square does (UX review U4). `busy`: a send is running,
--- when a press changes nothing (toggleLock), so the second line says that instead of promising
--- a lock on an item already on its way (Codex review, 2026-11-09).
UI.BUSY_LINE = "Sending: locks can't change until it's done."
function UI.TooltipLines(item, staying, pad, bankAlt, busy)
    local r = item.result or {}
    local verb = pad and "Press" or "Click"
    local pick = pad and not busy and #(item.choices or {}) > 0 and ns.Features.On("padPick")
        and (ns.Gamepad.Glyph(ns.Gamepad.FACE_LEFT) .. " " .. nextPickText(item) .. ": where it goes this visit.")
        or nil
    if staying then
        if ns.Valuation.Is(r, ns.Valuation.K.locked) then
            return "Locked in Mailworthy: it stays in your bags and is never mailed.",
                busy and UI.BUSY_LINE or (verb .. " to unlock."), pick
        end
        local where = (UI.PinnedHere(r) and "BH: it stays, to bank here: you pinned it, and "
                .. tostring(ns.Pins.ModeText()) .. ".")
            or (ns.Valuation.BankForCraft(r) and ("BH: bank it here: " .. UI.WhyKept(r) .. "."))
            or ("It stays: " .. UI.StayReason(r) .. ".")
        return where, busy and UI.BUSY_LINE or (verb .. " to lock it, so it always stays."), pick
    end
    local to = r.to or bankAlt
    local where = to and ((r.route == "return" and "Going back to " or "Mailing to ") .. S.firstName(to)
        .. (r.pinned and ": you pinned it for your bank alt (BA)." or ".")) or "Mailing."
    -- The pin beats this character's own profession (operator, 2026-11-13): said on the row too.
    if r.pinConflict then
        where = where .. string.format(" Your %s uses it, but the pin wins (Settings > Pinned items: Bank here keeps it).",
            tostring(r.pinConflict))
    end
    return where, busy and UI.BUSY_LINE or (verb .. " to lock: it stays in your bags and is never mailed."), pick
end

-- The row whose tooltip shows (the mouse over it, or the controller's highlight on it), and
-- whether the controller put it there.
local tipRow, tipPad

-- Through TooltipDataProcessor (installed at login, as Border's line is) the lines are added each
-- time the game builds the tooltip, so a rebuild (item data arriving) keeps them. A build that
-- didn't come (no processor; the item already left its slot mid-send, so there is no item data:
-- Codex review, 2026-11-09) leaves them to showTooltip, which adds them once. `tipAdded`: this
-- showing's tooltip has them.
local tipAdded = false

--- The item whose row tooltip `tooltip` is, with Mailworthy's own lines on it, or nil: Border
--- leaves its "Alt+click to unlock" line off that tooltip (here a plain press does it). The
--- tooltip must still be the row's: the same item hovered in the bags after the controller's
--- highlight reached its row keeps Border's line (Codex review, 2026-11-09).
function UI.TooltipItem(tooltip)
    if not (tipRow and tipRow.item and ns.Features.On("tooltipLines")) then return nil end
    tooltip = tooltip or rawget(_G, "GameTooltip")
    if type(tooltip) ~= "table" or tooltip:GetOwner() ~= tipRow.button then return nil end
    return tipRow.item.itemID
end

local function addLines(tooltip)
    local where, press, pick = UI.TooltipLines(tipRow.item, tipRow.staying, tipPad, ns.Config.BankAlt(),
        ns.Mailer.Busy())
    local r = tipRow.item.result or {}
    -- A pin's line in its destination's colour (BA when mailed, BH when it stays), like its glow and tag.
    local c = r.vendorPin and P.V.fg or UI.PinnedHere(r) and P.BH.fg or r.pinned and P.BA.fg or ns.Border.COLOR
    tipAdded = true
    tooltip:AddLine(" ")
    tooltip:AddLine(where, c[1], c[2], c[3], true)
    tooltip:AddLine(press, 1, 0.82, 0, true)
    if pick then tooltip:AddLine(pick, 1, 0.82, 0, true) end
end

local function onTooltipData(tooltip, data)
    if tooltip ~= rawget(_G, "GameTooltip") then return end
    local id = UI.TooltipItem(tooltip)
    if id and type(data) == "table" and tonumber(data.id) == id then addLines(tooltip) end
end

--- At login: the row tooltip's lines join every build of the tooltip. False without the processor.
function UI.InstallTooltip()
    local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
    local itemType = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item
    if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" or itemType == nil then
        ns.Log.Add("ui", "TooltipDataProcessor missing: row tooltip lines added once, at show")
        return false
    end
    local ok, err = pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data)
        local okLine, errLine = pcall(onTooltipData, tooltip, data)
        if not okLine then ns.Log.Add("ui", "row tooltip error: %s", tostring(errLine)) end
    end)
    ns.Log.Add("ui", "row tooltip lines %s", ok and "installed" or ("failed: " .. tostring(err)))
    return ok == true
end

function S.hideTooltip()
    if not tipRow then return end
    tipRow = nil
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

function S.showTooltip(row, pad)
    if not row.item or type(GameTooltip) ~= "table" then return S.hideTooltip() end
    tipRow, tipPad = row, pad or false
    local slot = row.item.slots and row.item.slots[1]
    GameTooltip:SetOwner(row.button, "ANCHOR_RIGHT")
    tipAdded = false
    if slot then pcall(GameTooltip.SetBagItem, GameTooltip, slot.bag, slot.slot) end
    -- Nothing in the slot any more (sent a moment ago): the item by its link, so the lines below
    -- still have a name over them.
    local built = GameTooltip:NumLines()
    if (tonumber(built) or 0) == 0 and row.item.link then
        pcall(GameTooltip.SetHyperlink, GameTooltip, row.item.link)
    end
    if ns.Features.On("tooltipLines") and not tipAdded then addLines(GameTooltip) end
    GameTooltip:Show()
end

function S.leaveRow(row)
    if tipRow == row then S.hideTooltip() end
end

-- After a redraw the row under the mouse or the highlight may hold another item, or none.
function S.refreshTooltip()
    if not tipRow then return end
    if tipRow.item and tipRow.button:IsVisible() then S.showTooltip(tipRow, tipPad) else S.hideTooltip() end
end

-- The controller's highlight (Nav) on an item row shows the tooltip the mouse gets there, with
-- "Press" for "Click"; anywhere else it goes away. A row's pick button is not a D-pad stop (Square
-- picks on the row): its mouse tooltip goes away too.
function S.OnNavSelect(button)
    local row = button and S.rowOf[button]
    if type(GameTooltip) == "table" and S.pickOf[GameTooltip:GetOwner()] then GameTooltip:Hide() end
    if row and row.item and ns.Features.On("tooltipLines") then
        UI.stats.padTips = UI.stats.padTips + 1
        S.showTooltip(row, true)
    elseif tipRow and (tipPad or not button) then
        S.hideTooltip()
    end
end

--- Pure: the pick button's tooltip lines for a row's item: a title, one line per state (the current
--- one marked) and what a press does. `pad`: the controller ("Press" for "Click").
function UI.PickLines(item, pad, busy)
    local choices = item.choices or {}
    local current = item.pickState or ns.Routes.MINE
    local lines = { "Where this goes, for this visit" }
    local function line(state, text)
        lines[#lines + 1] = (state == current and "> " or "   ") .. text
    end
    line(ns.Routes.MINE, "Me: " .. ns.Routes.PickLabel(ns.Routes.MINE) .. " (its own rule: keep, sell or bank)")
    for _, r in ipairs(choices) do
        line(r.key, string.format("%s: to %s (%s)", ns.Routes.PickLabel(r.key, choices), S.firstName(ns.Routes.Recipient(r)),
            ns.Routes.Describe(r)))
    end
    lines[#lines + 1] = busy and UI.BUSY_LINE or string.format("%s: %s. Cleared when the mailbox closes.",
        pad and "Press" or "Click", nextPickText(item))
    return lines
end

--- The pick button's tooltip (the mouse over it).
function S.showPickTip(row)
    if not row.item or type(GameTooltip) ~= "table" then return end
    S.hideTooltip()
    GameTooltip:SetOwner(row.pick, "ANCHOR_RIGHT")
    for i, text in ipairs(UI.PickLines(row.item, false, ns.Mailer.Busy())) do
        if i == 1 then GameTooltip:SetText(text) else GameTooltip:AddLine(text, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end
