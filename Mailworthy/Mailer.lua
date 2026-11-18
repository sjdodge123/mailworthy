-- Sending: the scan's mail list goes to the saved bank alt, 12 stacks per mail,
-- after one press of Send; items a binding diverts (Routes) go to that player in
-- their own mails, after the bank alt's, and so do items going back to their sender
-- (Return to sender, Returns.lua: their own mails, subject "returned to you").
-- Every recipient is shown in the window. Each mail: clear the send tab, re-check every slot
-- right before attaching it (same item, same count, not locked by the game or by
-- Mailworthy, not bound; anything that changed is skipped), attach with
-- UseContainerItem, zero money and COD (as Blizzard's Send button does), then
-- SendMail. The next mail follows MAIL_SEND_SUCCESS without another press
-- (measured: alpha2 send test). It stops on MAIL_FAILED, a closed mailbox,
-- combat, the Send Mail tab going away, or no answer within 10 s.
--
-- QoL pass (operator, 2026-11-09, media/qol-prototype.png): the player can stop a run
-- (Mailer.RequestStop: a mail waiting for the game's answer is counted first, then the rest is
-- given back), nothing is sent the player can't pay the postage for (Mailer.Short before Send,
-- GetSendMailPrice against GetMoney before each SendMail), and a run ends with a receipt
-- (Mailer.Receipt, Mailer.ReceiptText): what went, to whom, its gain, what stayed and why.
--
-- A money reserve (operator, 2026-11-14: "you should always have a reserve of 5s before
-- mailworthy will auto send"): postage never takes the player below Mailer.RESERVE, before Send
-- (Mailer.Short) and before each SendMail alike.
local _, ns = ...

local Mailer = {}
ns.Mailer = Mailer

Mailer.PER_MAIL = 12 -- stacks per mail (ATTACHMENTS_MAX_SEND, measured); Bags.Evaluate counts mails by it too
Mailer.DELAY = 0.5
Mailer.TIMEOUT = 10
Mailer.SUBJECT = "Mailworthy"
Mailer.RETURN_WHAT = "returned to you"
Mailer.KEEP_DAYS = 30
Mailer.RESERVE = 500 -- copper the player keeps after postage: 5s

local state = { busy = false, run = 0 }
Mailer.state = state
local changed, sent = ns.Util.Signal("mailer changed"), ns.Util.Signal("mailer sent")

local Util = ns.Util
local call = Util.Call

-- Timers belong to one send run: once that run stops (combat, mailbox closed,
-- failure) or a new one starts, its pending timers do nothing.
local function after(delay, fn)
    local myRun = state.run
    local function run()
        if not state.busy or state.run ~= myRun then return end
        local ok, err = pcall(fn)
        if not ok then
            ns.Log.Add("mailer", "error: %s", tostring(err))
            Mailer.Stop("error: " .. tostring(err))
        end
    end
    Util.After(delay, run)
end

Mailer.OnChanged = changed.Add

--- fn(mailsSent) once a send run has mailed everything it planned.
Mailer.OnSent = sent.Add
local function notify() changed.Fire() end

local function setStatus(text, ...)
    state.status = string.format(text, ...)
    ns.Log.Add("mailer", "%s", state.status)
    notify()
end

function Mailer.Status() return state.status end
function Mailer.Busy() return state.busy end
--- True once the player pressed Stop while a mail was waiting for the game's answer.
function Mailer.Stopping() return state.busy and state.stopRequested ~= nil end

--- Pure: can the player pay `price` (copper) out of `have` and still keep Mailer.RESERVE?
function Mailer.Affords(price, have)
    return price + Mailer.RESERVE <= have
end

--- Pure: "; Mailworthy keeps 5s on you" (the reserve, for the messages that refuse a send).
function Mailer.ReserveText()
    return "; Mailworthy keeps " .. ns.Valuation.Money(Mailer.RESERVE) .. " on you"
end

--- What the mail list costs to send and what the player has, when that isn't enough to pay it
--- and keep Mailer.RESERVE: need (the postage), have (copper); nil when it is. When the game
--- doesn't say what the player has, need and a nil `have`: nothing goes on money it can't check
--- (Codex review, 2026-11-14; before, the check was skipped). `items` is the scan's mail list
--- (each item's result.postage: Valuation's postage for its stacks).
function Mailer.Short(items)
    local need = 0
    for _, item in ipairs(items or {}) do need = need + (tonumber(item.result and item.result.postage) or 0) end
    local have = call(GetMoney)
    if type(have) ~= "number" then return need, nil end
    if not Mailer.Affords(need, have) then return need, have end
    return nil
end

--- Pure: split the items to mail into mails of PER_MAIL stacks each, per recipient: the
--- bank alt's mails first, then one run per binding (an item's result.to and what) in the
--- order they appear. Returns { { to, what, stacks = { {bag, slot, count, itemID, link,
--- item} ... } }, ... }; `to` is nil for the bank alt's mails when no bank alt is given,
--- `what` ("Enchanting materials") only for a binding's (and a return's, with `returning`).
function Mailer.Plan(items, bankAlt)
    local groups, order = {}, {}
    for _, item in ipairs(items) do
        local r = item.result or {}
        local key = r.to and (r.to .. "|" .. tostring(r.what)) or ""
        if not groups[key] then
            groups[key] = { to = r.to or bankAlt, what = r.to and r.what or nil, items = {},
                returning = r.to ~= nil and r.route == "return" or nil }
            if key == "" then table.insert(order, 1, key) else order[#order + 1] = key end
        end
        table.insert(groups[key].items, item)
    end
    local mails = {}
    for _, key in ipairs(order) do
        local group, currentMail = groups[key], nil
        for _, item in ipairs(group.items) do
            for _, s in ipairs(item.slots) do
                if not currentMail or #currentMail.stacks >= Mailer.PER_MAIL then
                    currentMail = { to = group.to, what = group.what, returning = group.returning, stacks = {} }
                    mails[#mails + 1] = currentMail
                end
                currentMail.stacks[#currentMail.stacks + 1] = { bag = s.bag, slot = s.slot, count = s.count,
                    itemID = item.itemID, link = item.link, item = item }
            end
        end
    end
    return mails
end

local function sendTabShown()
    local frame = rawget(_G, "SendMailFrame")
    return type(frame) == "table" and call(frame.IsShown, frame) == true
end

--- Why sending can't start right now, or nil when it can. Every mail needs a recipient
--- that isn't this character: the bank alt for the bank alt's mails, the bound player
--- for a binding's. Without a bank alt (optional since 2026-11-08) only bindings' mails go.
function Mailer.Blocker(bankAlt, mails)
    if state.busy then return "already sending" end
    local me = tostring(ns.PlayerName()):lower()
    local anyToAlt = not mails or #mails == 0
    for _, mail in ipairs(mails or {}) do
        if not mail.what then anyToAlt = true end
        if mail.what and mail.to and tostring(mail.to):lower() == me then
            return "a binding points at this character: remove it"
        end
    end
    if anyToAlt then
        -- A mail for the bank alt with none set (Bags holds that share, so only a stale plan).
        if not bankAlt and mails and #mails > 0 then return "no bank alt set: press Settings" end
        if tostring(bankAlt):lower() == me then return "this character is the bank alt" end
    end
    if InCombatLockdown() then return "not in combat" end
    if not sendTabShown() then return "switch to the Send Mail tab first" end
    if not mails or #mails == 0 then return "nothing to mail" end
    -- Short on postage: nothing goes until the whole list can be paid for (QoL pass, 2026-11-09),
    -- with Mailer.RESERVE left over (operator, 2026-11-14).
    local items, seen = {}, {}
    for _, mail in ipairs(mails) do
        for _, stack in ipairs(mail.stacks) do
            if stack.item and not seen[stack.item] then
                seen[stack.item] = true
                items[#items + 1] = stack.item
            end
        end
    end
    local need, have = Mailer.Short(items)
    if need and not have then return "Mailworthy can't read your money" end
    if need then
        return string.format("postage is %s and you have %s%s", ns.Valuation.Money(need), ns.Valuation.Money(have),
            Mailer.ReserveText())
    end
    return nil
end

-- The mailer's words for Bags.StillThere's checks (the stayed list and the log show them).
local RECHECK = {
    read = function(bag, slot) return call(C_Container and C_Container.GetContainerItemInfo, bag, slot) end,
    bound = true,
    words = { gone = "gone", different = "a different item", count = "count changed", inUse = "in use",
        bound = "soulbound", conjured = "conjured", ammo = "ammo", locked = "locked", quest = "an active quest needs it" },
}

--- Is this bag slot still exactly what the preview showed? (Bags.StillThere: the shared re-check.)
function Mailer.StillThere(stack)
    return ns.Bags.StillThere(stack, RECHECK)
end

local function attachedCount()
    local n = 0
    for i = 1, tonumber(ATTACHMENTS_MAX_SEND) or Mailer.PER_MAIL do
        if call(GetSendMailItem, i) then n = n + 1 end
    end
    return n
end

local function record(mail)
    local mailed, now = Util.Store(MailworthyDB, "mailed"), Util.Now()
    for _, stack in ipairs(mail.attached or {}) do
        local r = stack.item.result or {}
        mailed[stack.itemID] = { route = r.route, listRoute = r.listRoute, reason = r.reason, gain = r.gain, at = now,
            from = ns.PlayerName(), to = mail.to }
    end
end

--- Drop records older than KEEP_DAYS.
function Mailer.Prune(now)
    now = now or Util.Now()
    for itemID, entry in pairs(Util.Table(MailworthyDB.mailed)) do
        if type(entry) ~= "table" or (tonumber(entry.at) or 0) < now - Mailer.KEEP_DAYS * 86400 then
            MailworthyDB.mailed[itemID] = nil
        end
    end
end

local sendNext

-- The receipt of the run that just ended (`stopped`: why it ended early, nil when it mailed
-- everything it planned): what the mails that went carried. An item's gain is the scan's, for
-- all its stacks: a stack's share is by count.
local function finish(stopped)
    local receipt = { sent = state.sent, planned = #(state.mails or {}), stacks = state.stacks, gain = 0,
        priced = false, recipients = {}, stayed = state.stayed or {}, stopped = stopped }
    local seen, went, order = {}, {}, {}
    for _, mail in ipairs(state.mails or {}) do
        if mail.sent then
            local to = tostring(mail.to)
            if not seen[to:lower()] then
                seen[to:lower()] = true
                receipt.recipients[#receipt.recipients + 1] = to
            end
            for _, stack in ipairs(mail.attached or {}) do
                local item = stack.item
                if item then
                    went[item] = went[item] or { count = 0, stacks = 0 }
                    went[item].count, went[item].stacks = went[item].count + stack.count, went[item].stacks + 1
                    if not order[item] then
                        order[item] = true
                        order[#order + 1] = item
                    end
                end
            end
        end
    end
    for _, item in ipairs(order) do
        local gain = Mailer.GainOf(item, went[item].count, went[item].stacks, state.settings)
        if gain then
            receipt.priced = true
            receipt.gain = receipt.gain + gain
        end
    end
    state.receipt = receipt
end

--- The gain (over vendoring) of the `count` units in `stacks` stacks of a scan item that went, or
--- nil when it has none to count: no price, or it went to a binding or back to its sender (the
--- window's total leaves those out too). All of it went: the scan's own figure. Part of it (a
--- stopped run, a skipped stack): valued again for what went, since postage and deposits go by
--- the stack, not by the unit (Codex review, 2026-11-09), with the settings the list was scanned
--- with (`settings`: a listing length changed mid-run doesn't move the figure).
function Mailer.GainOf(item, count, stacks, settings)
    local r = item.result
    if type(r) ~= "table" or r.to or tonumber(r.gain) == nil then return nil end
    if count == item.count and stacks == item.stacks then return r.gain end
    local part = setmetatable({ count = count, stacks = stacks }, { __index = item })
    local ok, again = pcall(function() return ns.Valuation.Evaluate(part, item.price, settings or ns.Bags.CurrentSettings())
    end)
    if ok and type(again) == "table" and tonumber(again.gain) then return again.gain end
    return nil
end

--- The last run's receipt (see `finish`), or nil: none yet, a run is on, or it was dismissed.
function Mailer.Receipt() return not state.busy and state.receipt or nil end

--- The player changed the list after a run: its receipt and status no longer describe it.
function Mailer.Dismiss()
    if state.busy then return end
    state.receipt, state.status = nil, nil
end

local function plural(n, one, many) return string.format("%d %s", n, n == 1 and one or (many or one .. "s")) end
local function itemName(link) return Util.LinkName(link) or tostring(link) end
local function firstNames(names)
    local out = {}
    for i, name in ipairs(names) do out[i] = tostring(name):match("^(%S+)") or tostring(name) end
    return out
end
local function andList(names) return Util.ListText(names, "nobody") end

--- Pure: the receipt as text (media/qol-prototype.png, "After: a receipt"). `vendorLeft`: items
--- left in the bags for the vendor. Returns the window's headline, its note (may be ""), and the
--- one chat line.
function Mailer.ReceiptText(r, vendorLeft)
    local money = ns.Valuation.Money
    local gain = r.priced and r.gain > 0 and ("+" .. money(r.gain)) or nil
    local head, chat
    if r.stopped then
        head = string.format("Stopped after %d of %s: %s.", r.sent, plural(r.planned, "mail"), r.stopped)
        chat = head
        if r.sent > 0 then
            local went = string.format(" Sent to %s%s.", andList(firstNames(r.recipients)), gain and (": " .. gain) or "")
            head, chat = head .. went, chat .. string.format(" Sent %s to %s%s.", plural(r.stacks, "stack"),
                andList(r.recipients), gain and (": " .. gain .. " more than vendoring") or "")
        end
    elseif r.sent == 0 then
        head = "Nothing was sent."
        chat = head
    else
        head = string.format("Sent %s to %s%s", plural(r.sent, "mail"), andList(firstNames(r.recipients)),
            gain and (": " .. gain) or ".")
        chat = string.format("Sent %s (%s) to %s%s.", plural(r.sent, "mail"), plural(r.stacks, "stack"),
            andList(r.recipients), gain and (": " .. gain .. " more than vendoring") or "")
    end
    local notes = {}
    if #r.stayed > 0 then
        local first = r.stayed[1]
        local more = #r.stayed > 1 and string.format(" and %d more", #r.stayed - 1) or ""
        notes[#notes + 1] = string.format("%s stayed: %s (%s)%s. Check the list.", plural(#r.stayed, "stack"),
            itemName(first.link), first.why, more)
        chat = chat .. string.format(" %s stayed (%s: %s%s).", plural(#r.stayed, "stack"), itemName(first.link),
            first.why, more)
    end
    if (vendorLeft or 0) > 0 then
        notes[#notes + 1] = string.format("%s left for the vendor.", plural(vendorLeft, "item"))
        chat = chat .. " " .. notes[#notes]
    end
    return head, table.concat(notes, "\n"), chat
end

local function waitFor(index)
    after(Mailer.TIMEOUT, function()
        if state.busy and state.waiting == index then
            Mailer.Stop(string.format("no answer from the game for mail %d", index))
        end
    end)
end

--- The subject of mails[index], numbered among the mails to the same recipient only
--- (operator, 2026-11-18): the bank alt's 1/3 next to two friends' 2/3 and 3/3 read as mail
--- missing. "Mailworthy 2/3" when that player gets three, plain "Mailworthy" when one; a
--- binding's mail adds what it carries ("Mailworthy: Enchanting materials"), a return
--- "returned to you". Pure.
function Mailer.Subject(mails, index)
    local mail = mails[index]
    -- The name as mail wants it (Util.NameKey): a bank alt saved with its realm and a binding
    -- without it are one player (Codex review, 2026-11-18).
    local function key(to) return Util.NameKey(to) or tostring(to):lower() end
    local who = key(mail.to)
    local nth, of = 0, 0
    for i, other in ipairs(mails) do
        if key(other.to) == who then
            of = of + 1
            if i <= index then nth = of end
        end
    end
    local subject = Mailer.SUBJECT
    if of > 1 then subject = string.format("%s %d/%d", subject, nth, of) end
    local what = mail.returning and Mailer.RETURN_WHAT or mail.what
    if what then subject = subject .. ": " .. tostring(what) end
    return subject
end

local function sendMail(index)
    local mail = state.mails[index]
    if not sendTabShown() then return Mailer.Stop("the Send Mail tab closed") end
    local n = attachedCount()
    if n == 0 then
        -- Everything in this mail changed since the preview: skip it.
        ns.Log.Add("mailer", "mail %d: nothing attached, skipped", index)
        return sendNext(index + 1)
    end
    if n ~= #mail.attached then
        pcall(ClearSendMail)
        return Mailer.Stop(string.format("mail %d: %d attached, expected %d; nothing sent", index, n, #mail.attached))
    end
    -- A bow, crossbow or gun equipped while the stacks sat attached (Mailer.DELAY; Codex review,
    -- 2026-11-14): its ammo stays. Give everything back and send nothing more.
    local fires = ns.Ammo.Equipped()
    for _, stack in ipairs(mail.attached) do
        if ns.Ammo.Is(stack.link, fires) then
            pcall(ClearSendMail)
            return Mailer.Stop(string.format("mail %d: %s is ammo for your ranged weapon now; nothing sent",
                index, tostring(stack.link)))
        end
    end
    pcall(SetSendMailCOD, 0)
    pcall(SetSendMailMoney, 0)
    -- The game's own check before its Send button (MailFrame.lua): what this mail costs
    -- against what the player has, keeping Mailer.RESERVE. Short: give the attachments back,
    -- send nothing more.
    local price, have = call(GetSendMailPrice), call(GetMoney)
    -- Either one unreadable: nothing goes on money Mailworthy can't check (Codex review, 2026-11-14).
    if type(price) ~= "number" or type(have) ~= "number" then
        return Mailer.Stop(string.format("Mailworthy can't read the postage for mail %d or your money", index))
    end
    if not Mailer.Affords(price, have) then
        return Mailer.Stop(string.format("postage for mail %d is %s and you have %s%s", index,
            ns.Valuation.Money(price), ns.Valuation.Money(have), Mailer.ReserveText()))
    end
    state.waiting = index
    ns.lastCommand = string.format("Mailworthy send %d/%d", index, #state.mails)
    -- No body (operator, 2026-11-11): a mail with text keeps a letter to take after its items,
    -- so the recipient had to delete every one; with none it goes away once emptied.
    local subject = Mailer.Subject(state.mails, index)
    mail.subject = subject
    local ok, err = pcall(SendMail, mail.to, subject, "")
    ns.Log.Add("mailer", "SendMail %q to %s with %d stacks: %s", subject, tostring(mail.to), n, ok and "called" or tostring(err))
    if not ok then return Mailer.Stop("SendMail failed: " .. tostring(err)) end
    setStatus("Sending mail %d of %d to %s...", index, #state.mails, tostring(mail.to))
    waitFor(index)
end

sendNext = function(index)
    if not state.busy then return end
    if index > #state.mails then
        state.busy = false
        finish(nil)
        setStatus("Sent %d mail(s), %d stacks, to %s.", state.sent, state.stacks, Mailer.Recipients(state.mails, true))
        -- One short sound (the kit Forever's own MailFrame.lua plays); a missing kit plays nothing.
        local kit = rawget(_G, "SOUNDKIT")
        if state.sent > 0 and type(kit) == "table" and kit.IG_MAINMENU_OPTION_CHECKBOX_ON then
            pcall(PlaySound, kit.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        sent.Fire(state.sent)
        return
    end
    if InCombatLockdown() then return Mailer.Stop("combat") end
    if not sendTabShown() then return Mailer.Stop("the Send Mail tab closed") end
    local mail = state.mails[index]
    pcall(ClearSendMail)
    mail.attached = {}
    for _, stack in ipairs(mail.stacks) do
        local ok, why = Mailer.StillThere(stack)
        if ok then
            local okUse, err = pcall(C_Container.UseContainerItem, stack.bag, stack.slot)
            if okUse then
                mail.attached[#mail.attached + 1] = stack
            else
                ns.Log.Add("mailer", "attach %s failed: %s", tostring(stack.link), tostring(err))
            end
        else
            state.skipped = state.skipped + 1
            state.stayed[#state.stayed + 1] = { link = stack.link, itemID = stack.itemID, count = stack.count, why = why }
            ns.Log.Add("mailer", "skipped %s (bag %d slot %d): %s", tostring(stack.link), stack.bag, stack.slot, why)
        end
    end
    after(Mailer.DELAY, function() sendMail(index) end)
end

--- Pure: "Roknua Themicrulah and Bob Surname" (the distinct recipients of `mails`, in order;
--- `sentOnly` counts only mails that went).
function Mailer.Recipients(mails, sentOnly)
    local names, seen = {}, {}
    for _, mail in ipairs(mails or {}) do
        local to = tostring(mail.to)
        if (not sentOnly or mail.attached and mail.sent) and not seen[to:lower()] then
            seen[to:lower()] = true
            names[#names + 1] = to
        end
    end
    return Util.ListText(names, "nobody")
end

--- One press: send every mail in the plan: the bank alt's, then each binding's.
--- `settings`: the scan's (Bags.Evaluate's result.settings), for the receipt's figures.
function Mailer.Start(items, bankAlt, settings)
    local mails = Mailer.Plan(items or {}, bankAlt)
    local blocker = Mailer.Blocker(bankAlt, mails)
    if blocker then
        setStatus("Can't send: %s.", blocker)
        return false
    end
    state.run = state.run + 1
    state.busy, state.mails, state.bankAlt, state.settings = true, mails, bankAlt, settings
    state.sent, state.stacks, state.skipped, state.waiting = 0, 0, 0, nil
    state.stayed, state.receipt, state.stopRequested, state.pending = {}, nil, nil, nil
    ns.Log.Add("mailer", "start: %d mail(s) to %s", #mails, Mailer.Recipients(mails))
    sendNext(1)
    return true
end

function Mailer.Stop(reason)
    if not state.busy then return end
    -- Give back what this run attached, unless a mail is already on its way.
    if not state.waiting and sendTabShown() then pcall(ClearSendMail) end
    -- A mail still with the game may yet go: its answer is credited when it comes (MAIL_SEND_SUCCESS).
    state.pending = state.waiting and state.mails and state.mails[state.waiting] or nil
    state.busy, state.waiting, state.stopRequested = false, nil, nil
    finish(tostring(reason))
    setStatus("Stopped after %d of %d mail(s): %s.", state.sent, #(state.mails or {}), tostring(reason))
end

--- The player's Stop (the window's Send button while a run is on). Between mails: stop now,
--- what is attached goes back. While a mail waits for the game's answer it can't be called
--- back: the run ends when the answer comes, so that mail is counted and logged like any other.
function Mailer.RequestStop(reason)
    if not state.busy then return end
    reason = reason or "stopped by you"
    if not state.waiting then return Mailer.Stop(reason) end
    state.stopRequested = reason
    setStatus("Stopping after mail %d of %d...", state.waiting, #state.mails)
end

-- A mail the game confirmed: counted, remembered (`mailed`), logged (the mail ledger) and, for a
-- guild rule's, counted for the guild.
local function credit(mail)
    state.sent = state.sent + 1
    state.stacks = state.stacks + #mail.attached
    mail.sent = true
    record(mail)
    -- A guild template rule's mail (Contributions.lua): its rule, revision and stack units, or nil.
    local okTag, guild = pcall(ns.Contributions.Tag, mail)
    if not okTag then
        ns.Log.Add("mailer", "contributions error: %s", tostring(guild))
        guild = nil
    end
    if ns.Ledger then -- the mail log and the balance with a friend (Ledger.lua): exactly what was attached
        local items = {}
        for _, stack in ipairs(mail.attached) do
            items[#items + 1] = { itemID = stack.itemID, link = stack.link, count = stack.count }
        end
        local okLog, err = pcall(ns.Ledger.RecordSent, { to = mail.to, subject = mail.subject, items = items,
            guild = guild }, "Mailworthy")
        if not okLog then ns.Log.Add("mailer", "ledger error: %s", tostring(err)) end
    end
    if guild then -- the guild contributions count it (not mail to this account's own characters)
        local okCount, err = pcall(ns.Contributions.Count, mail.to, guild)
        if not okCount then ns.Log.Add("mailer", "contributions error: %s", tostring(err)) end
    end
end

ns.On("MAIL_SEND_SUCCESS", function()
    if not state.busy then
        -- The run was stopped (combat, the mailbox closed, no answer in time) while a mail was
        -- with the game, and the game now says it went: it is counted and logged like any other,
        -- and the receipt corrected (Codex review, 2026-11-09: before, it went unrecorded).
        local mail = state.pending
        if not mail then return end
        state.pending = nil
        credit(mail)
        ns.Log.Add("mailer", "MAIL_SEND_SUCCESS after the stop: the mail to %s is counted", tostring(mail.to))
        local why = state.receipt and state.receipt.stopped or "stopped"
        finish(why)
        setStatus("Stopped after %d of %d mail(s): %s.", state.sent, #(state.mails or {}), why)
        return
    end
    if not state.waiting then return end
    local index = state.waiting
    local mail = state.mails[index]
    state.waiting = nil
    credit(mail)
    ns.Log.Add("mailer", "MAIL_SEND_SUCCESS for mail %d", index)
    if state.stopRequested then
        if index >= #state.mails then return sendNext(index + 1) end -- it was the last one: all sent
        return Mailer.Stop(state.stopRequested)
    end
    notify()
    after(Mailer.DELAY, function() sendNext(index + 1) end)
end)
ns.On("MAIL_FAILED", function()
    state.pending = nil -- the mail a stopped run left with the game didn't go
    if state.busy then
        pcall(ClearSendMail)
        -- The game answered: no mail is on its way, so Stop keeps none to credit later (a mail the
        -- player then sends by hand must not count as this one: Codex review, 2026-11-09).
        state.waiting = nil
        Mailer.Stop("the game refused the mail (MAIL_FAILED)")
    end
end)
ns.On("UI_ERROR_MESSAGE", function(_, message)
    if state.busy then ns.Log.Add("mailer", "UI error: %s", tostring(message)) end
end)
ns.On("MAIL_CLOSED", function() Mailer.Stop("the mailbox closed") end)
ns.On("PLAYER_REGEN_DISABLED", function() Mailer.Stop("combat") end)
ns.On("PLAYER_LOGIN", function() Mailer.Prune() end)
ns.On("MAIL_SHOW", function()
    if not state.busy then state.status, state.receipt, state.pending = nil, nil, nil end
end)
