-- The UX pass (media/ux-pass-prototype.png): each window shows one task at a time and
-- hides what doesn't apply. These specs walk every view of every window and check
-- what the controller can reach: no blank (left-over) buttons in a view, the buttons
-- of the other view out of reach, and the highlight never left on a hidden button.
local loadAddon = require("spec.support.load_addon")

describe("window views", function()
    local ns, watcher

    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
    local function reachable()
        local set = {}
        for _, c in ipairs(ns.Nav.Candidates()) do set[c.button:GetName() or "?"] = c.button end
        return set
    end
    -- Every reachable button says what it does (item rows and the X carry no text of their own).
    local function assertNoBlankButtons()
        for name, b in pairs(reachable()) do
            if not name:find("Row%d") and not name:find("CloseButton") then
                assert.truthy(b:GetText() and b:GetText() ~= "", "blank button in view: " .. name)
            end
        end
    end
    local function press(button)
        ns.Nav.Select(button)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
    end

    before_each(function()
        ns = loadAddon()
        _G.Minimap = WowStub.newWidget("Frame", "Minimap")
        ns.Fire("PLAYER_LOGIN")
        MailworthyDB.characters[ns.Characters.Key("Roknua Themicrulah", "Classic Beta PvP", "Alliance")] = {
            name = "Roknua Themicrulah", realm = "Classic Beta PvP", faction = "Alliance", class = "WARRIOR", level = 8,
        }
        WowStub.state.guild = { clubId = 3, members = { { name = "Bob Surname", level = 30, online = true, professions = { 333 } } } }
        WowStub.state.gamepadUI = true
        watcher = _G.MailworthyPadWatcher
    end)

    after_each(function()
        _G.Minimap = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.equal(0, WowStub.focusCalls)
    end)

    it("settings: Choose... opens the picker, a pick returns to the settings; each view reaches only its own buttons", function()
        ns.SettingsUI.Show()
        assert.equal("main", ns.SettingsUI.View(), "a bank alt is optional: the settings first")
        _G.MailworthySettingsChange:Click()
        tick()
        local r = reachable()
        assert.truthy(r.MailworthySettingsChoice1)
        assert.truthy(r.MailworthySettingsHere)
        assert.truthy(r.MailworthySettingsUseName)
        assert.truthy(r.MailworthySettingsBack)
        assert.is_nil(r.MailworthySettingsDuration1)
        assert.is_nil(r.MailworthySettingsChange)
        assert.is_nil(r.MailworthySettingsChoice2, "only the choices there are")
        assertNoBlankButtons()

        press(_G.MailworthySettingsChoice1)
        assert.equal("main", ns.SettingsUI.View())
        assert.is_true(ns.Nav.Current():IsVisible(), "the highlight left the hidden picker")
        r = reachable()
        -- Two views since the UX review (U2): Mailing, then Bags and more.
        assert.equal("mailing", ns.SettingsUI.Tab())
        for _, name in ipairs({ "TabMailing", "TabMore", "Routing", "Change", "AmountUp", "AmountDown", "PercentUp", "PercentDown",
            "Duration1", "Duration3", "Disenchant", "Mats", "Gather", "SendAuction", "SendDisenchant", "SendBank",
            "SendVendor", "Done" }) do
            assert.truthy(r["MailworthySettings" .. name], "Mailing reaches " .. name)
        end
        for _, name in ipairs({ "Tags", "Glow", "Locks", "Summary", "Minimap", "Report" }) do
            assert.is_nil(r["MailworthySettings" .. name], "Mailing: no " .. name)
        end
        assert.is_nil(r.MailworthySettingsChoice1)
        assert.is_nil(r.MailworthySettingsHere)
        assertNoBlankButtons()

        press(_G.MailworthySettingsTabMore)
        assert.equal("more", ns.SettingsUI.Tab())
        assert.is_true(ns.Nav.Current():IsVisible())
        r = reachable()
        for _, name in ipairs({ "TabMailing", "TabMore", "Routing", "Tags", "Glow", "Pins", "Tooltips", "PinWarning",
            "Minimap", "Locks", "Pinned", "Summary", "Report", "Done" }) do
            assert.truthy(r["MailworthySettings" .. name], "Bags and more reaches " .. name)
        end
        -- Friends, Guild and Mail ledger are in Mail routing (operator, 2026-11-22), with a binding or none.
        for _, name in ipairs({ "Friends", "Guild", "Ledger", "FriendsGuild", "Change", "AmountUp", "Disenchant",
            "SendVendor" }) do
            assert.is_nil(r["MailworthySettings" .. name], "Bags and more: no " .. name)
        end
        assertNoBlankButtons()
        ns.Routes.Add("Bob Surname", 333)
        ns.SettingsUI.Refresh()
        r = reachable()
        for _, name in ipairs({ "Friends", "Guild", "Ledger", "FriendsGuild" }) do
            assert.is_nil(r["MailworthySettings" .. name], "a binding: still no " .. name)
        end
        assert.truthy(r.MailworthySettingsRouting)
        assertNoBlankButtons()
        -- Widgets.Views knows each view's buttons: every one that shows is a D-pad stop.
        for _, name in ipairs(ns.SettingsUI.Views().Buttons("more")) do
            if _G[name]:IsVisible() then assert.truthy(r[name], "Bags and more: " .. name .. " shows but can't be reached") end
        end
        press(_G.MailworthySettingsTabMailing)
        r = reachable()
        for _, name in ipairs(ns.SettingsUI.Views().Buttons("mailing")) do
            assert.truthy(r[name], "Mailing: " .. name .. " can't be reached")
        end

        press(_G.MailworthySettingsChange)
        assert.equal("pick", ns.SettingsUI.View())
        assert.is_true(ns.Nav.Current():IsVisible())
        press(_G.MailworthySettingsBack)
        assert.equal("main", ns.SettingsUI.View())
    end)

    it("mail routing: no bindings opens on the list; Add a binding... step 1, step 2; the list after binding", function()
        ns.RoutesUI.Show()
        tick()
        assert.equal("list", ns.RoutesUI.View(), "the list, bindings or none (2026-11-22)")
        local r = reachable()
        for _, name in ipairs({ "Add", "Guild", "ChangeAlt", "Ledger", "Done" }) do
            assert.truthy(r["MailworthyFriends" .. name], "the empty list reaches " .. name)
        end
        assert.is_nil(r.MailworthyFriendsPick1)
        assertNoBlankButtons()
        press(_G.MailworthyFriendsAdd)
        assert.equal("add", ns.RoutesUI.View())
        assert.is_true(ns.Nav.Current():IsVisible(), "the highlight left the hidden list")
        r = reachable()
        assert.truthy(r.MailworthyFriendsPick1)
        assert.truthy(r.MailworthyFriendsRefresh)
        assert.truthy(r.MailworthyFriendsBack)
        assert.is_nil(r.MailworthyFriendsProfession1)
        assert.is_nil(r.MailworthyFriendsAdd)
        assertNoBlankButtons()

        press(_G.MailworthyFriendsPick1)
        assert.is_true(ns.Nav.Current():IsVisible(), "the highlight left the hidden player list")
        r = reachable()
        assert.truthy(r.MailworthyFriendsProfession1)
        assert.truthy(r.MailworthyFriendsProfession8)
        assert.is_nil(r.MailworthyFriendsPick1)
        assert.is_nil(r.MailworthyFriendsRefresh)
        assertNoBlankButtons()

        press(_G.MailworthyFriendsProfession4)
        assert.equal(1, ns.Routes.Count())
        assert.equal("list", ns.RoutesUI.View())
        assert.is_true(ns.Nav.Current():IsVisible())
        r = reachable()
        for _, name in ipairs({ "Remove1", "CapUp1", "CapDown1", "Scope1", "Add", "Guild", "ChangeAlt", "Ledger", "Done" }) do
            assert.truthy(r["MailworthyFriends" .. name], "reaches " .. name)
        end
        assert.is_nil(r.MailworthyFriendsRemove2)
        assert.is_nil(r.MailworthyFriendsBack)
        assertNoBlankButtons()
    end)

    describe("popups beside the window that opened them", function()
        local function geometry(f, left, right, scale)
            f.GetLeft = function() return left end
            f.GetRight = function() return right end
            f.GetEffectiveScale = function() return scale or 1 end
        end
        local function anchor(f)
            local points = {}
            f.SetPoint = function(_, point, rel, relPoint) points[#points + 1] = { point, rel, relPoint } end
            return points
        end

        it("picks a side that fits on screen, else none", function()
            local side = ns.Widgets.Side
            assert.equal("right", side(408, 928, 420, 1365, 8))
            assert.equal("left", side(800, 1300, 420, 1365, 8))
            assert.is_nil(side(300, 1100, 560, 1365, 8), "neither side: laid over the opener")
            assert.is_nil(side(nil, 928, 420, 1365, 8))
        end)

        it("settings from the mailbox window: beside it; from /mw: centred; opaque windows", function()
            ns.Config.SetBankAlt("Roknua Themicrulah")
            MailFrame:Show()
            SendMailFrame:Show()
            WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 }))
            ns.MailWindow.Show("send")
            local window, settings = ns.MailWindow.Frame(), ns.SettingsUI.Frame()
            geometry(window, 408, 928)
            geometry(settings, 0, 0)
            settings.GetWidth = function() return 420 end
            geometry(UIParent, 0, 1365)
            local points = anchor(settings)
            _G.MailworthyMailSettings:Click()
            assert.same({ "TOPLEFT", window, "TOPRIGHT" }, points[#points])

            settings:Hide()
            geometry(window, 300, 1100) -- no room either side: squarely over it
            _G.MailworthyMailSettings:Click()
            assert.same({ "TOPLEFT", window, "TOPLEFT" }, points[#points])

            settings:Hide()
            ns.HandleSlash("")
            assert.same({ "CENTER" }, { points[#points][1] })

            local friends = ns.RoutesUI.Frame()
            geometry(settings, 936, 1356)
            geometry(friends, 0, 0)
            friends.GetWidth = function() return 560 end
            local fpoints = anchor(friends)
            _G.MailworthySettingsRouting:Click()
            assert.same({ "TOPRIGHT", settings, "TOPLEFT" }, fpoints[#fpoints], "no room on the right: left of settings")
        end)
    end)

    it("mailbox window: the bindings block shows only with bindings, and the window fits its rows", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        MailFrame:Show()
        SendMailFrame:Show()
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 }))
        WowStub.state.activeFrame = MailFrame
        ns.MailWindow.Show("send")
        tick()
        local r = reachable()
        assert.truthy(r.MailworthyMailSend)
        assert.truthy(r.MailworthyMailSettings)
        assert.truthy(r.MailworthyMailRow1)
        assert.is_nil(r.MailworthyMailClose, "no Close button: X, Escape and Circle close it")
        assert.is_nil(r.MailworthyMailFriends)
        assert.is_nil(r.MailworthyMailSkip1)
        assertNoBlankButtons()

        local plain = ns.MailWindow.Layout({ routes = 0, mail = 1, stay = 0 })
        local full = ns.MailWindow.Layout({ routes = 3, mail = ns.MailWindow.MAIL_ROWS, stay = ns.MailWindow.STAY_ROWS })
        assert.truthy(plain < 300, "one item, no bindings: a small window (" .. plain .. ")")
        assert.truthy(full > plain + 300)
        assert.truthy(full <= 726, "never taller than before the UX pass (" .. full .. ")")

        ns.Routes.Add("Bob Surname", 333)
        ns.MailWindow.Refresh()
        r = reachable()
        assert.truthy(r.MailworthyMailFriends)
        assert.truthy(r.MailworthyMailSkip1)
        assert.truthy(r.MailworthyMailUnbind1)
        assert.is_nil(r.MailworthyMailSkip2)
        assertNoBlankButtons()
        press(_G.MailworthyMailUnbind1)
        assert.equal(1, ns.Routes.Count(), "Remove asks first (U7)")
        assert.equal("Sure?", _G.MailworthyMailUnbind1:GetText())
        press(_G.MailworthyMailSkip1) -- the highlight moving on cancels
        press(_G.MailworthyMailSkip1)
        assert.equal("Remove", _G.MailworthyMailUnbind1:GetText())
        press(_G.MailworthyMailUnbind1)
        press(_G.MailworthyMailUnbind1)
        assert.equal(0, ns.Routes.Count())
        assert.is_true(ns.Nav.Current():IsVisible(), "the highlight left the removed binding's row")
    end)
end)
