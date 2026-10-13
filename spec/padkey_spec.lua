-- Triangle at the mailbox through Mailworthy's own override binding, only while
-- the mail window has controller focus; re-applied if Blizzard replaces it.
local loadAddon = require("spec.support.load_addon")

local ACTION = "CLICK MailworthyPadButton:LeftButton"

describe("Triangle at the mailbox", function()
    local ns, watcher
    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        watcher = _G.MailworthyPadWatcher
        MailFrame:Show()
        ns.Fire("MAIL_SHOW")
    end)

    it("binds Triangle while the mail window is the focused window", function()
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4, "not focused yet")
        WowStub.state.activeFrame = MailFrame
        tick()
        assert.equal(ACTION, WowStub.state.bindings.PAD4)
        assert.equal(watcher, WowStub.state.bindingOwners.PAD4)
    end)

    it("re-applies when Blizzard replaces the binding", function()
        WowStub.state.activeFrame = MailFrame
        tick()
        WowStub.state.bindings.PAD4 = "" -- the fallthrough catcher blocked it again
        tick()
        assert.equal(ACTION, WowStub.state.bindings.PAD4)
        assert.equal(2, ns.PadKey.stats.applies)
    end)

    it("lets go when the bags take focus, the mailbox closes, or combat starts", function()
        WowStub.state.activeFrame = MailFrame
        tick()
        WowStub.state.activeFrame = ContainerFrameCombinedBags
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4)
        WowStub.state.activeFrame = MailFrame
        tick()
        ns.Fire("PLAYER_REGEN_DISABLED")
        assert.is_nil(WowStub.state.bindings.PAD4)
        tick()
        ns.Fire("MAIL_CLOSED")
        assert.is_nil(WowStub.state.bindings.PAD4)
        assert.is_false(watcher:IsShown())
    end)

    it("a press toggles the window on Send Mail, once per press", function()
        SendMailFrame:Show()
        _G.MailworthyPadButton:Click()
        _G.MailworthyPadButton:Click() -- the same press delivered as down + up
        assert.is_true(ns.SelfTestUI.Frame():IsShown())
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadButton:Click()
        assert.is_false(ns.SelfTestUI.Frame():IsShown())
        assert.equal(2, ns.PadKey.stats.presses)
    end)

    it("never binds in combat or without the gamepad UI", function()
        WowStub.state.inCombat = true
        WowStub.state.activeFrame = MailFrame
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4)
    end)
end)
