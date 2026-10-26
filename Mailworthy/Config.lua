-- Saved settings (account-wide, MailworthyDB): the bank alt per realm + faction,
-- the history of names the player confirmed, and the decision-rule settings that
-- Valuation reads. Only values the player touched are saved; everything else is
-- Valuation.DEFAULTS (so the disenchant default keeps following the disenchant addon
-- until the player sets it).
local _, ns = ...

local Config = {}
ns.Config = Config

Config.MIN_GAIN_STEPS = { 0, 100, 200, 300, 500, 1000, 2000, 5000, 10000, 20000, 50000 }
Config.PCT_STEPS = { 0, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5, 0.75, 1 }
Config.MAX_NAMES = 10

local function db()
    MailworthyDB.settings = type(MailworthyDB.settings) == "table" and MailworthyDB.settings or {}
    MailworthyDB.realms = type(MailworthyDB.realms) == "table" and MailworthyDB.realms or {}
    MailworthyDB.bankAlts = type(MailworthyDB.bankAlts) == "table" and MailworthyDB.bankAlts or {}
    MailworthyDB.names = type(MailworthyDB.names) == "table" and MailworthyDB.names or {}
    return MailworthyDB
end

--- Collapse spaces; Forever names are "First Surname".
function Config.Clean(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
end

local function realmKey()
    local _, realm, faction = ns.Characters.Current()
    return tostring(realm) .. "|" .. tostring(faction), realm, faction
end

-- Settings -------------------------------------------------------------------

function Config.Values()
    return ns.Valuation.Settings(db().settings, ns.Prices.DisenchantAddonInstalled())
end

function Config.Get(key) return Config.Values()[key] end

local function serverTime()
    local ok, t = pcall(GetServerTime)
    return ok and tonumber(t) or time()
end

--- The first server time Mailworthy saw this realm (recorded at login), for Valuation.ServerDay.
function Config.FirstSeen()
    local _, realm = ns.Characters.Current()
    local realms = db().realms
    realms[tostring(realm)] = type(realms[tostring(realm)]) == "table" and realms[tostring(realm)] or {}
    local entry = realms[tostring(realm)]
    if type(entry.firstSeen) ~= "number" then entry.firstSeen = serverTime() end
    return entry.firstSeen
end

--- Days since launch for the decision rule (nil when the server time is unknown).
function Config.ServerDay()
    return ns.Valuation.ServerDay(serverTime(), Config.FirstSeen())
end

ns.On("PLAYER_LOGIN", function() Config.FirstSeen() end)

-- Saved switches outside the decision rule. glowEverywhere: the locked-item glow
-- in the bags away from the mailbox too (off: only while a mailbox is open).
Config.FLAGS = { minimapHidden = true, tagsEverywhere = true, glowEverywhere = true }

function Config.Set(key, value)
    if ns.Valuation.DEFAULTS[key] == nil and not Config.FLAGS[key] then return end
    db().settings[key] = value
    ns.Log.Add("config", "%s = %s", key, tostring(value))
end

--- Pure: the next value in `steps` from `value` in direction +1 / -1 (from the
--- nearest step, so a value saved between steps still moves sensibly).
function Config.NextStep(steps, value, dir)
    local nearest, nearestDistance = 1, math.huge
    for i, v in ipairs(steps) do
        local distance = math.abs(v - (value or 0))
        if distance < nearestDistance - 1e-9 then nearest, nearestDistance = i, distance end
    end
    local i = math.max(1, math.min(#steps, nearest + (dir > 0 and 1 or -1)))
    return steps[i]
end

function Config.Step(key, dir)
    local steps = key == "minGain" and Config.MIN_GAIN_STEPS or key == "minGainPct" and Config.PCT_STEPS or nil
    if not steps then return end
    Config.Set(key, Config.NextStep(steps, Config.Get(key), dir))
end

function Config.MinimapShown() return db().settings.minimapHidden ~= true end

--- A saved switch from Config.FLAGS (false until set).
function Config.Flag(key) return db().settings[key] == true end

-- Bank alt --------------------------------------------------------------------

function Config.BankAlt()
    return db().bankAlts[(realmKey())]
end

local function knownEntry(name)
    local lower = name:lower()
    for _, entry in ipairs(ns.Characters.Mailable()) do
        if tostring(entry.name):lower() == lower then return entry end
    end
    return nil
end

function Config.IsKnown(name)
    name = Config.Clean(name)
    return name ~= nil and knownEntry(name) ~= nil
end

local function remember(name, realm, faction)
    local names = db().names
    for i = #names, 1, -1 do
        local e = names[i]
        if e.realm == realm and e.faction == faction and tostring(e.name):lower() == name:lower() then
            table.remove(names, i)
        end
    end
    table.insert(names, 1, { name = name, realm = realm, faction = faction })
    while #names > Config.MAX_NAMES * 4 do table.remove(names) end
end

--- Save the bank alt for this realm + faction. A known character's name is
--- used exactly as recorded (so a typed "roknua themicrulah" can't misspell it).
function Config.SetBankAlt(name)
    name = Config.Clean(name)
    if not name then return nil end
    local entry = knownEntry(name)
    if entry then name = entry.name end
    local key, realm, faction = realmKey()
    db().bankAlts[key] = name
    remember(name, realm, faction)
    ns.Log.Add("config", "bank alt for %s = %s%s", key, name, entry and "" or " (not seen by Mailworthy)")
    return name
end

--- This character declares itself the bank alt (the control in the settings window).
--- Same slot as a picked name, so every other character on this realm + faction
--- on this account mails to it, and BankAlt.IsBankAlt() is true here. Needed when
--- the bank alt lives on a second WoW account: SavedVariables are per account, so
--- the main's choice never reaches this one. Not added to the names history.
function Config.SetBankAltHere()
    local name = Config.Clean(ns.PlayerName())
    if not name then return nil end
    local key = realmKey()
    db().bankAlts[key] = name
    ns.Log.Add("config", "bank alt for %s = %s (this character)", key, name)
    return name
end

--- No bank alt on this realm + faction any more (undo for SetBankAltHere).
function Config.ClearBankAlt()
    local key = realmKey()
    if db().bankAlts[key] == nil then return end
    db().bankAlts[key] = nil
    ns.Log.Add("config", "bank alt for %s cleared", key)
end

--- Is this character the saved bank alt for its realm + faction?
function Config.IsBankAltHere()
    local alt = Config.BankAlt()
    return alt ~= nil and tostring(alt):lower() == tostring(ns.PlayerName()):lower()
end

function Config.ForgetName(name)
    local _, realm, faction = realmKey()
    local names = db().names
    for i = #names, 1, -1 do
        local e = names[i]
        if e.realm == realm and e.faction == faction and e.name == name then table.remove(names, i) end
    end
end

--- Names to offer, this realm + faction: known characters first (by name), then
--- saved names Mailworthy hasn't seen log in. { name, known, class, level }.
function Config.Choices()
    local list, seen = {}, {}
    for _, entry in ipairs(ns.Characters.Mailable()) do
        list[#list + 1] = { name = entry.name, known = true, class = entry.class, level = entry.level }
        seen[tostring(entry.name):lower()] = true
    end
    local _, realm, faction = realmKey()
    local me = tostring(ns.PlayerName()):lower()
    for _, e in ipairs(db().names) do
        local lower = tostring(e.name):lower()
        if e.realm == realm and e.faction == faction and not seen[lower] and lower ~= me then
            list[#list + 1] = { name = e.name, known = false }
            seen[lower] = true
        end
    end
    return list
end

--- Pure: the first choice whose name starts with `prefix` (case-insensitive), or nil.
function Config.Complete(prefix, choices)
    prefix = Config.Clean(prefix)
    if not prefix then return nil end
    prefix = prefix:lower()
    for _, c in ipairs(choices) do
        if tostring(c.name):lower():sub(1, #prefix) == prefix then return c.name end
    end
    return nil
end
