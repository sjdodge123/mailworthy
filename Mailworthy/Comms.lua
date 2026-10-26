-- Addon messages between Mailworthy users (C_ChatInfo, prefix "Mailworthy"), so a
-- binding can offer "to their bank alt" and the friends window can mark who
-- runs Mailworthy and what they craft. Each Mailworthy says hello to its guild
-- and group at login, when the group changes, when its bank alt changes, and
-- when another Mailworthy asks (the friends window asks when it opens):
--
--   H1|<bank alt or empty>|<profession skill lines, comma separated>
--   A1                                                   (ask: please say hello)
--
-- What arrives is data from other players, never instructions: names are
-- cleaned and length-checked, professions must be crafting skill lines
-- Mailworthy knows, anything else is dropped. Peers are kept per realm +
-- faction in MailworthyDB.peers for PEER_DAYS. Switch: /mw feature comms off.
-- The API is Forever's documented C_ChatInfo (RegisterAddonMessagePrefix,
-- SendAddonMessage, CHAT_MSG_ADDON); unseen in game yet (README "Beta unknowns").
local _, ns = ...

local Comms = {}
ns.Comms = Comms

Comms.PREFIX = "Mailworthy"
Comms.VERSION = 1
Comms.PEER_DAYS = 60
Comms.HELLO_DELAY = 8      -- seconds after login (the guild roster and group are in by then)
Comms.THROTTLE = 10        -- seconds between hellos
Comms.ASK_THROTTLE = 30    -- seconds between asks
Comms.MAX_NAME = 48

local lastHello, lastAsk, pendingHello = -math.huge, -math.huge, false

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function now() return call(GetTime) or 0 end
local function serverTime() return call(GetServerTime) or time() end

local function realmKey()
    local _, realm, faction = ns.Characters.Current()
    return tostring(realm) .. "|" .. tostring(faction)
end

local function store()
    MailworthyDB.peers = type(MailworthyDB.peers) == "table" and MailworthyDB.peers or {}
    local key = realmKey()
    MailworthyDB.peers[key] = type(MailworthyDB.peers[key]) == "table" and MailworthyDB.peers[key] or {}
    return MailworthyDB.peers[key]
end

function Comms.On() return ns.Features.On("comms") end

