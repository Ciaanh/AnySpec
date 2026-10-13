-- AnySpec/UI/QuickSwitch.lua
-- Centered spec selector popup with loadout support.
-- The ANYSPEC_SWITCH button is invisible (1x1); it is only used via /click macro on action bars.

AnySpec = AnySpec or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.QuickSwitch = AnySpec.UI.QuickSwitch or {}
local QS = AnySpec.UI.QuickSwitch
local L  = AnySpec.L
local T  = AnySpec.UI.Theme
local W  = AnySpec.UI.Widgets
local C  = T.C

local MODAL_W     = 380
local PADDING     = 12
local TITLE_H     = 26
local FOOTER_H    = 26
local ROW_HEIGHT  = 62
local ROW_GAP     = 6
local ICON_SIZE   = 40

local modal = nil
local clickHandler = nil
local specRows = {}               -- pooled rows, [specIndex] = row
local selectedLoadoutsBySpec = {} -- [specIndex] = configID

------------------------------------------------------------
-- Create the centered modal frame
------------------------------------------------------------
local function CreateModal()
    local f = CreateFrame("Frame", "AnySpecQuickSwitchModal", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetWidth(MODAL_W)
    f:Hide()
    T:Surface(f, C.window, C.border)
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "AnySpecQuickSwitchModal")

    local title = T:Text(f, 12, C.muted)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING + 4, -PADDING - 4)
    title:SetText(L["QS_TITLE"]:upper())

    local esc = T:Text(f, 12, C.faint)
    esc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING - 4, -PADDING - 4)
    esc:SetText("Esc")

    local footer = T:Text(f, 12, C.faint)
    footer:SetJustifyH("CENTER")
    footer:SetPoint("BOTTOM", f, "BOTTOM", 0, PADDING + 2)
    footer:SetText(L["QS_INTRO_TIP"])

    -- Close when clicking elsewhere
    W.AttachClickOutside(f, "DIALOG", function() QS:Hide() end)

    return f
end

------------------------------------------------------------
-- Named click handler (invisible, for /click ANYSPEC_SWITCH macro)
------------------------------------------------------------

local function CreateClickHandler()
    local btn = CreateFrame("Button", "ANYSPEC_SWITCH", UIParent, "SecureHandlerClickTemplate")
    btn:SetSize(1, 1)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10) -- off-screen
    btn:RegisterForClicks("AnyUp")

    btn:SetScript("OnClick", function()
        QS:Toggle()
    end)

    return btn
end

