-- The ledger window (/mw ledger; Settings > Bags and more; the Mailworthy window's "pay back" line;
-- the friends window): the players this account received more from than it mailed back, one
-- row each with what they sent and "Mark paid" (two presses), then "Export log..." (the whole
-- mail log in the copy box). Only the player's own side: nobody is ever shown as owing them
-- (operator, 2026-11-07). Every control is a button (Nav + PadKey "settings" set); nothing to type.
-- Built on Widgets.ListWindow (rows, pager on the bottom row, empty line, Done).
local _, ns = ...

local UI = {}
ns.LedgerUI = UI

UI.ROWS = 5
local WIDTH, ROW, TOP = 520, 44, -78

local W = ns.Widgets
local win, exportButton, hint
local armed = nil
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
        armed = d.name
        setHint("Press Mark paid again if you paid " .. d.name .. " back another way (a trade, gold in person).")
        UI.Refresh()
        return
    end
    armed = nil
    if ns.Ledger.MarkPaid(d.name) then setHint(d.name .. ": marked paid. The log keeps the record.") end
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
            row.detail:SetWidth(WIDTH - 56 - 120)
            row.detail:SetJustifyH("LEFT")
            row.paid = W.Button(w.frame, "Mark paid", 100, function() markPaid(row) end, "MailworthyLedgerPaid" .. i)
            row.widgets = { row.text, row.detail, row.paid }
            return row
        end,
        before = function() marked = false end,
        list = function() return ns.Ledger.Debts() end,
        fillRow = function(row, d, y)
            local nameText, m = ns.Comms.Mark(d.name)
            marked = marked or m
            local text, detail = UI.RowText(d, nameText)
            row.text:SetText(text)
            row.detail:SetText(detail)
            row.paid:SetText(armed == d.name and "Sure?" or "Mark paid")
            win.at(row.text, 28, y - 4)
            win.at(row.detail, 28, y - 22)
            win.at(row.paid, -24, y, "TOPRIGHT")
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
        win.pager.page, armed = 1, nil
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
