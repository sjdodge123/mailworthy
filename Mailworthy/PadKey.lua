-- Triangle (Y) at the mailbox, without touching Blizzard's controller UI.
--
-- alpha1 added Triangle to the mail window's footer; that wrote into Blizzard's
-- binding stack and tainted gamepad input game-wide. Instead, while the mail
-- window is the controller's focused window, Mailworthy sets its OWN override
-- binding: SetOverrideBindingClick(our frame, true, "PAD4", our button). That
-- touches no Blizzard Lua table. Blizzard binds unused face buttons to nothing
-- while a window is focused (FrameControlsManager's fallthrough catcher) and
-- re-applies its bindings on many refreshes, so a watcher checks every 0.1 s
-- (GetBindingAction("PAD4", true)) and re-applies ours when it was replaced -
-- the pattern wow-forever-tweaks uses. The binding is cleared as soon as the
-- mail window loses focus (e.g. L2/R2 to the bags, where Triangle is the bags'
-- More menu), when the mailbox closes and when combat starts.
-- Reads FrameControlsManager:GetActiveFrame() only.
local _, ns = ...

local PadKey = {}
ns.PadKey = PadKey

PadKey.KEY = "PAD4"
PadKey.BUTTON = "MailworthyPadButton"
PadKey.ACTION = "CLICK MailworthyPadButton:LeftButton"
PadKey.INTERVAL = 0.1

local watcher, bound, elapsed = nil, false, 0
PadKey.stats = { applies = 0, clears = 0, presses = 0 }

local function activeFrame()
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    if type(manager) ~= "table" or type(manager.GetActiveFrame) ~= "function" then return nil end
    local ok, frame = pcall(manager.GetActiveFrame, manager)
    return ok and frame or nil
end

function PadKey.Wanted()
    if InCombatLockdown() then return false end
    local mail = rawget(_G, "MailFrame")
    if type(mail) ~= "table" or not mail:IsShown() then return false end
    return activeFrame() == mail
end

local function clear(reason)
    if not bound then return end
    if InCombatLockdown() then return end
    pcall(ClearOverrideBindings, watcher)
    bound = false
    PadKey.stats.clears = PadKey.stats.clears + 1
    ns.Log.Add("pad", "Triangle binding cleared (%s)", reason)
end

function PadKey.Check()
    if not PadKey.Wanted() then return clear("mail window not focused") end
    local okAction, action = pcall(GetBindingAction, PadKey.KEY, true)
    if okAction and action == PadKey.ACTION then return end
    local ok, err = pcall(SetOverrideBindingClick, watcher, true, PadKey.KEY, PadKey.BUTTON)
    PadKey.stats.applies = PadKey.stats.applies + 1
    PadKey.stats.lastReplaced = okAction and tostring(action) or "?"
    if not bound or PadKey.stats.applies <= 3 or PadKey.stats.applies % 25 == 0 then
        ns.Log.Add("pad", "Triangle binding %s (apply #%d, PAD4 was %q)%s", bound and "re-applied" or "set",
            PadKey.stats.applies, PadKey.stats.lastReplaced, ok and "" or (": " .. tostring(err)))
    end
    bound = ok
end

function PadKey.Create()
    if watcher then return end
    if not ns.Features.On("padTriangle") then
        ns.Log.Add("pad", "Triangle at the mailbox off (/mw feature padTriangle on, then /reload)")
        return
    end
    watcher = CreateFrame("Frame", "MailworthyPadWatcher", UIParent)
    watcher:Hide()
    watcher:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < PadKey.INTERVAL then return end
        elapsed = 0
        local ok, err = pcall(PadKey.Check)
        if not ok then ns.Log.Add("pad", "check error: %s", tostring(err)) end
    end)
    -- Hidden click target for the binding. A CLICK binding may deliver the press as
    -- down, up or both depending on settings, so take either and debounce.
    local pad = CreateFrame("Button", PadKey.BUTTON, UIParent)
    pad:Hide()
    pad:RegisterForClicks("AnyDown", "AnyUp")
    local last = 0
    pad:SetScript("OnClick", function()
        local now = GetTime()
        if now - last < 0.3 then return end
        last = now
        PadKey.stats.presses = PadKey.stats.presses + 1
        ns.MailButton.Activate("Triangle")
    end)
    ns.Log.Add("pad", "Triangle watcher ready")
end

function PadKey.Report()
    return string.format("Triangle binding: applies %d, clears %d, presses %d, last replaced %s, PAD4 now %s",
        PadKey.stats.applies, PadKey.stats.clears, PadKey.stats.presses, tostring(PadKey.stats.lastReplaced),
        tostring(select(2, pcall(GetBindingAction, PadKey.KEY, true))))
end

ns.On("PLAYER_LOGIN", function() PadKey.Create() end)
ns.On("MAIL_SHOW", function()
    if watcher then elapsed = PadKey.INTERVAL; watcher:Show() end
end)
ns.On("MAIL_CLOSED", function()
    if watcher then watcher:Hide(); clear("mailbox closed") end
end)
ns.On("PLAYER_REGEN_DISABLED", function() clear("combat") end)
