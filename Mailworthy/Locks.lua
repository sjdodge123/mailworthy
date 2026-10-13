-- Slot locks from the game's own item menu: Triangle (Y) on a bag item opens a
-- Blizzard Menu tagged MORE_CONTEXT_ACTIONS; we add "Mailworthy: Lock slot" /
-- "Unlock slot" through Menu.ModifyMenu (Blizzard's extension point, run under
-- securecallfunction). The same tag is used by professions, the spellbook, the
-- character screen and more, so the entry is only added for bag item buttons.
-- See docs/FOREVER-UI-NOTES.md.
local _, ns = ...

local Locks = {}
ns.Locks = Locks

Locks.TAG = "MORE_CONTEXT_ACTIONS"
Locks.CONTEXT = "ButtonContext_ContainerFrameItemButton"

function Locks.Key(bag, slot)
    return bag .. ":" .. slot
end

function Locks.IsLocked(bag, slot)
    return MailworthyCharDB ~= nil and MailworthyCharDB.lockedSlots[Locks.Key(bag, slot)] ~= nil
end

local function itemAt(bag, slot)
    local get = C_Container and C_Container.GetContainerItemInfo
    if type(get) ~= "function" then return nil end
    local ok, info = pcall(get, bag, slot)
    return ok and type(info) == "table" and info or nil
end

local function describe(info)
    return info and (info.hyperlink or tostring(info.itemID)) or "empty slot"
end

function Locks.Toggle(bag, slot)
    local key, info = Locks.Key(bag, slot), itemAt(bag, slot)
    local locked = not Locks.IsLocked(bag, slot)
    MailworthyCharDB.lockedSlots[key] = locked and { itemID = info and info.itemID, at = time() } or nil
    ns.Log.Add("lock", "%s bag %d slot %d (%s)", locked and "locked" or "unlocked", bag, slot, describe(info))
    ns.Print(string.format("%s bag %d slot %d (%s).", locked and "Locked" or "Unlocked", bag, slot, describe(info)))
    return locked
end

function Locks.PrintList()
    local keys = {}
    for key in pairs(MailworthyCharDB.lockedSlots) do keys[#keys + 1] = key end
    table.sort(keys)
    ns.Print(#keys == 0 and "No locked slots." or ("Locked slots (bag:slot): " .. table.concat(keys, ", ")))
end

local function ownerName(owner)
    if type(owner) ~= "table" then return tostring(owner) end
    local ok, name = pcall(owner.GetDebugName or owner.GetName, owner)
    return ok and name and tostring(name) or "?"
end

--- The ModifyMenu callback: add our entry to bag item menus only.
function Locks.OnMenu(owner, rootDescription)
    if Locks.installing then return end -- ModifyMenu replays an earlier menu at once, with a stale owner
    local context = type(owner) == "table" and owner.buttonContext or nil
    if context ~= Locks.CONTEXT or type(owner.GetBagID) ~= "function" then
        ns.Log.Add("lock", "More menu on %s: not a bag item (context %s), no entry", ownerName(owner), tostring(context))
        return
    end
    local okBag, bag = pcall(owner.GetBagID, owner)
    local okSlot, slot = pcall(owner.GetID, owner)
    if not okBag or not okSlot or type(bag) ~= "number" or type(slot) ~= "number" then
        ns.Log.Add("lock", "More menu on %s: no bag/slot (%s, %s)", ownerName(owner), tostring(bag), tostring(slot))
        return
    end
    local label = Locks.IsLocked(bag, slot) and "Mailworthy: Unlock slot" or "Mailworthy: Lock slot"
    local ok, err = pcall(rootDescription.CreateButton, rootDescription, label, function() Locks.Toggle(bag, slot) end)
    ns.Log.Add("lock", "More menu on bag %d slot %d (%s): %s %q", bag, slot, describe(itemAt(bag, slot)),
        ok and "added" or ("CreateButton failed: " .. tostring(err)), label)
end

function Locks.Install()
    local modify = Menu and Menu.ModifyMenu
    if type(modify) ~= "function" then
        ns.Log.Add("lock", "Menu.ModifyMenu missing: no Lock slot entry")
        return false
    end
    Locks.installing = true
    local ok, err = pcall(modify, Locks.TAG, function(owner, rootDescription)
        local okMenu, errMenu = pcall(Locks.OnMenu, owner, rootDescription)
        if not okMenu then ns.Log.Add("lock", "menu callback error: %s", tostring(errMenu)) end
    end)
    Locks.installing = false
    ns.Log.Add("lock", "Menu.ModifyMenu(%q) %s", Locks.TAG, ok and "installed" or ("failed: " .. tostring(err)))
    return ok
end

ns.On("PLAYER_LOGIN", function() Locks.Install() end)
