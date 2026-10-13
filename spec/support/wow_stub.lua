-- Stubs for the WoW API Mailworthy calls. `WowStub.reset()` restores a default
-- character, bags, mailbox and gamepad UI; tests tweak `WowStub.state` (or the
-- globals) before calling the addon. Timers queue until `WowStub.runTimers()`.
local WowStub = {}
_G.WowStub = WowStub

local printed = {}
WowStub.printed = printed

local function link(id, name) return string.format("|cffffffff|Hitem:%d::::::::8:::::|h[%s]|h|r", id, name) end
WowStub.link = link

--- A bag item: WowStub.item(2770, "Copper Ore", { count = 5, sell = 5, class = 7 })
function WowStub.item(id, name, o)
    o = o or {}
    return {
        itemID = id, hyperlink = link(id, name), stackCount = o.count or 1, quality = o.quality or 1,
        isBound = o.bound or false, hasNoValue = o.noValue or false, isLocked = false,
        sell = o.sell or 1, class = o.class or 7, quest = o.quest or false,
    }
end

local function defaultState()
    return {
        name = "Rettana Quilwrit", realm = "Classic Beta PvP", faction = "Alliance",
        class = { "Paladin", "PALADIN", 2 }, level = 8, serverTime = 1791900000, inCombat = false,
        professions = { { index = 6, name = "Mining", rank = 12, maxRank = 75, skillLine = 186 } },
        numSlots = { [0] = 20, [1] = 4, [2] = 6, [3] = 0, [4] = 0 },
        bags = { [0] = {}, [1] = {}, [2] = {} },
        attached = {}, cursor = nil, used = {}, sent = {}, postage = 30,
        inbox = {}, invoices = {},
    }
end

local function s() return WowStub.state end

function WowStub.setBag(bag, slot, item) s().bags[bag] = s().bags[bag] or {}; s().bags[bag][slot] = item end

--- Timers queue with their delay; runTimers(upTo) runs, in order, every timer
--- (including ones queued meanwhile) whose own delay is at most `upTo` seconds (default 1),
--- so a 10-second timeout stays pending unless a test asks for it.
WowStub.timers = {}
function WowStub.runTimers(upTo)
    upTo = upTo or 1
    local guard, ran = 0, true
    while ran and guard < 100 do
        ran = false
        for i, t in ipairs(WowStub.timers) do
            if t.delay <= upTo then
                table.remove(WowStub.timers, i)
                guard, ran = guard + 1, true
                t.fn()
                break
            end
        end
    end
end

WowStub.menuModifiers = {}

function WowStub.reset()
    WowStub.state = defaultState()
    for i = #printed, 1, -1 do printed[i] = nil end
    for i = #WowStub.timers, 1, -1 do WowStub.timers[i] = nil end
    WowStub.menuModifiers = {}
    WowStub.focusCalls = 0
    WowStub.managerCalls = {}
    _G.MailworthyDB, _G.MailworthyCharDB = nil, nil
    _G.Auctionator = nil
    _G.SendMailFrame = WowStub.newWidget("Frame", "SendMailFrame")
    _G.InboxFrame = WowStub.newWidget("Frame", "InboxFrame")
    _G.MailFrame = WowStub.newWidget("Frame", "MailFrame")
end

