-- Controller helpers that only read: button symbols and API presence.
--
-- Mailworthy must NOT write into Blizzard's controller UI. alpha1 added a
-- Triangle binding to the mail footer (GamepadSharedUtility prompted bindings +
-- Finalize) and registered its own window with FrameControlsManager: on the
-- beta that tainted the whole gamepad input stack from login on, and the game
-- then blocked jumping (DescendStop, RunBinding), targeting
-- (SetPreferredGamepadInteractTarget), InteractUnit, ClearTarget and item use
-- (2026-10-13 self-test). Controller access now comes from plain buttons that
-- smart navigation reaches on its own. See docs/FOREVER-UI-NOTES.md.
local _, ns = ...

local Gamepad = {}
ns.Gamepad = Gamepad

Gamepad.FACE_BOTTOM = "PAD1" -- Cross / A
Gamepad.FACE_RIGHT = "PAD2" -- Circle / B
Gamepad.FACE_LEFT = "PAD3" -- Square / X
Gamepad.FACE_TOP = "PAD4" -- Triangle / Y

local NAMES = { PAD1 = "Cross/A", PAD2 = "Circle/B", PAD3 = "Square/X", PAD4 = "Triangle/Y", PADLSTICK = "L3" }

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

--- The controller's symbol for a key as inline text (a texture markup string;
--- nothing is registered), or "[Triangle/Y]" if the game can't draw it.
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
    "Menu.ModifyMenu", "SmartNavigation", "InputIconTextureSetUtility", "CreateAtlasMarkup",
    "C_GamePad.GetDeviceMappedState", "C_InputInterfaceStyle.GetCurrentStyle", "ItemLocation", "C_Mail.IsCommandPending",
    "C_Container.UseContainerItem", "ClearSendMail", "GetInboxInvoiceInfo", "GetProfessionInfo",
    "C_AuctionHouse.CalculateItemDeposit", "C_AuctionHouse.CalculateCommodityDeposit",
}

function Gamepad.Presence()
    local parts = {}
    for _, path in ipairs(Gamepad.API) do
        local v = get(path)
        parts[#parts + 1] = path .. "=" .. (v == nil and "missing" or type(v))
    end
    return table.concat(parts, ", ")
end
