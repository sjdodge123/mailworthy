-- "Triangle: Mailworthy" in the mail footer: added once per footer when the tab
-- takes controller focus, Finalize'd, never in combat; pressing it opens the
-- self-test window.
local loadAddon = require("spec.support.load_addon")

describe("mail footer", function()
    local ns
    before_each(function()
        ns = loadAddon()
        InboxFrame.FocusGamepad = function() end
        SendMailFrame.FocusGamepad = function() end
    end)

    it("waits for the game to create the footer, then adds Triangle once", function()
        ns.Fire("PLAYER_LOGIN")
        assert.is_false(ns.MailFooter.Ensure("InboxFrame"))
        local footer = WowStub.footer()
        InboxFrame.gamepadFooter = footer
        InboxFrame:FocusGamepad()
        InboxFrame:FocusGamepad()
        assert.equal(1, #footer.bindings)
        assert.equal("PAD4", footer.bindings[1].key)
        assert.equal("Mailworthy", footer.bindings[1].label)
        assert.equal(1, footer.finalized)
    end)

    it("covers the Send Mail tab too", function()
        local footer = WowStub.footer()
        SendMailFrame.gamepadFooter = footer
        ns.Fire("MAIL_SHOW")
        assert.equal(1, #footer.bindings)
    end)

    it("doesn't touch the footer in combat", function()
        ns.Fire("PLAYER_LOGIN")
        WowStub.state.inCombat = true
        local footer = WowStub.footer()
        InboxFrame.gamepadFooter = footer
        InboxFrame:FocusGamepad()
        assert.equal(0, #footer.bindings)
        WowStub.state.inCombat = false
        InboxFrame:FocusGamepad()
        assert.equal(1, #footer.bindings)
    end)

    it("opens the self-test window on Triangle, ignoring button-up", function()
        local footer = WowStub.footer()
        InboxFrame.gamepadFooter = footer
        ns.Fire("MAIL_SHOW")
        footer.bindings[1].fn(false)
        assert.is_nil(ns.SelfTestUI.Frame())
        footer.bindings[1].fn(true)
        assert.is_true(ns.SelfTestUI.Frame():IsShown())
    end)
end)
