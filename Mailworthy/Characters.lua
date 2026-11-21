-- Known characters (account-wide): every character that logs in with Mailworthy
-- is recorded, so the bank alt is picked from a list instead of typed. Mail
-- can't cross realm or faction, so only same realm + faction are offered.
local _, ns = ...

local Characters = {}
ns.Characters = Characters

local call = ns.Util.Call

--- "First Surname" on Forever (no realm suffix).
function ns.PlayerName()
    return call(GetUnitName, "player", true) or call(UnitName, "player")
end

--- Pure: a name with its spaces collapsed and trimmed, or nil (not a string, empty). Forever names
--- are "First Surname". (Config.Clean.)
function Characters.CleanSpaces(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
end

--- Pure: a player name as mail wants it: spaces collapsed, any "-Realm" suffix dropped (guild
--- rosters and addon messages carry one; a Forever name never has a hyphen). (Routes.Clean.)
function Characters.Clean(name)
    name = Characters.CleanSpaces(name)
    if not name then return nil end
    name = name:match("^([^%-]+)") or name
    return Characters.CleanSpaces(name)
end

function Characters.Key(name, realm, faction)
    return string.format("%s|%s|%s", tostring(name), tostring(realm), tostring(faction))
end

-- The realm ----------------------------------------------------------------------------
-- Everything saved per realm (the bank alt, the account's bindings, the mail ledger, the
-- guild template, friends heard from) hangs off the realm's name, so a blank one is never
-- a realm (another addon's author, 2026-11-20: since a client patch `GetRealmName()`
-- returned ""; every character then started an empty "realm", and two realms shared it).
-- Characters.Realm asks, in order:
--   1. the game: `GetRealmName()`, when it is a non-empty string. Only this is ever saved:
--      for the character (MailworthyCharDB.realm) and, with the server ID in its GUID
--      (`Player-<serverID>-<id>`), for the server (MailworthyDB.realmIDs);
--   2. the realm the game last named for this character (MailworthyCharDB.realm);
--   3. the realm the game named for another character with this server ID (realmIDs);
--   4. the account's recorded characters: the one realm this name and faction is known on
--      (what an older Mailworthy saved, before 2. existed), unless that record is known to
--      be of another server, or was itself made from a server ID (`guess`). Only with a
--      server ID of its own: without one a namesake can't be told from the recorded one;
--   5. a placeholder, a realm of its own, so unnamed realms never share a bank alt:
--      "#<serverID>" for a server ID not known to stand for two realms, else one for this
--      character alone: "#<GUID>", or without a GUID "#?<token>", a token kept in this
--      character's own saved variables (MailworthyCharDB.realmToken); nil before those load.
-- A server ID the game named two realms for is never trusted again (realmIDs[id] = false):
-- what was recorded from it is forgotten, and it rules out 3. and 4. (a namesake on the
-- other realm). Nothing found by 3. to 5. is saved as a fact.
-- The answer holds while a mailbox is open and while a mail run is on or waits for the
-- game's answer, through the handlers of the event that ends either: what was previewed,
-- sent and logged in one visit is one realm's.
Characters.PLACEHOLDER = "#"
Characters.REALM_SOURCES = {
    game = "the game", saved = "this character's last login", server = "the server ID",
    characters = "this account's characters", placeholder = "a placeholder (no realm known)", unknown = "unknown",
}

--- Pure: a non-empty string, or nil (a blank realm name is no answer).
local function named(v) return type(v) == "string" and v ~= "" and v or nil end

--- Pure: is `realm` a placeholder ("#91"), not a name?
function Characters.IsPlaceholder(realm)
    return type(realm) == "string" and realm:sub(1, 1) == Characters.PLACEHOLDER
end

--- The server ID in this character's GUID ("91" of "Player-91-0ABCDEF0"), or nil.
function Characters.ServerID()
    local guid = call(UnitGUID, "player")
    return type(guid) == "string" and guid:match("^Player%-(%d+)%-%x+$") or nil
end

--- The game named `realm` for this character: remember it, and its server ID's realm.
local function learn(realm, id)
    if type(MailworthyCharDB) == "table" and MailworthyCharDB.realm ~= realm then MailworthyCharDB.realm = realm end
    if not id or type(MailworthyDB) ~= "table" then return end
    local ids = ns.Util.Store(MailworthyDB, "realmIDs")
    if ids[id] == nil then
        ids[id] = realm
    elseif ids[id] ~= realm and ids[id] ~= false then
        ids[id] = false -- one server ID, two realms: it doesn't name a realm
        -- What was recorded on its word is forgotten (Characters.Record's `guess`).
        local characters = ns.Util.Table(MailworthyDB.characters)
        for key, e in pairs(characters) do
            if type(e) == "table" and e.guess == id then characters[key] = nil end
        end
        ns.Log.Add("chars", "server ID %s seen on two realms: no longer used to find the realm", tostring(id))
    end
end

--- The one named realm the account's recorded characters know this name and faction on, or nil
--- (none, or more than one). Never a record of another server, or one made from a server ID; nor
--- a realm the game has named for another server ID than `id` (an old record carries no server ID
--- of its own, but its realm may have one by now: Codex review, fourth pass).
local function fromCharacters(id)
    local name, faction = ns.PlayerName(), call(UnitFactionGroup, "player")
    if not name or not faction or type(MailworthyDB) ~= "table" then return nil end
    local elsewhere = {} -- realm -> true: the game named it for another server ID
    for other, realm in pairs(ns.Util.Table(MailworthyDB.realmIDs)) do
        if other ~= id and named(realm) then elsewhere[realm] = true end
    end
    local found
    for _, e in pairs(ns.Util.Table(MailworthyDB.characters)) do
        if type(e) == "table" and e.name == name and e.faction == faction and not e.guess
            and (e.server == nil or e.server == id) then
            local realm = named(e.realm)
            if realm and not Characters.IsPlaceholder(realm) and not elsewhere[realm] then
                if found and found ~= realm then return nil end
                found = realm
            end
        end
    end
    return found
end

local function resolve()
    local id = Characters.ServerID()
    local realm = named(call(GetRealmName))
    if realm then
        learn(realm, id)
        return realm, "game"
    end
    realm = type(MailworthyCharDB) == "table" and named(MailworthyCharDB.realm) or nil
    if realm then return realm, "saved" end
    local known
    if id and type(MailworthyDB) == "table" then known = ns.Util.Table(MailworthyDB.realmIDs)[id] end
    if named(known) then return known, "server" end
    local P = Characters.PLACEHOLDER
    if id and known ~= false then
        -- Not on a server ID known to stand for two realms: a namesake there may be on the other
        -- one, and a record's matching server ID then says nothing (Codex review, second pass). Not
        -- without a server ID either: nothing then tells this character from a namesake (third pass).
        realm = fromCharacters(id)
        if realm then return realm, "characters" end
        return P .. id, "placeholder"
    end
    -- No server ID, or one that stands for two realms: a realm of this character alone.
    local guid = named(call(UnitGUID, "player"))
    if guid then return P .. guid, "placeholder" end
    -- No GUID either: a token of this character's own saved variables (a name can have a namesake
    -- on another realm; Codex review, second pass).
    if type(MailworthyCharDB) ~= "table" then return nil, "unknown" end
    if not named(MailworthyCharDB.realmToken) then
        MailworthyCharDB.realmToken = string.format("%d-%06d", ns.Util.Now(), math.random(0, 999999))
    end
    return P .. "?" .. MailworthyCharDB.realmToken, "placeholder"
end

local held       -- { realm, source }: the last answer
local atMailbox  -- a mailbox is open (MAIL_SHOW .. after MAIL_CLOSED's handlers)
local settling   -- a mail's answer is being handled (through MAIL_SEND_SUCCESS's handlers)

--- Is a mail run on, or a mail of a stopped run still with the game?
local function mailing()
    local mailer = ns.Mailer
    return mailer ~= nil and (mailer.Busy() or (type(mailer.state) == "table" and mailer.state.pending ~= nil))
end

--- Does the last answer hold (a mailbox visit, a mail run, a mail still with the game)?
local function holding()
    return held ~= nil and (atMailbox or settling or mailing()) and true or false
end

--- This character's realm (the key its realm's saved data is kept under) and where it came from
--- (a key of Characters.REALM_SOURCES): see the list above. nil, "unknown" when nothing is known.
function Characters.Realm()
    if holding() then return held[1], held[2] end
    local realm, source = resolve()
    held = { realm, source }
    return realm, source
