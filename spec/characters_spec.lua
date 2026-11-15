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
