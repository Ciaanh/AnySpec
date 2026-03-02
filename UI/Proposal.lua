-- AnySpec/UI/Proposal.lua
-- Auto-switch proposal toast shown when entering configured content

AnySpec = AnySpec or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.Proposal = AnySpec.UI.Proposal or {}
local PR = AnySpec.UI.Proposal

local TOAST_WIDTH = 340
local TOAST_HEIGHT = 72
local FADE_DURATION = 0.3
local PROPOSAL_TIMEOUT = 5

local toast = nil
local dismissTimer = nil
local currentAssignment = nil
local currentZoneInfo = nil

local function CancelDismissTimer()
    if dismissTimer then
        dismissTimer:Cancel()
        dismissTimer = nil
    end
end

local function CreateToast()
    local f = CreateFrame("Frame", "AnySpecProposalToast", UIParent, "BackdropTemplate")
    f:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    f:SetPoint("TOP", UIParent, "TOP", 0, -80)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    -- Spec icon
    local specIcon = f:CreateTexture(nil, "ARTWORK")
    specIcon:SetSize(48, 48)
    specIcon:SetPoint("LEFT", f, "LEFT", 10, 0)
    specIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._specIcon = specIcon

    -- Proposal text
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", specIcon, "RIGHT", 8, 6)
    text:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    f._text = text

    -- Content sub-text
    local subText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subText:SetPoint("LEFT", specIcon, "RIGHT", 8, -10)
    subText:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    subText:SetJustifyH("LEFT")
    subText:SetTextColor(0.7, 0.7, 0.7)
    f._subText = subText

    -- Switch button
    local switchBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    switchBtn:SetSize(80, 22)
    switchBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 62, 8)
    switchBtn:SetText("Switch")
    switchBtn:SetScript("OnClick", function()
        PR:OnAccept()
    end)
    f._switchBtn = switchBtn

    -- Dismiss button
    local dismissBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dismissBtn:SetSize(80, 22)
    dismissBtn:SetPoint("LEFT", switchBtn, "RIGHT", 6, 0)
    dismissBtn:SetText("Dismiss")
    dismissBtn:SetScript("OnClick", function()
        PR:OnDismiss()
    end)
    f._dismissBtn = dismissBtn

    return f
end

local function FadeIn(frame)
    frame:SetAlpha(0)
    frame:Show()
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local alpha = elapsed / FADE_DURATION
        if alpha >= 1 then
            alpha = 1
            self:SetScript("OnUpdate", nil)
        end
        self:SetAlpha(alpha)
    end)
end

local function FadeOut(frame, onComplete)
    local elapsed = 0
    local startAlpha = frame:GetAlpha()
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local alpha = startAlpha * (1 - elapsed / FADE_DURATION)
        if alpha <= 0 then
            alpha = 0
            self:SetScript("OnUpdate", nil)
            self:Hide()
            if onComplete then onComplete() end
        end
        self:SetAlpha(alpha)
    end)
end

function PR:Init()
    toast = CreateToast()
end

function PR:Show(assignment, zoneInfo)
    if not toast then return end

    currentAssignment = assignment
    currentZoneInfo = zoneInfo

    local specInfo = AnySpec.SpecManager:GetSpecInfo(assignment.specIndex)
    if not specInfo then return end

    toast._specIcon:SetTexture(specInfo.icon)
    toast._text:SetText("Switch to |cffffffff" .. specInfo.name .. "|r?")
    toast._subText:SetText(zoneInfo.instanceName or zoneInfo.category or "")

    CancelDismissTimer()

    dismissTimer = C_Timer.NewTimer(PROPOSAL_TIMEOUT, function()
        PR:OnDismiss()
    end)

    FadeIn(toast)
end

function PR:Hide()
    CancelDismissTimer()
    if toast and toast:IsShown() then
        FadeOut(toast)
    end
end

function PR:OnAccept()
    CancelDismissTimer()
    if not currentAssignment then return end

    local ok, err = AnySpec.SpecManager:SwitchSpec(
        currentAssignment.specIndex,
        currentAssignment.loadoutID
    )

    if not ok then
        toast._text:SetText("|cffff4444" .. (err or "Switch failed.") .. "|r")
        C_Timer.After(2, function() PR:Hide() end)
        return
    end

    -- Show a brief progress indicator; PLAYER_SPECIALIZATION_CHANGED will confirm
    toast._switchBtn:SetEnabled(false)
    toast._dismissBtn:SetEnabled(false)
    toast._text:SetText("Switching...")

    -- Auto-close after a few seconds regardless
    C_Timer.After(5, function() PR:Hide() end)

    currentAssignment = nil
    currentZoneInfo = nil
end

function PR:OnDismiss()
    CancelDismissTimer()
    if currentAssignment and currentZoneInfo then
        AnySpec.AutoSwitch:OnProposalDismissed(currentZoneInfo, currentAssignment.specIndex)
    end
    currentAssignment = nil
    currentZoneInfo = nil
    if toast and toast:IsShown() then
        FadeOut(toast)
    end
end

function PR:OnSpecSwitchFailed()
    if not toast or not toast:IsShown() then return end
    toast._text:SetText("|cffff4444Spec switch failed.|r")
    toast._switchBtn:SetEnabled(true)
    toast._dismissBtn:SetEnabled(true)
    C_Timer.After(3, function() PR:Hide() end)
end
