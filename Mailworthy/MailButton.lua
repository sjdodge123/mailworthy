-- The way in at the mailbox, for mouse and controller alike.
--
-- A plain "Mailworthy" Button just below the mail window, parented to
-- SendMailFrame: the mail window's smart navigation only searches the active
-- tab's group ("Inbox" / "Send Mail", MailFrame.lua), and SendMailFrame is the
-- "Send Mail" group, so the D-pad reaches it there (children outside the
-- frame's bounds count) and Cross presses it. A click works for the mouse.
-- On the Inbox tab a hint says to switch to Send Mail (R1); we never switch
-- tabs ourselves (Blizzard's tab code would then run in our context).
--
-- Everything is created at login: creating frames while a gamepad panel is open
-- trips SmartNavigation's CreateFrame hook in our context. Nothing is written
-- into Blizzard's tables, and no smart-navigation key is set on our buttons.
local _, ns = ...

local MailButton = {}
ns.MailButton = MailButton

local button, inboxHint

local function sendTabShown()
    local send = rawget(_G, "SendMailFrame")
    return type(send) == "table" and send:IsShown()
end

--- Mail button click or Triangle: toggle the Mailworthy window on Send Mail.
function MailButton.Activate(source)
    ns.lastCommand = tostring(source)
    if not sendTabShown() then
        ns.Log.Add("mailbutton", "%s on the Inbox: hint shown", tostring(source))
        ns.Print("Switch to the Send Mail tab (R1), then press Triangle or the Mailworthy button.")
        return
    end
    ns.Log.Add("mailbutton", "%s", tostring(source))
    ns.SelfTestUI.Toggle()
end

function MailButton.Create()
    if button then return button end
    local send, inbox, mail = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame"), rawget(_G, "MailFrame")
    if type(send) ~= "table" or type(mail) ~= "table" or InCombatLockdown() then return nil end
    if not ns.Features.On("mailButton") then
        ns.Log.Add("mailbutton", "off (/mw feature mailButton on, then /reload)")
        return nil
    end
    -- Created on UIParent, then parented: the CreateFrame hook only reacts to frames under an open panel.
    button = CreateFrame("Button", "MailworthyMailButton", UIParent, "UIPanelButtonTemplate")
    button:SetParent(send)
    button:SetSize(140, 24)
    button:SetText("Mailworthy " .. ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP, 14))
    button:SetPoint("TOPRIGHT", mail, "BOTTOMRIGHT", -7, -2)
    button:SetScript("OnClick", function() MailButton.Activate("mail button") end)
    if type(inbox) == "table" then
        inboxHint = inbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        inboxHint:SetPoint("TOPRIGHT", mail, "BOTTOMRIGHT", -9, -6)
        inboxHint:SetText("Mailworthy: Send Mail tab (R1), then " .. ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP, 14))
    end
    ns.Log.Add("mailbutton", "created under SendMailFrame (below the mail window)")
    return button
end

ns.On("PLAYER_LOGIN", function() MailButton.Create() end)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_MailFrame" then MailButton.Create() end
end)
