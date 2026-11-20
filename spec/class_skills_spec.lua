-- Class skills (a CurseForge comment, 2026-11-20: "Could you add the option to send lockboxes to a
-- rogue friend/alt?"; operator: "Lock boxes can route to rouges for training ... comprehension items
-- to mages(class specific profession)"): a class binding takes what its class's own skill levels on
-- like a profession's materials, and a rogue or a mage keeps its own.
local loadAddon = require("spec.support.load_addon")

local IRON = 4634       -- Iron Lockbox: one of Classic's, known by ID
local JUNKBOX = 277700  -- a Forever-only box: only its tooltip says "Locked"
local SCROLL = 211234   -- "Scroll: VOCE WELL": "Classes: Mage", "Requires Comprehension (15)"
local TOME = 211240     -- mage-only, no Comprehension line: a plain class item
local ORE = 2770
local BOB = "Bob Surname"
local BANK_ALT = "Roknua Themicrulah"

describe("class skills: lockboxes and Comprehension scrolls", function()
    local ns, prices

    local function find(list, itemID)
        for _, it in ipairs(list) do if it.itemID == itemID then return it end end
    end

    local function useAuctionator()
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end

    local function be(class)
        WowStub.state.class = { class:sub(1, 1) .. class:sub(2):lower(), class, 1 }
    end

    before_each(function()
        ns = loadAddon()
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 20 * 86400
        prices = {}
        useAuctionator()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(BANK_ALT)
        local S = WowStub.state
        WowStub.setBag(0, 1, WowStub.item(IRON, "Iron Lockbox", { quality = 2, sell = 0, class = 15 }))
        S.tooltipLines[IRON] = { "Locked", "Requires Lockpicking (70)" }
        WowStub.setBag(0, 2, WowStub.item(JUNKBOX, "Heavy Iron Junkbox", { quality = 2, sell = 0, class = 15 }))
        S.tooltipLines[JUNKBOX] = { "|cffff2020Locked|r", "Requires Lockpicking (175)" }
        WowStub.setBag(0, 3, WowStub.item(SCROLL, "Scroll: VOCE WELL", { quality = 2, sell = 15, class = 0 }))
        S.itemClasses[SCROLL] = "Mage"
        S.tooltipLines[SCROLL] = { "Requires Comprehension (15)" }
        WowStub.setBag(0, 4, WowStub.item(TOME, "Tome of the Magi", { quality = 2, sell = 15, class = 0 }))
        S.itemClasses[TOME] = "Mage"
        WowStub.setBag(0, 5, WowStub.item(ORE, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }))
        prices[WowStub.link(ORE, "Copper Ore")] = 174
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("reads the tooltip's lines in the client's words", function()
        local C = ns.ClassSkills
        assert.equal("lockpicking", C.Read({ "Iron Lockbox", "Locked" }))
        assert.equal("lockpicking", C.Read({ "|cffff2020Locked|r" }), "colour codes don't count")
        assert.equal("lockpicking", C.Read({ "Requires Lockpicking (70)" }), "the skill line alone")
        assert.equal("lockpicking", C.Read({ "Locked\nRequires Lockpicking (70)" }), "both texts on one line")
        assert.equal("comprehension", C.Read({ "Classes: Mage\nRequires Comprehension (15)" }))
        assert.is_true(C.IsLockedLine("|cffff2020Locked|r\nRequires Lockpicking (70)"))
        assert.is_false(C.IsLockedLine("Unlocked"))
        assert.equal("comprehension", C.Read({ "Classes: Mage", "Requires Comprehension (15)" }))
        assert.is_nil(C.Read({ "Classes: Mage", "Requires Tailoring (300)" }), "a mage's robe pattern is no scroll")
        assert.is_nil(C.Read({ "Locked Chest Key", "Unlocked" }))
        assert.is_nil(C.Read({}))
        assert.equal("lockpicking", C.Read({ "Verschlossen" }, "Verschlossen"), "LOCKED as the client has it")
        assert.is_nil(C.Read({ "Locked" }, "Verschlossen"))
        assert.equal("comprehension", C.Read({ "Benötigt Comprehension (15)" }, nil, "Benötigt %s (%d)"))
        assert.equal("comprehension", C.Read({ "Comprehension (15) requis" }, nil, "%1$s (%2$d) requis"))
        assert.equal("comprehension", C.Read({ "Requires Comprehension (15)" }, nil, "no placeholders"),
            "a format without %s: the English one")
    end)

    it("knows Classic's lockboxes by ID, anything else by its tooltip, and asks again until the item has loaded", function()
        local C = ns.ClassSkills
        for _, id in ipairs({ 4632, 4633, 4634, 4636, 4637, 4638, 5758, 5759, 5760, 16882, 16883, 16884, 16885,
            6354, 6355, 13875, 13918 }) do
            assert.is_true(C.Known(id), tostring(id))
        end
        WowStub.state.tooltipLines[IRON] = nil
        assert.equal("lockpicking", C.Of(IRON), "by ID: no tooltip needed")
        assert.equal("item ID", C.How(IRON))
        assert.equal("lockpicking", C.Of(JUNKBOX))
        assert.equal("tooltip", C.How(JUNKBOX))
        assert.equal("comprehension", C.Of(SCROLL))
        assert.is_false(C.Of(TOME))
        assert.is_false(C.Of(ORE))
        assert.is_nil(C.How(ORE))
        local reads = WowStub.state.tooltipReads
        C.Of(ORE)
        C.Of(JUNKBOX)
        assert.equal(reads, WowStub.state.tooltipReads, "both answers are remembered")
        -- not loaded yet: a name line alone says nothing, and isn't remembered
        WowStub.state.uncached[277701] = true
        WowStub.state.tooltipLines[277701] = { "Locked" }
        assert.is_false(C.Of(277701))
        WowStub.state.uncached[277701] = nil
        assert.equal("lockpicking", C.Of(277701))
        -- a mailbox visit asks the "neither" answers again
        WowStub.state.tooltipLines[TOME] = { "Requires Comprehension (50)" }
        assert.is_false(C.Of(TOME))
        ns.Fire("MAIL_SHOW")
        assert.equal("comprehension", C.Of(TOME))
        assert.same({ "lockpicking" }, C.OfClass("ROGUE"))
        assert.same({}, C.OfClass("PALADIN"))
        assert.equal("lockboxes", C.ItemsText("ROGUE"))
        assert.equal("Comprehension scrolls", C.ItemsText("MAGE"))
        assert.is_nil(C.ItemsText("WARRIOR"))
    end)

    it("without a binding nothing changes: the normal rule, and no tooltip is read for it", function()
        local before = ns.Bags.Evaluate()
        assert.is_nil(find(before.mail, IRON).result.to)
        assert.equal("noprice", find(before.mail, IRON).result.route, "unpriced with Auctionator: the bank alt, as before")
        assert.is_nil(find(before.mail, IRON).classSkill)
        assert.is_nil(find(before.mail, SCROLL).result.to)
    end)

    it("a rogue's binding takes locked lockboxes whatever their price, like a profession's materials", function()
        local route = assert(ns.Routes.Add(BOB, "ROGUE"))
        local result = ns.Bags.Evaluate()
        local box = find(result.mail, IRON)
        assert.equal(BOB, box.result.to, "no auction price: still to the rogue")
        assert.equal("Lockboxes go to Bob Surname", box.result.reason)
        assert.equal("Rogue items", box.result.what)
        assert.equal(route.key, box.result.key)
        assert.equal(BOB, find(result.mail, JUNKBOX).result.to, "one only its tooltip names")
        assert.is_nil(find(result.mail, ORE).result.to)
        assert.is_nil(find(result.mail, SCROLL).result.to, "a mage's scroll isn't the rogue's")
        -- a stale price: still to the rogue
        prices[WowStub.link(IRON, "Iron Lockbox")] = 300
        Auctionator.API.v1.GetAuctionAgeByItemLink = function() return 30 end
        assert.equal(BOB, find(ns.Bags.Evaluate().mail, IRON).result.to)
        Auctionator.API.v1.GetAuctionAgeByItemLink = function() return 0 end
        assert.equal(BOB, find(ns.Bags.Evaluate().mail, IRON).result.to, "3s each: under the 10s cap")
        -- at the cap the normal rule applies: the bank alt
        prices[WowStub.link(IRON, "Iron Lockbox")] = 5000
        local capped = find(ns.Bags.Evaluate().mail, IRON).result
        assert.is_nil(capped.to)
        assert.equal(route.key, capped.capped.key)
        -- without a price source: a green lockbox still goes to the rogue, the green tome stays
        _G.Auctionator = nil
        result = ns.Bags.Evaluate()
        assert.equal(BOB, find(result.mail, IRON).result.to)
        assert.equal("uncommon or better (no price data)", find(result.keep, TOME).result.reason)
    end)

    it("never past a hard keep, a failed price call or a bank pin", function()
        ns.Routes.Add(BOB, "ROGUE")
        ns.Locks.ToggleItem(IRON, WowStub.link(IRON, "Iron Lockbox"), "spec")
        assert.equal("locked", find(ns.Bags.Evaluate().keep, IRON).result.reason)
        ns.Locks.ToggleItem(IRON, WowStub.link(IRON, "Iron Lockbox"), "spec")
        WowStub.setBag(0, 2, WowStub.item(JUNKBOX, "Heavy Iron Junkbox", { quality = 2, sell = 0, class = 15, bound = true }))
        assert.is_nil(find(ns.Bags.Evaluate().mail, JUNKBOX), "soulbound: never mailed")
        ns.Pins.Set(IRON, WowStub.link(IRON, "Iron Lockbox"), ns.Pins.BANK, "spec")
        local pinned = find(ns.Bags.Evaluate().mail, IRON).result
        assert.is_nil(pinned.to, "pinned: the bank alt, not the rogue")
        assert.is_true(pinned.pinned)
        ns.Pins.Set(IRON, WowStub.link(IRON, "Iron Lockbox"), nil, "spec")
        Auctionator.API.v1.GetAuctionPriceByItemLink = function(_, l)
            if l == WowStub.link(IRON, "Iron Lockbox") then error("boom") end
            return prices[l]
        end
        local failed = find(ns.Bags.Evaluate().keep, IRON)
        assert.is_true(failed.result.failed, "the price call failed: it stays, binding or not")
    end)

    it("a lockbox already picked trains nobody: no binding takes it, the normal rule applies", function()
        ns.Routes.Add(BOB, "ROGUE")
        WowStub.state.opened["0:1"] = true
        local result = ns.Bags.Evaluate()
        assert.is_nil(find(result.mail, IRON).result.to)
        assert.equal(BOB, find(result.mail, JUNKBOX).result.to, "the locked one still goes")
        assert.is_true(ns.ClassSkills.Opened(0, 1, IRON))
        assert.is_false(ns.ClassSkills.Opened(0, 2, JUNKBOX))
        -- a bag tooltip that hasn't loaded says nothing: the box counts as locked
        WowStub.state.uncached[IRON] = true
        assert.is_false(ns.ClassSkills.Opened(0, 1, IRON))
        local real = _G.C_TooltipInfo
        _G.C_TooltipInfo = { GetItemByID = real.GetItemByID }
        WowStub.state.uncached[IRON] = nil
        assert.is_false(ns.ClassSkills.Opened(0, 1, IRON), "a client without GetBagItem")
        _G.C_TooltipInfo = real
    end)

    it("locked and unlocked boxes of one kind are valued apart (Codex review)", function()
        WowStub.setBag(0, 6, WowStub.item(IRON, "Iron Lockbox", { quality = 2, sell = 0, class = 15 }))
        WowStub.state.opened["0:6"] = true
        ns.Routes.Add(BOB, "ROGUE")
        local toBob, toAlt = 0, 0
        for _, it in ipairs(ns.Bags.Evaluate().mail) do
            if it.itemID == IRON then
                assert.equal(1, it.stacks)
                if it.result.to == BOB then
                    toBob = toBob + 1
                    assert.same({ { bag = 0, slot = 1, count = 1 } }, it.slots)
                else
                    toAlt = toAlt + 1
                    assert.same({ { bag = 0, slot = 6, count = 1 } }, it.slots)
                end
            end
        end
        assert.same({ 1, 1 }, { toBob, toAlt }, "the locked one to the rogue, the unlocked one on the normal rule")
        be("ROGUE")
        local result = ns.Bags.Evaluate()
        assert.same({ { bag = 0, slot = 1, count = 1 } }, find(result.keep, IRON).slots, "a rogue keeps the locked one")
        assert.equal("your Lockpicking needs it", find(result.keep, IRON).result.reason)
        assert.same({ { bag = 0, slot = 6, count = 1 } }, find(result.mail, IRON).slots)
        assert.is_nil(find(result.mail, IRON).result.to)
    end)

    it("a lockbox's slot is read only where Lockpicking matters (Codex review)", function()
        ns.Bags.Evaluate()
        assert.equal(0, WowStub.state.bagTooltipReads, "no binding, a paladin: nothing read")
        ns.Routes.Add(BOB, "MAGE")
        ns.Bags.Evaluate()
        ns.Bags.Evaluate()
        assert.equal(0, WowStub.state.bagTooltipReads, "a mage's binding only: no lockbox slot is read")
        ns.Routes.Add(BOB, "ROGUE")
        ns.Bags.Evaluate()
        assert.equal(2, WowStub.state.bagTooltipReads, "a rogue's binding: the two lockboxes' slots")
    end)

    it("a rogue's lockbox whose data hasn't loaded is a hard keep: no pick moves it (Codex review)", function()
        be("ROGUE")
        local route = assert(ns.Routes.Add(BOB, "ROGUE"))
        local unloaded = { link = WowStub.link(IRON, "Iron Lockbox"), itemID = IRON, count = 1, stacks = 1, quality = 2,
            vendor = nil, classSkill = "lockpicking", ownSkill = "Lockpicking" }
        local verdict = ns.Valuation.Evaluate(unloaded, nil, ns.Valuation.Settings({}, false))
        assert.equal("item info not loaded yet", verdict.reason)
        assert.is_true(ns.Valuation.HardKeep(verdict))
        route.skill = nil
        assert.same({}, ns.Routes.Choices(unloaded, verdict, nil, {}, { route }))
        unloaded.vendor = 0
        verdict = ns.Valuation.Evaluate(unloaded, nil, ns.Valuation.Settings({}, false))
        assert.equal("your Lockpicking needs it", verdict.reason)
        assert.equal(1, #ns.Routes.Choices(unloaded, verdict, nil, {}, { route }), "loaded: the pick is offered")
    end)

    it("a binding naming this rogue (saved on another character): no pick sends its lockbox to another rogue (Codex review)", function()
        be("ROGUE")
        ns.Routes.Add(BOB, "ROGUE")
        local list = ns.Util.Store(MailworthyDB, "routes", (ns.Util.RealmKey()))
        list[#list + 1] = { to = ns.PlayerName(), class = "ROGUE", cap = 1000, at = 1 }
        local box = find(ns.Bags.Evaluate().keep, IRON)
        assert.equal("your Lockpicking needs it", box.result.reason)
        assert.same({}, box.choices, "no pick button: it is this character's")
        ns.Routes.Pick(box.link, "class:ROGUE|bob surname")
        assert.is_nil(find(ns.Bags.Evaluate().mail, IRON), "a stale pick moves nothing")
        ns.Routes.ClearPicks()
        -- with "Keep my professions' materials" off the binding itself keeps it here, as before
        ns.Routes.Remove("class:ROGUE|bob surname")
        ns.Config.Set("keepProfessionMats", false)
        box = find(ns.Bags.Evaluate().keep, IRON)
        assert.is_truthy(box.result.forMe)
        assert.same({}, box.choices)
    end)

    it("a mage's binding takes Comprehension scrolls unpriced; a plain mage-only item keeps the price rule", function()
        ns.Routes.Add(BOB, "MAGE")
        local result = ns.Bags.Evaluate()
        local scroll = find(result.mail, SCROLL).result
        assert.equal(BOB, scroll.to)
        assert.equal("Comprehension scrolls go to Bob Surname", scroll.reason)
        local tome = find(result.mail, TOME).result
        assert.is_nil(tome.to, "no auction price: the bank alt, never the class binding")
        assert.equal("noprice", tome.route)
        assert.is_nil(find(result.mail, IRON).result.to, "a lockbox isn't the mage's")
        prices[WowStub.link(TOME, "Tome of the Magi")] = 300
        assert.equal(BOB, find(ns.Bags.Evaluate().mail, TOME).result.to, "priced under the cap: the class rule as before")
    end)

    it("a rogue keeps its own lockboxes, a mage its scrolls: me first, the pick and a pin still move them", function()
        be("ROGUE")
        local route = assert(ns.Routes.Add(BOB, "ROGUE"))
        local result = ns.Bags.Evaluate()
        local box = find(result.keep, IRON)
        assert.equal("your Lockpicking needs it", box.result.reason)
        assert.equal("Lockpicking", box.result.neededBy)
        assert.is_nil(ns.Valuation.Verdict(box, false), "no Bank tag: it is picked from the bags")
        assert.is_false(ns.Valuation.BankForCraft(box.result))
        assert.equal("Lockpicking", ns.Bags.ProfessionKeep(box.link, IRON), "PinWarning's conflict")
        assert.is_nil(find(result.mail, SCROLL).result.to, "a rogue doesn't keep a mage's scroll")
        -- the row's button sends it to the other rogue
        assert.equal(route.key, box.choices[1].key)
        ns.Routes.Pick(box.link, route.key)
        assert.equal(BOB, find(ns.Bags.Evaluate().mail, IRON).result.to)
        ns.Routes.ClearPicks()
        -- a bank pin wins, and says what it beat
        ns.Pins.Set(IRON, box.link, ns.Pins.BANK, "spec")
        local pinned = find(ns.Bags.Evaluate().mail, IRON).result
        assert.is_nil(pinned.to)
        assert.equal("Lockpicking", pinned.pinConflict)
        ns.Pins.Set(IRON, box.link, nil, "spec")
        -- an unlocked one isn't kept for Lockpicking
        WowStub.state.opened["0:1"] = true
        assert.is_nil(find(ns.Bags.Evaluate().keep, IRON))
        assert.is_true(find(ns.Bags.Evaluate().mail, IRON).opened)
        WowStub.state.opened["0:1"] = nil
        -- "on my bank alt" doesn't move them: they are picked here
        ns.Config.Set("matsToBankAlt", true)
        assert.equal("your Lockpicking needs it", find(ns.Bags.Evaluate().keep, IRON).result.reason)
        ns.Config.Set("matsToBankAlt", false)
        -- "Keep my professions' materials" off: the binding takes them
        ns.Config.Set("keepProfessionMats", false)
        assert.equal(BOB, find(ns.Bags.Evaluate().mail, IRON).result.to)
        ns.Config.Set("keepProfessionMats", true)
        ns.Routes.Remove(route.key)
        assert.equal("your Lockpicking needs it", find(ns.Bags.Evaluate().keep, IRON).result.reason, "and without a binding")

        be("MAGE")
        result = ns.Bags.Evaluate()
        assert.equal("your Comprehension needs it", find(result.keep, SCROLL).result.reason)
        assert.is_nil(find(result.keep, IRON), "a mage doesn't keep lockboxes")
        assert.equal("Comprehension", ns.Bags.ProfessionKeep(WowStub.link(SCROLL, "Scroll: VOCE WELL"), SCROLL))
        assert.is_nil(ns.Bags.ProfessionKeep(WowStub.link(IRON, "Iron Lockbox"), IRON))
    end)

    it("the friends window says what a rogue's or a mage's items are; /mw report lists what the bags hold", function()
        local options = ns.RoutesUI.Options({ name = BOB, class = "ROGUE", professions = {} })
        assert.equal("Rogue items (lockboxes, and what only a rogue can use)", options[1].text)
        options = ns.RoutesUI.Options({ name = BOB, class = "MAGE", professions = {} })
        assert.equal("Mage items (Comprehension scrolls, and what only a mage can use)", options[1].text)
        options = ns.RoutesUI.Options({ name = BOB, class = "WARRIOR", professions = {} })
        assert.equal("Warrior items (only a warrior can use them)", options[1].text)
        WowStub.state.opened["0:1"] = true
        local line = table.concat(ns.ClassSkills.ReportLines(), "\n")
        assert.truthy(line:find('LOCKED = "Locked"', 1, true))
        assert.truthy(line:find('ITEM_MIN_SKILL = "Requires %s (%d)"', 1, true))
        assert.truthy(line:find("Iron Lockbox.-%(Lockpicking, item ID, 1 of 1 already unlocked: the normal rule%)"))
        assert.truthy(line:find("Heavy Iron Junkbox.-%(Lockpicking, tooltip%)"))
        assert.truthy(line:find("VOCE WELL.-%(Comprehension, tooltip%)"))
        assert.is_nil(line:find("Copper Ore", 1, true))
        _G.LOCKED, _G.ITEM_MIN_SKILL = nil, nil
        line = table.concat(ns.ClassSkills.ReportLines(), "\n")
        assert.truthy(line:find('no LOCKED text, comparing with "Locked"', 1, true))
        assert.truthy(line:find('no ITEM_MIN_SKILL text, comparing with "Requires %s (%d)"', 1, true))
        _G.LOCKED, _G.ITEM_MIN_SKILL = "Locked", "Requires %s (%d)"
        assert.truthy(ns.Report.Build():find("class skills (lockboxes, Comprehension scrolls)", 1, true))
    end)
end)
