-- AnySpec/UI/QuickSwitch.lua
-- Centered spec selector modal with keyboard shortcuts (1-4) and loadout support.
-- The ANYSPEC_SWITCH button is invisible (1x1); it is only used via /click macro on action bars.

AnySpec = AnySpec or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.QuickSwitch = AnySpec.UI.QuickSwitch or {}
local QS = AnySpec.UI.QuickSwitch
local L  = AnySpec.L

local PADDING     = 12
local ROW_HEIGHT  = 60
local ICON_SIZE   = 40
local ROW_WIDTH   = 280 - PADDING * 2

local modal = nil
local clickHandler = nil
local specRows = {}
local selectedLoadoutsBySpec = {} -- [specIndex] = configID
local introTipShown = false       -- intro tip is printed once per session, not per open

------------------------------------------------------------
-- Create the centered modal frame
------------------------------------------------------------
local function CreateModal()
    local f = CreateFrame("Frame", "AnySpecQuickSwitchModal", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:Hide()

    -- Dark backdrop matching MainFrame
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = false,
        tileSize = 16,
        edgeSize = 14,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0.28, 0.28, 0.32, 1)

    f:EnableMouse(true)
    tinsert(UISpecialFrames, "AnySpecQuickSwitchModal")

    -- Close when clicking elsewhere
    f:SetScript("OnShow", function(self)
        C_Timer.After(0.05, function()
            if not f:IsShown() then return end
            f._closeFrame = f._closeFrame or CreateFrame("Button", nil, UIParent)
            f._closeFrame:SetAllPoints(UIParent)
            f._closeFrame:SetFrameStrata("DIALOG")
            f._closeFrame:SetFrameLevel(f:GetFrameLevel() - 1)
            f._closeFrame:SetScript("OnClick", function()
                QS:Hide()
            end)
            f._closeFrame:Show()
        end)
    end)

    f:SetScript("OnHide", function()
        if f._closeFrame then
            f._closeFrame:Hide()
        end
    end)

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
-- Build spec rows in the modal
--
-- Rows (and their per-row loadout dropdown menus) are pooled and reused across
-- opens/refreshes. Each row's scripts are created once and read mutable
-- row._* fields, so nothing is recreated per open — avoiding a frame leak on a
-- panel that is rebuilt every time it is shown or the spec changes.
-- The spec count is stable for a character, so the row pool size is stable.
------------------------------------------------------------

-- Create (once) or fetch the pooled loadout-menu item button at the given index.
-- The OnClick reads self._item / row._* so it needs no per-open recreation.
local function AcquireMenuButton(row, idx)
    local pool = row._menuButtons
    local mb = pool[idx]
    if mb then return mb end

    mb = CreateFrame("Button", nil, row._menu)
    mb:SetSize(row._menuButtonWidth or 100, 20)
    mb:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    if idx == 1 then
        mb:SetPoint("TOPLEFT", row._menu, "TOPLEFT", 3, -3)
    else
        mb:SetPoint("TOPLEFT", pool[idx - 1], "BOTTOMLEFT", 0, -2)
    end

    local itemText = mb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemText:SetPoint("LEFT", mb, "LEFT", 20, 0)
    mb.itemText = itemText

    local check = mb:CreateTexture(nil, "OVERLAY")
    check:SetSize(12, 12)
    check:SetPoint("LEFT", mb, "LEFT", 4, 0)
    check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    check:Hide()
    mb.checkmark = check

    mb:SetScript("OnClick", function(self)
        local item = self._item
        if not item then return end
        if item.isInfo then
            row._menu:Hide()
            return
        end
        selectedLoadoutsBySpec[row._specIdx] = item.configID
        row._dropdownText:SetText(item.name)
        row._dropdownText:SetTextColor(1, 1, 1)
        for _, b in ipairs(row._menuButtons) do
            b.checkmark:Hide()
        end
        self.checkmark:Show()
        row._menu:Hide()
        print(string.format(L["QS_SELECTED_LOADOUT"], item.name, row._spec.name))
    end)

    pool[idx] = mb
    return mb
end

