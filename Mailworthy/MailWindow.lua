-- The Mailworthy window at the mailbox (media/ui-prototype.png): who the mail
-- goes to, what goes and why, what stays and why, the total gain, and Send /
-- Settings / Close. One press of Send mails everything (Mailer).
--
-- Mouse: click. Controller: Triangle at the mail window opens it, then the D-pad
-- moves Mailworthy's own highlight, Cross presses, Circle closes (PadKey "window"
-- set, Nav). Every row is a button: pressing an item locks it (it stays in the
-- bags) or unlocks it, so the controller can change the list without a menu.
-- Everything the mouse tooltip shows is also on the row itself.
--
-- Created at login (never while a gamepad panel is open), parented to the
-- showing mail tab; nothing is written into Blizzard's frames or tables.
local _, ns = ...

local UI = {}
ns.MailWindow = UI

UI.MAIL_ROWS, UI.STAY_ROWS = 8, 5
local WIDTH, MAIL_ROW, STAY_ROW = 520, 30, 20
local HEIGHT = 196 + UI.MAIL_ROWS * MAIL_ROW + UI.STAY_ROWS * STAY_ROW + 100

local W = ns.Widgets
local money = function(c) return ns.Valuation.Money(c) end

local frame, title, toName, toNote, mailCount, stayCount, mailPage, stayPage
local totalLine, totalNote, sendButton, pricesLine, statusLine, legend
local mailRows, stayRows = {}, {}
local result
local pages = { mail = 1, stay = 1 }

UI.CHIPS = {
    ah = { "Auction", 0.2, 0.4, 0.75 },
    de = { "Disenchant", 0.45, 0.25, 0.65 },
    common = { "Common", 0.4, 0.4, 0.4 },
}

function UI.Frame() return frame end
function UI.Result() return result end

--- Pure: "|cffRRGGBB" + name from an item link (no brackets), or the link as is.
function UI.ItemText(link, count, stacks)
    local color, name = tostring(link):match("|c(%x%x%x%x%x%x%x%x).-%[(.-)%]")
    local text = name and ("|c" .. color .. name .. "|r") or tostring(link)
    if count and count > 1 then text = text .. " |cffaaaaaax" .. count .. "|r" end
    if stacks and stacks > 1 then text = text .. " |cff888888(" .. stacks .. " stacks)|r" end
    return text
end

--- Pure: a player-facing reason for an item that stays.
function UI.StayReason(r)
    if r.reason == "not worth it" then
        if (r.gain or 0) <= 0 then return "sells better at a vendor" end
        return string.format("only %s more than a vendor (needs %s)", money(r.gain), money(r.threshold))
    end
    if r.reason == "no price" then return "no auction price yet" end
    if r.reason == "locked" then return "locked (press to unlock)" end
    return r.reason
end

local function firstName(name) return tostring(name):match("^(%S+)") or tostring(name) end

local function toggleLock(row)
    if row.item and not ns.Mailer.Busy() then ns.Locks.ToggleItem(row.item.itemID, row.item.link, "Mailworthy window") end
end

local function showTooltip(row)
    if not row.item or type(GameTooltip) ~= "table" then return end
    local slot = row.item.slots and row.item.slots[1]
    GameTooltip:SetOwner(row.button, "ANCHOR_RIGHT")
    if slot then pcall(GameTooltip.SetBagItem, GameTooltip, slot.bag, slot.slot) end
    GameTooltip:Show()
end

