-- The Mailworthy window (self-test build) and the report box.
--
-- Controller: the window is a child of SendMailFrame, the mail window's
-- "Send Mail" navigation group, anchored to the right of the mail window. Its
-- buttons are plain buttons created at login (never while a gamepad panel is
-- open), so smart navigation picks them up with the rest of the tab: D-pad to
-- move, Cross to press. It registers nothing with Blizzard's controller UI and
-- sets no smart-navigation keys (both tainted gamepad input in alpha1/alpha2).
-- Mouse and keyboard work as usual. Keyboard focus never moves (SetFocus
-- crashed the gamepad UI in LedgerLink).
--
-- Pages: Questions (Yes/No), Bag locks (Cross / click toggles a slot's lock:
-- the controller way to lock), Tests (attach / send).
local _, ns = ...

local UI = {}
ns.SelfTestUI = UI

local WIDTH, ROW, CELL, COLUMNS = 440, 24, 34, 11
UI.MAX_LOCK_BUTTONS = 110
local BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local frame, title, status, legend, recipientButton, pageLabel
local pages, questionRows, lockButtons = {}, {}, {}
local lockSlots = setmetatable({}, { __mode = "k" }) -- our lock button -> { bag, slot }
local current = "questions"
local reportFrame, reportBox, reportText

local function window(name, width, height, parent)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate")
    if not ok then f = CreateFrame("Frame", name, UIParent) end
    if parent then f:SetParent(parent) end
    f:SetSize(width, height)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop(BACKDROP)
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    end
    f.CloseButton = CreateFrame("Button", name .. "CloseButton", f, "UIPanelCloseButton")
    f.CloseButton:SetPoint("TOPRIGHT", -6, -6)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    f:Hide()
    return f
end

local function button(parent, text, width, onClick, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function label(parent, font)
    return parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
end

local function page(name)
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 16, -104)
    p:SetPoint("BOTTOMRIGHT", -16, 36)
    p:Hide()
    pages[name] = p
    return p
end

