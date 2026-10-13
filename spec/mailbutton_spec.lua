-- The Mailworthy button: created at login under SendMailFrame (the "Send Mail"
-- navigation group), below the mail window; on the Inbox a hint says R1.
local loadAddon = require("spec.support.load_addon")

describe("mail button", function()
    local ns
    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
    end)

    it("is created at login under SendMailFrame", function()
        local b = _G.MailworthyMailButton
        assert.equal(SendMailFrame, b.parent)
        assert.truthy(b.text:find("Mailworthy", 1, true))
    end)

    it("toggles the window on the Send Mail tab", function()
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.SelfTestUI.Frame():IsShown())
        _G.MailworthyMailButton:Click()
        assert.is_false(ns.SelfTestUI.Frame():IsShown())
    end)

    it("on the Inbox, says to switch to Send Mail instead", function()
        MailFrame:Show()
        ns.MailButton.Activate("Triangle")
        assert.is_false(ns.SelfTestUI.Frame():IsShown())
        assert.truthy(WowStub.printed[#WowStub.printed]:find("Send Mail tab (R1)", 1, true))
    end)

    it("can be switched off", function()
        _G.MailworthyMailButton = nil
        local ns2 = loadAddon()
        ns2.HandleSlash("feature mailbutton off")
        ns2.Fire("PLAYER_LOGIN")
        assert.is_nil(_G.MailworthyMailButton)
    end)
end)
