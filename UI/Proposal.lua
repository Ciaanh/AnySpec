-- AnySpec/UI/Proposal.lua
-- Multi-option spec/loadout proposal toast shown on instance entry.
-- Up to 3 spec+loadout pairs are shown as clickable rows with keyboard shortcuts
-- and a countdown timer bar. Timeout fades silently with no dismiss cooldown.

AnySpec    = AnySpec    or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.Proposal = AnySpec.UI.Proposal or {}
local PR = AnySpec.UI.Proposal
local L  = AnySpec.L

------------------------------------------------------------
-- Layout constants
------------------------------------------------------------
local TOAST_W          = 360
local PADDING          = 10
local HEADER_H         = 26
local SEP_H            = 1
local ROW_H            = 50
local ROW_GAP          = 3
local TIMER_H          = 4
local HINT_H           = 18
local FADE_DURATION    = 0.25
local PROPOSAL_TIMEOUT = 8      -- seconds; expiry does NOT set dismiss cooldown

-- Position options for the toast
PR.POSITIONS = {
    TOP_CENTER       = "top_center",
    CENTER           = "center",
    TOP_RIGHT        = "top_right",
    BOTTOM_CENTER    = "bottom_center",
}
local DEFAULT_POSITION = PR.POSITIONS.TOP_CENTER

------------------------------------------------------------
-- Module state
------------------------------------------------------------
local toast              = nil
local proposalRows       = {}   -- row frames created per Show()
local currentAssignments = nil  -- array of { specIndex, loadoutID }
local currentZoneInfo    = nil
local currentPosition    = DEFAULT_POSITION  -- saved position setting

-- Unified per-frame state (timer + fade share one OnUpdate)
local state = {
    timerRunning   = false,
    timerElapsed   = 0,
    fadeActive     = false,
    fadeDirection  = 1,     -- 1 = fade-in, -1 = fade-out
    fadeElapsed    = 0,
    onFadeOutDone  = nil,
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function ClearRows()
    for _, row in ipairs(proposalRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(proposalRows)
end

local function SetRowsEnabled(enabled)
    for _, row in ipairs(proposalRows) do
        row:EnableMouse(enabled)
    end
end

local function StartFadeIn()
    state.fadeActive   = true
    state.fadeDirection = 1
    state.fadeElapsed  = 0
    state.onFadeOutDone = nil
    toast:SetAlpha(0)
    toast:Show()
end

local function StartFadeOut(onDone)
    state.fadeActive   = true
    state.fadeDirection = -1
    state.fadeElapsed  = 0
    state.onFadeOutDone = onDone
end

------------------------------------------------------------
-- Toast frame (shell only; rows added per Show)
------------------------------------------------------------
local function CreateToast()
    local f = CreateFrame("Frame", "AnySpecProposalToast", UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    -- Instance name header
    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT",  f, "TOPLEFT",  PADDING, -PADDING)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, -PADDING)
    header:SetJustifyH("LEFT")
    f._header = header

    -- Separator below header
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(SEP_H)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  PADDING,  -(PADDING + HEADER_H + 2))
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, -(PADDING + HEADER_H + 2))
    sep:SetColorTexture(0.3, 0.3, 0.35, 0.8)

    -- Timer bar background
    local timerBg = f:CreateTexture(nil, "ARTWORK")
    timerBg:SetHeight(TIMER_H)
    timerBg:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PADDING,  PADDING)
    timerBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PADDING, PADDING)
    timerBg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
    f._timerBg = timerBg

    -- Timer bar fill (shrinks left→right as time runs out)
    local timerFill = f:CreateTexture(nil, "OVERLAY")
    timerFill:SetHeight(TIMER_H)
    timerFill:SetPoint("TOPLEFT",    timerBg, "TOPLEFT",    0, 0)
    timerFill:SetPoint("BOTTOMLEFT", timerBg, "BOTTOMLEFT", 0, 0)
    timerFill:SetColorTexture(0.05, 0.65, 1, 0.85)
    f._timerFill = timerFill

    -- Hint text (only shown when 2+ rows)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, PADDING + TIMER_H + 4)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(0.4, 0.4, 0.4)
    hint:Hide()
    f._hint = hint

    -- Keyboard handling
    f:EnableKeyboard(false)
    f:SetScript("OnKeyDown", function(self, key)
        local handled = false
        if key == "ESCAPE" then
            PR:OnDismiss()
            handled = true
        elseif tonumber(key) then
            local idx = tonumber(key)
            if currentAssignments and idx >= 1 and idx <= #currentAssignments then
                PR:OnAccept(idx)
                handled = true
            end
        end
        self:SetPropagateKeyboardInput(not handled)
    end)

    -- Unified OnUpdate: fade-in/out + countdown timer
    f:SetScript("OnUpdate", function(self, dt)
        -- Fade
        if state.fadeActive then
            state.fadeElapsed = state.fadeElapsed + dt
            local prog = math.min(state.fadeElapsed / FADE_DURATION, 1)
            self:SetAlpha(state.fadeDirection == 1 and prog or (1 - prog))
            if prog >= 1 then
                state.fadeActive = false
                if state.fadeDirection == -1 then
                    self:Hide()
                    self:SetAlpha(1)
                    if state.onFadeOutDone then
                        state.onFadeOutDone()
                        state.onFadeOutDone = nil
                    end
                end
            end
        end

        -- Timer bar
        if not state.timerRunning then return end
        state.timerElapsed = state.timerElapsed + dt
        local fraction = 1 - math.min(state.timerElapsed / PROPOSAL_TIMEOUT, 1)
        local barW = self._timerBg:GetWidth() or (TOAST_W - PADDING * 2)
        self._timerFill:SetWidth(math.max(0.1, barW * fraction))

        if state.timerElapsed >= PROPOSAL_TIMEOUT then
            state.timerRunning = false
            PR:_HideNoCD()  -- expired: no dismiss cooldown
        end
    end)

    f:Hide()
    return f