end

--- A new login, or the mailbox closed: the realm is asked again.
function Characters.ReleaseRealm() atMailbox, settling, held = false, false, nil end

ns.On("MAIL_SHOW", function()
    if mailing() and held then -- a mail of the last visit is still with the game: its realm stands
        atMailbox = true
        return
    end
    atMailbox, held = false, nil
    Characters.Realm()
    atMailbox = true
end)
-- Released once every MAIL_CLOSED handler has run (the ledger commits its pending takes there).
ns.On("MAIL_CLOSED", function() ns.AfterEvent(function() atMailbox = false end) end)
-- This file loads before Mailer.lua, so this runs first: the mail the game just confirmed is
-- credited by the mailer's handler, which clears its "busy" / "pending" before it writes the ledger.
ns.On("MAIL_SEND_SUCCESS", function()
    if not holding() then return end
    settling = true
    ns.AfterEvent(function() settling = false end)
end)

--- "the game says "X"" / "the game gives no realm name (""): using X, from this character's last
--- login; server ID 91", for /mw report.
function Characters.RealmText()
    local raw = call(GetRealmName)
    local realm, source = Characters.Realm()
    local id = Characters.ServerID()
    local said = named(raw) and string.format("the game says %q", raw)
        or string.format("the game gives no realm name (%s)", type(raw) == "string" and string.format("%q", raw) or tostring(raw))
    local using = (source == "game" and realm == raw) and "" or string.format(": using %s, from %s", tostring(realm),
        Characters.REALM_SOURCES[source] or tostring(source))
    return string.format("%s%s; server ID %s", said, using, tostring(id or "unknown"))
