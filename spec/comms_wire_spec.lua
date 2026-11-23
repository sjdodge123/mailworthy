-- The addon-message wire, kind by kind (UX and architecture review A6: each module registers the
-- kinds it owns with Comms.Register). Older Mailworthys in the wild read and send these exact
-- strings: every encoder's output below was captured from the build before the registry and must
-- stay byte-identical, decode back to the same message, and reach the module that owns its kind.
-- A hello's follow-ups go in the same order, on the same channels.
local loadAddon = require("spec.support.load_addon")

describe("addon message wire", function()
    local ns
    local ENCHANTING, TAILORING, ALCHEMY = 333, 197, 171
    local GM, BOB, ME = "Guild Master", "Bob Surname", "Rettana Quilwrit"
    local NOW = 1791900000
    local REV = NOW - 60

    -- What the build before the registry sent, byte for byte.
    local WIRE = {
        H = "H2|197,333|Bob Alt=171",
        A = "A2",
        S = "S2|129:80,197:130|Bob Alt=171:150,333:120",
        F = "F2|20740",
        U = "U2|v0.31.0",
        G = "G2|1791900000|1/1|40|1791800000|0:15;1:25",
        T1 = "T2|1791899940|Guild Master|1/2|333=Bob Surname:50001",
        T2 = "T2|1791899940|Guild Master|2/2|171=Ann Herbal:0",
        T0 = "T2|1791899940|Guild Master|0/0|",
        Q = "Q2|1791899940",
        M = "M2|Bob Surname|Rettana Quilwrit|1791900000|42|2589:20:1000:3:1;2770:20:1200::1;2589:20:1000::2",
        R = "R2|Rettana Quilwrit|Bob Surname|42|2589:20:900:2",
        V = "V2|Bob Surname|Rettana Quilwrit|1791900000|2589:20:1000:3;2770:20:1200",
        -- Payback ideas (2026-11-22): the needs note, and a payback valued by its materials ("c" for the age),
        -- in a message of its own so an older Mailworthy drops only that one.
        N = "N2|Bob Surname|Rettana Quilwrit|1791900000|24|HUNTER|6,6,6,0|3",
        MC = "M2|Bob Surname|Rettana Quilwrit|1791900000|43|5763:1:3500:c:1",
        -- The gear note (2026-11-22, the rest of the payback table): a kind of its own beside N2.
        E = "E2|Bob Surname|Rettana Quilwrit|1791900000|blade|gun|0|4,15",
    }

    before_each(function()
        ns = loadAddon()
        WowStub.state.serverTime = NOW
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", rank = 3, members = {
            { name = GM, rank = 0, online = true }, { name = BOB, rank = 3, online = true },
            { name = ME, rank = 3, online = true },
        } }
        ns.Fire("PLAYER_LOGIN")
        WowStub.state.addonMessages = {}
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("every kind is registered by the module that owns it", function()
        local kinds, order = ns.Comms.Kinds()
        local owners = { H = false, A = false, S = false, T = "Guild", Q = "Guild", F = "Stale", U = "Version",
            M = "Ledger", V = "Ledger", R = "Ledger", G = "Contributions", N = "Paybacks", E = "Paybacks" }
        for letter, module in pairs(owners) do
            assert.is_table(kinds[letter], letter)
            assert.equal(module or nil, kinds[letter].module, letter)
        end
        assert.same({ "H", "A", "S", "T", "Q", "F", "U", "M", "V", "R", "G", "N", "E" }, order, "the .toc order")
        assert.same({ WHISPER = true }, kinds.N.channels)
        assert.same({ WHISPER = true }, kinds.E.channels)
        assert.same({ GUILD = true }, kinds.G.channels)
        for _, letter in ipairs({ "M", "V", "R" }) do assert.same({ WHISPER = true }, kinds[letter].channels, letter) end
    end)

    it("hello, ask and skills: byte-identical and decoded back", function()
        local hello = ns.Comms.Encode({ { skillLine = ENCHANTING }, { skillLine = TAILORING }, { skillLine = 999 } },
            { { name = "Bob Alt", professions = { { skillLine = ALCHEMY } } },
                { name = "Bad=Name", professions = { { skillLine = 165 } } }, { name = "No Craft", professions = {} } })
        assert.equal(WIRE.H, hello)
        assert.same({ kind = "hello", version = 2, professions = { TAILORING, ENCHANTING },
            characters = { { name = "Bob Alt", professions = { ALCHEMY } } } }, ns.Comms.Decode(hello))
        assert.same({ kind = "ask", version = 2 }, ns.Comms.Decode(WIRE.A))
        local skills = ns.Comms.EncodeSkills({ { skillLine = TAILORING, rank = 130 }, { skillLine = 129, rank = 80.6 } },
            { { name = "Bob Alt", professions = { { skillLine = ALCHEMY, rank = 150 }, { skillLine = ENCHANTING, rank = 120 } } } })
        assert.equal(WIRE.S, skills)
        assert.same({ kind = "skills", version = 2, skills = { [129] = 80, [TAILORING] = 130 },
            characters = { { name = "Bob Alt", skills = { [ALCHEMY] = 150, [ENCHANTING] = 120 } } } }, ns.Comms.Decode(skills))
        assert.same({ kind = "skills", version = 2, skills = { [ENCHANTING] = 50 }, characters = {} },
            ns.Comms.Decode("S2|186:50,333:50|"), "a skill line Mailworthy does not know is dropped")
    end)

    it("scan day and release: byte-identical and decoded back", function()
        assert.equal(WIRE.F, ns.Stale.Encode(20740))
        assert.same({ kind = "fresh", version = 2, day = 20740 }, ns.Comms.Decode(WIRE.F))
        ns.VERSION = "v0.31.0"
        assert.equal(WIRE.U, ns.Version.Message())
        assert.same({ kind = "release", version = 2, release = "v0.31.0" }, ns.Comms.Decode(WIRE.U))
    end)

    it("guild template and ask, guild giving: byte-identical and decoded back", function()
        local t = ns.Guild.Encode(REV, GM, { { profession = ENCHANTING, to = BOB, cap = 50000, gear = ns.Routes.GEAR_DE },
            { profession = ALCHEMY, to = "Ann Herbal" } })
        assert.same({ WIRE.T1, WIRE.T2 }, t)
        assert.same({ WIRE.T0 }, ns.Guild.Encode(REV, GM, {}))
        assert.same({ kind = "template", version = 2, part = { rev = REV, author = GM, index = 1, count = 2,
            rule = { profession = ENCHANTING, to = BOB, cap = 50000, gear = ns.Routes.GEAR_DE } } }, ns.Comms.Decode(WIRE.T1))
        assert.same({ kind = "template", version = 2, part = { rev = REV, author = GM, index = 0, count = 0 } },
            ns.Comms.Decode(WIRE.T0))
        assert.same({ kind = "templateAsk", version = 2, rev = REV }, ns.Comms.Decode(WIRE.Q))
        assert.same({ WIRE.G }, ns.Contributions.Encode({ total = 40, since = NOW - 100000,
            days = { [math.floor(NOW / 86400) - 1] = 25, [math.floor(NOW / 86400)] = 15 } }, NOW))
        assert.same({ kind = "giving", version = 2, part = { asOf = NOW, index = 1, count = 1, total = 40, since = NOW - 100000,
            days = { { back = 0, units = 15 }, { back = 1, units = 25 } } } }, ns.Comms.Decode(WIRE.G))
    end)

    it("ledger values and answers: byte-identical and decoded back; v0.25.0's V2 still read", function()
        assert.same({ WIRE.M }, ns.Ledger.EncodeValues(BOB, ME, NOW, 42, { { itemID = 2589, count = 20, value = 1000, age = 3 },
            { itemID = 2770, count = 20, value = 1200 }, { itemID = 2589, count = 20, value = 1000 } }))
        assert.same({ kind = "values", version = 2, values = { from = BOB, to = ME, at = NOW, id = 42, items = {
            { itemID = 2589, count = 20, value = 1000, age = 3, k = 1 }, { itemID = 2770, count = 20, value = 1200, k = 1 },
            { itemID = 2589, count = 20, value = 1000, k = 2 } } } }, ns.Comms.Decode(WIRE.M))
        assert.same({ WIRE.R }, ns.Ledger.EncodeAnswers(ME, BOB, 42, { { itemID = 2589, count = 20, value = 900, k = 2 } }))
        assert.same({ kind = "answers", version = 2, answers = { receiver = ME, from = BOB, id = 42, items = {
            { itemID = 2589, count = 20, value = 900, k = 2 } } } }, ns.Comms.Decode(WIRE.R))
        assert.same({ kind = "values", version = 2, values = { from = BOB, to = ME, at = NOW, items = {
            { itemID = 2589, count = 20, value = 1000, age = 3 }, { itemID = 2770, count = 20, value = 1200 } } } },
            ns.Comms.Decode(WIRE.V))
    end)

    it("the needs note and a payback's materials value: byte-identical and decoded back", function()
        assert.equal(WIRE.N, ns.Paybacks.EncodeNeeds(BOB, ME, NOW, { level = 24, class = "HUNTER", bags = { 6, 6, 6, 0 }, fires = 3 }))
        assert.same({ kind = "needs", version = 2, needs = { from = BOB, to = ME, at = NOW, level = 24, class = "HUNTER",
            bags = { 6, 6, 6, 0 }, fires = 3 } }, ns.Comms.Decode(WIRE.N))
        assert.equal("N2|Bob Surname|Rettana Quilwrit|1791900000|5|-|0,0,0,0|0",
            ns.Paybacks.EncodeNeeds(BOB, ME, NOW, { level = 5, bags = {} }), "no class, no bags, no ranged weapon")
        assert.is_nil(ns.Comms.Decode("N2|Bob Surname|Rettana Quilwrit|1791900000|24|HUNTER|6,6,6|3"), "four bags")
        assert.is_nil(ns.Comms.Decode("N2|Bob Surname|Rettana Quilwrit|1791900000|24|HUNTER|6,6,6,99|3"), "no such bag")
        assert.is_nil(ns.Comms.Decode("N2|Bob Surname|Rettana Quilwrit|1791900000|24|HUNTER|6,6,6,6|5"), "no such ammo")
        -- The materials value goes after the mail's other values, in a message of its own.
        assert.same({ "M2|Bob Surname|Rettana Quilwrit|1791900000|43|2589:20:1000:3:1", WIRE.MC },
            ns.Ledger.EncodeValues(BOB, ME, NOW, 43, { { itemID = 5763, count = 1, value = 3500, source = "craft" },
                { itemID = 2589, count = 20, value = 1000, age = 3, source = "mine" } }))
        assert.same({ kind = "values", version = 2, values = { from = BOB, to = ME, at = NOW, id = 43, items = {
            { itemID = 5763, count = 1, value = 3500, k = 1, craft = true } } } }, ns.Comms.Decode(WIRE.MC))
        assert.is_nil(ns.Comms.Decode("M2|Bob Surname|Rettana Quilwrit|1791900000|43|5763:1:3500:c3:1"), "c alone")
        assert.equal(WIRE.E, ns.Paybacks.EncodeGear(BOB, ME, NOW, { main = "blade", ranged = "gun", quiver = 0, empty = { 4, 15 } }))
        assert.same({ kind = "gear", version = 2, gear = { from = BOB, to = ME, at = NOW, main = "blade", ranged = "gun",
            quiver = 0, empty = { 4, 15 } } }, ns.Comms.Decode(WIRE.E))
        assert.equal("E2|Bob Surname|Rettana Quilwrit|1791900000|-|-|0|-", ns.Paybacks.EncodeGear(BOB, ME, NOW, {}))
        assert.is_nil(ns.Comms.Decode("E2|Bob Surname|Rettana Quilwrit|1791900000|sword|gun|0|-"), "blade or blunt")
        assert.is_nil(ns.Comms.Decode("E2|Bob Surname|Rettana Quilwrit|1791900000|-|-|0|2"), "not a gear slot")
    end)

    it("each kind reaches the module that owns it", function()
        local function hear(text, channel, sender) return ns.Comms.Hear(sender or BOB, text, channel or "GUILD") end
        assert.same({ 197, 333 }, hear(WIRE.H).professions, "hello: a peer")
        assert.same({ 197, 333 }, ns.Comms.Peer(BOB).professions)
        assert.equal(130, hear(WIRE.S, "PARTY").skills["bob surname"][TAILORING], "skills: kept with the peer")
        assert.equal(20740, hear(WIRE.F).day, "scan day: Stale")
        assert.equal(20740, ns.Stale.Peers()["bob surname"].day)
        assert.equal("v0.31.0", hear(WIRE.U), "release: Version")
        assert.equal("v0.31.0", ns.Comms.Peer(BOB).release, "kept with the peer")
        assert.equal("partial", hear((WIRE.G:gsub("1/1", "1/2")), "GUILD"), "giving: Contributions")
        assert.is_nil(hear(WIRE.G, "PARTY"), "giving: GUILD only")
        assert.equal("taken", hear(WIRE.T0, "GUILD", GM), "template: Guild")
        assert.is_nil(hear(WIRE.T0, "PARTY", GM), "template: GUILD only")
        assert.is_nil(hear(WIRE.M, "GUILD"), "values: whispered only")
        assert.is_nil(hear(WIRE.R, "GUILD"), "answers: whispered only")
        assert.is_table(hear(WIRE.M, "WHISPER"), "values: Ledger")
        assert.equal(3, #ns.Ledger.Store().expect["bob surname"], "three stacks expected")
        assert.equal(0, hear(WIRE.R, "WHISPER"), "answers: Ledger (no such mail here)")
        local before = #WowStub.state.addonMessages
        assert.same({ kind = "ask", version = 2 }, hear(WIRE.A, "GUILD", "Cid Third"), "ask: a hello in answer")
        assert.equal("H2|", WowStub.state.addonMessages[before + 1].message:sub(1, 3))
    end)

    it("multipart messages (Guild, Contributions): per slot, a new head starts again, count 0 is whole at once", function()
        local add = ns.Comms.Assembler()
        assert.is_nil(add("guild A\nbob", "rev1", 1, 2, "one"))
        assert.is_nil(add("guild B\nbob", "rev1", 2, 2, "two"), "another slot never joins")
        assert.is_nil(add("guild A\nbob", "rev1", 1, 2, "again"), "a part already in is kept")
        assert.same({ "one", "two" }, add("guild A\nbob", "rev1", 2, 2, "two"))
        assert.is_nil(add("guild A\nbob", "rev1", 2, 2, "two"), "done: a new message starts")
        assert.is_nil(add("guild A\nbob", "rev2", 1, 2, "new"), "another head starts again")
        assert.same({}, add("guild A\nann", "rev3", 0, 0, nil))
    end)

    it("a kind whose module is missing (an older build) decodes to nil, like any unknown kind", function()
        ns.Stale = nil
        assert.is_nil(ns.Comms.Decode(WIRE.F))
        assert.is_nil(ns.Comms.Hear(BOB, WIRE.F, "GUILD"))
        assert.is_nil(ns.Comms.Decode("Z2|whatever"))
    end)

    it("a hello's follow-ups: the same kinds, order and channels as before the registry", function()
        WowStub.state.group = { members = { { name = "Cara Friend", online = true } } }
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function() return nil end,
            GetAuctionAgeByItemLink = function() return nil end,
            GetAuctionAgeByItemID = function(_, id) return id == 2589 and 1 or nil end,
        } } }
        ns.VERSION = "v0.31.0"
        local key = ns.Guild.Key()
        MailworthyDB.guildGiven = { [key] = { [ME:lower()] = { name = ME, total = 20, since = NOW - 100,
            days = { [math.floor(NOW / 86400)] = 20 } } } }
        assert.is_true(ns.Comms.Announce("wire"))
        local sent = {}
        for _, m in ipairs(WowStub.state.addonMessages) do sent[#sent + 1] = m.message:sub(1, 2) .. " " .. m.channel end
        assert.same({ "H2 GUILD", "H2 PARTY", "S2 GUILD", "S2 PARTY", "F2 GUILD", "F2 PARTY", "U2 GUILD", "U2 PARTY",
            "G2 GUILD" }, sent)
        assert.equal("F2|" .. (math.floor(NOW / 86400) - 1), WowStub.state.addonMessages[5].message)
        assert.equal(WIRE.U, WowStub.state.addonMessages[7].message)
        assert.equal("G2|" .. NOW .. "|1/1|20|" .. (NOW - 100) .. "|0:20", WowStub.state.addonMessages[9].message)
        local lines = table.concat(ns.Log.Lines(), "\n")
        assert.truthy(lines:find("hello (wire): H2 on GUILD, PARTY; S2 on GUILD, PARTY; F2 on GUILD, PARTY; "
            .. "U2 on GUILD, PARTY; G2 on GUILD", 1, true), lines)
    end)
end)