-- Create (once) or fetch the pooled spec row at the given index.
local function AcquireSpecRow(index)
    local row = specRows[index]
    if row then return row end

    row = CreateFrame("Button", nil, modal)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    -- Hotkey background + number
    local hotkeyBg = row:CreateTexture(nil, "BACKGROUND")
    hotkeyBg:SetSize(28, 28)
    hotkeyBg:SetPoint("LEFT", row, "LEFT", 4, 0)
    hotkeyBg:SetColorTexture(0.15, 0.15, 0.15, 0.7)

    local hotkeyNum = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hotkeyNum:SetSize(28, 28)
    hotkeyNum:SetPoint("CENTER", hotkeyBg, "CENTER", 0, 0)
    hotkeyNum:SetTextColor(0.7, 0.7, 1)
    row._hotkeyNum = hotkeyNum

    -- Icon
    local iconTex = row:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(ICON_SIZE, ICON_SIZE)
    iconTex:SetPoint("LEFT", row, "LEFT", 36, 0)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row._icon = iconTex

    -- Spec name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 8, 0)
    row._name = nameText

    -- Active-spec indicator (shown only when this is the current spec)
    local activeCheck = row:CreateTexture(nil, "OVERLAY")
    activeCheck:SetSize(16, 16)
    activeCheck:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    activeCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    activeCheck:Hide()
    row._activeCheck = activeCheck

    -- Loadout label (text is constant)
    local loadoutLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    loadoutLabel:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -6)
    loadoutLabel:SetText(L["QS_LOADOUT_LABEL"])
    loadoutLabel:SetTextColor(0.7, 0.7, 0.7)
    row._loadoutLabel = loadoutLabel

    -- Loadout dropdown button
    local dropdownBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    dropdownBtn:SetSize(100, 20)
    dropdownBtn:SetPoint("LEFT", loadoutLabel, "RIGHT", 4, 0)
    dropdownBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dropdownBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    dropdownBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    row._dropdownBtn = dropdownBtn

    local dropdownText = dropdownBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropdownText:SetPoint("LEFT", dropdownBtn, "LEFT", 6, 0)
    dropdownText:SetPoint("RIGHT", dropdownBtn, "RIGHT", -20, 0)
    dropdownText:SetJustifyH("LEFT")
    dropdownBtn.text = dropdownText
    row._dropdownText = dropdownText

    local arrow = dropdownBtn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", dropdownBtn, "RIGHT", -4, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

    -- Menu frame
    local menu = CreateFrame("Frame", nil, dropdownBtn, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    menu:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    menu:Hide()
    menu:EnableMouse(true)
    menu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
    row._menu = menu
    row._menuButtons = {}

    dropdownBtn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide() else menu:Show() end
    end)

    menu:SetScript("OnHide", function()
        if menu._closeFrame then menu._closeFrame:Hide() end
    end)
    menu:SetScript("OnShow", function()
        C_Timer.After(0.05, function()
            if not menu:IsShown() then return end
            menu._closeFrame = menu._closeFrame or CreateFrame("Button", nil, UIParent)
            menu._closeFrame:SetAllPoints(UIParent)
            menu._closeFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            menu._closeFrame:SetFrameLevel(menu:GetFrameLevel() - 1)
            menu._closeFrame:SetScript("OnClick", function() menu:Hide() end)
            menu._closeFrame:Show()
        end)
    end)

    -- Row click: switch to this spec (with any selected loadout)
    row:SetScript("OnClick", function()
        local loadoutToUse = selectedLoadoutsBySpec[row._specIdx]
        local ok, err = AnySpec.SpecManager:SwitchSpec(row._specIdx, loadoutToUse)
        if not ok then
            -- Leave the popup open so the reason (e.g. combat) stays visible.
            print("|cffff4444" .. L["ADDON_PREFIX"] .. ":|r " .. (err or L["PROPOSAL_SWITCH_FAILED"]))
            return
        end
        if loadoutToUse then
            print(string.format(L["QS_SWITCHING_WITH_LOADOUT"], row._spec.name))
        else
            print(string.format(L["QS_SWITCHING"], row._spec.name))
        end
        QS:Hide()
    end)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self._spec.name, 0.2, 1, 0.2)
        GameTooltip:AddLine(self._spec.description, 0.7, 0.7, 0.7, true)

        if self.currentTalentsUnsaved then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Current talents are not saved as a loadout.", 1, 0.82, 0, true)
        end

        local selected = selectedLoadoutsBySpec[self._specIdx]
        if selected then
            GameTooltip:AddLine(" ")
            local loadoutName = "Unknown"
            for _, loadout in ipairs(self.loadouts or {}) do
                if loadout.configID == selected then
                    loadoutName = loadout.name
                    break
                end
            end
            GameTooltip:AddLine("Loadout: |cff00ff00" .. loadoutName .. "|r", 1, 1, 1)
        end

        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    specRows[index] = row
    return row
end

