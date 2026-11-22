-- Mail ledger (operator, 2026-11-07): "a player exportable log of everything that was sent,
-- in case someone ever needs to validate where items went", and, from it, what another player
-- mailed you beyond what you have mailed back ("encourage players to pay back who sent them
-- materials"; "i dont ever want to see a list of 'who owes me'").
--
-- The log: every mail this account's characters send (Mailworthy's own runs and Blizzard's
-- Send button) and every item or gold they take out of the mailbox, with the date, both
-- names, the subject, each item and count, and its value. Account-wide per realm + faction,
-- the newest LOG_MAX entries; /mw ledger's Export log puts it in the copy box.
--
-- The balance, per other player (not this account's characters, not the auction house or
-- other system mail, not cash on delivery): what they mailed you (items at their value, plus
-- gold) minus what you mailed them. Only your own side ever shows: a player you received more
-- from than you sent back ("you've received 10s more from Bob than you've sent back"). Nobody
-- is ever listed as owing you. Kept as running totals, so they outlive the log's pruning.
--
-- Values, "captured at the time of send": what you send is valued with your own prices when it
-- goes, with the age of that Auctionator scan. What you receive: when the sender's Mailworthy
-- told yours its value and scan age (a "V2" whisper right after the send, or as soon as they
-- hear from you later), the more up-to-date of the two at the time of send wins (operator,
-- 2026-11-07: "we should trust the more up to date value at time of send"): your own price as
-- it stood that day (your last scan then, or that day in Auctionator's history) against theirs;
-- a tie or an unknown age keeps the sender's. A sender's value counts at most PRICE_CAP times
-- your own, so a made-up value can't run up a debt. Without their value, your own price when
-- you take it. Without any price an item is listed by count only. When the receiver's value
-- differs from the sender's, its Mailworthy answers ("R2", held like the values until the sender
-- is heard from) and the sender's log and balance take the agreed value, so both sides match
-- (operator, 2026-11-07); an answer more than PRICE_CAP times off the sender's own is ignored.
--
-- How it sees mail: hooksecurefunc post-hooks on SendMail, TakeInboxItem, AutoLootMailItem and
-- TakeInboxMoney (AGENTS: post-hooks are allowed), confirmed by MAIL_SEND_SUCCESS and
-- MAIL_SUCCESS, dropped on MAIL_FAILED. Mailworthy's own sends are recorded by Mailer.lua
-- with exactly what it attached. Nothing here writes to a Blizzard frame or sends mail.
-- Switch: /mw feature ledger off. Unseen in game yet (README "Beta unknowns").
--
-- Four files, loaded in this order (.toc): Ledger.lua (the log and the balances), LedgerWire.lua
-- (the M2 / R2 values between Mailworthys, their outbox and expect queues), LedgerHooks.lua (the
-- mail hooks and events: what is sent and taken) and LedgerExport.lua (the export and the report).
-- What only they share is on Ledger.internal; everything else is ns.Ledger as before.
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

Ledger.LOG_MAX = 2000      -- log entries kept per realm + faction (the balances are kept apart)
Ledger.PRICE_CAP = 3       -- a sender's value counts at most 3x the receiver's own price
Ledger.EXPECT_DAYS = 31    -- a sender's values wait this long for the mail (mail lasts 30 days)
Ledger.OUTBOX_DAYS = 30    -- values for a player not heard from wait this long
Ledger.MAX_EXPECT = 200    -- values kept per sender
Ledger.MAX_COPPER = 1e9    -- 100,000g: anything above is not a value
Ledger.MAX_COUNT = 1000
Ledger.MAX_NAMES = 30      -- item names kept per player and direction
Ledger.RECEIVE_SLOTS = 16  -- ATTACHMENTS_MAX_RECEIVE
Ledger.CHAT_DELAY = 1      -- seconds: takes from one sender in this window share a chat line

local Util = ns.Util
local call = Util.Call

local now = Util.Now
local function clean(name) return ns.Routes.Clean(name) end
local function money(c) return ns.Valuation.Money(c) end

