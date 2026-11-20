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
--   1. the game: `GetRealmName()`, when it is a non-empty string;
--   2. the realm this character was last seen on (MailworthyCharDB.realm);
--   3. the account's recorded characters: the one realm this name and faction is known on
--      (saved by an older Mailworthy, before 2. existed);
--   4. the server ID in the character's GUID (`Player-<serverID>-<id>`), for a realm this
--      account has seen with that ID (MailworthyDB.realmIDs);
--   5. a placeholder, "#<serverID>": a realm of its own, so two unnamed realms never share
--      a bank alt; then nil (nothing known: the callers' "nil" key, as before).
-- A server ID seen with two realm names is never trusted again (realmIDs[id] = false).
Characters.PLACEHOLDER = "#"
Characters.REALM_SOURCES = {
    game = "the game", saved = "this character's last login", characters = "this account's characters",
    server = "the server ID", placeholder = "a placeholder for the server ID", unknown = "unknown",
}

--- Pure: a non-empty string, or nil (a blank realm name is no answer).
local function named(v) return type(v) == "string" and v ~= "" and v or nil end

--- Pure: is `realm` a placeholder for a server ID ("#91"), not a name?
function Characters.IsPlaceholder(realm)
    return type(realm) == "string" and realm:sub(1, 1) == Characters.PLACEHOLDER
end

--- The server ID in this character's GUID ("91" of "Player-91-0ABCDEF0"), or nil.
function Characters.ServerID()
    local guid = call(UnitGUID, "player")
    return type(guid) == "string" and guid:match("^Player%-(%d+)%-%x+$") or nil
end

--- Remember `realm` for this character (`keep`) and, with a server ID, for its server.
local function learn(realm, id, keep)
    if keep and type(MailworthyCharDB) == "table" and MailworthyCharDB.realm ~= realm then MailworthyCharDB.realm = realm end
    if not id or type(MailworthyDB) ~= "table" then return end
    local ids = ns.Util.Store(MailworthyDB, "realmIDs")
    if ids[id] == nil then
        ids[id] = realm
    elseif ids[id] ~= realm and ids[id] ~= false then
        ids[id] = false -- one server ID, two realms: it doesn't name a realm
        ns.Log.Add("chars", "server ID %s seen on two realms: no longer used to find the realm", tostring(id))
    end
end

--- The one named realm the account's recorded characters know this name and faction on, or nil
--- (none, or more than one).
local function fromCharacters()
    local name, faction = ns.PlayerName(), call(UnitFactionGroup, "player")
    if not name or not faction or type(MailworthyDB) ~= "table" then return nil end
    local found
    for _, e in pairs(ns.Util.Table(MailworthyDB.characters)) do
        if type(e) == "table" and e.name == name and e.faction == faction then
            local realm = named(e.realm)
            if realm and not Characters.IsPlaceholder(realm) then
                if found and found ~= realm then return nil end
                found = realm
            end
        end
    end
    return found
end

--- This character's realm (the key its realm's saved data is kept under) and where it came from
--- (a key of Characters.REALM_SOURCES): see the list above. nil, "unknown" when nothing is known.
function Characters.Realm()
    local id = Characters.ServerID()
    local realm = named(call(GetRealmName))
    if realm then
        learn(realm, id, true)
        return realm, "game"
    end
    realm = type(MailworthyCharDB) == "table" and named(MailworthyCharDB.realm) or nil
    if realm then
        learn(realm, id, true)
        return realm, "saved"
    end
    realm = fromCharacters()
    if realm then
        learn(realm, id, true)
        return realm, "characters"
    end
    -- Not kept for the character: read again each time, so a server ID that turns out to stand for
    -- two realms stops answering.
    realm = id and type(MailworthyDB) == "table" and named(ns.Util.Table(MailworthyDB.realmIDs)[id]) or nil
    if realm then return realm, "server" end
    if id then return Characters.PLACEHOLDER .. id, "placeholder" end
    return nil, "unknown"
end

--- "the game says "X"" / "the game gives no realm name (""): using X, from this character's last
--- login; server ID 91", for /mw report.
function Characters.RealmText()
    local raw = call(GetRealmName)
    local realm, source = Characters.Realm()
    local id = Characters.ServerID()
    local said = named(raw) and string.format("the game says %q", raw)
        or string.format("the game gives no realm name (%s)", type(raw) == "string" and string.format("%q", raw) or tostring(raw))
    local using = source == "game" and "" or string.format(": using %s, from %s", tostring(realm),
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
    MailworthyDB.characters[Characters.Key(name, realm, faction)] = entry
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

ns.On("PLAYER_LOGIN", function() Characters.Record() end)
