-- The self-test window and the report box. Both join Forever's controller UI
-- (ns.Gamepad.Join: footer, L2/R2 cycle, Circle closes via CloseButton), use
-- only plain buttons (no typing, no right-click, no drag needed) and never move
-- keyboard focus: SetFocus crashed the gamepad UI in LedgerLink.
local _, ns = ...

local UI = {}
ns.SelfTestUI = UI

local WIDTH, ROW = 560, 26
local BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local frame, title, status, recipientButton, questionRows
local reportFrame, reportBox, reportText

local function window(name, width, height)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate")
    if not ok then f = CreateFrame("Frame", name, UIParent) end
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop(BACKDROP)
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    end
    -- Named *CloseButton and set as f.CloseButton: Circle (B) closes through it.
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

local function create()
    local height = 230 + #ns.SelfTest.QUESTIONS * ROW
    frame = window("MailworthySelfTestFrame", WIDTH, height)
    title = label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    status = label(frame, "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 22, -44)
    status:SetWidth(WIDTH - 44)
    status:SetJustifyH("LEFT")

    local y = -100
    local attachB = button(frame, "Attach test", 150, function() ns.SelfTest.RunAttach() end, "MailworthySelfTestAttach")
    attachB:SetPoint("TOPLEFT", 22, y)
    local clearB = button(frame, "Clear attachments", 150, function() ns.SelfTest.RunClear() end, "MailworthySelfTestClear")
    clearB:SetPoint("LEFT", attachB, "RIGHT", 10, 0)
    local reportB = button(frame, "Report", 150, function() ns.SelfTest.ShowReport() end, "MailworthySelfTestReport")
    reportB:SetPoint("LEFT", clearB, "RIGHT", 10, 0)
    y = y - ROW - 4
    recipientButton = button(frame, "Recipient: none", 310, function() ns.SelfTest.CycleRecipient() end,
        "MailworthySelfTestRecipient")
    recipientButton:SetPoint("TOPLEFT", 22, y)
    local sendB = button(frame, "Send test", 150, function() ns.SelfTest.SendPress() end, "MailworthySelfTestSend")
    sendB:SetPoint("LEFT", recipientButton, "RIGHT", 10, 0)

    y = y - ROW - 12
    local heading = label(frame)
    heading:SetPoint("TOPLEFT", 22, y)
    heading:SetText("What did you see? (answer with the controller)")
    questionRows = {}
    for i, q in ipairs(ns.SelfTest.QUESTIONS) do
        local rowY = y - 4 - i * ROW
        local text = label(frame, "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 22, rowY - 4)
        text:SetWidth(WIDTH - 170)
        text:SetJustifyH("LEFT")
        local yes = button(frame, "Yes", 52, function() ns.SelfTest.Answer(q.id, "yes") end, "MailworthySelfTestYes" .. i)
        yes:SetPoint("TOPRIGHT", -84, rowY)
        local no = button(frame, "No", 52, function() ns.SelfTest.Answer(q.id, "no") end, "MailworthySelfTestNo" .. i)
        no:SetPoint("TOPRIGHT", -24, rowY)
        questionRows[i] = { q = q, text = text }
    end

    ns.Gamepad.Join(frame, "MailworthySelfTestFooter", {
        { key = ns.Gamepad.FACE_LEFT, label = "Attach test", fn = function(isDown)
            if isDown ~= false then ns.SelfTest.RunAttach() end
        end },
        { key = ns.Gamepad.FACE_TOP, label = "Report", fn = function(isDown)
            if isDown ~= false then ns.SelfTest.ShowReport() end
        end },
    })
end

function UI.Refresh()
    if not frame then return end
    local glyph = ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP)
    title:SetText("Mailworthy self-test  " .. glyph)
    status:SetText(ns.SelfTest.state.status ~= "" and ns.SelfTest.state.status
        or ("Steps: docs/DISCOVERY-SESSION-2.md. Controller symbols: " .. tostring(ns.Gamepad.LabelStyle())))
    recipientButton:SetText("Recipient: " .. tostring(MailworthyDB.selftest.recipient or "press to choose"))
    for _, row in ipairs(questionRows) do
        local ans = MailworthyDB.selftest.answers[row.q.id]
        row.text:SetText((ans and ("[" .. ans.value .. "] ") or "") .. row.q.text)
    end
end

function UI.Show()
    if not frame then create() end
    UI.Refresh()
    frame:Show()
end

function UI.Frame() return frame end

-- Report box: a read-only-feeling EditBox. The player clicks the text to select it.
local function createReport()
    reportFrame = window("MailworthyReportFrame", 640, 440)
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
    ns.Gamepad.Join(reportFrame, "MailworthyReportFooter", {})
end

function UI.ShowReport(text)
    if not reportFrame then createReport() end
    reportText = text
    reportBox:SetText(text)
    reportFrame:Show()
end

function UI.ReportText() return reportText end
