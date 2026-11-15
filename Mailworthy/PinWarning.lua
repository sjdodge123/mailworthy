-- The warning when a pin to the bank alt (BA) takes an item this character's own profession uses
-- ("Keep my professions' materials" would keep it). The pin wins (operator, 2026-11-13: "a bank pin
-- is a hard decision by the user and needs to be honored"), but the player hears it once, with a
-- quick way to reduce the conflict: bank this character's pins here (BH), or unpin the item.
-- "Don't show this again" turns it off for the account (Settings > Bags and more > "Pin warning: off"
-- brings it back, so does /mw pinwarning on; /mw report says which). The Mailworthy window's row and
-- the bag tooltip say it every time, so turning the window off loses nothing.
--
-- Our own window (created at login, Nav + PadKey "settings" set): every control is a button.
local _, ns = ...

local UI = {}
ns.PinWarning = UI

local W = ns.Widgets
local WIDTH = 440
local win, frame, text
local BOTTOM = -178 -- the second row of buttons
local current -- { itemID, link, profession } the window is about

function UI.Frame() return frame end
function UI.Text() return text and text:GetText() end

function UI.Hidden() return ns.Config.Flag("hidePinWarning") end

--- Pure: the window's text.
function UI.Message(link, profession)
    local ba, bh = ns.Palette.Letters(ns.Palette.BA), ns.Palette.Letters(ns.Palette.BH)
    return string.format("%s is pinned to your bank alt (%s), but your %s uses it.\n\n"
        .. "The pin wins: Send mails it to your bank alt.\n\n"
        .. "To keep it here instead: bank this character's pins here (%s; every pin then stays on this character),"
        .. " or unpin it.", tostring(link), ba, tostring(profession), bh)
end

--- A BA pin was just set (Pins.Set): show the warning when this character's profession uses the item.
function UI.Check(itemID, link)
    if UI.Hidden() then return false end
    local ok, profession = pcall(ns.Bags.ProfessionKeep, link, itemID)
    if not ok or not profession then return false end
    UI.Show(itemID, link, profession)
    return true
end

function UI.Show(itemID, link, profession)
    if not frame then UI.Create() end
    current = { itemID = itemID, link = link, profession = profession }
    text:SetText(UI.Message(link, profession))
    frame:Show()
    frame:Raise()
    win.Finish(BOTTOM, false)
    ns.Log.Add("pin", "warning: %s pinned to the bank alt, %s uses it", tostring(link), tostring(profession))
end

local function close() if frame then frame:Hide() end end

function UI.Create()
    if frame then return frame end
    win = W.Shell({ name = "MailworthyPinWarningFrame", width = WIDTH, height = 250,
        title = "Pinned, but your profession uses it", log = "pin warning window" })
    frame = win.frame
    text = W.Label(frame, "GameFontHighlight")
    text:SetPoint("TOPLEFT", 28, -48)
    text:SetWidth(WIDTH - 56)
    text:SetJustifyH("LEFT")
    W.Button(frame, "OK, keep the pin", 186, close, "MailworthyPinWarningOK"):SetPoint("TOPLEFT", 24, -150)
    W.Button(frame, "Unpin it", 186, function()
        -- Not mid-send, like every pin change: what is on its way was previewed (Codex review, 2026-11-13).
        if ns.Mailer.Busy() then
            ns.Print(ns.Pins.BUSY)
            return
        end
        if current and ns.Pins.Kind(current.itemID) then
            ns.Pins.Set(current.itemID, current.link, nil, "pin warning")
        end
        close()
    end, "MailworthyPinWarningUnpin"):SetPoint("TOPRIGHT", -24, -150)
    W.Button(frame, "Bank pins here (BH)", 186, function()
        if ns.Pins.SetMode(ns.Pins.HERE, "pin warning") then close() end
    end, "MailworthyPinWarningHere"):SetPoint("TOPLEFT", 24, BOTTOM)
    W.Button(frame, "Don't show this again", 186, function()
        ns.Config.Set("hidePinWarning", true)
        -- The button that brings it back, by name (UX review U6, U3).
        ns.Print("Pin warning off. The Mailworthy window and the tooltip still say it."
            .. " Settings > Bags and more > \"Pin warning: off\" brings it back.")
        close()
    end, "MailworthyPinWarningHide"):SetPoint("TOPRIGHT", -24, BOTTOM)
    frame:Hide()
    return frame
end

ns.On("PLAYER_LOGIN", function() UI.Create() end)
