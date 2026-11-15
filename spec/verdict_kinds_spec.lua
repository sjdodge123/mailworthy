-- Verdict kinds (UX and architecture pass, 2026-11-15): code decides by a verdict's `kind` and its flags
-- (Valuation.KINDS), never by its `reason`, which is only what the player reads. Before, the hard keeps
-- were a table keyed by display text, and one check matched a reason nothing produced any more.
-- Three guards: no source line compares or indexes by a reason; every kind is well formed; and the
-- whole critical path passes again with every reason reworded.
local loadAddon = require("spec.support.load_addon")

--- Lines of Mailworthy/*.lua (comments stripped) that read a reason's text to decide something.
local function reasonReads()
    local found = {}
    local patterns = {
        "reason%s*[=~]=",          -- r.reason == "locked", reason ~= x
        "[=~]=%s*[%w_%.]*reason%f[^%w_]", -- "locked" == r.reason
        "reason%s*:%s*find%f[^%w]", "reason%s*:%s*g?match%f[^%w]", "reason%s*:%s*g?sub%f[^%w]", -- reason:find(...)
        "%[[^%]]*reason%s*%]",     -- SOME_TABLE[r.reason]
        "find%([%w_%.]*reason",    -- string.find(r.reason, ...)
    }
    local dir = io.popen("ls Mailworthy/*.lua")
    for path in dir:lines() do
        local n = 0
        for line in io.lines(path) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            for _, pat in ipairs(patterns) do
                if code:find(pat) then found[#found + 1] = path .. ":" .. n .. ": " .. line end
            end
        end
    end
    dir:close()
    return found
end

describe("verdict kinds", function()
    it("no code reads a verdict's reason text to decide anything", function()
        assert.same({}, reasonReads())
    end)

    it("every kind has text and known flags; K errors on a misspelt kind", function()
        local ns = loadAddon()
        local known = { text = true, hard = true, unmailable = true, priceKeep = true, quiet = true }
        for id, def in pairs(ns.Valuation.KINDS) do
            assert.equal("string", type(def.text), id)
            for k, v in pairs(def) do
                assert.is_true(known[k] == true, id .. ": unknown field " .. k)
                if k ~= "text" then assert.is_true(v, id .. "." .. k) end
            end
            assert.equal(id, ns.Valuation.K[id])
        end
        assert.has_error(function() return ns.Valuation.K.lokced end)
        assert.has_error(function() ns.Valuation.Keep("lokced") end)
    end)

    it("unmailable kinds are hard keeps too (the game can't mail them, so nothing may try)", function()
        local ns = loadAddon()
        for id, def in pairs(ns.Valuation.KINDS) do
            if def.unmailable then assert.is_true(def.hard == true, id) end
        end
    end)

    it("every keep the rule returns carries a kind", function()
        local ns = loadAddon()
        local V = ns.Valuation
        local base = { itemID = 2770, link = "[Copper Ore]", count = 20, stacks = 1, quality = 1, classID = 7,
            subclassID = 7, vendor = 5 }
        local function with(extra)
            local item = {}
            for k, v in pairs(base) do item[k] = v end
            for k, v in pairs(extra) do item[k] = v end
            return item
        end
        local cases = {
            { with({ locked = true }) }, { with({ bound = true }) }, { with({ quest = true }) },
            { with({ questFor = "A Quest" }) }, { with({ inUse = true }) }, { with({ ammo = true }) },
            { with({ pin = V.PIN_HERE, vendor = nil }) }, { with({ pin = V.PIN_HERE }) },
            { with({ pin = V.PIN_VENDOR }) }, { with({ pin = V.PIN_BANK }), { failed = true } },
            { with({ quality = 0 }), nil }, { with({ quality = 2, classID = 4 }), nil },
            { with({}), { failed = true } }, { with({ vendor = nil }), { ah = 100, age = 0 } },
            { with({ vendor = 1000 }), { ah = 1, age = 0 } }, { with({ quality = 0 }), {} },
        }
        for i, c in ipairs(cases) do
            local r = V.Evaluate(c[1], c[2], V.DEFAULTS)
            if r.action == "keep" then
                assert.truthy(r.kind and V.KINDS[r.kind], "case " .. i .. ": a keep without a kind (" .. tostring(r.reason) .. ")")
            end
        end
    end)

    describe("the critical path with every reason reworded", function()
        setup(function() _G.MAILWORTHY_SPEC_REWORD = true end)
        teardown(function() _G.MAILWORTHY_SPEC_REWORD = nil end)
        -- The shipping gate's own cases, run again here (its describe blocks need this file's environment).
        local chunk = assert(loadfile("spec/critical_path_spec.lua"))
        setfenv(chunk, getfenv(1))
        chunk()
    end)
end)
