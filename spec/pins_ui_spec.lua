-- The pinned items window (PinsUI.lua; UX review U3, 2026-11-15): /mw pins and Settings > Bags and
-- more > "Pinned items (N)..." open it; one row per pin with where it sends the item from this
-- character (BA / BH / V), what the bags hold, and Unpin, by mouse and by controller. A pin on an
-- item that is no longer in the bags can be removed there; an unpinned row stays until the window
-- closes with "Pin" (the pin it had); nothing changes while a send runs.
local loadAddon = require("spec.support.load_addon")

describe("the pinned items window", function()
    local ns, watcher
    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
    local function pin(id, name, kind) MailworthyDB.pins[id] = { kind = kind or "bank", link = WowStub.link(id, name), at = 1 } end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        watcher = _G.MailworthyPadWatcher
        MailworthyDB.characters[ns.Characters.Key("Roknua Themicrulah", "Classic Beta PvP", "Alliance")] = {
            name = "Roknua Themicrulah", realm = "Classic Beta PvP", faction = "Alliance", class = "WARRIOR", level = 8,
        }
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        pin(2770, "Copper Ore")
        pin(4338, "Mageweave Cloth", "vendor") -- not in the bags
    end)

    after_each(function()
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.equal(0, WowStub.focusCalls)
    end)

    it("/mw pins opens it: a row per pin, by name, with its tag here and what the bags hold", function()
        ns.HandleSlash("pins")
        assert.is_true(ns.PinsUI.Frame():IsShown())
        local P = ns.Palette
        assert.equal(WowStub.link(2770, "Copper Ore") .. "  " .. P.Letters(P.BA) .. "  |cffaaaaaax5 in your bags|r",
            ns.PinsUI.RowLine(1))
        assert.equal(WowStub.link(4338, "Mageweave Cloth") .. "  " .. P.Letters(P.V) .. "  |cffff8040not in your bags|r",
            ns.PinsUI.RowLine(2))
        assert.is_nil(ns.PinsUI.RowLine(3))
        assert.equal("Unpin", _G.MailworthyPinsUnpin1:GetText())
        assert.is_false(_G.MailworthyPinsPage:IsShown(), "one page: no pager")
        assert.truthy(ns.PinsUI.Hint():find("Ctrl+Alt+click", 1, true))
        ns.Pins.SetMode(ns.Pins.HERE, "spec")
        assert.truthy(ns.PinsUI.RowLine(1):find(P.Letters(P.BH), 1, true), "this character banks its pins here: BH")
    end)

    it("Unpin removes a pin on an item that is not in the bags; the row stays with Pin, which puts it back", function()
        ns.HandleSlash("pins")
        _G.MailworthyPinsUnpin2:Click()
        assert.is_nil(ns.Pins.Kind(4338))
        assert.equal("bank", ns.Pins.Kind(2770), "the other pin stays")
        assert.truthy(ns.PinsUI.RowLine(2):find("unpinned", 1, true))
        assert.equal("Pin", _G.MailworthyPinsUnpin2:GetText())
        _G.MailworthyPinsUnpin2:Click()
        assert.equal("vendor", ns.Pins.Kind(4338), "the pin it had")
        assert.equal(WowStub.link(4338, "Mageweave Cloth"), MailworthyDB.pins[4338].link, "with its link")
        assert.equal("Unpin", _G.MailworthyPinsUnpin2:GetText())
        _G.MailworthyPinsUnpin2:Click()
        _G.MailworthyPinsDone:Click()
        assert.is_false(ns.PinsUI.Frame():IsShown())
        ns.HandleSlash("pins")
        assert.is_nil(ns.PinsUI.RowLine(2), "opened again: only what is pinned")
    end)

    it("by controller: D-pad and Cross unpin, Circle closes", function()
        WowStub.state.gamepadUI = true
        WowStub.state.layout = true
        ns.HandleSlash("pins")
        tick()
        assert.equal("settings", ns.PadKey.Wanted(), "the window takes the controller like the others")
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadDown:Click()
        assert.equal(_G.MailworthyPinsUnpin2, ns.Nav.Current())
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        assert.is_nil(ns.Pins.Kind(4338))
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCircle:Click()
        assert.is_false(ns.PinsUI.Frame():IsShown())
    end)

    it("during a send nothing changes, and the window says why", function()
        ns.HandleSlash("pins")
        local busy = ns.Mailer.Busy
        ns.Mailer.Busy = function() return true end
        _G.MailworthyPinsUnpin1:Click()
        assert.equal("bank", ns.Pins.Kind(2770))
        assert.equal(ns.Pins.BUSY, ns.PinsUI.Hint())
        ns.Mailer.Busy = busy
        _G.MailworthyPinsUnpin1:Click()
        assert.is_nil(ns.Pins.Kind(2770))
    end)

    it("pages both ways", function()
        for i = 1, 7 do pin(5000 + i, "Thing " .. i) end -- 9 pins: two pages of 6
        ns.HandleSlash("pins")
        assert.equal("1/2  >", _G.MailworthyPinsPage:GetText())
        _G.MailworthyPinsPageBack:Click()
        assert.equal("2/2  >", _G.MailworthyPinsPage:GetText(), "back from the first page: the last")
        assert.truthy(ns.PinsUI.RowLine(3):find("Thing 7", 1, true))
    end)

    it("Settings > Bags and more: \"Pinned items (N)...\" counts the pins and opens the window", function()
        ns.SettingsUI.Show(nil, "more")
        assert.equal("Pinned items (2)...", _G.MailworthySettingsPinned:GetText())
        assert.is_true(_G.MailworthySettingsPinned:IsShown())
        _G.MailworthySettingsPinned:Click()
        assert.is_true(ns.PinsUI.Frame():IsShown())
        _G.MailworthyPinsUnpin1:Click()
        assert.equal("Pinned items (1)...", _G.MailworthySettingsPinned:GetText())
        assert.equal("Pinned items...", ns.PinsUI.ButtonText(0))
    end)
end)
