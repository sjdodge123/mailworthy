-- "Triangle (Y): Mailworthy" in the mail window's controller footer, on the
-- Inbox and Send Mail tabs (an opened mail already uses Triangle for Options).
-- The footer only exists once the game has set up gamepad mode, and SetupGamepad
-- can't be hooked, so we hook each tab's FocusGamepad (called by name) and add
-- the binding once per footer, then Finalize (Refresh alone doesn't re-read the
-- list). Out of combat only: activating a footer sets override bindings.
-- See docs/FOREVER-UI-NOTES.md.
local _, ns = ...

local MailFooter = {}
ns.MailFooter = MailFooter

MailFooter.TARGETS = { "InboxFrame", "SendMailFrame" }

local added = setmetatable({}, { __mode = "k" }) -- footer -> true (kept off Blizzard's tables)
local hooked = {}

function MailFooter.OnPress(frameName, isDown)
    if isDown == false then return end
    ns.Log.Add("footer", "Triangle pressed on %s", frameName)
    ns.lastCommand = "footer Triangle on " .. frameName
    ns.SelfTest.Open(frameName)
end

function MailFooter.Ensure(frameName)
    local frame = rawget(_G, frameName)
    local footer = type(frame) == "table" and frame.gamepadFooter or nil
    if type(footer) ~= "table" then
        ns.Log.Add("footer", "%s: no gamepadFooter yet", frameName)
        return false
    end
    if added[footer] then return true end
    if InCombatLockdown() then
        ns.Log.Add("footer", "%s: in combat, binding not added", frameName)
        return false
    end
    local binding, err = ns.Gamepad.Binding(ns.Gamepad.FACE_TOP,
        function(isDown) MailFooter.OnPress(frameName, isDown) end, "Mailworthy")
    if not binding then
        ns.Log.Add("footer", "%s: %s", frameName, err)
        return false
    end
    local okAdd, errAdd = pcall(footer.AddPromptedBinding, footer, binding)
    local okFin, errFin = pcall(footer.Finalize, footer)
    added[footer] = okAdd or nil
    ns.Log.Add("footer", "%s: AddPromptedBinding %s, Finalize %s, footer shown %s", frameName,
        okAdd and "ok" or tostring(errAdd), okFin and "ok" or tostring(errFin), tostring(footer.isShown))
    return okAdd and okFin
end

function MailFooter.Install()
    for _, name in ipairs(MailFooter.TARGETS) do
        local frame = rawget(_G, name)
        if not hooked[name] and type(frame) == "table" and type(frame.FocusGamepad) == "function" then
            local ok, err = pcall(hooksecurefunc, frame, "FocusGamepad", function() MailFooter.Ensure(name) end)
            hooked[name] = ok
            ns.Log.Add("footer", "hook %s:FocusGamepad %s", name, ok and "ok" or tostring(err))
        end
        if hooked[name] then MailFooter.Ensure(name) end
    end
end

ns.On("PLAYER_LOGIN", function() MailFooter.Install() end)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_MailFrame" then MailFooter.Install() end
end)
ns.On("MAIL_SHOW", function() MailFooter.Install() end)
ns.On("INPUT_DEVICE_INTERFACE_TRANSITION", function()
    for _, name in ipairs(MailFooter.TARGETS) do
        if hooked[name] then MailFooter.Ensure(name) end
    end
end)
