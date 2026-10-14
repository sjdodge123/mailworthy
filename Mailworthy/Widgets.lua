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
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    end
    f.CloseButton = CreateFrame("Button", name .. "CloseButton", f, "UIPanelCloseButton")
    f.CloseButton:SetPoint("TOPRIGHT", -6, -6)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    f:Hide()
    return f
end

function Widgets.Button(parent, text, width, onClick, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
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