local tableOr = Util.Table

local function store()
    local s = Util.Store(MailworthyDB, "ledger", (Util.RealmKey()))
    s.log, s.players, s.expect, s.outbox = tableOr(s.log), tableOr(s.players), tableOr(s.expect), tableOr(s.outbox)
    return s
end
Ledger.Store = store

function Ledger.On() return ns.Features.On("ledger") end

--- Pure: "[Linen Cloth]" out of an item link, or nil.
function Ledger.NameOf(link)
    return Util.LinkName(link)
end

--- Is `name` this character, another character of this account here, or the bank alt?
function Ledger.IsOwn(name)
    name = clean(name)
    if not name then return false end
    local lower = name:lower()
    if lower == tostring(ns.PlayerName()):lower() then return true end
    for _, c in ipairs(ns.Characters.Mailable()) do
        if tostring(c.name):lower() == lower then return true end
    end
    return Util.NameKey(ns.Config.BankAlt()) == lower
end

--- The player behind a character: a Mailworthy peer whose hello lists `name` as one of their
--- characters while `name`'s own hello lists them back, else `name` itself (cleaned). Balances
--- are shown per player.
local function lists(peer, lower)
    for _, c in ipairs(type(peer) == "table" and type(peer.characters) == "table" and peer.characters or {}) do
        if tostring(c.name):lower() == lower then return true end
    end
    return false
end

-- Lower-case name -> the name its group goes by, built once from the peers' hellos and again only
-- after another Mailworthy message (Codex review: following links per record stalled the window
-- with hundreds of peers).
local ownerIndex

--- Pure: the groups in `peers` (lower-case name -> { name, characters }): two names are linked
--- when each one's own hello lists the other; linked names, followed through the whole group, go
--- by the group's alphabetically first name. Returns lower-case name -> that name.
function Ledger.Groups(peers)
    local parent = {}
    local function find(x)
        while parent[x] and parent[x] ~= x do x = parent[x] end
        return x
    end
    local names = {}
    for _, peer in pairs(type(peers) == "table" and peers or {}) do
        if type(peer) == "table" and peer.name then
            local lower = tostring(peer.name):lower()
            names[lower], parent[lower] = peer.name, parent[lower] or lower
            for _, c in ipairs(type(peer.characters) == "table" and peer.characters or {}) do
                local other = tostring(c.name):lower()
                local back = peers[other]
                if other ~= lower and type(back) == "table" and lists(back, lower) then
                    names[other], parent[other] = back.name, parent[other] or other
                    local a, b = find(lower), find(other)
                    if a ~= b then if a < b then parent[b] = a else parent[a] = b end end
                end
            end
        end
    end
    local index = {}
    for lower in pairs(names) do index[lower] = names[find(lower)] end
    return index
end

function Ledger.Owner(name)
    name = clean(name)
    if not name or not ns.Comms then return name end
    -- A hello is anyone's word: two names are one player only when each one's own hello lists the
    -- other (a stranger claiming "Bob is my alt" never takes Bob's balance); see Ledger.Groups.
    ownerIndex = ownerIndex or Ledger.Groups(ns.Comms.Peers())
    return ownerIndex[name:lower()] or name
end

--- This account's own value of one unit (copper): the price the decision rule uses (the last
--- scan, capped by the recent median), or nil without one; and the scan's age in days (nil
--- when Auctionator doesn't say).
function Ledger.UnitValue(link)
    local price = link and ns.Prices.Lookup(link)
    if type(price) ~= "table" or price.ah == nil then return nil end
    local unit = ns.Valuation.SmoothedPrice(price)
    if not unit then return nil end
    local age = tonumber(price.age)
    return math.floor(unit + 0.5), age and math.max(0, math.floor(age)) or nil
end

