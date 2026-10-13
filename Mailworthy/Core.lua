-- Mailworthy: namespace, saved variables, events and slash commands.
-- The design (entry points, decision rule, phases) is in docs/PLAN.md; this
-- discovery build carries the pieces docs/DISCOVERY-SESSION-2.md tests.
local addonName, ns = ...

ns.NAME = addonName
ns.VERSION = "@project-version@" -- the packager substitutes the release tag (also ## Version in the .toc)

function ns.Print(msg)
    print("|cff33ff99Mailworthy|r: " .. tostring(msg))
end

function ns.Init()
    MailworthyDB = type(MailworthyDB) == "table" and MailworthyDB or {}
    MailworthyCharDB = type(MailworthyCharDB) == "table" and MailworthyCharDB or {}
    MailworthyDB.blocked = MailworthyDB.blocked or {}
    MailworthyDB.characters = MailworthyDB.characters or {}
    MailworthyDB.selftest = MailworthyDB.selftest or {}
    local st = MailworthyDB.selftest
    st.log = st.log or {}
    st.answers = st.answers or {}
    st.loads = st.loads or {}
    MailworthyCharDB.lockedSlots = MailworthyCharDB.lockedSlots or {}
    MailworthyDB.features = MailworthyDB.features or {}
end

-- Kill switches for each piece that touches Blizzard UI, so a problem in game
-- can be isolated with /mw feature <name> off + /reload instead of a new build.
ns.Features = { DEFAULTS = { lockMenu = true, mailButton = true } }

function ns.Features.On(name)
    local saved = MailworthyDB and MailworthyDB.features and MailworthyDB.features[name]
    if saved == nil then return ns.Features.DEFAULTS[name] == true end
    return saved
end

local function featureCommand(rest)
    local name, value = rest:match("^(%S+)%s+(%S+)$")
    local known
    for key in pairs(ns.Features.DEFAULTS) do
        if name and key:lower() == name:lower() then known = key end
    end
    if not known or (value ~= "on" and value ~= "off") then
        local list = {}
        for key in pairs(ns.Features.DEFAULTS) do list[#list + 1] = key .. "=" .. (ns.Features.On(key) and "on" or "off") end
        table.sort(list)
        ns.Print("Usage: /mw feature <name> on|off (then /reload). Now: " .. table.concat(list, ", "))
        return
    end
    MailworthyDB.features[known] = value == "on"
    ns.Log.Add("feature", "%s %s", known, value)
    ns.Print(known .. " " .. value .. ". /reload to apply.")
end

-- Event dispatch: modules register handlers with ns.On(event, fn).
local handlers = {}
local events = CreateFrame("Frame")
ns.eventFrame = events

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(events.RegisterEvent, events, event)
    end
    table.insert(handlers[event], fn)
end

function ns.Fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok and ns.Log then ns.Log.Add("error", "%s handler: %s", event, tostring(err)) end
    end
end

events:SetScript("OnEvent", function(_, event, ...) ns.Fire(event, ...) end)

ns.On("ADDON_LOADED", function(name)
    if name == addonName then ns.Init() end
end)

local HELP = {
    "At a mailbox: the Mailworthy button on the mail window opens the self-test (mouse, or D-pad + Cross).",
    "Triangle (Y) on a bag item: Mailworthy: Lock slot / Unlock slot.",
    "/mw selftest - open the self-test window",
    "/mw selftest report - the copyable report (paste it to the addon developer)",
    "/mw locks - list this character's locked slots",
    "/mw feature <lockMenu|mailButton> on|off - switch a piece off to isolate a problem (then /reload)",
}

local function showHelp()
    ns.Print("v" .. ns.VERSION .. " (discovery build) - commands (/mw or /mailworthy):")
    for _, line in ipairs(HELP) do print("  " .. line) end
end

function ns.HandleSlash(msg)
    ns.lastCommand = "/mw " .. tostring(msg or "")
    local cmd, rest = string.match(string.lower(msg or ""), "^%s*(%S*)%s*(.-)%s*$")
    if cmd == "selftest" and rest == "report" then
        ns.SelfTest.ShowReport()
    elseif cmd == "selftest" then
        ns.SelfTest.Open("slash")
    elseif cmd == "feature" then
        featureCommand(rest)
    elseif cmd == "locks" then
        ns.Locks.PrintList()
    else
        showHelp()
    end
end

SLASH_MAILWORTHY1 = "/mw"
SLASH_MAILWORTHY2 = "/mailworthy"
SlashCmdList.MAILWORTHY = function(msg) ns.HandleSlash(msg) end
