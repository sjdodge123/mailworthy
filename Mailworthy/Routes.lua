-- Bindings: "send my Enchanting materials to Bob" (operator, 2026-10-26). A binding
-- ties one crafting profession to one player (a guild member, a party member or
-- one of the player's own characters): every trade good that profession uses
-- (Valuation.PROFESSION_MATS) is mailed to that player instead of being valued
-- for the auction house, until the binding is removed. Saved for all the
-- account's characters on this realm + faction (MailworthyDB.routes) or for this
-- character only (MailworthyCharDB.routes); this character's bindings win.
--
-- A profession binding also takes its profession's recipes (item class 9, Valuation.RecipeProfession;
-- operator, 2026-11-08: "recipes should go to their respective profession mappings"), cap included.
--
-- Safety: locks, soulbound / quest / in-use items, profession tools and the ranged weapon's ammo still
-- stay; a binding never mails what the normal rule wouldn't touch. The price
-- cap ("to my alt at 10s each or more", a stepper on the binding) keeps a material
-- the market suddenly wants: at or above the cap the normal rule applies and
-- the item goes to the bank alt. "Skip once" drops a binding for this mailbox
-- visit (cleared at MAIL_CLOSED). The recipient is always shown in the window.
-- When the bound player runs Mailworthy, its hello (Comms) lists their
-- characters' crafting professions, and the mail goes to the one that has the
-- bound profession: the player themself when they do, their crafter when they
-- don't, the player when nothing is known (operator, 2026-10-26: the goal is
-- the friend who actually has the profession, never their alt for the AH).
--
-- A class binding (operator, 2026-11-08: "this is a mage only item, id like to be able to friend
-- mail these types of items too"): { to, class = "MAGE" } instead of a profession. It takes
-- items only that class may use (the tooltip's "Classes: Mage", Classes.lua) and this character
-- can't, with the same hard keeps and price cap; the mail goes to the player named.
--
-- Who can be bound: the party / raid (unit tokens), the guild (C_Club member
-- info, which carries each member's two professions and presence, as Blizzard's
-- Communities roster reads it on Forever; GetGuildRosterInfo as the fallback),
-- the account's known characters, and whoever Comms heard from. Every game call
-- is guarded; a missing API just means a shorter list.
local _, ns = ...

local Routes = {}
ns.Routes = Routes

-- Copper per unit; nil = no cap. Every step is an even number of copper: a guild template rule's
-- gear switch travels as an odd cap (Guild.lua, the wire). From 50c (operator, 2026-11-11: "if
-- they only step through gold values that wont be very helpful early game. even 50s will not be
-- used until level 30+"; "add 1s and 50c as lowest options as well").
Routes.CAP_STEPS = { 50, 100, 500, 1000, 2500, 5000, 10000, 20000, 50000, 100000, 250000, 500000, 1000000 }
-- 10s each for a new binding (Valuation.DEFAULT_CAP). A saved binding keeps the cap it has.
Routes.DEFAULT_CAP = ns.Valuation.DEFAULT_CAP
Routes.MAX = 12             -- bindings per scope
Routes.SCOPES = { account = "All my characters", character = "This character" }
Routes.SCOPE_REPORT = { account = "all my characters", character = "this character", guild = "guild template" }
Routes.ROUTE = "friend"     -- the verdict route of a diverted item

-- Verdicts a binding never overrides (AGENTS safety: never a locked item, and nothing the game
-- wouldn't let us attach): the kinds flagged `hard` in Valuation.KINDS (Valuation.HardKeep).

-- Verdicts a class binding doesn't override either: AGENTS safety keeps anything but white items
-- (without a price source) in the bags (Codex review, 2026-11-08), and an item with no auction
-- price goes to the bank alt, not a class binding (operator, 2026-11-08: the price cap can't be
-- checked without a price).
function Routes.PriceKeep(verdict)
    -- A verdict that replaced another (an enchanter's disenchant-here, Valuation) is judged by the one it replaced.
    if type(verdict) == "table" and type(verdict.was) == "table" then return Routes.PriceKeep(verdict.was) end
    if verdict and verdict.action == "mail" and verdict.route == ns.Valuation.NO_PRICE then return true end
    if not (verdict and verdict.action == "keep") then return false end
    return ns.Valuation.Flag(verdict, "priceKeep")
end

local skipped = {} -- route key -> true for this mailbox visit

local Util = ns.Util
local call = Util.Call

local function accountList() return Util.Store(MailworthyDB, "routes", (Util.RealmKey())) end

local function charList() return Util.Store(MailworthyCharDB, "routes") end

local function listFor(scope)
    return scope == "character" and charList() or accountList()
end

--- Pure: a player name as mail wants it (Characters.Clean: spaces collapsed, any "-Realm" dropped).
Routes.Clean = ns.Characters.Clean

-- An Enchanting binding also takes green and blue weapons and armor (operator, 2026-11-06:
-- "the enchanter binding ... should also include green or blue items that can be used for
-- disenchanting"): what the friend disenchants. The binding's price cap still sends a piece
-- the auction house pays well for to the bank alt; soulbound gear never leaves (a hard keep).
Routes.ENCHANTING = 333
Routes.GEAR_QUALITIES = { [2] = true, [3] = true } -- uncommon (green), rare (blue)
-- The Gear switch on an Enchanting binding (a CurseForge comment, 2026-11-11: "the option to only
-- send green/blue items if the disenchant value is greater than vendor/ah"; operator: "on each
-- enchanting binding"): `route.gear` = nil (every green and blue piece, as before) or GEAR_DE (a
-- piece goes only when disenchanting it pays more than the auction house and a vendor would;
-- Routes.GearBeaten). A piece without a disenchant value still goes (operator: "sent anyway as
-- today"). Dust, essences, shards and recipes aren't touched by it.
Routes.GEAR_DE = "de"
-- What a binding takes, when it differs from the profession's own list (primary materials only).
Routes.BINDING_MATS = { [333] = "dust, essences, shards, green and blue gear", [129] = "cloth" }

--- The crafting professions a binding can name: { { id, name, mats }, ... } by name.
function Routes.Professions()
    local list = {}
    for id, p in pairs(ns.Valuation.PROFESSION_MATS) do
        list[#list + 1] = { id = id, name = p.name, mats = (Routes.BINDING_MATS[id] or p.mats) .. ", recipes" }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Routes.ProfessionName(id)
    local p = ns.Valuation.PROFESSION_MATS[tonumber(id) or -1]
    return p and p.name or nil
end

--- Pure: the binding takes gear to disenchant (an Enchanting binding): the one with a Gear switch.
function Routes.TakesGear(route)
    return route ~= nil and not route.class and tonumber(route.profession) == Routes.ENCHANTING
end

--- Pure: a green or blue weapon or armor piece (what an Enchanting binding takes to disenchant).
function Routes.IsGear(item)
    return Routes.GEAR_QUALITIES[tonumber(item.quality) or -1] == true and ns.Valuation.CanDisenchant(item)
end

--- Pure: "Gear: all green and blue" / "Gear: only when disenchanting pays more" (the switch's
--- button), or nil for a binding that takes no gear.
function Routes.GearText(route)
    if not Routes.TakesGear(route) then return nil end
    return route.gear == Routes.GEAR_DE and "Gear: only when disenchanting pays more" or "Gear: all green and blue"
end

--- Pure: with the Gear switch on "only when disenchanting pays more", why this piece doesn't go
--- to the binding, or nil when it goes: { to, de (the disenchant value after postage), best
--- (what beats or matches it), by = "auction" / "vendor" }. Nil too with the switch off, for
--- anything but gear, and for a piece without a disenchant value (it goes, as before). The
--- auction side is the verdict's net (after cut, deposit and postage; none without a current
--- auction price), the vendor side what a vendor pays for the stack. Without a price source there
--- is no `price`: a disenchant addon's own value then comes as `item.de` (Bags.Evaluate).
function Routes.GearBeaten(route, item, verdict, price, settings)
    if not (Routes.TakesGear(route) and route.gear == Routes.GEAR_DE and Routes.IsGear(item)) then return nil end
    local de = type(price) == "table" and tonumber(price.de) or tonumber(item.de)
    if not de then return nil end
    local n = item.count or 1
    local net = math.floor(de * n) - (settings and settings.postage or 30) * (item.stacks or 1)
    local best, by = (tonumber(item.vendor) or 0) * n, "vendor"
    local ah = type(verdict) == "table" and tonumber(verdict.ahNet) or nil
    if ah and ah > best then best, by = ah, "auction" end
    if net > best then return nil end
    return { to = route.to, de = net, best = best, by = by }
end

--- Pure: "Enchanting materials" (the profession's materials, for rows and subjects), or
--- "Mage items" for a class binding.
function Routes.What(route)
    if route.class then return (ns.Classes.Name(route.class) or tostring(route.class)) .. " items" end
    return (Routes.ProfessionName(route.profession) or "?") .. " materials"
end

function Routes.Key(profession, to)
    return tostring(profession) .. "|" .. tostring(to):lower()
end

--- A saved binding's key: "333|bob" for a profession, "class:MAGE|bob" for a class.
function Routes.KeyOf(r)
    return Routes.Key(r.class and ("class:" .. tostring(r.class)) or r.profession, r.to)
end

--- Pure: the item is one of the binding's profession's primary materials: a trade good of its
--- own subclasses (cloth for Tailoring, herbs for Alchemy), or, for Enchanting, a green or
--- blue weapon or armor piece to disenchant; or a recipe the profession learns. What a profession uses on the side (Tiers.KEEP:
--- an engineer's Linen Cloth, a blacksmith's gems) isn't mailed to a binding (2026-11-07: "only
--- focus on the primary materials ... they can ask or acquire some minor pieces"); it follows
--- the normal rule. A material the bound player's skill (`route.skill`, Routes.Skill) is past
--- (Tiers) doesn't match, unless `tiers` is false or converting it still pays
--- (Tiers.WorthConverting with `priceOf`: the friend converts it); the second return is then true.
function Routes.Matches(route, item, tiers, priceOf)
    if route.class then -- a class binding: what only that class may use, and this character can't
        return ns.Classes.ForOther(item.classes, route.class, item.myClass) == true
    end
    if Routes.TakesGear(route) and Routes.IsGear(item) then return true end
    -- A recipe its profession learns (operator, 2026-11-08: "recipes should go to their respective
    -- profession mappings"); the cap still sends a recipe the auction house pays well for to the bank alt.
    local recipeFor = ns.Valuation.RecipeProfession(item)
    if recipeFor then return recipeFor == tonumber(route.profession) end
    local p = ns.Valuation.PROFESSION_MATS[tonumber(route.profession) or -1]
    if not (p and item.classID == ns.Valuation.TRADE_GOODS and p.subclasses[item.subclassID] == true) then
        return false
    end
    if tiers ~= false and ns.Tiers.Outgrown(route.profession, item.itemID, route.skill)
        and not ns.Tiers.WorthConverting(route.profession, item.itemID, priceOf) then
        return false, true
    end
    return true
end

local function has(ids, profession)
    for _, id in ipairs(ids or {}) do
        if tonumber(id) == tonumber(profession) then return true end
    end
    return false
end

--- Pure: who gets a binding's mail given what the bound player's Mailworthy said (`peer`,
--- or nil): the player when they have the profession or nothing is known, else the first
--- of their characters that has it. Second return: true when it's another character.
function Routes.Crafter(route, peer)
    if route.class then return route.to, false end -- the player named: they're the class
    if not peer or has(peer.professions, route.profession) then return route.to, false end
    for _, c in ipairs(peer.characters or {}) do
        if has(c.professions, route.profession) then return c.name, true end
    end
    return route.to, false
end

--- Where a binding's mail goes right now (Routes.Crafter with the peer heard from).
function Routes.Recipient(route)
    return Routes.Crafter(route, ns.Comms and ns.Comms.Peer(route.to) or nil)
end

-- The guild roster's members by lower-case name (the first of a name wins), with their C_Club member
-- info: it carries profession1ID / profession1Rank, as Blizzard's Communities roster sorts by them.
local function guildRoster()
    local byName = {}
    if call(IsInGuild) ~= true then return byName end
    local club = rawget(_G, "C_Club")
    local clubId = type(club) == "table" and call(club.GetGuildClubId) or nil
    local members = clubId and call(club.GetClubMembers, clubId) or nil
    for _, memberId in ipairs(type(members) == "table" and members or {}) do
        local info = call(club.GetMemberInfo, clubId, memberId)
        if type(info) == "table" and info.name then
            local key = tostring(Routes.Clean(info.name)):lower()
            if byName[key] == nil then byName[key] = info end
        end
    end
    return byName
end

-- The guild roster's rank for a member's primary profession. `cache` (optional): a table that keeps
-- the roster for several calls (Routes.Active: one roster walk per scan, not one per binding).
local function guildSkill(name, profession, cache)
    local roster
    if cache then
        cache.roster = cache.roster or guildRoster()
        roster = cache.roster
    else
        roster = guildRoster()
    end
    local info = roster[name:lower()]
    if not info then return nil end
    if tonumber(info.profession1ID) == profession then return tonumber(info.profession1Rank) end
    if tonumber(info.profession2ID) == profession then return tonumber(info.profession2Rank) end
    return nil
end

local function ownSkill(name, profession)
    -- This character (a binding to yourself): its live professions; Characters.Mailable leaves it out
    -- (Codex review, 2026-11-14: a self binding kept what its own skill had outgrown).
    if Routes.IsMe(name) then
        for _, p in ipairs(ns.Characters.Professions() or {}) do
            if tonumber(p.skillLine) == profession then return tonumber(p.rank) end
        end
        return nil
    end
    for _, entry in ipairs(ns.Characters.Mailable()) do
        if tostring(entry.name):lower() == name:lower() then
            for _, p in ipairs(entry.professions or {}) do
                if tonumber(p.skillLine) == profession then return tonumber(p.rank) end
            end
        end
    end
    return nil
end

--- The skill in a binding's profession of the character that gets its mail, or nil when
--- unknown: the highest of what their Mailworthy said (Comms "S2"), this account's own
--- character's last login, and the guild roster (primary professions only). Skill only
--- grows, so the highest is the latest. `cache` (optional, a table): keeps the guild roster between
--- calls (Routes.Active passes one per scan).
function Routes.Skill(route, cache)
    if route.class then return nil end
    local to = Routes.Recipient(route)
    local profession = tonumber(route.profession)
    local best
    for _, skill in ipairs({ ns.Comms and ns.Comms.Skill(to, profession) or false, ownSkill(to, profession) or false,
        guildSkill(to, profession, cache) or false }) do
        if skill and (not best or skill > best) then best = skill end
    end
    return best
end

--- Is `name` this character (a binding's recipient, cleaned and case-blind as Mailer.Blocker reads it)?
function Routes.IsMe(name)
    local me = ns.PlayerName and ns.PlayerName()
    if not name or not me then return false end
    return tostring(Routes.Clean(name) or name):lower() == tostring(Routes.Clean(me) or me):lower()
end

local GROUP = { character = 1, account = 2, guild = 3 }

--- Pure: of two bindings that both take an item, `a` goes first: this character's, then the
--- account's, then the guild's (this character's win, personal wins), then within one of those
--- the recipient with the lower skill in their profession (`skill`, Routes.Active; operator,
--- 2026-11-07, Blacksmithing and Engineering both taking metal and stone: "Lowest skill first",
--- so both crafters keep levelling), a known skill before an unknown one; else the list's order.
function Routes.Before(a, b)
    local ga, gb = GROUP[a.scope] or 2, GROUP[b.scope] or 2
    if ga ~= gb then return ga < gb end
    local sa, sb = tonumber(a.skill), tonumber(b.skill)
    if sa and sb then return sa < sb end
    return sa ~= nil and sb == nil
end

--- Pure: divert an item to a binding. `verdict` is Valuation.Evaluate's result for the
--- item, `routes` the active bindings (Routes.Active()). Returns the new verdict, or nil
--- when no binding applies; a second return names the binding whose cap kept the item on
--- the normal rule, a third the binding whose player's skill is past the material (Tiers), a
--- fourth why a piece of gear didn't go to an Enchanting binding whose Gear switch is on
--- (Routes.GearBeaten: disenchanting pays no more than selling it).
--- Several bindings taking the item (metal and stone: Blacksmithing and Engineering): the first
--- by Routes.Before; its cap and its Gear switch decide, as if it were the only one.
function Routes.Divert(item, verdict, price, settings, routes)
    if not Routes.Divertible(verdict, price) then return nil end
    -- Me first (operator, 2026-11-14: "Make me a profit/level my professions first, then the same to
    -- my friend rules, then the same to my guild rules"): what this character's own professions still
    -- use (Valuation's profession keep, its "on my bank alt" mail, an enchanter's disenchant-here) stays
    -- with it, whatever binding takes the material. The row's button (Routes.Pick) sends it anyway.
    if verdict and verdict.neededBy then return nil end
    local unit, capUnit = Routes.Units(item, price, settings)
    local outgrown, route
    for _, r in ipairs(routes or {}) do
        local matches, past = Routes.Matches(r, item, settings and settings.tiers, settings and settings.priceOf)
        -- A class binding needs a current auction price when there's a price source (the cap is checked
        -- against it): an item without one goes to the bank alt, whatever its route (a disenchant
        -- value alone isn't one; Codex review, 2026-11-08).
        if r.class and not Routes.ClassPriced(verdict, price, unit) then matches = false end
        -- A recipe this character already knows (item.known, Recipes.lua; operator, 2026-11-14: "already
        -- known crafting recipes should continue down regular routing rules"): a binding naming this
        -- character doesn't keep it here; another binding or the regular rules take it.
        if matches and item.known and Routes.IsMe((Routes.Recipient(r))) then matches = false end
        if past then outgrown = outgrown or r end
        if matches and (not route or Routes.Before(r, route)) then route = r end
    end
    if not route then return nil, nil, outgrown end
    if route.cap and capUnit and capUnit >= route.cap then return nil, route end
    local beaten = Routes.GearBeaten(route, item, verdict, price, settings)
    if beaten then return nil, nil, outgrown, beaten end
    return Routes.Force(item, route, unit, settings)
end

--- Pure: a binding may take an item with this verdict at all: never a hard keep, a pinned item (Pins.lua:
--- it goes to the bank alt, the player asked for exactly that) or after a failed price call (AGENTS safety;
--- Codex review, 2026-11-08). The row's button (Routes.Choices) is held to the same.
function Routes.Divertible(verdict, price)
    if ns.Valuation.HardKeep(verdict) then return false end
    if verdict and (verdict.pinned or verdict.failed) then return false end
    -- A binding naming this character keeps the item here (Routes.Force): no pick moves it (AGENTS Safety).
    if verdict and verdict.forMe then return false end
    if type(price) == "table" and price.failed then return false end
    return true
end

--- Pure: a class binding's price rule (AGENTS: an item without a current auction price goes to the bank
--- alt, never to a class binding): true when it may take the item.
function Routes.ClassPriced(verdict, price, unit)
    return not (Routes.PriceKeep(verdict) or (type(price) == "table" and unit == nil))
end

--- Pure: the current auction unit price (none past the age limit), and the unit price a binding's cap is
--- checked against: the current one; for a recipe an old one too, so a recipe the auction house paid well
--- for isn't given away on a stale price (Codex review, 2026-11-08); for a green or blue piece of gear the
--- vendor price when it is higher (operator, 2026-11-14: "something that vendors or AH for 70s gives me a
--- substantial profit and i would want to sell that instead": a piece with no auction price but a 70s
--- vendor price isn't given to the enchanter under a 50s cap).
function Routes.Units(item, price, settings)
    local unit
    if type(price) == "table" and price.ah ~= nil
        and (price.age == nil or price.age <= (settings and settings.maxAgeDays or math.huge)) then
        unit = ns.Valuation.SmoothedPrice(price)
    end
    local capUnit = unit
    if capUnit == nil and ns.Valuation.RecipeProfession(item) and type(price) == "table" and price.ah ~= nil then
        capUnit = ns.Valuation.SmoothedPrice(price)
    end
    if Routes.IsGear(item) then
        local vendor = tonumber(item.vendor)
        if vendor and vendor > 0 and (capUnit == nil or vendor > capUnit) then capUnit = vendor end
    end
    return unit, capUnit
end

--- Pure: the verdict that mails `item` to `route`'s recipient, past its cap, Gear switch and the profession
--- keep (Divert has checked those; a row pick, Routes.Choices, skips them on purpose). A binding naming
--- this character keeps the item here instead (it is saved for all the account's characters, so on the
--- bound one it names itself: Cooking bound to Androl from another alt, Androl at the mailbox,
--- rl-companion 2026-11-14): not to the bank alt, which would mail it straight back, and never in a mail
--- to this character (Mailer.Blocker). `unit`: the current auction unit price (Routes.Units).
function Routes.Force(item, route, unit, settings)
    local to, crafter = Routes.Recipient(route)
    if Routes.IsMe(to) then
        return ns.Valuation.Keep(ns.Valuation.K.forMe, { forMe = route.key }, Routes.What(route))
    end
    local n = item.count or 1
    return {
        action = "mail", route = Routes.ROUTE, to = to, crafter = crafter, key = route.key, what = Routes.What(route),
        reason = ns.Valuation.RecipeProfession(item) and (Routes.ProfessionName(route.profession) .. " recipe goes to "
            .. tostring(to)) or (Routes.What(route) .. " go to " .. tostring(to)),
        vendor = (item.vendor or 0) * n, postage = (settings and settings.postage or 30) * (item.stacks or 1),
        ahUnit = unit,
        -- A guild template rule's mail (Guild.Rules): the mail log tags it and the guild contributions
        -- count it (Contributions.lua); personal and class bindings carry none.
        guild = route.scope == "guild" and { key = route.guildKey, profession = tonumber(route.profession),
            rev = tonumber(route.rev) } or nil,
    }
end

-- Row picks (this mailbox visit) ------------------------------------------------------
-- The button on each row of the mailbox window (operator, 2026-11-14: "i want to click next to that
-- copper bar and toggle it to 2) click again and toggles it to 3) ... so with 2 clicks it would actually
-- route the copper bar to Jold for that round of sending"): the item goes where the player picked, for
-- this visit (cleared at MAIL_CLOSED, like Skip once). The choices are the item's own verdict ("mine":
-- keep / AH / DE / V / bank) and each binding whose profession or class takes it, friends' before the
-- guild's (Routes.Before). A pick wins over the profession keep, the binding's price cap, its Gear switch
-- and the tier table (operator: "my click wins"), never over a hard keep, a pin, a failed price call, a
-- class binding's price rule, Return to sender or a binding naming this character.

Routes.MINE = "mine"
local picks = {} -- item link -> Routes.MINE or a binding's key

--- Pure: the bindings a row's button can send `item` to, in order (Routes.Before): those whose
--- profession or class takes it (the tier table aside), not naming this character. `verdict` is the
--- item's own (Valuation.Evaluate's, before any binding); none for what no binding may take.
function Routes.Choices(item, verdict, price, settings, routes)
    if not Routes.Divertible(verdict, price) then return {} end
    local unit = Routes.Units(item, price, settings)
    local list = {}
    for _, r in ipairs(routes or {}) do
        if Routes.Matches(r, item, false) and not Routes.IsMe(Routes.Recipient(r))
            and (not r.class or Routes.ClassPriced(verdict, price, unit)) then
            list[#list + 1] = r
        end
    end
    table.sort(list, function(a, b)
        if Routes.Before(a, b) then return true end
        if Routes.Before(b, a) then return false end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

--- Pure: the state after `current` (Routes.MINE or a key) in the cycle mine, then each choice: what one
--- press of the row's button picks. Nil when there is nothing to pick between.
function Routes.NextPick(current, choices)
    if #(choices or {}) == 0 then return nil end
    local states = { Routes.MINE }
    for _, r in ipairs(choices) do states[#states + 1] = r.key end
    for i, s in ipairs(states) do
        if s == current then return states[i % #states + 1] end
    end
    return states[1]
end

function Routes.Pick(link, state)
    if link then picks[link] = state end
end
function Routes.Picked(link) return link and picks[link] or nil end
function Routes.ClearPicks() picks = {} end

--- Pure: a row's state as its button names it: "Me" for the item's own verdict, "Friend" for the
--- player's own binding (this character's or all of them), "Guild" for a guild template rule.
function Routes.PickLabel(state, choices)
    if state == nil or state == Routes.MINE then return "Me" end
    for _, r in ipairs(choices or {}) do
        if r.key == state then return r.scope == "guild" and "Guild" or "Friend" end
    end
    return "Me"
end

-- Saved bindings ----------------------------------------------------------------

local function withKeys(list, scope)
    local out = {}
    for _, r in ipairs(list) do
        if type(r) == "table" and r.to and (r.profession or r.class) then
            local copy = {}
            for k, v in pairs(r) do copy[k] = v end
            copy.scope, copy.key = scope, Routes.KeyOf(r)
            out[#out + 1] = copy
        end
    end
    return out
end

--- The player's own bindings (the friends window's): this character's, then the account's.
function Routes.Personal()
    local list = withKeys(charList(), "character")
    for _, r in ipairs(withKeys(accountList(), "account")) do list[#list + 1] = r end
    return list
end

--- Every binding that applies to this character: this character's first, then the
--- account's for this realm + faction, then the guild template's rules while the player has
--- them on (Guild.Rules: personal bindings and this character's professions come first).
--- Each carries `scope` ("character" / "account" / "guild") and `key`.
function Routes.List()
    local list = Routes.Personal()
    if ns.Guild then
        for _, r in ipairs(ns.Guild.Rules(list)) do list[#list + 1] = r end
    end
    return list
end

function Routes.Count() return #Routes.List() end

--- The bindings in force for this mailbox visit (not skipped once), each with the
--- recipient's `skill` (Routes.Skill) for the material tiers. The guild roster is walked once for
--- all of them (every bag scan calls this).
function Routes.Active()
    local list, cache = {}, {}
    for _, r in ipairs(Routes.List()) do
        if not skipped[r.key] then
            r.skill = Routes.Skill(r, cache)
            list[#list + 1] = r
        end
    end
    return list
end

local function find(key)
    for _, scope in ipairs({ "character", "account" }) do
        local list = listFor(scope)
        for i, r in ipairs(list) do
            if type(r) == "table" and Routes.KeyOf(r) == key then return list, i, r, scope end
        end
    end
    return nil
end

function Routes.Get(key)
    local _, _, r, scope = find(key)
    if not r then return nil end
    local copy = {}
    for k, v in pairs(r) do copy[k] = v end
    copy.scope, copy.key = scope, key
    return copy
end

--- Add a binding. `what`: a crafting profession's skill line ID, or a class token ("MAGE") for
--- a class binding. opts: scope ("account" default / "character"), cap (copper; false = none).
--- Returns the binding, or nil and why.
function Routes.Add(name, what, opts)
    opts = opts or {}
    name = Routes.Clean(name)
    if not name then return nil, "no name" end
    -- A binding to yourself (operator, 2026-11-14: "i dont yet have leather working but i plan on picking
    -- it up but its defaulting to my guild rule"): this character keeps the materials (Routes.Force), the
    -- guild's rule for that profession is left out ("personal wins", Guild.Rules), and with "All my
    -- characters" the others mail them here. Not for a class: this character's class items are its own.
    local toSelf = Routes.IsMe(name)
    local profession, class = tonumber(what), nil
    if not profession then
        class = type(what) == "string" and ns.Classes.Token(what) or nil
        if not class then return nil, "not a crafting profession or a class" end
        if toSelf then return nil, "a class binding to this character means nothing" end
    elseif not Routes.ProfessionName(profession) then
        return nil, "not a crafting profession"
    end
    local route = { to = name, profession = profession, class = class,
        cap = opts.cap == nil and Routes.DEFAULT_CAP or (opts.cap or nil), at = Util.Now() }
    local key = Routes.KeyOf(route)
    if find(key) then return nil, "already bound" end
    local scope = opts.scope == "character" and "character" or "account"
    local list = listFor(scope)
    if #list >= Routes.MAX then return nil, "too many bindings" end
    list[#list + 1] = route
    ns.Log.Add("routes", "bound %s to %s (%s)", Routes.What(route), name, scope)
    return Routes.Get(key)
end

function Routes.Remove(key)
    local list, i, r = find(key)
    if not list then return false end
    table.remove(list, i)
    skipped[key] = nil
    ns.Log.Add("routes", "unbound %s to %s", Routes.What(r), r.to)
    return true
end

--- Move a binding between "account" and "character".
function Routes.SetScope(key, scope)
    local list, i, r, current = find(key)
    if not list or current == scope or not Routes.SCOPES[scope] then return false end
    local target = listFor(scope)
    if #target >= Routes.MAX then return false end
    table.remove(list, i)
    target[#target + 1] = r
    ns.Log.Add("routes", "%s to %s now %s", Routes.What(r), r.to, scope)
    return true
end

function Routes.ToggleScope(key)
    local r = Routes.Get(key)
    if not r then return false end
    return Routes.SetScope(key, r.scope == "account" and "character" or "account")
end

--- Pure: the next cap in direction +1 / -1; past the top step the cap goes (nil = none).
function Routes.NextCap(cap, dir)
    local steps = Routes.CAP_STEPS
    if cap == nil then
        if dir > 0 then return nil end
        return steps[#steps]
    end
    local i, nearest = 1, math.huge
    for j, v in ipairs(steps) do
        if math.abs(v - cap) < nearest then i, nearest = j, math.abs(v - cap) end
    end
    if dir > 0 then return steps[i + 1] end -- nil past the last step: no cap
    return steps[math.max(1, i - 1)]
end

function Routes.StepCap(key, dir)
    local _, _, r = find(key)
    if not r then return end
    r.cap = Routes.NextCap(r.cap, dir)
    ns.Log.Add("routes", "%s to %s: cap %s", Routes.What(r), r.to, r.cap and ns.Valuation.Money(r.cap) or "none")
end

--- Flip an Enchanting binding's Gear switch (Routes.GEAR_DE / every piece). Returns true when
--- the binding has one.
function Routes.ToggleGear(key)
    local _, _, r = find(key)
    if not Routes.TakesGear(r) then return false end
    r.gear = r.gear ~= Routes.GEAR_DE and Routes.GEAR_DE or nil
    ns.Log.Add("routes", "%s to %s: %s", Routes.What(r), r.to, Routes.GearText(r))
    return true
end

--- Pure: "to my alt at 10s each or more" / "no price cap".
function Routes.CapText(route)
    if not route.cap then return "no price cap" end
    return "to my alt at " .. ns.Valuation.Money(route.cap) .. " each or more"
end

--- Pure: "Enchanting materials to Bob Surname".
function Routes.Describe(route)
    return Routes.What(route) .. " to " .. tostring(route.to)
end

-- Skip once (this mailbox visit) --------------------------------------------------

function Routes.SkipOnce(key)
    for _, r in ipairs(Routes.List()) do
        if r.key == key then skipped[key] = true end
    end
end

function Routes.Unskip(key) skipped[key] = nil end
function Routes.Skipped(key) return skipped[key] == true end
function Routes.ClearSkips() skipped = {} end

ns.On("MAIL_CLOSED", function()
    Routes.ClearSkips()
    Routes.ClearPicks()
end)

-- Candidates: who can be bound ------------------------------------------------------

local function presenceOnline(presence)
    local enum = rawget(_G, "Enum")
    local p = type(enum) == "table" and enum.ClubMemberPresence or {}
    local offline, unknown = p.Offline or 3, p.Unknown or 0
    return presence ~= nil and presence ~= offline and presence ~= unknown
end

local function addCandidate(list, byName, c)
    c.name = Routes.Clean(c.name)
    if not c.name or c.name:lower() == tostring(ns.PlayerName()):lower() then return end
    local entry = byName[c.name:lower()]
    if not entry then
        entry = { name = c.name, sources = {}, professions = {}, professionSet = {}, online = false }
        byName[c.name:lower()] = entry
        list[#list + 1] = entry
    end
    entry.sources[c.source] = true
    entry.online = entry.online or c.online == true
    entry.class, entry.level = entry.class or ns.Classes.Token(c.class), entry.level or c.level
    for _, id in ipairs(c.professions or {}) do
        id = tonumber(id)
        if Routes.ProfessionName(id) and not entry.professionSet[id] then
            entry.professionSet[id] = true
            entry.professions[#entry.professions + 1] = id
        end
    end
end

local function groupCandidates(list, byName)
    local n = tonumber((call(GetNumGroupMembers))) or 0
    if n == 0 then return end
    local raid = call(IsInRaid) == true
    for i = 1, n do
        local unit = raid and ("raid" .. i) or ("party" .. (i - 1))
        if unit ~= "party0" then
            local name = call(GetUnitName, unit, true) or call(UnitName, unit)
            if name then
                local _, class = call(UnitClass, unit)
                addCandidate(list, byName, { name = name, source = "party", online = call(UnitIsConnected, unit) ~= false,
                    class = class, level = call(UnitLevel, unit) })
            end
        end
    end
end

local function guildCandidates(list, byName)
    if call(IsInGuild) ~= true then return end
    local club = rawget(_G, "C_Club")
    local clubId = type(club) == "table" and call(club.GetGuildClubId) or nil
    local members = clubId and call(club.GetClubMembers, clubId) or nil
    if type(members) == "table" and #members > 0 then
        for _, memberId in ipairs(members) do
            local info = call(club.GetMemberInfo, clubId, memberId)
            if type(info) == "table" and info.name and not info.isSelf then
                addCandidate(list, byName, { name = info.name, source = "guild", online = presenceOnline(info.presence),
                    level = info.level, class = ns.Classes.Token(info.classID),
                    professions = { info.profession1ID, info.profession2ID } })
            end
        end
        return
    end
    for i = 1, tonumber((call(GetNumGuildMembers))) or 0 do
        local name, _, _, level, _, _, _, _, online, _, class = call(GetGuildRosterInfo, i)
        if name then
            addCandidate(list, byName, { name = name, source = "guild", online = online == true, level = level, class = class })
        end
    end
end

local function altCandidates(list, byName)
    for _, entry in ipairs(ns.Characters.Mailable()) do
        local ids = {}
        for _, p in ipairs(entry.professions or {}) do ids[#ids + 1] = p.skillLine end
        addCandidate(list, byName, { name = entry.name, source = "alt", class = entry.class, level = entry.level,
            professions = ids })
    end
end

local function peerCandidates(list, byName)
    if not ns.Comms then return end
    for _, peer in pairs(ns.Comms.Peers()) do
        addCandidate(list, byName, { name = peer.name, source = "mailworthy", professions = peer.professions })
        local entry = byName[Util.NameKey(peer.name) or ""]
        if entry then entry.peer = peer end
    end
end

--- Pure: a candidate's professions Mailworthy can bind, by name: { { id, name }, ... }.
function Routes.Suggested(candidate)
    local list = {}
    for _, id in ipairs(candidate.professions or {}) do list[#list + 1] = { id = id, name = Routes.ProfessionName(id) } end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

--- Pure: "Bob Surname - Enchanting, Tailoring - online - guild, Mailworthy". `nameText` shows in
--- place of the name (the friends window's: the name with the Mailworthy mark, Comms.Mark).
function Routes.CandidateText(c, nameText)
    local parts = { nameText or c.name }
    local profs = {}
    for _, p in ipairs(Routes.Suggested(c)) do profs[#profs + 1] = p.name end
    if #profs > 0 then parts[#parts + 1] = table.concat(profs, ", ") end
    if c.online then parts[#parts + 1] = "online" end
    local where = {}
    if c.sources.me then where[#where + 1] = "you" end
    for _, s in ipairs({ "party", "guild", "alt" }) do
        if c.sources[s] then where[#where + 1] = s == "alt" and "my character" or s end
    end
    if c.sources.mailworthy or c.peer then where[#where + 1] = "Mailworthy" end
    if #where > 0 then parts[#parts + 1] = table.concat(where, ", ") end
    return table.concat(parts, " - ")
end

--- Everyone this character could bind: online players first, then the account's own
--- characters, then Mailworthy users, then party before guild, by name. Each: { name, sources = { party / guild / alt /
--- mailworthy }, online, class, level, professions = { ids... }, peer }.
function Routes.Candidates()
    local list, byName = {}, {}
    groupCandidates(list, byName)
    guildCandidates(list, byName)
    altCandidates(list, byName)
    peerCandidates(list, byName)
    local rank = { party = 1, guild = 2, alt = 3 }
    local function best(c)
        local r = 9
        for s, n in pairs(rank) do if c.sources[s] and n < r then r = n end end
        return r
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        local aa, ab = a.sources.alt == true, b.sources.alt == true -- own characters: mail always arrives
        if aa ~= ab then return aa end
        local pa, pb = a.peer ~= nil, b.peer ~= nil
        if pa ~= pb then return pa end
        local ra, rb = best(a), best(b)
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return list
end

-- A crafter of your own (QoL pass F, operator 2026-11-09: "8"; media/qol-prototype.png) ------
-- When the scan holds what a known character of this account crafts with, and no binding takes
-- it, the mail window offers the binding: "Sadie Ember is your enchanter (skill 140). ...". Bind
-- is an ordinary personal binding (Routes.Add), so the list redraws with "to Sadie" before
-- anything is sent; "Not for Sadie" is remembered for that character and profession.

Routes.CRAFTER = { [164] = "blacksmith", [202] = "engineer", [165] = "leatherworker", [197] = "tailor",
    [171] = "alchemist", [333] = "enchanter", [185] = "cook" }

local function dismissals() return Util.Store(MailworthyDB, "crafterOffers", (Util.RealmKey())) end
local function offerKey(name, profession) return tostring(name):lower() .. "|" .. tostring(tonumber(profession)) end

--- "Not for <name>": never offer this character this profession's materials again.
function Routes.DismissOffer(name, profession) dismissals()[offerKey(name, profession)] = true end
function Routes.OfferDismissed(name, profession) return dismissals()[offerKey(name, profession)] == true end

--- The binding to offer for a scan (Bags.Evaluate's result), or nil: { name, profession, skill,
--- count (list rows it would take), items, gearOnly }. One at a time: the one that takes the most.
--- Never this character, the bank alt (`bankAlt`), a profession this character has itself (it
--- keeps those materials), a profession any binding already names, or a dismissed pair.
---
--- The count is what Bind would really do (Codex review, 2026-11-09): every item of the scan is
--- run through Routes.Divert with the bindings in force plus the offered one, as the next scan
--- will, so another binding that wins the item (lower skill, its cap), the crafter's real skill
--- (Routes.Skill: the roster's or their Mailworthy's, not only the saved rank), the price cap and
--- the hard keeps all count; and an item staying today that the binding would take counts too.
--- A binding whose mail would be redirected to another character (Routes.Recipient) isn't offered.
function Routes.Offer(scan, bankAlt)
    if type(scan) ~= "table" then return nil end
    local account = 0
    for _, r in ipairs(Routes.Personal()) do
        if r.scope == "account" then account = account + 1 end
    end
    if account >= Routes.MAX then return nil end -- Bind adds an account binding: its own limit
    local settings = scan.settings or {}
    local taken = {}
    for _, p in ipairs(type(settings.professions) == "table" and settings.professions or {}) do
        taken[tonumber(p.skillLine) or -1] = true
    end
    for _, r in ipairs(Routes.List()) do
        if r.profession then taken[tonumber(r.profession)] = true end
    end
    -- Each item with the verdict it has before any binding (a held or diverted one is valued again).
    local items = {}
    for _, list in ipairs({ scan.mail or {}, scan.keep or {} }) do
        for _, item in ipairs(list) do
            local ok, verdict = pcall(ns.Valuation.Evaluate, item, item.price, settings)
            if ok and type(verdict) == "table" then items[#items + 1] = { item = item, verdict = verdict } end
        end
    end
    if #items == 0 then return nil end
    local me = tostring(ns.PlayerName()):lower()
    local alt = Util.NameKey(bankAlt) or ""
    local active = Routes.Active()
    local best
    for _, entry in ipairs(ns.Characters.Mailable()) do
        local name = Routes.Clean(entry.name)
        local lower = name and name:lower()
        if name and lower ~= me and lower ~= alt then
            for _, p in ipairs(entry.professions or {}) do
                local id = tonumber(p.skillLine)
                if id and Routes.ProfessionName(id) and not taken[id] and not Routes.OfferDismissed(name, id) then
                    local route = { to = name, profession = id, cap = Routes.DEFAULT_CAP, scope = "account" }
                    route.key = Routes.KeyOf(route)
                    route.skill = Routes.Skill(route) or tonumber(p.rank)
                    local routes = { route }
                    for _, r in ipairs(active) do routes[#routes + 1] = r end
                    local offer = { name = name, profession = id, skill = route.skill, count = 0, items = {}, gearOnly = true }
                    local redirected = false
                    for _, it in ipairs(items) do
                        local ok, verdict = pcall(Routes.Divert, it.item, it.verdict, it.item.price, settings, routes)
                        if ok and verdict and verdict.key == route.key then
                            if tostring(verdict.to):lower() ~= lower then redirected = true end
                            offer.count = offer.count + 1
                            offer.items[#offer.items + 1] = it.item
                            local class = tonumber(it.item.classID)
                            if class ~= 2 and class ~= 4 then offer.gearOnly = false end
                        end
                    end
                    if offer.count > 0 and not redirected and (not best or offer.count > best.count
                            or (offer.count == best.count
                                and (offer.name < best.name or (offer.name == best.name and id < best.profession)))) then
                        best = offer
                    end
                end
            end
        end
    end
    return best
end

--- This character as a candidate: for a guild template rule naming its author (2026-11-07: "I
--- should be able to set routing to me in the guild template as well"), and for a binding of the
--- player's own (2026-11-14: a profession they plan to pick up). Here the binding keeps the
--- materials (Routes.Force); the guild's other members (and this account's other characters) mail you.
function Routes.Me()
    local name = Routes.Clean(ns.PlayerName())
    if not name then return nil end
    local ids = {}
    for _, p in ipairs(ns.Characters.Professions()) do
        local id = tonumber(p.skillLine)
        if Routes.ProfessionName(id) then ids[#ids + 1] = id end
    end
    return { name = name, sources = { me = true, guild = true }, professions = ids, professionSet = {}, online = true }
end

local lastRosterRequest = -math.huge
--- Ask the game for a fresh guild roster (what Blizzard's mail window does when the
--- auto-complete list is empty), at most every 10 s.
function Routes.RequestRoster()
    local now = call(GetTime) or 0
    if now - lastRosterRequest < 10 then return end
    lastRosterRequest = now
    local guild = rawget(_G, "C_GuildInfo")
    if call(IsInGuild) == true and type(guild) == "table" then call(guild.GuildRoster) end
end

--- One line per binding for /mw report.
function Routes.ReportLines()
    local lines = {}
    for _, r in ipairs(Routes.List()) do
        local to, crafter = Routes.Recipient(r)
        local skill = Routes.Skill(r)
        local past = skill and ns.Tiers.PastText(r.profession, skill) or ""
        local gear = Routes.GearText(r)
        lines[#lines + 1] = string.format("binding: %s (%s, %s%s%s, skill %s%s%s)", Routes.Describe(r),
            Routes.SCOPE_REPORT[r.scope] or tostring(r.scope), Routes.CapText(r),
            gear and r.gear and (", " .. gear:lower()) or "",
            crafter and (", delivered to their crafter " .. to) or "", skill and tostring(skill) or "unknown",
            past ~= "" and (": past " .. past) or "",
            skipped[r.key] and ", skipped this visit" or "")
    end
    return lines
end
