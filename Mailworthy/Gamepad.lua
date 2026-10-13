-- Forever's controller UI ("smart navigation"), from Blizzard's source
-- (docs/FOREVER-UI-NOTES.md): button symbols, prompted-binding footers and
-- joining the L2/R2 window cycle. Every call is guarded and logged, since the
-- self-test exists to see which of these work at runtime.
local _, ns = ...

local Gamepad = {}
ns.Gamepad = Gamepad

Gamepad.FACE_BOTTOM = "PAD1" -- Cross / A
Gamepad.FACE_RIGHT = "PAD2" -- Circle / B
Gamepad.FACE_LEFT = "PAD3" -- Square / X
Gamepad.FACE_TOP = "PAD4" -- Triangle / Y

local NAMES = { PAD1 = "Cross/A", PAD2 = "Circle/B", PAD3 = "Square/X", PAD4 = "Triangle/Y" }

local function get(path)
    local v = _G
    for part in path:gmatch("[^.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end
Gamepad.Get = get

--- "Shapes" = PlayStation, "Generic" / "Letters" = Xbox, "Reverse" = Switch.
function Gamepad.LabelStyle()
    local getId, getState = get("C_GamePad.GetActiveDeviceID"), get("C_GamePad.GetDeviceMappedState")
    if type(getId) ~= "function" or type(getState) ~= "function" then return nil end
    local ok, id = pcall(getId)
    if not ok then return nil end
    local ok2, state = pcall(getState, id)
    return ok2 and type(state) == "table" and state.labelStyle or nil
end

--- The controller's symbol for a key as inline text, or "[Triangle/Y]" if the game can't draw it.
function Gamepad.Glyph(key, size)
    size = size or 16
    local atlasFor = get("InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture")
    if type(atlasFor) == "function" and type(CreateAtlasMarkup) == "function" then
        local ok, atlas = pcall(atlasFor, key)
        if ok and atlas then
            local ok2, markup = pcall(CreateAtlasMarkup, atlas, size, size)
            if ok2 and markup then return markup end
        end
    end
    return "[" .. (NAMES[key] or key) .. "]"
end

Gamepad.API = {
    "Menu.ModifyMenu", "GamepadSharedUtility.CreatePromptedBinding", "GamepadSharedUtility.CreatePromptedBindingFooter",
    "GamepadMode.FrameControlsManager", "SmartNavigation", "InputIconTextureSetUtility", "CreateAtlasMarkup",
    "C_GamePad.GetDeviceMappedState", "C_InputInterfaceStyle.GetCurrentStyle", "ItemLocation", "C_Mail.IsCommandPending",
    "SetSendMailShowing", "C_Container.UseContainerItem", "ClearSendMail", "GetInboxInvoiceInfo", "GetProfessionInfo",
}

function Gamepad.Presence()
    local parts = {}
    for _, path in ipairs(Gamepad.API) do
        local v = get(path)
        parts[#parts + 1] = path .. "=" .. (v == nil and "missing" or type(v))
    end
    return table.concat(parts, ", ")
end

--- A prompted binding (footer button). `fn(isDown)` runs on button-down.
function Gamepad.Binding(key, fn, label)
    local create = get("GamepadSharedUtility.CreatePromptedBinding")
    if type(create) ~= "function" then return nil, "CreatePromptedBinding missing" end
    local ok, binding = pcall(create, key, fn, label)
    if not ok then return nil, tostring(binding) end
    return binding
end

--- Give `frame` a footer (Cross select, extra bindings, L2/R2 hints, Circle back) and
--- register it with the FrameControlsManager so the game focuses it like its own windows.
function Gamepad.Join(frame, footerName, bindings)
    local manager = get("GamepadMode.FrameControlsManager")
    local createFooter = get("GamepadSharedUtility.CreatePromptedBindingFooter")
    frame.useFooterJumpHints = true
    frame.GetJumpHintLabel = frame.GetJumpHintLabel or function() return "Mailworthy" end
    local function ensureFooter()
        if type(frame.gamepadFooter) == "table" or type(createFooter) ~= "function" then return frame.gamepadFooter end
        local ok, footer = pcall(createFooter, frame, footerName)
        if not ok or not footer then
            ns.Log.Add("nav", "%s: CreatePromptedBindingFooter failed: %s", footerName, tostring(footer))
            return nil
        end
        local steps = {}
        local function step(name, ...)
            local fn = footer[name]
            local okStep, err = pcall(fn, footer, ...)
            steps[#steps + 1] = name .. (okStep and "" or (" (error: " .. tostring(err) .. ")"))
        end
        step("AddStandardSelectPrompt")
        for _, b in ipairs(bindings or {}) do
            local binding, err = Gamepad.Binding(b.key, b.fn, b.label)
            if binding then step("AddPromptedBinding", binding) else steps[#steps + 1] = b.label .. " (" .. err .. ")" end
        end
        step("AddStandardFrameControlManagerBindings", frame)
        step("AddStandardBackPrompt")
        step("Finalize")
        frame.gamepadFooter = footer
        ns.Log.Add("nav", "%s footer: %s", footerName, table.concat(steps, ", "))
        return footer
    end
    frame.FocusGamepad = function()
        local footer = ensureFooter()
        local ok, err = pcall(footer and footer.ShowAndActivateBindings or error, footer)
        ns.Log.Add("nav", "%s focused (footer %s)", footerName, ok and "shown" or tostring(err))
    end
    frame.UnfocusGamepad = function()
        local footer = frame.gamepadFooter
        if footer then pcall(footer.HideAndDeactivateBindings, footer) end
        ns.Log.Add("nav", "%s unfocused", footerName)
    end
    frame:HookScript("OnShow", function()
        if not manager or type(manager.FrameShown) ~= "function" then
            ns.Log.Add("nav", "%s shown: FrameControlsManager missing", footerName)
            return
        end
        local ok, err = pcall(manager.FrameShown, manager, frame)
        ns.Log.Add("nav", "%s shown: FrameControlsManager:FrameShown %s", footerName, ok and "ok" or tostring(err))
    end)
    frame:HookScript("OnHide", function()
        if manager and type(manager.FrameHidden) == "function" then pcall(manager.FrameHidden, manager, frame) end
    end)
end
