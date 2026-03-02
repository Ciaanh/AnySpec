-- AnySpec/UI/SpecButtons.lua
-- Per-spec named buttons: ANYSPEC_SPEC1 .. ANYSPEC_SPEC4
-- Players can use /click ANYSPEC_SPEC1 etc. as action bar macros.

AnySpec = AnySpec or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.SpecButtons = AnySpec.UI.SpecButtons or {}
local SB = AnySpec.UI.SpecButtons

local MAX_SPEC_BUTTONS = 4
local buttons = {}

local function CreateSpecButton(index)
    local name = "ANYSPEC_SPEC" .. index
    local btn = CreateFrame("Button", name, UIParent)
    btn:SetSize(36, 36)
    btn:SetPoint("LEFT", UIParent, "LEFT", -200, 0)  -- Off-screen default; not meant to be visible directly
    btn:RegisterForClicks("AnyUp")
    btn:Hide()  -- Hidden by default; used via /click macro

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = icon

    btn._specIndex = index

    btn:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            print("|cff00aaffAnySpec|r: Cannot switch specs in combat.")
            return
        end
        AnySpec.SpecManager:SwitchSpec(self._specIndex)
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local info = AnySpec.SpecManager:GetSpecInfo(self._specIndex)
        if info then
            GameTooltip:SetText(info.name, 1, 1, 1)
            GameTooltip:AddLine(info.role, 0.8, 0.8, 0.8)
            local currentSpec = AnySpec.SpecManager:GetCurrentSpecIndex()
            if currentSpec == self._specIndex then
                GameTooltip:AddLine("Currently active", 0, 1, 0)
            end
        else
            GameTooltip:SetText("Spec " .. self._specIndex, 1, 1, 1)
        end
        GameTooltip:AddLine("|cffffd700/click " .. self:GetName() .. "|r to use as a macro", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

function SB:Init()
    for i = 1, MAX_SPEC_BUTTONS do
        buttons[i] = CreateSpecButton(i)
    end
    self:Refresh()
end

function SB:Refresh()
    local specs = AnySpec.SpecManager:GetAllSpecs()
    local currentSpec = AnySpec.SpecManager:GetCurrentSpecIndex()

    for i = 1, MAX_SPEC_BUTTONS do
        local btn = buttons[i]
        local spec = specs[i]
        if spec then
            btn._icon:SetTexture(spec.icon)
            -- Visually indicate active spec
            if currentSpec == i then
                btn:SetAlpha(1.0)
            else
                btn:SetAlpha(0.65)
            end
        end
    end
end
