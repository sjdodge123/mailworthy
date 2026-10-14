-- Records "Mailworthy has been blocked from an action only available to the
-- Blizzard UI". The game names the blocked function in ADDON_ACTION_FORBIDDEN /
-- ADDON_ACTION_BLOCKED; we keep it with the command that preceded it so a tester
-- can report it. (From LedgerLink, where a gamepad SetFocus crash was found this way.)
local addonName, ns = ...

local Blocked = {}
ns.Blocked = Blocked

Blocked.MAX = 10
local told = false -- one chat line per session; the rest go to /mw report

function Blocked.OnEvent(event, blockedAddon, fn)
    if blockedAddon ~= addonName then return end
    MailworthyDB.blocked = MailworthyDB.blocked or {}
    local list = MailworthyDB.blocked
    list[#list + 1] = {
        event = event, fn = tostring(fn), at = time(), after = ns.lastCommand or "(no command yet)", version = ns.VERSION,
    }
    while #list > Blocked.MAX do table.remove(list, 1) end
    if ns.Log then ns.Log.Add("blocked", "%s %s after %s", event, tostring(fn), list[#list].after) end
    if not told then
        told = true
        ns.Print(string.format("The game blocked %s (after %s). Please send /mw report to the addon developer.",
            tostring(fn), list[#list].after))
    end
end

--- Report lines for the recorded blocks, oldest first.
function Blocked.Lines()
    local lines = {}
    for _, b in ipairs(MailworthyDB and MailworthyDB.blocked or {}) do
        lines[#lines + 1] = string.format("blocked: %s %s after %s at %s (%s)",
            b.event, b.fn, b.after, date("%Y-%m-%d %H:%M:%S", b.at), b.version or "older build")
    end
    return lines
end

local frame = CreateFrame("Frame")
Blocked.frame = frame
for _, event in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, blockedAddon, fn)
    if MailworthyDB then Blocked.OnEvent(event, blockedAddon, fn) end
end)
