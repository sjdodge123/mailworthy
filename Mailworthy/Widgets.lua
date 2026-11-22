-- Shared building blocks for Mailworthy's windows. Frames are created at login
-- on UIParent and parented afterwards: creating frames while a gamepad panel is
-- open trips SmartNavigation's CreateFrame hook in our context. No
-- smart-navigation keys are set on anything (controller: Nav + PadKey).
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

Widgets.BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

--- A dialog-style window with a close button; Escape closes it. Hidden until shown.
function Widgets.Window(name, width, height, parent)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate")
    if not ok then f = CreateFrame("Frame", name, UIParent) end
    if parent then f:SetParent(parent) end
    f:SetSize(width, height)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop(Widgets.BACKDROP)
        f:SetBackdropColor(0.05, 0.05, 0.07, 1) -- opaque: a window on top never shows the text below
    end
    f:SetClampedToScreen(true)
    f.CloseButton = CreateFrame("Button", name .. "CloseButton", f, "UIPanelCloseButton")
    f.CloseButton:SetPoint("TOPRIGHT", -6, -6)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    f:Hide()
    return f
end

--- Pure: which side of an opener a window of `width` fits on, all in one unit:
--- "right", "left" (both with `gap`), or nil when neither (the caller lays it over the opener).
function Widgets.Side(openerLeft, openerRight, width, screenWidth, gap)
    gap = gap or 8
    if not (openerLeft and openerRight and width and screenWidth) then return nil end
    if openerRight + gap + width <= screenWidth then return "right" end
    if openerLeft - gap - width >= 0 then return "left" end
    return nil
end

--- Whether `region` hangs, anchor by anchor, on `f` (a few steps deep at most).
local function dependsOn(region, f, depth)
    if not region or depth > 8 or type(region.GetNumPoints) ~= "function" then return false end
    for i = 1, region:GetNumPoints() or 0 do
        local _, rel = region:GetPoint(i)
        if rel == f or (rel and rel ~= region and dependsOn(rel, f, depth + 1)) then return true end
    end
    return false
end

--- `opener` was placed beside `f` before (Settings > Mail routing..., then the routing window's
--- Change... back to Settings; Codex review, 2026-11-22): pin `opener` where it is on screen first,
--- or anchoring `f` to it would be circular, which the game refuses.
function Widgets.Unanchor(opener, f)
    if not dependsOn(opener, f, 0) then return false end
    local left, top = opener:GetLeft(), opener:GetTop()
    opener:ClearAllPoints()
    if left and top then
        opener:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
        opener:SetPoint("CENTER")
    end
    return true
end

--- Place a window that another Mailworthy window opened (operator, 2026-11-06: popups
--- "overlap the existing menus and you cant read the new popup easily"): beside the opener
--- when it fits on screen, else squarely over it (opaque, so the opener's text never shows
--- through); centred without an opener (/mw, the minimap button). Clamped to the screen.
function Widgets.PlaceBeside(f, opener)
    f:ClearAllPoints()
    if opener and opener ~= f then Widgets.Unanchor(opener, f) end
    local side
    if opener and opener ~= f and opener:IsVisible() then
        local left, right = opener:GetLeft(), opener:GetRight()
        local fScale, oScale = f:GetEffectiveScale(), opener:GetEffectiveScale()
        local screen = UIParent:GetRight()
        local uiScale = UIParent:GetEffectiveScale()
        if left and right and screen and fScale and oScale and uiScale and fScale > 0 then
            local k = oScale / fScale
            side = Widgets.Side(left * k, right * k, f:GetWidth(), screen * uiScale / fScale, 8) or "over"
        else
            side = "over"
        end
    end
    if side == "right" then
        f:SetPoint("TOPLEFT", opener, "TOPRIGHT", 8, 0)
    elseif side == "left" then
        f:SetPoint("TOPRIGHT", opener, "TOPLEFT", -8, 0)
    elseif side == "over" then
        f:SetPoint("TOPLEFT", opener, "TOPLEFT", 0, 0)
    else
        f:SetPoint("CENTER")
    end
    return side or "center"
