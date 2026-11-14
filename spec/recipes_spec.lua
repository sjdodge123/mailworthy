-- Known recipes (operator, 2026-11-14: "already known crafting recipes should continue down regular
-- routing rules. currently i have an already known recipe that is saying to keep because I'm a cook"):
-- a Cooking binding saved for all characters names this one, so it kept every cooking recipe here,
-- even one this character has already learned. A known recipe now goes where the regular rules send it.
local loadAddon = require("spec.support.load_addon")

local STEW = 728    -- Recipe: Westfall Stew (class 9 Recipe, subclass 5 Cooking)
local BOAR = 2697   -- Recipe: Goretusk Liver Pie
local BOB = "Bob Surname"
local ALT = "Roknua Themicrulah"

describe("known recipes", function()
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

    local function bind(list)
        MailworthyDB.routes = { ["Classic Beta PvP|Alliance"] = list }
    end

    before_each(function()
        ns = loadAddon()
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 20 * 86400
        WowStub.state.professions = { { index = 1, name = "Cooking", rank = 120, maxRank = 150, skillLine = 185 } }
        prices = {}
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(ALT)
        WowStub.setBag(0, 1, WowStub.item(STEW, "Recipe: Westfall Stew", { sell = 50, class = 9, subclass = 5 }))
        WowStub.setBag(0, 2, WowStub.item(BOAR, "Recipe: Goretusk Liver Pie", { sell = 50, class = 9, subclass = 5 }))
        prices[WowStub.link(STEW, "Recipe: Westfall Stew")] = 2000
        prices[WowStub.link(BOAR, "Recipe: Goretusk Liver Pie")] = 2000
        -- Cooking bound to this character, saved for all the account's characters (rl-companion's setup).
        bind({ { to = ns.PlayerName(), profession = 185 } })
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("reads the tooltip's \"Already known\" line, colour codes and spaces aside", function()
        local R = ns.Recipes
        assert.is_true(R.IsKnownLine("Already known", "Already known"))
        assert.is_true(R.IsKnownLine(" |cffff2020Already known|r ", "Already known"))
        assert.is_true(R.IsKnownLine("|cnRED_FONT_COLOR:Already known|r", "Already known"))
        assert.is_true(R.IsKnownLine("Already known"), "no global string: the English text")
        assert.is_false(R.IsKnownLine("Requires Cooking (75)", "Already known"))
        assert.is_false(R.IsKnownLine(nil, "Already known"))
        WowStub.state.known[STEW] = true
        assert.is_true(R.Known(STEW))
        assert.is_false(R.Known(BOAR))
        assert.is_false(R.Known(nil))
    end)

    it("a known recipe skips the binding to this character and goes to the bank alt for the auction house", function()
        useAuctionator()
        WowStub.state.known[STEW] = true
        local result = ns.Bags.Evaluate()
        local stew = find(result.mail, STEW)
        assert.truthy(stew, "the report's bug: kept 'for this character' though it knows the recipe")
        assert.is_nil(stew.result.to, "to the bank alt")
        assert.equal("ah", stew.result.route)
        assert.is_nil(stew.result.forMe)
        -- The one it hasn't learned still stays for this character, as before.
        local pie = find(result.keep, BOAR)
        assert.truthy(pie and pie.result.forMe, "an unknown recipe stays for the cook")
        assert.is_nil(find(result.mail, BOAR))
    end)

    it("a known recipe goes to a friend's binding of the same profession instead", function()
        useAuctionator()
        WowStub.state.known[STEW] = true
        bind({ { to = ns.PlayerName(), profession = 185 }, { to = BOB, profession = 185 } })
        local result = ns.Bags.Evaluate()
        assert.equal(BOB, find(result.mail, STEW).result.to)
        local pie = find(result.keep, BOAR)
        assert.truthy(pie and pie.result.forMe, "this character's own binding still wins for one it can learn")
    end)

    it("without a price source a known recipe follows the white-items rule, never a binding to this character", function()
        WowStub.state.known[STEW] = true
        local result = ns.Bags.Evaluate()
        assert.is_false(result.priced)
        local stew = find(result.mail, STEW)
        assert.truthy(stew)
        assert.is_nil(stew.result.to)
        assert.equal("common", stew.result.route)
        -- A green one stays: without a price source only white items and staples go (AGENTS Safety).
        WowStub.state.known[BOAR] = true
        ns.Fire("MAIL_SHOW") -- read in the scan above as not known: the next visit reads it again
        WowStub.setBag(0, 2, WowStub.item(BOAR, "Recipe: Goretusk Liver Pie", { sell = 50, class = 9, subclass = 5, quality = 2 }))
        local again = ns.Bags.Evaluate()
        assert.is_nil(find(again.mail, BOAR))
        assert.equal("uncommon or better (no price data)", find(again.keep, BOAR).result.reason)
    end)

    it("a known recipe still never passes a hard keep", function()
        useAuctionator()
        WowStub.state.known[STEW] = true
        ns.Locks.ToggleItem(STEW, WowStub.link(STEW, "Recipe: Westfall Stew"), "spec")
        local result = ns.Bags.Evaluate()
        assert.is_nil(find(result.mail, STEW))
        assert.equal("locked", find(result.keep, STEW).result.reason)
    end)

    it("a tooltip that raises or has nothing answers 'not known': the binding keeps it, as before", function()
        useAuctionator()
        WowStub.state.known[STEW] = true
        local real = _G.C_TooltipInfo
        _G.C_TooltipInfo = { GetItemByID = function() error("boom") end }
        assert.is_false(ns.Recipes.Known(STEW))
        local result = ns.Bags.Evaluate()
        assert.truthy(find(result.keep, STEW).result.forMe)
        _G.C_TooltipInfo = nil
        assert.is_false(ns.Recipes.Known(STEW))
        _G.C_TooltipInfo = real
    end)

    it("each mailbox visit reads the tooltips again: a recipe learned since counts", function()
        assert.is_false(ns.Recipes.Known(STEW))
        WowStub.state.known[STEW] = true
        assert.is_false(ns.Recipes.Known(STEW), "remembered for this visit")
        ns.Fire("MAIL_SHOW")
        assert.is_true(ns.Recipes.Known(STEW))
    end)

    it("doesn't remember 'not known' before the item's data loads", function()
        WowStub.state.uncached[STEW] = true
        assert.is_false(ns.Recipes.Known(STEW))
        WowStub.state.uncached[STEW] = nil
        WowStub.state.known[STEW] = true
        assert.is_true(ns.Recipes.Known(STEW))
    end)

    it("only reads the tooltip of recipes", function()
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }))
        local asked, real = {}, ns.Recipes.Known
        ns.Recipes.Known = function(id) asked[#asked + 1] = id return real(id) end
        ns.Bags.Evaluate()
        ns.Recipes.Known = real
        table.sort(asked)
        assert.same({ STEW, BOAR }, asked)
    end)

    it("/mw report names the text it compares with and the known recipes in the bags", function()
        WowStub.state.known[STEW] = true
        ns.HandleSlash("report")
        local text = ns.Report.Text()
        assert.truthy(text:find('known recipes (regular rules, never a binding to this character): '
            .. 'ITEM_SPELL_KNOWN = "Already known"; in your bags: ' .. WowStub.link(STEW, "Recipe: Westfall Stew"), 1, true), text)
    end)
end)
