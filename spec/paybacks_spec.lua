-- Payback ideas (Paybacks.lua, MailIdeas.lua; phase 3 of docs/RECOMMENDATIONS.md; operator, 2026-11-22): the
-- needs note a sender's Mailworthy whispers with a mail's values, the ideas a crafter's own recipes give for it
-- (a bigger bag, the ammo their weapon fires), the payback pick on a crafted item's row (off until picked), its
-- subject, and the ledger: a payback with no auction price counts its materials, never more than what's owed,
-- on the crafter's side and on the receiver's.
local loadAddon = require("spec.support.load_addon")

local BOB, ME, MALLORY = "Bob Surname", "Rettana Quilwrit", "Mallory Thief"
local BAG, LINEN_BAG, SHOT, BOLT, THREAD = 5763, 4240, 8068, 2997, 2320

describe("payback ideas", function()
    local ns, prices, info

    local function link(id) return WowStub.link(id, info[id] and info[id].name or ("Item " .. id)) end
    local function needs(o)
        o = o or {}
        local text = ns.Paybacks.EncodeNeeds(o.from or BOB, o.to or ME, o.at or WowStub.state.serverTime,
            { level = o.level or 24, class = "HUNTER", bags = o.bags or { 6, 6, 6, 6 }, fires = o.fires == nil and 3 or o.fires })
        return ns.Comms.Hear(o.whisperer or o.from or BOB, text, "WHISPER")
    end
    local function owe(copper)
        ns.Ledger.Store().players["bob surname"] = { name = BOB, received = copper, sent = 0, inItems = {}, outItems = {}, at = 1 }
    end
    local function crafts(list)
        local key = ns.Characters.Key(ns.Characters.Current())
        MailworthyDB.tierCheck = MailworthyDB.tierCheck or {}
        MailworthyDB.tierCheck[key] = { [197] = { rank = 100, crafts = list } }
    end
    local function put(slot, id, count, o)
        o = o or {}
        local it = WowStub.item(id, info[id].name, { count = count or 1, class = info[id].class, subclass = info[id].subclass,
            sell = o.sell or 10, bound = o.bound })
        WowStub.setBag(0, slot, it)
        return it
    end
    local function findRow(itemID)
        local result = ns.Bags.Evaluate()
        for _, list in ipairs({ result.mail, result.keep }) do
            for _, item in ipairs(list) do if item.itemID == itemID then return item end end
        end
    end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.state.level = 30
        WowStub.state.professions = { { index = 6, name = "Tailoring", rank = 100, maxRank = 150, skillLine = 197 } }
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
        info = {
            [BAG] = { name = "Woolen Bag", class = 1, subclass = 0, minLevel = 0, slots = 8 },
            [LINEN_BAG] = { name = "Linen Bag", class = 1, subclass = 0, minLevel = 0, slots = 6 },
            [SHOT] = { name = "Crafted Heavy Shot", class = 6, subclass = 3, minLevel = 15 },
            [BOLT] = { name = "Bolt of Woolen Cloth", class = 7, subclass = 5, minLevel = 0 },
            [THREAD] = { name = "Coarse Thread", class = 7, subclass = 11, minLevel = 0 },
        }
        local getInfo = _G.GetItemInfo
        _G.GetItemInfo = function(l)
            local id = tonumber(type(l) == "number" and l or tostring(l):match("item:(%d+)"))
            local i = id and info[id]
            if i then return i.name, link(id), 1, 1, i.minLevel, "t", "s", 20, "", 0, 10, i.class, i.subclass end
            return getInfo(l)
        end
        _G.CONTAINER_SLOTS = "%d Slot %s"
        WowStub.state.tooltipLines[BAG] = { "8 Slot Bag" }
        WowStub.state.tooltipLines[LINEN_BAG] = { "6 Slot Bag" }
        crafts({ [BAG] = { recipe = "Woolen Bag", reagents = { [BOLT] = 3, [THREAD] = 1 } },
            [LINEN_BAG] = { recipe = "Linen Bag", reagents = { [THREAD] = 1 } },
            [SHOT] = { recipe = "Crafted Heavy Shot", reagents = { [THREAD] = 2 } } })
        prices[link(BOLT)] = 300
        prices[link(THREAD)] = 50
        MailFrame:Show()
        SendMailFrame:Show()
        ns.Fire("MAIL_SHOW")
    end)
    after_each(function()
        _G.Auctionator, _G.CONTAINER_SLOTS = nil, nil
        ns.Paybacks.Reset()
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    describe("the needs note", function()
        local function sendByHand(to)
            WowStub.state.attached = { WowStub.item(2589, "Linen Cloth", { count = 20 }) }
            WowStub.state.money = 0
            ns.Fire("MAIL_SEND_INFO_UPDATE")
            SendMail(to, "for you", "")
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        local function queued(name)
            local out = {}
            for _, item in ipairs(ns.Ledger.Store().outbox[name:lower()] or {}) do
                for _, m in ipairs(item.messages) do if m:find("^N2|") then out[#out + 1] = m end end
            end
            return out
        end

        it("goes with a counted mail's values: level, class, bag sizes, the ammo it fires; once a session", function()
            WowStub.state.numSlots = { [0] = 16, [1] = 6, [2] = 6, [3] = 8, [4] = 0 }
            sendByHand(BOB)
            local list = queued(BOB)
            assert.equal(1, #list)
            assert.truthy(list[1]:find("^N2|Rettana Quilwrit|Bob Surname|%d+|30|PALADIN|6,6,8,0|0$"), list[1])
            sendByHand(BOB)
            assert.equal(1, #queued(BOB), "one a session")
        end)

        it("not with Settings > Tell crafters off, nor to this account's own characters", function()
            ns.Config.Set("hideNeeds", true)
            sendByHand(BOB)
            assert.equal(0, #queued(BOB))
            ns.Config.Set("hideNeeds", false)
            sendByHand("Roknua Themicrulah") -- the bank alt: not counted, no note
            assert.equal(0, #queued("Roknua Themicrulah"))
        end)

        it("is kept only from the character it names, for one of this account's characters, newest first", function()
            assert.is_nil(needs({ whisperer = MALLORY }), "Mallory can't speak for Bob")
            assert.is_nil(needs({ to = "Someone Else" }), "not for this account")
            assert.truthy(needs())
            assert.equal(24, ns.Paybacks.Needs()["bob surname"].level)
            assert.is_nil(needs({ level = 20, at = WowStub.state.serverTime - 100 }), "an older note")
            assert.is_nil(needs({ at = WowStub.state.serverTime - 31 * 86400 }), "past 30 days")
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", ns.Paybacks.EncodeNeeds(BOB, ME, WowStub.state.serverTime + 5,
                { level = 26, bags = { 6, 6, 6, 6 } }), "GUILD", BOB)
            assert.equal(24, ns.Paybacks.Needs()["bob surname"].level, "whispered only")
        end)
    end)

    describe("the ideas (pure)", function()
        local function ideas(n)
            return ns.Paybacks.Ideas(n, ns.TierCheck.MyCrafts(), ns.Paybacks.Facts, function(id)
                return ({ [BOLT] = 13, [THREAD] = 6 })[id] or 0
            end)
        end

        it("a bag bigger than their smallest, up to one per smaller bag; the same size is a note", function()
            local list, notes = ideas({ name = BOB, level = 24, bags = { 6, 6, 6, 6 } })
            assert.equal(1, #list)
            assert.equal(BAG, list[1].itemID)
            assert.equal(4, list[1].want)
            assert.equal(4, list[1].canMake, "13 bolts: 4 bags; 6 thread")
            assert.equal("Bob's smallest bag holds 6; this one holds 8", list[1].why)
            assert.same({ { name = "Crafted Heavy Shot", why = "Bob has no bow or gun equipped" },
                { name = "Linen Bag", why = "6 slots: no bigger than Bob's" } }, notes)
            -- The best of a kind only (2026-11-22, the rest of the table): the bigger bag, not both.
            local withEmpty = ideas({ name = BOB, level = 24, bags = { 6, 6, 6, 0 } })
            assert.equal(1, #withEmpty)
            assert.equal("Bob has an empty bag slot; this one holds 8", withEmpty[1].why)
        end)

        it("the ammo their ranged weapon fires, for their level (no more than 10 under)", function()
            local list = ideas({ name = BOB, level = 24, bags = { 8, 8, 8, 8 }, fires = 3 })
            assert.equal(SHOT, list[1].itemID)
            assert.equal("Bob's ranged weapon fires bullets", list[1].why)
            assert.equal(0, #ideas({ name = BOB, level = 24, bags = { 8, 8, 8, 8 }, fires = 2 }), "arrows: a bow")
            assert.equal(0, #ideas({ name = BOB, level = 30, bags = { 8, 8, 8, 8 }, fires = 3 }), "too low for 30")
            assert.equal(0, #ideas({ name = BOB, level = 12, bags = { 8, 8, 8, 8 }, fires = 3 }), "too high for 12")
        end)

        it("what's missing when the bags can't make one", function()
            local list = ns.Paybacks.Ideas({ name = BOB, level = 24, bags = { 6, 6, 6, 6 } }, ns.TierCheck.MyCrafts(),
                ns.Paybacks.Facts, function(id) return id == BOLT and 2 or 0 end)
            assert.equal(0, list[1].canMake)
            table.sort(list[1].missing, function(a, b) return a.itemID < b.itemID end)
            assert.same({ { itemID = THREAD, need = 1 }, { itemID = BOLT, need = 1 } }, list[1].missing)
        end)

        it("a bag's slots come from its tooltip line", function()
            assert.equal(8, ns.Paybacks.SlotsFromLine("8 Slot Bag", "%d Slot %s"))
            assert.equal(14, ns.Paybacks.SlotsFromLine("14 Slot Bag"))
            assert.is_nil(ns.Paybacks.SlotsFromLine("Binds when equipped", "%d Slot %s"))
        end)
    end)

    describe("the rest of the table (2026-11-22)", function()
        -- Made-up item facts, by kind (the pure check reads only these).
        local F = {
            [2300] = { name = "Embossed Leather Vest", classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST", minLevel = 20,
                itemLevel = 25 },
            [6238] = { name = "Brown Linen Robe", classID = 4, subclassID = 1, equipLoc = "INVTYPE_ROBE", minLevel = 20, itemLevel = 25 },
            [2580] = { name = "Reinforced Linen Cape", classID = 4, subclassID = 1, equipLoc = "INVTYPE_CLOAK", minLevel = 18,
                itemLevel = 23 },
            [7278] = { name = "Light Leather Quiver", classID = 11, subclassID = 2, minLevel = 0, itemLevel = 15, slots = 10 },
            [7279] = { name = "Small Leather Ammo Pouch", classID = 11, subclassID = 3, minLevel = 0, itemLevel = 15, slots = 10 },
            [2863] = { name = "Coarse Sharpening Stone", classID = 7, subclassID = 0, minLevel = 0, itemLevel = 20 },
            [3240] = { name = "Coarse Weightstone", classID = 7, subclassID = 0, minLevel = 0, itemLevel = 20 },
            [4406] = { name = "Standard Scope", classID = 0, subclassID = 8, minLevel = 0, itemLevel = 22 },
            [929] = { name = "Healing Potion", classID = 0, subclassID = 1, minLevel = 22, itemLevel = 22 },
            [3827] = { name = "Mana Potion", classID = 0, subclassID = 1, minLevel = 22, itemLevel = 22 },
            [5527] = { name = "Goblin Deviled Clams", classID = 0, subclassID = 5, minLevel = 20, itemLevel = 25 },
            [118] = { name = "Minor Healing Potion", classID = 0, subclassID = 1, minLevel = 1, itemLevel = 5 },
            [3531] = { name = "Heavy Wool Bandage", classID = 0, subclassID = 7, minLevel = 0, itemLevel = 20 },
            [11287] = { name = "Lesser Magic Wand", classID = 2, subclassID = 19, minLevel = 18, itemLevel = 23 },
        }
        local function all()
            local c = {}
            for id in pairs(F) do c[id] = { recipe = F[id].name, reagents = { [THREAD] = 1 } } end
            return c
        end
        local function kinds(n)
            local list, notes = ns.Paybacks.Ideas(n, all(), function(id) return F[id] end, function() return 9 end)
            local out = {}
            for _, idea in ipairs(list) do out[#out + 1] = idea.kind .. ":" .. idea.name end
            return out, notes
        end
        local function hunter(o)
            local n = { name = BOB, level = 24, class = "HUNTER", bags = { 16, 16, 16, 16 }, ranged = "bow", quiver = 0,
                main = "blade", empty = { 5, 15 } }
            for k, v in pairs(o or {}) do n[k] = v end
            return n
        end

        it("a hunter: a quiver, a vest of the leather they wear, a cloak; best first, three at most", function()
            local list, notes = kinds(hunter())
            assert.same({ "quiver:Light Leather Quiver", "armor:Embossed Leather Vest", "armor:Reinforced Linen Cape" }, list)
            local robe
            for _, note in ipairs(notes) do if note.name == "Brown Linen Robe" then robe = note.why end end
            assert.equal("Bob wears leather", robe)
        end)

        it("a gun takes an ammo pouch; a quiver as big as the one they have is left out", function()
            assert.equal("quiver:Small Leather Ammo Pouch", (kinds(hunter({ ranged = "gun" })))[1])
            assert.equal("armor:Embossed Leather Vest", (kinds(hunter({ quiver = 12 })))[1])
        end)

        it("stones for the main hand, a scope for a bow, potions, food and bandages for the level", function()
            local n = hunter({ quiver = 20, empty = {} })
            assert.same({ "scope:Standard Scope", "stone:Coarse Sharpening Stone", "potion:Healing Potion" }, (kinds(n)),
                "one potion idea: healing first, anyone drinks it")
            local mages = ns.Paybacks.Ideas({ name = BOB, level = 24, class = "MAGE", bags = { 16, 16, 16, 16 }, ranged = "wand" },
                { [3827] = { reagents = {} } }, function(id) return F[id] end, function() return 0 end)
            assert.equal("Mana Potion", mages[1].name, "a mana potion for a class with mana")
            local warriors = ns.Paybacks.Ideas({ name = BOB, level = 24, class = "WARRIOR", bags = { 16, 16, 16, 16 } },
                { [3827] = { reagents = {} } }, function(id) return F[id] end, function() return 0 end)
            assert.equal(0, #warriors, "never for a warrior")
            n.main = "blunt"
            assert.equal("stone:Coarse Weightstone", (kinds(n))[2])
            local warrior = { name = BOB, level = 24, class = "WARRIOR", bags = { 16, 16, 16, 16 }, empty = {} }
            assert.same({ "potion:Healing Potion", "food:Goblin Deviled Clams", "bandage:Heavy Wool Bandage" }, (kinds(warrior)),
                "a warrior has no mana; too low a level (Minor Healing Potion) is left out")
        end)

        it("a wand for a wand user with an empty ranged slot; never for one with a ranged weapon", function()
            local mage = { name = BOB, level = 24, class = "MAGE", bags = { 16, 16, 16, 16 }, empty = {} }
            assert.equal("wand:Lesser Magic Wand", (kinds(mage))[1])
            mage.ranged = "wand"
            assert.are_not.equal("wand:Lesser Magic Wand", (kinds(mage))[1])
        end)

        it("the armor a class wears best, by level", function()
            assert.equal(3, ns.Paybacks.ArmorFor("WARRIOR", 39))
            assert.equal(4, ns.Paybacks.ArmorFor("PALADIN", 40))
            assert.equal(2, ns.Paybacks.ArmorFor("SHAMAN", 20))
            assert.equal(3, ns.Paybacks.ArmorFor("HUNTER", 40))
            assert.equal(1, ns.Paybacks.ArmorFor("PRIEST", 60))
            assert.is_nil(ns.Paybacks.ArmorFor(nil, 60))
        end)

        it("the gear note: read from what's worn, sent with the needs note, kept with it", function()
            WowStub.state.equipped[16] = WowStub.item(2488, "Gladius", { class = 2, subclass = 7 })
            WowStub.state.equipped[18] = WowStub.item(2508, "Old Blunderbuss", { class = 2, subclass = 3 })
            WowStub.state.equipped[5] = WowStub.item(2300, "Vest", { class = 4, subclass = 2 })
            local gear = ns.Paybacks.MyGear()
            assert.equal("blade", gear.main)
            assert.equal("gun", gear.ranged)
            assert.same({ 1, 3, 4, 6, 7, 8, 9, 10, 15 }, gear.empty)
            ns.Ledger.RecordSent({ to = BOB, subject = "for you", items = { { itemID = 2589, link = "[x]", count = 20 } } }, "mail")
            local found = {}
            for _, item in ipairs(ns.Ledger.Store().outbox["bob surname"] or {}) do
                for _, m in ipairs(item.messages) do found[m:sub(1, 2)] = true end
            end
            assert.is_true(found.N2 and found.E2, "both notes wait for Bob")
            needs()
            ns.Comms.Hear(BOB, ns.Paybacks.EncodeGear(BOB, ME, WowStub.state.serverTime, { main = "blunt", empty = { 15 } }), "WHISPER")
            assert.is_nil(ns.Comms.Hear(MALLORY, ns.Paybacks.EncodeGear(BOB, ME, WowStub.state.serverTime, { main = "blade" }), "WHISPER"))
            local kept = ns.Paybacks.Needs()["bob surname"]
            assert.equal(24, kept.level, "the needs note stays")
            assert.equal("blunt", kept.main)
            assert.same({ 15 }, kept.empty)
        end)

        describe("Codex review (2026-11-22)", function()
            local NOW = function() return WowStub.state.serverTime end
            local function gear(at, g)
                return ns.Comms.Hear(BOB, ns.Paybacks.EncodeGear(BOB, ME, at, g or { main = "blade", empty = { 15 } }), "WHISPER")
            end

            it("a quiver for their level: never one they can't wear yet", function()
                F[7280] = { name = "Quickdraw Quiver", classID = 11, subclassID = 2, minLevel = 40, itemLevel = 45, slots = 18 }
                local list = kinds(hunter())
                F[7280] = nil
                assert.equal("quiver:Light Leather Quiver", list[1], "the level-40 one is left out, the small one stays")
            end)

            it("a gear note redraws the open mailbox, as the needs note does", function()
                local refresh, calls = ns.MailWindow.RefreshIfShown, 0
                ns.MailWindow.RefreshIfShown = function() calls = calls + 1 end
                needs()
                gear(NOW())
                ns.MailWindow.RefreshIfShown = refresh
                assert.equal(2, calls)
            end)

            it("a gear note heard first never blocks an earlier needs note", function()
                gear(NOW())
                assert.truthy(needs({ at = NOW() - 1 }))
                local kept = ns.Paybacks.Needs()["bob surname"]
                assert.equal(24, kept.level)
                assert.equal("blade", kept.main)
            end)

            it("each note expires on its own: a fresh needs note doesn't keep an old gear note's facts", function()
                gear(NOW() - 20 * 86400)
                needs()
                local store = ns.Ledger.Store().needs["bob surname"]
                store.gearAt = NOW() - 31 * 86400 -- the gear note is past 30 days now
                local kept = ns.Paybacks.Needs()["bob surname"]
                assert.equal(24, kept.level)
                assert.is_nil(kept.main)
                assert.is_nil(kept.empty)
            end)
        end)

        it("pay back in kind: a player you owe whose profession uses something here, for this visit", function()
            owe(5000)
            ns.Comms.UpdatePeer(BOB, { name = BOB, professions = { 164 } }, true)
            WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }))
            prices[WowStub.link(2770, "Copper Ore")] = 174
            local list = ns.Routes.Suggestions(ns.Bags.Evaluate(), ns.Config.BankAlt())
            assert.equal(BOB, list[1].name)
            assert.is_true(list[1].owed)
            assert.equal("visit", list[1].scope)
            assert.truthy(ns.MailWindow.OfferText(list[1]):find("you owe. Pay back in kind: send them Copper Ore x20?", 1, true),
                ns.MailWindow.OfferText(list[1]))
            ns.Ledger.MarkPaid(BOB)
            assert.equal(0, #ns.Routes.Suggestions(ns.Bags.Evaluate(), ns.Config.BankAlt()), "nothing owed: not suggested")
        end)
    end)

    describe("at the crafter's mailbox", function()
        before_each(function()
            owe(17400)
            needs()
            put(10, BOLT, 13)
            put(11, THREAD, 6)
        end)

        it("the ideas show under the owed notice; Not for <name> hides one; Fold folds them", function()
            _G.MailworthyMailButton:Click()
            local list, who = ns.MailWindow.Ideas()
            assert.equal(BOB, who)
            assert.equal(BAG, list[1].itemID)
            assert.is_true(_G.MailworthyMailIdeaNot1:IsShown())
            assert.equal("Not for Bob", _G.MailworthyMailIdeaNot1:GetText())
            assert.equal("|cffffd100Woolen Bag|r: Bob's smallest bag holds 6; this one holds 8 (up to 4). Each: 1 Coarse Thread,"
                .. " 3 Bolt of Woolen Cloth; you have enough for 4.",
                ns.MailWindow.IdeaText(list[1], function(id) return info[id].name end))
            _G.MailworthyMailIdeasFold:Click()
            assert.is_false(_G.MailworthyMailIdeaNot1:IsShown())
            _G.MailworthyMailIdeasFold:Click()
            _G.MailworthyMailIdeaNot1:Click()
            assert.is_true(ns.Paybacks.Declined(BOB, BAG))
            assert.equal(SHOT, (ns.MailWindow.Ideas())[1].itemID, "next: the bullets his gun fires")
            _G.MailworthyMailIdeaNot1:Click()
            assert.is_false(_G.MailworthyMailIdeaNot1:IsShown(), "no idea left for Bob")
        end)

        it("nothing once nothing is owed, or with the switch off", function()
            ns.Ledger.MarkPaid(BOB)
            _G.MailworthyMailButton:Click()
            assert.is_nil((ns.MailWindow.Ideas())[1])
            owe(17400)
            MailworthyDB.features = { paybacks = false }
            ns.MailWindow.Refresh()
            assert.is_false(_G.MailworthyMailIdeaNot1:IsShown())
        end)

        it("a made item's row offers Bob after Me; picked, it mails to him as a payback, subject and all", function()
            put(12, BAG, 1)
            local row = findRow(BAG)
            assert.equal("payback|bob surname", row.choices[#row.choices].key)
            assert.are_not.equal(BOB, row.result.to, "off until picked")
            ns.Routes.Pick(row.link, "payback|bob surname")
            row = findRow(BAG)
            assert.equal(BOB, row.result.to)
            assert.equal("payback", row.result.route)
            assert.equal("Bob", ns.Routes.PickLabel(row.pickState, row.choices))
            local mails = ns.Mailer.Plan({ row }, "Roknua Themicrulah")
            assert.equal("Mailworthy: made for you (Woolen Bag)", ns.Mailer.Subject(mails, 1))
            assert.is_true(mails[1].payback)
        end)

        it("never on a locked, soulbound or pinned item", function()
            put(12, BAG, 1, { bound = true })
            assert.is_nil(findRow(BAG), "soulbound: not on the lists at all")
            put(12, BAG, 1)
            ns.Locks.ToggleItem(BAG, link(BAG), "spec")
            local row = findRow(BAG)
            assert.equal(0, #(row.choices or {}))
        end)

        it("sent with no auction price: counts its materials (3 bolts + 1 thread), never more than what's owed", function()
            assert.equal(950, ns.Paybacks.MaterialsValue(BAG))
            ns.Ledger.RecordSent({ to = BOB, subject = "Mailworthy: made for you (Woolen Bag)", payback = true,
                items = { { itemID = BAG, link = link(BAG), count = 2 } } }, "Mailworthy")
            assert.equal(17400 - 1900, (ns.Ledger.Net(BOB)))
            local log = ns.Ledger.Store().log
            assert.equal("craft", log[#log].items[1].source)
            owe(500)
            ns.Ledger.RecordSent({ to = BOB, subject = "Mailworthy: made for you (Woolen Bag)", payback = true,
                items = { { itemID = BAG, link = link(BAG), count = 1 } } }, "Mailworthy")
            assert.equal(0, (ns.Ledger.Net(BOB)), "capped at what was owed: no debt the other way")
            ns.Ledger.RecordSent({ to = BOB, subject = "for you", items = { { itemID = BAG, link = link(BAG), count = 1 } } }, "mail")
            assert.is_nil(ns.Ledger.Store().log[#ns.Ledger.Store().log].items[1].value, "not a payback: unpriced as before")
        end)

        it("the profession window: one chat line a session with what can be made now", function()
            ns.Fire("MAIL_CLOSED")
            MailFrame:Hide()
            ns.Fire("TRADE_SKILL_SHOW")
            WowStub.runTimers(2)
            local said = 0
            for _, line in ipairs(WowStub.printed) do
                if line:find("Payback idea for Bob Surname: Woolen Bag (materials for 4)", 1, true) then said = said + 1 end
            end
            assert.equal(1, said)
            ns.Fire("TRADE_SKILL_SHOW")
            WowStub.runTimers(2)
            local again = 0
            for _, line in ipairs(WowStub.printed) do if line:find("Payback idea", 1, true) then again = again + 1 end end
            assert.equal(1, again, "once a session")
        end)
    end)

    describe("Codex review (2026-11-22)", function()
        local function payback(count)
            return ns.Ledger.RecordSent({ to = BOB, subject = "Mailworthy: made for you (Woolen Bag)", payback = true,
                items = { { itemID = BAG, link = link(BAG), count = count or 1 } } }, "Mailworthy")
        end

        it("once the cap is used up, the rest still goes as a craft value of 0 (never priced the receiver's way)", function()
            owe(500)
            local entry = ns.Ledger.RecordSent({ to = BOB, subject = "Mailworthy: made for you (Woolen Bag)", payback = true,
                items = { { itemID = BAG, link = link(BAG), count = 1 }, { itemID = BAG, link = link(BAG), count = 1 } } },
                "Mailworthy")
            assert.equal(500, entry.items[1].value)
            assert.equal(0, entry.items[2].value)
            assert.equal("craft", entry.items[2].source)
            local msgs = ns.Ledger.EncodeValues(ME, BOB, entry.at, entry.id, entry.items)
            assert.truthy(msgs[1]:find(BAG .. ":1:0:c:2", 1, true), msgs[1])
        end)

        it("a craft that makes several shares its materials among them", function()
            crafts({ [SHOT] = { recipe = "Crafted Heavy Shot", reagents = { [THREAD] = 2 }, yield = 2 } })
            assert.equal(50, ns.Paybacks.MaterialsValue(SHOT), "2 thread (100c) for 2 rounds")
        end)

        it("a payback returned to this account undoes what it counted", function()
            owe(500)
            payback(1)
            assert.equal(0, (ns.Ledger.Net(BOB)))
            WowStub.state.inbox = { { sender = BOB, subject = "Mailworthy: made for you (Woolen Bag)", returned = true,
                daysLeft = 29.9, items = { { itemID = BAG, name = "Woolen Bag", count = 1 } } } }
            TakeInboxItem(1, 1)
            ns.Fire("MAIL_SUCCESS", BAG)
            WowStub.runTimers(2)
            assert.equal(500, (ns.Ledger.Net(BOB)), "owed again")
        end)

        it("the receiver's lower answer for a craft value is taken, however low", function()
            owe(500)
            local entry = payback(1)
            assert.equal(0, (ns.Ledger.Net(BOB)))
            ns.Comms.Hear(BOB, ns.Ledger.EncodeAnswers(BOB, ME, entry.id, { { itemID = BAG, count = 1, value = 100, k = 1 } })[1],
                "WHISPER")
            assert.equal(400, (ns.Ledger.Net(BOB)), "both sides count 100c")
        end)

        it("only the professions this character has now", function()
            WowStub.state.professions = { { index = 6, name = "Mining", rank = 12, maxRank = 75, skillLine = 186 } }
            assert.same({}, ns.TierCheck.MyCrafts(), "Tailoring was dropped: its recipes don't count")
            owe(17400)
            needs()
            assert.same({}, ns.Paybacks.Targets())
        end)
    end)

    describe("at the receiver's side", function()
        it("a materials value counts at most what the crafter owed this account", function()
            -- This account sent Bob 10s of cloth; Bob pays back with a bag his Mailworthy values at 35s of materials.
            ns.Ledger.Store().players["bob surname"] = { name = BOB, received = 0, sent = 1000, inItems = {}, outItems = {}, at = 1 }
            ns.Comms.Hear(BOB, "M2|Bob Surname|Rettana Quilwrit|" .. WowStub.state.serverTime .. "|43|" .. BAG .. ":1:3500:c:1", "WHISPER")
            WowStub.state.inbox = { { sender = BOB, subject = "Mailworthy: made for you (Woolen Bag)", daysLeft = 29.9,
                items = { { itemID = BAG, name = "Woolen Bag", count = 1 } } } }
            TakeInboxItem(1, 1)
            ns.Fire("MAIL_SUCCESS", BAG)
            WowStub.runTimers(2)
            local log = ns.Ledger.Store().log
            assert.equal(1000, log[#log].items[1].value)
            assert.equal("capped", log[#log].items[1].source)
            assert.equal(0, (ns.Ledger.Net(BOB)), "cleared, never a debt to Bob")
            WowStub.runTimers(ns.Ledger.CHAT_DELAY or 5)
            local made = false
            for _, line in ipairs(WowStub.printed) do made = made or line:find("Bob Surname made you 1 Woolen Bag", 1, true) ~= nil end
            assert.is_true(made, "the chat line says he made it")
        end)
    end)
end)
