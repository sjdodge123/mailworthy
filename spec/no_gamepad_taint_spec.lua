-- Regression guard (alpha1, 2026-10-13): writing into Blizzard's controller UI
-- (prompted-binding footers, FrameControlsManager) tainted gamepad input from
-- login on, and the game blocked jumping, targeting and item use. Nothing in
-- Mailworthy may call those APIs.
local loadAddon = require("spec.support.load_addon")

describe("no writes into the controller UI", function()
    local saved
    before_each(function()
        saved = { util = GamepadSharedUtility, mode = GamepadMode }
        local function forbidden(name) return function() error("Mailworthy called " .. name) end end
        _G.GamepadSharedUtility = setmetatable({}, { __index = function(_, k) return forbidden("GamepadSharedUtility." .. k) end })
        _G.GamepadMode = { FrameControlsManager = setmetatable({}, { __index = function(_, k)
            return forbidden("FrameControlsManager:" .. k)
        end }) }
    end)
    after_each(function()
        _G.GamepadSharedUtility, _G.GamepadMode = saved.util, saved.mode
    end)

    it("logs in, opens the mailbox, the self-test and the report without touching them", function()
        local ns = loadAddon()
        InboxFrame.gamepadFooter = WowStub.footer()
        ns.Fire("PLAYER_LOGIN")
        MailFrame:Show()
        ns.Fire("MAIL_SHOW")
        _G.MailworthyMailButton:Click()
        ns.SelfTest.ShowReport()
        assert.equal(0, #InboxFrame.gamepadFooter.calls)
        assert.falsy(table.concat(MailworthyDB.selftest.log, "\n"):find("Mailworthy called", 1, true))
    end)
end)
