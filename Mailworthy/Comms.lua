-- Addon messages between Mailworthy users (C_ChatInfo, prefix "Mailworthy"), so a
-- binding reaches the friend's character that has the profession (operator,
-- 2026-10-26: "get the materials to the friend that actually has the profession,
-- not to their alt for the AH") and the friends window can mark who runs
-- Mailworthy and what they craft. Each Mailworthy says hello to its guild and
-- group at login, when the group changes, and when another Mailworthy asks (the
-- friends window asks when it opens):
--
--   H2|<this character's crafting skill lines>|<other characters on this realm + faction
--       that have a crafting profession: Name=333,197;Other Name=165>
--   A2                                                   (ask: please say hello)
--   F2|<server day of this character's freshest Auctionator scan>  (Stale.lua; right after
--       a hello; Mailworthys before v0.15 drop it, as they drop any kind they don't know)
--   T2|<revision>|<author>|<i>/<n>|<skill line>=<Name>:<cap>   (a guild template rule: Guild.lua;
--       GUILD only; any member passes a copy on; an odd cap on the Enchanting rule is its Gear
--       switch, Guild.WireCap)
--   Q2|<revision held>                    (ask: whoever holds a newer guild template sends it)
--   S2|<this character's crafting skills: 129:80,197:130>|<other characters here:
--       Name=197:150,333:120;Other Name=165:90>   (right after a hello, for the material
--       tiers: a binding stops taking what the bound player's skill is past; Mailworthys
--       before v0.18 drop it)
--   M2|<mail's sender>|<recipient>|<server time>|<mail id>|<itemID>:<count>:<copper>:<scan age>:<k>;...
--       (LedgerWire.lua: what a mail to another player was worth when it went; WHISPER only, to the
--       recipient once heard from. v0.25.0 sent V2|<sender>|<recipient>|<time>|<itemID>:<count>:<copper>;...,
--       still read, and drops M2)
--   R2|<recipient>|<mail's sender>|<mail id>|<itemID>:<count>:<copper>:<k>;...   (LedgerWire.lua: the value the
--       recipient settled on when it differs from the M2 one, so the sender's log matches; WHISPER only,
--       held until the sender is heard from)
--   U2|<this build's release: v0.31.0>   (Version.lua: right after a hello, release builds only;
--       fields after the version are left out; v0.30.0 and older drop it)
--   G2|<asOf>|<i>/<n>|<total>|<since>|<days back>:<units>;...   (Contributions.lua: this character's own
--       guild-rule giving, right after a hello and after a mailbox visit that counted some; GUILD only;
--       information only, for Raid Ledger's guild contributions; older Mailworthys drop it)
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
Comms.VERSION = 2
Comms.MAX_MESSAGE = 255   -- the addon-message limit; characters past it are left out
Comms.PEER_DAYS = 60
Comms.HELLO_DELAY = 8      -- seconds after login (the guild roster and group are in by then)
Comms.THROTTLE = 10        -- seconds between hellos
Comms.ASK_THROTTLE = 30    -- seconds between asks
Comms.MAX_NAME = 48
-- A player in both our guild and our group sends every message on GUILD and PARTY; the copy
-- that arrives within this many seconds is dropped (rl-companion log, 2026-11-08: every hello
-- was heard, stored and logged twice).
Comms.DUPLICATE_WINDOW = 5

local lastHello, lastAsk, pendingHello = -math.huge, -math.huge, false
local recent, recentCount = {}, 0 -- "sender\ntext" -> GetTime() it was last heard (Comms.Duplicate)
local groupSeen = {}              -- lower-case name -> true: the online group members at the last roster change
Comms.stats = { heard = 0, copies = 0, hellos = 0, rosterQuiet = 0 }
local announcedSteps -- "129:1,197:2": the tier steps (Tiers.Step) last told to peers

--- Pure: the tier steps of a professions list, as text to compare ("129:1,197:2").
function Comms.Steps(professions)
    local out = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine)
        if id and ns.Valuation.PROFESSION_MATS[id] then out[#out + 1] = id .. ":" .. ns.Tiers.Step(id, p.rank) end
    end
    table.sort(out)
    return table.concat(out, ",")
end

local Util = ns.Util
local call = Util.Call

local function now() return call(GetTime) or 0 end
local serverTime = Util.Now

local function store() return Util.Store(MailworthyDB, "peers", (Util.RealmKey())) end

function Comms.On() return ns.Features.On("comms") end

--- Pure: the crafting skill lines in a professions list ({ skillLine = } entries or ids), sorted.
local function craftingIds(professions)
    local ids = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine or p)
        if id and ns.Valuation.PROFESSION_MATS[id] then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

