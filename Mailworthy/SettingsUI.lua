-- The settings window (media/simplify-prototype.png, panels 3-5), one task at a time, in views
-- (Widgets.Views; UX review U2, 2026-11-15):
--   "Mailing" (tab): the bank alt on one row with Change..., then what gets mailed: minimum gain,
--     listing length, disenchant value, profession materials, sell what I gather, send by tag
--     (AH / DE / BA / V);
--   "Bags and more" (tab): in your bags (tags, lock glow, pins, item tooltips, pin warning, minimap
--     button) and the windows (locked items, pinned items, bank alt summary, report);
--   "Mail routing..." (a button on the tabs' row, on both tabs; not a tab: operator, 2026-11-22,
--     media/settings-routing-prototype.png, "go with B, move them, call it Mail routing"): the Mail
--     routing window (RoutesUI) on its list: the bindings, the guild's rules, the bank alt, and from
--     there Guild... and Mail ledger... (before, Bags and more had Friends / Guild / Mail ledger, folded
--     into "Friends and guild..." for a solo player);
--   pick view (Change... / Choose...; a bank alt is optional since 2026-11-08): the known
--     characters, "This character is my bank alt" (a main on another WoW account),
--     an optional typed name, Back. Picking saves and returns to the settings.
-- Each view is laid out by rows (no fixed y per button), so the window sizes to its view. Buttons
-- carry short labels; the full explanation is in the button's tooltip, shown to the controller too
-- while the highlight is on it (Widgets.Tip; UX review U8). On shows one way: the green fill and
-- ": on" (U6).
-- Keyboard/mouse: click. Controller: the D-pad moves Mailworthy's own highlight,
-- Cross presses, Circle closes (PadKey "settings" set, Nav); every setting is a
-- button, so nothing needs typing. The name box is an optional fallback the player
-- clicks into (the game never moves focus: no SetFocus).
--
-- Opened with /mw, the minimap button, or the Settings button in the Mailworthy
-- window at the mailbox. Not registered in Blizzard's options panel: that hands
-- our frame and category tables to a panel the controller UI navigates, the same
-- pattern that made the More-menu entry taint gamepad input (alpha2).
local _, ns = ...

local UI = {}
ns.SettingsUI = UI

UI.MAX_CHOICES = 6
UI.TABS = { "mailing", "more" }
local WIDTH, ROW, VERSION_ROW, TOP = 420, 26, 20, -74
local LEFT, RIGHT, HALF = 24, 214, 182 -- the two columns of half-width buttons
local THIRD = 120 -- the tabs' row: Mailing, Bags and more, Mail routing...

local win, frame, views, nameBox, nameHint, current, emptyHint, pricesLine, versionLine, changeButton
local choiceRows = {}
local sendButtons = {} -- verdict tag ("ah", "de", "b", "v") -> its Send switch
local amountLabel, pctLabel, disenchantButton, minimapButton, tagsButton, glowButton, matsButton, hereButton
local gatherButton, locksButton, pinButton, tooltipButton, pinWarningButton, pinnedButton, suggestButton
local summaryButton, reportButton, routingButton
local tabButtons = {}
local durationButtons = {}
local typedLabel, useNameButton, backButton, doneButton
local rows = { mailing = {}, more = {} } -- each view's rows, top to bottom (layout)
local view = "main"
local tab = "mailing"
local pendingUnknown -- a typed name Mailworthy hasn't seen, waiting for a second press

local W = ns.Widgets
local money = function(c) return ns.Valuation.Money(c) end

