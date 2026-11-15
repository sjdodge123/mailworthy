-- The pinned items window (/mw pins; Settings > Bags and more > "Pinned items (N)..."; UX review U3,
-- 2026-11-15, media/simplify-prototype.png panel 6): the account's pinned items (Pins.lua), one row
-- each with where the pin sends it from this character (BA: mailed to the bank alt, BH: banked here,
-- V: kept for the vendor), how many the bags hold ("x3 in your bags" / "not in your bags") and Unpin.
-- The only place a pin on an item that is no longer in the bags can be removed: Ctrl+Alt+click and
-- the controller's pin key need the item in a bag slot. An unpinned row stays until the window
-- closes, its button now "Pin" (the pin it had), so a wrong press is undone with a second one.
-- No change while a send runs (Mailer.Busy): what is on its way was previewed, like every pin change.
-- Built like the locked items window (Widgets.ListWindow); every control is a button (Nav + PadKey
-- "settings" set), nothing to type, nothing on hover.
local _, ns = ...

local UI = {}
ns.PinsUI = UI

UI.ROWS = 6
local WIDTH, ROW, TOP = 460, 28, -80

local W = ns.Widgets
local win, hint
local unpinned = {} -- itemID -> { link, kind }: unpinned here since the window opened
local busyNote = false -- a press came during a send: the hint says why nothing changed

function UI.Frame() return win and win.frame end
--- The rows as listed (every page), for specs: { itemID, link, name, kind (nil: unpinned here), was, count }.
function UI.List() return win and win.entries or {} end
--- A row's line as drawn (nil when the row is hidden), for specs.
function UI.RowLine(i)
    local row = win and win.rows[i]
    return row and row.text:IsShown() and row.text:GetText() or nil
end
function UI.Hint() return hint and hint:GetText() end

--- Pure: a row's line. `where` is the Palette entry the pin has here (BA / BH / V), nil when unpinned.
function UI.RowText(e, where)
    local count
    if (e.count or 0) > 0 then
        count = string.format("|cffaaaaaax%d in your bags|r", e.count)
    else
        count = "|cffff8040not in your bags|r"
    end
    local pin = where and ns.Palette.Letters(where) or "|cffaaaaaaunpinned|r"
    return (e.link or e.name) .. "  " .. pin .. "  " .. count
end

--- Pure: the line under the rows: how an item gets pinned (the window only unpins, and undoes).
function UI.HowText(pad)
    local key = ns.Gamepad.STICK_RIGHT_PRESS
    return "Pin from your bags: Ctrl+Alt+click, or "
        .. (pad and ns.Gamepad.Glyph(key, 14) or (ns.Gamepad.Name(key) .. " on a controller")) .. "."
end

--- Pure: the Settings button's text.
function UI.ButtonText(n)
    return (n or 0) > 0 and string.format("Pinned items (%d)...", n) or "Pinned items..."
end

--- Every pin, and the ones unpinned here since the window opened, by name.
function UI.Entries()
    local counts, list, seen = ns.Locks.BagCounts(), {}, {}
    for _, e in ipairs(ns.Pins.List()) do
        e.count = counts[e.itemID] or 0
        list[#list + 1] = e
        seen[e.itemID] = true
    end
    for itemID, u in pairs(unpinned) do
        if not seen[itemID] and not ns.Pins.Kind(itemID) then
            list[#list + 1] = { itemID = itemID, link = u.link, name = ns.Locks.NameOf(itemID, u.link), was = u.kind,
                count = counts[itemID] or 0 }
        end
    end
    table.sort(list, function(a, b)
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return tostring(a.itemID) < tostring(b.itemID)
    end)
    return list
end

local function press(row)
    local e = row.entry
    if not e then return end
    if ns.Mailer.Busy() then -- like Ctrl+Alt+click: no pin changes mid-send
        busyNote = true
        return UI.Refresh()
    end
    -- The row may be a moment old: act only when the pin is still what it shows.
    if ns.Pins.Kind(e.itemID) == e.kind then
        if e.kind then
            unpinned[e.itemID] = { link = e.link, kind = e.kind }
            ns.Pins.Set(e.itemID, e.link, nil, "pinned items window")
        elseif e.was then
            ns.Pins.Set(e.itemID, e.link, e.was, "pinned items window")
        end
    end
    UI.Refresh()
end

function UI.Create()
    if win then return win.frame end
    win = W.ListWindow({
        name = "MailworthyPinsFrame", width = WIDTH, title = "Pinned items", log = "pinned items window",
        sub = "Bank pins go to your bank alt (BA), or stay to bank here (BH); vendor pins stay, tagged V. "
            .. "On every character of this account.",
        rows = UI.ROWS, rowHeight = ROW, top = TOP,
        emptyText = "No pinned items.",
        pagerName = "MailworthyPinsPage", doneName = "MailworthyPinsDone",
        makeRow = function(w, i)
            local row = {}
            row.text = W.Label(w.frame, "GameFontHighlight")
            row.text:SetWidth(WIDTH - 56 - 100)
            row.text:SetJustifyH("LEFT")
            if type(row.text.SetWordWrap) == "function" then pcall(row.text.SetWordWrap, row.text, false) end
            row.button = W.Button(w.frame, "Unpin", 90, function() press(row) end, "MailworthyPinsUnpin" .. i)
            row.widgets = { row.text, row.button }
            return row
        end,
        list = UI.Entries,
        fillRow = function(row, e, y)
            row.text:SetText(UI.RowText(e, e.kind and ns.Pins.Palette(e.itemID) or nil))
            row.button:SetText(e.kind and "Unpin" or "Pin")
            win.at(row.text, 28, y - 5)
            win.at(row.button, -24, y, "TOPRIGHT")
        end,
        below = function(w, y)
            busyNote = busyNote and ns.Mailer.Busy()
            hint:SetText(busyNote and ns.Pins.BUSY or UI.HowText(ns.MailButton.GamepadUI()))
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
        -- Pressed again while open: the rows unpinned here stay, with their Pin buttons.
        if not wasShown then win.pager.page, unpinned = 1, {} end
        busyNote = false
    end)
end

function UI.RefreshIfShown()
    if win then win.RefreshIfShown() end
end

ns.On("PLAYER_LOGIN", function()
    UI.Create()
    ns.Pins.OnChanged(UI.RefreshIfShown)
    -- A send ended: the "pins can't change" hint goes at once, not at the next press.
    ns.Mailer.OnChanged(UI.RefreshIfShown)
end)
-- The counts follow the bags.
ns.On("BAG_UPDATE_DELAYED", UI.RefreshIfShown)
