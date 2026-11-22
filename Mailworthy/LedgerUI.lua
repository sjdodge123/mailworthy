-- The ledger window (/mw ledger; Settings > Bags and more; the Mailworthy window's "pay back" line;
-- the friends window): the players this account received more from than it mailed back, one
-- row each with what they sent, "Mark paid" (two presses) and "Part paid" (2026-11-22: an amount, - / +, two
-- presses: an enchant in person, a trade, part of the gold), then "Export log..." (the whole
-- mail log in the copy box). Only the player's own side: nobody is ever shown as owing them
-- (operator, 2026-11-07). Every control is a button (Nav + PadKey "settings" set); nothing to type.
-- Built on Widgets.ListWindow (rows, pager on the bottom row, empty line, Done).
local _, ns = ...

local UI = {}
ns.LedgerUI = UI

UI.ROWS = 5
local WIDTH, ROW, TOP = 520, 52, -78

local W = ns.Widgets
local win, exportButton, hint
local armed = nil     -- the player whose Mark paid was pressed once
local armedPart = nil -- the player whose Part paid was pressed once
local armedAmount = nil -- the amount that first press showed
local amounts = {}    -- player -> the part-paid amount on their row
local marked = false

function UI.Frame() return win and win.frame end
function UI.Debts() return win and win.entries or {} end
--- The footer (the Mailworthy mark's key, the controller legend), for specs.
function UI.Footer() return win and win.legend:GetText() end
--- A row's first line, for specs.
function UI.RowLine(i)
    local row = win and win.rows[i]
    return row and row.text:IsShown() and row.text:GetText() or nil
end

local function setHint(text) if hint then hint:SetText(text or "") end end

--- Pure: a row's two lines for one debt ({ name, net, items, gold }). `nameText` shows in place of
--- the name (with the Mailworthy mark, Comms.Mark).
function UI.RowText(d, nameText)
    local got = d.items ~= "" and d.items or ""
    if (d.gold or 0) > 0 then got = got ~= "" and (got .. " and " .. ns.Valuation.Money(d.gold)) or ns.Valuation.Money(d.gold) end
    return string.format("|cffffd100%s|r: %s more than you've sent back", nameText or d.name, ns.Valuation.Money(d.net)),
        got ~= "" and ("|cffaaaaaareceived " .. got .. "|r") or ""
end

-- Mark paid keeps its own two presses (no time limit, a hint line saying what the second does).
local function markPaid(row)
    local d = row.entry
    if not d then return end
    if armed ~= d.name then
        armed, armedPart = d.name, nil
        setHint("Press Mark paid again if you paid " .. d.name .. " back another way (a trade, gold in person).")
        UI.Refresh()
        return
    end
    armed = nil
    if ns.Ledger.MarkPaid(d.name) then setHint(d.name .. ": marked paid. The log keeps the record.") end
    UI.Refresh()
end

-- Part paid: its own two presses, like Mark paid; - / + change the amount and cancel a first press.
local function partPaid(row)
    local d = row.entry
    if not d then return end
    local amount = ns.Ledger.StepPart(amounts[d.name], nil, d.net)
    -- The second press pays only what the first one showed (Codex review, 2026-11-22: a mail taken in
    -- between moved the amount, and "Sure?" paid another one): a changed amount asks again.
    if armedPart ~= d.name or armedAmount ~= amount then
        armedPart, armedAmount, armed = d.name, amount, nil
        setHint(string.format("Press Part paid again if you paid %s %s back another way.", d.name, ns.Valuation.Money(amount)))
        UI.Refresh()
        return
    end
    armedPart = nil
    if ns.Ledger.MarkPaid(d.name, amount) then
        setHint(string.format("%s: %s marked paid. The log keeps the record.", d.name, ns.Valuation.Money(amount)))
    end
    amounts[d.name] = nil
    UI.Refresh()
end

local function stepPart(row, dir)
    local d = row.entry
    if not d then return end
    amounts[d.name] = ns.Ledger.StepPart(amounts[d.name], dir, d.net)
    armedPart = nil
    setHint("")
    UI.Refresh()
end

function UI.Create()
    if win then return win.frame end
    local o = {
        name = "MailworthyLedgerFrame", width = WIDTH, title = "Mail ledger", log = "ledger window",
        sub = "What other players mailed you beyond what you've mailed them back, valued when it was sent. "
            .. "Pay back by mail, in materials or gold: it counts when it goes.",
        rows = UI.ROWS, rowHeight = ROW, top = TOP,
        emptyText = "Nothing to pay back: you've mailed every player at least as much as they mailed you.",
        pagerName = "MailworthyLedgerPage", doneName = "MailworthyLedgerDone",
        makeRow = function(w, i)
            local row = {}
            row.text = W.Label(w.frame, "GameFontHighlight")
            row.text:SetWidth(WIDTH - 56 - 120)
            row.text:SetJustifyH("LEFT")
            row.detail = W.Label(w.frame, "GameFontHighlightSmall")
            row.detail:SetWidth(WIDTH - 56 - 196)
            row.detail:SetJustifyH("LEFT")
            row.paid = W.Button(w.frame, "Mark paid", 100, function() markPaid(row) end, "MailworthyLedgerPaid" .. i)
            row.less = W.Button(w.frame, "-", 24, function() stepPart(row, -1) end, "MailworthyLedgerPartLess" .. i)
            row.part = W.Button(w.frame, "Part paid", 120, function() partPaid(row) end, "MailworthyLedgerPart" .. i)
            row.more = W.Button(w.frame, "+", 24, function() stepPart(row, 1) end, "MailworthyLedgerPartMore" .. i)
            row.widgets = { row.text, row.detail, row.paid, row.less, row.part, row.more }
            return row
        end,
        before = function() marked = false end,
        -- A page turn cancels an armed Mark paid, as before the shared pager (Codex review, 2026-11-15:
        -- it stayed armed, and one press an hour later cleared the balance).
        onPage = function()
            armed, armedPart = nil, nil
            setHint("")
        end,
        list = function() return ns.Ledger.Debts() end,
        fillRow = function(row, d, y)
            local nameText, m = ns.Comms.Mark(d.name)
            marked = marked or m
            local text, detail = UI.RowText(d, nameText)
            row.text:SetText(text)
            row.detail:SetText(detail)
            row.paid:SetText(armed == d.name and "Sure?" or "Mark paid")
            local amount = ns.Ledger.StepPart(amounts[d.name], nil, d.net)
            row.part:SetText(armedPart == d.name and "Sure?" or ("Part paid: " .. ns.Valuation.Money(amount)))
            win.at(row.text, 28, y - 4)
            win.at(row.detail, 28, y - 22)
            win.at(row.paid, -24, y, "TOPRIGHT")
            win.at(row.more, -24, y - 24, "TOPRIGHT")
            win.at(row.part, -24 - 24 - 4, y - 24, "TOPRIGHT")
            win.at(row.less, -24 - 24 - 4 - 120 - 4, y - 24, "TOPRIGHT")
        end,
        -- The hint on its own line under the list (the bottom row holds Export, the pager and Done).
        below = function(w, y)
            local text = hint:GetText()
            if text and text ~= "" then
                w.at(hint, 28, y - 6)
                hint:Show()
                return y - 40
            end
            hint:Hide()
            return y - 10
        end,
        marked = function() return marked end,
    }
    win = W.ListWindow(o)
    exportButton = W.Button(win.frame, "Export log...", 130, function() UI.Export() end, "MailworthyLedgerExport")
    o.left = { exportButton } -- on the bottom row, left of the pager and Done
    hint = W.Label(win.frame, "GameFontHighlightSmall")
    hint:SetJustifyH("LEFT")
    hint:SetWidth(WIDTH - 56)
    return win.frame
end

function UI.Refresh()
    if win then win.Refresh() end
end

--- The whole mail log in the copy box (sent and received, oldest first).
function UI.Export()
    ns.Report.Show(ns.Ledger.ExportText(), "Mailworthy mail log")
    local f = ns.Report.Frame()
    if f and win then W.PlaceBeside(f, win.frame) end
    ns.Log.Add("ui", "mail log exported")
end

--- `opener`: the Mailworthy window whose button opened it, or nil (centred).
function UI.Show(opener)
    if not win then UI.Create() end
    win.Show(opener, function()
        win.pager.page, armed, armedPart = 1, nil, nil
        setHint("")
    end)
end

function UI.RefreshIfShown()
    if win then win.RefreshIfShown() end
end

ns.On("PLAYER_LOGIN", function()
    UI.Create()
    ns.Ledger.OnChanged(UI.RefreshIfShown)
end)
-- A new Mailworthy user can be a name on screen (Comms.Mark): redraw.
ns.Comms.OnMarksChanged(function() UI.RefreshIfShown() end)
