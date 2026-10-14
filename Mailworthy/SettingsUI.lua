-- The settings window: bank alt, minimum gain, disenchant, listing length,
-- minimap button. Keyboard/mouse: click. Controller: the D-pad moves Mailworthy's
-- own highlight, Cross presses, Circle closes (PadKey "settings" set, Nav); every
-- setting is a button, so nothing needs typing. The name box is an optional
-- fallback the player clicks into (the game never moves focus: no SetFocus).
--
-- Opened with /mw, the minimap button, or the Settings button in the Mailworthy
-- window at the mailbox. Not registered in Blizzard's options panel: that hands
-- our frame and category tables to a panel the controller UI navigates, the same
-- pattern that made the More-menu entry taint gamepad input (alpha2).
local _, ns = ...

local UI = {}
ns.SettingsUI = UI

UI.MAX_CHOICES = 6
local WIDTH, HEIGHT, ROW = 420, 580, 26

local frame, nameBox, nameHint, current, emptyHint, legend
local choiceRows = {}
local amountLabel, pctLabel, disenchantButton, minimapButton, tagsButton
local durationButtons = {}
local pendingUnknown -- a typed name Mailworthy hasn't seen, waiting for a second press

local W = ns.Widgets
local money = function(c) return ns.Valuation.Money(c) end

function UI.Frame() return frame end

local function heading(text, y)
    local h = W.Label(frame, "GameFontNormal")
    h:SetPoint("TOPLEFT", 20, y)
    h:SetText(text)
    return h
end

local function setHint(text) nameHint:SetText(text or "") end

function UI.UseTyped()
    local text = ns.Config.Clean(nameBox:GetText())
    if not text then return setHint("Type a name first, or pick one above.") end
    if text:lower() == tostring(ns.PlayerName()):lower() then
        return setHint("That's this character. Pick the character that should receive the mail.")
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
    if saved then ns.Print("Bank alt: " .. saved .. ". Mail goes only to this character.") end
    UI.Refresh()
end

local function createBankAlt()
    heading("Bank alt (Mailworthy mails only to this character)", -46)
    current = W.Label(frame, "GameFontHighlight")
    current:SetPoint("TOPLEFT", 28, -66)
    emptyHint = W.Label(frame, "GameFontHighlightSmall")
    emptyHint:SetPoint("TOPLEFT", 28, -92)
    emptyHint:SetWidth(WIDTH - 56)
    emptyHint:SetJustifyH("LEFT")
    emptyHint:SetText("No other characters on this realm and faction yet: log in on your bank alt once "
        .. "with Mailworthy installed, or type its name below.")
    for i = 1, UI.MAX_CHOICES do
        local y = -88 - (i - 1) * ROW
        local row = {}
        row.button = W.Button(frame, "", 290, function()
            if row.name then UI.Choose(row.name) end
        end, "MailworthySettingsChoice" .. i)
        row.button:SetPoint("TOPLEFT", 24, y)
        row.forget = W.Button(frame, "Forget", 70, function()
            if row.name then
                ns.Config.ForgetName(row.name)
                UI.Refresh()
            end
        end, "MailworthySettingsForget" .. i)
        row.forget:SetPoint("TOPLEFT", 322, y)
        choiceRows[i] = row
    end
    local typed = W.Label(frame, "GameFontHighlightSmall")
    typed:SetPoint("TOPLEFT", 28, -252)
    typed:SetText("Or type it:")
    nameBox = CreateFrame("EditBox", "MailworthySettingsName", frame, "InputBoxTemplate")
    nameBox:SetSize(190, 20)
    nameBox:SetPoint("TOPLEFT", 104, -248)
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
    W.Button(frame, "Use name", 90, function() UI.UseTyped() end, "MailworthySettingsUseName")
        :SetPoint("TOPLEFT", 302, -247)
    nameHint = W.Label(frame, "GameFontHighlightSmall")
    nameHint:SetPoint("TOPLEFT", 28, -274)
    nameHint:SetWidth(WIDTH - 56)
    nameHint:SetJustifyH("LEFT")
end

local function stepper(y, key, name)
    local text = W.Label(frame, "GameFontHighlight")
    text:SetPoint("TOPLEFT", 28, y - 4)
    local minus = W.Button(frame, "-", 32, function()
        ns.Config.Step(key, -1)
        UI.Refresh()
    end, "MailworthySettings" .. name .. "Down")
    minus:SetPoint("TOPLEFT", 300, y)
    local plus = W.Button(frame, "+", 32, function()
        ns.Config.Step(key, 1)
        UI.Refresh()
    end, "MailworthySettings" .. name .. "Up")
    plus:SetPoint("TOPLEFT", 338, y)
    return text
end

