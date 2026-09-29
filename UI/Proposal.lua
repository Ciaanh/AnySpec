-- AnySpec/UI/Proposal.lua
-- Multi-option spec/loadout proposal toast shown on instance entry.
-- Up to 3 spec+loadout pairs are shown as clickable rows with keyboard shortcuts
-- and a countdown timer bar. Timeout fades silently with no dismiss cooldown.

AnySpec    = AnySpec    or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.Proposal = AnySpec.UI.Proposal or {}
local PR = AnySpec.UI.Proposal
local L  = AnySpec.L
local T  = AnySpec.UI.Theme
local W  = AnySpec.UI.Widgets
local C  = T.C

------------------------------------------------------------
-- Layout constants
------------------------------------------------------------
local TOAST_W          = 380
local PADDING          = 12
local HEADER_H         = 44
local ROW_H            = 50
local ROW_GAP          = 6
local TIMER_H          = 3
local HINT_H           = 16
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
    T:Surface(f, C.window, C.border)

    -- Instance name + current spec line
    local header = T:Text(f, 17, C.text)
    header:SetPoint("TOPLEFT",  f, "TOPLEFT",  PADDING + 2, -PADDING - 2)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING - 34, -PADDING - 2)
    f._header = header

    local subtitle = T:Text(f, 13, C.muted)
    subtitle:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    f._subtitle = subtitle

    local closeBtn = W.CreateIconButton(f, "close", 28)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() PR:OnDismiss() end)

    -- Timer bar along the bottom edge (shrinks as time runs out)
    local timerBg = f:CreateTexture(nil, "ARTWORK")
    timerBg:SetHeight(TIMER_H)
    timerBg:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  1, 1)
    timerBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    timerBg:SetColorTexture(T.RGBA(C.surfaceHi))
    f._timerBg = timerBg

    local timerFill = f:CreateTexture(nil, "OVERLAY")
    timerFill:SetHeight(TIMER_H)
    timerFill:SetPoint("TOPLEFT",    timerBg, "TOPLEFT",    0, 0)
    timerFill:SetPoint("BOTTOMLEFT", timerBg, "BOTTOMLEFT", 0, 0)
    timerFill:SetColorTexture(T:GetAccent())
    f._timerFill = timerFill

    -- Footer: key hint (left) + seconds remaining (right)
    local hint = T:Text(f, 12, C.faint)
    hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PADDING + 2, TIMER_H + 9)
    f._hint = hint

    local secs = T:Text(f, 12, C.faint)
    secs:SetJustifyH("RIGHT")
    secs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PADDING - 2, TIMER_H + 9)
    f._secs = secs

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
        local barW = self._timerBg:GetWidth() or (TOAST_W - 2)
        self._timerFill:SetWidth(math.max(0.1, barW * fraction))
        self._secs:SetText(math.ceil(PROPOSAL_TIMEOUT - state.timerElapsed) .. "s")

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
    local rowsTopOffset    = PADDING + HEADER_H + 8
    local ar, ag, ab       = T:GetAccent()

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

            local row = CreateFrame("Button", nil, toast, "BackdropTemplate")
            row:SetSize(TOAST_W - PADDING * 2, ROW_H)
            row:SetPoint("TOPLEFT", toast, "TOPLEFT", PADDING,
                         -(rowsTopOffset + (i - 1) * (ROW_H + ROW_GAP)))
            row:RegisterForClicks("LeftButtonUp")

            local function Paint(hover)
                if isCurrent then
                    T:Surface(row, C.selected, { ar * 0.55, ag * 0.55, ab * 0.55, 1 })
                else
                    T:Surface(row, hover and C.surfaceHi or C.surface, hover and C.borderHi or C.border)
                end
            end
            Paint(false)
            row:SetScript("OnEnter", function() Paint(true) end)
            row:SetScript("OnLeave", function() Paint(false) end)

            -- Number badge (accent on the first option)
            local badge = CreateFrame("Frame", nil, row, "BackdropTemplate")
            badge:SetSize(24, 24)
            badge:SetPoint("LEFT", row, "LEFT", 10, 0)
            local numLbl = T:Text(badge, 13, i == 1 and C.onAccent or C.textDim)
            numLbl:SetJustifyH("CENTER")
            numLbl:SetPoint("CENTER")
            numLbl:SetText(tostring(i))
            if i == 1 then
                T:Surface(badge, { ar, ag, ab, 1 }, { ar, ag, ab, 1 })
            else
                T:Surface(badge, C.surfaceHi, C.borderHi)
            end

            -- Spec icon
            local ico = T:Icon(row, 34, specInfo.icon)
            ico:SetPoint("LEFT", badge, "RIGHT", 10, 0)

            -- Spec name
            local specNameLbl = T:Text(row, 15, C.text)
            specNameLbl:SetPoint("TOPLEFT",  ico, "TOPRIGHT",  10, -1)
            specNameLbl:SetPoint("RIGHT", row, "RIGHT", -80, 0)
            specNameLbl:SetText(specInfo.name)

            -- Loadout name (smaller, dimmer)
            local loadoutLbl = T:Text(row, 13, C.muted)
            loadoutLbl:SetPoint("BOTTOMLEFT",  ico, "BOTTOMRIGHT",  10, 1)
            loadoutLbl:SetPoint("RIGHT", row, "RIGHT", -80, 0)
            if loadoutName and loadoutName ~= "" then
                loadoutLbl:SetText(loadoutName)
            else
                loadoutLbl:SetText(L["LOADOUT_DEFAULT"])
            end

            -- "Current" tag or chevron
            if isCurrent then
                local tag = T:Text(row, 12, { ar, ag, ab, 1 })
                tag:SetJustifyH("RIGHT")
                tag:SetPoint("RIGHT", row, "RIGHT", -12, 0)
                tag:SetText(L["PROPOSAL_CURRENT"])
            else
                local chev = T:Glyph(row, "chevron-right", 12, C.faint)
                chev:SetPoint("RIGHT", row, "RIGHT", -12, 0)
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
    if AnySpec.db and AnySpec.db.toastPosition then
        PR:SetPosition(AnySpec.db.toastPosition)
    end
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

    -- Toast height
    local rowsH  = numRows * ROW_H + math.max(0, numRows - 1) * ROW_GAP
    local totalH = PADDING + HEADER_H + 8 + rowsH + 12 + HINT_H + 8 + TIMER_H + 1
    toast:SetSize(TOAST_W, totalH)
    AnchorToastFrame(toast, currentPosition)

    toast._header:SetText(zoneInfo.instanceName or zoneInfo.category or "")
    local curSpec  = AnySpec.SpecManager:GetCurrentSpecIndex()
    local curInfo  = curSpec and AnySpec.SpecManager:GetSpecInfo(curSpec)
    toast._subtitle:SetText(curInfo
        and string.format(L["PROPOSAL_SUBTITLE"], "|cffffffff" .. curInfo.name .. "|r")
        or "")

    BuildRows(assignments)

    local keys = {}
    for i = 1, numRows do tinsert(keys, tostring(i)) end
    toast._hint:SetText(string.format(L["PROPOSAL_HINT"], table.concat(keys, "-")))
    toast._secs:SetText(PROPOSAL_TIMEOUT .. "s")

    -- Start timer bar at full width
    state.timerElapsed = 0
    state.timerRunning = true
    toast._timerFill:SetWidth(TOAST_W - 2)

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
    toast._subtitle:SetText("")
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