end

Widgets.PAD = 16 -- the button art's edges: text stays inside them

local FONTS = {
    { normal = "GameFontNormal", highlight = "GameFontHighlight", disabled = "GameFontDisable" },
    { normal = "GameFontNormalSmall", highlight = "GameFontHighlightSmall", disabled = "GameFontDisableSmall" },
}

local function setFonts(b, set)
    for _, part in ipairs({ { "SetNormalFontObject", set.normal }, { "SetHighlightFontObject", set.highlight },
        { "SetDisabledFontObject", set.disabled } }) do
        local font = rawget(_G, part[2])
        if font and type(b[part[1]]) == "function" then pcall(b[part[1]], b, font) end
    end
end

local function textWidth(fs)
    local measure = fs.GetUnboundedStringWidth or fs.GetStringWidth
    local ok, w = pcall(measure, fs)
    return ok and tonumber(w) or nil
end

--- Pure: which font a label of `normalWidth` takes on a button of `width`: 1 (normal) when it
--- fits, else 2 (small); the second return is true when even the small one doesn't (the
--- label is then cut with "..." at the button's edge). `smallWidth` is its width in the small font.
function Widgets.FitFont(width, normalWidth, smallWidth)
    local room = width - Widgets.PAD
    if not normalWidth or normalWidth <= room then return 1, false end
    return 2, (smallWidth or normalWidth) > room
end

--- Keep a button's label inside its border (2026-11-07: "button text commonly runs over the
--- button borders"): the normal font when it fits, the small one when it doesn't, and past that
--- the label stops at the edge. Runs after every SetText on our own buttons.
function Widgets.Fit(b)
    local fs = type(b.GetFontString) == "function" and b:GetFontString() or nil
    local width = type(b.GetWidth) == "function" and tonumber((b:GetWidth())) or nil
    if not fs or not width or width <= 0 then return end
    setFonts(b, FONTS[1])
    if type(fs.SetWidth) == "function" then pcall(fs.SetWidth, fs, 0) end
    local normal = textWidth(fs)
    local font = Widgets.FitFont(width, normal)
    if font == 1 then return end
    setFonts(b, FONTS[2])
    local _, cut = Widgets.FitFont(width, normal, textWidth(fs))
    if cut and type(fs.SetWidth) == "function" then pcall(fs.SetWidth, fs, width - Widgets.PAD) end
end

