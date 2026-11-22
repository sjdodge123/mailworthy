-- The Mailworthy window at the mailbox (media/ux-pass-prototype.png): who the mail
-- goes to, the bindings in force (only when there are any: a profession's materials
-- to a friend, with Skip once and Remove), what goes and why, what stays and why,
-- the total gain, and Send / Settings... One press of Send mails everything (Mailer).
-- The window grows and shrinks to the rows it shows (UI.Layout); the X, Escape and
-- the controller's Circle close it.
--
-- It opens by itself when the Send Mail tab shows (operator, 2026-11-08: "when you click send
-- mail mailworthy should open"; the tab watcher sees the tab, switch autoOpen). Opened on the
-- Inbox, Send is greyed out and says "Click Send Mail"; on Send Mail it is "Send to ...".
--
-- Mouse: click. Controller: Triangle at the mail window opens it, then the D-pad
-- moves Mailworthy's own highlight, Cross presses, Square moves a row's pick on, Circle closes
-- (PadKey "window" set, Nav). Every row is a button: pressing an item locks it (it stays in the
-- bags) or unlocks it, so the controller can change the list without a menu.
-- A row's tooltip (the mouse over it, or the controller's highlight on it) is the item's own plus
-- where it stands and what a press does ("Click to lock ...", "Press to unlock."; switch
-- tooltipLines). Everything it says is also on the row itself.
--
-- Return to sender (operator, 2026-11-08; Returns.lua): a toggle beside Settings..., on every
-- character. While it is on (lit green, like every toggle that is on), what other characters
-- mailed this one joins the Mailing list, to go back to them; pressed again, the list is back to
-- normal. On the bank alt the window works too ("bank alt view should still allow mail
-- automation"): its own share stays (it sells it), bindings and returns mail, and a Bank alt
-- summary... button opens the old summary (switch bankAltMail off: the button opens only the summary).
--
-- The window is split over several files (loaded in .toc order, all on this one ns.MailWindow
-- table; UX review A5):
--   MailWindow.lua      this file: the frame, Create, Layout, Refresh (one call per block), Show
--   MailTooltip.lua     the row tooltips (mouse and the controller's highlight), the pick's lines
--   MailRows.lua        the Mailing / Staying rows, their pick buttons (and Square), the pagers
--   MailRecipients.lua  "To:" and its lines, Skip once / Choose bank alt..., Return to sender
--   MailBanners.lua     the notices over the bindings: stale prices, pay back, a crafter on offer
--   MailBindings.lua    the bindings block (Skip once, Remove asks "Sure?")
--   MailTotals.lua      the total box: gain, fees, postage, the last run's receipt
--   MailSend.lua        Send / Stop and "what was previewed is what is sent" (UI.Changed)
--   MailTabs.lua        the tab watcher: Inbox or Send Mail, opening by itself, re-reading
--
-- Created at login (never while a gamepad panel is open), parented to the
-- showing mail tab; nothing is written into Blizzard's frames or tables.
local _, ns = ...

local UI = {}
ns.MailWindow = UI

UI.MAIL_ROWS, UI.STAY_ROWS, UI.ROUTE_ROWS = 8, 5, 3
UI.TO_LINES = 2 -- recipient lines under "To:" (the last says "+N more" when there are more)
UI.stats = { padTips = 0 } -- /mw report: tooltips the controller's highlight showed

-- The window's state and widgets, shared by its files (not for other modules).
local S = {
    WIDTH = 520, MAIL_ROW = 30, STAY_ROW = 20, ROUTE_ROW = 24,
    pages = { mail = 1, stay = 1 },
    mailRows = {}, stayRows = {}, routeRows = {}, toLines = {},
    -- frame, title, legend; result (the scan on screen); shownAlt (the bank alt the list on screen
    -- was drawn for: UI.Send compares against it); marked (a name on screen carries the Mailworthy
    -- mark: the footer says what it means); and each file's widgets.
}
UI.shared = S

local W = ns.Widgets

function S.money(c) return ns.Valuation.Money(c) end
function S.firstName(name) return tostring(name):match("^(%S+)") or tostring(name) end

-- `text` (default: the name) with the Mailworthy mark when `name` runs Mailworthy (Comms.Mark).
function S.withMark(name, text)
    local out, m = ns.Comms.Mark(name, text)
    S.marked = S.marked or m
    return out
end

function S.at(widget, x, y, point)
    widget:ClearAllPoints()
    widget:SetPoint(point or "TOPLEFT", S.frame, point or "TOPLEFT", x, y)
end

function UI.Frame() return S.frame end
function UI.Result() return S.result end
--- The footer (the Mailworthy mark's key, the controller legend), for specs.
function UI.Footer() return S.legend and S.legend:GetText() end
--- The texts at the top ("To:" and the recipient lines) and the fees / status line, for specs and the report.
function UI.Texts()
    local to = { S.toName and S.toName:GetText() }
    for _, line in ipairs(S.toLines) do
        if line.name:IsShown() then to[#to + 1] = line.name:GetText() .. " | " .. line.note:GetText() end
    end
    return { to = to, note = S.totalNote and S.totalNote:GetText(), total = S.totalLine and S.totalLine:GetText() }
end

function UI.Create()
    if S.frame then return S.frame end
    local send = rawget(_G, "SendMailFrame")
    local frame = W.Window("MailworthyMailWindow", S.WIDTH, 400, type(send) == "table" and send or nil)
    S.frame = frame
    S.title = W.Label(frame, "GameFontNormalLarge")
    S.title:SetPoint("TOPLEFT", 22, -18)
    S.CreateTo()
    S.CreateBanners()
    S.CreateBindingsHead()
    S.CreateToButtons()
    S.CreateBindingRows()
    S.CreateLists()
    S.CreateTotals()
    S.CreateButtons()
    S.legend = W.Label(frame, "GameFontHighlightSmall")
    S.legend:SetJustifyH("RIGHT")

    frame:SetScript("OnHide", function(self)
        if type(send) == "table" and self:GetParent() ~= send then self:SetParent(send) end
    end)
    -- The lock glow shows only while this window is open (Border.Wanted): redraw it on both.
    local function glow()
        local ok, err = pcall(ns.Border.RefreshAll)
        if not ok then ns.Log.Add("border", "refresh error: %s", tostring(err)) end
    end
    frame:HookScript("OnShow", glow)
    frame:HookScript("OnHide", glow)
    frame:HookScript("OnHide", S.hideTooltip)
    ns.Nav.Attach(frame)
    ns.Nav.OnSelect(S.OnNavSelect)
    -- The controller's shortcut to Send: Up from the top row lands on it (operator, 2026-11-09:
    -- "B: Up jumps"), and Down from the bottom row goes back to the top.
    -- Only from the window's own top and bottom rows (Nav.AtEdge): a button in the middle with
    -- nothing straight above it stays where it is, so a stray Up never lands on Send or Stop.
    ns.Nav.SetWrap(frame, function(dir)
        if not ns.Nav.AtEdge(dir) then return nil end
        if dir == "up" and S.sendButton:IsShown() and S.sendButton:IsEnabled() then return S.sendButton end
        if dir == "down" then return true end
        return nil
    end)
    ns.Log.Add("ui", "mail window created%s", type(send) == "table" and " under SendMailFrame" or "")
    return frame
end

--- Place everything top to bottom for the rows that show; returns the window height.
--- `n` = { routes = , mail = , stay = } shown row counts; `n.stale`, `n.owed`, `n.offer` = that
--- notice shows; `n.to` = recipient lines under "To:" (more than one recipient); `n.toRows` = extra
--- rows the folded last line wraps onto (UI.MoreRecipientsText).
function UI.Layout(n)
    local at = S.at
    local y = -76
    for i, line in ipairs(S.toLines) do
        if i <= (n.to or 0) then
            at(line.name, 50, y + 4)
            at(line.note, -26, y + 2, "TOPRIGHT")
            y = y - 20
        end
    end
    y = y - 14 * (n.toRows or 0)
    if (n.to or 0) > 0 then y = y - 6 end
    y = S.LayoutBanners(y, n)
    if n.routes > 0 then
        at(S.routesHead, 24, y)
        at(S.friendsButton, -24, y + 4, "TOPRIGHT")
        at(S.guildButton, -140, y + 4, "TOPRIGHT")
        y = y - 22
        for i, row in ipairs(S.routeRows) do
            if i <= n.routes then
                at(row.text, 28, y - 5)
                at(row.skip, -102, y, "TOPRIGHT")
                at(row.remove, -20, y, "TOPRIGHT")
                y = y - S.ROUTE_ROW
            end
        end
        y = y - 10
    end

    at(S.mailHead, 22, y)
    at(S.mailHint, 90, y - 2)
    at(S.mailCount, -24, y - 2, "TOPRIGHT")
    at(S.mailPage, -150, y + 4, "TOPRIGHT")
    y = y - 18
    for i, row in ipairs(S.mailRows) do
        row.button:SetPoint("TOP", S.frame, "TOP", 0, y - (i - 1) * S.MAIL_ROW)
    end
    if n.mail == 0 then
        at(S.mailEmpty, 28, y - 4)
        y = y - 22
    end
    y = y - n.mail * S.MAIL_ROW - 8

    if n.stay > 0 then
        at(S.stayHead, 22, y)
        at(S.stayCount, -24, y - 2, "TOPRIGHT")
        at(S.stayPage, -150, y + 4, "TOPRIGHT")
        y = y - 18
        for i, row in ipairs(S.stayRows) do
            row.button:SetPoint("TOP", S.frame, "TOP", 0, y - (i - 1) * S.STAY_ROW)
        end
        y = y - n.stay * S.STAY_ROW - 8
    end

    at(S.totalLine, 24, y - 2)
    at(S.totalNote, 24, y - 24)
    y = y - 50
    at(S.sendButton, 20, y)
    at(S.settingsButton, 220, y)
    at(S.returnButton, 336, y)
    if (n.legend or 0) > 0 then -- the footer under the buttons (Return to sender sits where it was)
        at(S.legend, -24, y - 28, "TOPRIGHT")
        y = y - 14 * n.legend - 10
    end
    return -(y - 22) + 18
end

--- The footer under the buttons: a newer Mailworthy, the Mailworthy mark's key, the controller
--- legend (with "Square pick" while a row has a pick); returns how many lines it takes.
local function fillFooter(ctx)
    local footer, notice = W.Footer(ctx.pad, S.marked, "\n"), ns.Version.Text() -- notice: a newer Mailworthy is out
    if ctx.pad and not ctx.busy and ns.Features.On("padPick") and S.AnyPick() then
        footer = footer .. "    " .. ns.Gamepad.Glyph(ns.Gamepad.FACE_LEFT) .. " pick"
    end
    if notice then footer = footer ~= "" and (notice .. "\n" .. footer) or notice end
    S.legend:SetText(footer)
    return (S.marked and 1 or 0) + (ctx.pad and 1 or 0) + (notice and 1 or 0)
end

--- Re-scan the bags (unless only paging) and redraw.
function UI.Refresh(keepScan)
    if not S.frame then return end
    if not keepScan or not S.result then
        if not ns.Mailer.Busy() then S.result = ns.Bags.Evaluate() end
    end
    local result = S.result
    if not result then return end
    local ctx = {
        pad = ns.MailButton.GamepadUI(),
        bankAlt = ns.Config.BankAlt(),
        isBankAlt = ns.Config.IsBankAltHere(),
        skipped = ns.Bags.BankAltSkipped(),
        busy = ns.Mailer.Busy(),
    }
    S.title:SetText("Mailworthy  " .. (ctx.pad and ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP) or ""))
    S.shownAlt = ctx.bankAlt
    S.marked = false
    local shown = S.FillTo(result, ctx) -- { to = , toRows = }
    S.FillBanners(result, ctx, shown) -- stale, owed, offer
    shown.routes = S.FillBindings()
    shown.mail, shown.stay = S.FillLists(result, ctx)
    local need = S.FillTotals(result, ctx)
    S.FillSend(result, ctx, need)
    S.FillReturn(result, ctx)
    shown.legend = fillFooter(ctx)
    S.frame:SetHeight(UI.Layout(shown))
    ns.Nav.Revalidate()
    S.refreshTooltip()
end

--- Beside the mail window, as a child of the showing tab; away from a mailbox, centred.
function UI.Show(tab)
    if not S.frame then UI.Create() end
    local frame = S.frame
    local send, inbox, mail = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame"), rawget(_G, "MailFrame")
    local parent = (tab == "inbox") and inbox or send
    frame:ClearAllPoints()
    if type(parent) == "table" and type(mail) == "table" then
        if frame:GetParent() ~= parent then frame:SetParent(parent) end
        frame:SetPoint("TOPLEFT", mail, "TOPRIGHT", 8, 0)
    else
        frame:SetParent(UIParent)
        frame:SetPoint("CENTER")
    end
    S.pages.mail, S.pages.stay = 1, 1
    UI.Refresh()
    frame:Show()
    ns.Log.Add("ui", "mail window shown (%s tab): %d to mail, %d staying", tostring(tab), #S.result.mail, #S.result.keep)
end

function UI.Toggle(tab)
    -- IsVisible, not IsShown: opened on one tab and hidden with it, the window keeps its shown
    -- flag, and a press on the other tab's button must show it there, not "hide" it.
    if S.frame and S.frame:IsVisible() then
        S.frame:Hide()
    else
        UI.Show(tab)
    end
end

local function refreshIfShown()
    if S.frame and S.frame:IsShown() then UI.Refresh() end
end
UI.RefreshIfShown = refreshIfShown

-- Redraw what shows from the scan on screen (no new scan, so the list the player sees doesn't
-- change under them).
local function redrawIfShown()
    if S.frame and S.frame:IsShown() and not ns.Mailer.Busy() then UI.Refresh(true) end
end

ns.On("PLAYER_LOGIN", function()
    UI.Create()
    if ns.Features.On("tooltipLines") then UI.InstallTooltip() end
    ns.Locks.OnChanged(refreshIfShown)
    ns.Pins.OnChanged(refreshIfShown)
    -- While sending, redraw the status only; once it's done or stopped, re-scan: the bag
    -- update for the sent items may have come mid-send, when it was skipped (v0.4.0).
    ns.Mailer.OnChanged(function()
        if S.frame and S.frame:IsShown() then UI.Refresh(ns.Mailer.Busy()) end
        local ok, err = pcall(S.PrintReceipt)
        if not ok then ns.Log.Add("ui", "receipt error: %s", tostring(err)) end
    end)
    local settings = ns.SettingsUI.Frame()
    if settings then settings:HookScript("OnHide", refreshIfShown) end
    local friends = ns.RoutesUI.Frame()
    if friends then friends:HookScript("OnHide", refreshIfShown) end
end)
-- A new Mailworthy user can be a name on screen (Comms.Mark).
ns.Comms.OnMarksChanged(redrawIfShown)
-- A newer Mailworthy heard of: its line in the footer.
ns.Version.OnChanged(redrawIfShown)
ns.On("BAG_UPDATE_DELAYED", function()
    if not ns.Mailer.Busy() then refreshIfShown() end
end)
-- Money came or went: the postage check follows (from the scan on screen).
ns.On("PLAYER_MONEY", redrawIfShown)
