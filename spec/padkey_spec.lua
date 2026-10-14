-- Mailworthy's own controller bindings: Triangle at a focused mail window; the
-- D-pad, Cross and Circle while the Mailworthy window is open; L3 in the bags.
-- Re-applied when Blizzard replaces them; cleared on focus loss and combat.
local loadAddon = require("spec.support.load_addon")

local function click(name) return "CLICK " .. name .. ":LeftButton" end

describe("controller bindings", function()
    local ns, watcher
    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end

    before_each(function()
        ns = loadAddon()
        WowStub.state.gamepadUI = true
        ns.Fire("PLAYER_LOGIN")
        watcher = _G.MailworthyPadWatcher
        MailFrame:Show()
        SendMailFrame:Show()
    end)

    -- The watcher runs Check inside pcall and logs errors, so a failing Check
    -- doesn't fail a test by itself (alpha5 logged one ten times a second).
    after_each(function()
        for _, line in ipairs(ns.Log.Lines()) do
            assert.is_nil(line:find("check error", 1, true), line)
        end
    end)

    it("does nothing, and logs nothing, while nothing of ours is focused", function()
        for _ = 1, 5 do tick() end
        assert.same({}, WowStub.state.bindings)
        assert.equal(0, ns.PadKey.stats.applies)
    end)

    it("binds only Triangle while the mail window is focused", function()
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4, "not focused yet")
        WowStub.state.activeFrame = MailFrame
        tick()
        assert.equal(click("MailworthyPadTriangle"), WowStub.state.bindings.PAD4)
        assert.is_nil(WowStub.state.bindings.PADDUP)
    end)

    it("with the window open: D-pad, Cross and Circle drive Mailworthy's navigation", function()
        WowStub.state.activeFrame = MailFrame
        tick()
        _G.MailworthyPadTriangle:Click()
        tick()
        local b = WowStub.state.bindings
        assert.equal(click("MailworthyPadUp"), b.PADDUP)
        assert.equal(click("MailworthyPadRight"), b.PADDRIGHT)
        assert.equal(click("MailworthyPadCross"), b.PAD1)
        assert.equal(click("MailworthyPadCircle"), b.PAD2)
        assert.truthy(ns.Nav.Current(), "the highlight starts on the top-left button")
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCircle:Click()
        assert.is_false(ns.SelfTestUI.Frame():IsShown())
        tick()
        assert.is_nil(b.PADDUP, "back to Triangle only")
        assert.equal(click("MailworthyPadTriangle"), b.PAD4)
    end)

    it("re-applies when Blizzard replaces a binding", function()
        WowStub.state.activeFrame = MailFrame
        tick()
        WowStub.state.bindings.PAD4 = ""
        tick()
        assert.equal(click("MailworthyPadTriangle"), WowStub.state.bindings.PAD4)
    end)

    it("L3 in the bags locks the selected item; bags keep their own Triangle", function()
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        WowStub.state.activeFrame = ContainerFrameCombinedBags
        tick()
        assert.equal(click("MailworthyPadLock"), WowStub.state.bindings.PADLSTICK)
        assert.is_nil(WowStub.state.bindings.PAD4)
        WowStub.state.navButton = WowStub.itemButton(0, 3)
        _G.MailworthyPadLock:Click()
        assert.is_true(ns.Locks.IsItemLocked(2770))
    end)

    it("lets go when nothing of ours is focused, at combat, and without the controller UI", function()
        WowStub.state.activeFrame = MailFrame
        tick()
        WowStub.state.activeFrame = nil
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4)
        WowStub.state.activeFrame = MailFrame
        tick()
        WowStub.state.inCombat = true
        ns.Fire("PLAYER_REGEN_DISABLED")
        assert.is_nil(WowStub.state.bindings.PAD4, "cleared as combat starts")
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4, "and not re-bound in combat")
        WowStub.state.inCombat = false
        WowStub.state.gamepadUI = false
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4)
    end)

    it("one press delivered as down + up counts once", function()
        WowStub.state.activeFrame = MailFrame
        local b = _G.MailworthyPadTriangle
        b.scripts.OnClick(b, "LeftButton", true)
        b.scripts.OnClick(b, "LeftButton", false)
        assert.is_true(ns.SelfTestUI.Frame():IsShown())
        assert.equal(1, ns.PadKey.stats.presses)
    end)
end)
