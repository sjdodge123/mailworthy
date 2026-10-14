-- Blue glow on locked items in the bags: the quest-item border, tinted blue.
-- Textures are created on the game's bag item buttons (CreateTexture isn't
-- hooked by smart navigation and
-- textures aren't returned by GetChildren, so its button scan never sees them)
-- and kept in our own weak table: no field is ever written on a Blizzard frame.
-- Buttons are pooled, so every refresh recomputes from GetBagID / GetID.
-- Refreshed by a post-hook on each container frame's UpdateItems (combined bags
-- and the individual bag frames) and whenever a lock changes.
local _, ns = ...

local Border = {}
ns.Border = Border

-- The quest-item border Blizzard draws on bag slots (TEXTURE_ITEM_QUEST_BORDER),
-- desaturated and tinted blue, plus an additive copy for the glow.
Border.TEXTURE = "Interface\\ContainerFrame\\UI-Icon-QuestBorder"
Border.COLOR = { 0.3, 0.65, 1 }
Border.GLOW_ALPHA = 0.7

local borders = setmetatable({}, { __mode = "k" }) -- button -> { textures }
local frames = {}
local decorators = {} -- fn(button, bag, slot): more per-slot drawing (bank alt tags)

--- Draw more on every bag button after each refresh (same hooks, same rules).
function Border.AddDecorator(fn) table.insert(decorators, fn) end

--- The lock glow for any button (ours or the game's bag buttons), created once,
--- kept in our own weak table.
function Border.Glow(button)
    local set = borders[button]
    if set then return set end
    set = {}
    for i, blend in ipairs({ "BLEND", "ADD" }) do
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 6 + i - 1)
        tex:SetTexture(Border.TEXTURE)
        tex:SetAllPoints()
        tex:SetDesaturated(true)
        tex:SetVertexColor(unpack(Border.COLOR))
        tex:SetBlendMode(blend)
        if blend == "ADD" then tex:SetAlpha(Border.GLOW_ALPHA) end
        tex:Hide()
        set[i] = tex
    end
    borders[button] = set
    return set
end

function Border.Show(button, shown)
    if not shown and not borders[button] then return end
    for _, tex in ipairs(Border.Glow(button)) do
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
        local valid = okBag and okSlot
        if ns.Features.On("slotBorder") then Border.Show(button, valid and ns.Locks.IsLocked(bag, slot)) end
        for _, fn in ipairs(decorators) do
            local okDecorate, err = pcall(fn, button, valid and bag or nil, valid and slot or nil)
            if not okDecorate then ns.Log.Add("border", "decorator error: %s", tostring(err)) end
        end
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
    -- The hooks serve the lock glow and the bank alt tags: either switch keeps them.
    if not ns.Features.On("slotBorder") and not ns.Features.On("bankAltTags") then
        ns.Log.Add("border", "slot border and bank alt tags off (/mw feature slotBorder on, then /reload)")
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
