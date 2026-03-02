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
------------------------------------------------------------
local function BuildSpecRows(parent)
    for _, row in ipairs(specRows) do
        row:Hide()
    end
    wipe(specRows)

    local specs = AnySpec.SpecManager:GetAllSpecs()
    local currentSpec = AnySpec.SpecManager:GetCurrentSpecIndex()
    local activeConfigID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() or nil
    local width = 280

    for specIdx, spec in ipairs(specs) do
        local row = CreateFrame("Button", nil, parent)
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
        hotkeyNum:SetText(tostring(specIdx))
        hotkeyNum:SetTextColor(0.7, 0.7, 1)

        -- Icon
        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ICON_SIZE, ICON_SIZE)
        iconTex:SetPoint("LEFT", row, "LEFT", 36, 0)
        iconTex:SetTexture(spec.icon)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Spec name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 8, 0)
        nameText:SetText(spec.name)

        -- Get available loadouts for this spec
        local loadouts = AnySpec.SpecManager:GetLoadoutsForSpec(specIdx)
        row.loadouts = loadouts -- Store for tooltip access
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
        
        -- Loadout dropdown (only show if there are loadouts)
        if #loadouts > 0 then
            -- Label
            local loadoutLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            loadoutLabel:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -6)
            loadoutLabel:SetText(L["QS_LOADOUT_LABEL"])
            loadoutLabel:SetTextColor(0.7, 0.7, 0.7)

            local labelWidth = math.floor(loadoutLabel:GetStringWidth() + 0.5)
            local rightReserve = (currentSpec == specIdx) and 24 or 8
            local availableDropdownWidth = ROW_WIDTH - (84 + labelWidth + 4) - rightReserve
            local dropdownWidth = math.max(98, math.min(availableDropdownWidth, 126))
            local menuButtonWidth = dropdownWidth - 6
            
            -- Dropdown button (adjusted width to fit in row)
            local dropdownBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            dropdownBtn:SetSize(dropdownWidth, 20)
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
            
            -- Dropdown text
            local dropdownText = dropdownBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dropdownText:SetPoint("LEFT", dropdownBtn, "LEFT", 6, 0)
            dropdownText:SetPoint("RIGHT", dropdownBtn, "RIGHT", -20, 0)
            dropdownText:SetJustifyH("LEFT")
            if row.currentTalentsUnsaved then
                dropdownText:SetText(L["QS_LOADOUT_UNSAVED"])
                dropdownText:SetTextColor(1, 0.82, 0)
            else
                dropdownText:SetText(L["QS_LOADOUT_SELECT"])
                dropdownText:SetTextColor(1, 1, 1)
            end
            dropdownBtn.text = dropdownText
            
            -- Dropdown arrow
            local arrow = dropdownBtn:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(12, 12)
            arrow:SetPoint("RIGHT", dropdownBtn, "RIGHT", -4, 0)
            arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
            
            -- Create menu frame
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
            
            -- Build menu items from available loadouts
            local menuItems = {}
            if row.currentTalentsUnsaved then
                table.insert(menuItems, { name = "Current (unsaved)", configID = nil, isInfo = true })
            end
            for _, loadout in ipairs(loadouts) do
                table.insert(menuItems, { name = loadout.name, configID = loadout.configID })
            end
            
            -- Create menu item buttons
            local menuButtons = {}
            local menuHeight = 6
            for idx, item in ipairs(menuItems) do
                local menuBtn = CreateFrame("Button", nil, menu)
                menuBtn:SetSize(menuButtonWidth, 20)
                menuBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                
                if idx == 1 then
                    menuBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -3)
                else
                    menuBtn:SetPoint("TOPLEFT", menuButtons[idx - 1], "BOTTOMLEFT", 0, -2)
                end
                
                -- Menu item text
                local itemText = menuBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                itemText:SetPoint("LEFT", menuBtn, "LEFT", 20, 0)
                itemText:SetText(item.name)
                if item.isInfo then
                    itemText:SetTextColor(1, 0.82, 0)
                else
                    itemText:SetTextColor(1, 1, 1)
                end
                menuBtn.itemText = itemText
                
                -- Checkmark (hidden by default)
                local check = menuBtn:CreateTexture(nil, "OVERLAY")
                check:SetSize(12, 12)
                check:SetPoint("LEFT", menuBtn, "LEFT", 4, 0)
                check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                check:Hide()
                menuBtn.checkmark = check
                
                menuBtn:SetScript("OnClick", function(self)
                    if item.isInfo then
                        menu:Hide()
                        return
                    end

                    -- Update selection
                    selectedLoadoutsBySpec[specIdx] = item.configID
                    
                    -- Update dropdown text
                    dropdownText:SetText(item.name)
                    dropdownText:SetTextColor(1, 1, 1)
                    
                    -- Update checkmarks
                    for _, btn in ipairs(menuButtons) do
                        btn.checkmark:Hide()
                    end
                    self.checkmark:Show()
                    
                    -- Hide menu
                    menu:Hide()
                    
                    -- Print feedback
                    print(string.format(L["QS_SELECTED_LOADOUT"], item.name, spec.name))
                end)
                
                table.insert(menuButtons, menuBtn)
                menuHeight = menuHeight + 22
            end
            
            menu:SetSize(dropdownWidth, menuHeight)
            menu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
            
            -- Dropdown button click handler
            dropdownBtn:SetScript("OnClick", function(self)
                if menu:IsShown() then
                    menu:Hide()
                else
                    menu:Show()
                end
            end)
            
            -- Hide menu when clicking elsewhere
            menu:SetScript("OnHide", function()
                if menu._closeFrame then
                    menu._closeFrame:Hide()
                end
            end)
            
            menu:SetScript("OnShow", function()
                C_Timer.After(0.05, function()
                    if not menu:IsShown() then return end
                    menu._closeFrame = menu._closeFrame or CreateFrame("Button", nil, UIParent)
                    menu._closeFrame:SetAllPoints(UIParent)
                    menu._closeFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                    menu._closeFrame:SetFrameLevel(menu:GetFrameLevel() - 1)
                    menu._closeFrame:SetScript("OnClick", function()
                        menu:Hide()
                    end)
                    menu._closeFrame:Show()
                end)
            end)
            
            -- Initialize: restore previous selection if any
            if selectedLoadoutsBySpec[specIdx] ~= nil then
                for idx, btn in ipairs(menuButtons) do
                    if menuItems[idx].configID == selectedLoadoutsBySpec[specIdx] then
                        btn.checkmark:Show()
                        dropdownText:SetText(menuItems[idx].name)
                        if menuItems[idx].isInfo then
                            dropdownText:SetTextColor(1, 0.82, 0)
                        else
                            dropdownText:SetTextColor(1, 1, 1)
                        end
                        break
                    end
                end
            end
            
            row.dropdownBtn = dropdownBtn
            row.menu = menu
        end

        -- Active indicator (green checkmark)
        if currentSpec == specIdx then
            nameText:SetTextColor(0.2, 1, 0.2)
            local checkmark = row:CreateTexture(nil, "OVERLAY")
            checkmark:SetSize(16, 16)
            checkmark:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            checkmark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        else
            nameText:SetTextColor(1, 1, 1)
        end

        -- Click handler
        row:SetScript("OnClick", function()
            local loadoutToUse = selectedLoadoutsBySpec[specIdx]
            if loadoutToUse then
                print(string.format(L["QS_SWITCHING_WITH_LOADOUT"], spec.name))
            else
                print(string.format(L["QS_SWITCHING"], spec.name))
            end
            AnySpec.SpecManager:SwitchSpec(specIdx, loadoutToUse)
            QS:Hide()
        end)

        -- Hover tooltip
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(spec.name, 0.2, 1, 0.2)
            GameTooltip:AddLine(spec.description, 0.7, 0.7, 0.7, true)

            if self.currentTalentsUnsaved then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Current talents are not saved as a loadout.", 1, 0.82, 0, true)
            end
            
            -- Show selected loadout if any
            if selectedLoadoutsBySpec[specIdx] then
                GameTooltip:AddLine(" ")
                local loadoutName = "Unknown"
                for _, loadout in ipairs(self.loadouts) do
                    if loadout.configID == selectedLoadoutsBySpec[specIdx] then
                        loadoutName = loadout.name
                        break
                    end
                end
                GameTooltip:AddLine("Loadout: |cff00ff00" .. loadoutName .. "|r", 1, 1, 1)
            end
            
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        specRows[specIdx] = row
    end

    -- Layout rows
    local y = -PADDING
    for specIdx, row in ipairs(specRows) do
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, y)
        y = y - (ROW_HEIGHT + 4)
    end

    -- Resize modal
    local totalHeight = #specRows * (ROW_HEIGHT + 4) + PADDING * 2
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
    print(L["QS_INTRO_TIP"])
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
