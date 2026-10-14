-- The settings window: every control is a button (mouse click or controller
-- Cross), the typed name is an optional fallback with a check, and the
-- controller drives it with Mailworthy's own bindings wherever it's open.
local loadAddon = require("spec.support.load_addon")

local function click(name) return "CLICK " .. name .. ":LeftButton" end

describe("settings window", function()
    local ns, watcher, box
    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
    local function type_(text)
        box:SetText(text)
        box.scripts.OnTextChanged(box, true)
    end
    local function hint() return table.concat(WowStub.printed, "\n") end

    before_each(function()
        ns = loadAddon()
        _G.Minimap = WowStub.newWidget("Frame", "Minimap")
        ns.Fire("PLAYER_LOGIN")
        MailworthyDB.characters[ns.Characters.Key("Roknua Themicrulah", "Classic Beta PvP", "Alliance")] = {
            name = "Roknua Themicrulah", realm = "Classic Beta PvP", faction = "Alliance", class = "WARRIOR", level = 8,
        }
        watcher = _G.MailworthyPadWatcher
        box = _G.MailworthySettingsName
        ns.SettingsUI.Show()
    end)

    after_each(function()
        _G.Minimap = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.equal(0, WowStub.focusCalls, "never moves keyboard focus")
    end)

    it("lists known characters as buttons; pressing one saves the bank alt", function()
        assert.truthy(_G.MailworthySettingsChoice1:GetText():find("Roknua Themicrulah", 1, true))
        assert.is_false(_G.MailworthySettingsChoice2:IsShown())
        assert.is_false(_G.MailworthySettingsForget1:IsShown(), "known characters can't be forgotten")
        _G.MailworthySettingsChoice1:Click()
        assert.equal("Roknua Themicrulah", ns.Config.BankAlt())
        assert.truthy(_G.MailworthySettingsChoice1:GetText():find("> Roknua", 1, true), "marked as chosen")
        assert.truthy(hint():find("Bank alt: Roknua Themicrulah", 1, true))
    end)

    it("typed name: completes from known characters", function()
        type_("rok")
        _G.MailworthySettingsUseName:Click()
        assert.equal("Roknua Themicrulah", ns.Config.BankAlt())
        assert.equal("", box:GetText())
    end)

    it("typed name Mailworthy hasn't seen: a second press saves it, and it can be forgotten", function()
        type_("Newalt Somebody")
        _G.MailworthySettingsUseName:Click()
        assert.is_nil(ns.Config.BankAlt(), "first press only warns")
        _G.MailworthySettingsUseName:Click()
        assert.equal("Newalt Somebody", ns.Config.BankAlt())
        assert.truthy(_G.MailworthySettingsChoice2:GetText():find("(not seen)", 1, true))
        assert.is_true(_G.MailworthySettingsForget2:IsShown())
        _G.MailworthySettingsForget2:Click()
        assert.is_false(_G.MailworthySettingsChoice2:IsShown())
    end)

    it("won't save this character or an empty name", function()
        type_("Rettana Quilwrit")
        _G.MailworthySettingsUseName:Click()
        _G.MailworthySettingsUseName:Click()
        type_("  ")
        _G.MailworthySettingsUseName:Click()
        assert.is_nil(ns.Config.BankAlt())
    end)

    it("steppers, disenchant, listing length and the minimap button", function()
        _G.MailworthySettingsAmountUp:Click()
        _G.MailworthySettingsPercentDown:Click()
        _G.MailworthySettingsDisenchant:Click()
        _G.MailworthySettingsDuration2:Click()
        local v = ns.Config.Values()
        assert.equal(1000, v.minGain)
        assert.equal(0.2, v.minGainPct)
        assert.is_true(v.disenchant)
        assert.equal(2, v.duration)
        assert.truthy(_G.MailworthySettingsDuration2:GetText():find("> 8h <", 1, true))
        assert.is_true(MailworthyMinimapButton:IsShown())
        _G.MailworthySettingsMinimap:Click()
        assert.is_false(MailworthyMinimapButton:IsShown())
        assert.equal("Minimap button: hidden", _G.MailworthySettingsMinimap:GetText())
    end)

    it("the minimap button toggles the window", function()
        MailworthySettingsFrame:Hide()
        MailworthyMinimapButton:Click()
        assert.is_true(MailworthySettingsFrame:IsShown())
        MailworthyMinimapButton:Click()
        assert.is_false(MailworthySettingsFrame:IsShown())
    end)

    describe("controller", function()
        before_each(function() WowStub.state.gamepadUI = true end)

        it("binds the D-pad, Cross and Circle while it's open, with no Blizzard window focused", function()
            WowStub.state.activeFrame = nil
            tick()
            local b = WowStub.state.bindings
            assert.equal(click("MailworthyPadCross"), b.PAD1)
            assert.equal(click("MailworthyPadCircle"), b.PAD2)
            assert.equal(click("MailworthyPadDown"), b.PADDDOWN)
            assert.is_nil(b.PAD4, "Triangle stays the game's")
            assert.truthy(ns.Nav.Current(), "the highlight starts on a settings button")
            ns.Nav.Select(_G.MailworthySettingsDuration1)
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCross:Click()
            assert.equal(1, ns.Config.Get("duration"))
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCircle:Click()
            assert.is_false(MailworthySettingsFrame:IsShown())
            tick()
            assert.is_nil(b.PAD1, "bindings go when it closes")
        end)

        it("lets go in combat", function()
            tick()
            WowStub.state.inCombat = true
            ns.Fire("PLAYER_REGEN_DISABLED")
            tick()
            assert.is_nil(WowStub.state.bindings.PAD1)
        end)

        it("over the Mailworthy window at the mailbox: Circle closes settings, then the window takes over", function()
            MailFrame:Show()
            SendMailFrame:Show()
            WowStub.state.activeFrame = MailFrame
            MailworthySettingsFrame:Hide()
            ns.SelfTestUI.Show("send")
            tick()
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthySelfTestSettings:Click()
            assert.is_true(MailworthySettingsFrame:IsShown())
            assert.equal(MailworthySettingsFrame, ns.Nav.Root())
            tick()
            assert.is_nil(WowStub.state.bindings.PAD4, "settings set: no Triangle")
            _G.MailworthyPadCircle:Click()
            assert.is_false(MailworthySettingsFrame:IsShown())
            assert.is_true(ns.SelfTestUI.Frame():IsShown(), "only the top window closes")
            tick()
            assert.equal(click("MailworthyPadTriangle"), WowStub.state.bindings.PAD4)
            assert.equal(ns.SelfTestUI.Frame(), ns.Nav.Root())
        end)
    end)
end)
