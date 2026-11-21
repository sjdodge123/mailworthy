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
--      (`Player-<serverID>-<id>`), for the server (MailworthyDB.realmIDs) and the realm
--      (MailworthyDB.realmServers);
--   2. the realm the game last named for this character (MailworthyCharDB.realm), which also
--      teaches the server and realm tables its server ID when that is only known now;
--   3. the realm the game named for another character with this server ID (realmIDs);
--   4. the account's recorded characters: the one realm this name and faction is known on
--      (what an older Mailworthy saved, before 2. existed), unless that record or its realm
--      is known to be of another server, or it was itself made from a server ID (`guess`). Only with a
--      server ID of its own: without one a namesake can't be told from the recorded one;
--   4b. what those characters vouch for: a character found by 4. says which realm its
--      server ID is on (MailworthyDB.realmGuesses), so a character never seen there finds
--      the realm too, and one whose name is recorded on several realms finds its own. On a client
--      that never names the realm nothing else could tell it
--      (operator, 2026-11-20, after build 71037 was read giving "": "Yes, fix it"). A guess,
--      never a fact: two characters vouching for different realms end it (false), the
--      game's own name replaces it, and a character found this way vouches for nothing;
--   5. a placeholder, a realm of its own, so unnamed realms never share a bank alt:
--      "#<serverID>" for a server ID not known to stand for two realms, else one for this
--      character alone: "#<GUID>", or without a whole GUID "#?<token>", a token kept in this
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
    characters = "this account's characters", siblings = "your other characters on this server",
    placeholder = "a placeholder (no realm known)", unknown = "unknown",
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

--- Forget the records made on a server ID's word (Characters.Record's `guess`), except those on `keep`.
local function forgetGuessed(id, keep)
    local characters = ns.Util.Table(MailworthyDB.characters)
    for key, e in pairs(characters) do
        if type(e) == "table" and e.guess == id and e.realm ~= keep then characters[key] = nil end
    end
end

