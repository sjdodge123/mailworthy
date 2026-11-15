-- Key bindings (Bindings.xml; UX pass U9, 2026-11-15): Options > Keybindings > AddOns, so a controller player
-- can open Settings and the report away from a mailbox without typing.
local loadAddon = require("spec.support.load_addon")

local function bindings()
    local file = assert(io.open("Mailworthy/Bindings.xml"))
    local xml = file:read("*a")
    file:close()
    local list = {}
    for name, body in xml:gmatch('<Binding name="([%w_]+)"[^>]*>(.-)</Binding>') do
        list[#list + 1] = { name = name, body = body:match("^%s*(.-)%s*$") }
    end
    return list
end

describe("key bindings", function()
    local ns
    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
    end)

    it("each binding has a name for the keybindings list and calls MailworthyBinding with a known command", function()
        local list = bindings()
        assert.equal(2, #list)
        for _, b in ipairs(list) do
            assert.equal("string", type(_G["BINDING_NAME_" .. b.name]), b.name)
            local which = b.body:match('^MailworthyBinding%("(%a+)"%)$')
            assert.truthy(which and ns.BINDINGS[which], b.name .. ": " .. b.body)
        end
    end)

    it("the settings binding toggles Settings; the report binding opens the report", function()
        local list = bindings()
        local settings, report = assert(loadstring(list[1].body)), assert(loadstring(list[2].body))
        settings()
        assert.is_true(ns.SettingsUI.Frame():IsShown())
        settings()
        assert.is_false(ns.SettingsUI.Frame():IsShown())
        report()
        assert.is_true(_G.MailworthyReportFrame:IsShown())
    end)

    it("ignores anything else", function()
        MailworthyBinding("feature comms off")
        assert.is_true(ns.Features.On("comms"))
    end)
end)
