-- Self-test log: every hook, press, attach, send and mail event is written here
-- (account-wide, so the bank alt's report holds the whole session).
local _, ns = ...

local Log = {}
ns.Log = Log

Log.MAX = 400

function Log.Add(area, fmt, ...)
    local st = MailworthyDB and MailworthyDB.selftest
    if not st then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    st.log[#st.log + 1] = string.format("%s %s [%s] %s", date("%H:%M:%S"), ns.PlayerName and ns.PlayerName() or "?",
        area, msg)
    while #st.log > Log.MAX do table.remove(st.log, 1) end
end

function Log.Lines()
    local st = MailworthyDB and MailworthyDB.selftest
    return st and st.log or {}
end
