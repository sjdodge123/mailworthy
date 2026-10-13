-- Mailworthy: namespace, saved variables and slash commands.
-- The design (entry points, decision rule, phases) is in docs/PLAN.md.
local addonName, ns = ...

ns.NAME = addonName
ns.VERSION = "@project-version@" -- the packager substitutes the release tag (also ## Version in the .toc)

function ns.Print(msg)
    print("|cff33ff99Mailworthy|r: " .. tostring(msg))
end

function ns.Init()
    MailworthyDB = type(MailworthyDB) == "table" and MailworthyDB or {}
    MailworthyCharDB = type(MailworthyCharDB) == "table" and MailworthyCharDB or {}
    MailworthyDB.blocked = MailworthyDB.blocked or {}
end

local HELP = {
    "Open a mailbox and press the Mailworthy button (coming in Phase 3).",
    "/mw - this help (settings panel coming in Phase 2)",
}

local function showHelp()
    ns.Print("v" .. ns.VERSION .. " - commands (/mw or /mailworthy):")
    for _, line in ipairs(HELP) do print("  " .. line) end
end

function ns.HandleSlash(msg)
    ns.lastCommand = "/mw " .. tostring(msg or "")
    showHelp()
end

SLASH_MAILWORTHY1 = "/mw"
SLASH_MAILWORTHY2 = "/mailworthy"
SlashCmdList.MAILWORTHY = function(msg) ns.HandleSlash(msg) end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        ns.Init()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
