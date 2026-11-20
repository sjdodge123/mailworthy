-- Bag scan: every stack in the backpack, bags 1-4 and the reagent bag (bag 5)
-- becomes item facts, grouped per item link (all stacks of an item go or stay
-- together), then valued by Valuation. `/mw scan` shows the result and sends
-- nothing. Profession bags (herb, enchanting, soul, quiver...) sit in bag slots
-- 1-4, so they are covered; the keyring (-1) and the bank are not bags here.
local _, ns = ...

local Bags = {}
ns.Bags = Bags

local call = ns.Util.Call

--- The last equipped bag ID: the reagent bag (Enum.BagIndex.ReagentBag = 5 on
--- Forever, Blizzard_FrameXMLBase/Constants.lua: NUM_TOTAL_EQUIPPED_BAG_SLOTS =
--- NUM_BAG_SLOTS + NUM_REAGENTBAG_SLOTS). Bag IDs above it are bank tabs.
function Bags.LastBag()
    local total = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS)
    if total then return total end
    return (tonumber(NUM_BAG_SLOTS) or 4) + (tonumber(NUM_REAGENTBAG_SLOTS) or 1)
end

--- Is this a bag the player carries (backpack, bags 1-4, reagent bag)?
function Bags.IsBag(bag)
    return type(bag) == "number" and bag >= 0 and bag <= Bags.LastBag()
end