--- Auctionator's scan day for a server time: floor((local time - SCAN_DAY_0) / 86400), as its
--- database counts days (SCAN_DAY_0 = local midnight, Jan 1 2020; a price's age is today's scan
--- day minus its newest). The client clock's offset from the server's is applied, so "how many
--- scan days since the mail went" crosses the same boundary Auctionator does.
function Ledger.ScanDay(serverTime)
    local a = rawget(_G, "Auctionator")
    local day0 = type(a) == "table" and type(a.Constants) == "table" and tonumber(a.Constants.SCAN_DAY_0)
        or call(time, { year = 2020, month = 1, day = 1, hour = 0 }) or 0
    local offset = (call(time) or 0) - (call(GetServerTime) or call(time) or 0)
    return math.floor(((tonumber(serverTime) or 0) + offset - day0) / 86400)
end

--- Pure: our own price for one unit as it stood `daysAgo` scan days ago, and how old its scan was then.
--- `price` = Prices.Lookup's table, `unit` = today's value of it (Ledger.UnitValue). Our last scan
--- was already in when it is at least `daysAgo` old; a scan since then is newer than that day,
--- so the day comes from Auctionator's history (the latest scanned day up to it, its lowest
--- price seen), or nil when the history doesn't reach back.
function Ledger.PriceThen(price, unit, daysAgo)
    if type(price) ~= "table" or not unit then return nil end
    local age = tonumber(price.age)
    if age == nil then return unit, nil end
    age = math.max(0, math.floor(age))
    daysAgo = math.max(0, math.floor(daysAgo or 0))
    if age >= daysAgo then return unit, age - daysAgo end
    local history = type(price.history) == "table" and price.history or {}
    if not history[1] or not tonumber(history[1].day) then return nil end
    local thatDay = history[1].day + age - daysAgo
    for _, row in ipairs(history) do -- newest first
        if tonumber(row.day) and row.day <= thatDay and tonumber(row.minSeen) then
            return math.floor(row.minSeen + 0.5), thatDay - row.day
        end
    end
    return nil
end

--- Pure: the value of a received stack from the sender's (`claimed`, its scan `claimedAge` days
--- old at the time of send) and ours as it stood then (`mine`, `mineAge`); totals in copper.
--- The more up-to-date scan wins; a tie or an unknown age keeps the sender's, which counts at
--- most `cap` times ours. Returns value, source ("sender" / "capped" / "fresher" / "mine"), age.
function Ledger.Pick(claimed, claimedAge, mine, mineAge, cap)
    cap = cap or Ledger.PRICE_CAP
    if claimed == nil then return mine, mine and "mine" or nil, mineAge end
    if mine == nil then return claimed, "sender", claimedAge end
    if claimedAge ~= nil and mineAge ~= nil and mineAge < claimedAge then return mine, "fresher", mineAge end
    if claimed > mine * cap then return mine * cap, "capped", mineAge end
    return claimed, "sender", claimedAge
end

--- Pure: the priced total of an entry's items plus its gold, and how many items had no price.
function Ledger.Total(entry)
    local total, unpriced = tonumber(entry.money) or 0, 0
    for _, it in ipairs(entry.items or {}) do
        if it.value then total = total + it.value else unpriced = unpriced + 1 end
    end
    return total, unpriced
end

--- Pure: does this entry move the balance with `entry.other`? Not this account's characters,
--- not system mail (the auction house, NPCs, GMs), not cash on delivery (a sale).
function Ledger.Counts(entry)
    return not entry.own and not entry.system and (tonumber(entry.cod) or 0) == 0
end

local function remember(map, name, count)
    if not name then return end
    if map[name] == nil then
        local n = 0
        for _ in pairs(map) do n = n + 1 end
        if n >= Ledger.MAX_NAMES then return end
        map[name] = 0
    end
    map[name] = map[name] + count
end