local function createQuestions()
    local p = page("questions")
    for i, q in ipairs(ns.SelfTest.QUESTIONS) do
        local y = -(i - 1) * ROW
        local text = label(p, "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 4, y - 4)
        text:SetWidth(WIDTH - 160)
        text:SetJustifyH("LEFT")
        local yes = button(p, "Yes", 48, function() ns.SelfTest.Answer(q.id, "yes") end, "MailworthySelfTestYes" .. i)
        yes:SetPoint("TOPRIGHT", -56, y)
        local no = button(p, "No", 48, function() ns.SelfTest.Answer(q.id, "no") end, "MailworthySelfTestNo" .. i)
        no:SetPoint("TOPRIGHT", -4, y)
        questionRows[i] = { q = q, text = text }
    end
end

local function lockEdges(b)
    local edges = {}
    local specs = { { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }
    for i, spec in ipairs(specs) do
        local tex = b:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(unpack(ns.Border.COLOR))
        tex:SetPoint(spec[1])
        tex:SetPoint(spec[2])
        if spec[3] then tex:SetWidth(spec[3]) end
        if spec[4] then tex:SetHeight(spec[4]) end
        edges[i] = tex
    end
    return edges
end

local function createLocks()
    local p = page("locks")
    local hint = label(p, "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 4, 0)
    hint:SetText("Press a slot to lock or unlock it. Locked slots are never mailed (blue border).")
    for i = 1, UI.MAX_LOCK_BUTTONS do
        local b = CreateFrame("Button", "MailworthyLockSlot" .. i, p)
        b:SetSize(CELL - 2, CELL - 2)
        b:SetPoint("TOPLEFT", ((i - 1) % COLUMNS) * CELL, -18 - math.floor((i - 1) / COLUMNS) * CELL)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", -2, 2)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function(self)
            local slot = lockSlots[self]
            if slot then ns.Locks.Toggle(slot.bag, slot.slot, "lock grid") end
        end)
        -- Mouse: the item's tooltip on hover.
        b:SetScript("OnEnter", function(self)
            local slot = lockSlots[self]
            if not slot or type(GameTooltip) ~= "table" then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetBagItem, GameTooltip, slot.bag, slot.slot)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        b:Hide()
        lockButtons[i] = { button = b, icon = icon, count = count, edges = lockEdges(b) }
    end
end

local function createTests()
    local p = page("tests")
    local attach = button(p, "Attach test", 130, function() ns.SelfTest.RunAttach() end, "MailworthySelfTestAttach")
    attach:SetPoint("TOPLEFT", 0, 0)
    local clear = button(p, "Clear attachments", 130, function() ns.SelfTest.RunClear() end, "MailworthySelfTestClear")
    clear:SetPoint("LEFT", attach, "RIGHT", 8, 0)
    recipientButton = button(p, "Recipient: none", 268, function() ns.SelfTest.CycleRecipient() end,
        "MailworthySelfTestRecipient")
    recipientButton:SetPoint("TOPLEFT", 0, -30)
    local send = button(p, "Send test", 130, function() ns.SelfTest.SendPress() end, "MailworthySelfTestSend")
    send:SetPoint("TOPLEFT", 0, -60)
end

local PAGES = { { "questions", "Questions" }, { "locks", "Bag locks" }, { "tests", "Tests" } }

function UI.ShowPage(name)
    current = name
    for key, p in pairs(pages) do
        if key == name then p:Show() else p:Hide() end
    end
    UI.Refresh()
end

function UI.Create()
    if frame then return frame end
    local send = rawget(_G, "SendMailFrame")
    local height = 150 + math.max(#ns.SelfTest.QUESTIONS * ROW, 18 + math.ceil(UI.MAX_LOCK_BUTTONS / COLUMNS) * CELL)
    frame = window("MailworthySelfTestFrame", WIDTH, height, type(send) == "table" and send or nil)
    title = label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    status = label(frame, "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 20, -42)
    status:SetWidth(WIDTH - 40)
    status:SetJustifyH("LEFT")
    local previous
    for i, spec in ipairs(PAGES) do
        local b = button(frame, spec[2], 96, function() UI.ShowPage(spec[1]) end, "MailworthySelfTestPage" .. i)
        if previous then b:SetPoint("LEFT", previous, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 18, -74) end
        previous = b
    end
    local report = button(frame, "Report", 96, function() ns.SelfTest.ShowReport() end, "MailworthySelfTestReport")
    report:SetPoint("LEFT", previous, "RIGHT", 6, 0)
    pageLabel = label(frame, "GameFontNormalSmall")
    pageLabel:SetPoint("TOPRIGHT", -20, -24)
    createQuestions()
    createLocks()
    createTests()
    legend = label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", 0, 16)
    frame:SetScript("OnHide", function(self)
        -- Opened with /mw selftest away from a mailbox: give it back to the Send Mail tab.
        if type(send) == "table" and self:GetParent() ~= send then self:SetParent(send) end
    end)
    UI.ShowPage("questions")
    ns.Log.Add("ui", "window created%s", type(send) == "table" and " under SendMailFrame" or " (no SendMailFrame)")
    return frame
end

function UI.RefreshLocks()
    if not frame then return end
    local n = 0
    local numSlots = C_Container and C_Container.GetContainerNumSlots
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        local okSlots, slots = pcall(numSlots, bag)
        for slot = 1, okSlots and tonumber(slots) or 0 do
            local info = ns.Locks.ItemAt(bag, slot)
            if info and n < UI.MAX_LOCK_BUTTONS then
                n = n + 1
                local entry = lockButtons[n]
                lockSlots[entry.button] = { bag = bag, slot = slot }
                entry.icon:SetTexture(info.iconFileID)
                entry.count:SetText((tonumber(info.stackCount) or 1) > 1 and info.stackCount or "")
                local locked = ns.Locks.IsLocked(bag, slot)
                for _, tex in ipairs(entry.edges) do
                    if locked then tex:Show() else tex:Hide() end
                end
                entry.button:Show()
            end
        end
    end
    for i = n + 1, UI.MAX_LOCK_BUTTONS do
        lockSlots[lockButtons[i].button] = nil
        lockButtons[i].button:Hide()
    end
end

function UI.Refresh()
    if not frame then return end
    title:SetText("Mailworthy  " .. ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP))
    legend:SetText(string.format("%s select    %s back    D-pad move    %s open / close",
        ns.Gamepad.Glyph(ns.Gamepad.FACE_BOTTOM), ns.Gamepad.Glyph(ns.Gamepad.FACE_RIGHT),
        ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP)))
    status:SetText(ns.SelfTest.state.status ~= "" and ns.SelfTest.state.status
        or "Discovery build: answer the questions; lock slots on Bag locks.")
    for _, spec in ipairs(PAGES) do
        if spec[1] == current then pageLabel:SetText(spec[2]) end
    end
    recipientButton:SetText("Recipient: " .. tostring(MailworthyDB.selftest.recipient or "press to choose"))
    for _, row in ipairs(questionRows) do
        local ans = MailworthyDB.selftest.answers[row.q.id]
        row.text:SetText((ans and ("[" .. ans.value .. "] ") or "") .. row.q.text)
    end
    if current == "locks" then UI.RefreshLocks() end
end

--- Beside the mail window, as a child of the showing tab: on Send Mail (the
--- controller's D-pad reaches it there) or, for mouse / keyboard, the Inbox.
--- Away from a mailbox (/mw selftest) a normal window in the middle.
function UI.Show(tab)
    if not frame then UI.Create() end
    local send, inbox, mail = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame"), rawget(_G, "MailFrame")
    local parent
    if tab == "send" or (tab == nil and type(send) == "table" and send:IsShown()) then
        parent = send
    elseif tab == "inbox" or (tab == nil and type(inbox) == "table" and inbox:IsShown()) then
        parent = inbox
    end
    frame:ClearAllPoints()
    if type(parent) == "table" then
        if frame:GetParent() ~= parent then frame:SetParent(parent) end
        frame:SetPoint("TOPLEFT", mail, "TOPRIGHT", 8, 0)
    else
        frame:SetParent(UIParent)
        frame:SetPoint("CENTER")
    end
    UI.Refresh()
    frame:Show()
    ns.Log.Add("ui", "window shown (%s)", parent == send and "Send Mail tab" or parent == inbox and "Inbox tab"
        or "on its own")
end

function UI.Toggle(tab)
    if frame and frame:IsShown() then
        frame:Hide()
        ns.Log.Add("ui", "window hidden")
    else
        UI.Show(tab)
    end
end

function UI.Frame() return frame end

-- Report box: created at login on UIParent. The player clicks the text to select it.
function UI.CreateReport()
    if reportFrame then return end
    reportFrame = window("MailworthyReportFrame", 640, 440)
    reportFrame:SetPoint("CENTER")
    local heading = label(reportFrame, "GameFontNormalLarge")
    heading:SetPoint("TOP", 0, -18)
    heading:SetText("Mailworthy self-test report")
    local hint = label(reportFrame, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOM", 0, 18)
    hint:SetText("Click the text, Ctrl+C, then paste it to the addon developer")
    local scroll = CreateFrame("ScrollFrame", "MailworthyReportScroll", reportFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -44)
    scroll:SetPoint("BOTTOMRIGHT", -40, 40)
    reportBox = CreateFrame("EditBox", "MailworthyReportEditBox", scroll)
    reportBox:SetMultiLine(true)
    reportBox:SetMaxLetters(0)
    reportBox:SetAutoFocus(false)
    reportBox:SetFontObject(ChatFontNormal)
    reportBox:SetWidth(560)
    reportBox:SetScript("OnEscapePressed", function() reportFrame:Hide() end)
    reportBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(reportText)
            self:HighlightText()
        end
    end)
    reportBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    reportBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    scroll:SetScrollChild(reportBox)
end

function UI.ShowReport(text)
    if not reportFrame then UI.CreateReport() end
    reportText = text
    reportBox:SetText(text)
    reportFrame:Show()
end

function UI.ReportText() return reportText end

ns.On("PLAYER_LOGIN", function()
    UI.Create()
    UI.CreateReport()
    ns.Locks.OnChanged(function() if frame and frame:IsShown() then UI.Refresh() end end)
end)
ns.On("BAG_UPDATE_DELAYED", function()
    if frame and frame:IsShown() and current == "locks" then UI.RefreshLocks() end
end)
ns.On("MAIL_CLOSED", function()
    if frame and frame:IsShown() and frame:GetParent() ~= UIParent then frame:Hide() end
end)
