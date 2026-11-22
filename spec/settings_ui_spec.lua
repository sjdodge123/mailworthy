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
        -- A bank alt is optional (operator, 2026-11-08): the settings open first, Choose... picks one.
        assert.equal("main", ns.SettingsUI.View(), "no bank alt yet: still the settings")
        assert.equal("Choose...", _G.MailworthySettingsChange:GetText())
        _G.MailworthySettingsChange:Click()
        assert.truthy(_G.MailworthySettingsChoice1:GetText():find("Roknua Themicrulah", 1, true))
        assert.is_false(_G.MailworthySettingsChoice2:IsShown())
        assert.is_false(_G.MailworthySettingsForget1:IsShown(), "known characters can't be forgotten")
        _G.MailworthySettingsChoice1:Click()
        assert.equal("Roknua Themicrulah", ns.Config.BankAlt())
        assert.truthy(hint():find("Bank alt: Roknua Themicrulah", 1, true))
        assert.equal("main", ns.SettingsUI.View(), "a pick returns to the settings")
        assert.is_false(_G.MailworthySettingsChoice1:IsShown())
        assert.truthy(_G.MailworthySettingsChange:IsShown())
        _G.MailworthySettingsChange:Click()
        assert.equal("pick", ns.SettingsUI.View())
        -- chosen: the green fill, no "> <" arrows (UX review U6)
        assert.is_true(ns.Widgets.IsToggled(_G.MailworthySettingsChoice1), "marked as chosen")
        assert.is_nil(_G.MailworthySettingsChoice1:GetText():find(">", 1, true))
        _G.MailworthySettingsBack:Click()
        assert.equal("main", ns.SettingsUI.View())
        assert.equal("Roknua Themicrulah", ns.Config.BankAlt(), "Back changes nothing")
    end)

    it("opens on the settings once a bank alt is set; the bank alt row names it", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        MailworthySettingsFrame:Hide()
        ns.SettingsUI.Show()
        assert.equal("main", ns.SettingsUI.View())
        assert.equal("|cff33ff99Roknua Themicrulah|r  |cffaaaaaawarrior 8|r",
            ns.SettingsUI.BankAltText("Roknua Themicrulah", false, ns.Config.Choices()))
        assert.truthy(ns.SettingsUI.BankAltText(nil):find("None: what's worth selling stays in your bags", 1, true))
        assert.is_false(_G.MailworthySettingsHere:IsShown(), "the picker's buttons are hidden")
        assert.is_false(_G.MailworthySettingsName:IsShown())
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
        assert.equal("main", ns.SettingsUI.View())
        _G.MailworthySettingsChange:Click()
        assert.truthy(_G.MailworthySettingsChoice2:GetText():find("(not seen)", 1, true))
        assert.is_true(_G.MailworthySettingsForget2:IsShown())
        _G.MailworthySettingsForget2:Click() -- two presses (UX review U7): the first asks
        assert.is_true(_G.MailworthySettingsChoice2:IsShown())
        assert.equal("Sure?", _G.MailworthySettingsForget2:GetText())
        _G.MailworthySettingsForget2:Click()
        assert.is_false(_G.MailworthySettingsChoice2:IsShown())
    end)

    it("won't save this character or an empty name; a typed own name points at the button", function()
        type_("Rettana Quilwrit")
        _G.MailworthySettingsUseName:Click()
        _G.MailworthySettingsUseName:Click()
        assert.truthy(_G.MailworthySettingsName:GetText() ~= "", "the typed name stays")
        type_("  ")
        _G.MailworthySettingsUseName:Click()
        assert.is_nil(ns.Config.BankAlt())
    end)

    it("'This character is my bank alt' (a bank alt on a second WoW account) saves this character; again clears it",
        function()
            local here = _G.MailworthySettingsHere
            assert.equal("This character is my bank alt", here:GetText())
            here:Click()
            assert.equal("Rettana Quilwrit", ns.Config.BankAlt())
            assert.is_true(ns.BankAlt.IsBankAlt())
            assert.equal("bankalt", ns.BankAlt.Mode(), "no 'tags everywhere' needed")
            assert.equal("main", ns.SettingsUI.View())
            assert.truthy(ns.SettingsUI.BankAltText("Rettana Quilwrit", true, {}):find("this character", 1, true))
            _G.MailworthySettingsChange:Click()
            assert.is_true(ns.Widgets.IsToggled(here), "marked as chosen (the green fill)")
            assert.truthy(hint():find("Bank alt: Rettana Quilwrit (this character)", 1, true), hint())
            assert.is_false(ns.Widgets.IsToggled(_G.MailworthySettingsChoice1))
            assert.equal("this character is the bank alt", ns.Mailer.Blocker(ns.Config.BankAlt(), {}),
                "the Mailworthy window still refuses to mail to itself")
            here:Click()
            assert.is_nil(ns.Config.BankAlt())
            assert.is_false(ns.BankAlt.IsBankAlt())
            assert.equal("This character is my bank alt", here:GetText())
            assert.truthy(hint():find("No bank alt set on this realm and faction any more.", 1, true))
            -- Picking another character afterwards works as before.
            _G.MailworthySettingsChoice1:Click()
            assert.equal("Roknua Themicrulah", ns.Config.BankAlt())
            assert.equal("This character is my bank alt", here:GetText())
        end)

    it("Send by tag: one switch per verdict, Auction / Disenchant / Bank on and Vendor off until pressed", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        ns.SettingsUI.Show()
        assert.equal("AH: on", _G.MailworthySettingsSendAuction:GetText())
        assert.equal("DE: on", _G.MailworthySettingsSendDisenchant:GetText())
        assert.equal("BA: on", _G.MailworthySettingsSendBank:GetText())
        assert.equal("V: off", _G.MailworthySettingsSendVendor:GetText())
        _G.MailworthySettingsSendVendor:Click()
        _G.MailworthySettingsSendAuction:Click()
        local v = ns.Config.Values()
        assert.is_true(v.sendVendor)
        assert.is_false(v.sendAuction)
        assert.is_true(v.sendDisenchant)
        assert.equal("V: on", _G.MailworthySettingsSendVendor:GetText())
        assert.equal("AH: off", _G.MailworthySettingsSendAuction:GetText())
        assert.is_true(MailworthyDB.settings.sendVendor, "saved")
        _G.MailworthySettingsSendAuction:Click()
        assert.is_true(ns.Config.Get("sendAuction"))
    end)

    it("steppers, disenchant, listing length and the minimap button", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        ns.SettingsUI.Show()
        assert.is_true(_G.MailworthySettingsAmountUp:IsShown())
        _G.MailworthySettingsAmountUp:Click()
        _G.MailworthySettingsPercentDown:Click()
        _G.MailworthySettingsDisenchant:Click()
        _G.MailworthySettingsDuration2:Click()
        local v = ns.Config.Values()
        assert.equal(200, v.minGain, "one step up from the 1s default")
        assert.equal(0.2, v.minGainPct)
        assert.is_true(v.disenchant)
        assert.equal(2, v.duration)
        assert.equal("8h", _G.MailworthySettingsDuration2:GetText(), "no arrows (UX review U6)")
        assert.is_true(ns.Widgets.IsToggled(_G.MailworthySettingsDuration2))
        assert.is_false(ns.Widgets.IsToggled(_G.MailworthySettingsDuration3))
        assert.is_true(MailworthyMinimapButton:IsShown())
        _G.MailworthySettingsMinimap:Click()
        assert.is_false(MailworthyMinimapButton:IsShown())
        assert.equal("Minimap button: hidden", _G.MailworthySettingsMinimap:GetText())
        assert.equal("Lock glow: in Mailworthy", _G.MailworthySettingsGlow:GetText())
        _G.MailworthySettingsGlow:Click()
        assert.is_true(ns.Config.Flag("glowEverywhere"))
        assert.equal("Lock glow: always", _G.MailworthySettingsGlow:GetText())
        -- short labels, the explanation in the tooltip (UX review U8)
        local tip = function(name) return ns.Widgets.TipText(_G["MailworthySettings" .. name]) end
        assert.equal("Item tooltips: full", _G.MailworthySettingsTooltips:GetText())
        assert.truthy(tip("Tooltips"):find("full (the verdict and its numbers)", 1, true))
        _G.MailworthySettingsTooltips:Click()
        assert.equal("short", ns.Config.Tooltips())
        assert.equal("Item tooltips: short", _G.MailworthySettingsTooltips:GetText())
        assert.truthy(tip("Tooltips"):find("short (one line)", 1, true))
        _G.MailworthySettingsTooltips:Click()
        assert.equal("Item tooltips: off", _G.MailworthySettingsTooltips:GetText())
        _G.MailworthySettingsTooltips:Click()
        assert.equal("full", ns.Config.Tooltips(), "and round again")
        assert.equal("Profession materials: on (BH)", _G.MailworthySettingsMats:GetText())
        assert.truthy(tip("Mats"):find("This character keeps its profession materials: on (BH) (no crafting profession here)",
            1, true))
        WowStub.state.professions[2] = { index = 9, name = "Enchanting", rank = 1, maxRank = 75, skillLine = 333 }
        _G.MailworthySettingsMats:Click()
        assert.is_false(ns.Config.Get("keepProfessionMats"))
        assert.equal("Profession materials: off", _G.MailworthySettingsMats:GetText())
        assert.truthy(tip("Mats"):find("This character keeps its profession materials: off (Enchanting 1)", 1, true))
        _G.MailworthySettingsMats:Click() -- the third state: kept, on the bank alt
        assert.is_true(ns.Config.Get("keepProfessionMats"))
        assert.is_true(ns.Config.Get("matsToBankAlt"))
        assert.equal("Profession materials: on my bank alt (BA)", _G.MailworthySettingsMats:GetText())
        assert.truthy(tip("Mats"):find("profession materials: on my bank alt (BA) (Enchanting 1)", 1, true))
        _G.MailworthySettingsMats:Click() -- and round to on (kept here)
        assert.is_true(ns.Config.Get("keepProfessionMats"))
        assert.is_false(ns.Config.Get("matsToBankAlt"))
        assert.equal("Profession materials: on (BH)", _G.MailworthySettingsMats:GetText())
        assert.truthy(tip("Mats"):find("profession materials: on (BH) (Enchanting 1)", 1, true))
        _G.MailworthySettingsMats:Click() -- off again, as the lines below expect
        -- Per character (operator, 2026-11-13: an enchanter bank alt sells its dust, the mains keep theirs).
        assert.is_false(MailworthyCharDB.settings.keepProfessionMats)
        assert.is_nil(MailworthyDB.settings.keepProfessionMats, "the account's value is left alone")
        assert.is_nil(MailworthyDB.settings.matsToBankAlt)
        assert.equal("Sell what I gather: off", _G.MailworthySettingsGather:GetText())
        assert.truthy(tip("Gather"):find("Sell what I gather: off (Mining)", 1, true), "the stub character mines")
        _G.MailworthySettingsGather:Click()
        assert.is_true(ns.Config.Get("sellGathered"))
        assert.equal("Sell what I gather: on", _G.MailworthySettingsGather:GetText())
        assert.truthy(tip("Gather"):find("Sell what I gather: on (Mining)", 1, true))
    end)

    describe("Bags and more (UX review U1, U3)", function()
        before_each(function() _G.MailworthySettingsTabMore:Click() end)

        -- Operator, 2026-11-22: "go with B, move them, call it Mail routing" (media/settings-routing-prototype.png).
        it("Mail routing... on the tabs' row of both tabs opens the routing list; Friends, Guild and Mail ledger moved there",
            function()
                assert.is_true(_G.MailworthySettingsRouting:IsShown())
                assert.equal("Mail routing...", _G.MailworthySettingsRouting:GetText())
                for _, name in ipairs({ "Friends", "Guild", "Ledger", "FriendsGuild" }) do
                    assert.is_nil(_G["MailworthySettings" .. name], name .. " left Bags and more")
                end
                assert.is_nil(ns.SettingsUI.Solo, "no solo fold any more")
                ns.Routes.Add("Bob Surname", 333) -- a binding changes nothing here
                ns.SettingsUI.Refresh()
                assert.is_true(_G.MailworthySettingsLocks:IsShown())
                assert.is_true(_G.MailworthySettingsReport:IsShown())
                _G.MailworthySettingsRouting:Click()
                local routing = ns.RoutesUI.Frame()
                assert.is_true(routing:IsShown())
                assert.equal("list", ns.RoutesUI.View())
                assert.equal("Mail routing", ns.RoutesUI.TITLE.routing)
                for _, name in ipairs({ "Add", "Guild", "ChangeAlt", "Ledger", "Remove1" }) do
                    assert.is_true(_G["MailworthyFriends" .. name]:IsShown(), name)
                end
                routing:Hide()
                _G.MailworthySettingsTabMailing:Click()
                assert.is_true(_G.MailworthySettingsRouting:IsShown(), "on the Mailing tab too")
            end)

        it("the routing list's bank alt line follows the settings' picker", function()
            ns.Config.ClearBankAlt()
            ns.SettingsUI.Refresh()
            _G.MailworthySettingsRouting:Click()
            assert.equal("Choose...", _G.MailworthyFriendsChangeAlt:GetText())
            _G.MailworthyFriendsChangeAlt:Click()
            assert.equal("pick", ns.SettingsUI.View())
            ns.SettingsUI.Choose("Roknua Themicrulah")
            assert.equal("Change...", _G.MailworthyFriendsChangeAlt:GetText(), "the open routing window redrew")
        end)

        it("Pin warning: on / off, the switch /mw pinwarning was the only way to", function()
            local b = _G.MailworthySettingsPinWarning
            assert.equal("Pin warning: on", b:GetText())
            assert.is_true(ns.Widgets.IsToggled(b))
            b:Click()
            assert.is_true(ns.Config.Flag("hidePinWarning"))
            assert.equal("Pin warning: off", b:GetText())
            assert.is_false(ns.Widgets.IsToggled(b))
            ns.HandleSlash("pinwarning on")
            assert.equal("Pin warning: on", b:GetText(), "the slash command redraws the button")
        end)

        it("Report... opens the report box beside the settings", function()
            _G.MailworthySettingsReport:Click()
            assert.is_true(ns.Report.Frame():IsShown())
            assert.truthy(ns.Report.Text():find("Mailworthy", 1, true))
        end)
    end)

    it("short labels; the explanation in the tooltip, for the mouse and the controller's highlight (U8)", function()
        WowStub.state.gamepadUI = true
        local mats = _G.MailworthySettingsMats
        assert.equal("Profession materials: on (BH)", mats:GetText())
        for _, fn in ipairs(mats.hooks.OnEnter or {}) do fn(mats) end
        assert.equal(mats, GameTooltip:GetOwner(), "mouse-over")
        for _, fn in ipairs(mats.hooks.OnLeave or {}) do fn(mats) end
        ns.Nav.Select(_G.MailworthySettingsDisenchant)
        assert.equal(_G.MailworthySettingsDisenchant, GameTooltip:GetOwner(), "the highlight on it")
        assert.truthy(GameTooltip.shown)
        ns.Nav.Select(_G.MailworthySettingsDone)
        assert.is_false(GameTooltip.shown, "a button without one: the tooltip goes")
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
            _G.MailworthySettingsChange:Click() -- Choose...: the picker
            WowStub.state.activeFrame = nil
            tick()
            local b = WowStub.state.bindings
            assert.equal(click("MailworthyPadCross"), b.PAD1)
            assert.equal(click("MailworthyPadCircle"), b.PAD2)
            assert.equal(click("MailworthyPadDown"), b.PADDDOWN)
            assert.is_nil(b.PAD4, "Triangle stays the game's")
            assert.truthy(ns.Nav.Current(), "the highlight starts on a settings button")
            local function reachable(button)
                for _, c in ipairs(ns.Nav.Candidates()) do
                    if c.button == button then return true end
                end
                return false
            end
            assert.is_true(reachable(_G.MailworthySettingsHere), "the D-pad reaches 'This character is my bank alt'")
            assert.is_false(reachable(_G.MailworthySettingsDuration1), "the settings wait behind the picker")
            ns.Nav.Select(_G.MailworthySettingsHere)
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCross:Click()
            assert.equal("Rettana Quilwrit", ns.Config.BankAlt(), "Cross declares this character the bank alt")
            assert.equal("main", ns.SettingsUI.View())
            assert.truthy(ns.Nav.Current():IsVisible(), "the highlight moved to a button that still shows")
            assert.is_true(reachable(_G.MailworthySettingsDuration1))
            assert.is_true(reachable(_G.MailworthySettingsChange))
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
            ns.MailWindow.Show("send")
            tick()
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyMailSettings:Click()
            assert.is_true(MailworthySettingsFrame:IsShown())
            assert.equal(MailworthySettingsFrame, ns.Nav.Root())
            tick()
            assert.is_nil(WowStub.state.bindings.PAD4, "settings set: no Triangle")
            _G.MailworthyPadCircle:Click()
            assert.is_false(MailworthySettingsFrame:IsShown())
            assert.is_true(ns.MailWindow.Frame():IsShown(), "only the top window closes")
            tick()
            assert.equal(click("MailworthyPadTriangle"), WowStub.state.bindings.PAD4)
            assert.equal(ns.MailWindow.Frame(), ns.Nav.Root())
        end)
    end)
end)
