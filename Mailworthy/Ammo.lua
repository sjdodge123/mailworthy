-- Ammo (operator, 2026-11-14: "Matching type only"): arrows and bullets (item class 6,
-- Projectile) were valued like any item, so a hunter's or warrior's ammo was listed for the bank
-- alt: white, so mailed without a price source, and a stack can clear the minimum gain. The ammo
-- the equipped ranged weapon fires (a bow or a crossbow: arrows; a gun: bullets) stays in the bags,
-- a hard keep (Valuation: "ammo"): no binding, pin, pick or Return to sender takes it. The other
-- type, and every ammo stack while no bow, crossbow or gun is equipped (a wand, a thrown weapon,
-- nothing), is valued like any item.
--
-- The ranged slot is read with GetInventoryItemID("player", INVSLOT_RANGED) (both in Forever's
-- source: EquipmentManager.lua, Constants.lua's INVSLOT_RANGED = 18) and the weapon's class with
-- GetItemInfoInstant (as Prices.ClassID reads it); each call pcall'd. The subclass numbers are
-- Classic's Enum.ItemWeaponSubclass (Bows 2, Guns 3, Crossbow 18) and Enum.ItemProjectileSubclass
-- (Arrow 2, Bullet 3), not in the source mirror (README "Beta unknowns"; /mw report says what
-- it read).
local _, ns = ...

local Ammo = {}
ns.Ammo = Ammo

Ammo.REASON = "ammo"   -- the verdict's reason (Valuation.Evaluate)
Ammo.PROJECTILE = 6    -- Enum.ItemClass.Projectile
Ammo.WEAPON = 2        -- Enum.ItemClass.Weapon
Ammo.RANGED_SLOT = 18  -- INVSLOT_RANGED
-- Weapon subclass -> the projectile subclass it fires.
Ammo.FIRES = { [2] = 2, [18] = 2, [3] = 3 }
Ammo.NAMES = { [2] = "arrows", [3] = "bullets" }

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function classOf(item)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, _, _, classID, subclassID = call(instant, item)
    return tonumber(classID), tonumber(subclassID)
end

--- Pure: the projectile subclass a weapon of this class and subclass fires, or nil.
function Ammo.Fires(classID, subclassID)
    if tonumber(classID) ~= Ammo.WEAPON then return nil end
    return Ammo.FIRES[tonumber(subclassID) or -1]
end

--- Pure: is an item of this class and subclass the ammo `fires` (Ammo.Equipped) names?
function Ammo.Matches(classID, subclassID, fires)
    return fires ~= nil and tonumber(classID) == Ammo.PROJECTILE and tonumber(subclassID) == fires
end

--- The equipped ranged weapon's item ID, or nil.
function Ammo.RangedItem()
    local id = call(rawget(_G, "GetInventoryItemID"), "player", rawget(_G, "INVSLOT_RANGED") or Ammo.RANGED_SLOT)
    return tonumber(id)
end

--- The projectile subclass the equipped ranged weapon fires (2 arrows, 3 bullets), or nil: none
--- equipped, a wand or a thrown weapon, or no answer from the client.
function Ammo.Equipped()
    local id = Ammo.RangedItem()
    if not id then return nil end
    return Ammo.Fires(classOf(id))
end

--- Is this item (link or ID) ammo the equipped ranged weapon fires? `fires` (optional): an
--- Ammo.Equipped answer already read.
function Ammo.Is(item, fires)
    if fires == nil then fires = Ammo.Equipped() end
    if fires == nil or item == nil then return false end
    local classID, subclassID = classOf(item)
    return Ammo.Matches(classID, subclassID, fires)
end

--- /mw report: what the ranged slot holds and which ammo stays.
function Ammo.ReportLines()
    local id = Ammo.RangedItem()
    local classID, subclassID
    if id then classID, subclassID = classOf(id) end
    local fires = id and Ammo.Fires(classID, subclassID) or nil
    return { string.format("ammo (kept for the ranged weapon): %s; %s",
        id and string.format("ranged slot item %d, class %s subclass %s", id, tostring(classID), tostring(subclassID))
            or "nothing in the ranged slot",
        fires and ("keeping " .. Ammo.NAMES[fires]) or "keeping none") }
end