--- Pure: this character's hello: bank alt (unless this character is it) and crafting professions.
function Comms.Encode(bankAlt, professions)
    local ids = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine or p)
        if id and ns.Valuation.PROFESSION_MATS[id] then ids[#ids + 1] = tostring(id) end
    end
    table.sort(ids)
    local alt = tostring(bankAlt or ""):gsub("|", "")
    return string.format("H%d|%s|%s", Comms.VERSION, alt, table.concat(ids, ","))
end

--- Pure: a message from another Mailworthy, or nil. { kind = "hello", version, bankAlt,
--- professions = { ids } } or { kind = "ask", version }.
function Comms.Decode(text)
    if type(text) ~= "string" or #text > 255 then return nil end
    local kind, version, rest = text:match("^(%a)(%d+)|?(.*)$")
    if kind == "A" then return { kind = "ask", version = tonumber(version) } end
    if kind ~= "H" then return nil end
    local alt, profs = rest:match("^([^|]*)|?([%d,]*)$")
    if alt == nil then return nil end
    alt = ns.Routes.Clean(alt)
    if alt and (#alt > Comms.MAX_NAME or alt:find("%c")) then alt = nil end
    local ids = {}
    for id in tostring(profs):gmatch("%d+") do
        if ns.Routes.ProfessionName(tonumber(id)) then ids[#ids + 1] = tonumber(id) end
    end
    return { kind = "hello", version = tonumber(version), bankAlt = alt, professions = ids }
end

local function channels()
    local list = {}
    if call(IsInGuild) == true then list[#list + 1] = "GUILD" end
    local n = tonumber((call(GetNumGroupMembers))) or 0
    if n > 0 then list[#list + 1] = call(IsInRaid) == true and "RAID" or "PARTY" end
    return list
end

local function send(message)
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return false end
    local sent = false
    for _, channel in ipairs(channels()) do
        local ok, result = pcall(chat.SendAddonMessage, Comms.PREFIX, message, channel)
        sent = sent or ok
        ns.Log.Add("comms", "%s on %s: %s", message:sub(1, 2), channel, ok and tostring(result) or ("error " .. tostring(result)))
    end
    return sent
end

--- Say hello to the guild and group (throttled; the next tick sends a hello that was throttled).
function Comms.Announce(reason)
    if not Comms.On() then return false end
    if now() - lastHello < Comms.THROTTLE then
        pendingHello = true
        return false
    end
    lastHello, pendingHello = now(), false
    local bankAlt = not ns.Config.IsBankAltHere() and ns.Config.BankAlt() or nil
    ns.Log.Add("comms", "hello (%s)", tostring(reason))
    return send(Comms.Encode(bankAlt, ns.Characters.Professions()))
end

--- Ask other Mailworthys to say hello (the friends window, throttled).
function Comms.Ask()
    if not Comms.On() or now() - lastAsk < Comms.ASK_THROTTLE then return false end
    lastAsk = now()
    return send(string.format("A%d", Comms.VERSION))
end

--- Peers heard from on this realm + faction: lower-case name -> { name, bankAlt, professions, version, at }.
function Comms.Peers()
    return store()
end

function Comms.Peer(name)
    name = ns.Routes.Clean(name)
    return name and store()[name:lower()] or nil
end

--- Record a hello from `sender` (a name, possibly with a realm suffix).
function Comms.Hear(sender, text)
    local msg = Comms.Decode(text)
    local name = ns.Routes.Clean(sender)
    if not msg or not name or #name > Comms.MAX_NAME or name:find("%c") then return nil end
    if name:lower() == tostring(ns.PlayerName()):lower() then return nil end
    if msg.kind == "ask" then
        Comms.Announce("asked by " .. name)
        return msg
    end
    local peer = { name = name, bankAlt = msg.bankAlt, professions = msg.professions, version = msg.version, at = serverTime() }
    if peer.bankAlt and peer.bankAlt:lower() == name:lower() then peer.bankAlt = nil end
    store()[name:lower()] = peer
    ns.Log.Add("comms", "hello from %s: bank alt %s, professions %s", name, tostring(peer.bankAlt or "none"),
        #peer.professions > 0 and table.concat(peer.professions, ",") or "none")
    return peer
end

--- Drop peers not heard from in PEER_DAYS.
function Comms.Prune(at)
    at = at or serverTime()
    for key, peer in pairs(store()) do
        if type(peer) ~= "table" or (tonumber(peer.at) or 0) < at - Comms.PEER_DAYS * 86400 then store()[key] = nil end
    end
end

--- One line per peer for /mw report.
function Comms.ReportLines()
    local lines = {}
    for _, peer in pairs(store()) do
        local profs = {}
        for _, id in ipairs(peer.professions or {}) do profs[#profs + 1] = ns.Routes.ProfessionName(id) or tostring(id) end
        lines[#lines + 1] = string.format("mailworthy peer: %s (bank alt %s, %s, heard %s)", tostring(peer.name),
            tostring(peer.bankAlt or "none"), #profs > 0 and table.concat(profs, ", ") or "no crafting profession",
            date("%b %d", peer.at or 0))
    end
    table.sort(lines)
    return lines
end

function Comms.Register()
    if not Comms.On() then return end
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return end
    local ok, result = pcall(chat.RegisterAddonMessagePrefix, Comms.PREFIX)
    ns.Log.Add("comms", "prefix registered: %s", ok and tostring(result) or ("error " .. tostring(result)))
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
    if prefix ~= Comms.PREFIX or not Comms.On() then return end
    Comms.Hear(sender, text)
end)

ns.On("PLAYER_LOGIN", function()
    Comms.Register()
    Comms.Prune()
    if not Comms.On() then return end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(Comms.HELLO_DELAY, function() pcall(Comms.Announce, "login") end)
    end
end)

ns.On("GROUP_ROSTER_UPDATE", function()
    if tonumber((call(GetNumGroupMembers))) and tonumber((call(GetNumGroupMembers))) > 0 then Comms.Announce("group") end
end)

-- A hello the throttle held back goes out at the next mailbox (a natural moment to be known).
ns.On("MAIL_SHOW", function()
    if pendingHello then Comms.Announce("pending") end
end)
