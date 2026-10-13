-- The "Mailworthy" button on the mail window: a plain child of MailFrame (mouse
-- click, or the controller's D-pad + Cross through smart navigation).
local loadAddon = require("spec.support.load_addon")

describe("mail button", function()
    local ns
    before_each(function() ns = loadAddon() end)

    it("is created on the mail window when the mailbox opens, once", function()
        ns.Fire("MAIL_SHOW")
        ns.Fire("MAIL_SHOW")
        local b = _G.MailworthyMailButton
        assert.equal(MailFrame, b.parent)
        assert.equal("Mailworthy", b.text)
    end)

    it("opens the self-test beside the mail window", function()
        MailFrame:Show()
        ns.Fire("MAIL_SHOW")
        _G.MailworthyMailButton:Click()
        local f = ns.SelfTestUI.Frame()
        assert.is_true(f:IsShown())
        assert.equal(MailFrame, f.parent)
    end)

    it("can be switched off for isolating problems", function()
        _G.MailworthyMailButton = nil
        ns.HandleSlash("feature mailbutton off")
        assert.is_false(MailworthyDB.features.mailButton)
        ns.Fire("MAIL_SHOW")
        assert.is_nil(_G.MailworthyMailButton)
    end)
end)