end

------------------------------------------------------------
-- Build per-show spec+loadout rows
------------------------------------------------------------
local function BuildRows(assignments)
    ClearRows()

    local currentSpec      = AnySpec.SpecManager:GetCurrentSpecIndex()
    local currentLoadoutID = AnySpec.SpecManager:GetCurrentLoadoutConfigID()
    local rowsTopOffset    = PADDING + HEADER_H + SEP_H + 8

    for i, a in ipairs(assignments) do
        local specInfo = AnySpec.SpecManager:GetSpecInfo(a.specIndex)
        if specInfo then
            -- Resolve loadout display name
            local loadoutName = nil
            if a.loadoutID then
                local cfg = C_Traits.GetConfigInfo(a.loadoutID)
                if cfg then loadoutName = cfg.name end
            end

            -- Match both spec and loadout to determine if this is the current config
            local specMatch    = (currentSpec == a.specIndex)
            local loadoutMatch = (a.loadoutID == currentLoadoutID)  -- nil==nil is true (both default)
            local isCurrent    = specMatch and loadoutMatch

            local row = CreateFrame("Button", nil, toast)
            row:SetSize(TOAST_W - PADDING * 2, ROW_H)
            row:SetPoint("TOPLEFT", toast, "TOPLEFT", PADDING,
                         -(rowsTopOffset + (i - 1) * (ROW_H + ROW_GAP)))
            row:RegisterForClicks("LeftButtonUp")

            -- Green tint for the row matching current spec
            if isCurrent then
                local rowBg = row:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints()
                rowBg:SetColorTexture(0.07, 0.32, 0.07, 0.4)
            end

            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

            -- Number badge
            local badge = row:CreateTexture(nil, "BACKGROUND")
            badge:SetSize(22, 22)
            badge:SetPoint("LEFT", row, "LEFT", 4, 0)
            badge:SetColorTexture(0.12, 0.12, 0.12, 0.9)

            local numLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            numLbl:SetSize(22, 22)
            numLbl:SetPoint("CENTER", badge, "CENTER", 0, 0)
            numLbl:SetText(tostring(i))
            numLbl:SetTextColor(0.6, 0.6, 1)

            -- Spec icon
            local ico = row:CreateTexture(nil, "ARTWORK")
            ico:SetSize(32, 32)
            ico:SetPoint("LEFT", row, "LEFT", 30, 0)
            ico:SetTexture(specInfo.icon)
            ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            -- Spec name (green when current)
            local specNameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            specNameLbl:SetPoint("TOPLEFT",  ico, "TOPRIGHT",  8, -3)
            specNameLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -28, -3)
            specNameLbl:SetJustifyH("LEFT")
            specNameLbl:SetText(specInfo.name)
            specNameLbl:SetTextColor(isCurrent and 0.2 or 1, isCurrent and 1 or 1, isCurrent and 0.2 or 1)

            -- Loadout name (smaller, dimmer)
            local loadoutLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            loadoutLbl:SetPoint("BOTTOMLEFT",  ico, "BOTTOMRIGHT",  8, 4)
            loadoutLbl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -28, 4)
            loadoutLbl:SetJustifyH("LEFT")
            if loadoutName and loadoutName ~= "" then
                loadoutLbl:SetText(loadoutName)
                loadoutLbl:SetTextColor(0.62, 0.62, 0.62)
            else
                loadoutLbl:SetText(L["LOADOUT_DEFAULT"])
                loadoutLbl:SetTextColor(0.35, 0.35, 0.35)
            end

            -- Checkmark for current spec
            if isCurrent then
                local check = row:CreateTexture(nil, "OVERLAY")
                check:SetSize(16, 16)
                check:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            end

            local rowIdx = i
            row:SetScript("OnClick", function() PR:OnAccept(rowIdx) end)

            tinsert(proposalRows, row)
        end
    end
end

