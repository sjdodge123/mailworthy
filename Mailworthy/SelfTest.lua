-- Discovery self-test (docs/DISCOVERY-SESSION-2.md): the active checks a
-- read-only probe can't make. Attach test (postage with 0/1/2 items, attaching
-- on a button press and from a timer, ClearSendMail), send test (mail 1 on a
-- press, mail 2 chained after MAIL_SEND_SUCCESS with no press), inbox checks
-- (test mails arriving, AH invoices for the house cut) and Yes/No observations.
-- It only ever uses the two cheapest tradeable, unlocked, non-consumable stacks,
-- shows them first, sends only to a known character after a second press, and
-- never attaches money. Everything lands in the account-wide report.
local _, ns = ...

local SelfTest = {}
ns.SelfTest = SelfTest

SelfTest.CALLER = "Mailworthy"
SelfTest.DELAY = 0.5
SelfTest.TIMEOUT = 10
SelfTest.SUBJECT = "Mailworthy test %d/2"

-- v0.4.0 check (docs/DISCOVERY-SESSION-2.md "Phase 3 check"); earlier answers stay in
-- the saved data but only these are reported.
SelfTest.QUESTIONS = {
    { id = "no_blocks", text = 'Played a minute (move, jump, target, loot, NPC): no "The game blocked" messages' },
    { id = "window_lists", text = "The Mailworthy window lists what goes and what stays, with reasons" },
    { id = "row_lock", text = "Pressing an item in the window locks it (it moves to staying) and unlocks it" },
    { id = "send_works", text = "Send mailed exactly the listed items to your bank alt, in one press" },
    { id = "no_money", text = "The mail had no money attached and nothing locked / soulbound in it" },
    { id = "pad_window", text = "Controller: Triangle opens it, D-pad + Cross reach Send, Circle closes it" },
    { id = "settings_mouse", text = "Settings: every button works with the mouse" },
    { id = "settings_pad", text = "Settings with the controller, at the mailbox and away from it" },
    { id = "settings_saved", text = "Settings are unchanged after /reload" },
    { id = "minimap", text = "The minimap icon opens settings; its toggle hides it" },
    { id = "arrived", text = "On the bank alt: the Mailworthy mail arrived" },
}


local state = { busy = false, armed = false, phase = 0, attach = nil, send = nil, status = "" }
SelfTest.state = state

local function st() return MailworthyDB.selftest end