------------------------------------------------------------
-- Spec rows (created once per spec index, refreshed on every show)
------------------------------------------------------------
local function CreateSpecRow(parent, specIdx)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(MODAL_W - PADDING * 2, ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    local badge = CreateFrame("Frame", nil, row, "BackdropTemplate")
    badge:SetSize(24, 24)
    badge:SetPoint("LEFT", row, "LEFT", 10, 0)
    T:Surface(badge, C.surfaceHi, C.borderHi)
    local num = T:Text(badge, 13, C.textDim)
    num:SetJustifyH("CENTER")
    num:SetPoint("CENTER")
    num:SetText(tostring(specIdx))

    -- Icon with an accent ring when active
    local ring = CreateFrame("Frame", nil, row, "BackdropTemplate")
    ring:SetSize(ICON_SIZE + 4, ICON_SIZE + 4)
    ring:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    local icon = T:Icon(ring, ICON_SIZE, nil)
    icon:SetPoint("CENTER")
    row._ring, row._icon = ring, icon

    local nameText = T:Text(row, 16, C.text)
    nameText:SetPoint("TOPLEFT", ring, "TOPRIGHT", 10, -1)
    row._name = nameText

    local ar, ag, ab = T:GetAccent()
    local active = CreateFrame("Frame", nil, row, "BackdropTemplate")
    active:SetHeight(16)
    active:SetPoint("LEFT", nameText, "RIGHT", 8, 0)
    T:Surface(active, { ar, ag, ab, 1 }, { ar, ag, ab, 1 })
    local activeText = T:Text(active, 11, C.onAccent)
    activeText:SetPoint("CENTER")
    activeText:SetText(L["QS_ACTIVE"]:upper())
    active:SetWidth(math.ceil(activeText:GetStringWidth()) + 12)
    row._active = active

    local dropdown = W.CreateCustomDropdown(row, 170, 22)
    dropdown:SetPoint("BOTTOMLEFT", ring, "BOTTOMRIGHT", 10, 1)
    dropdown:SetOnChanged(function(value)
        selectedLoadoutsBySpec[specIdx] = value
    end)
    row._dropdown = dropdown

    local noLoadouts = T:Text(row, 13, C.muted)
    noLoadouts:SetPoint("BOTTOMLEFT", ring, "BOTTOMRIGHT", 10, 4)
    noLoadouts:SetText(L["LOADOUT_DEFAULT"])
    row._noLoadouts = noLoadouts

    local chev = T:Glyph(row, "chevron-right", 12, C.faint)
    chev:SetPoint("RIGHT", row, "RIGHT", -12, 0)

    row:SetScript("OnClick", function()
        local loadoutToUse = selectedLoadoutsBySpec[specIdx]
        local spec = AnySpec.SpecManager:GetSpecInfo(specIdx)
        local specName = spec and spec.name or tostring(specIdx)
        local ok, err = AnySpec.SpecManager:SwitchSpec(specIdx, loadoutToUse)
        if not ok then
            -- Leave the popup open so the reason (e.g. combat) stays visible.
            print("|cffff4444" .. L["ADDON_PREFIX"] .. ":|r " .. (err or L["PROPOSAL_SWITCH_FAILED"]))
            return
        end
        if loadoutToUse then
            print(string.format(L["QS_SWITCHING_WITH_LOADOUT"], specName))
        else
            print(string.format(L["QS_SWITCHING"], specName))
        end
        QS:Hide()
    end)

    row:SetScript("OnEnter", function(self)
        T:Surface(self, self._isCurrent and C.selected or C.surfaceHi,
                  self._isCurrent and self._activeBorder or C.borderHi)
        local spec = AnySpec.SpecManager:GetSpecInfo(specIdx)
        if not spec then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(spec.name, 1, 1, 1)
        GameTooltip:AddLine(spec.description, 0.7, 0.7, 0.7, true)
        if self.currentTalentsUnsaved then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["QS_UNSAVED_TIP"], 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self:Paint()
        GameTooltip:Hide()
    end)

    function row:Paint()
        if self._isCurrent then
            T:Surface(self, C.selected, self._activeBorder)
        else
            T:Surface(self, C.surface, C.border)
        end
    end

    return row
end

local function BuildSpecRows(parent)
    local specs = AnySpec.SpecManager:GetAllSpecs()
    local currentSpec = AnySpec.SpecManager:GetCurrentSpecIndex()
    local activeConfigID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() or nil
    local ar, ag, ab = T:GetAccent()

    for _, row in pairs(specRows) do row:Hide() end

    local y = -(PADDING + TITLE_H)
    for specIdx, spec in ipairs(specs) do
        local row = specRows[specIdx] or CreateSpecRow(parent, specIdx)
        specRows[specIdx] = row

        local isCurrent = (currentSpec == specIdx)
        row._isCurrent = isCurrent
        row._activeBorder = { ar * 0.55, ag * 0.55, ab * 0.55, 1 }
        row._icon:SetTexture(spec.icon)
        row._name:SetText(spec.name)
        row._active:SetShown(isCurrent)
        if isCurrent then
            T:Surface(row._ring, { 0, 0, 0, 0 }, { ar, ag, ab, 1 })
        else
            T:Surface(row._ring, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
        end

        local loadouts = AnySpec.SpecManager:GetLoadoutsForSpec(specIdx)
        row.currentTalentsUnsaved = false
        if isCurrent and activeConfigID then
            row.currentTalentsUnsaved = true
            for _, loadout in ipairs(loadouts) do
                if loadout.configID == activeConfigID then
                    row.currentTalentsUnsaved = false
                    break
                end
            end
        end

        if #loadouts > 0 then
            local items = {}
            for _, loadout in ipairs(loadouts) do
                tinsert(items, { label = loadout.name, value = loadout.configID })
            end
            row._dropdown:SetItems(items)
            row._dropdown:SetPlaceholder(row.currentTalentsUnsaved
                and ("|cffffd100" .. L["QS_LOADOUT_UNSAVED"] .. "|r")
                or L["QS_LOADOUT_SELECT"])
            if selectedLoadoutsBySpec[specIdx] ~= nil then
                row._dropdown:SetSelected(selectedLoadoutsBySpec[specIdx])
            else
                row._dropdown:ClearSelection()
            end
            row._dropdown:Show()
            row._noLoadouts:Hide()
        else
            row._dropdown:Hide()
            row._noLoadouts:Show()
        end

        row:Paint()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, y)
        row:Show()
        y = y - (ROW_HEIGHT + ROW_GAP)
    end

    parent:SetHeight(PADDING + TITLE_H + #specs * (ROW_HEIGHT + ROW_GAP) + FOOTER_H + PADDING)
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

function QS:Init()
    modal = CreateModal()
    clickHandler = CreateClickHandler()
end

function QS:Toggle()
    if modal:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function QS:Show()
    BuildSpecRows(modal)

    -- Center on screen
    modal:ClearAllPoints()
    modal:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    modal:Show()
end

function QS:Hide()
    if modal then
        for _, row in pairs(specRows) do row._dropdown:CloseMenu() end
        modal:Hide()
    end
end

function QS:Refresh()
    if modal and modal:IsShown() then
        BuildSpecRows(modal)
    end
    -- Update minimap button icon when spec changes
    if AnySpec.UI.MinimapButton then
        AnySpec.UI.MinimapButton:UpdateIcon()
    end
    if AnySpec.UI.MainFrame and AnySpec.UI.MainFrame.OnSpecChanged then
        AnySpec.UI.MainFrame:OnSpecChanged()
    end
end

function QS:UpdateButtonIcon()
    -- Icon is now on the minimap button
    if AnySpec.UI.MinimapButton then
        AnySpec.UI.MinimapButton:UpdateIcon()
    end
end
