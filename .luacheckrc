std = "lua51"
max_line_length = 140
exclude_files = { ".luarocks/**", ".install/**", "lua_modules/**", ".release/**" }

-- Globals the addon defines (SavedVariables + slash command registration).
globals = {
    "MailworthyDB", "MailworthyCharDB",
    "SLASH_MAILWORTHY1", "SLASH_MAILWORTHY2", "SlashCmdList",
}

-- WoW API the addon reads. Keep this list to what the code actually calls.
read_globals = {
    -- Lua extensions the client provides
    "date", "time",
    -- UI
    "CreateFrame",
}

files["spec/**"] = {
    std = "+busted",
    globals = { "WowStub", "print", "unpack", "time", "date", "CreateFrame" },
    allow_defined_top = true,
}