end

function Characters.Current()
    return ns.PlayerName(), (Characters.Realm()), call(UnitFactionGroup, "player")
end

local function professions()
    local list = {}
    for _, index in ipairs({ call(GetProfessions) }) do
        local name, _, rank, maxRank, _, _, skillLine = call(GetProfessionInfo, index)
        if name then list[#list + 1] = { name = name, rank = rank, maxRank = maxRank, skillLine = skillLine } end
    end
    return list
end

--- This character's professions right now: { { name, rank, maxRank, skillLine }, ... }.
function Characters.Professions() return professions() end

function Characters.Describe(entry)
    local profs = {}
    for _, p in ipairs(entry.professions or {}) do
        profs[#profs + 1] = string.format("%s %s/%s", tostring(p.name), tostring(p.rank), tostring(p.maxRank))
    end
    return string.format("%s (%s, %s) %s level %s, professions: %s", tostring(entry.name), tostring(entry.realm),
        tostring(entry.faction), tostring(entry.class), tostring(entry.level),
        #profs > 0 and table.concat(profs, ", ") or "none")
end

function Characters.Record()
    local name, realm, faction = Characters.Current()
    if not name or not realm or not faction then return end
    local _, class = call(UnitClass, "player")
    local entry = {
        name = name, realm = realm, faction = faction, class = class, level = call(UnitLevel, "player"),
        professions = professions(), lastSeen = ns.Util.Now(),
    }
    -- Where the realm came from (Characters.Realm): `server` is the GUID's server ID when the game
    -- named the realm for this character (now or before), else what the record already said;
    -- `guess` marks a realm taken from the server ID alone, which never vouches for another character.
    local key = Characters.Key(name, realm, faction)
    local _, source = Characters.Realm()
    local id, old = Characters.ServerID(), MailworthyDB.characters[key]
    entry.server = type(old) == "table" and old.server or nil
    -- A login without a GUID never erases the server ID the record has (Codex review, third pass).
    if id and (source == "game" or source == "saved") then entry.server = id end
    if source == "server" then entry.guess = id end
    MailworthyDB.characters[key] = entry
    ns.Log.Add("chars", "recorded %s", Characters.Describe(entry))
    return entry
end

--- Characters this one can mail: same realm and faction, not itself, by name.
function Characters.Mailable()
    local name, realm, faction = Characters.Current()
    local list = {}
    for _, entry in pairs(MailworthyDB and MailworthyDB.characters or {}) do
        if entry.realm == realm and entry.faction == faction and entry.name ~= name then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return list
end

ns.On("PLAYER_LOGIN", function()
    Characters.ReleaseRealm()
    Characters.Record()
end)
