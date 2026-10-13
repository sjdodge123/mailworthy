-- Regression guard (alpha1 + alpha2, 2026-10-13): writing into Blizzard's
-- controller UI (prompted-binding footers, FrameControlsManager registration,
-- the gamepad More menu) tainted gamepad input. Mailworthy may only READ
-- FrameControlsManager:GetActiveFrame(); everything else must stay untouched.
local loadAddon = require("spec.support.load_addon")

describe("no writes into the controller UI", function()
    local saved
    before_each(function()
        saved = { util = GamepadSharedUtility, mode = GamepadMode, menu = Menu }
        local function forbidden(name) return function() error("Mailworthy called " .. name) end end
        _G.GamepadSharedUtility = setmetatable({}, { __index = function(_, k) return forbidden("GamepadSharedUtility." .. k) end })
        _G.GamepadMode = { FrameControlsManager = setmetatable({ GetActiveFrame = function() return MailFrame end },
            { __index = function(_, k) return forbidden("FrameControlsManager:" .. k) end }) }
        _G.Menu = setmetatable({}, { __index = function(_, k) return forbidden("Menu." .. k) end })
    end)
    after_each(function()
        _G.GamepadSharedUtility, _G.GamepadMode, _G.Menu = saved.util, saved.mode, saved.menu
    end)

    it("logs in, opens the mailbox, binds Triangle, opens the window and the report without touching them", function()
        local ns = loadAddon()
        InboxFrame.gamepadFooter = WowStub.footer()
        ns.Fire("PLAYER_LOGIN")
        MailFrame:Show()
        SendMailFrame:Show()
        ns.Fire("MAIL_SHOW")
        MailworthyPadWatcher.scripts.OnUpdate(MailworthyPadWatcher, 0.2)
        _G.MailworthyPadButton:Click()
        ns.SelfTestUI.ShowPage("locks")
        ns.SelfTest.ShowReport()
        assert.equal(0, #InboxFrame.gamepadFooter.calls)
        assert.falsy(table.concat(MailworthyDB.selftest.log, "\n"):find("Mailworthy called", 1, true))
    end)
end)
