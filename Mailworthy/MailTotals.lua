-- The mail window's total box (MailWindow.lua): the gain over vendoring and the fees under it; with
-- no bank alt, what one would get; while a run is on, the mailer's progress; after it, its receipt
-- (in chat too, once); short on postage, what is missing (Mailer.RESERVE).
local _, ns = ...

local UI = ns.MailWindow
local S = UI.shared
local W = ns.Widgets

--- Pure: the total line and the fees note under the lists, for a scan (Bags.Evaluate). Items going
--- to the bank alt with no auction price have no gain: the line counts them (Codex review, 2026-11-08).
function UI.TotalText(scan)
    local money, t = S.money, scan.totals
    if scan.priced then
        return "+" .. money(t.gain) .. " more than vendoring" .. ((t.unpriced or 0) > 0
                and string.format(", %d with no price yet", t.unpriced) or ""),
            string.format("after the %d%% AH cut, %dh deposits and %s postage",
                math.floor(scan.settings.cut * 100 + 0.5), ns.Valuation.DURATION_HOURS[scan.settings.duration],
                money(t.postage))
    end
    return string.format("%d item%s to mail", t.items, t.items == 1 and "" or "s"),
        "No Auctionator: white items and staple trade goods go. Postage " .. money(t.postage) .. "."
end

--- Pure: the line under "Mailing" when nothing goes.
function UI.EmptyText(hasBankAlt)
    return hasBankAlt and "Nothing worth mailing in your bags right now."
        or "Nothing to mail without a bank alt or a binding."
end

--- Pure: the total box with no bank alt, when a bank alt would get something (`keep`: the scan's
--- Staying list; the held share has result.held): "+79s 61c would go to a bank alt" and what to
--- do. nil when nothing is held. `tags`: the bags carry the tags on this character.
function UI.NoAltText(keep, tags)
    local items, gain = 0, 0
    for _, item in ipairs(keep or {}) do
        if item.result and item.result.held then
            items, gain = items + 1, gain + (tonumber(item.result.gain) or 0)
        end
    end
    if items == 0 then return nil end
    local head = gain > 0 and ("+" .. S.money(gain) .. " would go to a bank alt")
        or string.format("%d item%s would go to a bank alt", items, items == 1 and "" or "s")
    return head, "Pick one and this list is ready to send"
        .. (tags and "; until then your bags carry the AH / DE / V tags." or ".")
end

--- Pure: the note under the total when the player can't pay the postage and keep Mailer.RESERVE
--- (operator, 2026-11-14: 5s always stays on the character).
function UI.PostageText(need, have)
    local money, reserve = S.money, ns.Mailer.RESERVE
    if not have then -- GetMoney unreadable (Mailer.Short): nothing goes
        return string.format("Postage is %s and Mailworthy can't read your money, so nothing is sent.", money(need))
    end
    return string.format("Postage is %s and you have %s; Mailworthy keeps %s on you. Press an item to keep it, "
        .. "or come back with %s more.", money(need), money(have), money(reserve), money(need + reserve - have))
end

--- How many items of a scan stay for the vendor (the bank alt view's V: BankAlt.Verdict).
function UI.VendorLeft(scan)
    local n = 0
    for _, item in ipairs(scan and scan.keep or {}) do
        local ok, verdict = pcall(ns.BankAlt.Verdict, item)
        if ok and verdict == "v" then n = n + 1 end
    end
    return n
end

--- Pure: a mail list as { [link] = units }, every row of an item added up (one item can be
--- several rows: some back to a sender, the rest to the bank alt).
function UI.ListCounts(items)
    local list = {}
    for _, item in ipairs(items or {}) do
        local key = item.link or item.itemID
        list[key] = (list[key] or 0) + (tonumber(item.count) or 0)
    end
    return list
end

-- The mail list as it stood when a run ended (UI.ListCounts), per receipt: taken at the first
-- redraw or chat line after the run, whichever comes first, window open or not.
local receiptLists = setmetatable({}, { __mode = "k" })
local function receiptList(receipt, scan)
    if not receiptLists[receipt] then receiptLists[receipt] = UI.ListCounts(scan and scan.mail) end
    return receiptLists[receipt]
end

--- Pure: has the mail list `now` more of anything than the list `before` (UI.ListCounts) held?
function UI.Grew(before, now)
    for key, count in pairs(UI.ListCounts(now)) do
        if count > (before[key] or 0) then return true end
    end
    return false
end

-- A run ended: its receipt goes to chat once, the same words as the window's.
local printedReceipt
function S.PrintReceipt()
    local receipt = ns.Mailer.Receipt()
    if not receipt or receipt == printedReceipt then return end
    printedReceipt = receipt
    local scan = S.result
    if not (S.frame and S.frame:IsShown()) then
        local ok, fresh = pcall(ns.Bags.Evaluate)
        scan = ok and fresh or nil
    end
    receiptList(receipt, scan) -- the list as the run left it, even with the window closed
    local _, _, chat = ns.Mailer.ReceiptText(receipt, UI.VendorLeft(scan))
    ns.Print(chat)
end

--- At login: the total line and the note under it.
function S.CreateTotals()
    S.totalLine = W.Label(S.frame, "GameFontNormalLarge")
    S.totalLine:SetTextColor(0.6, 1, 0.5)
    S.totalNote = W.Label(S.frame, "GameFontHighlightSmall")
    S.totalNote:SetWidth(S.WIDTH - 48)
    S.totalNote:SetJustifyH("LEFT")
end

--- The total box for a scan. Returns the postage the player can't pay (Mailer.Short), or nil.
function S.FillTotals(result, ctx)
    local line, note = UI.TotalText(result)
    -- No bank alt and nothing going: what one would get, and how to get there.
    if ctx.bankAlt == nil and not ctx.isBankAlt and #result.mail == 0 then
        local heldLine, heldNote = UI.NoAltText(result.keep, ns.Config.Flag("tagsEverywhere") == true)
        if heldLine then line, note = heldLine, heldNote end
    end
    S.totalLine:SetText(line)
    S.totalNote:SetText(note)
    -- While sending (and after), the mailer's progress or problem takes the fees line.
    local status = ns.Mailer.Status()
    if status then S.totalNote:SetText(status) end
    -- After a run: its receipt (what went, to whom, the gain; what stayed; what is left for the
    -- vendor). A run that mailed everything takes the headline too; a stopped one leaves the
    -- headline to the list still waiting.
    local receipt = ns.Mailer.Receipt()
    -- Something new on the list since the run ended (looted, taken from the mailbox): the total
    -- is the list's again, the receipt has had its say (Codex review, 2026-11-09).
    if receipt and UI.Grew(receiptList(receipt, result), result.mail) then
        ns.Mailer.Dismiss()
        receipt = nil
        S.totalNote:SetText(note)
    end
    if receipt then
        local head, notes = ns.Mailer.ReceiptText(receipt, UI.VendorLeft(result))
        if receipt.stopped then
            S.totalNote:SetText(head .. (notes ~= "" and ("\n" .. notes) or ""))
        else
            S.totalLine:SetText(head)
            S.totalNote:SetText(notes)
        end
    end
    -- Short on postage: nothing would go (Mailer.Blocker), so the window says what is missing.
    local need, have = nil, nil
    if not ctx.busy then need, have = ns.Mailer.Short(result.mail) end
    if need then S.totalNote:SetText("|cffff8040" .. UI.PostageText(need, have) .. "|r") end
    return need
end