-- Reconfigure a pooled row for the given spec.
local function ConfigureSpecRow(row, specIdx, spec, currentSpec, activeConfigID)
    row._specIdx = specIdx
    row._spec    = spec

    row._hotkeyNum:SetText(tostring(specIdx))
    row._icon:SetTexture(spec.icon)
    row._name:SetText(spec.name)

    -- Available loadouts + "current talents unsaved" detection
    local loadouts = AnySpec.SpecManager:GetLoadoutsForSpec(specIdx)
    row.loadouts = loadouts  -- for tooltip access
    row.currentTalentsUnsaved = false
    if currentSpec == specIdx and activeConfigID then
        row.currentTalentsUnsaved = true
        for _, loadout in ipairs(loadouts) do
            if loadout.configID == activeConfigID then
                row.currentTalentsUnsaved = false
                break
            end
        end
    end

    -- Active-spec indicator + name colour
    if currentSpec == specIdx then
        row._name:SetTextColor(0.2, 1, 0.2)
        row._activeCheck:Show()
    else
        row._name:SetTextColor(1, 1, 1)
        row._activeCheck:Hide()
    end

    row._menu:Hide()

    if #loadouts > 0 then
        local labelWidth   = math.floor(row._loadoutLabel:GetStringWidth() + 0.5)
        local rightReserve = (currentSpec == specIdx) and 24 or 8
        local availableDropdownWidth = ROW_WIDTH - (84 + labelWidth + 4) - rightReserve
        local dropdownWidth   = math.max(98, math.min(availableDropdownWidth, 126))
        local menuButtonWidth = dropdownWidth - 6
        row._menuButtonWidth  = menuButtonWidth
        row._dropdownBtn:SetSize(dropdownWidth, 20)

        -- Default dropdown label
        if row.currentTalentsUnsaved then
            row._dropdownText:SetText(L["QS_LOADOUT_UNSAVED"])
            row._dropdownText:SetTextColor(1, 0.82, 0)
        else
            row._dropdownText:SetText(L["QS_LOADOUT_SELECT"])
            row._dropdownText:SetTextColor(1, 1, 1)
        end

        -- Build menu item list
        local menuItems = {}
        if row.currentTalentsUnsaved then
            tinsert(menuItems, { name = "Current (unsaved)", configID = nil, isInfo = true })
        end
        for _, loadout in ipairs(loadouts) do
            tinsert(menuItems, { name = loadout.name, configID = loadout.configID })
        end

        -- Configure pooled menu buttons
        local menuHeight = 6
        for idx, item in ipairs(menuItems) do
            local mb = AcquireMenuButton(row, idx)
            mb:SetSize(menuButtonWidth, 20)
            mb._item = item
            mb.itemText:SetText(item.name)
            if item.isInfo then
                mb.itemText:SetTextColor(1, 0.82, 0)
            else
                mb.itemText:SetTextColor(1, 1, 1)
            end
            mb.checkmark:Hide()
            mb:Show()
            menuHeight = menuHeight + 22
        end
        for idx = #menuItems + 1, #row._menuButtons do
            row._menuButtons[idx]._item = nil
            row._menuButtons[idx]:Hide()
        end

        row._menu:SetSize(dropdownWidth, menuHeight)

        -- Restore previous selection if any
        local selected = selectedLoadoutsBySpec[specIdx]
        if selected ~= nil then
            for idx, item in ipairs(menuItems) do
                if item.configID == selected then
                    row._menuButtons[idx].checkmark:Show()
                    row._dropdownText:SetText(item.name)
                    row._dropdownText:SetTextColor(1, 1, 1)
                    break
                end
            end
        end

        row._loadoutLabel:Show()
        row._dropdownBtn:Show()
    else
        row._loadoutLabel:Hide()
        row._dropdownBtn:Hide()
        for idx = 1, #row._menuButtons do
            row._menuButtons[idx]:Hide()
        end
    end

    row:Show()
end

local function BuildSpecRows(parent)
    local specs = AnySpec.SpecManager:GetAllSpecs()
    local currentSpec = AnySpec.SpecManager:GetCurrentSpecIndex()
    local activeConfigID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() or nil
    local width = 280

    local y = -PADDING
    for specIdx, spec in ipairs(specs) do
        local row = AcquireSpecRow(specIdx)
        ConfigureSpecRow(row, specIdx, spec, currentSpec, activeConfigID)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, y)
        y = y - (ROW_HEIGHT + 4)
    end

    -- Hide any pooled rows left over from a class with more specs (defensive)
    for i = #specs + 1, #specRows do
        specRows[i]:Hide()
    end

    -- Resize modal
    local totalHeight = #specs * (ROW_HEIGHT + 4) + PADDING * 2
    parent:SetSize(width, totalHeight)
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
    if not introTipShown then
        print(L["QS_INTRO_TIP"])
        introTipShown = true
    end
end

function QS:Hide()
    if modal then
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
end

function QS:UpdateButtonIcon()
    -- Icon is now on the minimap button
    if AnySpec.UI.MinimapButton then
        AnySpec.UI.MinimapButton:UpdateIcon()
    end
end
