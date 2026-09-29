-- AnySpec/UI/Theme.lua
-- Design tokens (colors, fonts) and low-level drawing helpers shared by every UI module.
-- Flat dark surfaces, 1px borders and a single accent color that follows the player's class.

AnySpec    = AnySpec    or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.Theme = AnySpec.UI.Theme or {}
local T = AnySpec.UI.Theme

------------------------------------------------------------
-- Colors  { r, g, b, a }
------------------------------------------------------------
T.C = {
    window     = { 0.063, 0.071, 0.090, 0.97 },
    header     = { 0.043, 0.051, 0.067, 1 },
    sidebar    = { 0.051, 0.059, 0.075, 1 },
    surface    = { 0.075, 0.086, 0.110, 1 },
    surfaceHi  = { 0.098, 0.114, 0.141, 1 },
    field      = { 0.071, 0.082, 0.106, 1 },
    selected   = { 0.102, 0.129, 0.161, 1 },
    border     = { 0.137, 0.149, 0.180, 1 },
    borderHi   = { 0.220, 0.240, 0.290, 1 },
    text       = { 0.925, 0.933, 0.953, 1 },
    textDim    = { 0.682, 0.706, 0.761, 1 },
    muted      = { 0.549, 0.576, 0.639, 1 },
    faint      = { 0.420, 0.447, 0.510, 1 },
    danger     = { 1.000, 0.380, 0.380, 1 },
    onAccent   = { 0.043, 0.051, 0.067, 1 },
}

local FALLBACK_ACCENT = { 0.247, 0.780, 0.922 }  -- used when class color is unavailable

-- Accent = the player's class color.
function T:GetAccent()
    local _, classFile = UnitClass("player")
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return FALLBACK_ACCENT[1], FALLBACK_ACCENT[2], FALLBACK_ACCENT[3]
end

function T:GetAccentHex()
    local r, g, b = self:GetAccent()
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Unpack a color token, optionally overriding alpha.
function T.RGBA(c, alpha)
    return c[1], c[2], c[3], alpha or c[4] or 1
end

------------------------------------------------------------
-- Fonts
-- Arial Narrow ships with every Latin client and gives a clean, condensed look.
-- Other locales fall back to the client's standard font so glyphs still render.
------------------------------------------------------------
local LATIN_LOCALES = {
    enUS = true, enGB = true, deDE = true, frFR = true, esES = true,
    esMX = true, itIT = true, ptBR = true,
}

local function FontPath()
    if LATIN_LOCALES[GetLocale()] then
        return "Fonts\\ARIALN.TTF"
    end
    return STANDARD_TEXT_FONT
end

local fontCache = {}

function T:GetFont(size)
    size = size or 13
    local f = fontCache[size]
    if not f then
        f = CreateFont("AnySpecFont" .. size)
        f:SetFont(FontPath(), size, "")
        f:SetShadowOffset(1, -1)
        f:SetShadowColor(0, 0, 0, 0.6)
        fontCache[size] = f
    end
    return f
end

-- Creates a font string with the theme font. color is a token from T.C (default: text).
function T:Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(self:GetFont(size))
    fs:SetTextColor(T.RGBA(color or T.C.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

------------------------------------------------------------
-- Surfaces
------------------------------------------------------------
local FLAT_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile     = false,
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- Applies a flat 1px-bordered backdrop. frame must inherit BackdropTemplate.
function T:Surface(frame, bg, border)
    frame:SetBackdrop(FLAT_BACKDROP)
    frame:SetBackdropColor(T.RGBA(bg or T.C.surface))
    frame:SetBackdropBorderColor(T.RGBA(border or T.C.border))
end

-- Solid color rectangle (texture).
function T:Fill(parent, color, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    tex:SetColorTexture(T.RGBA(color))
    return tex
end

-- 1px horizontal rule anchored across parent at y offset from the top.
function T:HRule(parent, y, color)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetHeight(1)
    tex:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    tex:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    tex:SetColorTexture(T.RGBA(color or T.C.border))
    return tex
end

------------------------------------------------------------
-- Glyphs drawn with Line objects (no texture assets needed)
--   kinds: "chevron-down", "chevron-up", "chevron-right", "close", "plus", "check"
------------------------------------------------------------
local GLYPHS = {
    ["chevron-down"]  = { { -0.35, 0.18, 0, -0.18 }, { 0, -0.18, 0.35, 0.18 } },
    ["chevron-up"]    = { { -0.35, -0.18, 0, 0.18 }, { 0, 0.18, 0.35, -0.18 } },
    ["chevron-right"] = { { -0.18, 0.35, 0.18, 0 }, { 0.18, 0, -0.18, -0.35 } },
    ["close"]         = { { -0.35, 0.35, 0.35, -0.35 }, { -0.35, -0.35, 0.35, 0.35 } },
    ["plus"]          = { { 0, 0.4, 0, -0.4 }, { -0.4, 0, 0.4, 0 } },
    ["check"]         = { { -0.38, 0, -0.1, -0.28 }, { -0.1, -0.28, 0.4, 0.28 } },
}

-- Returns a frame of the given size that draws the glyph; :SetColor(r,g,b,a) recolors it.
function T:Glyph(parent, kind, size, color, thickness)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder:EnableMouse(false)
    holder._lines = {}
    for _, seg in ipairs(GLYPHS[kind] or GLYPHS["close"]) do
        local line = holder:CreateLine(nil, "OVERLAY")
        line:SetThickness(thickness or 1.5)
        line:SetStartPoint("CENTER", holder, seg[1] * size, seg[2] * size)
        line:SetEndPoint("CENTER", holder, seg[3] * size, seg[4] * size)
        tinsert(holder._lines, line)
    end
    function holder:SetColor(r, g, b, a)
        for _, l in ipairs(self._lines) do l:SetColorTexture(r, g, b, a or 1) end
    end
    holder:SetColor(T.RGBA(color or T.C.muted))
    return holder
end

-- Spec / instance icon with trimmed edges.
function T:Icon(parent, size, texture, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetSize(size, size)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if texture then tex:SetTexture(texture) end
    return tex
end
