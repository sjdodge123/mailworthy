-- Blue border on locked slots in the bags. Textures are created on the game's
-- bag item buttons (CreateTexture isn't hooked by smart navigation and
-- textures aren't returned by GetChildren, so its button scan never sees them)
-- and kept in our own weak table: no field is ever written on a Blizzard frame.
-- Buttons are pooled, so every refresh recomputes from GetBagID / GetID.
-- Refreshed by a post-hook on each container frame's UpdateItems (combined bags
-- and the individual bag frames) and whenever a lock changes.
local _, ns = ...

local Border = {}
ns.Border = Border

Border.COLOR = { 0.25, 0.6, 1, 1 }
Border.THICKNESS = 2

local borders = setmetatable({}, { __mode = "k" }) -- item button -> { textures }
local frames = {}

local function edges(button)
    local set = borders[button]
    if set then return set end
    set = {}
    local t = Border.THICKNESS
    local specs = {
        { "TOPLEFT", "TOPRIGHT", nil, t }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, t },
        { "TOPLEFT", "BOTTOMLEFT", t, nil }, { "TOPRIGHT", "BOTTOMRIGHT", t, nil },
    }
    for i, spec in ipairs(specs) do
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(unpack(Border.COLOR))
        tex:SetPoint(spec[1])
        tex:SetPoint(spec[2])
        if spec[3] then tex:SetWidth(spec[3]) end
        if spec[4] then tex:SetHeight(spec[4]) end
        set[i] = tex
    end
    borders[button] = set
    return set
end

local function show(button, shown)
    if not shown and not borders[button] then return end
    for _, tex in ipairs(edges(button)) do
        if shown then tex:Show() else tex:Hide() end
    end
end

function Border.RefreshFrame(frame)
    if type(frame) ~= "table" or type(frame.EnumerateValidItems) ~= "function" then return end
    local ok, iter, state, start = pcall(frame.EnumerateValidItems, frame)
    if not ok or type(iter) ~= "function" then return end
    for _, button in iter, state, start do
        local okBag, bag = pcall(button.GetBagID, button)
        local okSlot, slot = pcall(button.GetID, button)
        show(button, okBag and okSlot and ns.Locks.IsLocked(bag, slot))
    end
end

function Border.RefreshAll()
    for _, frame in ipairs(frames) do Border.RefreshFrame(frame) end
end

local function containerFrames()
    local list = {}
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if type(combined) == "table" then list[#list + 1] = combined end
    local container = rawget(_G, "ContainerFrameContainer")
    for _, frame in ipairs(type(container) == "table" and type(container.ContainerFrames) == "table"
        and container.ContainerFrames or {}) do
        list[#list + 1] = frame
    end
    return list
end

function Border.Install()
    if not ns.Features.On("slotBorder") then
        ns.Log.Add("border", "slot border off (/mw feature slotBorder on, then /reload)")
        return
    end
    local hooked = 0
    for _, frame in ipairs(containerFrames()) do
        if type(frame.UpdateItems) == "function" then
            local ok = pcall(hooksecurefunc, frame, "UpdateItems", function(self)
                local okRefresh, err = pcall(Border.RefreshFrame, self)
                if not okRefresh then ns.Log.Add("border", "refresh error: %s", tostring(err)) end
            end)
            if ok then
                hooked = hooked + 1
                frames[#frames + 1] = frame
            end
        end
    end
    ns.Locks.OnChanged(Border.RefreshAll)
    ns.Log.Add("border", "UpdateItems hooked on %d container frames", hooked)
end

ns.On("PLAYER_LOGIN", function() Border.Install() end)
