-- The bank alt view (media/bank-alt-prototype.png): what each item is for,
-- recomputed with this character's own, fresh Auctionator prices.
--
--   * tags on bag slots: AH (list it), B (bank it: it sells higher later, or this character's
--     own crafting needs it, Valuation.BankForCraft), DE (disenchant it), V (vendor now);
--   * tooltip lines: today's verdict with the price and its age, and why it was
--     mailed ("Mailed for: Auction +8s 21c, Oct 14, from <main>", recorded by
--     Mailer in MailworthyDB.mailed);
--   * a summary window: stacks to list, items to disenchant, items now better
--     at a vendor (and how many of those were mailed for the auction house).
--
-- Shown on the bank alt (the character this realm + faction mails to), on a character
-- with no bank alt (it sells its own: the bank alt is optional, operator 2026-11-08), or
-- on every character with the "tags everywhere" setting. Postage doesn't count there:
-- nothing is being mailed.
--
-- The tooltip also says why an item stays (operator, 2026-11-08: Sharp Claw and Jade showed
-- nothing, read as "missing data": they were kept for a profession, and a kept item had no
-- line), and, while the Mailworthy window is open, what the window does with it.
--
-- On a main, after Send has mailed everything (operator, 2026-10-14): V tags
-- only, on what the Mailworthy window kept because a vendor pays more, for the
-- rest of the session, so the trip to the vendor is easy. Same settings as the
-- window (postage included), so the tags match what it showed.
--
-- Grey junk with a vendor price is V too (the AH has no price for it). Without
-- Auctionator: only that, plus the "Mailed for" line.
--
-- Taint: tags are textures and font strings on the game's bag buttons (and the bag
-- addons' buttons, BagAddons.lua), kept in our own weak table (the lock glow's
-- technique, via Border's hooks and Border.RefreshButton); tooltip
-- lines go through TooltipDataProcessor, which runs addon callbacks insecurely
-- by design (forceinsecure behind an attribute delegate). Switches:
-- /mw feature bankAltTags off, /mw feature tooltipLines off.
local _, ns = ...

local BankAlt = {}
ns.BankAlt = BankAlt

local P = ns.Palette

--- Does this character bank here what goes "to the bank" (it is the bank alt, or has none)?
function BankAlt.BanksHere()
    return ns.Config.IsBankAltHere() or not ns.Config.BankAlt()
end