------------------------------------------------------------
-- Position management
------------------------------------------------------------
local function AnchorToastFrame(f, position)
    position = position or currentPosition or DEFAULT_POSITION
    f:ClearAllPoints()
    
    if position == PR.POSITIONS.TOP_CENTER then
        f:SetPoint("TOP", UIParent, "TOP", 0, -80)
    elseif position == PR.POSITIONS.CENTER then
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    elseif position == PR.POSITIONS.TOP_RIGHT then
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -80)
    elseif position == PR.POSITIONS.BOTTOM_CENTER then
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 80)
    end
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------
function PR:Init()
    toast = CreateToast()
end

function PR:SetPosition(position)
    -- Normalize position key: "top-center" or "top_center" -> "TOP_CENTER"
    local normalized = position:upper():gsub("-", "_")
    if PR.POSITIONS[normalized] then
        currentPosition = position
        if toast then
            AnchorToastFrame(toast, position)
        end
        return true
    end
    return false
end

function PR:GetPosition()
    return currentPosition or DEFAULT_POSITION
end

-- assignments = array of { specIndex, loadoutID }
function PR:Show(assignments, zoneInfo)
    if not toast then
        return
    end
    if not assignments or #assignments == 0 then
        return
    end

    currentAssignments = assignments
    currentZoneInfo    = zoneInfo

    local numRows  = #assignments
    local showHint = (numRows >= 2)

    -- Toast height
    local rowsH  = numRows * ROW_H + math.max(0, numRows - 1) * ROW_GAP
    local hintH  = showHint and (HINT_H + 4) or 0
    local totalH = PADDING + HEADER_H + SEP_H + 8 + rowsH + 8 + hintH + TIMER_H + PADDING
    toast:SetSize(TOAST_W, totalH)
    AnchorToastFrame(toast, currentPosition)

    toast._header:SetText(zoneInfo.instanceName or zoneInfo.category or "")

    BuildRows(assignments)

    if showHint then
        local keys = {}
        for i = 1, numRows do tinsert(keys, tostring(i)) end
        toast._hint:SetText(string.format(L["PROPOSAL_HINT"], table.concat(keys, "-")))
        toast._hint:Show()
    else
        toast._hint:Hide()
    end

    -- Start timer bar at full width
    state.timerElapsed = 0
    state.timerRunning = true
    toast._timerFill:SetWidth(TOAST_W - PADDING * 2)

    toast:EnableKeyboard(true)
    StartFadeIn()
end

-- User picked option at position idx
function PR:OnAccept(idx)
    if not currentAssignments or not currentAssignments[idx] then return end

    state.timerRunning = false
    toast:EnableKeyboard(false)
    SetRowsEnabled(false)

    -- Dim non-chosen rows
    for i, row in ipairs(proposalRows) do
        if i ~= idx then row:SetAlpha(0.3) end
    end

    local chosen   = currentAssignments[idx]
    local specInfo = AnySpec.SpecManager:GetSpecInfo(chosen.specIndex)
    local label    = specInfo and specInfo.name or ("Spec " .. chosen.specIndex)

    local ok, err = AnySpec.SpecManager:SwitchSpec(chosen.specIndex, chosen.loadoutID)

    if not ok then
        toast._header:SetText("|cffff4444" .. (err or L["PROPOSAL_SWITCH_FAILED"]) .. "|r")
        SetRowsEnabled(true)
        toast:EnableKeyboard(true)
        state.timerElapsed = 0
        state.timerRunning = true
        return
    end

    toast._header:SetText(string.format(L["PROPOSAL_SWITCHING"], label))
    currentAssignments = nil
    currentZoneInfo    = nil
    C_Timer.After(3, function()
        if toast:IsShown() then PR:_HideNoCD() end
    end)
end

-- Explicit dismiss: sets cooldown so proposal won't re-appear for 60 s
function PR:OnDismiss()
    if not toast or not toast:IsShown() then return end
    PR:_HideWithCD()
end

-- Hide and record dismiss cooldown (user explicitly dismissed)
function PR:_HideWithCD()
    state.timerRunning = false
    if currentZoneInfo then
        AnySpec.AutoSwitch:OnProposalDismissed(currentZoneInfo)
    end
    currentAssignments = nil
    currentZoneInfo    = nil
    toast:EnableKeyboard(false)
    if toast:IsShown() then StartFadeOut(nil) end
end

-- Hide without cooldown (timer expiry)
function PR:_HideNoCD()
    state.timerRunning = false
    currentAssignments = nil
    currentZoneInfo    = nil
    toast:EnableKeyboard(false)
    if toast:IsShown() then StartFadeOut(nil) end
end

-- Called externally (e.g. combat start): hide silently, no dismiss cooldown.
function PR:Hide()
    if not toast or not toast:IsShown() then return end
    self:_HideNoCD()
end

-- Called when combat starts while toast is visible
function PR:OnSpecSwitchFailed()
    if not toast or not toast:IsShown() then return end
    toast._header:SetText("|cffff4444" .. L["PROPOSAL_SWITCH_FAILED"] .. "|r")
    SetRowsEnabled(true)
    toast:EnableKeyboard(true)
    state.timerElapsed = 0
    state.timerRunning = true
end
