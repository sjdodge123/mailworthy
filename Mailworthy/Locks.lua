-- Slot locks: slots Mailworthy never mails. Saved per character.
--
-- Ways to toggle a lock, none of which writes into Blizzard's UI:
--   * keyboard / mouse: Alt+click a bag item. A post-hook on the global
--     HandleModifiedItemClick, which the bag item button calls for modified
--     clicks; with only Alt held it matches none of its cases (chat link,
--     dress-up, expand), so Blizzard does nothing else with the click.
--   * controller: the "Bag locks" page of the Mailworthy window (SelfTestUI).
--
-- Not the gamepad Triangle "More" menu: adding an entry there (Menu.ModifyMenu
-- on MORE_CONTEXT_ACTIONS) taints the gamepad UI by design - Blizzard's menu
-- code runs our element factory and hands the menu to SmartNavigation, which
-- then writes its state tainted; jumping, targeting and item use got blocked
-- (alpha1/alpha2, 2026-10-13). See docs/FOREVER-UI-NOTES.md.
local _, ns = ...

local Locks = {}
ns.Locks = Locks

local listeners = {}

function Locks.Key(bag, slot)
    return bag .. ":" .. slot
end

function Locks.IsLocked(bag, slot)
    return MailworthyCharDB ~= nil and MailworthyCharDB.lockedSlots[Locks.Key(bag, slot)] ~= nil
end

function Locks.OnChanged(fn) table.insert(listeners, fn) end

local function itemAt(bag, slot)
    local get = C_Container and C_Container.GetContainerItemInfo
    if type(get) ~= "function" then return nil end
    local ok, info = pcall(get, bag, slot)
    return ok and type(info) == "table" and info or nil
end
Locks.ItemAt = itemAt

local function describe(info)
    return info and (info.hyperlink or tostring(info.itemID)) or "empty slot"
end

function Locks.Toggle(bag, slot, how)
    local key, info = Locks.Key(bag, slot), itemAt(bag, slot)
    local locked = not Locks.IsLocked(bag, slot)
    MailworthyCharDB.lockedSlots[key] = locked and { itemID = info and info.itemID, at = time() } or nil
    ns.Log.Add("lock", "%s bag %d slot %d (%s) by %s", locked and "locked" or "unlocked", bag, slot, describe(info),
        tostring(how))
    ns.Print(string.format("%s bag %d slot %d (%s).", locked and "Locked" or "Unlocked", bag, slot, describe(info)))
    for _, fn in ipairs(listeners) do pcall(fn) end
    return locked
end

function Locks.PrintList()
    local keys = {}
    for key in pairs(MailworthyCharDB.lockedSlots) do keys[#keys + 1] = key end
    table.sort(keys)
    ns.Print(#keys == 0 and "No locked slots." or ("Locked slots (bag:slot): " .. table.concat(keys, ", ")))
end

local function isBagSlot(bag)
    return type(bag) == "number" and bag >= 0 and bag <= (tonumber(NUM_BAG_SLOTS) or 4)
end

--- Post-hook of HandleModifiedItemClick(link, itemLocation): Alt (alone) + click on a bag item.
function Locks.OnModifiedItemClick(_, itemLocation)
    if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    if type(itemLocation) ~= "table" or type(itemLocation.IsBagAndSlot) ~= "function" then return end
    local okIs, isBag = pcall(itemLocation.IsBagAndSlot, itemLocation)
    if not okIs or not isBag then return end
    local ok, bag, slot = pcall(itemLocation.GetBagAndSlot, itemLocation)
    if ok and isBagSlot(bag) and type(slot) == "number" then Locks.Toggle(bag, slot, "Alt+click") end
end

function Locks.Install()
    if not ns.Features.On("altClickLock") then
        ns.Log.Add("lock", "Alt+click lock off (/mw feature altClickLock on, then /reload)")
        return false
    end
    if type(HandleModifiedItemClick) ~= "function" then
        ns.Log.Add("lock", "HandleModifiedItemClick missing: no Alt+click lock")
        return false
    end
    local ok, err = pcall(hooksecurefunc, "HandleModifiedItemClick", function(link, itemLocation)
        local okHook, errHook = pcall(Locks.OnModifiedItemClick, link, itemLocation)
        if not okHook then ns.Log.Add("lock", "Alt+click hook error: %s", tostring(errHook)) end
    end)
    ns.Log.Add("lock", "Alt+click lock hook %s", ok and "installed" or ("failed: " .. tostring(err)))
    return ok
end

ns.On("PLAYER_LOGIN", function() Locks.Install() end)