function UI.Frame() return frame end
--- The footer (the Mailworthy mark's key, the controller legend), for specs.
function UI.Footer() return win and win.legend:GetText() end
--- The "a newer Mailworthy is out" line ("" when there's none), for specs.
function UI.VersionLine() return versionLine and versionLine:GetText() end
--- "main" (the settings) or "pick" (choosing the bank alt).
function UI.View() return view end
--- The settings' tab: "mailing" or "more" (Bags and more).
function UI.Tab() return tab end
--- The buttons each view shows (Widgets.Views: "mailing", "more", "pick"), for specs.
function UI.Views() return views end

local function at(widget, x, y, point) win.at(widget, x, y, point) end

local function setHint(text) nameHint:SetText(text or "") end

local function setView(v)
    view = v
    pendingUnknown = nil
    if nameHint then setHint("") end
end

--- Show a tab ("mailing" / "more") of the settings.
function UI.SetTab(t)
    if t ~= "mailing" and t ~= "more" then return end
    tab = t
    setView("main")
    UI.Refresh()
end

function UI.UseTyped()
    local text = ns.Config.Clean(nameBox:GetText())
    if not text then return setHint("Type a name first, or pick one above.") end
    if text:lower() == tostring(ns.PlayerName()):lower() then
        return setHint("That's this character. Pick the character that should receive the mail, or, if this "
            .. "character is the one receiving it, press \"This character is my bank alt\".")
    end
    local name = ns.Config.Complete(text, ns.Config.Choices())
    if not name and pendingUnknown ~= text:lower() then
        pendingUnknown = text:lower()
        return setHint("|cffff8040Mailworthy hasn't seen " .. text .. " on this realm and faction. "
            .. "Check the spelling, then press Use name again to save it.|r")
    end
    UI.Choose(name or text)
    nameBox:SetText("")
    setHint("")
end

function UI.Choose(name)
    pendingUnknown = nil
    local saved = ns.Config.SetBankAlt(name)
    if saved then
        ns.Print("Bank alt: " .. saved .. ". Mail goes only to this character.")
        setView("main")
    end
    UI.Refresh()
    if saved and ns.MailWindow then ns.MailWindow.RefreshIfShown() end -- the list now has somewhere to go
    if ns.RoutesUI then ns.RoutesUI.RefreshIfShown() end -- its bank alt line
end

--- "This character is my bank alt": the character receiving the mail says so itself
--- (the only way when it plays on a second WoW account, whose saved settings the main
--- never sees). Pressed again, it clears the bank alt.
function UI.ToggleHere()
    pendingUnknown = nil
    if ns.Config.IsBankAltHere() then
        ns.Config.ClearBankAlt()
        ns.Print("No bank alt set on this realm and faction any more.")
    else
        local saved = ns.Config.SetBankAltHere()
        if saved then
            setView("main")
            ns.Print("Bank alt: " .. saved .. " (this character). Your bags now carry the AH / B / DE / V tags; "
                .. "on your main, type this name in Mailworthy's settings if it hasn't been picked there.")
        end
    end
    if ns.BankAlt then ns.BankAlt.Redraw() end
    UI.Refresh()
    if ns.RoutesUI then ns.RoutesUI.RefreshIfShown() end -- its bank alt line
end

-- Layout by rows ---------------------------------------------------------------------------
-- A row: { h = height, items = { { widget, x, dy, point }, ... }, when = fn() (shown only while it
-- says so), grid = fn() -> buttons (two per row, the visible ones only) }. Placing a view walks its
-- rows from the top; a row added or hidden moves everything under it.

local function row(viewName, h, items, when)
    rows[viewName][#rows[viewName] + 1] = { h = h, items = items, when = when }
end

local function place(viewName, y)
    for _, r in ipairs(rows[viewName]) do
        if r.grid then
            local list = r.grid()
            for i, b in ipairs(list) do
                at(b, i % 2 == 1 and LEFT or RIGHT, y)
                if i % 2 == 0 or i == #list then y = y - ROW end
            end
        elseif not r.when or r.when() then
            for _, it in ipairs(r.items) do at(it[1], it[2], y + (it[3] or 0), it[4]) end
            y = y - r.h
        else
            for _, it in ipairs(r.items) do it[1]:Hide() end
        end
    end
    return y
end

local function heading(viewName, text)
    local h = views.Add(viewName, W.Label(frame, "GameFontNormal"))
    h:SetText(text)
    row(viewName, 22, { { h, 20, 0 } })
    return h
end

-- A setting changed: this window, and the mail list beside it, which it decides (QoL pass,
-- 2026-11-09; before, the list only followed when Settings closed).
local function changed()
    UI.Refresh()
    if ns.MailWindow then ns.MailWindow.RefreshIfShown() end
end

local function button(viewName, text, width, name, onClick, tipText)
    local b = views.Add(viewName, W.Button(frame, text, width, onClick, "MailworthySettings" .. name))
    if tipText then W.Tip(b, nil, tipText) end
    return b
end

local function toggle(viewName, width, name, onClick, tipText)
    return button(viewName, "", width, name, function()
        onClick()
        changed()
    end, tipText)
end

-- Tabs: Mailing / Bags and more, then Mail routing... -----------------------------------------

local function createTabs()
    for i, t in ipairs(UI.TABS) do
        local b = button({ "mailing", "more" }, t == "mailing" and "Mailing" or "Bags and more", THIRD,
            t == "mailing" and "TabMailing" or "TabMore", function() UI.SetTab(t) end,
            t == "mailing" and "The bank alt and what gets mailed." or "Tags, pins, tooltips and Mailworthy's other windows.")
        at(b, LEFT + (i - 1) * (THIRD + 6), -44)
        tabButtons[t] = b
    end
    -- Not a tab: it opens the Mail routing window beside the settings, like Locked items... does.
    routingButton = button({ "mailing", "more" }, "Mail routing...", THIRD, "Routing", function()
        ns.RoutesUI.Show(frame)
    end, "Where your mail goes: your bindings (Add a binding...), the guild's rules and the bank alt.")
    at(routingButton, LEFT + 2 * (THIRD + 6), -44)
end

-- Mailing: the bank alt on one row, what gets mailed ----------------------------------------

local function stepper(key, name, tipText)
    local text = views.Add("mailing", W.Label(frame, "GameFontHighlight"))
    local minus = button("mailing", "-", 32, name .. "Down", function()
        ns.Config.Step(key, -1)
        changed()
    end, tipText)
    local plus = button("mailing", "+", 32, name .. "Up", function()
        ns.Config.Step(key, 1)
        changed()
    end, tipText)
    row("mailing", 28, { { text, 28, -4 }, { minus, 302, 0 }, { plus, 340, 0 } })
    return text
end

local function createMailing()
    local label = views.Add("mailing", W.Label(frame, "GameFontNormal"))
    label:SetText("Bank alt:")
    current = views.Add("mailing", W.Label(frame, "GameFontHighlight"))
    current:SetWidth(200)
    current:SetJustifyH("LEFT")
    changeButton = button("mailing", "Change...", 96, "Change", function()
        setView("pick")
        UI.Refresh()
    end, "Pick the character that receives the mail (same realm and faction), or say this character is the bank alt.")
    row("mailing", 30, { { label, 20, -4 }, { current, 92, -4 }, { changeButton, -24, 0, "TOPRIGHT" } })
    heading("mailing", "What gets mailed")
    amountLabel = stepper("minGain", "Amount",
        "Mail an item only when the auction house brings at least this much more than a vendor pays.")
    pctLabel = stepper("minGainPct", "Percent", "... and at least this much more than its vendor price, in percent.")
    local listing = views.Add("mailing", W.Label(frame, "GameFontHighlight"))
    listing:SetText("Auction listing")
    local items = { { listing, 28, -4 } }
    for i, hours in ipairs(ns.Valuation.DURATION_HOURS) do
        local b = button("mailing", hours .. "h", 56, "Duration" .. i, function()
            ns.Config.Set("duration", i)
            changed()
        end, "The listing length Mailworthy counts the auction deposit for.")
        items[#items + 1] = { b, 196 + (i - 1) * 60, 0 }
        durationButtons[i] = b
    end
    row("mailing", 30, items)
    disenchantButton = toggle("mailing", HALF, "Disenchant", function()
        ns.Config.Set("disenchant", not ns.Config.Get("disenchant"))
    end, function() return UI.DisenchantTip(ns.Config.Get("disenchant"), ns.Prices.DisenchantAddon()) end)
    -- Full width: "on my bank alt (BA)" is the state's name (the critical path reads it).
    matsButton = toggle("mailing", 372, "Mats", function()
        -- Three states: on (kept here) -> off (valued like anything else) -> on my bank alt -> on.
        local keepHere, toAlt = ns.Config.Get("keepProfessionMats"), ns.Config.Get("matsToBankAlt")
        if keepHere and not toAlt then
            ns.Config.Set("keepProfessionMats", false)
        elseif not keepHere then
            ns.Config.Set("keepProfessionMats", true)
            ns.Config.Set("matsToBankAlt", true)
        else
            ns.Config.Set("matsToBankAlt", false)
        end
        if ns.BankAlt then ns.BankAlt.Redraw() end
    end, function() return UI.MatsTip(ns.Config.Values(), ns.Bags.CraftingText(ns.Characters.Professions())) end)
    row("mailing", ROW, { { matsButton, LEFT, 0 } })
    gatherButton = toggle("mailing", HALF, "Gather", function()
        ns.Config.Set("sellGathered", not ns.Config.Get("sellGathered"))
        if ns.BankAlt then ns.BankAlt.Redraw() end
    end, function()
        local gathering = {}
        for _, p in ipairs(ns.Valuation.GatheringProfessions(ns.Characters.Professions())) do gathering[#gathering + 1] = p.name end
        return string.format("Sell what I gather: %s (%s). On: what this character's gathering professions bring in "
            .. "is mailed to be sold, not kept for its crafting professions.", ns.Config.Get("sellGathered") and "on" or "off",
            #gathering > 0 and table.concat(gathering, ", ") or "no gathering profession here")
    end)
    row("mailing", ROW + 4, { { disenchantButton, LEFT, 0 }, { gatherButton, RIGHT, 0 } })
    -- What Send takes of the bank alt's share, by verdict (Bags.ApplySendSwitches): one switch per tag.
    local send = views.Add("mailing", W.Label(frame, "GameFontHighlight"))
    send:SetText("Send by tag")
    items = { { send, 28, -4 } }
    for i, tag in ipairs(ns.Valuation.SEND_ORDER) do
        local key = ns.Valuation.SEND[tag]
        local b = toggle("mailing", 64, "Send" .. ns.Valuation.SEND_LABEL[tag], function()
            ns.Config.Set(key, not ns.Config.Get(key))
        end, string.format("Send mails the items tagged %s (%s) to your bank alt while this is on.",
            ns.Valuation.SEND_TAG[tag], ns.Valuation.SEND_LABEL[tag]:lower()))
        items[#items + 1] = { b, 124 + (i - 1) * 68, 0 }
        sendButtons[tag] = b
    end
    row("mailing", 30, items)
end

-- Bags and more: in your bags, the windows ---------------------------------------------------

local function window(name, onClick, tipText)
    return button("more", "", HALF, name, onClick, tipText)
end

local function createMore()
    heading("more", "In your bags")
    tagsButton = toggle("more", HALF, "Tags", function()
        ns.Config.Set("tagsEverywhere", not ns.Config.Flag("tagsEverywhere"))
        if ns.BankAlt then ns.BankAlt.Redraw() end
    end, "The AH / BA / BH / DE / V tags on your bag items: on every character, or only on your bank alt and after Send.")
    glowButton = toggle("more", HALF, "Glow", function()
        ns.Config.Set("glowEverywhere", not ns.Config.Flag("glowEverywhere"))
        if ns.Border then ns.Border.RefreshAll() end
    end, "Locked items glow blue in your bags: always, or only while the Mailworthy window is open.")
    row("more", ROW, { { tagsButton, LEFT, 0 }, { glowButton, RIGHT, 0 } })
    -- Where this character banks its pinned items (Pins.lua; operator, 2026-11-13): BA or BH.
    pinButton = toggle("more", HALF, "Pins", function()
        ns.Pins.SetMode(ns.Pins.Mode() == ns.Pins.HERE and ns.Pins.BANK or ns.Pins.HERE, "settings")
    end, function() return UI.PinTip() end)
    -- How much Mailworthy adds to item tooltips (Config.Tooltips; a CurseForge request, 2026-11-14).
    tooltipButton = toggle("more", HALF, "Tooltips", function()
        ns.Config.CycleTooltips()
    end, function() return UI.TooltipsTip(ns.Config.Tooltips()) end)
    row("more", ROW, { { pinButton, LEFT, 0 }, { tooltipButton, RIGHT, 0 } })
    -- The pin warning (PinWarning.lua) as a switch (UX review U3: it was /mw pinwarning only).
    pinWarningButton = toggle("more", HALF, "PinWarning", function()
        ns.Config.Set("hidePinWarning", not ns.Config.Flag("hidePinWarning"))
    end, "Warn once when a pin to your bank alt takes an item this character's profession uses. The Mailworthy"
        .. " window's row and the item's tooltip say it every time.")
    minimapButton = toggle("more", HALF, "Minimap", function()
        ns.Config.Set("minimapHidden", ns.Config.MinimapShown())
        if ns.MinimapButton then ns.MinimapButton.Refresh() end
    end, "Mailworthy's button on the minimap (click: these settings).")
    row("more", ROW, { { pinWarningButton, LEFT, 0 }, { minimapButton, RIGHT, 0 } })
    -- Suggested bindings (Suggest.lua; operator, 2026-11-22: a Settings switch to turn them off for good).
    suggestButton = toggle("more", HALF, "Suggestions", function()
        ns.Config.Set("hideSuggestions", not ns.Config.Flag("hideSuggestions"))
    end, "At the mailbox, suggest crafters in your group and your own characters for your materials, and say in"
        .. " chat when one in your group could use something in your bags.")
    row("more", ROW + 4, { { suggestButton, LEFT, 0 } })
    heading("more", "Windows")
    -- QoL pass D (2026-11-09): the locked items window; the count is in the label.
    locksButton = window("Locks", function() ns.LocksUI.Show(frame) end,
        "This character's locked items, each with Unlock (also one no longer in your bags).")
    pinnedButton = window("Pinned", function() ns.PinsUI.Show(frame) end,
        "The account's pinned items, each with Unpin (also one no longer in your bags).")
    -- Friends, Guild and Mail ledger moved to the Mail routing window (operator, 2026-11-22).
    summaryButton = window("Summary", function()
        if ns.BankAlt then ns.BankAlt.ShowWindow(frame) end
    end, "On your bank alt (or without one): what to list, disenchant or sell to a vendor.")
    reportButton = window("Report", function() UI.OpenReport() end,
        "A copyable report for a bug report: settings, switches, the last send and the log.")
    rows.more[#rows.more + 1] = { grid = function()
        return { locksButton, pinnedButton, summaryButton, reportButton }
    end }
end

-- Pick view: who gets the mail --------------------------------------------------------

local function createPicker()
    local h = views.Add("pick", W.Label(frame, "GameFontNormal"))
    h:SetPoint("TOPLEFT", 20, -46)
    h:SetText("Who gets your mail?")
    local sub = views.Add("pick", W.Label(frame, "GameFontHighlightSmall"))
    sub:SetPoint("TOPLEFT", 28, -66)
    sub:SetText("Mailworthy mails only to this character (same realm and faction).")
    emptyHint = W.Label(frame, "GameFontHighlightSmall")
    emptyHint:SetWidth(WIDTH - 56)
    emptyHint:SetJustifyH("LEFT")
    emptyHint:SetText("No other characters on this realm and faction yet: log in on your bank alt once "
        .. "with Mailworthy installed, or type its name below. If this character is the bank alt (for "
        .. "example for a main on another WoW account), press the button below instead.")
    for i = 1, UI.MAX_CHOICES do
        local r = {}
        r.button = W.Button(frame, "", 290, function()
            if r.name then UI.Choose(r.name) end
        end, "MailworthySettingsChoice" .. i)
        -- Two presses (UX review U7): "Sure?" for 3 seconds, the second forgets the name.
        r.forget = W.ConfirmButton(frame, "Forget", "Sure?", 70, function()
            if r.name then
                ns.Config.ForgetName(r.name)
                UI.Refresh()
            end
        end, "MailworthySettingsForget" .. i)
        choiceRows[i] = r
    end
    hereButton = views.Add("pick", W.Button(frame, "", 372, function() UI.ToggleHere() end, "MailworthySettingsHere"))
    typedLabel = views.Add("pick", W.Label(frame, "GameFontHighlightSmall"))
    typedLabel:SetText("Or type a name:")
    nameBox = views.Add("pick", CreateFrame("EditBox", "MailworthySettingsName", frame, "InputBoxTemplate"))
    nameBox:SetSize(170, 20)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(48)
    nameBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        pendingUnknown = nil
        local match = ns.Config.Complete(self:GetText(), ns.Config.Choices())
        setHint(match and ("Matches " .. match .. ": press Use name.") or "")
    end)
    nameBox:SetScript("OnEnterPressed", function(self)
        UI.UseTyped()
        self:ClearFocus()
    end)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    useNameButton = views.Add("pick", W.Button(frame, "Use name", 90, function() UI.UseTyped() end,
        "MailworthySettingsUseName"))
    nameHint = views.Add("pick", W.Label(frame, "GameFontHighlightSmall"))
    nameHint:SetWidth(WIDTH - 56)
    nameHint:SetJustifyH("LEFT")
    backButton = views.Add("pick", W.Button(frame, "Back", 100, function()
        setView("main")
        UI.Refresh()
    end, "MailworthySettingsBack"))
end

--- Pick view layout for the choices that show; returns the y of its bottom row (Back).
local function layoutPicker(shown)
    local y = -88
    if shown == 0 then
        at(emptyHint, 28, y)
        y = y - 56
    end
    for i, r in ipairs(choiceRows) do
        at(r.button, 24, y - (i - 1) * ROW)
        at(r.forget, 324, y - (i - 1) * ROW)
    end
    y = y - shown * ROW - 6
    at(hereButton, 24, y)
    y = y - 34
    at(typedLabel, 28, y - 4)
    at(nameBox, 132, y)
    at(useNameButton, 310, y + 1)
    y = y - 26
    at(nameHint, 28, y)
    y = y - 32
    at(backButton, -24, y, "TOPRIGHT")
    return y
end

function UI.Create()
    if frame then return frame end
    win = W.Shell({ name = "MailworthySettingsFrame", width = WIDTH, height = 400, title = "Mailworthy settings",
        refresh = function() UI.Refresh() end })
    frame = win.frame
    views = W.Views({ mailing = {}, more = {}, pick = {} })
    createTabs()
    createMailing()
    createMore()
    createPicker()
    pricesLine = views.Add({ "mailing", "more" }, W.Label(frame, "GameFontDisableSmall"))
    pricesLine:SetWidth(270)
    pricesLine:SetJustifyH("LEFT")
    -- A newer Mailworthy is out (Version.lua): under the Prices line; the window grows to fit it.
    versionLine = views.Add({ "mailing", "more" }, W.Label(frame, "GameFontHighlightSmall"))
    versionLine:SetWidth(WIDTH - 56)
    versionLine:SetJustifyH("LEFT")
    doneButton = views.Add({ "mailing", "more" }, win.Done("MailworthySettingsDone"))
    views.pooled = { emptyHint }
    for _, r in ipairs(choiceRows) do
        views.pooled[#views.pooled + 1] = r.button
        views.pooled[#views.pooled + 1] = r.forget
    end
    views.Show("mailing")
    return frame
end

--- Pure: the bank alt row: "Name  (class level)" or "(this character)", or none yet. `mark` (the
--- Mailworthy mark, Comms.Mark) shows after the name.
function UI.BankAltText(bankAlt, here, choices, mark)
    if not bankAlt then return "|cffaaaaaaNone: what's worth selling stays in your bags.|r" end
    local detail = here and "this character" or nil
    for _, c in ipairs(choices or {}) do
        if c.name == bankAlt then
            detail = c.known and (tostring(c.class or "?"):lower() .. " " .. tostring(c.level or "?")) or "not seen yet"
        end
    end
    return "|cff33ff99" .. bankAlt .. "|r" .. (mark and (" " .. mark) or "") .. (detail and ("  |cffaaaaaa" .. detail .. "|r") or "")
end

local function fillPicker(bankAlt, here, choices)
    hereButton:SetText("This character is my bank alt")
    W.SetToggled(hereButton, here)
    local shown, marked = 0, false
    for i, r in ipairs(choiceRows) do
        local c = choices[i]
        if (c and c.name) ~= r.name then W.Disarm(r.forget) end -- the row shows another name now
        r.name = c and c.name or nil
        if c then
            local detail = c.known and string.format("(%s %s)", tostring(c.class or "?"):lower(), tostring(c.level or "?"))
                or "(not seen)"
            local nameText, m = ns.Comms.Mark(c.name)
            marked = marked or m
            r.button:SetText(nameText .. "  " .. detail)
            W.SetToggled(r.button, bankAlt == c.name)
            r.button:Show()
            if c.known then r.forget:Hide() else r.forget:Show() end
            shown = shown + 1
        else
            r.button:Hide()
            r.forget:Hide()
        end
    end
    if shown == 0 then emptyHint:Show() else emptyHint:Hide() end
    return shown, marked
end

--- Pure: the Profession materials button's label for Config.Values `v` (U8: short; the tooltip says
--- the rest): "Profession materials: on (BH)" / "on my bank alt (BA)" / "off".
function UI.MatsText(v)
    return "Profession materials: " .. (not v.keepProfessionMats and "off" or v.matsToBankAlt and "on my bank alt (BA)"
        or "on (BH)")
end

--- Pure: its explanation. `crafting`: "First Aid 80, Tailoring 130" (Bags.CraftingText), or "".
function UI.MatsTip(v, crafting)
    return string.format("This character keeps its profession materials: %s (%s). Press: %s.",
        not v.keepProfessionMats and "off" or v.matsToBankAlt and "on my bank alt (BA)" or "on (BH)",
        crafting ~= "" and crafting or "no crafting profession here",
        not v.keepProfessionMats and "kept on your bank alt (BA)" or v.matsToBankAlt and "kept here (BH)"
            or "off: valued like anything else")
end

--- Pure: the Disenchant value button's explanation; `addon` is the disenchant addon in use, or nil.
function UI.DisenchantTip(on, addon)
    return string.format("Include disenchant value: %s (%s). On: an item that brings more as enchanting materials "
        .. "is tagged DE and mailed to be disenchanted.", on and "on" or "off", addon or "era tables")
end

local function fillMain(bankAlt, here, choices)
    local _, marked = ns.Comms.Mark(bankAlt)
    if not bankAlt then marked = false end
    current:SetText(UI.BankAltText(bankAlt, here, choices, marked and ns.Comms.MARK or nil))
    changeButton:SetText(bankAlt and "Change..." or "Choose...")
    local v = ns.Config.Values()
    amountLabel:SetText("Gain at least |cffffffff" .. money(v.minGain) .. "|r")
    pctLabel:SetText(string.format("and at least |cffffffff%d%%|r over the vendor price",
        math.floor(v.minGainPct * 100 + 0.5)))
    for i, b in ipairs(durationButtons) do
        b:SetText(ns.Valuation.DURATION_HOURS[i] .. "h")
        W.SetToggled(b, v.duration == i)
    end
    disenchantButton:SetText("Disenchant value: " .. (v.disenchant and "on" or "off"))
    W.SetToggled(disenchantButton, v.disenchant == true)
    -- Per character (Config.CHARACTER): kept here, mailed to the bank alt (BA), or valued like the rest.
    matsButton:SetText(UI.MatsText(v))
    W.SetToggled(matsButton, v.keepProfessionMats == true)
    gatherButton:SetText("Sell what I gather: " .. (v.sellGathered and "on" or "off"))
    W.SetToggled(gatherButton, v.sellGathered == true)
    for tag, b in pairs(sendButtons) do
        local on = v[ns.Valuation.SEND[tag]] == true
        b:SetText(ns.Valuation.SEND_TAG[tag] .. ": " .. (on and "on" or "off")) -- the bag tag's own letters
        W.SetToggled(b, on)
    end
    tagsButton:SetText("Bag tags: " .. (ns.Config.Flag("tagsEverywhere") and "every character" or "bank alt + after Send"))
    W.SetToggled(tagsButton, ns.Config.Flag("tagsEverywhere") == true)
    glowButton:SetText("Lock glow: " .. (ns.Config.Flag("glowEverywhere") and "always" or "in Mailworthy"))
    W.SetToggled(glowButton, ns.Config.Flag("glowEverywhere") == true)
    pinButton:SetText(UI.PinText())
    W.SetToggled(pinButton, ns.Pins.Mode() == ns.Pins.HERE)
    tooltipButton:SetText(UI.TooltipsText(ns.Config.Tooltips()))
    W.SetToggled(tooltipButton, ns.Config.Tooltips() ~= "full")
    local warn = not ns.Config.Flag("hidePinWarning")
    pinWarningButton:SetText("Pin warning: " .. (warn and "on" or "off"))
    W.SetToggled(pinWarningButton, warn)
    local suggest = not ns.Config.Flag("hideSuggestions")
    suggestButton:SetText("Suggestions: " .. (suggest and "on" or "off"))
    W.SetToggled(suggestButton, suggest)
    minimapButton:SetText("Minimap button: " .. (ns.Config.MinimapShown() and "shown" or "hidden"))
    W.SetToggled(minimapButton, ns.Config.MinimapShown() == true)
    summaryButton:SetText("Bank alt summary...")
    reportButton:SetText("Report...")
    locksButton:SetText(ns.LocksUI.ButtonText(ns.Locks.Count()))
    pinnedButton:SetText(ns.PinsUI.ButtonText(#ns.Pins.List()))
    pricesLine:SetText(UI.PricesText())
    versionLine:SetText(ns.Version.Text() or "")
    for t, b in pairs(tabButtons) do W.SetToggled(b, tab == t) end
    return marked
end

--- Pure: the Item tooltips button, for Config.Tooltips' `size` (U8: short; UI.TooltipsTip says more).
function UI.TooltipsText(size)
    return "Item tooltips: " .. (size == "short" and "short" or size == "off" and "off" or "full")
end

--- Pure: the Item tooltips button's explanation.
function UI.TooltipsTip(size)
    return "How much Mailworthy adds to item tooltips: " .. (size == "short" and "short (one line)" or size == "off"
        and "off" or "full (the verdict and its numbers)") .. ". Press: full, short, off, round again."
end

--- Pure: the Pins button (U8: short): where this character banks its pins, in the tag's letters.
function UI.PinText()
    local why = ns.Pins.HereBecause()
    local P = ns.Palette
    if why == "no bank alt" or why == "bank alt" then return "Pins: " .. P.Letters(P.BH) .. " bank here" end
    return "Pins: " .. (why == "setting" and (P.Letters(P.BH) .. " bank here") or (P.Letters(P.BA) .. " to bank alt"))
end

--- Pure: the Pins button's explanation (what the pins do on this character, and why).
function UI.PinTip()
    local why = ns.Pins.HereBecause()
    local P = ns.Palette
    if why == "no bank alt" or why == "bank alt" then
        return "Pinned items: " .. P.Letters(P.BH) .. " bank here (" .. (why == "bank alt" and "this is your bank alt"
            or "no bank alt") .. ")"
    end
    return "Pinned items: " .. (why == "setting" and (P.Letters(P.BH) .. " bank here, on this character")
        or (P.Letters(P.BA) .. " mail to your bank alt")) .. ". Press to switch."
end

--- The main view's "Prices:" line: the auction source in use (Auctionator wins over
--- TradeSkillMaster), or what installing one changes.
function UI.PricesText()
    return "Prices: " .. (ns.Prices.SourceText() or "none (install Auctionator or TSM; white items and staple trade goods only)")
end

--- Report... (UX review U3): /mw report's box, beside the settings.
function UI.OpenReport()
    ns.Report.Open()
    local f = ns.Report.Frame()
    if f then W.PlaceBeside(f, frame) end
end

function UI.Refresh()
    if not frame then return end
    local bankAlt = ns.Config.BankAlt()
    local here = ns.Config.IsBankAltHere()
    local choices = ns.Config.Choices()
    views.Show(view == "pick" and "pick" or tab)
    local markedMain = fillMain(bankAlt, here, choices)
    local shown, markedPick = fillPicker(bankAlt, here, choices)
    local bottom
    if view == "pick" then
        bottom = layoutPicker(shown)
    else
        for _, r in ipairs(choiceRows) do
            r.button:Hide()
            r.forget:Hide()
        end
        emptyHint:Hide()
        local y = place(tab, TOP) - 6
        at(pricesLine, 28, y - 6)
        at(doneButton, -24, y, "TOPRIGHT")
        bottom = y
        if ns.Version.Text() then
            at(versionLine, 28, y - 26)
            bottom = y - VERSION_ROW
        end
    end
    win.Finish(bottom, (view == "pick" and markedPick) or (view ~= "pick" and markedMain))
end

function UI.RefreshIfShown()
    if frame and frame:IsShown() then UI.Refresh() end
end

--- Opens on the settings (a bank alt is optional: Choose... picks one), on the tab last shown.
--- `opener`: the Mailworthy window whose button opened it (placed beside that), or nil (centred).
--- `startView`: "pick" opens on choosing the bank alt (the mail window's Choose bank alt...);
--- "mailing" or "more" opens on that tab.
function UI.Show(opener, startView)
    if not frame then UI.Create() end
    if startView == "mailing" or startView == "more" then tab = startView end
    win.Show(opener, function() setView(startView == "pick" and "pick" or "main") end)
    ns.Log.Add("ui", "settings shown (%s, %s)", view, tab)
end

function UI.Toggle()
    if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

ns.On("PLAYER_LOGIN", function()
    UI.Create()
end)
-- A new Mailworthy user can be a name on screen (Comms.Mark): redraw.
ns.Comms.OnMarksChanged(UI.RefreshIfShown)
ns.Version.OnChanged(UI.RefreshIfShown)
-- The "Locked items (N)..." button counts the locks.
ns.Locks.OnChanged(UI.RefreshIfShown)
-- The Pins button follows the pin mode (also set from the pin warning); "Pinned items (N)..." counts them.
ns.Pins.OnChanged(UI.RefreshIfShown)
