-- Mailworthy's own controller navigation: nearest button within 45 degrees of
-- the pressed direction (Blizzard's rule), top-left start, gold highlight.
local loadAddon = require("spec.support.load_addon")

local function at(x, y, name) return { x = x, y = y, name = name } end

describe("navigation search", function()
    local ns
    before_each(function() ns = loadAddon() end)

    it("picks the nearest button within 45 degrees", function()
        local from = at(0, 0, "from")
        local right, far, diag, up = at(40, 0), at(120, 0), at(30, 40), at(0, 50)
        local all = { from, right, far, diag, up }
        assert.equal(right, ns.Nav.Pick(from, all, "right"))
        assert.equal(up, ns.Nav.Pick(from, { from, up, at(60, 40) }, "up"))
        assert.is_nil(ns.Nav.Pick(from, { from, at(-40, 0) }, "right"), "nothing that way: stay put")
        assert.is_nil(ns.Nav.Pick(from, { from, at(30, 60) }, "right"), "outside the cone")
    end)

    it("starts at the top-left button", function()
        local a, b, c = at(10, 100), at(50, 100), at(0, 50)
        assert.equal(a, ns.Nav.TopLeft({ b, c, a }))
    end)

    it("moves the highlight over visible window buttons and presses with Cross", function()
        ns.Fire("PLAYER_LOGIN")
        MailFrame:Show()
        SendMailFrame:Show()
        local window = ns.MailWindow.Frame()
        window:Show()
        local pressed = {}
        local function button(name, x, y)
            local b = CreateFrame("Button", name, window)
            b.cx, b.cy = x, y
            b:SetScript("OnClick", function() pressed[#pressed + 1] = name end)
            return b
        end
        -- Only these buttons count: hide everything the window created.
        for _, child in ipairs(window.children) do child.shown = false end
        local first, second = button("First", 10, 200), button("Second", 120, 200)
        local below = button("Below", 10, 150)
        ns.Nav.Reset()
        assert.equal(first, ns.Nav.Current())
        ns.Nav.Move("right")
        assert.equal(second, ns.Nav.Current())
        ns.Nav.Move("left")
        ns.Nav.Move("down")
        assert.equal(below, ns.Nav.Current())
        ns.Nav.Press()
        assert.same({ "Below" }, pressed)
        assert.is_true(_G.MailworthyMailWindowNavHighlight:IsShown())
    end)
end)
