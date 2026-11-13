-- One colour per destination, used everywhere Mailworthy marks an item (operator, 2026-11-13:
-- "unify the coloring so that pins / icon highlighting and the mailworthy tab are all in
-- alignment"): the bag tag (BankAlt.lua), a pin's glow (Border.lua), the chip on a Mailworthy
-- window row (MailWindow.lua), the bank alt summary's chips, the tooltip lines and the legend.
--
-- Each entry: text (the bag tag's letters), label (the tooltip's and the summary's word), bg (the
-- tag's and the chip's background, dark enough for white letters) and fg (the same hue, light:
-- glow, tooltip text, legend letters).
--
--   AH  auction house            DE  disenchant            V   vendor
--   BA  bank it on the bank alt (mailed there)              BH  bank it here, on this character
--   F   a friend's binding takes it                         R   Return to sender: back to who mailed it
--
-- A lock is not a destination: it keeps its own blue (Border.COLOR), as it always has.
local _, ns = ...

local Palette = {}
ns.Palette = Palette

Palette.AH = { key = "AH", text = "AH", label = "Auction", bg = { 0.2, 0.4, 0.75 }, fg = { 0.44, 0.62, 1 } }
Palette.DE = { key = "DE", text = "DE", label = "Disenchant", bg = { 0.45, 0.25, 0.65 }, fg = { 0.69, 0.5, 0.88 } }
Palette.V = { key = "V", text = "V", label = "Vendor", bg = { 0.45, 0.38, 0.2 }, fg = { 0.82, 0.69, 0.44 } }
-- The green the operator picked for bank pins (2026-11-13): a pin to the bank alt glows in it.
Palette.BA = { key = "BA", text = "BA", label = "Bank on alt", bg = { 0.24, 0.52, 0.2 }, fg = { 0.3, 0.7, 0.25 } }
Palette.BH = { key = "BH", text = "BH", label = "Bank here", bg = { 0.15, 0.5, 0.45 }, fg = { 0.25, 0.75, 0.68 } }
Palette.F = { key = "F", text = "F", label = "Friend", bg = { 0.55, 0.35, 0.12 }, fg = { 0.95, 0.6, 0.25 } }
Palette.R = { key = "R", text = "R", label = "Return to sender", bg = { 0.6, 0.22, 0.35 }, fg = { 0.95, 0.45, 0.6 } }
-- Window chips only (no bag tag): a white item mailed without prices, an item waiting for a price.
Palette.COMMON = { key = "COMMON", label = "Common", bg = { 0.4, 0.4, 0.4 }, fg = { 0.75, 0.75, 0.75 } }
Palette.NOPRICE = { key = "NOPRICE", label = "No price", bg = { 0.35, 0.35, 0.5 }, fg = { 0.65, 0.65, 0.85 } }

-- The legend's order.
Palette.ORDER = { "AH", "BA", "BH", "DE", "V", "F", "R" }
Palette.LEGEND = { AH = "auction", BA = "bank on alt", BH = "bank here", DE = "disenchant", V = "vendor",
    F = "to a friend", R = "back to sender" }

--- "|cffRRGGBB" for a colour { r, g, b }.
function Palette.Hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

--- An entry's letters in its light colour, for text: "|cff4db340BA|r".
function Palette.Letters(entry)
    return Palette.Hex(entry.fg) .. (entry.text or entry.label) .. "|r"
end