--- The Palette entry (tag letters, colours, label) for a verdict (BankAlt.Verdict). "b" (bank it, not
--- listed yet) is BA on a character that mails it to the bank alt, BH where it stays: the same item,
--- told by where it gets banked (operator, 2026-11-13: "Bank here (BH) vs Bank Alt (BA)").
--- "craft" (this character's own crafting needs it, 2026-11-11) and "here" (a bank-here pin) are BH.
function BankAlt.Tag(verdict)
    if verdict == "b" then return BankAlt.BanksHere() and P.BH or P.BA end
    if verdict == "craft" or verdict == "here" then return P.BH end
    return ({ ah = P.AH, de = P.DE, v = P.V, friend = P.F, ["return"] = P.R })[verdict]
end

local money = function(c) return ns.Valuation.Money(c) end
local tags = setmetatable({}, { __mode = "k" }) -- bag button -> { bg, text }
local cache = { dirty = true, bySlot = {}, byLink = {}, byItemID = {} }
local frame, rows, header, legend

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

--- The character this realm + faction mails to: picked from a main on the same
--- account, or declared here ("This character is my bank alt" in the settings
--- window) when the bank alt lives on a second WoW account.
function BankAlt.IsBankAlt()
    return ns.Config.IsBankAltHere()
end

--- A main that has sent with Mailworthy shows its tags from then on, saved for the character, so a
--- /reload or a relog keeps them (operator, 2026-11-13: "not just V tags, but all tags"; before,
--- only V, and only until the session ended).
local function sentHere() return type(MailworthyCharDB) == "table" and MailworthyCharDB.tagsAfterSend == true end

--- "bankalt", "everywhere" (the setting), "self" (no bank alt on this realm and faction: this
--- character sells its own), "sent" (a main that has sent: the window's settings), or nil (a main
--- that never sent: only pinned items are tagged).
function BankAlt.Mode()
    if BankAlt.IsBankAlt() then return "bankalt" end
    if ns.Config.Flag("tagsEverywhere") then return "everywhere" end
    if not ns.Config.BankAlt() then return "self" end
    if sentHere() then return "sent" end
    return nil
end

function BankAlt.Active()
    return BankAlt.Mode() ~= nil
end

--- Is there anything to draw at all? Every mode tags; a main that never sent tags its pinned items
--- (a pin always shows its BA / BH tag).
function BankAlt.Wanted()
    return ns.Features.On("bankAltTags") and (BankAlt.Active() or ns.Pins.Any())
end

--- Mailer: a send finished. Tag this main's bags from now on.
function BankAlt.AfterSend()
    if sentHere() or BankAlt.IsBankAlt() then return end
    MailworthyCharDB.tagsAfterSend = true
    ns.Log.Add("bankalt", "tags on after sending (saved)")
    BankAlt.Redraw()
end

--- Pure: the tag for a valued item: "ah" / "de" when the auction house or
--- disenchanting beats the vendor by the minimum gain, "b" when it should be banked
--- for a later phase instead of listed, "craft" when this character's own profession needs
--- it (bank it until then), "v" when the vendor wins, nil when there's nothing to say
--- (locked, soulbound, tool, no price...).
function BankAlt.Verdict(item)
    local r = item.result
    if not r then return nil end
    if r.pinned and r.action == "keep" and r.reason == ns.Valuation.PIN_HERE_REASON then return "here" end
    -- A pin valued for the bank alt where pins bank here (BankAlt.BanksHere) is a bank-here pin.
    if r.pinned and r.action == "mail" and r.route == "bank" and BankAlt.BanksHere() then return "here" end
    if ns.Valuation.BankForCraft(r) then return "craft" end
    if r.action == "mail" then
        -- Where the mailbox sends it, as the window does (operator, 2026-11-13: tags that ignored
        -- bindings and Return to sender disagreed with the window).
        if r.route == "return" then return "return" end
        if r.to then return "friend" end
        if r.route == "bank" then return "b" end
        return (r.route == "ah" or r.route == "de") and r.route or nil
    end
    if r.reason == "not worth it" and (r.vendor or 0) > 0 then return "v" end
    -- Grey junk: no auction price, but a vendor buys it.
    local unpriced = r.reason == "no price" or r.reason == "junk (no price data)"
    if item.quality == 0 and unpriced and (item.vendor or 0) > 0 then return "v" end
    return nil
end

--- Settings for the verdicts: on the bank alt (and with "tags everywhere") no postage,
--- since nothing is mailed from there; after a send on a main, the window's own settings. The
--- bindings count (an item a friend's binding takes is F, not AH), and so does Return to sender
--- while it is on at the mailbox (R): the tags say what the mailbox does (operator, 2026-11-13).
function BankAlt.Settings()
    local s = ns.Config.Values()
    if BankAlt.Mode() ~= "sent" then s.postage = 0 end
    if ns.Returns.On() then s.returns = ns.Returns.Current() end
    return s
end

function BankAlt.Invalidate()
    cache.dirty = true
end

function BankAlt.Refresh()
    cache.dirty = false
    cache.bySlot, cache.byLink, cache.byItemID = {}, {}, {}
    local keys = {}
    cache.result = ns.Bags.Evaluate(BankAlt.Settings())
    local mode = BankAlt.Mode()
    for _, list in ipairs({ cache.result.mail, cache.result.keep }) do
        for _, item in ipairs(list) do
            item.advice = BankAlt.Verdict(item) -- the tooltip's
            item.verdict = item.advice -- the bag tag's
            -- A main that never sent: its pinned items only (a pin always shows its tag).
            if mode == nil and not (item.result and item.result.pinned) then item.advice, item.verdict = nil, nil end
            local tag = item.verdict and BankAlt.Tag(item.verdict)
            if tag then keys[tag.key] = true end
            cache.byLink[item.link] = item
            cache.byItemID[item.itemID] = cache.byItemID[item.itemID] or item
            for _, s in ipairs(item.slots) do cache.bySlot[s.bag .. ":" .. s.slot] = item end
        end
    end
    cache.keys = keys
    -- The legend lists what the bags now show (it doesn't rescan on its own: LegendText).
    if legend then legend:SetText(BankAlt.LegendText()) end
    return cache.result
end

local function current()
    if cache.dirty then BankAlt.Refresh() end
    return cache
end

-- Tags on bag buttons --------------------------------------------------------------

local function tagFor(button)
    local t = tags[button]
    if t then return t end
    t = {}
    t.bg = button:CreateTexture(nil, "OVERLAY", nil, 6)
    t.bg:SetSize(18, 11)
    t.bg:SetPoint("TOPLEFT", 2, -2)
    t.text = button:CreateFontString(nil, "OVERLAY", "SystemFont_Tiny")
    t.text:SetPoint("CENTER", t.bg, "CENTER", 0, 0)
    t.text:SetTextColor(1, 1, 1)
    -- A bag skin that fades the button's other regions (EllesmereUI; issue #89) leaves the tag alone.
    ns.Border.HoldAlpha(t.bg)
    ns.Border.HoldAlpha(t.text)
    tags[button] = t
    return t
end

--- Border decorator: show the item's tag, or hide ours if there's none. The item is the one in
--- bag / slot; a view without bag slots (Auctionator's) passes nil for them and its item's link,
--- else its item ID (Border.RefreshButton).
function BankAlt.Decorate(button, bag, slot, itemID, link)
    local want = BankAlt.Wanted()
    local item
    if want then
        local c = current()
        if bag ~= nil then
            item = c.bySlot[bag .. ":" .. tostring(slot)]
        else
            item = (link and c.byLink[link]) or (itemID and c.byItemID[itemID]) or nil
        end
    end
    local tag = item and item.verdict and BankAlt.Tag(item.verdict)
    if not tag then
        local t = tags[button]
        if t then t.bg:Hide() t.text:Hide() end
        return
    end
    local t = tagFor(button)
    t.bg:SetColorTexture(tag.bg[1], tag.bg[2], tag.bg[3], 0.95)
    t.text:SetText(tag.text)
    t.bg:Show()
    t.text:Show()
end

--- The valued bag item with this item ID (the tags' scan), or nil; for the glow's tooltip.
function BankAlt.ItemFor(itemID)
    if itemID == nil or not BankAlt.Wanted() then return nil end
    return current().byItemID[itemID]
end

--- Does this button show one of our tags right now? (Baganator: our corner widget holds its corner
--- while it does.)
function BankAlt.TagShown(button)
    local t = tags[button]
    return t ~= nil and t.bg:IsShown() == true
end

--- Place a button's tag on `region` (Baganator: our corner widget, wherever the player put it), or
--- back in the top-left corner with nil.
function BankAlt.AnchorTag(button, region)
    local t = tags[button]
    if not t then return end
    t.bg:ClearAllPoints()
    if region then t.bg:SetAllPoints(region) else t.bg:SetPoint("TOPLEFT", 2, -2) end
end

--- Pure: the legend for the tags in `keys` (a set of Palette keys), in Palette.ORDER; "" for none.
function BankAlt.LegendFor(keys)
    local parts = {}
    for _, key in ipairs(P.ORDER) do
        if keys[key] then parts[#parts + 1] = P.Letters(P[key]) .. " " .. P.LEGEND[key] end
    end
    return #parts > 0 and ("Mailworthy: " .. table.concat(parts, "   ")) or ""
end

--- The legend under the bags: the tags the last scan put on the bags ("" for none), shared by
--- Blizzard's bags and the bag addons. Never a scan of its own: the tags' scan sets it.
function BankAlt.LegendText()
    if not BankAlt.Wanted() then return "" end
    return BankAlt.LegendFor(cache.keys or {})
end

local function redraw()
    BankAlt.Invalidate()
    ns.Border.RefreshAll()
    if legend then legend:SetText(BankAlt.LegendText()) end
    if frame and frame:IsShown() then BankAlt.RefreshWindow() end
end
BankAlt.Redraw = redraw

-- Tooltip --------------------------------------------------------------------------

local function ageText(age)
    if age == nil then return "" end
    if age <= 0 then return " (scanned today)" end
    return string.format(" (scanned %d day%s ago)", age, age == 1 and "" or "s")
end

-- Kept for a reason the tooltip doesn't repeat: the game's own lines (soulbound, quest item,
-- conjured item), the lock glow's line (Border), or nothing to say yet.
BankAlt.QUIET_KEEPS = { soulbound = true, ["quest item"] = true, ["conjured item"] = true, locked = true,
    ["in use"] = true, ["item info not loaded yet"] = true }

--- Pure: the label and the line for an item with no verdict tag: where the Mailworthy window
--- mails it, or why it stays in the bags. nil when there's nothing to add. `noBankAlt`: the bank
--- alt's share stays (true = none is set, or Bags.HoldReason's text: "this is your bank alt",
--- "bank alt skipped"), so nothing goes to one (Codex review).
function BankAlt.OtherLine(item, noBankAlt)
    local r = item and item.result
    if type(r) ~= "table" then return nil end
    if r.action == "mail" then
        if r.to then
            return "Mail", string.format("Goes to %s at the mailbox: %s.", tostring(r.to),
                r.what and (tostring(r.what) .. " binding") or "a binding")
        end
        if noBankAlt then
            return "Keep", string.format("Stays in your bags: %s (%s).", type(noBankAlt) == "string" and noBankAlt
                or "no bank alt", tostring(r.reason))
        end
        return "Mail", "Goes to your bank alt at the mailbox: " .. tostring(r.reason) .. "."
    end
    if r.action ~= "keep" or BankAlt.QUIET_KEEPS[r.reason] then return nil end
    return "Keep", "Stays in your bags: " .. ns.MailWindow.StayReason(r) .. "."
end

-- A warning inside a tooltip: something that breaks the usual pattern (operator, 2026-11-13:
-- "anything breaking that consistency is explained in the tooltip or with an explicit warning").
BankAlt.WARN = { 1, 0.5, 0.25 }

--- Pure: why this character banks its pins here (Pins.HereBecause), in words for the tooltip.
local HERE_BECAUSE = {
    setting = "this character banks its pins here (Settings: Pinned items)",
    ["no bank alt"] = "no bank alt is set, so it stays to bank here. Pick a bank alt to have pins mailed to it",
    ["bank alt"] = "this is your bank alt, where pins are banked",
}

--- Pure: the line that says what the tag means, for a tagged item.
local function tagText(verdict, item, settings)
    local r, p = item.result, item.price or {}
    local unit = r.ahUnit or p.ah
    local basis = (r.scans or 1) > 1 and string.format(" (%d-day median)", r.scans) or ""
    local unpin = " Ctrl+Alt+click it again to unpin."
    if verdict == "ah" then
        return string.format("Auction price today: %s each%s%s. After the %d%% cut and the %dh deposit: %s more than a vendor.",
            money(unit), basis, ageText(p.age), math.floor(settings.cut * 100 + 0.5),
            ns.Valuation.DURATION_HOURS[settings.duration], money(r.gain))
    elseif verdict == "here" then
        return "Bank it here: you pinned it, and " .. (HERE_BECAUSE[ns.Pins.HereBecause()] or HERE_BECAUSE.setting) .. "."
            .. unpin
    elseif verdict == "b" and r.pinned then
        return "Bank it on your bank alt: you pinned it, so Send mails it there (/mw pins lists pins)." .. unpin
    elseif verdict == "b" then
        local why = tostring(r.reason):gsub("^bank: ", "")
        return (BankAlt.BanksHere() and "Bank it here, don't list it yet: " or "Bank it on your bank alt, don't list it yet: ")
            .. why .. ". " .. (r.gain
            and string.format("Listed today it would bring %s%s more than a vendor.", unit and (money(unit) .. " each, ") or "",
                money(r.gain))
            or "No auction price yet, so the gain is unknown.")
    elseif verdict == "craft" then
        return "Bank it here: " .. ns.MailWindow.WhyKept(r) .. ". It waits in your bank, not your bags, until you craft."
            .. " (Settings: Keep my professions' materials, per character.)"
    elseif verdict == "friend" then
        return string.format("Goes to %s at the mailbox: %s.", tostring(r.to),
            r.what and (tostring(r.what) .. " binding") or "a binding")
    elseif verdict == "return" then
        return string.format("Goes back to %s at the mailbox: they mailed it to you, and Return to sender is on.",
            tostring(r.to))
    elseif verdict == "de" then
        return string.format("Disenchanting today: %s, %s more than a vendor.", money(p.de), money(r.gain))
    elseif p.ah then
        return string.format("Auction price today: %s each%s%s. After the %d%% cut and the deposit that's %s, "
            .. "so sell it to a vendor (%s).", money(unit), basis, ageText(p.age), math.floor(settings.cut * 100 + 0.5),
            (r.gain or 0) > 0 and ("under your " .. money(r.threshold) .. " minimum gain") or "less than a vendor pays",
            money(r.vendor))
    end
    return string.format("Worth no more than a vendor today: sell it (%s).", money(r.vendor))
end

--- Pure: the tooltip lines for one item: { { text, r, g, b }, ... }. Every tagged line is in its
--- tag's colour (Palette), like the tag, the glow and the window's chip.
--- `item` is the valued bag item (or nil when it isn't in the bags), `record` the
--- MailworthyDB.mailed entry (or nil).
function BankAlt.TooltipLines(item, record, settings)
    local lines = {}
    local verdict = item and (item.advice or item.verdict)
    local tag = verdict and BankAlt.Tag(verdict)
    local r = item and item.result or {}
    local otherLabel, otherText
    if not tag then otherLabel, otherText = BankAlt.OtherLine(item, ns.Bags.HoldReason() or false) end
    local label = tag and (tag.text .. ": " .. tag.label .. (r.pinned and ", pinned" or "")) or otherLabel
    if not label and not record then return lines end
    lines[1] = { "Mailworthy" .. (label and ("  |cffffffff[" .. label .. "]|r") or ""), 1, 0.82, 0 }
    if otherText then lines[#lines + 1] = { otherText, 1, 1, 1 } end
    if tag then
        lines[#lines + 1] = { tagText(verdict, item, settings), tag.fg[1], tag.fg[2], tag.fg[3] }
        -- A BA pin beats this character's own profession (operator, 2026-11-13): said every time.
        if r.pinConflict then
            lines[#lines + 1] = { string.format("Your %s uses it, but the pin wins. To keep it here: Settings > Pinned"
                .. " items: Bank here (BH), or unpin it.", tostring(r.pinConflict)), BankAlt.WARN[1], BankAlt.WARN[2],
                BankAlt.WARN[3] }
        end
        -- Pinned to the bank alt, but the bank alt is skipped this visit: it waits for the next one.
        if verdict == "b" and r.pinned and ns.Bags.BankAltSkipped() then
            lines[#lines + 1] = { "Bank alt skipped this visit: it stays, and goes next time.", BankAlt.WARN[1],
                BankAlt.WARN[2], BankAlt.WARN[3] }
        end
    end
    if record then
        local was = (record.route == "bank" and "Bank") or (record.route == "common" and "Common item")
            or (record.route == ns.Valuation.NO_PRICE and "No auction price yet")
            or (BankAlt.Tag(record.route) and BankAlt.Tag(record.route).label) or tostring(record.reason)
        lines[#lines + 1] = { string.format("Mailed for: %s%s, %s, from %s", was,
            record.gain and (" +" .. money(record.gain)) or "", date("%b %d", record.at or 0), tostring(record.from)),
            0.55, 0.75, 1 }
    end
    return lines
end

--- While the Mailworthy window shows, the item as the window has it (its settings: postage and
--- bindings), so the tooltip says what the window does; nil otherwise.
local function windowItem(link, itemID)
    local window = ns.MailWindow.Frame()
    local result = window and window:IsVisible() and ns.MailWindow.Result()
    if not result then return nil end
    local byID
    for _, list in ipairs({ result.mail, result.keep }) do
        for _, it in ipairs(list) do
            if link and it.link == link then return it, result end
            if itemID and it.itemID == itemID then byID = byID or it end
        end
    end
    return byID, byID and result or nil
end

local function onTooltip(tooltip, data)
    if not ns.Features.On("tooltipLines") then return end
    if tooltip ~= rawget(_G, "GameTooltip") then return end
    local link = select(2, call(rawget(_G, "TooltipUtil") and TooltipUtil.GetDisplayedItem, tooltip))
    local itemID = type(data) == "table" and tonumber(data.id) or nil
    local shown, shownResult = windowItem(link, itemID)
    if not shown and not BankAlt.Active() and not ns.Pins.Any() then return end
    local c = shown and { result = shownResult } or current()
    local item = shown and { result = shown.result, price = shown.price, advice = BankAlt.Verdict(shown) }
        or (link and c.byLink[link]) or (itemID and c.byItemID[itemID]) or nil
    local mode = BankAlt.Mode()
    -- A main that never sent says something only about its pinned items (their tag shows).
    if not shown and mode == nil and not (item and item.verdict) then return end
    itemID = itemID or (shown and shown.itemID) or (item and item.itemID)
    -- On a main, no "Mailed for": that belongs on the bank alt.
    local record = mode and mode ~= "sent" and itemID and type(MailworthyDB.mailed) == "table"
        and MailworthyDB.mailed[itemID] or nil
    if type(record) ~= "table" then record = nil end
    local lines = BankAlt.TooltipLines(item, record, c.result and c.result.settings or BankAlt.Settings())
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    for _, l in ipairs(lines) do tooltip:AddLine(l[1], l[2], l[3], l[4], true) end
end

function BankAlt.InstallTooltip()
    if not ns.Features.On("tooltipLines") then
        ns.Log.Add("bankalt", "tooltip lines off (/mw feature tooltipLines on, then /reload)")
        return false
    end
    local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
    local itemType = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item
    if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" or itemType == nil then
        ns.Log.Add("bankalt", "TooltipDataProcessor missing: no tooltip lines")
        return false
    end
    local ok, err = pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data)
        local okLines, errLines = pcall(onTooltip, tooltip, data)
        if not okLines then ns.Log.Add("bankalt", "tooltip error: %s", tostring(errLines)) end
    end)
    ns.Log.Add("bankalt", "tooltip lines %s", ok and "installed" or ("failed: " .. tostring(err)))
    return ok
end

-- Summary --------------------------------------------------------------------------

--- Pure: totals per verdict for the summary window.
function BankAlt.Summary(result)
    local s = { ah = { stacks = 0, items = 0, gain = 0 }, b = { stacks = 0, items = 0, gain = 0 },
        de = { stacks = 0, items = 0, gain = 0 }, v = { stacks = 0, items = 0, vendor = 0, wasAuction = 0 },
        pin = { stacks = 0, items = 0, gain = 0 } }
    local mailed = type(MailworthyDB.mailed) == "table" and MailworthyDB.mailed or {}
    for _, list in ipairs({ result.mail, result.keep }) do
        for _, item in ipairs(list) do
            local v = item.verdict
            -- Pinned items have their own row (operator, 2026-11-13), not "for a later phase".
            if (v == "b" or v == "here") and item.result and item.result.pinned then v = "pin" end
            local t = v and s[v]
            if t then
                t.stacks, t.items = t.stacks + item.stacks, t.items + item.count
                if v == "v" then
                    t.vendor = t.vendor + (item.result.vendor or 0)
                    local record = mailed[item.itemID]
                    if type(record) == "table" and (record.route == "ah" or record.listRoute == "ah") then
                        t.wasAuction = t.wasAuction + 1
                    end
                else
                    t.gain = t.gain + (item.result.gain or 0)
                end
            end
        end
    end
    return s
end

local ROW_TEXT = {
    ah = function(t) return string.format("%d stack%s to list", t.stacks, t.stacks == 1 and "" or "s"), "+" .. money(t.gain) end,
    b = function(t)
        return string.format("%d stack%s to bank for a later phase", t.stacks, t.stacks == 1 and "" or "s"), "+" .. money(t.gain)
    end,
    de = function(t) return string.format("%d item%s to disenchant", t.items, t.items == 1 and "" or "s"), "+" .. money(t.gain) end,
    pin = function(t) return string.format("%d pinned stack%s to bank", t.stacks, t.stacks == 1 and "" or "s"), "" end,
    v = function(t)
        return string.format("%d stack%s to sell to a vendor%s", t.stacks, t.stacks == 1 and "" or "s",
            t.wasAuction > 0 and string.format(" (%d mailed for the auction house)", t.wasAuction) or ""), money(t.vendor)
    end,
}

function BankAlt.CreateWindow()
    if frame then return frame end
    local W = ns.Widgets
    frame = W.Window("MailworthySummaryFrame", 440, 286)
    frame:SetPoint("CENTER")
    local title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetText("Mailworthy: what to sell")
    header = W.Label(frame, "GameFontNormal")
    header:SetPoint("TOPLEFT", 24, -50)
    rows = {}
    for i, key in ipairs({ "ah", "b", "pin", "de", "v" }) do
        local row = {}
        local y = -74 - (i - 1) * 28
        row.chipBg = frame:CreateTexture(nil, "BORDER")
        row.chipBg:SetSize(84, 16)
        row.chipBg:SetPoint("TOPLEFT", 26, y)
        row.chip = W.Label(frame, "GameFontHighlightSmall")
        row.chip:SetPoint("CENTER", row.chipBg, "CENTER")
        row.text = W.Label(frame, "GameFontHighlight")
        row.text:SetPoint("TOPLEFT", 120, y - 1)
        row.value = W.Label(frame, "GameFontHighlight")
        row.value:SetPoint("TOPRIGHT", -26, y - 1)
        rows[key] = row
    end
    W.Button(frame, "Close", 100, function() frame:Hide() end, "MailworthySummaryClose"):SetPoint("BOTTOMRIGHT", -20, 40)
    W.Button(frame, "Scan details", 120, function() ns.Bags.Scan() end, "MailworthySummaryScan")
        :SetPoint("BOTTOMLEFT", 20, 40)
    ns.Nav.Attach(frame)
    return frame
end

function BankAlt.RefreshWindow()
    if not frame then return end
    local c = current()
    local summary = BankAlt.Summary(c.result)
    header:SetText(c.result.priced and "With today's prices" or "No auction prices here: install Auctionator or TSM")
    for key, row in pairs(rows) do
        -- The chip as the bag tag reads (BA / BH follow where this character banks).
        -- Pins follow this character's pin mode (BH by the setting too: Codex review, 2026-11-13).
        local tag = BankAlt.Tag(key == "pin" and (ns.Pins.HereBecause() and "here" or "b") or key)
        row.chipBg:SetColorTexture(tag.bg[1], tag.bg[2], tag.bg[3], 0.9)
        row.chip:SetText(tag.text .. " " .. (key == "pin" and "pinned" or tag.label:lower()))
        local text, value = ROW_TEXT[key](summary[key])
        row.text:SetText(text)
        row.value:SetText(value)
    end
end

--- `opener`: the Mailworthy window whose button opened it (placed beside that), or nil (centred).
function BankAlt.ShowWindow(opener)
    if not frame then BankAlt.CreateWindow() end
    ns.Widgets.PlaceBeside(frame, opener)
    BankAlt.Invalidate()
    BankAlt.RefreshWindow()
    frame:Show()
    frame:Raise()
    ns.Log.Add("bankalt", "summary shown")
end

function BankAlt.Frame() return frame end

ns.Border.AddDecorator(BankAlt.Decorate)

ns.On("PLAYER_LOGIN", function()
    BankAlt.CreateWindow()
    BankAlt.InstallTooltip()
    -- Legend under the combined bags (a font string: not seen by smart navigation).
    local bags = rawget(_G, "ContainerFrameCombinedBags")
    if type(bags) == "table" and ns.Features.On("bankAltTags") then
        legend = bags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        legend:SetPoint("TOPRIGHT", bags, "BOTTOMRIGHT", -10, -4)
    end
    ns.Locks.OnChanged(redraw)
    ns.Pins.OnChanged(redraw)
    ns.Mailer.OnSent(function() BankAlt.AfterSend() end)
    local settings = ns.SettingsUI.Frame()
    if settings then settings:HookScript("OnHide", redraw) end
    local api = ns.Prices.Auctionator()
    if api and type(api.RegisterForDBUpdate) == "function" then
        pcall(api.RegisterForDBUpdate, ns.Prices.CALLER, redraw)
    end
    redraw()
end)
ns.On("BAG_UPDATE_DELAYED", function() redraw() end)
