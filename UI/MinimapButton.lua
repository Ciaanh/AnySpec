-- AnySpec/UI/MinimapButton.lua
-- Minimap button that orbits the minimap edge, angle saved per-account.

AnySpec = AnySpec or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.MinimapButton = AnySpec.UI.MinimapButton or {}
local MB = AnySpec.UI.MinimapButton

local BUTTON_NAME = "AnySpecMinimapButton"
local DEFAULT_ICON = 134063 -- INV_Misc_QuestionMark fallback; updated to current spec icon

local button = nil

-- Radius matches LibDBIcon-1.0: half of Minimap width + 10px margin.
local function GetRadius()
    return (Minimap:GetWidth() / 2) + 10
end

local function UpdatePosition()
    if not button then return end
    local angle = AnySpec.db and AnySpec.db.minimapButtonAngle or 2.5
    local r = GetRadius()
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function GetCurrentSpecIcon()
    local specIndex = AnySpec.SpecManager and AnySpec.SpecManager:GetCurrentSpecIndex()
    if specIndex then
        local info = AnySpec.SpecManager:GetSpecInfo(specIndex)
        if info then return info.icon end
    end
    return DEFAULT_ICON
end

local function CreateButton()
    local btn = CreateFrame("Button", BUTTON_NAME, Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")

    -- Icon
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = icon

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(20, 20)
    highlight:SetPoint("TOPLEFT", 7, -5)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("AnySpec", 0, 0.67, 1)
        GameTooltip:AddLine("Left-click: Open settings", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Toggle spec selector", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Click
    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            AnySpec.UI.QuickSwitch:Toggle()
        else
            AnySpec.UI.MainFrame:Toggle()
        end
    end)

    -- Drag to reposition around the minimap.
    -- GetCursorPosition() returns raw pixels; divide by UIParent scale to get UI units,
    -- which are the same coordinate space as Frame:GetCenter().
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local uiScale = UIParent:GetEffectiveScale()
            cx, cy = cx / uiScale, cy / uiScale
            AnySpec.db.minimapButtonAngle = math.atan2(cy - my, cx - mx)
            UpdatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    return btn
end

function MB:Init()
    button = CreateButton()
    self:UpdateIcon()
    UpdatePosition()

    if AnySpec.db and not AnySpec.db.minimapButton then
        button:Hide()
    end

    -- Register with AddOn Compartment if available (modern WoW)
    if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
        AddonCompartmentFrame:RegisterAddon({
            text = "AnySpec",
            icon = GetCurrentSpecIcon(),
            notCheckable = true,
            func = function() AnySpec.UI.MainFrame:Toggle() end,
        })
    end
end

function MB:UpdateIcon()
    if button and button._icon then
        button._icon:SetTexture(GetCurrentSpecIcon())
    end
end

function MB:SetShown(show)
    if button then
        button:SetShown(show)
    end
end
