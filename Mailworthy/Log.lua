-- Diagnostics log for /mw report: hooks, presses, locks, sends and mail events
-- (account-wide, so a report from the bank alt holds the main's session too).
local _, ns = ...

local Log = {}
ns.Log = Log

Log.MAX = 300

function Log.Add(area, fmt, ...)
    local log = MailworthyDB and MailworthyDB.log
    if type(log) ~= "table" then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    log[#log + 1] = string.format("%s %s [%s] %s", date("%H:%M:%S"), ns.PlayerName and ns.PlayerName() or "?",
        area, msg)
    while #log > Log.MAX do table.remove(log, 1) end
end

function Log.Lines()
    return MailworthyDB and type(MailworthyDB.log) == "table" and MailworthyDB.log or {}
end