--- The game named `realm` for this character: remember it, and its server ID's realm.
local function learn(realm, id)
    if type(MailworthyCharDB) == "table" and MailworthyCharDB.realm ~= realm then MailworthyCharDB.realm = realm end
    if not id or type(MailworthyDB) ~= "table" then return end
    -- The realm's own server ID, kept even when that ID stops naming a realm (below): it still
    -- tells an old record of this realm from a namesake on another server (Codex review, fifth pass).
    local servers = ns.Util.Store(MailworthyDB, "realmServers")
    if servers[realm] == nil then servers[realm] = id end
    -- The game's word replaces what characters vouched for (4b.): a different guess goes, with
    -- what was recorded on it.
    local guesses = ns.Util.Store(MailworthyDB, "realmGuesses")
    if guesses[id] ~= nil and guesses[id] ~= realm then
        guesses[id] = nil
        forgetGuessed(id, realm)
    end
    -- And a guess that puts this realm on another server ID than its own is ended, with what was
    -- recorded on it (Codex review: those records stayed in this realm's lists).
    for other, guess in pairs(guesses) do
        if guess == realm and other ~= servers[realm] then
            guesses[other] = false
            forgetGuessed(other)
        end
    end
    local ids = ns.Util.Store(MailworthyDB, "realmIDs")
    if ids[id] == nil then
        ids[id] = realm
    elseif ids[id] ~= realm and ids[id] ~= false then
        ids[id] = false -- one server ID, two realms: it doesn't name a realm
        forgetGuessed(id) -- what was recorded on its word is forgotten
        ns.Log.Add("chars", "server ID %s seen on two realms: no longer used to find the realm", tostring(id))
    end
end

--- A character found by its own record vouches for the realm of its server ID (4b.).
local function vouch(realm, id)
    if not id or type(MailworthyDB) ~= "table" then return end
    local guesses = ns.Util.Store(MailworthyDB, "realmGuesses")
    if guesses[id] == nil then
        guesses[id] = realm
        ns.Log.Add("chars", "server ID %s: %s, as this account's characters say", tostring(id), tostring(realm))
    elseif guesses[id] ~= realm and guesses[id] ~= false then
        guesses[id] = false -- two characters, two realms: no guess for this ID any more
        forgetGuessed(id)
        ns.Log.Add("chars", "server ID %s: this account's characters name two realms, no guess", tostring(id))
    end
end

--- The one named realm the account's recorded characters know this name and faction on; or nil
--- and, when they know it on more than one, the set of those realms. Never a record of another server, or one made from a server ID; nor
--- a realm the game has named for another server ID than `id` (MailworthyDB.realmServers: an old
--- record carries no server ID of its own, but its realm may have one by now: Codex review, fourth
--- pass). Nor a record of another class, or of a higher level than this character's: that is a
--- namesake (a character never changes class, and never loses a level).
local function fromCharacters(id)
    local name, faction = ns.PlayerName(), call(UnitFactionGroup, "player")
    if not name or not faction or type(MailworthyDB) ~= "table" then return nil end
    local servers = ns.Util.Table(MailworthyDB.realmServers)
    local _, class = call(UnitClass, "player")
    local level = tonumber((call(UnitLevel, "player")))
    local function same(e)
        if type(e.class) == "string" and type(class) == "string" and e.class ~= class then return false end
        if tonumber(e.level) and level and tonumber(e.level) > level then return false end
        return true
    end
    local found, realms, count = nil, {}, 0
    for _, e in pairs(ns.Util.Table(MailworthyDB.characters)) do
        if type(e) == "table" and e.name == name and e.faction == faction and not e.guess
            and (e.server == nil or e.server == id) and same(e) then
            local realm = named(e.realm)
            if realm and not Characters.IsPlaceholder(realm) and (servers[realm] == nil or servers[realm] == id)
                and not realms[realm] then
                realms[realm], count, found = true, count + 1, realm
            end
        end
    end
    if count == 1 then return found end
    return nil, count > 1 and realms or nil
end

local function resolve()
    local id = Characters.ServerID()
    local realm = named(call(GetRealmName))
    if realm then
        learn(realm, id)
        return realm, "game"
    end
    realm = type(MailworthyCharDB) == "table" and named(MailworthyCharDB.realm) or nil
    if realm then
        -- The game named it for this character before; its server ID may only be known now (a login
        -- that had no GUID: Codex review, sixth pass).
        learn(realm, id)
        return realm, "saved"
    end
    local known
    if id and type(MailworthyDB) == "table" then known = ns.Util.Table(MailworthyDB.realmIDs)[id] end
    if named(known) then return known, "server" end
    local P = Characters.PLACEHOLDER
    if id and known ~= false then
        -- Not on a server ID known to stand for two realms: a namesake there may be on the other
        -- one, and a record's matching server ID then says nothing (Codex review, second pass). Not
        -- without a server ID either: nothing then tells this character from a namesake (third pass).
        local several
        realm, several = fromCharacters(id)
        if realm then
            vouch(realm, id)
            return realm, "characters"
        end
        -- What this account's characters vouch for on this server ID (4b.), unless the game has
        -- named that realm for another one.
        local guess = ns.Util.Table(MailworthyDB.realmGuesses)[id]
        local home = named(guess) and ns.Util.Table(MailworthyDB.realmServers)[guess]
        local usable = named(guess) and (home == nil or home == id)
        if several then
            -- Its name is recorded on more than one realm: the vouched one, when it is among them.
            -- Still found by its own record (never marked a guess: Codex review), but it vouches for
            -- nothing, as the guess decided. Else no realm is known, as before.
            if usable and several[guess] then return guess, "characters" end
            return P .. id, "placeholder"
        end
        -- Never seen: the vouched realm.
        if usable then return guess, "siblings" end
        if guess == nil then return P .. id, "placeholder" end
        -- They name two realms for it, or one the game has on another server ID: nothing said of
        -- this ID can be relied on, so a realm of this character alone, below.
    end
    -- No server ID, or one that stands for two realms: a realm of this character alone. Its GUID,
    -- when it is a whole one (a cut-off one may be shared: Codex review, sixth pass).
    local guid = id and named(call(UnitGUID, "player"))
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
    if source == "server" or source == "siblings" then entry.guess = id end
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
