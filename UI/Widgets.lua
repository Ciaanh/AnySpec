-- AnySpec/UI/Widgets.lua
-- Shared reusable UI widget factories

AnySpec    = AnySpec    or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.Widgets = AnySpec.UI.Widgets or {}
local W = AnySpec.UI.Widgets

------------------------------------------------------------
-- CreateCustomDropdown(parent, width)
--
-- Creates a dark-themed dropdown button with a custom menu.
--
-- Public API on the returned frame:
--   :SetItems(items)         items = { { label, value [, icon] }, ... }
--   :SetSelected(value)      selects item by value, updates label
--   :SetPlaceholder(text)    placeholder shown when nothing is selected
--   :SetOnChanged(fn)        fn(value, label) called on selection change
--   :GetSelected()           returns value, label  (nil, nil if nothing)
--   :CloseMenu()             hides the dropdown list
--
-- NOTE: value=nil is valid (used for "Default loadout").
------------------------------------------------------------
function W.CreateCustomDropdown(parent, width)
    local dropdownWidth   = width or 140
    local menuBtnWidth    = dropdownWidth - 6

    ------------------------------------------------------------
    -- Button (the "closed" face of the dropdown)
    ------------------------------------------------------------
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(dropdownWidth, 20)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = false,
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local labelText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("LEFT",  btn, "LEFT",   6,   0)
    labelText:SetPoint("RIGHT", btn, "RIGHT", -20,  0)
    labelText:SetJustifyH("LEFT")
    labelText:SetText("Select...")
    labelText:SetTextColor(0.5, 0.5, 0.5)
    btn.text = labelText

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

    ------------------------------------------------------------
    -- Menu frame (the open dropdown list)
    ------------------------------------------------------------
    local menu = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = false,
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    menu:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    menu:Hide()
    menu:EnableMouse(true)
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)

    ------------------------------------------------------------
    -- State
    ------------------------------------------------------------
    local items        = {}
    local selectedValue = nil   -- nil is a valid value (= "Default loadout")
    local hasSelection  = false -- separate flag so we can tell nil-unset from nil-selected
    local onChangedFn  = nil
    local menuButtons  = {}
    local placeholder  = "Select..."

    local function UpdateLabel()
        if not hasSelection then
            labelText:SetText(placeholder)
            labelText:SetTextColor(0.5, 0.5, 0.5)
            return
        end
        for _, item in ipairs(items) do
            if item.value == selectedValue then
                labelText:SetText(item.label)
                labelText:SetTextColor(1, 1, 1)
                return
            end
        end
        -- value not found in current items
        labelText:SetText(placeholder)
        labelText:SetTextColor(0.5, 0.5, 0.5)
    end

    local function RebuildMenuItems()
        for _, mb in ipairs(menuButtons) do
            mb:SetParent(nil)
            mb:Hide()
        end
        wipe(menuButtons)

        local menuH = 6
        for idx, item in ipairs(items) do
            local mb = CreateFrame("Button", nil, menu)
            mb:SetSize(menuBtnWidth, 20)
            mb:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

            if idx == 1 then
                mb:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -3)
            else
                mb:SetPoint("TOPLEFT", menuButtons[idx - 1], "BOTTOMLEFT", 0, -2)
            end

            -- Checkmark
            local check = mb:CreateTexture(nil, "OVERLAY")
            check:SetSize(12, 12)
            check:SetPoint("LEFT", mb, "LEFT", 4, 0)
            check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            if hasSelection and item.value == selectedValue then
                check:Show()
            else
                check:Hide()
            end
            mb.check = check

            -- Optional icon
            local textLeft = 20
            if item.icon then
                local ico = mb:CreateTexture(nil, "ARTWORK")
                ico:SetSize(14, 14)
                ico:SetPoint("LEFT", mb, "LEFT", 20, 0)
                ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                ico:SetTexture(item.icon)
                textLeft = 38
            end

            -- Label
            local lbl = mb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT",  mb, "LEFT",  textLeft, 0)
            lbl:SetPoint("RIGHT", mb, "RIGHT", -4,       0)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(item.label)
            lbl:SetTextColor(1, 1, 1)

            local capturedItem = item
            mb:SetScript("OnClick", function()
                selectedValue = capturedItem.value
                hasSelection  = true
                -- Update all checkmarks
                for _, b in ipairs(menuButtons) do b.check:Hide() end
                check:Show()
                UpdateLabel()
                menu:Hide()
                if onChangedFn then
                    onChangedFn(capturedItem.value, capturedItem.label)
                end
            end)

            tinsert(menuButtons, mb)
            menuH = menuH + 22
        end

        menu:SetSize(dropdownWidth, menuH)
    end

    -- Close-elsewhere click-catcher
    menu:SetScript("OnShow", function()
        RebuildMenuItems()
        C_Timer.After(0.05, function()
            if not menu:IsShown() then return end
            menu._closeFrame = menu._closeFrame
                or CreateFrame("Button", nil, UIParent)
            menu._closeFrame:SetAllPoints(UIParent)
            menu._closeFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            menu._closeFrame:SetFrameLevel(menu:GetFrameLevel() - 1)
            menu._closeFrame:SetScript("OnClick", function() menu:Hide() end)
            menu._closeFrame:Show()
        end)
    end)
    menu:SetScript("OnHide", function()
        if menu._closeFrame then menu._closeFrame:Hide() end
    end)

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            menu:Show()
        end
    end)

    ------------------------------------------------------------
    -- Public API
    ------------------------------------------------------------
    function btn:SetItems(newItems)
        items = newItems
    end

    function btn:SetSelected(value)
        selectedValue = value
        hasSelection  = true
        UpdateLabel()
    end

    function btn:ClearSelection()
        selectedValue = nil
        hasSelection  = false
        UpdateLabel()
    end

    function btn:SetPlaceholder(text)
        placeholder = text
        if not hasSelection then
            labelText:SetText(placeholder)
            labelText:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    function btn:SetOnChanged(fn)
        onChangedFn = fn
    end

    -- Returns (value, label) or (nil, nil) when nothing selected.
    function btn:GetSelected()
        if not hasSelection then return nil, nil end
        for _, item in ipairs(items) do
            if item.value == selectedValue then
                return selectedValue, item.label
            end
        end
        return nil, nil
    end

    function btn:HasSelection()
        return hasSelection
    end

    function btn:CloseMenu()
        menu:Hide()
    end

    return btn
end