local function strings(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = tostring((select(i, ...))) end
    return table.concat(out, ", ")
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

function SelfTest.SetStatus(text)
    state.status = text
    ns.Log.Add("status", "%s", text)
    if ns.SelfTestUI then ns.SelfTestUI.Refresh() end
end

local function after(delay, fn)
    local timer = C_Timer and C_Timer.After
    local function run()
        local ok, err = pcall(fn)
        if not ok then
            ns.Log.Add("error", "timer: %s", tostring(err))
            state.busy = false
        end
    end
    if type(timer) == "function" then timer(delay, run) else run() end
end

local function sendPrice() return call(GetSendMailPrice) end

local function sendTabShown()
    local frame = rawget(_G, "SendMailFrame")
    return type(frame) == "table" and call(frame.IsShown, frame) == true
end

function SelfTest.AttachedCount()
    local n = 0
    for i = 1, tonumber(ATTACHMENTS_MAX_SEND) or 12 do
        if call(GetSendMailItem, i) then n = n + 1 end
    end
    return n
end

local function auctionPrice(link)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if type(api) ~= "table" then return nil end
    return tonumber((call(api.GetAuctionPriceByItemLink, SelfTest.CALLER, link)))
end

local function itemInfo(bag, slot)
    local info = call(C_Container and C_Container.GetContainerItemInfo, bag, slot)
    return type(info) == "table" and info or nil
end

--- The two cheapest stacks the tests may use: tradeable (not soulbound, not a
--- quest item), not locked by the game or by Mailworthy, with a vendor value,
--- and not a consumable (so a failed attach can never eat or use it).
function SelfTest.Candidates()
    local list = {}
    local numSlots = C_Container and C_Container.GetContainerNumSlots
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        for slot = 1, tonumber((call(numSlots, bag))) or 0 do
            local info = itemInfo(bag, slot)
            if info and not info.isBound and not info.isLocked and not info.hasNoValue
                and not ns.Locks.IsLocked(bag, slot) then
                local quest = call(C_Container.GetContainerItemQuestInfo, bag, slot)
                local classID = select(6, call((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant,
                    info.hyperlink or info.itemID))
                if not (type(quest) == "table" and quest.isQuestItem) and classID ~= 0 and classID ~= 12 then
                    local sell = select(11, call((C_Item and C_Item.GetItemInfo) or GetItemInfo, info.hyperlink))
                    local count = tonumber(info.stackCount) or 1
                    local unit = auctionPrice(info.hyperlink) or tonumber(sell) or 0
                    list[#list + 1] = { bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                        count = count, value = unit * count }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value < b.value end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return { list[1], list[2] }
end

local function name(c) return string.format("%s x%d (bag %d slot %d)", tostring(c.link), c.count, c.bag, c.slot) end

local function ready(what)
    if state.busy then
        SelfTest.SetStatus("A test is still running; wait for it to finish.")
        return nil
    end
    if InCombatLockdown() then
        SelfTest.SetStatus(what .. ": not in combat.")
        return nil
    end
    if not sendTabShown() then
        SelfTest.SetStatus(what .. ": open a mailbox and switch to the Send Mail tab (R1) first.")
        return nil
    end
    local c = SelfTest.Candidates()
    if not c[1] or not c[2] then
        SelfTest.SetStatus(what .. ": needs two tradeable, unlocked, non-consumable stacks in your bags.")
        return nil
    end
    return c
end

local function attach(c, how)
    local ok, err = pcall(C_Container.UseContainerItem, c.bag, c.slot)
    ns.Log.Add("attach", "UseContainerItem %s %s: %s", name(c), how, ok and "called" or tostring(err))
    return ok
end

-- Attach test -----------------------------------------------------------------

local function finishAttach(r)
    st().results = st().results or {}
    st().results.attach = r
    state.busy = false
    SelfTest.SetStatus(string.format("Attach test done: postage with 0 / 1 / 2 items = %s / %s / %s; attached %s then %s."
        .. " Now press Clear attachments.", tostring(r.p0), tostring(r.p1), tostring(r.p2), tostring(r.n1),
        tostring(r.n2)))
end

function SelfTest.RunAttach()
    local c = ready("Attach test")
    if not c then return end
    state.busy, state.attach = true, c
    ns.lastCommand = "selftest attach"
    pcall(ClearSendMail)
    local r = { p0 = sendPrice() }
    ns.Log.Add("attach", "start: postage with nothing attached %s; items %s and %s", tostring(r.p0), name(c[1]), name(c[2]))
    attach(c[1], "on the button press")
    after(SelfTest.DELAY, function()
        r.n1, r.p1 = SelfTest.AttachedCount(), sendPrice()
        ns.Log.Add("attach", "after the press: %d attached, postage %s", r.n1, tostring(r.p1))
        ns.lastCommand = "selftest attach (timer)"
        attach(c[2], "from a timer (no button press)")
        after(SelfTest.DELAY, function()
            r.n2, r.p2 = SelfTest.AttachedCount(), sendPrice()
            ns.Log.Add("attach", "after the timer: %d attached, postage %s", r.n2, tostring(r.p2))
            if r.n2 > r.n1 then return finishAttach(r) end
            -- Fallback: pick up and drop onto the first free attachment slot.
            local okPick, errPick = pcall(C_Container.PickupContainerItem, c[2].bag, c[2].slot)
            local okClick, errClick = pcall(ClickSendMailItemButton)
            after(SelfTest.DELAY, function()
                r.n2, r.p2 = SelfTest.AttachedCount(), sendPrice()
                ns.Log.Add("attach", "fallback from a timer: PickupContainerItem %s, ClickSendMailItemButton %s -> %d attached,"
                    .. " postage %s", okPick and "ok" or tostring(errPick), okClick and "ok" or tostring(errClick),
                    r.n2, tostring(r.p2))
                if call(CursorHasItem) then pcall(ClearCursor) ns.Log.Add("attach", "cleared the cursor") end
                finishAttach(r)
            end)
        end)
    end)
end

function SelfTest.RunClear()
    if state.busy then return SelfTest.SetStatus("A test is still running; wait for it to finish.") end
    local ok, err = pcall(ClearSendMail)
    ns.Log.Add("attach", "ClearSendMail: %s", ok and "called" or tostring(err))
    after(SelfTest.DELAY, function()
        local parts = {}
        for _, c in ipairs(state.attach or {}) do
            local info = itemInfo(c.bag, c.slot)
            parts[#parts + 1] = string.format("%s back %s", tostring(c.link),
                (info and info.itemID == c.itemID and not info.isLocked) and "yes" or "no")
        end
        local n = SelfTest.AttachedCount()
        ns.Log.Add("attach", "after ClearSendMail: %d still attached; %s", n, table.concat(parts, ", "))
        SelfTest.SetStatus(string.format("Cleared: %d still attached. %s", n, table.concat(parts, ", ")))
    end)
end

-- Send test -------------------------------------------------------------------

function SelfTest.CycleRecipient()
    local list = ns.Characters.Mailable()
    if #list == 0 then
        return SelfTest.SetStatus("No other character on this realm and faction yet: log in your bank alt once, then come back.")
    end
    local index = 1
    for i, entry in ipairs(list) do
        if entry.name == st().recipient then index = i % #list + 1 end
    end
    st().recipient = list[index].name
    state.armed = false
    SelfTest.SetStatus("Recipient: " .. st().recipient .. " (" .. ns.Characters.Describe(list[index]) .. ")")
end

local function timeout(phase)
    after(SelfTest.TIMEOUT, function()
        if state.busy and state.phase == phase then
            ns.Log.Add("send", "no MAIL_SEND_SUCCESS or MAIL_FAILED within %ds for mail %d", SelfTest.TIMEOUT, phase)
            state.busy = false
            SelfTest.SetStatus(string.format("Mail %d: no answer from the game within %d seconds.", phase, SelfTest.TIMEOUT))
        end
    end)
end

local function sendMail(phase, how)
    local recipient = state.send.recipient
    local n, price = SelfTest.AttachedCount(), sendPrice()
    local pending = call(C_Mail and C_Mail.IsCommandPending)
    ns.lastCommand = string.format("selftest send %d (%s)", phase, how)
    pcall(SetSendMailCOD, 0)
    pcall(SetSendMailMoney, 0)
    local ok, err = pcall(SendMail, recipient, string.format(SelfTest.SUBJECT, phase), "")
    ns.Log.Add("send", "mail %d to %q %s: %d attached, postage %s, IsCommandPending %s, SendMail %s", phase, recipient,
        how, n, tostring(price), tostring(pending), ok and "called" or tostring(err))
    state.phase = phase
    timeout(phase)
end

function SelfTest.SendPress()
    local recipient = st().recipient
    if not recipient then return SelfTest.SetStatus("Send test: choose the recipient first (your bank alt).") end
    if not state.armed then
        local c = ready("Send test")
        if not c then return end
        pcall(ClearSendMail)
        ns.lastCommand = "selftest send arm"
        attach(c[1], "for mail 1 (button press)")
        state.armed, state.send = true, { c[1], c[2], recipient = recipient }
        return SelfTest.SetStatus(string.format("Mail 1 holds %s. Press Send test again to send it to %s;"
            .. " mail 2 (%s) follows on its own.", name(c[1]), recipient, name(c[2])))
    end
    if state.busy then return SelfTest.SetStatus("A test is still running; wait for it to finish.") end
    state.armed, state.busy = false, true
    st().sent = { at = call(GetServerTime) or time(), recipient = recipient, from = ns.PlayerName() }
    sendMail(1, "on the button press")
end

local function onSendSuccess()
    if not state.busy then return end
    ns.Log.Add("send", "MAIL_SEND_SUCCESS for mail %d", state.phase)
    if state.phase == 1 then
        state.phase = 1.5
        after(SelfTest.DELAY, function()
            ns.lastCommand = "selftest send 2 attach (timer)"
            attach(state.send[2], "for mail 2 (timer, no button press)")
            after(SelfTest.DELAY, function() sendMail(2, "from a timer (no button press)") end)
        end)
    elseif state.phase == 2 then
        state.busy = false
        SelfTest.SetStatus("Send test done: both mails went out. Log in your bank alt to check they arrived.")
    end
end

ns.On("MAIL_SEND_SUCCESS", onSendSuccess)
ns.On("MAIL_FAILED", function(...)
    if not state.busy then return end
    ns.Log.Add("send", "MAIL_FAILED during mail %s: %s", tostring(state.phase), strings(...))
    state.busy = false
    SelfTest.SetStatus("Mail " .. tostring(state.phase) .. " failed; see the report.")
end)
ns.On("UI_ERROR_MESSAGE", function(errorType, message)
    if state.busy then ns.Log.Add("send", "UI error %s: %s", tostring(errorType), tostring(message)) end
end)
ns.On("MAIL_CLOSED", function()
    if state.busy or state.armed then ns.Log.Add("send", "mailbox closed during a test (phase %s)", tostring(state.phase)) end
    state.busy, state.armed = false, false
end)

-- Inbox: test mails arriving on the bank alt, and AH invoices (house cut). -----

local seen = {}
ns.On("MAIL_SHOW", function() seen = {} end)
ns.On("MAIL_INBOX_UPDATE", function()
    for i = 1, tonumber((call(GetInboxNumItems))) or 0 do
        local _, _, sender, subject, _, _, daysLeft, hasItem = call(GetInboxHeaderInfo, i)
        local key = tostring(subject) .. "|" .. tostring(daysLeft)
        if type(subject) == "string" and subject:find("^Mailworthy test") and not seen[key] then
            seen[key] = true
            local sent = st().sent
            ns.Log.Add("inbox", "found %q from %s, has item %s, days left %s; %s s after mail 1 was sent", subject,
                tostring(sender), tostring(hasItem), tostring(daysLeft),
                sent and tostring((call(GetServerTime) or time()) - sent.at) or "?")
        end
        local invoiceType, itemName, _, bid, buyout, deposit, consignment, _, _, _, count = call(GetInboxInvoiceInfo, i)
        if invoiceType and not seen["invoice" .. i .. tostring(itemName)] then
            seen["invoice" .. i .. tostring(itemName)] = true
            local base = tonumber(buyout) and tonumber(buyout) > 0 and tonumber(buyout) or tonumber(bid)
            ns.Log.Add("invoice", "%s %q x%s: bid %s, buyout %s, deposit %s, house cut %s%s", tostring(invoiceType),
                tostring(itemName), tostring(count), tostring(bid), tostring(buyout), tostring(deposit),
                tostring(consignment), (base and tonumber(consignment))
                    and string.format(" (%.2f%%)", 100 * tonumber(consignment) / base) or "")
        end
    end
end)

-- Answers and report -----------------------------------------------------------

function SelfTest.Answer(id, value)
    st().answers[id] = { value = value, char = ns.PlayerName(), at = call(GetServerTime) or time(), version = ns.VERSION }
    ns.Log.Add("answer", "%s = %s", id, value)
    if ns.SelfTestUI then ns.SelfTestUI.Refresh() end
end

function SelfTest.Report()
    local charName, realm, faction = ns.Characters.Current()
    local lines = {
        string.format("Mailworthy %s self-test report at %s", ns.VERSION, date("%Y-%m-%d %H:%M")),
        "build: " .. strings(call(GetBuildInfo)),
        string.format("character: %s (%s, %s)", tostring(charName), tostring(realm), tostring(faction)),
        string.format("controller: labelStyle=%s, interface style=%s, Triangle glyph=%s",
            tostring(ns.Gamepad.LabelStyle()),
            tostring(call(ns.Gamepad.Get("C_InputInterfaceStyle.GetCurrentStyle")) or "?"),
            ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP)),
        "api: " .. ns.Gamepad.Presence(),
        "features: " .. ns.Features.Describe(),
        ns.PadKey.Report(),
        string.format("AH durations: 1=%s, 2=%s, 3=%s", tostring(rawget(_G, "AUCTION_DURATION_ONE")),
            tostring(rawget(_G, "AUCTION_DURATION_TWO")), tostring(rawget(_G, "AUCTION_DURATION_THREE"))),
    }
    for _, entry in pairs(MailworthyDB.characters) do lines[#lines + 1] = "known character: " .. ns.Characters.Describe(entry) end
    for _, l in ipairs(st().loads) do
        lines[#lines + 1] = string.format("load: %s %s at %s", tostring(l.char), tostring(l.kind), date("%Y-%m-%d %H:%M:%S", l.at))
    end
    lines[#lines + 1] = "locked items (this character): " .. ns.Locks.Describe()
    local a = st().results and st().results.attach
    if a then
        lines[#lines + 1] = string.format("attach result: postage 0/1/2 items = %s/%s/%s, attached %s then %s",
            tostring(a.p0), tostring(a.p1), tostring(a.p2), tostring(a.n1), tostring(a.n2))
    end
    lines[#lines + 1] = "recipient: " .. tostring(st().recipient)
    for _, q in ipairs(SelfTest.QUESTIONS) do
        local ans = st().answers[q.id]
        lines[#lines + 1] = string.format("answer %s: %s (%s)", q.id,
            ans and string.format("%s by %s at %s (%s)", ans.value, tostring(ans.char),
                date("%m-%d %H:%M", ans.at or 0), ans.version or "older build") or "not answered", q.text)
    end
    for _, l in ipairs(ns.Blocked.Lines()) do lines[#lines + 1] = l end
    lines[#lines + 1] = "log:"
    for _, l in ipairs(ns.Log.Lines()) do lines[#lines + 1] = l end
    return table.concat(lines, "\n")
end

function SelfTest.Open(source)
    ns.Log.Add("ui", "window opened from %s", tostring(source))
    ns.SelfTestUI.Show()
end

function SelfTest.ShowReport()
    ns.SelfTestUI.ShowReport(SelfTest.Report())
end
