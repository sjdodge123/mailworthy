local loadAddon = require("spec.support.load_addon")

local function printed(text)
    for _, line in ipairs(WowStub.printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

describe("core", function()
    it("creates both saved tables", function()
        loadAddon()
        assert.is_table(MailworthyDB)
        assert.is_table(MailworthyCharDB)
        assert.same({}, MailworthyDB.blocked)
    end)

    it("keeps saved tables that already exist", function()
        local ns = loadAddon()
        MailworthyDB.bankAlt = "Keep Me"
        ns.Init()
        assert.equal("Keep Me", MailworthyDB.bankAlt)
    end)

    it("registers /mw and /mailworthy, and prints help", function()
        loadAddon()
        assert.equal("/mw", SLASH_MAILWORTHY1)
        assert.equal("/mailworthy", SLASH_MAILWORTHY2)
        SlashCmdList.MAILWORTHY("")
        assert.is_true(printed("commands (/mw or /mailworthy)"))
    end)

    it("never moves keyboard focus (gamepad crash in LedgerLink)", function()
        loadAddon()
        SlashCmdList.MAILWORTHY("")
        assert.equal(0, WowStub.focusCalls)
    end)
end)