_G.unpack = _G.unpack or table.unpack -- luacheck: ignore 143
_G.time = os.time
_G.date = os.date
_G.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    printed[#printed + 1] = table.concat(t, " ")
end

-- Widget stubs: any method call is accepted; the ones tests read are recorded.
-- SetFocus is counted so specs can prove the addon never calls it (gamepad crash).
local function newWidget(kind, name)
    local w = { kind = kind, name = name, scripts = {}, hooks = {}, shown = false, events = {} }
    local function runHooks(ev) for _, fn in ipairs(w.hooks[ev] or {}) do fn(w) end end
    return setmetatable(w, { __index = function(self, key)
        if key == "SetScript" then return function(_, ev, fn) self.scripts[ev] = fn end end
        if key == "GetScript" then return function(_, ev) return self.scripts[ev] end end
        if key == "HookScript" then
            return function(_, ev, fn) self.hooks[ev] = self.hooks[ev] or {}; table.insert(self.hooks[ev], fn) end
        end
        if key == "RegisterEvent" then return function(_, ev) self.events[ev] = true end end
        if key == "UnregisterEvent" then return function(_, ev) self.events[ev] = nil end end
        if key == "SetFocus" then return function() WowStub.focusCalls = WowStub.focusCalls + 1 end end
        if key == "Show" then return function() self.shown = true; runHooks("OnShow") end end
        if key == "Hide" then return function() self.shown = false; runHooks("OnHide") end end
        if key == "IsShown" then return function() return self.shown end end
        if key == "SetText" then return function(_, t) self.text = t end end
        if key == "GetText" then return function() return self.text end end
        if key == "GetName" then return function() return self.name end end
        if key == "SetParent" then return function(_, p) self.parent = p end end
        if key == "GetParent" then return function() return self.parent end end
        if key == "Click" then return function() if self.scripts.OnClick then self.scripts.OnClick(self) end end end
        if key == "CreateFontString" or key == "CreateTexture" then
            return function() return newWidget(key == "CreateTexture" and "Texture" or "FontString") end
        end
        -- Like real frames: unset fields (lowercase, e.g. gamepadFooter) are nil; methods are no-ops.
        if type(key) == "string" and key:match("^%l") then return nil end
        return function() end
    end })
end
WowStub.newWidget = newWidget
WowStub.frames = {}
_G.CreateFrame = function(kind, name, parent)
    local w = newWidget(kind, name)
    w.parent = parent
    if name then WowStub.frames[name] = w; _G[name] = w end
    return w
end
_G.UIParent = newWidget("Frame", "UIParent")
_G.UISpecialFrames = {}
_G.ChatFontNormal = {}
_G.SlashCmdList = {}
_G.NUM_BAG_SLOTS = 4
_G.ATTACHMENTS_MAX_SEND = 12

_G.hooksecurefunc = function(t, method, hook)
    local original = t[method]
    t[method] = function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end
end
_G.C_Timer = { After = function(delay, fn) table.insert(WowStub.timers, { delay = delay, fn = fn }) end }

-- Character
_G.GetUnitName = function() return s().name end
_G.UnitName = function() return (s().name:match("^(%S+)")) end
_G.GetRealmName = function() return s().realm end
_G.UnitFactionGroup = function() return s().faction end
_G.UnitClass = function() return unpack(s().class, 1, 3) end
_G.UnitLevel = function() return s().level end
_G.GetServerTime = function() return s().serverTime end
_G.InCombatLockdown = function() return s().inCombat end
_G.GetBuildInfo = function() return "1.60.1", "70338", "Oct  9 2026", 16001 end
_G.GetProfessions = function()
    local idx = {}
    for i, p in ipairs(s().professions) do idx[i] = p.index end
    return unpack(idx)
end
_G.GetProfessionInfo = function(index)
    for _, p in ipairs(s().professions) do
        if p.index == index then return p.name, 0, p.rank, p.maxRank, 0, 0, p.skillLine end
    end
end

-- Items and bags
local function byLink(l)
    for _, bag in pairs(s().bags) do
        for _, item in pairs(bag) do
            if item.hyperlink == l or item.itemID == l then return item end
        end
    end
end
_G.GetItemInfo = function(l)
    local item = byLink(l)
    if item then return "name", item.hyperlink, item.quality, 1, 1, "t", "s", 20, "", 0, item.sell end
end
_G.GetItemInfoInstant = function(l)
    local item = byLink(l)
    if item then return item.itemID, "t", "s", "", 0, item.class, 0 end
end
local function at(bag, slot) return s().bags[bag] and s().bags[bag][slot] end
local function attachItem(item)
    if not item or item.isLocked or #s().attached >= 12 then return end
    item.isLocked = true
    table.insert(s().attached, item)
end
_G.C_Container = {
    GetContainerNumSlots = function(bag) return s().numSlots[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot) return at(bag, slot) end,
    GetContainerItemQuestInfo = function(bag, slot)
        local item = at(bag, slot)
        return { isQuestItem = item and item.quest or false }
    end,
    UseContainerItem = function(bag, slot)
        if SendMailFrame:IsShown() then attachItem(at(bag, slot)) else table.insert(s().used, { bag, slot }) end
    end,
    PickupContainerItem = function(bag, slot) s().cursor = at(bag, slot) end,
}
_G.CursorHasItem = function() return s().cursor ~= nil end
_G.ClearCursor = function() s().cursor = nil end

-- Mail
_G.ClickSendMailItemButton = function()
    if s().cursor then attachItem(s().cursor); s().cursor = nil end
end
_G.GetSendMailItem = function(i)
    local item = s().attached[i]
    if item then return "name", item.itemID, 0, item.stackCount, item.quality end
end
_G.GetSendMailPrice = function() return s().postage * math.max(1, #s().attached) end
_G.ClearSendMail = function()
    for _, item in ipairs(s().attached) do item.isLocked = false end
    s().attached = {}
end
_G.SendMail = function(name, subject, body)
    local count = #s().attached
    for _, item in ipairs(s().attached) do
        for _, bag in pairs(s().bags) do
            for slot, x in pairs(bag) do if x == item then bag[slot] = nil end end
        end
    end
    s().attached = {}
    table.insert(s().sent, { name = name, subject = subject, body = body, count = count })
end
_G.C_Mail = { IsCommandPending = function() return false end }
_G.GetInboxNumItems = function() return #s().inbox, #s().inbox end
_G.GetInboxHeaderInfo = function(i)
    local m = s().inbox[i]
    if m then return nil, nil, m.sender, m.subject, 0, 0, m.daysLeft or 30, m.hasItem or 1 end
end
_G.GetInboxInvoiceInfo = function(i)
    local v = s().invoices[i]
    if v then return v.type, v.item, v.player, v.bid, v.buyout, v.deposit, v.cut, 0, 0, 0, v.count end
end

-- Menu + gamepad UI
_G.Menu = { ModifyMenu = function(tag, fn) WowStub.menuModifiers[tag] = fn end }

--- A footer like Blizzard's PromptedBindingFooter, recording what's added.
function WowStub.footer()
    local f = { bindings = {}, calls = {}, finalized = 0, isShown = false }
    local function rec(name) return function(_, ...) table.insert(f.calls, name) return ... end end
    f.AddStandardSelectPrompt = rec("select")
    f.AddStandardBackPrompt = rec("back")
    f.AddStandardFrameControlManagerBindings = rec("frameControls")
    f.AddPromptedBinding = function(self, b) table.insert(self.bindings, b); table.insert(self.calls, "binding") end
    f.Finalize = function(self) self.finalized = self.finalized + 1; table.insert(self.calls, "finalize") end
    f.ShowAndActivateBindings = function(self) self.isShown = true end
    f.HideAndDeactivateBindings = function(self) self.isShown = false end
    return f
end
_G.GamepadSharedUtility = {
    CreatePromptedBinding = function(key, fn, label) return { key = key, fn = fn, label = label } end,
    CreatePromptedBindingFooter = function() return WowStub.footer() end,
}
_G.GamepadMode = { FrameControlsManager = {
    FrameShown = function(_, f) table.insert(WowStub.managerCalls, { "shown", f.name }) end,
    FrameHidden = function(_, f) table.insert(WowStub.managerCalls, { "hidden", f.name }) end,
} }
_G.C_GamePad = {
    GetActiveDeviceID = function() return 5 end,
    GetDeviceMappedState = function() return { labelStyle = "Shapes" } end,
}

WowStub.reset()
return WowStub