--- Pure: apply a counted entry to a player's running totals (`p` = { received, sent, ... }).
--- A returned mail coming back is what we had sent that player, so it takes back the "sent".
function Ledger.Apply(p, entry)
    local total = Ledger.Total(entry)
    p.received, p.sent = tonumber(p.received) or 0, tonumber(p.sent) or 0
    p.inItems, p.outItems = tableOr(p.inItems), tableOr(p.outItems)
    if entry.dir == "sent" then
        p.sent = p.sent + total
        for _, it in ipairs(entry.items or {}) do remember(p.outItems, it.name, it.count or 1) end
    elseif entry.returned then
        p.sent = math.max(0, p.sent - total)
    else
        p.received = p.received + total
        for _, it in ipairs(entry.items or {}) do remember(p.inItems, it.name, it.count or 1) end
        if (tonumber(entry.money) or 0) > 0 then p.gold = (tonumber(p.gold) or 0) + entry.money end
    end
    p.at = entry.at
    return p
end

local function player(name)
    local players = store().players
    local key = tostring(name):lower()
    players[key] = tableOr(players[key])
    players[key].name = players[key].name or name
    return players[key]
end

local ledgerChanged = ns.Util.Signal("ledger")
--- fn() after the log or a balance changed (the ledger window, the mail window's line).
Ledger.OnChanged = ledgerChanged.Add
local function changed_() ledgerChanged.Fire() end

--- Add an entry to the log (and its balance when it counts). Returns the entry.
function Ledger.Add(entry)
    local s = store()
    entry.at = entry.at or now()
    entry.char = entry.char or ns.PlayerName()
    if entry.own == nil then entry.own = Ledger.IsOwn(entry.other) end
    entry.counted = Ledger.Counts(entry)
    s.log[#s.log + 1] = entry
    while #s.log > Ledger.LOG_MAX do table.remove(s.log, 1) end
    if entry.counted and entry.other then Ledger.Apply(player(entry.other), entry) end
    local total, unpriced = Ledger.Total(entry)
    ns.Log.Add("ledger", "%s %s %s: %d item(s), %s%s%s", entry.dir, entry.dir == "sent" and "to" or "from",
        tostring(entry.other), #(entry.items or {}), money(total), unpriced > 0 and (", " .. unpriced .. " unpriced") or "",
        entry.counted and "" or " (not counted)")
    changed_()
    return entry
end

-- Balances ------------------------------------------------------------------------------

--- What `name`'s player (Ledger.Owner) mailed this account beyond what it mailed them, in
--- copper (0 or less: nothing to pay back), and their records.
function Ledger.Net(name)
    local owner = Ledger.Owner(name)
    if not owner then return 0, {} end
    local net, records = 0, {}
    for _, p in pairs(store().players) do
        if type(p) == "table" and tostring(Ledger.Owner(p.name)):lower() == owner:lower() then
            net = net + (tonumber(p.received) or 0) - (tonumber(p.sent) or 0) - (tonumber(p.settled) or 0)
            records[#records + 1] = p
        end
    end
    return net, records
end

--- Pure: "20 Linen Cloth, 5 Wool Cloth" (most first, at most `max` names, "and N more").
function Ledger.ItemsText(map, max)
    local list = {}
    for name, count in pairs(type(map) == "table" and map or {}) do list[#list + 1] = { name = name, count = count } end
    table.sort(list, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.name < b.name end)
    local parts = {}
    for i, it in ipairs(list) do
        if i > (max or 3) then
            parts[#parts + 1] = string.format("and %d more", #list - (max or 3))
            break
        end
        parts[#parts + 1] = it.count .. " " .. it.name
    end
    return table.concat(parts, ", ")
end

--- The players this account received more from than it sent back, most first:
--- { { name, net, items = "20 Linen Cloth, ...", gold }, ... }. Never the other way round.
function Ledger.Debts()
    local byOwner, list = {}, {}
    for _, p in pairs(store().players) do
        if type(p) == "table" and p.name then
            local owner = Ledger.Owner(p.name)
            if not byOwner[owner:lower()] then
                local net, records = Ledger.Net(owner)
                local items, gold = {}, 0
                for _, r in ipairs(records) do
                    for n, c in pairs(tableOr(r.inItems)) do items[n] = (items[n] or 0) + c end
                    gold = gold + (tonumber(r.gold) or 0)
                end
                byOwner[owner:lower()] = true
                if net > 0 then list[#list + 1] = { name = owner, net = net, items = Ledger.ItemsText(items), gold = gold } end
            end
        end
    end
    table.sort(list, function(a, b) if a.net ~= b.net then return a.net > b.net end return a.name < b.name end)
    return list
end

--- Pure: "You've received 10s more from Bob than you've sent back." or nil (nothing to pay back).
function Ledger.DebtText(name, net)
    if not net or net <= 0 then return nil end
    return string.format("You've received %s more from %s than you've sent back.", money(net), tostring(name))
end

--- How much of what `name`'s player mailed this account has been paid back (mail sent to them and
--- what was marked paid), and the total they mailed: `paid`, `total` in copper, paid <= total (the pay-back
--- meter, docs/RECOMMENDATIONS.md; operator, 2026-11-22: "so that the debt is slowly cleared").
function Ledger.PaidBack(name)
    local net, records = Ledger.Net(name)
    local total = 0
    for _, p in ipairs(records) do total = total + (tonumber(p.received) or 0) end
    return math.max(0, total - math.max(0, net)), total
end

-- Mark part paid (operator, 2026-11-22: "Add 'Mark part paid'"): an amount paid another way (an enchant
-- cast in person, a trade), stepped 5s at a time, never more than what's owed.
Ledger.PART_STEP = 500
Ledger.PART_DEFAULT = 2000

--- Pure: the part-paid amount one step `dir` (+1 / -1) from `amount`, between one step and `net` (when
--- `net` is under a step, `net`); `amount` nil: from the default (20s).
function Ledger.StepPart(amount, dir, net)
    net = math.max(0, math.floor(tonumber(net) or 0))
    local step = Ledger.PART_STEP
    local low = math.min(step, net)
    local a = (tonumber(amount) or Ledger.PART_DEFAULT) + (dir or 0) * step
    if dir and dir > 0 and a > net then a = net end
    return math.max(low, math.min(net, a))
end

--- The player marks what they owe `name` as paid another way (a trade, a favour). Without `amount`,
--- or with one at or over what's owed, the balance starts again from zero; with a smaller amount
--- (Mark part paid) it goes down by that much. Logged ("paid", with `part` for a part).
function Ledger.MarkPaid(name, amount)
    local net, records = Ledger.Net(name)
    if net <= 0 then return false end
    amount = tonumber(amount)
    if amount and amount <= 0 then return false end
    local part = amount ~= nil and math.floor(amount) < net
    if part then
        amount = math.floor(amount)
        -- On the record that owes the most (a player's characters can be several records).
        local best, bestNet
        for _, p in ipairs(records) do
            local n = (tonumber(p.received) or 0) - (tonumber(p.sent) or 0) - (tonumber(p.settled) or 0)
            if not bestNet or n > bestNet then best, bestNet = p, n end
        end
        best.settled = (tonumber(best.settled) or 0) + amount
    else
        amount = net
        for _, p in ipairs(records) do
            p.settled = (tonumber(p.received) or 0) - (tonumber(p.sent) or 0)
        end
    end
    local s = store()
    s.log[#s.log + 1] = { at = now(), dir = "paid", char = ns.PlayerName(), other = Ledger.Owner(name), money = amount, items = {},
        counted = false, part = part or nil, left = part and (net - amount) or nil }
    ns.Log.Add("ledger", "marked %spaid: %s %s", part and "part " or "", tostring(Ledger.Owner(name)), money(amount))
    changed_()
    return true
end

-- Shared with LedgerWire / LedgerHooks / LedgerExport only (not an API for other modules).
Ledger.internal = { clean = clean, money = money, remember = remember, player = player, changed = changed_ }

ns.Comms.OnPeersChanged(function() ownerIndex = nil end) -- a hello may change the groups
ns.On("PLAYER_LOGIN", function() ownerIndex = nil end)
