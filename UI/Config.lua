-- AnySpec/UI/Config.lua
-- Thin shim - all settings UI now lives in UI/MainFrame.lua.
-- /anyspec and the minimap button both call MainFrame:Toggle() directly,
-- but this module is kept so existing call-sites (Core.lua) still compile.

AnySpec     = AnySpec     or {}
AnySpec.UI  = AnySpec.UI  or {}
AnySpec.UI.Config = AnySpec.UI.Config or {}
local CFG = AnySpec.UI.Config

function CFG:Init()
    -- Nothing to register - no Blizzard options panel.
end

function CFG:Open()
    AnySpec.UI.MainFrame:Open()
end
