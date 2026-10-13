-- Stubs for the WoW API Mailworthy calls. `WowStub.reset()` clears saved
-- variables and printed lines; tests tweak globals before calling the addon.
local WowStub = {}
_G.WowStub = WowStub

local printed = {}
WowStub.printed = printed

function WowStub.reset()
    for i = #printed, 1, -1 do printed[i] = nil end
    _G.MailworthyDB, _G.MailworthyCharDB = nil, nil
    WowStub.focusCalls = 0
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
    local w = { kind = kind, name = name, scripts = {}, shown = false, events = {} }
    return setmetatable(w, { __index = function(self, key)
        if key == "SetScript" then return function(_, ev, fn) self.scripts[ev] = fn end end
        if key == "GetScript" then return function(_, ev) return self.scripts[ev] end end
        if key == "RegisterEvent" then return function(_, ev) self.events[ev] = true end end
        if key == "UnregisterEvent" then return function(_, ev) self.events[ev] = nil end end
        if key == "SetFocus" then return function() WowStub.focusCalls = WowStub.focusCalls + 1 end end
        if key == "Show" then return function() self.shown = true end end
        if key == "Hide" then return function() self.shown = false end end
        if key == "IsShown" then return function() return self.shown end end
        return function() end
    end })
end
WowStub.newWidget = newWidget
WowStub.frames = {}
_G.CreateFrame = function(kind, name)
    local w = newWidget(kind, name)
    if name then WowStub.frames[name] = w; _G[name] = w end
    return w
end
_G.SlashCmdList = {}

WowStub.reset()
return WowStub
