-- The mail window's tab watcher (MailWindow.lua): our own frame, created at login on UIParent, that
-- reads which mail tab shows five times a second, nothing more. Its jobs: follow the window to the
-- Send Mail tab, open it when that tab shows (switch autoOpen), redraw when the tab changes (Send is
-- greyed out on the Inbox), and re-read an empty list. We never switch tabs ourselves
-- (MailFrameTab_OnClick taints the controller UI). Errors are logged, never raised every frame.
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared

--- True while the Inbox tab is what shows, where nothing can be sent. Read from what the
--- player sees (IsVisible), not from which tab the window was opened on: v0.17.1 to v0.20.1
--- tested the window's parent and the Send Mail frame's own shown flag, and in game the Send
--- button stayed hidden on the Send Mail tab (operator, 2026-11-07: "the send mail button is
--- just gone now").
function UI.OnInbox()
    local send, inbox = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame")
    if type(send) == "table" and send:IsVisible() then return false end
    return type(inbox) == "table" and inbox:IsVisible() == true
end

--- What the tab test sees, for the log and /mw report.
function UI.TabState()
    local function state(name)
        local f = rawget(_G, name)
        if type(f) ~= "table" then return name .. " missing" end
        return string.format("%s shown %s visible %s", name, tostring(f:IsShown()), tostring(f:IsVisible()))
    end
    local parent = S.frame and S.frame:GetParent()
    local parentName = parent and parent.GetName and parent:GetName() or tostring(parent)
    return string.format("%s; %s; window on %s", state("SendMailFrame"), state("InboxFrame"), tostring(parentName))
end

--- The watcher's second job: if the tab changed since the last draw (the Send button and the
--- Inbox note follow it), redraw. Returns true when it redrew.
function UI.CheckTab()
    if not (S.frame and S.frame:IsVisible()) or ns.Mailer.Busy() then return false end
    local onInbox = UI.OnInbox()
    if onInbox == S.renderedInbox then return false end
    ns.Log.Add("ui", "tab changed (%s): %s", onInbox and "Inbox" or "Send Mail", UI.TabState())
    S.renderedInbox = onInbox -- once per change, even if the redraw fails
    UI.Refresh(true)
    return true
end

--- The watcher's fourth job: with nothing on the list Send is greyed out, so no press re-reads the
--- bags as Send does. The list is read again every RECHECK seconds while it is empty (item data
--- that arrived late, a quest abandoned: Codex review, 2026-11-09). Returns true when it re-read.
UI.RECHECK = 2
local emptyFor = 0
function UI.RecheckEmpty(dt)
    if not (S.frame and S.frame:IsVisible()) or ns.Mailer.Busy() or not S.result or #S.result.mail > 0 then
        emptyFor = 0
        return false
    end
    emptyFor = emptyFor + (dt or 0)
    if emptyFor < UI.RECHECK then return false end
    emptyFor = 0
    UI.Refresh()
    return true
end

local sendWasVisible = false
--- The watcher's third job: the Send Mail tab just showed and the window is closed: open it
--- (operator, 2026-11-08). Once per showing: closed there, it stays closed until the tab shows
--- again. Returns true when it opened the window.
function UI.AutoOpen()
    local send, mail = rawget(_G, "SendMailFrame"), rawget(_G, "MailFrame")
    local visible = type(send) == "table" and send:IsVisible() == true and type(mail) == "table"
    local opened = false
    -- On the bank alt only while its window mails (switch bankAltMail): else its Mailworthy button
    -- opens the summary, not a list to send (Codex review).
    local bankAltWindow = not ns.Config.IsBankAltHere() or ns.Features.On("bankAltMail")
    if visible and not sendWasVisible and ns.Features.On("autoOpen") and not ns.Mailer.Busy()
        and bankAltWindow and not (S.frame and S.frame:IsVisible()) then
        ns.Log.Add("ui", "Send Mail tab shown: window opened")
        UI.Show("send")
        opened = true
    end
    sendWasVisible = visible
    return opened
end

--- Opened on the Inbox and the player moved to Send Mail: move the window there too.
--- (Opened on Send Mail and back from the Inbox needs nothing: it was hidden with its tab.)
function UI.FollowTab()
    local send, inbox = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame")
    local frame = S.frame
    if frame and frame:IsShown() and type(inbox) == "table" and frame:GetParent() == inbox
        and type(send) == "table" and send:IsShown() then
        ns.Log.Add("ui", "mail window follows to the Send Mail tab")
        UI.Show("send")
        return true
    end
    return false
end

ns.On("PLAYER_LOGIN", function()
    local watcher = CreateFrame("Frame", "MailworthyTabWatcher", UIParent)
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.2 then return end
        elapsed = 0
        local ok, err = pcall(UI.FollowTab)
        if ok then ok, err = pcall(UI.AutoOpen) end
        if ok then ok, err = pcall(UI.CheckTab) end
        if ok then ok, err = pcall(UI.RecheckEmpty, 0.2) end
        if not ok then ns.Log.Add("ui", "tab watcher error: %s", tostring(err)) end
    end)
end)
-- A mailbox closed and reopened on Send Mail between two watcher ticks still opens the window.
ns.On("MAIL_CLOSED", function() sendWasVisible = false end)