local function createRule()
    heading("Minimum gain over vendoring (both must hold)", -306)
    amountLabel = stepper(-328, "minGain", "Amount")
    pctLabel = stepper(-356, "minGainPct", "Percent")
    heading("Auction house and disenchanting", -390)
    disenchantButton = W.Button(frame, "", 364, function()
        ns.Config.Set("disenchant", not ns.Config.Get("disenchant"))
        UI.Refresh()
    end, "MailworthySettingsDisenchant")
    disenchantButton:SetPoint("TOPLEFT", 24, -412)
    local listing = W.Label(frame, "GameFontHighlight")
    listing:SetPoint("TOPLEFT", 28, -444)
    listing:SetText("Listing length:")
    for i, hours in ipairs(ns.Valuation.DURATION_HOURS) do
        local b = W.Button(frame, hours .. "h", 64, function()
            ns.Config.Set("duration", i)
            UI.Refresh()
        end, "MailworthySettingsDuration" .. i)
        b:SetPoint("TOPLEFT", 186 + (i - 1) * 70, -440)
        durationButtons[i] = b
    end
end

function UI.Create()
    if frame then return frame end
    frame = W.Window("MailworthySettingsFrame", WIDTH, HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetPoint("CENTER")
    local title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Mailworthy settings")
    createBankAlt()
    createRule()
    minimapButton = W.Button(frame, "", 220, function()
        ns.Config.Set("minimapHidden", ns.Config.MinimapShown())
        if ns.MinimapButton then ns.MinimapButton.Refresh() end
        UI.Refresh()
    end, "MailworthySettingsMinimap")
    minimapButton:SetPoint("TOPLEFT", 24, -510)
    tagsButton = W.Button(frame, "", 220, function()
        ns.Config.Set("tagsEverywhere", not ns.Config.Flag("tagsEverywhere"))
        if ns.BankAlt then ns.BankAlt.Redraw() end
        UI.Refresh()
    end, "MailworthySettingsTags")
    tagsButton:SetPoint("TOPLEFT", 24, -478)
    W.Button(frame, "Bank alt summary", 140, function()
        if ns.BankAlt then ns.BankAlt.ShowWindow() end
    end, "MailworthySettingsSummary"):SetPoint("TOPRIGHT", -24, -478)
    W.Button(frame, "Done", 100, function() frame:Hide() end, "MailworthySettingsDone")
        :SetPoint("TOPRIGHT", -24, -510)
    legend = W.Label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", 0, 18)
    ns.Nav.Attach(frame)
    ns.Log.Add("ui", "settings window created")
    return frame
end

local function selected(text, on)
    return on and ("|cff33ff99> " .. text .. " <|r") or text
end

function UI.Refresh()
    if not frame then return end
    local bankAlt = ns.Config.BankAlt()
    current:SetText("Now: " .. (bankAlt and ("|cff33ff99" .. bankAlt .. "|r") or "|cffff8040none: pick one below|r"))
    local choices = ns.Config.Choices()
    for i, row in ipairs(choiceRows) do
        local c = choices[i]
        row.name = c and c.name or nil
        if c then
            local detail = c.known and string.format("(%s %s)", tostring(c.class or "?"):lower(), tostring(c.level or "?"))
                or "(not seen)"
            row.button:SetText(selected(c.name .. "  " .. detail, bankAlt == c.name))
            row.button:Show()
            if c.known then row.forget:Hide() else row.forget:Show() end
        else
            row.button:Hide()
            row.forget:Hide()
        end
    end
    if #choices == 0 then emptyHint:Show() else emptyHint:Hide() end
    local v = ns.Config.Values()
    amountLabel:SetText("Amount: at least " .. money(v.minGain))
    pctLabel:SetText(string.format("Percent: at least %d%% of the vendor price", math.floor(v.minGainPct * 100 + 0.5)))
    disenchantButton:SetText(string.format("Include disenchant value: %s%s", v.disenchant and "on" or "off",
        ns.Prices.DisenchantryInstalled() and "" or " (Disenchantry not installed)"))
    for i, b in ipairs(durationButtons) do
        b:SetText(selected(ns.Valuation.DURATION_HOURS[i] .. "h", v.duration == i))
    end
    minimapButton:SetText("Minimap button: " .. (ns.Config.MinimapShown() and "shown" or "hidden"))
    tagsButton:SetText("AH / DE / V tags: " .. (ns.Config.Flag("tagsEverywhere") and "every character" or "bank alt only"))
    legend:SetText(ns.MailButton.GamepadUI() and W.Legend() or "")
end

function UI.Show()
    if not frame then UI.Create() end
    UI.Refresh()
    frame:Show()
    frame:Raise()
    ns.Log.Add("ui", "settings shown")
end

function UI.Toggle()
    if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

ns.On("PLAYER_LOGIN", function() UI.Create() end)
