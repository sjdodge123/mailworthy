-- The locked items window (/mw locks; Settings > Bags and more > "Locked items (N)..."; QoL pass D,
-- 2026-11-09, media/qol-prototype.png): this character's locked items, one row each with how
-- many the bags hold ("x9 in your bags" / "not in your bags") and Unlock. The only place a lock
-- on an item that is no longer in the bags (banked, used up) can be removed: Alt+click and the
-- controller's lock key need the item in a bag slot. An unlocked row stays until the window
-- closes, its button now "Lock", so a wrong press is undone with a second one.
-- Every control is a button (Nav + PadKey "settings" set); nothing to type, nothing on hover.
-- Built on Widgets.ListWindow (rows, pager, empty line, Done).
local _, ns = ...

local UI = {}
ns.LocksUI = UI

UI.ROWS = 6
local WIDTH, ROW, TOP = 460, 28, -80

local W = ns.Widgets
local win, hint
local unlocked = {} -- itemID -> link (or false): unlocked here since the window opened
local busyNote = false -- a press came during a send: the hint says why nothing changed

function UI.Frame() return win and win.frame end
--- The rows as listed (every page), for specs: Locks.List entries.
function UI.List() return win and win.entries or {} end
--- A row's line as drawn (nil when the row is hidden), for specs.
function UI.RowLine(i)
    local row = win and win.rows[i]
    return row and row.text:IsShown() and row.text:GetText() or nil
end
function UI.Hint() return hint and hint:GetText() end

--- Pure: a row's line for a Locks.List entry.
function UI.RowText(e)
    local where
    if not e.locked then
        where = "|cffaaaaaaunlocked|r"
    elseif (e.count or 0) > 0 then
        where = string.format("|cffaaaaaax%d in your bags|r", e.count)
    else
        where = "|cffff8040not in your bags|r"
    end
    return (e.link or e.name) .. "  " .. where
end

--- Pure: the line under the rows: how an item gets locked (the window only unlocks).
function UI.HowText(pad)
    local key = ns.Gamepad.STICK_LEFT_PRESS
    return "Lock from your bags: Alt+click, or "
        .. (pad and ns.Gamepad.Glyph(key, 14) or (ns.Gamepad.Name(key) .. " on a controller")) .. "."
end

--- Pure: the Settings button's text.
function UI.ButtonText(n)
    return (n or 0) > 0 and string.format("Locked items (%d)...", n) or "Locked items..."
end

local function press(row)
    local e = row.entry
    if not e then return end
    if ns.Mailer.Busy() then -- like the Mailworthy window's rows: no lock changes mid-send
        busyNote = true
        return UI.Refresh()
    end
    -- Locks.ToggleItem flips whatever the lock is now; the row may be a moment old.
    if ns.Locks.IsItemLocked(e.itemID) == e.locked then
        if e.locked then unlocked[e.itemID] = e.link or false end
        ns.Locks.ToggleItem(e.itemID, e.link, "locked items window")
    end
    UI.Refresh()
end

function UI.Create()
    if win then return win.frame end
    win = W.ListWindow({
        name = "MailworthyLocksFrame", width = WIDTH, title = "Locked items", log = "locked items window",
        sub = "Mailworthy never mails these from this character. Unlock one and it follows the normal rule again.",
        rows = UI.ROWS, rowHeight = ROW, top = TOP,
        emptyText = "No locked items on this character.",
        pagerName = "MailworthyLocksPage", doneName = "MailworthyLocksDone",
        makeRow = function(w, i)
            local row = {}
            row.text = W.Label(w.frame, "GameFontHighlight")
            row.text:SetWidth(WIDTH - 56 - 100)
            row.text:SetJustifyH("LEFT")
            if type(row.text.SetWordWrap) == "function" then pcall(row.text.SetWordWrap, row.text, false) end
            row.button = W.Button(w.frame, "Unlock", 90, function() press(row) end, "MailworthyLocksUnlock" .. i)
            row.widgets = { row.text, row.button }
            return row
        end,
        list = function() return ns.Locks.List(unlocked) end,
        fillRow = function(row, e, y)
            row.text:SetText(UI.RowText(e))
            row.button:SetText(e.locked and "Unlock" or "Lock")
            win.at(row.text, 28, y - 5)
            win.at(row.button, -24, y, "TOPRIGHT")
        end,
        below = function(w, y)
            busyNote = busyNote and ns.Mailer.Busy()
            hint:SetText(busyNote and (ns.MailWindow and ns.MailWindow.BUSY_LINE
                or "Sending: locks can't change until it's done.") or UI.HowText(ns.MailButton.GamepadUI()))
            w.at(hint, 28, y - 6)
            return y - 30
        end,
    })
    hint = W.Label(win.frame, "GameFontHighlightSmall")
    hint:SetWidth(WIDTH - 56)
    hint:SetJustifyH("LEFT")
    return win.frame
end

function UI.Refresh()
    if win then win.Refresh() end
end

--- `opener`: the Mailworthy window whose button opened it, or nil (centred).
function UI.Show(opener)
    if not win then UI.Create() end
    win.Show(opener, function(wasShown)
        -- Pressed again while open (Settings' button): the rows unlocked here stay, with their Lock
        -- buttons (Codex review: the undo for an item that is not in the bags went with them).
        if not wasShown then win.pager.page, unlocked = 1, {} end
        busyNote = false
    end)
end

function UI.RefreshIfShown()
    if win then win.RefreshIfShown() end
end

ns.On("PLAYER_LOGIN", function()
    UI.Create()
    ns.Locks.OnChanged(UI.RefreshIfShown)
    -- A send ended: the "locks can't change" hint goes at once (Codex review), not at the next press.
    ns.Mailer.OnChanged(UI.RefreshIfShown)
end)
-- The counts follow the bags (an item banked, looted or used while the window is open).
ns.On("BAG_UPDATE_DELAYED", UI.RefreshIfShown)