local function idText(ids)
    local out = {}
    for i, id in ipairs(ids) do out[i] = tostring(id) end
    return table.concat(out, ",")
end

local function goodName(name)
    name = ns.Routes.Clean(name)
    if not name or #name > Comms.MAX_NAME or name:find("[%c=;|]") then return nil end
    return name
end

--- Pure: this character's hello: its crafting professions and the account's other
--- characters here that craft ({ { name, professions }, ... }), as many as fit.
function Comms.Encode(professions, characters)
    local head = string.format("H%d|%s|", Comms.VERSION, idText(craftingIds(professions)))
    local parts = {}
    for _, c in ipairs(type(characters) == "table" and characters or {}) do
        local ids, name = craftingIds(c.professions), goodName(c.name)
        if name and #ids > 0 then
            local part = name .. "=" .. idText(ids)
            local candidate = head .. table.concat(parts, ";") .. (#parts > 0 and ";" or "") .. part
            if #candidate <= Comms.MAX_MESSAGE then parts[#parts + 1] = part end
        end
    end
    return head .. table.concat(parts, ";")
end

local function skillText(professions)
    local out = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id, rank = tonumber(type(p) == "table" and p.skillLine), tonumber(type(p) == "table" and p.rank)
        if id and rank and ns.Valuation.PROFESSION_MATS[id] then out[#out + 1] = { id, math.floor(rank) } end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    for i, e in ipairs(out) do out[i] = e[1] .. ":" .. e[2] end
    return table.concat(out, ",")
end

--- Pure: the skills message: this character's crafting skills and the account's other
--- characters' here ({ { name, professions = { { skillLine, rank } } } }), as many as fit.
function Comms.EncodeSkills(professions, characters)
    local head = string.format("S%d|%s|", Comms.VERSION, skillText(professions))
    local parts = {}
    for _, c in ipairs(type(characters) == "table" and characters or {}) do
        local skills, name = skillText(c.professions), goodName(c.name)
        if name and skills ~= "" then
            local part = name .. "=" .. skills
            local candidate = head .. table.concat(parts, ";") .. (#parts > 0 and ";" or "") .. part
            if #candidate <= Comms.MAX_MESSAGE then parts[#parts + 1] = part end
        end
    end
    return head .. table.concat(parts, ";")
end

-- Pure: "129:80,197:130" -> { [129] = 80, [197] = 130 } (crafting skill lines Mailworthy knows,
-- ranks 0-999), and whether any was found.
local function decodeSkills(text)
    local skills, any = {}, false
    for id, rank in tostring(text):gmatch("(%d+):(%d+)") do
        id, rank = tonumber(id), tonumber(rank)
        if ns.Routes.ProfessionName(id) and rank <= 999 then skills[id], any = rank, true end
    end
    return skills, any
end

-- Message kinds ---------------------------------------------------------------------------------
-- Each module registers the kinds it owns (Comms.Register): the hello, ask and skills here, the
-- guild template in Guild.lua, the scan day in Stale.lua, the release in Version.lua, the ledger's
-- values in LedgerWire.lua, the guild giving in Contributions.lua. Comms keeps the transport, the
-- checks every message gets (length, sender, this character's own, the channel, copies), the
-- throttles and the peers. What a kind's message looks like on the wire is its module's alone, and
-- never changes for one already sent: older Mailworthys in the wild read it (spec/comms_wire_spec.lua).
local registry, kindOrder = {}, {}

--- Register the message kind `letter` ("H", "M", ...). `def`:
---   kind       the decoded message's kind ("hello", "values", ...);
---   module     (optional) the ns field that owns it: while that is missing (an older build without
---              the file) the kind decodes to nil, like any kind this build doesn't know;
---   decode     fn(rest, text) -> the message's fields (a table; Comms adds kind and version) or nil.
---              `rest` is what follows "<letter><version>|", `text` the whole message;
---   hear       fn(name, msg, channel) -> what Comms.Hear returns (the sender's name is cleaned);
---   channels   (optional) { GUILD = true, ... }: the only channels it is taken on (anything else is
---              dropped before the copy check) and, for an afterHello message, the ones it goes on;
---   afterHello (optional) fn() -> a message, a list of them, or nil: sent right after each hello.
--- Kinds sent after a hello go in the order they were registered (the .toc order).
function Comms.Register(letter, def)
    assert(type(letter) == "string" and letter:match("^%a$"), "Comms.Register: one letter")
    assert(type(def) == "table" and type(def.kind) == "string" and type(def.decode) == "function"
        and type(def.hear) == "function", "Comms.Register: kind, decode and hear")
    if not registry[letter] then kindOrder[#kindOrder + 1] = letter end
    registry[letter] = def
end

--- The kinds registered, as { letter = def }; `order` lists the letters in registration order.
function Comms.Kinds()
    local copy, order = {}, {}
    for i, letter in ipairs(kindOrder) do copy[letter], order[i] = registry[letter], letter end
    return copy, order
end

local function present(def) return def.module == nil or ns[def.module] ~= nil end

-- The message and the definition of its kind, or nil.
local function decode(text)
    if type(text) ~= "string" or #text > Comms.MAX_MESSAGE then return nil end
    local letter, version, rest = text:match("^(%a)(%d+)|?(.*)$")
    local def = letter and registry[letter]
    if not def or not present(def) then return nil end
    local msg = def.decode(rest, text)
    if type(msg) ~= "table" then return nil end
    msg.kind, msg.version = def.kind, tonumber(version)
    return msg, def
end

--- Pure: a message from another Mailworthy, or nil: { kind, version, ... } with the fields its
--- kind's decoder gives: { kind = "hello", version, professions = { ids }, characters = { { name,
--- professions = { ids } }, ... } }, { kind = "ask", version }, { kind = "skills", version, skills =
--- { [id] = rank }, characters = { { name, skills } } } (the material tiers); the other kinds are
--- their modules' (Comms.Register).
function Comms.Decode(text)
    return (decode(text))
end

local function knownIds(list)
    local ids = {}
    for id in tostring(list):gmatch("%d+") do
        if ns.Routes.ProfessionName(tonumber(id)) then ids[#ids + 1] = tonumber(id) end
    end
    return ids
end

local function decodeHello(rest)
    local profs, chars = rest:match("^([%d,]*)|?([^|]*)$")
    if profs == nil then return nil end
    local characters = {}
    for part in tostring(chars):gmatch("[^;]+") do
        local name, ids = part:match("^([^=]+)=([%d,]*)$")
        name = name and goodName(name)
        if name and #knownIds(ids) > 0 then characters[#characters + 1] = { name = name, professions = knownIds(ids) } end
    end
    return { professions = knownIds(profs), characters = characters }
end

local function decodeSkillsMessage(rest)
    local own, chars = rest:match("^([%d:,]*)|?([^|]*)$")
    if own == nil then return nil end
    local characters = {}
    for part in tostring(chars):gmatch("[^;]+") do
        local name, list = part:match("^([^=]+)=([%d:,]*)$")
        name = name and goodName(name)
        local skills, any = decodeSkills(list)
        if name and any then characters[#characters + 1] = { name = name, skills = skills } end
    end
    return { skills = (decodeSkills(own)), characters = characters }
end

-- The guild and group channels this character is in; with `only` ({ GUILD = true }), just those.
local function channels(only)
    local list = {}
    if call(IsInGuild) == true then list[#list + 1] = "GUILD" end
    local n = tonumber((call(GetNumGroupMembers))) or 0
    if n > 0 then list[#list + 1] = call(IsInRaid) == true and "RAID" or "PARTY" end
    if only then
        for i = #list, 1, -1 do
            if not only[list[i]] then table.remove(list, i) end
        end
    end
    return list
end

-- A send result that means "sent": SendAddonMessage returns nothing on older clients, true, or
-- Enum.SendAddonMessageResult.Success (0).
local function sentOk(ok, result)
    return ok and (result == nil or result == true or result == 0)
end

-- Send `message` on the guild and group channels (or on `list`, from channels()). Returns whether
-- any channel took it and the channels with their result ("GUILD, PARTY", or "GUILD, PARTY error 3"
-- for one that failed).
local function send(message, list)
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return false, "no C_ChatInfo" end
    local sent, parts = false, {}
    for _, channel in ipairs(list or channels()) do
        local ok, result = pcall(chat.SendAddonMessage, Comms.PREFIX, message, channel)
        sent = sent or sentOk(ok, result) -- a rejected send (error code, no throw) didn't go out
        parts[#parts + 1] = sentOk(ok, result) and channel or (channel .. " error " .. tostring(result))
    end
    return sent, #parts > 0 and table.concat(parts, ", ") or "no guild or group"
end

--- Send one message to the guild only (Guild.lua's template and asks).
function Comms.SendGuild(message)
    if not Comms.On() or call(IsInGuild) ~= true then return false end
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return false end
    local ok, result = pcall(chat.SendAddonMessage, Comms.PREFIX, message, "GUILD")
    ns.Log.Add("comms", "%s on GUILD: %s", message:sub(1, 2), ok and tostring(result) or ("error " .. tostring(result)))
    return ok
end

--- Whisper one message to one player (Ledger.lua's values; only to a player just heard from,
--- so never to someone offline).
function Comms.Whisper(target, message)
    if not Comms.On() or not target then return false end
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return false end
    local ok, result = pcall(chat.SendAddonMessage, Comms.PREFIX, message, "WHISPER", target)
    ns.Log.Add("comms", "%s to %s: %s", message:sub(1, 2), tostring(target), ok and tostring(result) or ("error " .. tostring(result)))
    return ok
end

--- Say hello to the guild and group (throttled; a hello the throttle held back goes out at the
--- next mailbox). One log line per hello, whatever the number of channels and messages.
function Comms.Announce(reason)
    if not Comms.On() then return false end
    if now() - lastHello < Comms.THROTTLE then
        pendingHello = true
        return false
    end
    lastHello, pendingHello = now(), false
    local professions = ns.Characters.Professions()
    local sent, where = send(Comms.Encode(professions, ns.Characters.Mailable()))
    local results = { { "H2", where } }
    if sent then
        local _, skillsWhere = send(Comms.EncodeSkills(professions, ns.Characters.Mailable()))
        results[#results + 1] = { "S2", skillsWhere }
        announcedSteps = Comms.Steps(professions)
        Comms.stats.hellos = Comms.stats.hellos + 1
    end
    -- Then each kind sent after a hello, in registration order: the scan day (Stale.lua), the
    -- release (Version.lua; nil on a dev build), this character's guild-rule giving (Contributions.lua,
    -- to the guild only). One result per kind: a failed send's channels when one failed.
    for _, letter in ipairs(sent and kindOrder or {}) do
        local def = registry[letter]
        if def.afterHello and present(def) then
            local out = def.afterHello()
            local messages = type(out) == "string" and { out } or (type(out) == "table" and out or {})
            local list = channels(def.channels)
            if #messages > 0 and #list > 0 then
                local all = table.concat(list, ", ")
                local went = all
                for _, message in ipairs(messages) do
                    local _, w = send(message, list)
                    if w ~= all then went = w end
                end
                results[#results + 1] = { messages[1]:sub(1, 2), went }
            end
        end
    end
    ns.Log.Add("comms", "hello (%s): %s", tostring(reason), Comms.ResultText(results))
    return sent
end

--- Pure: { { kind, where }, ... } as one log text: "H2 S2 F2 on GUILD, PARTY" when every message
--- went the same way, else each with its own ("H2 on GUILD; S2 on GUILD error 3"), so a failed
--- send still shows in the one line.
function Comms.ResultText(results)
    local kinds, same = {}, true
    for i, r in ipairs(results) do
        kinds[i] = r[1]
        same = same and r[2] == results[1][2]
    end
    if same and #results > 0 then return table.concat(kinds, " ") .. " on " .. tostring(results[1][2]) end
    local parts = {}
    for i, r in ipairs(results) do parts[i] = r[1] .. " on " .. tostring(r[2]) end
    return table.concat(parts, "; ")
end

--- Ask other Mailworthys to say hello (the friends window, throttled).
function Comms.Ask()
    if not Comms.On() or now() - lastAsk < Comms.ASK_THROTTLE then return false end
    lastAsk = now()
    local sent, where = send(string.format("A%d", Comms.VERSION))
    ns.Log.Add("comms", "ask (A2) on %s", where)
    return sent
end

--- Whether `text` from `name` is a copy of one heard less than DUPLICATE_WINDOW seconds ago
--- (the same message on GUILD and PARTY). Whispers are never copies. Records the first one.
function Comms.Duplicate(name, text, channel, at)
    if channel == "WHISPER" then return false end
    local key = tostring(name):lower() .. "\n" .. tostring(text)
    local last = recent[key]
    if last and at - last < Comms.DUPLICATE_WINDOW then return true end
    if not last then recentCount = recentCount + 1 end
    recent[key] = at
    if recentCount > 64 then -- forget what is past the window (a busy guild sends many kinds)
        recentCount = 0
        for k, t in pairs(recent) do
            if at - t >= Comms.DUPLICATE_WINDOW then recent[k] = nil else recentCount = recentCount + 1 end
        end
    end
    return false
end

--- Peers heard from on this realm + faction: lower-case name -> { name, professions, characters, version (the
--- wire format, 2), at, skills, release (the Mailworthy release they run, Version.lua) }.
function Comms.Peers()
    return store()
end

function Comms.Peer(name)
    local key = Util.NameKey(name)
    return key and store()[key] or nil
end

-- The Mailworthy mark (operator, 2026-11-08: "a mailworthy icon or some sort of indicator on the
-- mailworthy ui when a player's name is mentioned showing if they have mailworthy as well"): the
-- addon's icon right after a name, as a texture escape in our own font strings (no frame, no
-- texture on anything of Blizzard's, no tooltip). Each window that shows one says what it means in
-- its footer (MARK_KEY, Widgets.Footer), so nothing depends on hovering. Switch: peerMark.
Comms.MARK = "|TInterface\\AddOns\\Mailworthy\\Textures\\Icon:0|t"
Comms.MARK_KEY = Comms.MARK .. " runs Mailworthy"

--- Whether `name` is known to run Mailworthy: this character, one of the account's characters
--- on this realm + faction (Mailworthy recorded them), a player whose Mailworthy said hello, or a
--- character that player's hello listed as theirs. Peers go after PEER_DAYS (Prune).
function Comms.Runs(name)
    name = ns.Routes.Clean(name)
    if not name then return false end
    local lower = name:lower()
    if lower == tostring(ns.PlayerName()):lower() then return true end
    for _, entry in ipairs(ns.Characters.Mailable()) do
        if tostring(entry.name):lower() == lower then return true end
    end
    local peers = store()
    if type(peers[lower]) == "table" then return true end
    for _, peer in pairs(peers) do
        local characters = type(peer) == "table" and peer.characters
        for _, c in ipairs(type(characters) == "table" and characters or {}) do
            if type(c) == "table" and tostring(c.name):lower() == lower then return true end
        end
    end
    return false
end

-- Windows that show marks redraw when the names behind them change (a new peer, a peer's
-- characters or professions changed), once per burst of messages: never on every addon packet (Codex review).
Comms.MARK_DELAY = 1 -- seconds
local marks, markPending = ns.Util.Signal("mark redraw"), false

--- Call `fn` (no arguments) after the set of names known to run Mailworthy changed.
Comms.OnMarksChanged = marks.Add

local function notifyMarks()
    markPending = false
    marks.Fire()
end

-- Pure: what a stored peer puts on screen, as text: the names it marks (the sender and the
-- characters its hello listed) with their professions, which decide where a binding delivers
-- (Routes.Crafter: "delivered to <their crafter>"; Codex review). Skill ranks are left out.
local function markNames(peer)
    if type(peer) ~= "table" then return "" end
    local function entry(name, professions)
        local ids = {}
        for i, id in ipairs(type(professions) == "table" and professions or {}) do ids[i] = tostring(id) end
        table.sort(ids)
        return tostring(name):lower() .. "=" .. table.concat(ids, ",")
    end
    local names = { entry(peer.name, peer.professions) }
    for _, c in ipairs(type(peer.characters) == "table" and peer.characters or {}) do
        if type(c) == "table" then names[#names + 1] = entry(c.name, c.professions) end
    end
    table.sort(names)
    return table.concat(names, ";")
end

local function marksChanged(before, after)
    if before == after or markPending then return end
    markPending = true
    Util.After(Comms.MARK_DELAY, notifyMarks)
end

-- Who a peer is (its name, characters and professions) changed: at once, for whoever keeps an index
-- built from the peers (Ledger.Owner's groups). The marks redraw later, once per burst.
local peersChanged = Util.Signal("peers")

--- Call `fn` (no arguments) at once when a peer's name, characters or professions were written, or a
--- peer was dropped (Ledger.lua's owner index).
Comms.OnPeersChanged = peersChanged.Add

--- Write `fields` into the record kept for peer `name`, in place: the fields not named stay as they
--- were (a hello keeps the skills and the release heard before it). Without a record, one is made
--- only when `create` (a hello or a skills message); else nothing is written. Returns the record or nil.
function Comms.UpdatePeer(name, fields, create)
    local key = Util.NameKey(name)
    if not key or type(fields) ~= "table" then return nil end
    local peers = store()
    local peer = peers[key]
    if type(peer) ~= "table" then
        if not create then return nil end
        peer = {}
    end
    local before = markNames(peers[key])
    for field, value in pairs(fields) do peer[field] = value end
    peers[key] = peer
    if fields.name ~= nil or fields.characters ~= nil or fields.professions ~= nil then peersChanged.Fire() end
    marksChanged(before, markNames(peer))
    return peer
end

-- Another Mailworthy spoke (any kind, once past the checks): it is online.
local heardFrom = Util.Signal("heard")

--- Call `fn(name)` when any message from another Mailworthy is taken (`name` cleaned): they are
--- online now (Ledger.lua sends what waits for them).
Comms.OnHeard = heardFrom.Add

--- `text` (default: the name) with the Mailworthy mark after it when `name` runs Mailworthy, and
--- whether it was marked (the window then shows MARK_KEY in its footer).
function Comms.Mark(name, text)
    text = text or tostring(name)
    if not ns.Features.On("peerMark") or not Comms.Runs(name) then return text, false end
    return text .. " " .. Comms.MARK, true
end

--- A message from `sender` (a name, possibly with a realm suffix) on `channel`: checked, then
--- handed to its kind's `hear` (Comms.Register). Returns what that gives, or nil when dropped.
function Comms.Hear(sender, text, channel)
    local msg, def = decode(text)
    local name = ns.Routes.Clean(sender)
    if not msg or not name or #name > Comms.MAX_NAME or name:find("%c") then return nil end
    if name:lower() == tostring(ns.PlayerName()):lower() then return nil end
    -- A kind taken on some channels only (G2 on GUILD, M2 / R2 whispered) is dropped elsewhere before
    -- the copy check, so a copy on another channel can't make the real one a "duplicate" (Codex review).
    if def.channels and not def.channels[channel] then return nil end
    if Comms.Duplicate(name, text, channel, now()) then
        Comms.stats.copies = Comms.stats.copies + 1
        return nil
    end
    Comms.stats.heard = Comms.stats.heard + 1
    heardFrom.Fire(name) -- online: values waiting for them go now (Ledger)
    return def.hear(name, msg, channel)
end

-- The hello: who this player is and which of their characters craft what.
local function hearHello(name, msg)
    local characters = {}
    for _, c in ipairs(msg.characters) do
        if c.name:lower() ~= name:lower() then characters[#characters + 1] = c end
    end
    local peer = Comms.UpdatePeer(name, { name = name, professions = msg.professions, characters = characters,
        version = msg.version, at = serverTime() }, true)
    if ns.BankAlt then ns.BankAlt.Invalidate() end
    ns.Log.Add("comms", "hello from %s: professions %s, %d other character(s)", name,
        #peer.professions > 0 and table.concat(peer.professions, ",") or "none", #characters)
    return peer
end

-- The skills (material tiers); a peer whose hello got lost is made from them (they say the same and more).
local function hearSkills(name, msg)
    local skills = { [name:lower()] = msg.skills }
    for _, c in ipairs(msg.characters) do
        if c.name:lower() ~= name:lower() then skills[c.name:lower()] = c.skills end
    end
    if type(Comms.Peer(name)) ~= "table" then
        local ids, characters = {}, {}
        for id in pairs(msg.skills) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, c in ipairs(msg.characters) do
            local cids = {}
            for id in pairs(c.skills) do cids[#cids + 1] = id end
            table.sort(cids)
            if c.name:lower() ~= name:lower() then characters[#characters + 1] = { name = c.name, professions = cids } end
        end
        Comms.UpdatePeer(name, { name = name, professions = ids, characters = characters, version = msg.version }, true)
    end
    local peer = Comms.UpdatePeer(name, { skills = skills, at = serverTime() })
    -- A binding's crafter can change with a skill: the bag tags read again at their next draw
    -- (before, the next bag update redrew them; Codex review, 2026-11-14).
    if ns.BankAlt then ns.BankAlt.Invalidate() end
    ns.Log.Add("comms", "skills from %s: %s", name, Comms.SkillText(msg.skills))
    return peer
end

Comms.Register("H", { kind = "hello", decode = decodeHello, hear = hearHello })
Comms.Register("A", {
    kind = "ask",
    decode = function() return {} end,
    hear = function(name, msg)
        Comms.Announce("asked by " .. name)
        return msg
    end,
})
Comms.Register("S", { kind = "skills", decode = decodeSkillsMessage, hear = hearSkills })

--- The skill in `profession` of a character some Mailworthy told us about (the sender or
--- one of their characters), or nil.
function Comms.Skill(name, profession)
    name = ns.Routes.Clean(name)
    if not name then return nil end
    local best
    for _, peer in pairs(store()) do
        local skills = type(peer) == "table" and type(peer.skills) == "table" and peer.skills[name:lower()]
        local rank = type(skills) == "table" and tonumber(skills[tonumber(profession)]) or nil
        if rank and (not best or rank > best) then best = rank end
    end
    return best
end

--- Pure: "First Aid 80, Tailoring 130" / "none".
function Comms.SkillText(skills)
    local parts = {}
    for id, rank in pairs(type(skills) == "table" and skills or {}) do
        parts[#parts + 1] = (ns.Routes.ProfessionName(id) or tostring(id)) .. " " .. tostring(rank)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

--- Drop peers not heard from in PEER_DAYS.
function Comms.Prune(at)
    at = at or serverTime()
    local dropped = false
    for key, peer in pairs(store()) do
        if type(peer) ~= "table" or (tonumber(peer.at) or 0) < at - Comms.PEER_DAYS * 86400 then
            store()[key], dropped = nil, true
        end
    end
    if dropped then peersChanged.Fire() end
end

--- Pure: "Enchanting, Tailoring" / "no crafting profession".
function Comms.ProfessionText(ids)
    local profs = {}
    for _, id in ipairs(ids or {}) do profs[#profs + 1] = ns.Routes.ProfessionName(id) or tostring(id) end
    table.sort(profs)
    return #profs > 0 and table.concat(profs, ", ") or "no crafting profession"
end

--- One line per peer for /mw report.
function Comms.ReportLines()
    local lines = {}
    for _, peer in pairs(store()) do
        local others = {}
        for _, c in ipairs(peer.characters or {}) do
            others[#others + 1] = tostring(c.name) .. " = " .. Comms.ProfessionText(c.professions)
        end
        local skills = type(peer.skills) == "table" and peer.skills[tostring(peer.name):lower()] or nil
        lines[#lines + 1] = string.format("mailworthy peer: %s (%s; skills: %s; other characters: %s; heard %s)",
            tostring(peer.name), Comms.ProfessionText(peer.professions), skills and Comms.SkillText(skills) or "not sent",
            #others > 0 and table.concat(others, ", ") or "none", date("%b %d", peer.at or 0))
    end
    table.sort(lines)
    local st = Comms.stats
    table.insert(lines, 1, string.format("comms this session: %d heard, %d copies dropped (guild + group), "
        .. "%d hello(s) sent, %d group change(s) with no one new (no hello)", st.heard, st.copies, st.hellos,
        st.rosterQuiet))
    return lines
end

function Comms.RegisterPrefix()
    if not Comms.On() then return end
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return end
    local ok, result = pcall(chat.RegisterAddonMessagePrefix, Comms.PREFIX)
    ns.Log.Add("comms", "prefix registered: %s", ok and tostring(result) or ("error " .. tostring(result)))
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= Comms.PREFIX or not Comms.On() then return end
    Comms.Hear(sender, text, channel)
end)

ns.On("PLAYER_LOGIN", function()
    Comms.RegisterPrefix()
    Comms.Prune()
    if not Comms.On() then return end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(Comms.HELLO_DELAY, function() pcall(Comms.Announce, "login") end)
    end
end)

--- The group's online members other than this character (lower-case names), from the units.
local function groupMembers()
    local members = {}
    local n = tonumber((call(GetNumGroupMembers))) or 0
    local raid = call(IsInRaid) == true
    local me = tostring(ns.PlayerName()):lower()
    for i = 1, n do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        local name = ns.Routes.Clean(call(GetUnitName, unit, true) or call(UnitName, unit))
        if name and name:lower() ~= me and call(UnitIsConnected, unit) ~= false then members[name:lower()] = true end
    end
    return members
end

--- Pure: how many of `members` (lower-case name -> true) are not in `before`.
function Comms.Joined(before, members)
    local n = 0
    for name in pairs(members) do
        if not before[name] then n = n + 1 end
    end
    return n
end

-- A hello when someone new is in the group (joined, or came online): they haven't heard it. The
-- game fires GROUP_ROSTER_UPDATE for much more (leader, loot, subgroups, levels): rl-companion's
-- log showed a guildmate's hellos every 20-40 s from it, each one three messages to the guild.
ns.On("GROUP_ROSTER_UPDATE", function()
    local members = groupMembers()
    local joined = Comms.Joined(groupSeen, members)
    groupSeen = members
    if joined > 0 then return Comms.Announce("group") end
    if next(members) ~= nil then Comms.stats.rosterQuiet = Comms.stats.rosterQuiet + 1 end
end)

-- A hello the throttle held back goes out at the next mailbox (a natural moment to be known),
-- and so does one when a skill-up crossed a material tier since the last hello (Tiers), so a
-- friend's binding stops sending what this character is now past.
ns.On("MAIL_SHOW", function()
    if pendingHello then return Comms.Announce("pending") end
    if announcedSteps and Comms.Steps(ns.Characters.Professions()) ~= announcedSteps then Comms.Announce("tier") end
end)
