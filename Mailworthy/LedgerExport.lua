-- Mail ledger, the export and the report (Ledger.lua's header has the whole story): the whole log as
-- text for the copy box (/mw ledger's Export log) and one count line for /mw report.
local _, ns = ...

local Ledger = ns.Ledger
local tableOr = ns.Util.Table
local store = Ledger.Store
local money = Ledger.internal.money

-- Export and report ---------------------------------------------------------------------

local function itemText(it)
    local value = it.value and money(it.value) or "no price"
    if it.source == "sender" then value = value .. ", sender's value"
    elseif it.source == "capped" then value = value .. ", capped at " .. Ledger.PRICE_CAP .. "x my price"
    elseif it.source == "fresher" then value = value .. ", my price: my scan was more up to date"
    elseif it.source == "agreed" then
        value = value .. string.format(", agreed with %s (mine said %s)", tostring(it.agreed), money(it.mine or 0))
    end
    if it.value and tonumber(it.age) then
        value = value .. string.format(", scan %d day%s old", it.age, it.age == 1 and "" or "s")
    end
    return string.format("%dx %s (item %s, %s)", it.count or 1, tostring(it.name), tostring(it.itemID), value)
end

--- Pure: one log line.
function Ledger.LineText(e)
    local stamp = date("%Y-%m-%d %H:%M", tonumber(e.at) or 0)
    if e.dir == "paid" then
        return string.format("%s  MARKED PAID  %s: %s set back to zero by %s", stamp, tostring(e.other),
            money(e.money), tostring(e.char))
    end
    local from, to = e.char, e.other
    if e.dir == "received" then from, to = e.other, e.char end
    local parts = {}
    for _, it in ipairs(e.items or {}) do parts[#parts + 1] = itemText(it) end
    if (tonumber(e.money) or 0) > 0 then parts[#parts + 1] = money(e.money) .. " gold" end
    local flags = {}
    if e.via == "Mailworthy" then flags[#flags + 1] = "sent by Mailworthy" end
    if e.scope == "guild" and type(e.guild) == "table" then
        flags[#flags + 1] = "guild rule: " .. tostring(ns.Routes.ProfessionName(e.guild.profession) or e.guild.profession)
    end
    if (tonumber(e.cod) or 0) > 0 then flags[#flags + 1] = "COD " .. money(e.cod) end
    if e.returned then flags[#flags + 1] = "returned mail" end
    if e.own then flags[#flags + 1] = "own character" end
    if e.system then flags[#flags + 1] = "system mail" end
    return string.format("%s  %-8s  %s -> %s  \"%s\"  %s%s", stamp, e.dir == "sent" and "SENT" or "RECEIVED",
        tostring(from), tostring(to), tostring(e.subject or ""), #parts > 0 and table.concat(parts, ", ") or "nothing",
        #flags > 0 and ("  [" .. table.concat(flags, "; ") .. "]") or "")
end

--- The whole log as text for the copy box, oldest first.
function Ledger.ExportText()
    local _, realm, faction = ns.Characters.Current()
    local log = store().log
    local lines = {
        string.format("Mailworthy %s mail log, %s %s, exported %s by %s", ns.VERSION, tostring(realm), tostring(faction),
            date("%Y-%m-%d %H:%M"), tostring(ns.PlayerName())),
        string.format("%d entries (the newest %d are kept). Values: copper per stack at the time of the mail.",
            #log, Ledger.LOG_MAX),
        "",
    }
    for _, e in ipairs(log) do lines[#lines + 1] = Ledger.LineText(e) end
    if #log == 0 then lines[#lines + 1] = "Nothing mailed or received yet." end
    return table.concat(lines, "\n")
end

--- For /mw report: counts only, never names or balances.
function Ledger.ReportLines()
    local s, outbox, expect, players = store(), 0, 0, 0
    for _, list in pairs(s.outbox) do outbox = outbox + #tableOr(list) end
    for _, list in pairs(s.expect) do expect = expect + #tableOr(list) end
    for _ in pairs(s.players) do players = players + 1 end
    return { string.format("ledger: %s, %d log entries, %d players, %d mail(s) of values waiting to go, %d values "
        .. "received, %d take(s) unconfirmed", Ledger.On() and "on" or "off", #s.log, players, outbox, expect,
        (Ledger.Pending())) }
end
