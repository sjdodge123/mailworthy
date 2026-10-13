-- The "Mailworthy" button on the mail window: a plain child Button of MailFrame,
-- so a mouse click works and the controller's smart navigation reaches it with
-- the D-pad like any other mail-window button (Cross presses it). It writes
-- nothing into Blizzard's controller tables: alpha1's footer binding did, and
-- tainted gamepad input game-wide (see Gamepad.lua).
local _, ns = ...

local MailButton = {}
ns.MailButton = MailButton

local button

function MailButton.Create()
    if button then return button end
    local mail = rawget(_G, "MailFrame")
    if type(mail) ~= "table" or InCombatLockdown() then return nil end
    if not ns.Features.On("mailButton") then
        ns.Log.Add("mailbutton", "off (/mw feature mailButton on, then /reload)")
        return nil
    end
    button = CreateFrame("Button", "MailworthyMailButton", mail, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    button:SetText("Mailworthy")
    button:SetPoint("TOPRIGHT", mail, "TOPRIGHT", -30, -28)
    button:SetScript("OnClick", function()
        ns.lastCommand = "mail button"
        ns.Log.Add("mailbutton", "pressed")
        ns.SelfTest.Open("mail button")
    end)
    ns.Log.Add("mailbutton", "created on MailFrame")
    return button
end

ns.On("MAIL_SHOW", function() MailButton.Create() end)