local function rowButton(name, parent, height)
    local b = CreateFrame("Button", name, parent)
    b:SetHeight(height)
    b:SetPoint("LEFT", 16, 0)
    b:SetPoint("RIGHT", -16, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    return b, bg
end

local function createMailRows(top)
    for i = 1, UI.MAIL_ROWS do
        local row = {}
        local b, bg = rowButton("MailworthyMailRow" .. i, frame, MAIL_ROW - 2)
        b:SetPoint("TOP", 0, top - (i - 1) * MAIL_ROW)
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
        row.button = b
        row.icon = b:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 8, 0)
        row.name = W.Label(b, "GameFontHighlight")
        row.name:SetPoint("LEFT", 40, 0)
        row.name:SetWidth(230)
        row.name:SetJustifyH("LEFT")
        row.chipBg = b:CreateTexture(nil, "BORDER")
        row.chipBg:SetSize(84, 16)
        row.chipBg:SetPoint("LEFT", 290, 0)
        row.chip = W.Label(b, "GameFontHighlightSmall")
        row.chip:SetPoint("CENTER", row.chipBg, "CENTER")
        row.gain = W.Label(b, "GameFontHighlight")
        row.gain:SetPoint("RIGHT", -8, 0)
        b:SetScript("OnClick", function() toggleLock(row) end)
        b:SetScript("OnEnter", function() showTooltip(row) end)
        b:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        b:Hide()
        mailRows[i] = row
    end
end

