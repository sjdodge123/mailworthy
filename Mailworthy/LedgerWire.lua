-- Mail ledger, values between Mailworthys (Ledger.lua's header has the whole story): a sent mail's
-- per-item values go to the recipient (M2), the recipient answers when it settled on another value
-- (R2), both whispered and held in the outbox until the other side is heard from; values received
-- wait in the expect queue for the mail they describe. The kinds are registered with Comms here.
local _, ns = ...

local Ledger = ns.Ledger
local Util = ns.Util
local call = Util.Call
local now = Util.Now
local tableOr = Util.Table
local store = Ledger.Store
local I = Ledger.internal
local clean, money, player, changed_ = I.clean, I.money, I.player, I.changed

-- Values between Mailworthys --------------------------------------------------------------

--- Pure: the value messages for one sent mail: "M2|<from>|<to>|<send time>|<mail id>|<itemID>:<count>:
--- <copper>:<scan age in days, or empty>:<k>;..." split to fit Comms.MAX_MESSAGE; priced items
--- only. The mail id (Ledger.RecordSent's account counter, never reused) names the mail and k the
--- stack among the mail's stacks of that item and count, so an answer names exactly one stack
--- (Codex review: send times and "the next unsettled stack" were not unique).
function Ledger.EncodeValues(from, to, at, id, items)
    local head = string.format("M%d|%s|%s|%d|%d|", ns.Comms.VERSION, tostring(from), tostring(to), math.floor(at),
        math.floor(id))
    local messages, parts, seen = {}, {}, {}
    local function flush()
        if #parts > 0 then messages[#messages + 1] = head .. table.concat(parts, ";") end
        parts = {}
    end
    for _, it in ipairs(items or {}) do
        local key = tostring(it.itemID) .. ":" .. tostring(it.count or 1)
        seen[key] = (seen[key] or 0) + 1
        if it.value and it.itemID then
            local part = string.format("%d:%d:%d:%s:%d", it.itemID, it.count or 1, math.floor(it.value),
                tonumber(it.age) and tostring(math.floor(it.age)) or "", seen[key])
            if #head + #table.concat(parts, ";") + #part + 1 > ns.Comms.MAX_MESSAGE then flush() end
            parts[#parts + 1] = part
        end
    end
    flush()
    return messages
end

local function goodNames(a, b)
    a, b = a and clean(a), b and clean(b)
    if not a or not b or #a > ns.Comms.MAX_NAME or #b > ns.Comms.MAX_NAME then return nil end
    return a, b
end

--- Pure: the body of an "M" message (after "M2|"), or of v0.25.0's "V" message ("V2|<from>|<to>|
--- <time>|<itemID>:<count>:<copper>[:<age>];...", no mail id: its values are used, with no
--- answer), or nil: { from, to, at, id, items = { { itemID, count, value, age, k } } }. Every field
--- is checked; anything odd drops the message.
function Ledger.DecodeValues(rest, kind)
    local from, to, at, id, list
    if kind == "V" then
        from, to, at, list = tostring(rest):match("^([^|]+)|([^|]+)|(%d+)|([%d:;]+)$")
    else
        from, to, at, id, list = tostring(rest):match("^([^|]+)|([^|]+)|(%d+)|(%d+)|([%d:;]+)$")
        if not id or #id > 10 then return nil end
    end
    from, to = goodNames(from, to)
    if not from or #at > 12 then return nil end
    local items = {}
    for part in list:gmatch("[^;]+") do
        local item, count, value, age, k
        if kind == "V" then
            item, count, value, age = part:match("^(%d+):(%d+):(%d+):?(%d*)$")
        else
            item, count, value, age, k = part:match("^(%d+):(%d+):(%d+):(%d*):(%d+)$")
            if not k or #k > 2 then return nil end
        end
        if not item or #age > 3 then return nil end
        item, count, value, age = tonumber(item), tonumber(count), tonumber(value), tonumber(age)
        if item < 1 or count < 1 or count > Ledger.MAX_COUNT or value > Ledger.MAX_COPPER then return nil end
        items[#items + 1] = { itemID = item, count = count, value = value, age = age, k = tonumber(k) }
        if #items > Ledger.RECEIVE_SLOTS then return nil end
    end
    if #items == 0 then return nil end
    return { from = from, to = to, at = tonumber(at), id = tonumber(id), items = items }
end

-- lower-case name -> { name, at = GetTime() } of the last message heard from them. A whisper to
-- an offline player prints "No player named ... is currently playing" in the sender's chat, so
-- messages go at once only to a player heard within HEARD_FRESH seconds; otherwise Mailworthy
-- asks for hellos and waits for theirs, which proves they're online.
local heard = {}
Ledger.HEARD_FRESH = 60

-- Values and answers go to, and are taken from, the exact character the mail names: a hello's
-- list of "my other characters" is anyone's word, so it never decides who may read or settle a
-- mail (Codex review, 2026-11-07: a stranger listing Bob as their alt got Bob's values and could
-- answer for him).

--- Send the messages waiting for `name`, to `name` (who is online: we just heard from them).
--- Returns how many messages went.
function Ledger.Flush(name)
    name = clean(name)
    if not name or not Ledger.On() or not ns.Comms or not ns.Comms.On() then return 0 end
    local outbox, sent = store().outbox, 0
    local me = tostring(ns.PlayerName()):lower()
    local waiting, keep = outbox[name:lower()], {}
    for _, item in ipairs(type(waiting) == "table" and waiting or {}) do
        -- The outbox is account-wide, but a message names its author (the V2 sender, the R2
        -- recipient) and the other side takes it only from that character: it waits for them
        -- (Codex review: a message sent by another character was rejected, then deleted).
        local first = type(item.messages) == "table" and item.messages[1]
        local author = item.by or (type(first) == "string" and first:match("^%a%d+|([^|]+)|")) or nil
        if author and tostring(author):lower() ~= me then
            keep[#keep + 1] = item
        else
            for _, m in ipairs(type(item.messages) == "table" and item.messages or {}) do
                if ns.Comms.Whisper(name, m) then sent = sent + 1 end
            end
        end
    end
    outbox[name:lower()] = #keep > 0 and keep or nil
    if sent > 0 then ns.Log.Add("ledger", "sent %d value message(s) to %s", sent, name) end
    return sent
end

--- Another Mailworthy spoke (any message): they are online, so values waiting for them go now.
function Ledger.Heard(name)
    name = clean(name)
    if not name then return end
    heard[name:lower()] = { name = name, at = call(GetTime) or 0 }
    Ledger.Flush(name)
end

--- Hold `messages` for `name` and send them as soon as they are heard from: at once when that
--- happened within HEARD_FRESH seconds.
local function queueFor(name, at, messages)
    if not ns.Comms or not ns.Comms.On() or #messages == 0 then return end
    local key = tostring(name):lower()
    local outbox = store().outbox
    outbox[key] = tableOr(outbox[key])
    table.insert(outbox[key], { at = at, messages = messages, by = ns.PlayerName() })
    local h = heard[key]
    if h and (call(GetTime) or 0) - h.at <= Ledger.HEARD_FRESH then return Ledger.Flush(h.name) end
    ns.Comms.Ask() -- whoever is online answers with a hello, and the messages follow it
end

local function queueValues(entry)
    queueFor(entry.other, entry.at, Ledger.EncodeValues(entry.char, entry.other, entry.at, entry.id, entry.items))
end
I.queueFor, I.queueValues = queueFor, queueValues -- LedgerHooks: a sent mail's values, a taken one's answer

--- Pure: the answer messages for values a receiver settled differently: "R2|<receiver>|<mail's
--- sender>|<mail id>|<itemID>:<count>:<copper>:<k>;..." (each { itemID, count, value, k }).
function Ledger.EncodeAnswers(receiver, sender, id, items)
    local head = string.format("R%d|%s|%s|%d|", ns.Comms.VERSION, tostring(receiver), tostring(sender), math.floor(id))
    local messages, parts = {}, {}
    for _, it in ipairs(items or {}) do
        local part = string.format("%d:%d:%d:%d", it.itemID, it.count or 1, math.floor(it.value), it.k or 1)
        if #parts > 0 and #head + #table.concat(parts, ";") + #part + 1 > ns.Comms.MAX_MESSAGE then
            messages[#messages + 1] = head .. table.concat(parts, ";")
            parts = {}
        end
        parts[#parts + 1] = part
    end
    if #parts > 0 then messages[#messages + 1] = head .. table.concat(parts, ";") end
    return messages
end

--- Pure: the body of an "R" message (after "R2|"), or nil: { receiver, from (the mail's sender),
--- id, items = { { itemID, count, value, k } } }.
function Ledger.DecodeAnswers(rest)
    local receiver, from, id, list = tostring(rest):match("^([^|]+)|([^|]+)|(%d+)|([%d:;]+)$")
    receiver, from = goodNames(receiver, from)
    if not receiver or #id > 10 then return nil end
    local items = {}
    for part in list:gmatch("[^;]+") do
        local item, count, value, k = part:match("^(%d+):(%d+):(%d+):(%d+)$")
        if not item or #k > 2 then return nil end
        item, count, value, k = tonumber(item), tonumber(count), tonumber(value), tonumber(k)
        if item < 1 or count < 1 or count > Ledger.MAX_COUNT or value > Ledger.MAX_COPPER or k < 1 then return nil end
        items[#items + 1] = { itemID = item, count = count, value = value, k = k }
        if #items > Ledger.RECEIVE_SLOTS then return nil end
    end
    if #items == 0 then return nil end
    return { receiver = receiver, from = from, id = tonumber(id), items = items }
end

--- An "R" message from `whisperer`: the value a receiver settled on for stacks of a mail one of
--- this account's characters sent. That mail (its id, sender and recipient; counted mails only)
--- and stack (the k-th of that item and count in it) take the value, once, when the receiver is
--- the whisperer and the value is within PRICE_CAP times either way of our own; the balance moves
--- by the difference. Returns how many stacks changed.
function Ledger.HearAnswers(whisperer, msg)
    whisperer = clean(whisperer)
    if not whisperer or type(msg) ~= "table" or not Ledger.On() or not Ledger.IsOwn(msg.from) then return 0 end
    if msg.receiver:lower() ~= whisperer:lower() then
        ns.Log.Add("ledger", "answer from %s for %s dropped: not the recipient", whisperer, msg.receiver)
        return 0
    end
    local entry
    for _, e in ipairs(store().log) do
        if e.dir == "sent" and e.counted and e.id == msg.id and tostring(e.other):lower() == msg.receiver:lower()
            and tostring(e.char):lower() == msg.from:lower() then entry = e end
    end
    if not entry then return 0 end
    local changed = 0
    for _, a in ipairs(msg.items) do
        local n, it = 0, nil
        for _, x in ipairs(entry.items or {}) do
            if x.itemID == a.itemID and x.count == a.count then
                n = n + 1
                if n == a.k then it = x end
            end
        end
        if it and it.value and not it.agreed and a.value * Ledger.PRICE_CAP >= it.value
            and a.value <= it.value * Ledger.PRICE_CAP then
            local delta = a.value - it.value
            it.mine, it.value, it.agreed, it.source = it.value, a.value, entry.other, "agreed"
            local p = player(entry.other)
            p.sent = math.max(0, (tonumber(p.sent) or 0) + delta)
            changed = changed + 1
        elseif it and it.value and not it.agreed then
            ns.Log.Add("ledger", "answer from %s for %s ignored: %s against our %s", whisperer, tostring(it.name),
                money(a.value), money(it.value))
        end
    end
    if changed > 0 then
        ns.Log.Add("ledger", "%s's values agreed for %d stack(s) of mail %d", msg.receiver, changed, msg.id)
        changed_()
    end
    return changed
end

--- A "V" message from `sender`: the values of a mail sent to one of this account's characters.
--- `from` (the mail's sender) must be the whisperer.
function Ledger.HearValues(sender, msg)
    sender = clean(sender)
    if not sender or type(msg) ~= "table" or not Ledger.On() then return nil end
    if not Ledger.IsOwn(msg.to) then return nil end
    if msg.from:lower() ~= sender:lower() then
        ns.Log.Add("ledger", "values from %s for %s's mail dropped: not the sender", sender, msg.from)
        return nil
    end
    local at = now()
    if msg.at > at + 600 or msg.at < at - Ledger.EXPECT_DAYS * 86400 then return nil end
    local expect = store().expect
    local key = msg.from:lower()
    expect[key] = tableOr(expect[key])
    for _, it in ipairs(msg.items) do
        table.insert(expect[key], { at = msg.at, to = msg.to, itemID = it.itemID, count = it.count, value = it.value,
            age = it.age, id = msg.id, k = it.k })
    end
    while #expect[key] > Ledger.MAX_EXPECT do table.remove(expect[key], 1) end
    ns.Log.Add("ledger", "values from %s: %d item(s) mailed to %s", msg.from, #msg.items, msg.to)
    return msg
end

--- The sender's value for `count` of `itemID` that `from` mailed to `to` (the character taking
--- it), used once (the oldest match), or nil: { value, age (their scan's age at send, or nil), at
--- (when they sent it), to }.
function Ledger.Claim(from, itemID, count, to)
    local list = store().expect[tostring(clean(from)):lower()]
    if type(list) ~= "table" then return nil end
    for i, e in ipairs(list) do
        if e.itemID == itemID and e.count == count and tostring(e.to):lower() == tostring(clean(to)):lower() then
            table.remove(list, i)
            return tonumber(e.value) and { value = tonumber(e.value), age = tonumber(e.age), at = tonumber(e.at), to = e.to,
                id = tonumber(e.id), k = tonumber(e.k) } or nil
        end
    end
    return nil
end

--- Drop values nobody claimed in EXPECT_DAYS and messages nobody picked up in OUTBOX_DAYS.
function Ledger.Prune(at)
    at = at or now()
    local s = store()
    for key, list in pairs(s.expect) do
        local keep = {}
        for _, e in ipairs(tableOr(list)) do
            if (tonumber(e.at) or 0) >= at - Ledger.EXPECT_DAYS * 86400 then keep[#keep + 1] = e end
        end
        s.expect[key] = #keep > 0 and keep or nil
    end
    for key, list in pairs(s.outbox) do
        local keep = {}
        for _, e in ipairs(tableOr(list)) do
            if (tonumber(e.at) or 0) >= at - Ledger.OUTBOX_DAYS * 86400 then keep[#keep + 1] = e end
        end
        s.outbox[key] = #keep > 0 and keep or nil
    end
end

ns.Comms.OnHeard(function(name) Ledger.Heard(name) end) -- online: values waiting for them go now

-- The kinds (Comms.Register): whispered only, to and from the character a mail names.
ns.Comms.Register("M", {
    kind = "values",
    module = "Ledger",
    channels = { WHISPER = true },
    decode = function(rest)
        local values = ns.Ledger.DecodeValues(rest, "M")
        return values and { values = values } or nil
    end,
    hear = function(name, msg) return ns.Ledger.HearValues(name, msg.values) end,
})
-- v0.25.0's values (no mail id): no longer sent, still read.
ns.Comms.Register("V", {
    kind = "values",
    module = "Ledger",
    channels = { WHISPER = true },
    decode = function(rest)
        local values = ns.Ledger.DecodeValues(rest, "V")
        return values and { values = values } or nil
    end,
    hear = function(name, msg) return ns.Ledger.HearValues(name, msg.values) end,
})
ns.Comms.Register("R", {
    kind = "answers",
    module = "Ledger",
    channels = { WHISPER = true },
    decode = function(rest)
        local answers = ns.Ledger.DecodeAnswers(rest)
        return answers and { answers = answers } or nil
    end,
    hear = function(name, msg) return ns.Ledger.HearAnswers(name, msg.answers) end,
})

