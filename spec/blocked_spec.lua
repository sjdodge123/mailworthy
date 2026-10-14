local loadAddon = require("spec.support.load_addon")

describe("blocked actions", function()
    it("listens for both block events", function()
        local ns = loadAddon()
        assert.is_true(ns.Blocked.frame.events.ADDON_ACTION_FORBIDDEN)
        assert.is_true(ns.Blocked.frame.events.ADDON_ACTION_BLOCKED)
    end)

    it("records the blocked function with the command before it", function()
        local ns = loadAddon()
        ns.HandleSlash("send")
        ns.Blocked.OnEvent("ADDON_ACTION_FORBIDDEN", "Mailworthy", "SendMail()")
        local entry = MailworthyDB.blocked[1]
        assert.equal("SendMail()", entry.fn)
        assert.equal("/mw send", entry.after)
        assert.truthy(ns.Blocked.Lines()[1]:find("SendMail()", 1, true))
        assert.truthy(ns.Blocked.Lines()[1]:find("(" .. ns.VERSION .. ")", 1, true), "names the build")
        MailworthyDB.blocked[1].version = nil -- recorded by a build that didn't store it
        assert.truthy(ns.Blocked.Lines()[1]:find("(older build)", 1, true))
    end)

    it("ignores other addons' blocks", function()
        local ns = loadAddon()
        ns.Blocked.OnEvent("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "CastSpellByName()")
        assert.equal(0, #MailworthyDB.blocked)
    end)

    it("keeps the newest 10", function()
        local ns = loadAddon()
        for i = 1, 12 do ns.Blocked.OnEvent("ADDON_ACTION_BLOCKED", "Mailworthy", "Fn" .. i .. "()") end
        assert.equal(10, #MailworthyDB.blocked)
        assert.equal("Fn3()", MailworthyDB.blocked[1].fn)
    end)
end)