-- Toggled-on look (operator, 2026-11-08: "make sure this button has a highlight when toggled
-- on. same with any other toggled button"): a green fill inside the button's border, under its
-- text, kept in our own table. Made with the button (at login), so nothing is created later.
Widgets.TOGGLED_COLOR = { 0.2, 0.8, 0.35, 0.45 }
local toggles = setmetatable({}, { __mode = "k" }) -- button -> { glow = texture, on = bool }

function Widgets.Button(parent, text, width, onClick, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, b, "SetText", function(self) Widgets.Fit(self) end)
    end
    Widgets.Fit(b)
    local glow = b:CreateTexture(nil, "BORDER")
    glow:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    local c = Widgets.TOGGLED_COLOR
    glow:SetColorTexture(c[1], c[2], c[3], c[4])
    glow:Hide()
    toggles[b] = { glow = glow, on = false }
    return b
end

--- Show a toggle button (one of ours, made by Widgets.Button) as on or off.
function Widgets.SetToggled(b, on)
    local t = toggles[b]
    if not t then return end
    t.on = on == true
    if t.on then t.glow:Show() else t.glow:Hide() end
end

--- Is this button shown as toggled on? (specs, /mw report)
function Widgets.IsToggled(b)
    local t = toggles[b]
    return t ~= nil and t.on and t.glow:IsShown() == true
end

function Widgets.Label(parent, font)
    return parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
end

--- The controller legend line: "(Cross) press   (Circle) close   D-pad move".
function Widgets.Legend(extra)
    local text = string.format("%s press    %s close    D-pad move", ns.Gamepad.Glyph(ns.Gamepad.FACE_BOTTOM),
        ns.Gamepad.Glyph(ns.Gamepad.FACE_RIGHT))
    return extra and (text .. "    " .. extra) or text
end

--- A window's footer: the Mailworthy mark's key while a marked name shows (Comms.Mark: what the
--- icon means, readable without hovering) and the controller legend with a controller, joined by
--- `sep` (default: spaces; the mailbox window stacks them).
function Widgets.Footer(pad, marked, sep)
    local parts = {}
    if marked then parts[#parts + 1] = ns.Comms.MARK_KEY end
    if pad then parts[#parts + 1] = Widgets.Legend() end
    return table.concat(parts, sep or "    ")
end

--- The "<" of a two-way pager (QoL pass, 2026-11-09): a small button left of a list's page button
--- (`nextButton`, whose text is "2/5  >"), shown and hidden with it. Create it at login.
function Widgets.PagerBack(parent, nextButton, name, onClick)
    local b = Widgets.Button(parent, "<", 26, onClick, name)
    b:SetPoint("RIGHT", nextButton, "LEFT", -4, 0)
    b:Hide()
    nextButton:HookScript("OnShow", function() b:Show() end)
    nextButton:HookScript("OnHide", function() b:Hide() end)
    return b
end

-- Window skeleton (UX review A4, 2026-11-15) ------------------------------------------------
-- Every Mailworthy window had the same lines: Widgets.Window on FULLSCREEN_DIALOG, a title and a
-- sub line, a local at(), the controller legend at the bottom, Show(opener) (placed beside the
-- opener, refreshed, raised, logged), RefreshIfShown and the end of every Refresh (footer, height,
-- Nav.Revalidate). Widgets.Shell is that once; Widgets.ListWindow adds a paged list of rows.

--- A window: `o` = { name, width, height, title, sub (text, optional), strata (default
--- FULLSCREEN_DIALOG), log (what Show logs), refresh = fn(win) }. Returns `win`: win.frame, win.title,
--- win.sub, win.legend, win.at(widget, x, y, point), win.Done(name, text), win.Finish(bottomY,
--- marked), win.Show(opener, prepare), win.Refresh(), win.RefreshIfShown(). Create it at login.
function Widgets.Shell(o)
    local win = {}
    local frame = Widgets.Window(o.name, o.width, o.height or 300)
    frame:SetFrameStrata(o.strata or "FULLSCREEN_DIALOG")
    frame:SetPoint("CENTER")
    win.frame, win.width = frame, o.width
    win.title = Widgets.Label(frame, "GameFontNormalLarge")
    win.title:SetPoint("TOP", 0, -18)
    win.title:SetText(o.title or "")
    if o.sub then
        win.sub = Widgets.Label(frame, "GameFontHighlightSmall")
        win.sub:SetPoint("TOPLEFT", 28, -44)
        win.sub:SetWidth(o.width - 56)
        win.sub:SetJustifyH("LEFT")
        win.sub:SetText(o.sub)
    end
    win.legend = Widgets.Label(frame, "GameFontHighlightSmall")
    win.legend:SetPoint("BOTTOM", 0, 14)
    function win.at(widget, x, y, point)
        widget:ClearAllPoints()
        widget:SetPoint(point or "TOPLEFT", frame, point or "TOPLEFT", x, y)
    end
    --- The window's close button: "Done" in every window (UX review U6).
    function win.Done(name, text)
        win.done = Widgets.Button(frame, text or "Done", 100, function() frame:Hide() end, name)
        return win.done
    end
    --- The end of a Refresh: the window ends under the row of buttons at `bottomY`, the footer says
    --- what the Mailworthy mark means while one shows (`marked`), and the highlight moves on if its
    --- button went away.
    function win.Finish(bottomY, marked)
        frame:SetHeight(-bottomY + 22 + 40)
        win.legend:SetText(Widgets.Footer(ns.MailButton.GamepadUI(), marked == true))
        ns.Nav.Revalidate()
    end
    function win.Refresh()
        if o.refresh then o.refresh(win) end
    end
    function win.RefreshIfShown()
        if frame:IsShown() then win.Refresh() end
    end
    --- `opener`: the Mailworthy window whose button opened it (placed beside that), or nil (centred).
    --- `prepare(wasShown)` resets what a fresh open resets (page 1, ...) before the refresh.
    function win.Show(opener, prepare)
        local wasShown = frame:IsShown()
        Widgets.PlaceBeside(frame, opener)
        if prepare then prepare(wasShown) end
        win.Refresh()
        frame:Show()
        frame:Raise()
        -- Already open (no OnShow): the controller still moves to it, over the window that opened it.
        if wasShown then ns.Nav.Raise(frame) end
        if o.log then ns.Log.Add("ui", "%s shown", o.log) end
    end
    ns.Nav.Attach(frame)
    if o.log then ns.Log.Add("ui", "%s created", o.log) end
    return win
end

--- A two-way pager: `name` is the "%d/%d  >" button, `name .. "Back"` the "<" left of it (shown and
--- hidden with it). Each press moves a page, wrapping at both ends, then calls `onChange()`.
--- pager.Clamp(count, perPage) -> page, pages, first index - 1; pager.Update() shows it when there
--- is more than one page (and says so).
function Widgets.Pager(parent, name, onChange, width)
    local p = { page = 1, pages = 1 }
    p.next = Widgets.Button(parent, "", width or 70, function()
        p.page = p.page + 1
        onChange()
    end, name)
    p.back = Widgets.PagerBack(parent, p.next, name .. "Back", function()
        p.page = p.page - 1
        onChange()
    end)
    function p.Clamp(count, perPage)
        p.pages = math.max(1, math.ceil((count or 0) / perPage))
        if p.page > p.pages then p.page = 1 end
        if p.page < 1 then p.page = p.pages end -- back from the first page: the last
        return p.page, p.pages, (p.page - 1) * perPage
    end
    function p.Update()
        if p.pages > 1 then
            p.next:SetText(string.format("%d/%d  >", p.page, p.pages))
            p.next:Show()
        else
            p.next:Hide()
        end
        return p.pages > 1
    end
    return p
end

--- A window of rows with a pager, an empty-state line and a bottom row of buttons (Locked items,
--- Pinned items, Mail ledger). `o` takes Shell's fields and: rows (per page), rowHeight, top (the
--- first row's y), makeRow(win, i) -> row (row.widgets: what the row shows), fillRow(row, entry, y),
--- list() -> entries, emptyText, pagerName, doneName, below(win, y) -> y of the bottom row (lines
--- under the list; default y - 10), left (buttons on the bottom row from the left), marked() ->
--- whether a name on screen carries the Mailworthy mark, onPage(win) (a page turn, before the redraw).
--- The pager sits on the bottom row, left of
--- Done (the list's last row, never the heading line: UX review U5).
--- Returns the Shell's `win` with win.rows, win.pager, win.empty, win.entries.
function Widgets.ListWindow(o)
    local win
    local shell = {}
    for k, v in pairs(o) do shell[k] = v end
    shell.refresh = function()
        if o.before then o.before(win) end
        local entries = o.list()
        win.entries = entries
        local _, _, first = win.pager.Clamp(#entries, o.rows)
        local shown = 0
        for i, row in ipairs(win.rows) do
            for _, w in ipairs(row.widgets) do w:Hide() end
            local e = entries[first + i]
            row.entry = e
            if e then
                o.fillRow(row, e, o.top - shown * o.rowHeight, i)
                for _, w in ipairs(row.widgets) do w:Show() end
                shown = shown + 1
            end
        end
        local y = o.top - shown * o.rowHeight
        if #entries == 0 then
            win.at(win.empty, 28, y - 4)
            win.empty:Show()
            y = y - 26
        else
            win.empty:Hide()
        end
        local bottom = o.below and o.below(win, y) or (y - 10)
        local x = 24
        for _, b in ipairs(o.left or {}) do
            win.at(b, x, bottom)
            x = x + (tonumber((b:GetWidth())) or 100) + 8
        end
        if win.pager.Update() then win.at(win.pager.next, -24 - 100 - 8, bottom, "TOPRIGHT") end
        win.at(win.done, -24, bottom, "TOPRIGHT")
        win.Finish(bottom, o.marked and o.marked() or false)
    end
    win = Widgets.Shell(shell)
    win.rows = {}
    for i = 1, o.rows do
        local row = o.makeRow(win, i)
        row.widgets = row.widgets or {}
        for _, w in ipairs(row.widgets) do w:Hide() end
        win.rows[i] = row
    end
    win.empty = Widgets.Label(win.frame, "GameFontHighlightSmall")
    win.empty:SetWidth(o.width - 56)
    win.empty:SetJustifyH("LEFT")
    win.empty:SetText(o.emptyText or "")
    win.empty:Hide()
    win.pager = Widgets.Pager(win.frame, o.pagerName, function()
        if o.onPage then o.onPage(win) end -- what a page turn resets (the ledger's armed Mark paid)
        win.Refresh()
    end)
    win.pager.next:Hide()
    win.Done(o.doneName)
    return win
end

--- One window, several views (UX review A4): `spec` = { view = { widget, ... }, ... }; a widget may
--- be in several views. views.Show(name) hides every widget of the other views and the `pooled`
--- ones (rows the view's own fill code shows), then shows this view's.
--- views.Buttons(name) -> the sorted global names of the view's buttons (specs).
function Widgets.Views(spec, pooled)
    local v = { spec = spec or {}, pooled = pooled or {} }
    --- Put `widget` in the view `name` (or in each of a list of views); returns the widget.
    function v.Add(name, widget)
        for _, n in ipairs(type(name) == "table" and name or { name }) do
            v.spec[n] = v.spec[n] or {}
            table.insert(v.spec[n], widget)
        end
        return widget
    end
    function v.Show(name)
        v.current = name
        local keep = {}
        for _, w in ipairs(v.spec[name] or {}) do keep[w] = true end
        for other, list in pairs(v.spec) do
            if other ~= name then
                for _, w in ipairs(list) do
                    if not keep[w] then w:Hide() end
                end
            end
        end
        for _, w in ipairs(v.pooled) do w:Hide() end
        for _, w in ipairs(v.spec[name] or {}) do w:Show() end
    end
    function v.Current() return v.current end
    function v.Buttons(name)
        local names = {}
        for _, w in ipairs(v.spec[name] or {}) do
            if type(w.IsObjectType) == "function" and w:IsObjectType("Button") and w:GetName() then
                names[#names + 1] = w:GetName()
            end
        end
        table.sort(names)
        return names
    end
    return v
end

-- Explanations (UX review U8) -----------------------------------------------------------------
-- A short label on the button, the full explanation in its tooltip: on mouse-over, and for the
-- controller while Mailworthy's highlight is on it (Nav.OnSelect), as the mail window's rows do.
-- Our own buttons and GameTooltip only.
local tips = setmetatable({}, { __mode = "k" }) -- button -> { title, text } (strings or fn(button))

local function tipLines(b)
    local t = tips[b]
    local title = type(t.title) == "function" and t.title(b) or t.title or b:GetText()
    local text = type(t.text) == "function" and t.text(b) or t.text
    return title, text
end

--- Show a button's explanation (mouse-over, or the controller's highlight on it).
function Widgets.ShowTip(b)
    local tip = rawget(_G, "GameTooltip")
    if not tips[b] or type(tip) ~= "table" then return end
    local title, text = tipLines(b)
    tip:SetOwner(b, "ANCHOR_RIGHT")
    tip:SetText(title or "")
    if text and text ~= "" then tip:AddLine(text, 1, 1, 1, true) end
    tip:Show()
end

local function hideTip(b)
    local tip = rawget(_G, "GameTooltip")
    if type(tip) == "table" and tip:GetOwner() == b then tip:Hide() end
end

--- Give one of our buttons an explanation: `title` (default: its label) and `text`, each a string
--- or fn(button) -> string, read each time it shows.
function Widgets.Tip(b, title, text)
    tips[b] = { title = title, text = text }
    b:HookScript("OnEnter", function(self) Widgets.ShowTip(self) end)
    b:HookScript("OnLeave", function(self) hideTip(self) end)
    return b
end

--- The explanation a button shows (specs, /mw report), or nil.
function Widgets.TipText(b)
    if not tips[b] then return nil end
    local _, text = tipLines(b)
    return text
end

local function onNavSelect(button)
    if Widgets.DisarmAll then Widgets.DisarmAll(button) end
    local tip = rawget(_G, "GameTooltip")
    if button and tips[button] then
        Widgets.ShowTip(button)
    elseif type(tip) == "table" and tips[tip:GetOwner() or false] then
        tip:Hide()
    end
end

local listening = false
ns.On("PLAYER_LOGIN", function()
    if listening or not ns.Nav then return end
    listening = true
    ns.Nav.OnSelect(onNavSelect)
end)

-- Two presses (UX review U7) -------------------------------------------------------------------
-- Remove, Forget and Publish took one press; Mark paid took two. One helper for the two-press
-- buttons: the first press says `confirmText` for 3 seconds, a second press within them acts. The
-- highlight moving to another button (Nav.Select), the window closing or the time running out
-- cancels it. The mail window uses the same helper.
Widgets.CONFIRM_SECONDS = 3
local confirms = setmetatable({}, { __mode = "k" }) -- button -> { text, confirm, armedAt, token }

--- Back to the first press's label (the row now shows another thing, the window closed, ...).
function Widgets.Disarm(b)
    local c = confirms[b]
    if not c or not c.armedAt then return end
    c.armedAt = nil
    b:SetText(c.text)
end

--- Disarm every two-press button but `except` (the highlight moved to another button).
function Widgets.DisarmAll(except)
    for b in pairs(confirms) do
        if b ~= except then Widgets.Disarm(b) end
    end
end

--- Is the button waiting for its second press?
function Widgets.Armed(b)
    local c = confirms[b]
    return c ~= nil and c.armedAt ~= nil
end

--- Change a two-press button's label (shown at once unless it is waiting for its second press).
function Widgets.SetConfirmText(b, text)
    local c = confirms[b]
    if not c then return b:SetText(text) end
    c.text = text
    if not c.armedAt then b:SetText(text) end
end

--- A button that acts on its second press: `onConfirm(button)`; `onArm(button)` (optional) runs on
--- the first (a hint line). Create it at login.
function Widgets.ConfirmButton(parent, text, confirmText, width, onConfirm, name, onArm)
    local c = { text = text, confirm = confirmText or "Sure?", token = 0 }
    local b
    b = Widgets.Button(parent, text, width, function(self)
        local now = tonumber(GetTime and GetTime()) or 0
        if c.armedAt and now - c.armedAt <= Widgets.CONFIRM_SECONDS then
            Widgets.Disarm(self)
            return onConfirm(self)
        end
        c.armedAt, c.token = now, c.token + 1
        local token = c.token
        self:SetText(c.confirm)
        if onArm then onArm(self) end
        ns.Util.After(Widgets.CONFIRM_SECONDS, function()
            if c.token == token then Widgets.Disarm(b) end
        end)
    end, name)
    confirms[b] = c
    if parent and type(parent.HookScript) == "function" then
        parent:HookScript("OnHide", function() Widgets.Disarm(b) end)
    end
    return b
end
