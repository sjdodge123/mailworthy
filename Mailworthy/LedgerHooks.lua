-- Mail ledger, how it sees mail (Ledger.lua's header has the whole story): hooksecurefunc post-hooks
-- on SendMail, TakeInboxItem, AutoLootMailItem and TakeInboxMoney (AGENTS: post-hooks are allowed),
-- confirmed by MAIL_SEND_SUCCESS and MAIL_SUCCESS, dropped on MAIL_FAILED. Mailworthy's own sends are
-- recorded by Mailer.lua (Ledger.RecordSent) with exactly what it attached.
local _, ns = ...

local Ledger = ns.Ledger
local Util = ns.Util
local call = Util.Call
local now = Util.Now
local store = Ledger.Store
local I = Ledger.internal
local clean, money, remember = I.clean, I.money, I.remember

-- Sending -----------------------------------------------------------------------------------

--- `owed` (a payback mail, Paybacks.lua): what this account owes the recipient, in copper. A crafted item with
--- no auction price then counts its materials at this character's prices (source "craft"), never more than
--- what's still owed (operator, 2026-11-22: "count the materials, capped": a payback clears a debt, never
--- makes one).
local function valued(items, owed)
    local out = {}
    for _, it in ipairs(items or {}) do
        local link = it.link or (it.itemID and ("item:" .. it.itemID)) or nil
        local unit, age = Ledger.UnitValue(link)
        local count = tonumber(it.count) or 1
        local v = { itemID = tonumber(it.itemID), name = it.name or Ledger.NameOf(it.link) or ("item " .. tostring(it.itemID)),
            count = count, value = unit and unit * count or nil, source = unit and "mine" or nil, age = unit and age or nil }
        if not unit and owed and owed > 0 and ns.Paybacks then
            local each = ns.Paybacks.MaterialsValue(it.itemID)
            if each then
                v.value, v.source = math.min(each * count, owed), "craft"
                owed = owed - v.value
            end
        end
        out[#out + 1] = v
    end
    return out
end

--- A mail that went (MAIL_SEND_SUCCESS): { to, subject, items = { { itemID, link, name, count } },
--- money, cod }; `via` = "Mailworthy" (Mailer.lua) or "mail" (Blizzard's Send button).
function Ledger.RecordSent(mail, via)
    if not Ledger.On() or type(mail) ~= "table" then return nil end
    local other = clean(mail.to) or tostring(mail.to)
    local s = store()
    s.nextId = (tonumber(s.nextId) or 0) + 1 -- names the mail in values and answers; never reused
    -- A guild template rule's mail (Mailer.lua, Contributions.Tag): scope "guild", the rule's profession
    -- skill line and the template's revision. Blizzard's Send button never carries one.
    local guild = via == "Mailworthy" and type(mail.guild) == "table" and tonumber(mail.guild.profession) and {
        key = mail.guild.key, profession = tonumber(mail.guild.profession), rev = tonumber(mail.guild.rev) } or nil
    local owed = mail.payback and math.max(0, (Ledger.Net(other))) or nil
    local entry = Ledger.Add({ id = s.nextId, dir = "sent", other = other, subject = mail.subject,
        items = valued(mail.items, owed), money = tonumber(mail.money) or 0, cod = tonumber(mail.cod) or 0, via = via,
        scope = guild and "guild" or nil, guild = guild, payback = mail.payback or nil })
    if entry.counted then
        I.queueValues(entry)
        if ns.Paybacks then pcall(ns.Paybacks.AfterSend, entry) end -- the needs note goes with the values
    end
    return entry
end

-- What Blizzard's Send Mail tab carries, read when it changes and again in the SendMail hook
-- (the attachments may be gone by then; the last reading stands in).
local snapshot = { items = {}, money = 0, cod = 0 }
local pendingSend

local function readSendTab()
    local items = {}
    for i = 1, tonumber(rawget(_G, "ATTACHMENTS_MAX_SEND")) or 12 do
        local name, itemID, _, count = call(GetSendMailItem, i)
        if itemID then
            items[#items + 1] = { itemID = tonumber(itemID), name = name, count = tonumber(count) or 1,
                link = call(rawget(_G, "GetSendMailItemLink"), i) }
        end
    end
    return { items = items, money = tonumber((call(rawget(_G, "GetSendMailMoney")))) or 0,
        cod = tonumber((call(rawget(_G, "GetSendMailCOD")))) or 0 }
end

local function mailerBusy() return ns.Mailer and ns.Mailer.Busy() end

local function takeSnapshot()
    if Ledger.On() and not mailerBusy() then snapshot = readSendTab() end
end

local function onSendMail(to, subject)
    if mailerBusy() then return end -- Mailer.lua records its own mails
    local tab = readSendTab()
    pendingSend = { to = to, subject = subject, items = #tab.items > 0 and tab.items or snapshot.items,
        money = tab.money > 0 and tab.money or snapshot.money, cod = tab.cod > 0 and tab.cod or snapshot.cod }
end

-- Receiving -----------------------------------------------------------------------------

local pendingTakes = {} -- takes waiting for MAIL_SUCCESS / MAIL_FAILED, oldest first
-- What is queued and still waiting for the server (a second click on the same item before it
-- answers). Freed once it answers: a later mail with the same header (Mailworthy's subjects repeat,
-- "Mailworthy: Enchanting materials"; Codex review, 2026-11-18), or a retry after MAIL_FAILED, counts.
local taken = {}
local chat = {}         -- sender -> { items, total, unpriced } waiting for the chat line

local function header(i)
    local _, _, sender, subject, cash, cod, daysLeft, _, _, wasReturned, _, canReply, isGM = call(GetInboxHeaderInfo, i)
    if sender == nil then return nil end
    local invoice = call(rawget(_G, "GetInboxInvoiceInfo"), i)
    return { sender = clean(sender) or tostring(sender), subject = subject, money = tonumber(cash) or 0,
        cod = tonumber(cod) or 0, returned = wasReturned == true,
        system = canReply == false or isGM == true or invoice ~= nil,
        expires = math.floor((now() + (tonumber(daysLeft) or 0) * 86400) / 60) }
end

local function queueItem(i, a)
    local h = header(i)
    local name, itemID, _, count = call(GetInboxItem, i, a)
    if not h or not itemID then return end
    local key = table.concat({ h.sender, tostring(h.subject), h.expires, a, itemID, tostring(count) }, "|")
    if taken[key] then return end
    taken[key] = true
    pendingTakes[#pendingTakes + 1] = { key = key, h = h, itemID = tonumber(itemID), item = { itemID = tonumber(itemID), name = name,
        count = tonumber(count) or 1, link = call(rawget(_G, "GetInboxItemLink"), i, a) } }
end

local function queueMoney(i)
    local h = header(i)
    if not h or h.money <= 0 then return end
    local key = table.concat({ h.sender, tostring(h.subject), h.expires, "money", h.money }, "|")
    if taken[key] then return end
    taken[key] = true
    pendingTakes[#pendingTakes + 1] = { key = key, h = h, money = h.money }
end

local function chatLine(sender)
    local c = chat[sender]
    chat[sender] = nil
    if not c then return end
    local what = Ledger.ItemsText(c.items, 4)
    if c.gold > 0 then what = what ~= "" and (what .. " and " .. money(c.gold)) or money(c.gold) end
    local value = ""
    if next(c.items) then
        value = c.total > 0 and (" (" .. money(c.total) .. (c.unpriced > 0 and ", some without a price" or "") .. ")")
            or (c.unpriced > 0 and " (no price yet)" or "")
    end
    local owner = Ledger.Owner(sender)
    -- A payback (Paybacks.lua: the subject "Mailworthy: made for you (...)"): "Grace Thorn made you 1 Woolen Bag".
    local text = c.made and string.format("%s made you %s%s.", sender, what, value)
        or string.format("Received %s%s from %s.", what, value, sender)
    local debt = Ledger.DebtText(owner, (Ledger.Net(owner)))
    ns.Print(debt and (text .. " " .. debt) or text)
end

local function commit(take)
    local h = take.h
    local items = {}
    if take.item then
        local link, count = take.item.link or ("item:" .. take.item.itemID), take.item.count
        local unit, age = Ledger.UnitValue(link)
        local value, source = unit and unit * count or nil, unit and "mine" or nil
        local claim = not h.returned and Ledger.Claim(h.sender, take.item.itemID, count, ns.PlayerName()) or nil
        if claim then -- their value and ours, each as it stood when the mail went
            local daysAgo = Ledger.ScanDay(now()) - Ledger.ScanDay(claim.at or now())
            local mine, mineAge = Ledger.PriceThen(unit and ns.Prices.Lookup(link), unit, daysAgo)
            value, source, age = Ledger.Pick(claim.value, claim.age, mine and mine * count or nil, mineAge)
            -- A payback valued by its materials (the sender's "craft" value): at most what the sender still owed
            -- this account, so it can clear their side and never make a debt here (Paybacks.lua).
            if claim.craft and value then
                local owedHere = math.max(0, -(Ledger.Net(h.sender)))
                if value > owedHere then value, source = owedHere, "capped" end
            end
            if value and value ~= claim.value and claim.id then -- tell the sender, so both logs match
                I.queueFor(h.sender, now(), Ledger.EncodeAnswers(claim.to, h.sender, claim.id,
                    { { itemID = take.item.itemID, count = count, value = value, k = claim.k } }))
            end
        end
        items[1] = { itemID = take.item.itemID, name = take.item.name or Ledger.NameOf(take.item.link)
            or ("item " .. tostring(take.item.itemID)), count = count, value = value, source = source,
            age = value and age or nil }
    end
    local entry = Ledger.Add({ dir = "received", other = h.sender, subject = h.subject, items = items,
        money = take.money or 0, cod = h.cod, returned = h.returned or nil, system = h.system or nil, via = "mail" })
    if entry.counted and not entry.returned then
        local c = chat[h.sender]
        if not c then
            c = { items = {}, total = 0, unpriced = 0, gold = 0 }
            chat[h.sender] = c
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(Ledger.CHAT_DELAY, function() pcall(chatLine, h.sender) end)
            end
        end
        for _, it in ipairs(items) do
            remember(c.items, it.name, it.count)
            if it.value then c.total = c.total + it.value else c.unpriced = c.unpriced + 1 end
        end
        c.gold = c.gold + (take.money or 0)
        if tostring(h.subject or ""):find(": made for you", 1, true) then c.made = true end
    end
end

local function settle(itemID, ok)
    for i, take in ipairs(pendingTakes) do
        local match = (itemID == nil and take.money ~= nil) or (itemID ~= nil and take.itemID == itemID)
        if match then
            table.remove(pendingTakes, i)
            taken[take.key] = nil
            if ok then commit(take) end
            return true
        end
    end
    if ok and pendingTakes[1] then -- confirmed without a match: the oldest one
        local take = table.remove(pendingTakes, 1)
        taken[take.key] = nil
        commit(take)
        return true
    end
    return false
end

--- Test and report hook: takes still waiting for the server's answer.
function Ledger.Pending() return #pendingTakes, pendingSend ~= nil end

-- Hooks and events ----------------------------------------------------------------------

local hooked = false
function Ledger.Install()
    if hooked or not Ledger.On() or type(hooksecurefunc) ~= "function" then return end
    hooked = true
    for fn, hook in pairs({
        SendMail = function(to, subject) pcall(onSendMail, to, subject) end,
        TakeInboxItem = function(i, a) pcall(queueItem, i, a) end,
        TakeInboxMoney = function(i) pcall(queueMoney, i) end,
        AutoLootMailItem = function(i)
            for a = 1, tonumber(rawget(_G, "ATTACHMENTS_MAX_RECEIVE")) or Ledger.RECEIVE_SLOTS do pcall(queueItem, i, a) end
            pcall(queueMoney, i)
        end,
    }) do
        if type(rawget(_G, fn)) == "function" then
            local ok, err = pcall(hooksecurefunc, fn, hook)
            if not ok then ns.Log.Add("ledger", "hook %s error: %s", fn, tostring(err)) end
        end
    end
    ns.Log.Add("ledger", "mail hooks installed")
end

ns.On("PLAYER_LOGIN", function()
    if not Ledger.On() then return end
    Ledger.Prune()
    Ledger.Install()
end)
for _, event in ipairs({ "MAIL_SEND_INFO_UPDATE", "SEND_MAIL_MONEY_CHANGED", "SEND_MAIL_COD_CHANGED" }) do
    ns.On(event, takeSnapshot)
end
ns.On("MAIL_SEND_SUCCESS", function()
    local mail = pendingSend
    pendingSend = nil
    snapshot = { items = {}, money = 0, cod = 0 }
    if mail and not mailerBusy() then Ledger.RecordSent(mail, "mail") end
end)
ns.On("MAIL_SUCCESS", function(itemID) settle(tonumber(itemID), true) end)
ns.On("MAIL_FAILED", function(itemID)
    if pendingSend or mailerBusy() then -- a send failed, not a take
        pendingSend = nil
        return
    end
    settle(tonumber(itemID), false)
end)
-- Takes the server never answered by the time the mailbox closes did happen (a failure says
-- so with MAIL_FAILED, as Blizzard's Open All relies on).
ns.On("MAIL_CLOSED", function()
    while #pendingTakes > 0 do commit(table.remove(pendingTakes, 1)) end
    pendingSend, taken = nil, {}
    snapshot = { items = {}, money = 0, cod = 0 }
end)
