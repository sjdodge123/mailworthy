-- Known characters (account-wide): every character that logs in with Mailworthy
-- is recorded, so the bank alt is picked from a list instead of typed. Mail
-- can't cross realm or faction, so only same realm + faction are offered.
local _, ns = ...

local Characters = {}
ns.Characters = Characters

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

--- "First Surname" on Forever (no realm suffix).
function ns.PlayerName()
    return call(GetUnitName, "player", true) or call(UnitName, "player")
end

function Characters.Key(name, realm, faction)
    return string.format("%s|%s|%s", tostring(name), tostring(realm), tostring(faction))
end

function Characters.Current()
    return ns.PlayerName(), call(GetRealmName), call(UnitFactionGroup, "player")
end

local function professions()
    local list = {}
    for _, index in ipairs({ call(GetProfessions) }) do
        local name, _, rank, maxRank, _, _, skillLine = call(GetProfessionInfo, index)
        if name then list[#list + 1] = { name = name, rank = rank, maxRank = maxRank, skillLine = skillLine } end
    end
    return list
end

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
        professions = professions(), lastSeen = call(GetServerTime) or time(),
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
