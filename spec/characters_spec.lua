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
        local REALM, OTHER = "Classic Beta PvP", "Other Realm"
        local ME = "Rettana Quilwrit"

        local function record(name, realm, extra)
            local e = { name = name, realm = realm, faction = "Alliance" }
            for k, v in pairs(extra or {}) do e[k] = v end
            MailworthyDB.characters[ns.Characters.Key(name, realm, "Alliance")] = e
        end

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
            assert.equal("91", MailworthyDB.characters[ME .. "|" .. REALM .. "|Alliance"].server)
        end)

        it("blank or missing is no answer: the realm the game last named for this character", function()
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
            MailworthyDB.characters = {}
            record(ME, REALM) -- as v0.44.1 saved it: no server ID
            WowStub.state.realm = ""
            assert.same({ REALM, "characters" }, { ns.Characters.Realm() })
            -- Found, never saved as a fact: only the game's own name is (Codex review).
            assert.is_nil(MailworthyCharDB.realm)
            assert.is_nil(MailworthyDB.realmIDs["91"])
            ns.Characters.Record()
            local entry = MailworthyDB.characters[ME .. "|" .. REALM .. "|Alliance"]
            assert.is_nil(entry.server, "the record doesn't claim a server ID the game never tied to this realm")
            assert.is_nil(entry.guess)
            -- Recorded on two realms: the name doesn't say which. What this character's own saved
            -- variables remember does (it was found on the first, above, while it had one record);
            -- a character that remembers nothing has no realm.
            record(ME, OTHER)
            assert.same({ REALM, "characters" }, { ns.Characters.Realm() })
            MailworthyCharDB.inferred = nil
            assert.same({ "#91", "placeholder" }, { ns.Characters.Realm() })
            -- Another faction's or another name's record says nothing; a blank or placeholder record neither.
            MailworthyDB.realmGuesses = {} -- nothing vouched: else a name with no record takes the vouched realm
            MailworthyDB.characters = {
                a = { name = ME, realm = REALM, faction = "Horde" },
                b = { name = "Someone Else", realm = REALM, faction = "Alliance" },
                c = { name = ME, realm = "", faction = "Alliance" },
                d = { name = ME, realm = "#91", faction = "Alliance" },
                e = "junk",
            }
            assert.same({ "#91", "placeholder" }, { ns.Characters.Realm() })
        end)

        -- Operator, 2026-11-20, once build 71037 was read giving "" on their client ("Yes, fix it"):
        -- the game never names the realm there, so only the recorded characters can say where a
        -- server ID is. Before, a new character got the placeholder and no bank alt.
        describe("recorded characters vouch for their server ID's realm", function()
            local memory = {} -- GUID -> what that character's own saved variables remember
            local function loginAs(name, guid, realm)
                memory[tostring(WowStub.state.guid)] = MailworthyCharDB.inferred
                MailworthyCharDB.realm, MailworthyCharDB.inferred = nil, memory[guid] -- that character's own file
                WowStub.state.name, WowStub.state.guid, WowStub.state.realm = name, guid, realm or ""
                ns.Fire("PLAYER_LOGIN")
                return ns.Characters.Realm()
            end

            before_each(function()
                memory = {}
                ns.Config.SetBankAlt("Zed Banker")
                MailworthyDB.characters, MailworthyDB.realmIDs, MailworthyDB.realmServers = {}, {}, {}
                record(ME, REALM, { class = "PALADIN", level = 8 }) -- as an older build saved it
                record("Old Friend", REALM)
            end)

            it("a new character finds the realm once a recorded one has logged in", function()
                assert.same({ "#91", "placeholder" }, { loginAs("New Here", "Player-91-0000000A") }, "nobody vouched yet")
                assert.same({ REALM, "characters" }, { loginAs(ME, "Player-91-0ABCDEF0") })
                assert.equal(REALM, MailworthyDB.realmGuesses["91"])
                assert.is_nil(MailworthyDB.realmIDs["91"], "a guess, not what the game said")
                assert.same({ REALM, "siblings" }, { loginAs("New Here", "Player-91-0000000A") })
                assert.equal("Zed Banker", ns.Config.BankAlt())
                assert.is_nil(MailworthyCharDB.realm, "never saved as a fact")
                local entry = MailworthyDB.characters["New Here|" .. REALM .. "|Alliance"]
                assert.equal("91", entry.guess, "recorded as found on the server ID's word")
                -- It vouches for nothing itself, and another server ID is another realm.
                MailworthyDB.realmGuesses = {}
                assert.same({ "#91", "placeholder" }, { loginAs("New Here", "Player-91-0000000A") })
                MailworthyDB.realmGuesses = { ["91"] = REALM }
                assert.same({ "#92", "placeholder" }, { loginAs("New Elsewhere", "Player-92-0000000B") })
                assert.is_nil(ns.Config.BankAlt())
                assert.truthy(ns.Characters.RealmText():find("a placeholder", 1, true))
                loginAs("New Here", "Player-91-0000000A")
                assert.truthy(ns.Characters.RealmText():find("using Classic Beta PvP, from your other characters on this server", 1, true),
                    ns.Characters.RealmText())
            end)

            it("two characters vouching for different realms end the guess", function()
                loginAs(ME, "Player-91-0ABCDEF0")
                loginAs("New Here", "Player-91-0000000A")
                assert.truthy(MailworthyDB.characters["New Here|" .. REALM .. "|Alliance"])
                record("Other One", OTHER) -- a character of another realm, on the same server ID
                assert.same({ OTHER, "characters" }, { loginAs("Other One", "Player-91-0000000C") }, "its own record still stands")
                assert.is_false(MailworthyDB.realmGuesses["91"])
                assert.is_nil(MailworthyDB.characters["New Here|" .. REALM .. "|Alliance"], "what was recorded on the guess is gone")
                assert.same({ "#Player-91-0000000A", "placeholder" }, { loginAs("New Here", "Player-91-0000000A") },
                    "a realm of its own: the ID may stand for two")
                assert.is_nil(ns.Config.BankAlt())
                assert.same({ REALM, "characters" }, { loginAs(ME, "Player-91-0ABCDEF0") }, "a recorded character keeps its realm")
                assert.is_false(MailworthyDB.realmGuesses["91"], "and the guess stays ended")
            end)

            it("the game's own name replaces the guess, and what was recorded on it", function()
                loginAs(ME, "Player-91-0ABCDEF0")
                loginAs("New Here", "Player-91-0000000A")
                assert.same({ OTHER, "game" }, { loginAs("Third One", "Player-91-0000000D", OTHER) })
                assert.is_nil(MailworthyDB.realmGuesses["91"])
                assert.equal(OTHER, MailworthyDB.realmIDs["91"])
                assert.is_nil(MailworthyDB.characters["New Here|" .. REALM .. "|Alliance"])
                assert.same({ OTHER, "server" }, { loginAs("New Here", "Player-91-0000000A") })
                -- The same name from the game leaves a right guess and its records alone.
                MailworthyDB.realmIDs, MailworthyDB.realmServers = { ["91"] = OTHER }, { [OTHER] = "91" }
                MailworthyDB.realmGuesses = { ["93"] = REALM }
                loginAs("New Too", "Player-93-0000000E")
                loginAs("Fourth One", "Player-93-0000000F", REALM)
                assert.equal(REALM, MailworthyDB.realmGuesses["93"])
                assert.truthy(MailworthyDB.characters["New Too|" .. REALM .. "|Alliance"])
            end)

            it("a guess for a realm the game named for another server ID is not used", function()
                MailworthyDB.realmGuesses = { ["92"] = REALM }
                MailworthyDB.realmServers = { [REALM] = "91" }
                assert.same({ "#Player-92-0000000A", "placeholder" }, { loginAs("New Here", "Player-92-0000000A") },
                    "what is said of server 92 can't be right: a realm of this character alone")
                assert.is_nil(ns.Config.BankAlt())
            end)

            -- Codex review: a character whose name is recorded on two realms fell through to the guess
            -- as if it had no record; its own record was then marked a guess, ignored at the next login
            -- and deleted, and the character ended up on the other realm.
            it("a name recorded on two realms: the vouched one of them, and the record stays the character's own", function()
                record(ME, OTHER, { class = "PALADIN", level = 20 }) -- a namesake's, on another realm
                WowStub.state.level = 8
                assert.same({ REALM, "characters" }, { loginAs(ME, "Player-91-0ABCDEF0") }, "level 8: not the level 20 record")
                assert.equal(REALM, MailworthyDB.realmGuesses["91"])
                WowStub.state.level = 20 -- it has caught up: both records fit now
                for _ = 1, 3 do -- and it stays on its realm, login after login
                    assert.same({ REALM, "characters" }, { loginAs(ME, "Player-91-0ABCDEF0") })
                    assert.equal("Zed Banker", ns.Config.BankAlt())
                    local own = MailworthyDB.characters[ME .. "|" .. REALM .. "|Alliance"]
                    assert.is_nil(own.guess, "its own record is never a guess")
                    assert.equal(20, own.level)
                end
                assert.equal(REALM, MailworthyDB.realmGuesses["91"])
                assert.truthy(MailworthyDB.characters[ME .. "|" .. OTHER .. "|Alliance"], "the namesake's record is left alone")
                -- Another character of that name (its own saved variables remember nothing), on a server
                -- ID nothing is vouched for: no realm known, the server's placeholder as before.
                assert.same({ "#92", "placeholder" }, { loginAs(ME, "Player-92-0000000A") })
                -- An ended guess: the ID can't be relied on, so a realm of this character alone (Codex
                -- review, second pass: two such characters on the two realms of an ID shared "#92", and
                -- with it a bank alt).
                MailworthyDB.realmGuesses["92"] = false
                assert.same({ "#Player-92-0000000A", "placeholder" }, { loginAs(ME, "Player-92-0000000A") })
                local one = ns.Util.RealmKey()
                assert.equal("#Player-92-0000000A|Alliance", one)
                ns.Config.SetBankAlt("Bank On A")
                loginAs(ME, "Player-92-0000000B") -- its namesake, on the ID's other realm
                assert.are_not.equal(one, (ns.Util.RealmKey()))
                assert.is_nil(ns.Config.BankAlt())
            end)

            -- Codex review, third pass: realms A and B on one server ID. A's character vouched, and B's
            -- characters (a namesake recorded on both, and a new one) took A and its bank alt until one of
            -- B's own recorded characters logged in.
            it("one voucher is not enough while the account has characters on another realm nothing ties to an ID", function()
                record(ME, OTHER, { class = "PALADIN", level = 8 }) -- its namesake on the other realm
                record("Only There", OTHER)
                assert.same({ REALM, "characters" }, { loginAs("Old Friend", "Player-91-0000000B") })
                assert.equal(REALM, MailworthyDB.realmGuesses["91"])
                assert.same({ "#91", "placeholder" }, { loginAs(ME, "Player-91-0000000C") }, "the namesake: either realm")
                assert.is_nil(ns.Config.BankAlt())
                assert.same({ "#91", "placeholder" }, { loginAs("New Here", "Player-91-0000000A") }, "a new character too")
                assert.is_nil(ns.Config.BankAlt())
                -- The other realm's own character logs in on another server ID: now each realm has its ID.
                assert.same({ OTHER, "characters" }, { loginAs("Only There", "Player-92-0000000D") })
                assert.same({ REALM, "siblings" }, { loginAs("New Here", "Player-91-0000000A") })
                assert.equal("Zed Banker", ns.Config.BankAlt())
                assert.same({ OTHER, "siblings" }, { loginAs("New There", "Player-92-0000000E") })
                assert.is_nil(ns.Config.BankAlt(), "the other realm has no bank alt")
            end)

            -- Codex review: a guess that put a realm on another server ID than the game then named for
            -- it was no longer used, but the records made on it stayed in that realm's lists.
            it("the game naming a realm's server ID ends a guess that put it elsewhere", function()
                MailworthyDB.realmGuesses = { ["92"] = REALM }
                assert.same({ REALM, "siblings" }, { loginAs("New B", "Player-92-0000000A") })
                assert.truthy(MailworthyDB.characters["New B|" .. REALM .. "|Alliance"])
                loginAs("Third One", "Player-91-0000000D", REALM) -- the game: this realm is server 91
                assert.is_false(MailworthyDB.realmGuesses["92"])
                assert.is_nil(MailworthyDB.characters["New B|" .. REALM .. "|Alliance"], "no longer one of this realm's characters")
                local names = {}
                for _, e in ipairs(ns.Characters.Mailable()) do names[e.name] = true end
                assert.is_nil(names["New B"])
                assert.same({ "#Player-92-0000000A", "placeholder" }, { loginAs("New B", "Player-92-0000000A") })
            end)

            it("a namesake of another class, or of a lower level than the record, is not the recorded one", function()
                WowStub.state.class = { "Mage", "MAGE", 8 }
                assert.same({ "#91", "placeholder" }, { loginAs(ME, "Player-91-0ABCDEF0") }, "the record is a paladin's")
                assert.is_nil(MailworthyDB.realmGuesses["91"], "and it vouches for nothing")
                WowStub.state.class = { "Paladin", "PALADIN", 2 }
                WowStub.state.level = 3
                assert.same({ "#91", "placeholder" }, { loginAs(ME, "Player-91-0ABCDEF0") }, "the record is level 8")
                WowStub.state.level = 9
                assert.same({ REALM, "characters" }, { loginAs(ME, "Player-91-0ABCDEF0") })
                -- A record without class or level (or a character whose class can't be read) is not held against it.
                assert.same({ REALM, "characters" }, { loginAs("Old Friend", "Player-91-0000000B") })
            end)
        end)

        it("a character never seen: the realm the game named for another character with its server ID", function()
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

        -- Codex review, finding 1: the name used to be asked before the server ID.
        it("the same name on two realms: the server ID's realm wins over the name's record", function()
            MailworthyDB.realmIDs = { ["91"] = REALM, ["92"] = OTHER }
            MailworthyDB.characters = {}
            record(ME, REALM) -- this name, recorded on the first realm only
            MailworthyCharDB.realm = nil
            WowStub.state.realm, WowStub.state.guid = "", "Player-92-0ABCDEF0" -- its namesake on the other realm
            assert.same({ OTHER, "server" }, { ns.Characters.Realm() })
            assert.equal(OTHER, MailworthyDB.realmIDs["92"], "the right mapping is left alone")
            -- No mapping for this server, and the record is known to be of another server: not this character.
            MailworthyDB.realmIDs = {}
            record(ME, REALM, { server = "91" })
            assert.same({ "#92", "placeholder" }, { ns.Characters.Realm() })
        end)

        -- Codex review, finding 2: a realm taken from the server ID was saved through the character's
        -- own record, and outlived the ID being found to stand for two realms.
        it("a realm taken from the server ID is a guess: never saved as a fact, forgotten when the ID is not trusted", function()
            MailworthyCharDB.realm = nil
            WowStub.state.name, WowStub.state.realm = "New Character", ""
            ns.Fire("PLAYER_LOGIN")
            local key = "New Character|" .. REALM .. "|Alliance"
            assert.equal("91", MailworthyDB.characters[key].guess, "recorded, marked as a guess from server ID 91")
            ns.Fire("PLAYER_LOGIN") -- a second login: the guess doesn't vouch for itself
            assert.same({ REALM, "server" }, { ns.Characters.Realm() })
            assert.is_nil(MailworthyCharDB.realm)
            -- Another character shows the same server ID under another realm name.
            WowStub.state.name, WowStub.state.realm = "Someone Else", OTHER
            ns.Fire("PLAYER_LOGIN")
            assert.is_false(MailworthyDB.realmIDs["91"])
            assert.is_nil(MailworthyDB.characters[key], "the guessed record is gone")
            MailworthyCharDB.realm = nil
            WowStub.state.name, WowStub.state.realm = "New Character", ""
            ns.Fire("PLAYER_LOGIN")
            assert.same({ "#Player-91-0ABCDEF0", "placeholder" }, { ns.Characters.Realm() }, "no longer the first realm")
        end)

        -- Codex review, finding 3: unnamed realms shared one writable key ("#91", "nil").
        it("a server ID that stands for two realms, or none: a realm of this character alone", function()
            MailworthyCharDB.realm, MailworthyDB.characters = nil, {}
            MailworthyDB.realmIDs = { ["91"] = false }
            WowStub.state.realm = ""
            WowStub.state.name, WowStub.state.guid = "One Here", "Player-91-0000000A"
            local one = ns.Util.RealmKey()
            ns.Config.SetBankAlt("Stranger Elsewhere")
            WowStub.state.name, WowStub.state.guid = "Two There", "Player-91-0000000B"
            assert.are_not.equal(one, (ns.Util.RealmKey()))
            assert.is_nil(ns.Config.BankAlt(), "the other realm's bank alt is not this one's")
            -- A GUID in another shape is not trusted to tell characters apart (Codex review, sixth pass:
            -- two characters given the same cut-off "Player-91" shared "#Player-91"): the token does.
            for _, guid in ipairs({ "Creature-0-91-0-0-1-0000000000", "Player-91", "Player--0ABCDEF0" }) do
                WowStub.state.guid = guid
                assert.is_nil(ns.Characters.ServerID(), guid)
                local realm = ns.Characters.Realm() -- makes the token
                assert.equal("#?" .. tostring(MailworthyCharDB.realmToken), realm)
            end
            WowStub.state.guid = "Player-91"
            local first = ns.Util.RealmKey()
            ns.Config.SetBankAlt("Bank On A")
            MailworthyCharDB.realmToken = nil -- another character's own saved variables, the same cut-off GUID
            assert.are_not.equal(first, (ns.Util.RealmKey()))
            assert.is_nil(ns.Config.BankAlt())
            -- No GUID at all: a token kept in this character's own saved variables. A namesake on another
            -- realm has its own (Codex review, second pass: "#?<name>" was shared by namesakes).
            WowStub.state.name = ME
            for _, guid in ipairs({ 7, false, "" }) do
                WowStub.state.guid = guid or nil
                local realm, source = ns.Characters.Realm()
                assert.equal("#?" .. MailworthyCharDB.realmToken, realm)
                assert.equal("placeholder", source)
            end
            local mine = ns.Util.RealmKey()
            ns.Config.SetBankAlt("Bank On A")
            assert.equal("Bank On A", ns.Config.BankAlt())
            MailworthyCharDB.realmToken = nil -- the namesake's own saved variables, on another realm
            assert.are_not.equal(mine, (ns.Util.RealmKey()))
            assert.is_nil(ns.Config.BankAlt(), "the namesake never reads the first one's bank alt")
        end)

        -- Codex review, second pass: a record with the same server ID vouched for a namesake on the
        -- other realm of an ID known to stand for two.
        it("on a server ID that stands for two realms, the name's record is not asked", function()
            MailworthyDB.characters = {}
            record(ME, REALM, { server = "91" })
            ns.Config.SetBankAlt("Bank On A")
            WowStub.state.name, WowStub.state.realm = "Someone Else", OTHER -- the same ID, another realm
            ns.Fire("PLAYER_LOGIN")
            assert.is_false(MailworthyDB.realmIDs["91"])
            MailworthyCharDB.realm = nil
            WowStub.state.name, WowStub.state.realm = ME, "" -- the namesake on that other realm
            ns.Fire("PLAYER_LOGIN")
            assert.same({ "#Player-91-0ABCDEF0", "placeholder" }, { ns.Characters.Realm() })
            assert.is_nil(ns.Config.BankAlt())
        end)

        -- Codex review, fourth pass: an old record has no server ID, but its realm may have one by now.
        it("an old record of a realm the game has named for another server ID is not this character's", function()
            MailworthyDB.characters = {}
            record(ME, REALM) -- as an older build saved it
            ns.Config.SetBankAlt("Bank On A")
            WowStub.state.name = "Someone Else" -- the game names that realm for server 91
            ns.Fire("PLAYER_LOGIN")
            assert.equal(REALM, MailworthyDB.realmIDs["91"])
            MailworthyCharDB.realm = nil
            WowStub.state.name, WowStub.state.realm, WowStub.state.guid = ME, "", "Player-92-0ABCDEF0"
            assert.same({ "#92", "placeholder" }, { ns.Characters.Realm() }, "the namesake on server 92")
            assert.is_nil(ns.Config.BankAlt())
            WowStub.state.guid = "Player-91-0ABCDEF0" -- the recorded character itself still finds its realm
            assert.same({ REALM, "server" }, { ns.Characters.Realm() })
            MailworthyDB.realmIDs, MailworthyDB.realmServers = { ["93"] = OTHER }, { [OTHER] = "93" }
            assert.same({ REALM, "characters" }, { ns.Characters.Realm() }, "another realm's ID says nothing about this one")
        end)

        -- Codex review, fifth pass: once server ID 91 was found to stand for two realms, the fact that
        -- the recorded realm is on 91 was lost, and the namesake on server 92 was taken for the record.
        it("a realm keeps its server ID after that ID stops naming a realm", function()
            MailworthyDB.characters = {}
            record(ME, REALM) -- as an older build saved it
            ns.Config.SetBankAlt("Bank On A")
            WowStub.state.name = "Someone Else"
            ns.Fire("PLAYER_LOGIN") -- the game names the recorded realm for server 91
            WowStub.state.name, WowStub.state.realm = "Third One", OTHER
            ns.Fire("PLAYER_LOGIN") -- and then another realm for the same ID
            assert.is_false(MailworthyDB.realmIDs["91"])
            assert.equal("91", MailworthyDB.realmServers[REALM])
            assert.equal("91", MailworthyDB.realmServers[OTHER])
            MailworthyCharDB.realm = nil
            WowStub.state.name, WowStub.state.realm, WowStub.state.guid = ME, "", "Player-92-0ABCDEF0"
            assert.same({ "#92", "placeholder" }, { ns.Characters.Realm() }, "the namesake on server 92")
            assert.is_nil(ns.Config.BankAlt())
        end)

        -- Codex review, sixth pass: a realm the game named on a login without a GUID never learned
        -- its server ID, so an old record of it was taken for a namesake on another server.
        it("a realm named without a GUID learns its server ID at the next login that has one", function()
            WowStub.state.guid = nil
            MailworthyDB.characters, MailworthyDB.realmIDs, MailworthyDB.realmServers = {}, {}, {}
            record(ME, REALM) -- as an older build saved it
            ns.Config.SetBankAlt("Bank On A")
            WowStub.state.name = "Sibling One"
            ns.Fire("PLAYER_LOGIN") -- the game names the realm; no GUID
            assert.is_nil(MailworthyDB.realmServers[REALM])
            WowStub.state.realm, WowStub.state.guid = "", "Player-91-0ABCDEF0"
            ns.Fire("PLAYER_LOGIN") -- no name now, but the GUID: the saved realm teaches its server ID
            assert.equal("91", MailworthyDB.realmServers[REALM])
            assert.equal(REALM, MailworthyDB.realmIDs["91"])
            MailworthyCharDB.realm = nil
            WowStub.state.name, WowStub.state.guid = ME, "Player-92-0ABCDEF0" -- the namesake on server 92
            assert.same({ "#92", "placeholder" }, { ns.Characters.Realm() })
            assert.is_nil(ns.Config.BankAlt())
        end)

        -- Codex review, third pass: without a GUID the two checks above were skipped.
        it("without a GUID the name's record is never asked, and a record keeps the server ID it has", function()
            MailworthyDB.characters = {}
            record(ME, REALM, { server = "91" })
            ns.Config.SetBankAlt("Bank On A")
            MailworthyDB.realmIDs = { ["91"] = false }
            MailworthyCharDB.realm = nil
            WowStub.state.realm, WowStub.state.guid = "", nil -- a namesake elsewhere, no realm name, no GUID
            local realm, source = ns.Characters.Realm()
            assert.equal("#?" .. MailworthyCharDB.realmToken, realm)
            assert.equal("placeholder", source)
            assert.is_nil(ns.Config.BankAlt())
            -- An old, server-less record is no better without a GUID.
            MailworthyDB.realmIDs, MailworthyDB.characters = {}, {}
            record(ME, REALM)
            assert.equal("#?" .. MailworthyCharDB.realmToken, (ns.Characters.Realm()))
            -- The recorded character logs in without a GUID: its record keeps server 91, so the
            -- namesake on server 92 is still told apart.
            MailworthyDB.characters = {}
            record(ME, REALM, { server = "91" })
            WowStub.state.realm = REALM
            ns.Fire("PLAYER_LOGIN")
            assert.equal("91", MailworthyDB.characters[ME .. "|" .. REALM .. "|Alliance"].server)
            MailworthyCharDB.realm, MailworthyDB.realmIDs = nil, {}
            WowStub.state.realm, WowStub.state.guid = "", "Player-92-0ABCDEF0"
            assert.same({ "#92", "placeholder" }, { ns.Characters.Realm() })
            assert.is_nil(ns.Config.BankAlt())
        end)

        it("before the saved variables load there is no realm, and nothing is recorded", function()
            MailworthyCharDB.realm, MailworthyDB.characters, MailworthyDB.realmIDs = nil, {}, {}
            WowStub.state.realm, WowStub.state.guid = "", nil
            local saved = MailworthyCharDB
            rawset(_G, "MailworthyCharDB", nil)
            local realm, source = ns.Characters.Realm()
            local recorded = ns.Characters.Record()
            rawset(_G, "MailworthyCharDB", saved)
            assert.same({ nil, "unknown" }, { realm, source })
            assert.is_nil(recorded, "no realm: the character is not recorded under a made-up one")
        end)

        it("a server ID the game named two realms for is never used again", function()
            WowStub.state.realm = OTHER -- the same GUID server ID, another name
            assert.equal(OTHER, (ns.Characters.Realm()))
            assert.is_false(MailworthyDB.realmIDs["91"])
            WowStub.state.realm = REALM
            assert.equal(REALM, (ns.Characters.Realm()))
            assert.is_false(MailworthyDB.realmIDs["91"], "it stays untrusted")
        end)

        -- Codex review, finding 4: a realm name arriving mid-send split the ledger over two keys.
        it("the realm holds for a mailbox visit and a mail run, and is asked again afterwards", function()
            MailworthyCharDB.realm, MailworthyDB.characters, MailworthyDB.realmIDs = nil, {}, {}
            WowStub.state.realm = ""
            ns.Fire("MAIL_SHOW")
            assert.equal("#91|Alliance", (ns.Util.RealmKey()))
            WowStub.state.realm = REALM -- the game names the realm while the mailbox is open
            assert.equal("#91|Alliance", (ns.Util.RealmKey()), "one visit, one realm")
            -- Through every MAIL_CLOSED handler (the ledger commits its takes there), with no timer
            -- (Codex review, second pass: a timer's synchronous fallback released it first).
            local timers, atClose = _G.C_Timer, nil
            _G.C_Timer = nil
            ns.On("MAIL_CLOSED", function() atClose = ns.Util.RealmKey() end) -- the last handler
            ns.Fire("MAIL_CLOSED")
            _G.C_Timer = timers
            assert.equal("#91|Alliance", atClose)
            assert.equal(REALM .. "|Alliance", (ns.Util.RealmKey()), "asked again once they have all run")
            -- A mail run, and a mail still waiting for the game's answer after a stop, hold it too.
            ns.Mailer.state.busy = true
            WowStub.state.realm = ""
            assert.same({ REALM, "game" }, { ns.Characters.Realm() })
            ns.Mailer.state.busy, ns.Mailer.state.pending = false, {}
            assert.same({ REALM, "game" }, { ns.Characters.Realm() })
            ns.Mailer.state.pending = nil
            assert.same({ REALM, "saved" }, { ns.Characters.Realm() })
            -- The next visit asks again.
            ns.Fire("MAIL_SHOW")
            assert.same({ REALM, "saved" }, { ns.Characters.Realm() })
            ns.Fire("PLAYER_LOGIN")
            WowStub.state.realm = OTHER
            assert.equal(OTHER, (ns.Characters.Realm()), "a login releases it")
        end)

        it("/mw report says what the game gave and what is used instead", function()
            assert.equal('the game says "Classic Beta PvP"; server ID 91', ns.Characters.RealmText())
            WowStub.state.realm = ""
            assert.equal('the game gives no realm name (""): using Classic Beta PvP, from this character\'s last login; '
                .. "server ID 91", ns.Characters.RealmText())
            WowStub.state.realm, WowStub.state.guid = nil, nil
            MailworthyCharDB.realm, MailworthyDB.characters = nil, {}
            local text = ns.Characters.RealmText() -- makes the token
            assert.equal("the game gives no realm name (nil): using #?" .. tostring(MailworthyCharDB.realmToken)
                .. ", from a placeholder (no realm known); server ID unknown", text)
        end)

        it("the saved bank alt, the known characters and the launch day survive a blank realm name", function()
            ns.Config.SetBankAlt("Zed Banker")
            local first = ns.Config.FirstSeen()
            record("Ann Enchanter", REALM)
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