--- One entry per occupied bag slot.
function Bags.Slots()
    local slots = {}
    local container = C_Container or {}
    for bag = 0, Bags.LastBag() do
        for slot = 1, tonumber((call(container.GetContainerNumSlots, bag))) or 0 do
            local info = call(container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.hyperlink then
                local quest = call(container.GetContainerItemQuestInfo, bag, slot)
                slots[#slots + 1] = {
                    bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                    count = tonumber(info.stackCount) or 1, quality = tonumber(info.quality),
                    bound = info.isBound == true, inUse = info.isLocked == true, noValue = info.hasNoValue == true,
                    quest = type(quest) == "table" and quest.isQuestItem == true, icon = info.iconFileID,
                }
            end
        end
    end
    return slots
end

-- The last-moment re-check -------------------------------------------------------
-- AGENTS Safety: "Re-check each slot right before attaching it; skip anything that changed." The
-- mailer (Mailer.StillThere, before each attach) and the vendor window (Vendor.StillThere, before each
-- sale) run the same checks, in this order, each with its own words; a check that only one of them
-- needs is switched on by that caller, never off by the other.
Bags.RECHECKS = { "gone", "different", "count", "inUse", "bound", "noValue", "conjured", "ammo", "locked", "quest",
    "owed" }

--- Is this bag stack ({ bag, slot, itemID, link, count }) still exactly what was listed, and may it
--- still go? Returns true, or false and the caller's words for the first check that failed.
--- `how`:
---   read(bag, slot): the slot's GetContainerItemInfo table or nil (default Locks.ItemAt);
---   words: check -> text (Bags.RECHECKS; a check without words says its own name);
---   looseLink: the link is compared only when both are known (the item ID always is);
---   bound: refuse a soulbound item (mail: never; a vendor buys a vendor-pinned one);
---   noValue: refuse what no vendor buys;
---   owed(itemID): true when another player mailed it here and it may go back to them.
--- Always: gone, a different item, a changed count, in use, conjured, the equipped ranged weapon's
--- ammo, locked, an active quest's need.
function Bags.StillThere(stack, how)
    how = how or {}
    local words = how.words or {}
    local function no(check) return false, words[check] or check end
    local info = (how.read or ns.Locks.ItemAt)(stack.bag, stack.slot)
    if type(info) ~= "table" or info.itemID == nil then return no("gone") end
    if info.itemID ~= stack.itemID then return no("different") end
    -- The whole link: a random-suffix variant has the item ID but not the item listed (Codex review).
    if info.hyperlink ~= stack.link and not (how.looseLink and (info.hyperlink == nil or stack.link == nil)) then
        return no("different")
    end
    if (tonumber(info.stackCount) or 1) ~= stack.count then return no("count") end
    if info.isLocked then return no("inUse") end
    if how.bound and info.isBound then return no("bound") end
    if how.noValue and info.hasNoValue then return no("noValue") end
    local link = info.hyperlink or stack.link
    if ns.Conjured.Is(info.itemID) then return no("conjured") end
    -- A bow, crossbow or gun equipped since the list was made: its ammo stays (Ammo.lua).
    if ns.Ammo.Is(link) then return no("ammo") end
    if ns.Locks.IsItemLocked(info.itemID) then return no("locked") end
    -- A quest accepted since the list was made (Codex review, 2026-11-08): what it asks for stays.
    if ns.Quests.For(link) then return no("quest") end
    if how.owed and how.owed(info.itemID) then return no("owed") end
    return true
end

Bags.PROJECTILE = 6 -- item class of arrows and bullets (Enum.ItemClass.Projectile)
local classByID = {} -- itemID -> item class, read once (GetItemInfoInstant needs no cache)

--- Pure: one string for what is in the bags (`slots`: Bags.Slots' shape, or GetContainerItemInfo's
--- fields), so a bag update that changes nothing the tags read can be told apart. The stack size of
--- ammo is left out: every shot of a bow, gun or crossbow takes one, and each fired BAG_UPDATE_DELAYED,
--- which re-valued the bags and redrew every bag addon button (a CurseForge report, 2026-11-14:
--- "stutter consistently everytime I am shooting a gun", Mailworthy and Baganator only).
--- `classOf(itemID, link)`: the item's class.
function Bags.FingerprintOf(slots, classOf)
    local parts = {}
    for _, s in ipairs(slots) do
        local count = classOf(s.itemID, s.link) == Bags.PROJECTILE and "ammo" or tostring(s.count)
        parts[#parts + 1] = table.concat({ s.bag, s.slot, tostring(s.link), count, tostring(s.inUse) }, ":")
    end
    return table.concat(parts, "|")
end

local function classOf(itemID, link)
    if itemID == nil then return nil end
    local known = classByID[itemID]
    if known ~= nil then return known or nil end
    local class = ns.Prices.ClassID(link or itemID)
    classByID[itemID] = class or false
    return class
end

--- What is in the bags right now, as Bags.FingerprintOf has it. Lighter than Bags.Slots: no
--- quest lookup per slot.
function Bags.Fingerprint()
    local slots = {}
    local container = C_Container or {}
    for bag = 0, Bags.LastBag() do
        for slot = 1, tonumber((call(container.GetContainerNumSlots, bag))) or 0 do
            local info = call(container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.hyperlink then
                slots[#slots + 1] = { bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                    count = tonumber(info.stackCount) or 1, inUse = info.isLocked == true }
            end
        end
    end
    return Bags.FingerprintOf(slots, classOf)
end

--- Stacks of the same link (and same bound / in-use state) become one item.
function Bags.Group(slots)
    local items, byKey = {}, {}
    for _, s in ipairs(slots) do
        local key = table.concat({ s.link, tostring(s.bound), tostring(s.inUse) }, "|")
        local item = byKey[key]
        if not item then
            item = { link = s.link, itemID = s.itemID, quality = s.quality, bound = s.bound, inUse = s.inUse,
                quest = s.quest, noValue = s.noValue, icon = s.icon, count = 0, stacks = 0, slots = {} }
            byKey[key] = item
            items[#items + 1] = item
        end
        item.count = item.count + s.count
        item.stacks = item.stacks + 1
        item.quest = item.quest or s.quest
        item.slots[#item.slots + 1] = { bag = s.bag, slot = s.slot, count = s.count }
    end
    return items
end

-- Scan inputs ---------------------------------------------------------------------------
-- One signal for "what a scan reads changed" (A9): a lock, a pin or the pin mode, a binding added,
-- removed or changed, a row pick or a Skip once, the bank alt skipped, Return to sender, an active
-- quest's needs, the recipes asked again, a setting or the bank alt. Whatever caches a scan listens
-- (the bag tags, BankAlt; Trip), so no input can leave one stale until the next bag update. Not the
-- Mailworthy window: it refreshes itself (MailWindow). Fired from the module that owns each input;
-- Comms (a peer's skills) and SettingsUI still push to BankAlt directly.
local inputsChanged = ns.Util.Signal("scan inputs")

--- Listen: fn(why, lazy). `why`: what changed ("lock", "routes", ...); `lazy`: only mark a cached
--- scan stale (read again at its next use), don't redraw now.
Bags.OnInputsChanged = inputsChanged.Add

--- Say that a scan's inputs changed (see above). `lazy`: see Bags.OnInputsChanged.
function Bags.InputsChanged(why, lazy)
    inputsChanged.Fire(why, lazy == true)
end

-- Locks and pins (and the pin mode) load before this file and have their own lists: passed on. At
-- PLAYER_LOGIN, after the lock glow's own listener (Border), as BankAlt listened before.
ns.On("PLAYER_LOGIN", function()
    ns.Locks.OnChanged(function() Bags.InputsChanged("lock") end)
    ns.Pins.OnChanged(function() Bags.InputsChanged("pin") end)
end)

-- The bank alt is optional (operator, 2026-11-08: "dont require a bank alt to use mailworthy"),
-- and the player can skip it for one mailbox visit ("Skip once for their bank alt sends too"):
-- then what would have gone to the bank alt stays in the bags, listed under Staying with the
-- route it would have had, and only bindings mail.
local bankAltSkipped = false

function Bags.SkipBankAlt(on)
    bankAltSkipped = on == true
    ns.Log.Add("scan", "bank alt %s this visit", bankAltSkipped and "skipped" or "back")
    Bags.InputsChanged("bank alt skip")
end
function Bags.BankAltSkipped() return bankAltSkipped end

--- Why the bank alt's share stays in the bags at this mailbox, or nil when it goes. On the bank
--- alt itself (operator, 2026-11-08: its window mails too) that share is what it sells here.
function Bags.HoldReason()
    if not ns.Config.BankAlt() then return "no bank alt" end
    if ns.Config.IsBankAltHere() then return "this is your bank alt" end
    if bankAltSkipped then return "bank alt skipped" end
    return nil
end

--- Fill in what a scan reads that the saved settings don't hold, each only when it isn't set yet (a
--- caller may pass its own): the launch day, this character's professions (with what the profession
--- window last showed still in use past the tier table: TierCheck), the tier switch, and, with an
--- auction price source (Auctionator, else TradeSkillMaster: Prices.Source), the materials' auction unit
--- prices (the leather conversions: Tiers.WorthConverting). Returns `settings`. The first step of
--- Bags.Evaluate; /mw report and Bags.ProfessionKeep need only this.
function Bags.PrepareSettings(settings)
    if settings.serverDay == nil then settings.serverDay = ns.Config.ServerDay() end
    if settings.professions == nil then settings.professions = ns.Characters.Professions() end
    if settings.tiers == nil then settings.tiers = ns.Tiers.On() end
    -- What the profession window last showed still in use past the table (TierCheck): kept.
    if settings.tiers then ns.TierCheck.Annotate(settings.professions) end
    if settings.priceOf == nil and ns.Prices.Source() then settings.priceOf = ns.Prices.MaterialPrice end
    return settings
end

--- The crafting profession of this character that "Keep my professions' materials" keeps this item
--- for, or its class's own skill (a rogue's lockbox: "Lockpicking"; ClassSkills.lua), or nil
--- (PinWarning: a pin to the bank alt beats it).
function Bags.ProfessionKeep(link, itemID)
    local s = Bags.PrepareSettings(ns.Config.Values())
    local item = { link = link, itemID = itemID }
    item.classID, item.subclassID = ns.Prices.ClassID(link)
    local profession = ns.Valuation.ProfessionKeep(item, s)
    if profession or not s.keepProfessionMats then return profession end
    local skill = ns.ClassSkills.SKILLS[ns.ClassSkills.Of(itemID) or ""]
    return skill and skill.class == ns.Classes.Mine() and skill.name or nil
end

--- The one settings builder for a scan (Bags.Evaluate), and for what reads the same settings (the
--- window, /mw scan, /mw report, the bag tags, Trip): the saved ones (Config.Values) and, while Return
--- to sender is on (Returns.lua), what goes back to whom. `opts` (optional):
---   forTags: the bag tags' scan (BankAlt.Settings): the send switches don't change a tag
---     (Bags.ApplySendSwitches), and the bank alt's share isn't held: a tag says what the item is for;
---   noPostage: nothing is mailed from here (the bank alt's tags): postage 0.
--- Without forTags, `hold` says why the bank alt's share stays in the bags (Bags.HoldReason), or nil.
function Bags.Settings(opts)
    opts = opts or {}
    local s = ns.Config.Values()
    if opts.noPostage then s.postage = 0 end
    if not opts.forTags then s.hold = Bags.HoldReason() end
    if ns.Returns.On() then s.returns = ns.Returns.Current() end
    if opts.forTags then s.forTags = true end
    return s
end

--- The window's settings (and /mw scan's): Bags.Settings().
function Bags.CurrentSettings()
    return Bags.Settings()
end

--- A copy of a bag item with only `slots` of it (Return to sender sends some stacks back and
--- values the rest as usual); `result` when already known.
function Bags.Part(item, slots, result)
    local part = {}
    for k, v in pairs(item) do part[k] = v end
    part.slots, part.count, part.stacks, part.result = {}, 0, #slots, result
    for i, s in ipairs(slots) do
        part.slots[i] = s
        part.count = part.count + s.count
    end
    return part
end

--- The send switches (settings: Send Auction / Disenchant / Bank / Vendor; Valuation.SEND): what
--- Send takes of the bank alt's share, by the item's verdict (Valuation.Verdict). A switch that is
--- off keeps its items in the bags (result.held says why, result.route what it would have been,
--- like a skipped bank alt); the Vendor switch, off by default, mails what a vendor pays more for
--- too (route Valuation.VENDOR), so the bank alt can sell it.
--- Never for a tag (`settings.forTags`: BankAlt.Settings), a binding's or a return's item
--- (result.to), a share that already stays (no bank alt, skipped), a hard keep (none has a
--- verdict) or a soulbound item; and the Vendor switch needs a price source: without one only
--- white items and staples go (AGENTS safety), so junk stays.
--- Never for a pinned item either way (operator, 2026-11-13: a pin "needs to be honored"): a switch
--- that is off doesn't hold a bank pin, and Send: V never mails a vendor pin. Send: V mails only what
--- has a current auction price a vendor beats ("not worth it"): never grey junk, an item with no
--- auction price or a failed price call (AGENTS safety: "Grey junk stays, an item whose price call
--- failed stays"; Codex/operator review of feat/craft-mats-to-alt, 2026-11-13).
function Bags.ApplySendSwitches(item, settings, priced)
    local r = item.result
    if settings.forTags or settings.hold or type(r) ~= "table" or r.to or r.held or r.pinned then return end
    local tag = ns.Valuation.Verdict(item, ns.Config.BanksHere())
    local key = tag and ns.Valuation.SEND[tag]
    if not key then return end
    if r.action == "mail" and settings[key] == false then
        r.action, r.held = "keep", "sending " .. ns.Valuation.SEND_LABEL[tag] .. " items is off"
    elseif tag == "v" and r.action == "keep" and settings.sendVendor == true and priced and not item.bound
        and ns.Valuation.Is(r, ns.Valuation.K.notWorth) and (item.quality or 0) >= 1 and not r.failed then
        r.action, r.route, r.keptFor = "mail", ns.Valuation.VENDOR, r.reason
        r.reason = "vendor item (sending Vendor items is on)"
        r.postage = r.postage or (settings.postage or 0) * (item.stacks or 1)
    end
end

--- The send switches in words, for /mw scan and /mw report: "Auction on, Disenchant on, Bank on, Vendor off".
function Bags.SendText(settings)
    local parts = {}
    for _, tag in ipairs(ns.Valuation.SEND_ORDER) do
        parts[#parts + 1] = ns.Valuation.SEND_LABEL[tag] .. " " .. (settings[ns.Valuation.SEND[tag]] == true and "on" or "off")
    end
    return table.concat(parts, ", ")
end

-- The scan, step by step ------------------------------------------------------------
-- Bags.Evaluate: prepare the settings (Bags.PrepareSettings), read once what every item needs
-- (scanContext), then per item group (a lockbox's locked and unlocked stacks apart: lockStates): its
-- facts (gatherFacts), where it goes (decide, then holdShare and
-- Bags.ApplySendSwitches), Return to sender's share (splitReturns); each part filed and counted
-- (tally); then the mail counts (countMails) and the lists' order (sortLists).

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

--- What a scan reads once, not per item: the price source (priced: without one only white items and
--- staples go, AGENTS.md Safety "without Auctionator"), the bindings in force, an enchanter's
--- disenchant-here cap, whether a binding is a class's (each item's class line is read then) or has its
--- Gear switch on (each unpriced piece's disenchant value is read then), and the ranged weapon's ammo.
local function scanContext(settings)
    local source = ns.Prices.Source()
    local routes = settings.routes or ns.Routes.Active()
    -- An enchanter's disenchant-here cap (Valuation.DisenchantsHere): an Enchanting binding of the player's
    -- own that names this character sets it, else the bindings' default.
    if settings.deHereCap == nil then
        for _, r in ipairs(routes) do
            if tonumber(r.profession) == ns.Valuation.ENCHANTING and r.cap and ns.Routes.IsMe(r.to) then
                settings.deHereCap = r.cap
            end
        end
    end
    local ctx = { settings = settings, source = source, priced = source ~= nil, routes = routes,
        classRoutes = false, gearRoutes = false }
    for _, r in ipairs(routes) do
        -- Class bindings (Routes, Classes.lua) need each item's class line: read only when there's one.
        ctx.classRoutes = ctx.classRoutes or r.class ~= nil
        -- An Enchanting binding with its Gear switch on asks each piece's disenchant value. Without a
        -- price source there is no price table to carry it, but a disenchant addon may still have one
        -- (Siz DisenchantValue): read it then, for gear only (Codex review, 2026-11-11).
        ctx.gearRoutes = ctx.gearRoutes or r.gear == ns.Routes.GEAR_DE
    end
    ctx.mine = ns.Classes.Mine()
    -- Class skills (ClassSkills.lua): a rogue's lockboxes and a mage's Comprehension scrolls. Each
    -- item's tooltip is read for them only where it matters: on a character of that class (they stay,
    -- "Keep my professions' materials") or with a binding for that class (it takes them).
    for _, id in ipairs(ns.ClassSkills.ORDER) do
        local class = ns.ClassSkills.SKILLS[id].class
        local wanted = class == ctx.mine and settings.keepProfessionMats
        for _, r in ipairs(routes) do wanted = wanted or r.class == class end
        if wanted then
            ctx.skills = ctx.skills or {}
            ctx.skills[id] = true
        end
    end
    -- The ammo the equipped ranged weapon fires stays (Ammo.lua): the slot is read once per scan.
    ctx.fires = ns.Ammo.Equipped()
    return ctx
end

--- An item's facts, each from its own module, for Valuation and the bindings: lock, pin, class line
--- (class bindings only), a class skill's item (ClassSkills), an active quest's need, conjured, item class, the equipped weapon's ammo, a
--- recipe this character knows, vendor and auction price, and an unpriced piece's disenchant value (a
--- Gear switch only).
local function gatherFacts(item, ctx)
    item.locked = ns.Locks.IsItemLocked(item.itemID)
    item.pin = ns.Pins.Effective(item.itemID)
    if ctx.classRoutes then item.classes, item.myClass = ns.Classes.Of(item.itemID), ctx.mine end
    -- A lockbox or a Comprehension scroll (ClassSkills.lua), and whether this character's own class levels on it.
    -- Not a lockbox already unlocked (item.opened, lockStates below).
    item.classSkill, item.ownSkill = nil, nil
    local skill = ctx.skills and not item.opened and ns.ClassSkills.Of(item.itemID) or nil
    if skill and ctx.skills[skill] then
        item.classSkill = skill
        if ns.ClassSkills.SKILLS[skill].class == ctx.mine then item.ownSkill = ns.ClassSkills.SKILLS[skill].name end
    end
    item.questFor = ns.Quests.For(item.link)
    item.conjured = ns.Conjured.Is(item.itemID)
    item.classID, item.subclassID = ns.Prices.ClassID(item.link)
    item.ammo = ns.Ammo.Matches(item.classID, item.subclassID, ctx.fires)
    -- A recipe this character already knows (Recipes.lua): no binding naming this character takes it.
    item.known = ns.Valuation.RecipeProfession(item) and ns.Recipes.Known(item.itemID) or nil
    item.vendor = item.noValue and 0 or ns.Prices.Vendor(item.link)
    item.price = ctx.priced and ns.Prices.Lookup(item.link) or nil
    item.de = nil
    if ctx.gearRoutes and item.price == nil and ns.Routes.IsGear(item) then
        item.de = ns.Prices.DisenchantValueFor(item.link)
    end
end

--- A lockbox's stacks apart by lock state (ClassSkills.Split), where Lockpicking matters to this scan
--- (ctx.skills: on a rogue, or with a binding for one; nothing is read otherwise): the locked ones, and
--- those already unlocked (`opened`: no lockbox for a binding or a rogue's keep, the normal rule).
--- Any other item as it is. Returns the item's parts.
local function lockStates(item, ctx)
    local lockpicking = ns.ClassSkills.LOCKPICKING
    if not (ctx.skills and ctx.skills[lockpicking] and ns.ClassSkills.Of(item.itemID) == lockpicking) then
        return { item }
    end
    local locked, opened = ns.ClassSkills.Split(item)
    if #opened == 0 then return { item } end
    if #locked == 0 then
        item.opened = true
        return { item }
    end
    local rest = Bags.Part(item, opened)
    rest.opened = true
    return { Bags.Part(item, locked), rest }
end

--- Where an item goes, from its facts: its own verdict (Valuation.Evaluate, a row's "Me"), a binding's
--- (Routes.Divert: me first, then friends, then the guild), then the row's pick for this mailbox visit
--- (Routes.Pick). Returns { own, result, choices, pickState }. `own` is never written to: what a binding
--- that didn't take the item says (capped, pastFor, gearBeaten) and a pick go on `result`, a table of
--- its own, which the later steps (holdShare, Bags.ApplySendSwitches) may change.
local function decide(item, ctx)
    local settings, routes, price = ctx.settings, ctx.routes, item.price
    local own = ns.Valuation.Evaluate(item, price, settings)
    local diverted, capped, past, beaten = ns.Routes.Divert(item, own, price, settings, routes)
    local result = diverted
    if not diverted then
        result = copy(own)
        result.capped, result.pastFor, result.gearBeaten = capped, past, beaten
    end
    -- A binding naming this character keeps it here: that is its own verdict now, and no pick moves
    -- it (Routes.Divertible; Codex review, 2026-11-14: "Me" mailed it to the bank alt).
    local moved = diverted ~= nil and not diverted.forMe
    if diverted and diverted.forMe then own = diverted end
    -- The row's button (Routes.Pick, this mailbox visit): where the player sent it instead.
    local choices = ns.Routes.Choices(item, own, price, settings, routes)
    local pickState = result.key or ns.Routes.MINE
    local pick = #choices > 0 and ns.Routes.Picked(item.link) or nil
    if pick == ns.Routes.MINE and moved then
        result, pickState = copy(own), pick
        result.picked = true
    elseif pick and pick ~= ns.Routes.MINE and pick ~= result.key then
        for _, r in ipairs(choices) do
            if r.key == pick then
                result = ns.Routes.Force(item, r, (ns.Routes.Units(item, price, settings)), settings)
                result.picked, pickState = true, pick
            end
        end
    end
    return { own = own, result = result, choices = choices, pickState = pickState }
end

--- No bank alt, or skipped this visit (settings.hold): its share stays (bindings and returns still go).
local function holdShare(item, settings)
    local r = item.result
    if settings.hold and r.action == "mail" and not r.to then r.action, r.held = "keep", settings.hold end
end

--- Value one item: its facts, its verdict, the bank alt's share held, the send switches.
local function value(item, ctx)
    gatherFacts(item, ctx)
    local d = decide(item, ctx)
    item.result, item.choices, item.pickState = d.result, d.choices, d.pickState
    holdShare(item, ctx.settings)
    Bags.ApplySendSwitches(item, ctx.settings, ctx.priced)
end

--- Return to sender: what another player mailed this character goes back to them (Returns.Split over
--- `owed`, this item's list, used up across its bag groups), shown as any return; the rest of a pinned
--- item goes to the bank alt (operator, 2026-11-13: "return to sender should win"). Never a hard keep, an
--- unmailable item or a soulbound one (vendor-pinned or not: its keep reason is the pin's). Returns the
--- parts going back (Bags.Part, each with its return verdict and no row pick: Return to sender wins)
--- and the slots left, or nil when nothing goes back.
local function splitReturns(item, owed, settings)
    local r = item.result
    if not owed or ns.Valuation.Unmailable(r) or ns.Valuation.HardKeep(r) or item.bound then return nil end
    local split, rest = ns.Returns.Split(item.slots, owed)
    if #split == 0 then return nil end
    local parts = {}
    for i, p in ipairs(split) do
        parts[i] = Bags.Part(item, p.slots, ns.Returns.Result(p.to, #p.slots, settings))
        parts[i].choices, parts[i].pickState = {}, nil
    end
    return parts, rest
end

--- What is owed back, per item ID: a copy of `returns`' list (Returns.Owed) made once per scan, which
--- Returns.Split uses up across the item's bag groups (the settings' own list stays as it was).
local function owedReader(returns)
    local left = {}
    return function(itemID)
        local list = returns and returns[itemID]
        if not list then return nil end
        if not left[itemID] then
            local mine = {}
            for i, o in ipairs(list) do mine[i] = { to = o.to, count = o.count, at = o.at } end
            left[itemID] = mine
        end
        return left[itemID]
    end
end

local function newResult(ctx)
    return { settings = ctx.settings, priced = ctx.priced, source = ctx.source, routes = ctx.routes, mail = {}, keep = {},
        unmailable = {}, totals = { items = 0, stacks = 0, mails = 0, gain = 0, postage = 0, routed = 0, unpriced = 0,
            recipients = {}, byRecipient = {} } }
end

--- File a valued item under Mailing, Staying or Not mailable; count a mailed one in the totals (items,
--- stacks, postage, the bank alt's gain, stacks to bindings and returns, unpriced) and per recipient
--- (`stacksTo`: stacks per mail run, for countMails).
local function tally(result, item, stacksTo)
    if item.result.action == "mail" then
        table.insert(result.mail, item)
        local t = result.totals
        t.items, t.stacks = t.items + item.count, t.stacks + item.stacks
        t.postage = t.postage + item.result.postage
        local to = item.result.to or "" -- "" = the bank alt
        if item.result.to then t.routed = t.routed + item.stacks else t.gain = t.gain + (item.result.gain or 0) end
        -- To the bank alt with no gain known (no auction price yet): the total says so (Codex review).
        if result.priced and not item.result.to and item.result.gain == nil then t.unpriced = t.unpriced + 1 end
        if not stacksTo[to] then
            stacksTo[to] = {}
            t.recipients[#t.recipients + 1] = to
            t.byRecipient[to] = { items = 0, stacks = 0, mails = 0, what = {}, crafter = item.result.crafter }
        end
        -- Mails per recipient as Mailer.Plan makes them: one run per binding (or return) to them.
        local group = item.result.to and tostring(item.result.what) or ""
        stacksTo[to][group] = (stacksTo[to][group] or 0) + item.stacks
        local each = t.byRecipient[to]
        each.items, each.stacks = each.items + item.count, each.stacks + item.stacks
        if item.result.what and not each.what[item.result.what] then
            each.what[item.result.what] = true
            each.what[#each.what + 1] = item.result.what
        end
    elseif ns.Valuation.Unmailable(item.result) then
        table.insert(result.unmailable, item)
    else
        table.insert(result.keep, item)
    end
end

--- The mails each recipient gets: each run's stacks in mails of Mailer.PER_MAIL (Mailer.Plan's split).
local function countMails(result, stacksTo)
    for to, groups in pairs(stacksTo) do
        for _, n in pairs(groups) do
            local mails = math.ceil(n / ns.Mailer.PER_MAIL)
            result.totals.mails = result.totals.mails + mails
            result.totals.byRecipient[to].mails = result.totals.byRecipient[to].mails + mails
        end
    end
end

--- The bank alt first among the recipients; the Mailing list in recipient groups, then by gain; the
--- Staying list locked first (operator, 2026-11-07: "I click them, they disappear off the menu and then
--- there's not a quick way to see what's been locked": one press on the row unlocks), then by gain.
local function sortLists(result)
    for i, to in ipairs(result.totals.recipients) do -- the bank alt first
        if to == "" and i > 1 then
            table.remove(result.totals.recipients, i)
            table.insert(result.totals.recipients, 1, "")
        end
    end
    local function byGain(a, b)
        local ga, gb = a.result.gain or -math.huge, b.result.gain or -math.huge
        if ga ~= gb then return ga > gb end
        return a.link < b.link
    end
    local order = {}
    for i, to in ipairs(result.totals.recipients) do order[to] = i end
    table.sort(result.mail, function(a, b)
        local oa, ob = order[a.result.to or ""] or 0, order[b.result.to or ""] or 0
        if oa ~= ob then return oa < ob end
        return byGain(a, b)
    end)
    local locked = ns.Valuation.K.locked
    table.sort(result.keep, function(a, b)
        local la, lb = ns.Valuation.Is(a.result, locked), ns.Valuation.Is(b.result, locked)
        if la ~= lb then return la end
        return byGain(a, b)
    end)
    result.locked = 0
    for _, item in ipairs(result.keep) do
        if ns.Valuation.Is(item.result, locked) then result.locked = result.locked + 1 end
    end
end

--- Scan and value the bags. `settings` (default Bags.CurrentSettings; filled in by
--- Bags.PrepareSettings): `hold` (Bags.HoldReason): the bank alt's share is kept, with result.held saying
--- why and result.route what it would have been; `returns` (Returns.Owed, Return to sender on): stacks
--- another character mailed this one go back to them (route "return"), whatever the rule says, except
--- hard keeps. Returns { settings, priced, source, routes, mail = {items}, keep = {items},
--- unmailable = {items} (soulbound / quest / conjured: never listed in the window), totals, locked }.
function Bags.Evaluate(settings)
    settings = Bags.PrepareSettings(settings or Bags.CurrentSettings())
    local ctx = scanContext(settings)
    local result, stacksTo = newResult(ctx), {}
    local owedFor = owedReader(settings.returns)
    for _, group in ipairs(Bags.Group(Bags.Slots())) do
        for _, item in ipairs(lockStates(group, ctx)) do
            value(item, ctx)
            local parts, rest = splitReturns(item, owedFor(item.itemID), settings)
            if not parts then
                tally(result, item, stacksTo)
            else
                for _, back in ipairs(parts) do tally(result, back, stacksTo) end
                if #rest > 0 then -- what wasn't mailed to this character (or won't split): the usual rule
                    local left = Bags.Part(item, rest)
                    value(left, ctx)
                    tally(result, left, stacksTo)
                end
            end
        end
    end
    countMails(result, stacksTo)
    sortLists(result)
    return result
end

-- Report ---------------------------------------------------------------------

local money = function(c) return ns.Valuation.Money(c) end

local ROUTE = { ah = "AH", de = "DE", common = "COMMON", bank = "BANK", friend = "FRIEND", ["return"] = "RETURN",
    noprice = "NO PRICE", vendor = "VENDOR" }

local function itemName(item)
    local name = item.link:match("%[(.-)%]") or item.link
    return string.format("[%s] x%d%s", name, item.count, item.stacks > 1 and (" (" .. item.stacks .. " stacks)") or "")
end

--- "5s", or "5s (6s 52c at launch day 90)" once the server's age has grown it.
function Bags.MinGainText(settings)
    local effective = ns.Valuation.MinGain(settings)
    if effective == settings.minGain then return money(settings.minGain) end
    return string.format("%s (%s at launch day %d)", money(settings.minGain), money(effective), settings.serverDay)
end

-- The numbers behind a verdict, so it can be checked by hand.
local function workings(item, settings)
    local r, p, parts = item.result, item.price, {}
    if item.vendor ~= nil then
        parts[#parts + 1] = "vendor " .. money(item.vendor) .. " each = " .. money(r.vendor or item.vendor * item.count)
    end
    if p and p.ah then
        local text = "AH " .. money(r.ahUnit or p.ah) .. " each"
        if (r.scans or 1) > 1 then
            text = text .. string.format(" (%d-day median; last scan %s)", r.scans, money(p.ah))
        elseif r.median then
            text = text .. string.format(" (last scan; %d-day median %s)", r.medianDays or 0, money(r.median))
        end
        if p.age then text = text .. ", " .. p.age .. " days old" end
        if p.exact == false then text = text .. " (not exact, -10%)" end
        -- TSM's price beat Auctionator's for this item (Prices.Lookup: the fresher one, 2026-11-17).
        if type(p.over) == "table" then
            text = text .. " (TSM; Auctionator: " .. (p.over.ah == nil and "no price"
                or tonumber(p.over.age) and (p.over.age .. " days old") or "older") .. ")"
        end
        parts[#parts + 1] = text
    end
    local L = r.liquidity
    if L and (L.available or L.trend) then
        local text = "market: " .. (L.available and (L.available .. " listed") or "listed ?")
        if L.trend then text = text .. string.format(", %+d%% vs last week", math.floor(L.trend * 100 + 0.5)) end
        if L.glut then text = text .. " (glut: floor price, deposit counted lost)" end
        parts[#parts + 1] = text
    end
    if r.ahNet then
        local deposit = money(r.deposit)
        if r.depositCounted ~= r.deposit then deposit = deposit .. " counted " .. money(r.depositCounted) end
        parts[#parts + 1] = string.format("AH net %s (cut %d%%, deposit %s, postage %s)", money(r.ahNet),
            math.floor(settings.cut * 100 + 0.5), deposit, money(r.postage))
    end
    if p and p.de then parts[#parts + 1] = "disenchant " .. money(p.de) .. " each (" .. tostring(p.deSource or "?") .. ")" end
    if r.deNet then parts[#parts + 1] = "DE net " .. money(r.deNet) end
    if r.gain then parts[#parts + 1] = string.format("gain %s (needs %s)", money(r.gain), money(r.threshold)) end
    if r.to then
        parts[#parts + 1] = "binding" .. (r.crafter and " (their character with the profession)" or "")
            .. (r.ahUnit and (", under the cap at " .. money(r.ahUnit) .. " each") or "")
    elseif r.capped then
        parts[#parts + 1] = string.format("not to %s: at or above the %s cap", tostring(r.capped.to),
            money(r.capped.cap or 0))
    end
    if r.gearBeaten then
        parts[#parts + 1] = string.format("not to %s: DE net %s is no more than %s %s", tostring(r.gearBeaten.to),
            money(r.gearBeaten.de), r.gearBeaten.by == "auction" and "the AH net" or "the vendor price",
            money(r.gearBeaten.best))
    end
    if r.pastFor then
        parts[#parts + 1] = string.format("not to %s: their %s (%s) is past it", tostring(r.pastFor.to),
            tostring(ns.Routes.ProfessionName(r.pastFor.profession)), tostring(r.pastFor.skill))
    end
    if r.outgrown then
        parts[#parts + 1] = string.format("your %s (%s) is past it", r.outgrown.name, tostring(r.outgrown.skill))
    end
    if r.untilSkill then parts[#parts + 1] = "kept until skill " .. r.untilSkill end
    if r.window then
        parts[#parts + 1] = string.format("past the table, but your profession window still shows %s (%s)%s",
            tostring(r.window.recipe), ns.TierCheck.COLORS[r.window.difficulty] or "?",
            r.window.via and (" via " .. r.window.via) or "")
    end
    if r.convert then
        parts[#parts + 1] = string.format("past its recipes; %d make a %s, worth more than selling them",
            r.convert.count, r.convert.name)
    end
    return table.concat(parts, "; ")
end

--- Pure: "First Aid 80, Tailoring 130" (each crafting profession with its skill, when known).
function Bags.CraftingText(professions)
    local names = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine or p)
        local known = ns.Valuation.PROFESSION_MATS[id or -1]
        if known then
            local rank = type(p) == "table" and tonumber(p.rank) or nil
            names[#names + 1] = known.name .. (rank and (" " .. rank) or "")
        end
    end
    return table.concat(names, ", ")
end

--- Pure: "First Aid 80 is past Linen Cloth; Tailoring 180 is past Linen Cloth, Wool Cloth" or "".
function Bags.OutgrownText(professions)
    local parts = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine)
        local known = ns.Valuation.PROFESSION_MATS[id or -1]
        local past = known and ns.Tiers.PastText(id, p.rank, nil, p.stillUsed) or ""
        if past ~= "" then parts[#parts + 1] = string.format("%s %d is past %s", known.name, p.rank, past) end
    end
    return table.concat(parts, "; ")
end

--- "kept for Tailoring 130, Enchanting 90" / "kept (no crafting profession here)" / "mailed".
function Bags.ProfessionMatsText(settings)
    if not settings.keepProfessionMats then return "mailed" end
    local crafting = Bags.CraftingText(settings.professions)
    local kept = settings.matsToBankAlt and "banked on your bank alt for " or "kept for "
    local text = crafting ~= "" and (kept .. crafting) or "kept (no crafting profession here)"
    local past = settings.tiers ~= false and Bags.OutgrownText(settings.professions) or ""
    if past ~= "" then text = text .. "; " .. past .. " (mailed)" end
    local names = ns.Valuation.CraftingProfessions(settings.professions)
    if settings.sellGathered and #names > 0 then
        local gathered = {}
        for _, p in ipairs(ns.Valuation.GatheringProfessions(settings.professions)) do gathered[#gathered + 1] = p.name end
        text = text .. (#gathered > 0 and ("; what " .. table.concat(gathered, ", ") .. " gathers is mailed")
            or "; sell what I gather: on (no gathering profession here)")
    end
    return text
end

--- The report's "settings:" line, for /mw scan (`mailing`: the deposit, the cut, postage and the
--- launch day a scan's verdicts used) and /mw report (`extra`: its own switches, before the profession
--- materials). `s`: a scan's settings (professions read: Bags.Evaluate fills them).
function Bags.SettingsLine(s, opts)
    opts = opts or {}
    local hours = ns.Valuation.DURATION_HOURS[s.duration]
    local parts = { opts.mailing and string.format("%dh listing (deposit x%d)", hours, ns.Valuation.DEPOSIT_MULTIPLIER[s.duration])
        or string.format("%dh listing", hours) }
    if opts.mailing then
        parts[#parts + 1] = string.format("AH cut %d%%", math.floor(s.cut * 100 + 0.5))
        parts[#parts + 1] = "postage " .. money(s.postage) .. " per stack"
    end
    parts[#parts + 1] = string.format("min gain %s and %d%%", Bags.MinGainText(s), math.floor(s.minGainPct * 100 + 0.5))
    parts[#parts + 1] = "disenchant " .. (s.disenchant and "on" or "off")
    parts[#parts + 1] = string.format("max price age %d days", s.maxAgeDays)
    if opts.mailing then parts[#parts + 1] = "launch day " .. tostring(s.serverDay) end
    for _, e in ipairs(opts.extra or {}) do parts[#parts + 1] = e end
    parts[#parts + 1] = "profession materials " .. Bags.ProfessionMatsText(s)
    return "settings: " .. table.concat(parts, ", ")
end

function Bags.Report(result)
    local s, t = result.settings, result.totals
    local lines = {
        string.format("Mailworthy %s scan at %s (sends nothing)", ns.VERSION, date("%Y-%m-%d %H:%M")),
        "bank alt: " .. tostring(ns.Config.BankAlt() or "none (its share stays in the bags; /mw settings)")
            .. (bankAltSkipped and ", skipped this visit" or "")
            .. (s.returns and "; return to sender: on (what other characters mailed you goes back)" or ""),
        "prices: " .. (result.priced and (ns.Prices.SOURCE_NAME[result.source] or "Auctionator")
            or "none (no Auctionator or TradeSkillMaster: mailing common items)")
            .. (result.priced and " (no auction price yet: to the bank alt)" or ""),
        Bags.SettingsLine(s, { mailing = true }),
        "send: " .. Bags.SendText(s),
        string.format("total: %d items (%d stacks) in %d mail(s), %s more than vendoring, postage %s%s",
            t.items, t.stacks, t.mails, money(t.gain), money(t.postage),
            t.routed > 0 and string.format(" (%d stacks to friends)", t.routed) or ""),
    }
    for _, r in ipairs(result.routes or {}) do
        local to, crafter = ns.Routes.Recipient(r)
        local gear = r.gear and ns.Routes.GearText(r)
        lines[#lines + 1] = string.format("binding: %s (%s%s%s)", ns.Routes.Describe(r), ns.Routes.CapText(r),
            gear and (", " .. gear:lower()) or "", crafter and (", delivered to their crafter " .. to) or "")
    end
    for _, item in ipairs(result.mail) do
        local w = workings(item, s)
        lines[#lines + 1] = string.format("MAIL %s %s: %s%s", ROUTE[item.result.route] or "?", itemName(item),
            item.result.reason, w ~= "" and (" - " .. w) or "")
    end
    for _, item in ipairs(result.keep) do
        local w = workings(item, s)
        local r = item.result
        local why = r.held and string.format("%s (%s %s)", r.held, ROUTE[r.route] or "?", r.reason) or r.reason
        if r.quest then why = why .. " (" .. r.quest .. ")" end
        lines[#lines + 1] = string.format("KEEP %s: %s%s", itemName(item), why, w ~= "" and (" - " .. w) or "")
    end
    if #result.unmailable > 0 then
        local names = {}
        for _, item in ipairs(result.unmailable) do names[#names + 1] = itemName(item) end
        lines[#lines + 1] = "NOT MAILABLE (soulbound, quest or conjured, not listed in the window): " .. table.concat(names, ", ")
    end
    return table.concat(lines, "\n")
end

function Bags.Scan()
    local result = Bags.Evaluate()
    local t = result.totals
    ns.Log.Add("scan", "%d to mail (%d stacks, %d mails, gain %s), %d kept, prices %s", #result.mail, t.stacks,
        t.mails, money(t.gain), #result.keep, result.priced and tostring(result.source) or "none")
    ns.Print(string.format("would mail %d items (%d stacks, %d mail(s)), %s more than vendoring; keeps %d. Details in the window.",
        t.items, t.stacks, t.mails, money(t.gain), #result.keep))
    ns.Report.Show(Bags.Report(result), "Mailworthy scan (sends nothing)")
    return result
end

ns.On("MAIL_CLOSED", function() bankAltSkipped = false end)