local function createStayRows(top)
    for i = 1, UI.STAY_ROWS do
        local row = {}
        local b, bg = rowButton("MailworthyStayRow" .. i, frame, STAY_ROW - 1)
        b:SetPoint("TOP", 0, top - (i - 1) * STAY_ROW)
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.02 or 0.05)
        row.button = b
        row.name = W.Label(b, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetWidth(220)
        row.name:SetJustifyH("LEFT")
        row.reason = W.Label(b, "GameFontHighlightSmall")
        row.reason:SetPoint("LEFT", 236, 0)
        row.reason:SetWidth(250)
        row.reason:SetJustifyH("LEFT")
        row.reason:SetTextColor(0.55, 0.75, 1)
        b:SetScript("OnClick", function() toggleLock(row) end)
        b:SetScript("OnEnter", function() showTooltip(row) end)
        b:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        b:Hide()
        stayRows[i] = row
    end
end

local function pageButton(name, list)
    local b = W.Button(frame, "", 70, function()
        local rows = list == "mail" and UI.MAIL_ROWS or UI.STAY_ROWS
        local items = result and result[list == "mail" and "mail" or "keep"] or {}
        local count = math.max(1, math.ceil(#items / rows))
        pages[list] = pages[list] % count + 1
        UI.Refresh(true)
    end, name)
    b:Hide()
    return b
end

function UI.Create()
    if frame then return frame end
    local send = rawget(_G, "SendMailFrame")
    frame = W.Window("MailworthyMailWindow", WIDTH, HEIGHT, type(send) == "table" and send or nil)
    title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 22, -18)
    toName = W.Label(frame, "GameFontHighlightLarge")
    toName:SetPoint("TOPLEFT", 24, -50)
    toNote = W.Label(frame, "GameFontDisableSmall")
    toNote:SetPoint("TOPRIGHT", -26, -54)

    local mailTop = -84
    local h = W.Label(frame, "GameFontNormal")
    h:SetPoint("TOPLEFT", 22, mailTop)
    h:SetText("Mailing")
    mailCount = W.Label(frame, "GameFontHighlightSmall")
    mailCount:SetPoint("TOPRIGHT", -24, mailTop - 2)
    mailPage = pageButton("MailworthyMailPage", "mail")
    mailPage:SetPoint("TOPLEFT", 120, mailTop + 4)
    createMailRows(mailTop - 18)

    local stayTop = mailTop - 26 - UI.MAIL_ROWS * MAIL_ROW
    local s = W.Label(frame, "GameFontNormal")
    s:SetPoint("TOPLEFT", 22, stayTop)
    s:SetText("Staying in your bags")
    stayCount = W.Label(frame, "GameFontHighlightSmall")
    stayCount:SetPoint("TOPRIGHT", -24, stayTop - 2)
    stayPage = pageButton("MailworthyStayPage", "stay")
    stayPage:SetPoint("TOPLEFT", 200, stayTop + 4)
    createStayRows(stayTop - 18)

    local totalTop = stayTop - 26 - UI.STAY_ROWS * STAY_ROW
    totalLine = W.Label(frame, "GameFontNormalLarge")
    totalLine:SetPoint("TOPLEFT", 24, totalTop)
    totalLine:SetTextColor(0.6, 1, 0.5)
    totalNote = W.Label(frame, "GameFontHighlightSmall")
    totalNote:SetPoint("TOPLEFT", 24, totalTop - 22)

    local buttonsTop = totalTop - 48
    sendButton = W.Button(frame, "Send", 170, function() UI.Send() end, "MailworthyMailSend")
    sendButton:SetPoint("TOPLEFT", 20, buttonsTop)
    W.Button(frame, "Settings", 110, function() ns.SettingsUI.Show() end, "MailworthyMailSettings")
        :SetPoint("LEFT", sendButton, "RIGHT", 10, 0)
    W.Button(frame, "Close", 110, function() frame:Hide() end, "MailworthyMailClose")
        :SetPoint("TOPRIGHT", -20, buttonsTop)

    statusLine = W.Label(frame, "GameFontHighlightSmall")
    statusLine:SetPoint("TOPLEFT", 24, buttonsTop - 30)
    statusLine:SetWidth(WIDTH - 48)
    statusLine:SetJustifyH("LEFT")
    pricesLine = W.Label(frame, "GameFontDisableSmall")
    pricesLine:SetPoint("BOTTOMRIGHT", -24, 34)
    legend = W.Label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOMLEFT", 24, 16)

    frame:SetScript("OnHide", function(self)
        if type(send) == "table" and self:GetParent() ~= send then self:SetParent(send) end
    end)
    ns.Nav.Attach(frame)
    ns.Log.Add("ui", "mail window created%s", type(send) == "table" and " under SendMailFrame" or "")
    return frame
end

local function fillMail(items)
    local first = (pages.mail - 1) * UI.MAIL_ROWS
    for i, row in ipairs(mailRows) do
        local item = items[first + i]
        row.item = item
        if item then
            local chip = UI.CHIPS[item.result.route] or UI.CHIPS.common
            row.icon:SetTexture(item.icon)
            row.name:SetText(UI.ItemText(item.link, item.count, item.stacks))
            row.chip:SetText(chip[1])
            row.chipBg:SetColorTexture(chip[2], chip[3], chip[4], 0.9)
            row.gain:SetText(item.result.gain and ("+" .. money(item.result.gain)) or "")
            row.button:Show()
        else
            row.button:Hide()
        end
    end
end

local function fillStay(items)
    local first = (pages.stay - 1) * UI.STAY_ROWS
    for i, row in ipairs(stayRows) do
        local item = items[first + i]
        row.item = item
        if item then
            row.name:SetText(UI.ItemText(item.link, item.count))
            row.reason:SetText(UI.StayReason(item.result))
            row.button:Show()
        else
            row.button:Hide()
        end
    end
end

local function pageLabel(button, list, rows)
    local count = math.ceil(#list / rows)
    if count <= 1 then
        button:Hide()
        return
    end
    button:SetText(string.format("%d/%d  >", math.min(pages[button == mailPage and "mail" or "stay"], count), count))
    button:Show()
end

--- Re-scan the bags (unless only paging) and redraw.
function UI.Refresh(keepScan)
    if not frame then return end
    if not keepScan or not result then
        if not ns.Mailer.Busy() then result = ns.Bags.Evaluate() end
    end
    if not result then return end
    title:SetText("Mailworthy  " .. (ns.MailButton.GamepadUI() and ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP) or ""))
    local bankAlt = ns.Config.BankAlt()
    local isBankAlt = bankAlt and bankAlt:lower() == tostring(ns.PlayerName()):lower()
    toName:SetText("|cffffd100To:|r " .. (bankAlt or "|cffff8040no bank alt set: press Settings|r"))
    toNote:SetText(isBankAlt and "this is your bank alt" or (bankAlt and "your bank alt" or ""))

    local t = result.totals
    for list, n in pairs({ mail = UI.MAIL_ROWS, stay = UI.STAY_ROWS }) do
        local items = result[list == "mail" and "mail" or "keep"]
        if pages[list] > math.max(1, math.ceil(#items / n)) then pages[list] = 1 end
    end
    mailCount:SetText(string.format("%d items in %d mail%s", t.items, t.mails, t.mails == 1 and "" or "s"))
    stayCount:SetText(string.format("%d item%s", #result.keep, #result.keep == 1 and "" or "s"))
    fillMail(result.mail)
    fillStay(result.keep)
    pageLabel(mailPage, result.mail, UI.MAIL_ROWS)
    pageLabel(stayPage, result.keep, UI.STAY_ROWS)

    if result.priced then
        totalLine:SetText("+" .. money(t.gain) .. " more than vendoring")
        totalNote:SetText(string.format("after the %d%% auction cut, deposits (%dh listing) and postage (%s)",
            math.floor(result.settings.cut * 100 + 0.5), ns.Valuation.DURATION_HOURS[result.settings.duration],
            money(t.postage)))
    else
        totalLine:SetText(string.format("%d common item%s to mail", t.items, t.items == 1 and "" or "s"))
        totalNote:SetText("No Auctionator prices: mailing white items only. Postage " .. money(t.postage) .. ".")
    end
    sendButton:SetText(ns.Mailer.Busy() and "Sending..." or (bankAlt and not isBankAlt)
        and ("Send to " .. firstName(bankAlt)) or "Send")
    pricesLine:SetText(string.format("Prices: %s  ·  Disenchant values: %s",
        result.priced and "Auctionator" or "none", result.settings.disenchant and "on" or "off"))
    local status = ns.Mailer.Status()
    if not status then
        status = "Press an item to lock it (it stays in your bags); press a locked one to unlock it."
    end
    statusLine:SetText(status)
    legend:SetText(ns.MailButton.GamepadUI() and W.Legend(ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP) .. " open / close") or "")
end

function UI.Send()
    if not result then return end
    ns.lastCommand = "Mailworthy Send"
    UI.Refresh() -- the freshest scan, so the mail list is what's in the bags now
    ns.Mailer.Start(result.mail, ns.Config.BankAlt())
    UI.Refresh(true)
end

--- Beside the mail window, as a child of the showing tab; away from a mailbox, centred.
function UI.Show(tab)
    if not frame then UI.Create() end
    local send, inbox, mail = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame"), rawget(_G, "MailFrame")
    local parent = (tab == "inbox") and inbox or send
    frame:ClearAllPoints()
    if type(parent) == "table" and type(mail) == "table" then
        if frame:GetParent() ~= parent then frame:SetParent(parent) end
        frame:SetPoint("TOPLEFT", mail, "TOPRIGHT", 8, 0)
    else
        frame:SetParent(UIParent)
        frame:SetPoint("CENTER")
    end
    pages.mail, pages.stay = 1, 1
    UI.Refresh()
    frame:Show()
    ns.Log.Add("ui", "mail window shown (%s tab): %d to mail, %d staying", tostring(tab), #result.mail, #result.keep)
end

function UI.Toggle(tab)
    if frame and frame:IsShown() then
        frame:Hide()
    else
        UI.Show(tab)
    end
end

local function refreshIfShown()
    if frame and frame:IsShown() then UI.Refresh() end
end

ns.On("PLAYER_LOGIN", function()
    UI.Create()
    ns.Locks.OnChanged(refreshIfShown)
    -- While sending, redraw the status only; once it's done or stopped, re-scan: the bag
    -- update for the sent items may have come mid-send, when it was skipped (v0.4.0).
    ns.Mailer.OnChanged(function()
        if frame and frame:IsShown() then UI.Refresh(ns.Mailer.Busy()) end
    end)
    local settings = ns.SettingsUI.Frame()
    if settings then settings:HookScript("OnHide", refreshIfShown) end
end)
ns.On("BAG_UPDATE_DELAYED", function()
    if not ns.Mailer.Busy() then refreshIfShown() end
end)
