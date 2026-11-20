-- Known characters: recorded on login, offered as mail recipients only on the
-- same realm and faction, never the current character.
local loadAddon = require("spec.support.load_addon")

describe("characters", function()
    it("records the logged-in character with class, level and professions", function()
        local ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        local entry = MailworthyDB.characters["Rettana Quilwrit|Classic Beta PvP|Alliance"]
        assert.equal("PALADIN", entry.class)
        assert.equal(8, entry.level)
        assert.same({ { name = "Mining", rank = 12, maxRank = 75, skillLine = 186 } }, entry.professions)
        assert.truthy(ns.Characters.Describe(entry):find("Mining 12/75", 1, true))
    end)

    it("offers only other characters on the same realm and faction, by name", function()
        local ns = loadAddon()
        local add = function(name, realm, faction)
            MailworthyDB.characters[ns.Characters.Key(name, realm, faction)] = { name = name, realm = realm, faction = faction }
        end
        add("Zed Banker", "Classic Beta PvP", "Alliance")
        add("Ann Enchanter", "Classic Beta PvP", "Alliance")
        add("Horde Alt", "Classic Beta PvP", "Horde")
        add("Other Realm", "Classic Beta PvE 2", "Alliance")
        ns.Fire("PLAYER_LOGIN")
        local names = {}
        for _, e in ipairs(ns.Characters.Mailable()) do names[#names + 1] = e.name end
        assert.same({ "Ann Enchanter", "Zed Banker" }, names)
    end)

    -- Another addon's author, 2026-11-20: since a client patch GetRealmName() returned "". Everything
    -- saved per realm hangs off the name, so a blank one must never count as a realm.
    describe("the realm, when the game gives no name for it", function()
        local ns
        local REALM = "Classic Beta PvP"

        before_each(function()
            ns = loadAddon()
            WowStub.state.guid = "Player-91-0ABCDEF0"
            ns.Fire("PLAYER_LOGIN")
        end)

        it("the game's name wins, and is remembered for the character and its server ID", function()
            assert.same({ REALM, "game" }, { ns.Characters.Realm() })
            assert.equal(REALM, MailworthyCharDB.realm)
            assert.equal(REALM, MailworthyDB.realmIDs["91"])
            assert.equal("91", ns.Characters.ServerID())
        end)

        it("blank or missing is no answer: the realm this character was last seen on", function()
            for _, blank in ipairs({ "", false }) do
                WowStub.state.realm = blank or nil
                assert.same({ REALM, "saved" }, { ns.Characters.Realm() })
                local _, realm = ns.Characters.Current()
                assert.equal(REALM, realm)
                assert.equal(REALM .. "|Alliance", (ns.Util.RealmKey()))
            end
            WowStub.state.realm = 42
            assert.equal(REALM, (ns.Characters.Realm()), "not a string either")
        end)

        it("an older build's saved data (no last-seen realm): the one realm this name is recorded on", function()
            MailworthyCharDB.realm, MailworthyDB.realmIDs = nil, {}
            WowStub.state.realm = ""
            assert.same({ REALM, "characters" }, { ns.Characters.Realm() })
            assert.equal(REALM, MailworthyCharDB.realm, "kept from now on")
            assert.equal(REALM, MailworthyDB.realmIDs["91"], "and its server ID learned for the account's other characters")
            -- Recorded on two realms: the name doesn't say which.
            MailworthyCharDB.realm, MailworthyDB.realmIDs = nil, {}
            MailworthyDB.characters["Rettana Quilwrit|Other Realm|Alliance"] =
                { name = "Rettana Quilwrit", realm = "Other Realm", faction = "Alliance" }
            assert.same({ "#91", "placeholder" }, { ns.Characters.Realm() })
            -- Another faction's or another name's record says nothing; a blank or placeholder record neither.
            MailworthyDB.characters = {
                a = { name = "Rettana Quilwrit", realm = REALM, faction = "Horde" },
                b = { name = "Someone Else", realm = REALM, faction = "Alliance" },
                c = { name = "Rettana Quilwrit", realm = "", faction = "Alliance" },
                d = { name = "Rettana Quilwrit", realm = "#91", faction = "Alliance" },
                e = "junk",
            }
            assert.same({ "#91", "placeholder" }, { ns.Characters.Realm() })
        end)

        it("a character never seen: the realm this account has seen with its GUID's server ID", function()
            MailworthyCharDB.realm, MailworthyDB.characters = nil, {}
            WowStub.state.name, WowStub.state.realm = "New Character", ""
            assert.same({ REALM, "server" }, { ns.Characters.Realm() })
            assert.is_nil(MailworthyCharDB.realm, "read again each time, never kept for the character")
            WowStub.state.guid = "Player-92-0ABCDEF0"
            assert.same({ "#92", "placeholder" }, { ns.Characters.Realm() }, "another server: a realm of its own")
            assert.equal("#92|Alliance", (ns.Util.RealmKey()))
            assert.is_true(ns.Characters.IsPlaceholder("#92"))
            assert.is_false(ns.Characters.IsPlaceholder(REALM))
            assert.is_nil(MailworthyDB.realmIDs["92"], "a placeholder is never learned as a name")
        end)

        it("a server ID seen with two realm names is never used again", function()
            WowStub.state.realm = "Other Realm" -- the same GUID server ID, another name
            assert.equal("Other Realm", (ns.Characters.Realm()))
            assert.is_false(MailworthyDB.realmIDs["91"])
            WowStub.state.realm = REALM
            assert.equal(REALM, (ns.Characters.Realm()))
            assert.is_false(MailworthyDB.realmIDs["91"], "it stays untrusted")
            MailworthyCharDB.realm, MailworthyDB.characters = nil, {}
            WowStub.state.realm = ""
            assert.same({ "#91", "placeholder" }, { ns.Characters.Realm() })
        end)

        it("nothing known at all: nil, as before; a GUID in another shape gives no server ID", function()
            MailworthyCharDB.realm, MailworthyDB.characters, MailworthyDB.realmIDs = nil, {}, {}
            WowStub.state.realm = ""
            for _, guid in ipairs({ "Creature-0-91-0-0-1-0000000000", "Player-91", "Player--0ABCDEF0", 7, false }) do
                WowStub.state.guid = guid or nil
                assert.is_nil(ns.Characters.ServerID(), tostring(guid))
                assert.same({ nil, "unknown" }, { ns.Characters.Realm() })
            end
            assert.is_nil(ns.Characters.Record(), "no realm: the character is not recorded under a made-up one")
        end)

        it("/mw report says what the game gave and what is used instead", function()
            assert.equal('the game says "Classic Beta PvP"; server ID 91', ns.Characters.RealmText())
            WowStub.state.realm = ""
            assert.equal('the game gives no realm name (""): using Classic Beta PvP, from this character\'s last login; '
                .. "server ID 91", ns.Characters.RealmText())
            WowStub.state.realm, WowStub.state.guid = nil, nil
            MailworthyCharDB.realm, MailworthyDB.characters = nil, {}
            assert.equal("the game gives no realm name (nil): using nil, from unknown; server ID unknown",
                ns.Characters.RealmText())
        end)

        it("the saved bank alt, the known characters and the launch day survive a blank realm name", function()
            ns.Config.SetBankAlt("Zed Banker")
            local first = ns.Config.FirstSeen()
            MailworthyDB.characters[ns.Characters.Key("Ann Enchanter", REALM, "Alliance")] =
                { name = "Ann Enchanter", realm = REALM, faction = "Alliance" }
            WowStub.state.realm = ""
            WowStub.state.serverTime = WowStub.state.serverTime + 86400
            ns.Fire("PLAYER_LOGIN")
            assert.equal("Zed Banker", ns.Config.BankAlt())
            assert.equal(first, ns.Config.FirstSeen())
            assert.equal("Ann Enchanter", ns.Characters.Mailable()[1].name)
            assert.is_nil(MailworthyDB.characters["Rettana Quilwrit||Alliance"], "no character recorded on a blank realm")
            assert.is_nil(MailworthyDB.realms[""], "no blank realm first seen")
        end)
    end)

    it("cleans names in one place: spaces, then a realm suffix (Config.Clean / Routes.Clean are aliases)", function()
        local ns = loadAddon()
        assert.equal("Bob Surname", ns.Characters.CleanSpaces("  Bob   Surname "))
        assert.is_nil(ns.Characters.CleanSpaces("   "))
        assert.is_nil(ns.Characters.CleanSpaces(42))
        assert.equal("Bob-Realm", ns.Characters.CleanSpaces("Bob-Realm"), "spaces only")
        assert.equal("Bob Surname", ns.Characters.Clean(" Bob  Surname-Some Realm"))
        assert.is_nil(ns.Characters.Clean(nil))
        assert.equal(ns.Characters.CleanSpaces, ns.Config.Clean)
        assert.equal(ns.Characters.Clean, ns.Routes.Clean)
        assert.equal("bob surname", ns.Util.NameKey("Bob Surname-Realm"))
    end)
end)
