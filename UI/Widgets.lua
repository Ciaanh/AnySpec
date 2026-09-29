-- AnySpec/UI/Widgets.lua
-- Shared reusable UI widget factories, styled with AnySpec.UI.Theme.

AnySpec    = AnySpec    or {}
AnySpec.UI = AnySpec.UI or {}
AnySpec.UI.Widgets = AnySpec.UI.Widgets or {}
local W = AnySpec.UI.Widgets
local T = AnySpec.UI.Theme
local C = T.C

------------------------------------------------------------
-- Click-outside catcher shared by popup menus.
-- Shows a full-screen invisible button just below `menu`; clicking it calls onClose.
------------------------------------------------------------
local function AttachClickOutside(menu, strata, onClose)
    menu:HookScript("OnShow", function()
        C_Timer.After(0.05, function()
            if not menu:IsShown() then return end
            menu._closeFrame = menu._closeFrame or CreateFrame("Button", nil, UIParent)
            menu._closeFrame:SetAllPoints(UIParent)
            menu._closeFrame:SetFrameStrata(strata)
            menu._closeFrame:SetFrameLevel(math.max(0, menu:GetFrameLevel() - 1))
            menu._closeFrame:SetScript("OnClick", onClose)
            menu._closeFrame:Show()
        end)
    end)
    menu:HookScript("OnHide", function()
        if menu._closeFrame then menu._closeFrame:Hide() end
    end)
end
W.AttachClickOutside = AttachClickOutside

------------------------------------------------------------
-- CreateButton(parent, text, style, width, height)
--   style: "default" (outlined), "primary" (accent fill), "ghost" (no chrome)
------------------------------------------------------------
function W.CreateButton(parent, text, style, width, height)
    style = style or "default"
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or 28)

    local fs = T:Text(btn, 13, style == "primary" and C.onAccent or C.text)
    fs:SetJustifyH("CENTER")
    fs:SetPoint("LEFT", btn, "LEFT", 8, 0)
    fs:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn:SetFontString(fs)
    btn:SetText(text or "")

    local ar, ag, ab = T:GetAccent()
    local function Paint(hover)
        if style == "primary" then
            local k = hover and 1.1 or 1
            T:Surface(btn, { math.min(ar * k, 1), math.min(ag * k, 1), math.min(ab * k, 1), 1 },
                           { ar, ag, ab, 1 })
        elseif style == "ghost" then
            T:Surface(btn, hover and C.surfaceHi or { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
        else
            T:Surface(btn, hover and C.surfaceHi or C.surface, hover and C.borderHi or C.border)
        end
    end
    Paint(false)
    btn:SetScript("OnEnter", function(self) if self:IsEnabled() then Paint(true) end end)
    btn:SetScript("OnLeave", function() Paint(false) end)
    btn:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    btn:SetScript("OnEnable",  function(self) self:SetAlpha(1) end)
    return btn
end

------------------------------------------------------------
-- CreateIconButton(parent, glyph, size, tooltip)
-- Square ghost button that draws a Theme glyph ("close", "plus", ...).
------------------------------------------------------------
function W.CreateIconButton(parent, glyph, size, tooltip)
    size = size or 28
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(size, size)
    T:Surface(btn, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })

    local g = T:Glyph(btn, glyph, math.floor(size * 0.42), C.muted)
    g:SetPoint("CENTER")
    btn._glyph = g

    btn:SetScript("OnEnter", function(self)
        T:Surface(self, C.surfaceHi, { 0, 0, 0, 0 })
        g:SetColor(T.RGBA(C.text))
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        T:Surface(self, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
        g:SetColor(T.RGBA(C.muted))
        if tooltip then GameTooltip:Hide() end
    end)
    return btn
end

------------------------------------------------------------
-- CreateSwitch(parent, onToggle)
--   :SetChecked(bool)  :GetChecked()
------------------------------------------------------------
function W.CreateSwitch(parent, onToggle)
    local sw = CreateFrame("Button", nil, parent, "BackdropTemplate")
    sw:SetSize(38, 20)

    local knob = sw:CreateTexture(nil, "OVERLAY")
    knob:SetSize(14, 14)

    local checked = false
    local function Paint()
        knob:ClearAllPoints()
        if checked then
            local r, g, b = T:GetAccent()
            T:Surface(sw, { r, g, b, 1 }, { r, g, b, 1 })
            knob:SetColorTexture(T.RGBA(C.onAccent))
            knob:SetPoint("RIGHT", sw, "RIGHT", -3, 0)
        else
            T:Surface(sw, C.field, C.borderHi)
            knob:SetColorTexture(T.RGBA(C.muted))
            knob:SetPoint("LEFT", sw, "LEFT", 3, 0)
        end
    end

    function sw:SetChecked(v)
        checked = not not v
        Paint()
    end
    function sw:GetChecked() return checked end

    sw:SetScript("OnClick", function(self)
        self:SetChecked(not checked)
        if onToggle then onToggle(checked) end
    end)

    Paint()
    return sw
end

------------------------------------------------------------
-- CreateSegmented(parent, items, onChange)
--   items = { { key, label }, ... }   :SetSelected(key)
------------------------------------------------------------
function W.CreateSegmented(parent, items, onChange)
    local PAD, SEG_H = 3, 24
    local seg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    T:Surface(seg, C.header, C.border)

    local buttons = {}
    local x = PAD
    for _, item in ipairs(items) do
        local b = CreateFrame("Button", nil, seg, "BackdropTemplate")
        local fs = T:Text(b, 13, C.muted)
        fs:SetJustifyH("CENTER")
        fs:SetPoint("CENTER")
        fs:SetText(item.label)
        local w = math.max(72, math.ceil(fs:GetStringWidth()) + 28)
        b:SetSize(w, SEG_H)
        b:SetPoint("LEFT", seg, "LEFT", x, 0)
        b._key, b._fs = item.key, fs
        b:SetScript("OnClick", function()
            seg:SetSelected(item.key)
            if onChange then onChange(item.key) end
        end)
        tinsert(buttons, b)
        x = x + w
    end
    seg:SetSize(x + PAD, SEG_H + PAD * 2)

    function seg:SetSelected(key)
        for _, b in ipairs(buttons) do
            if b._key == key then
                T:Surface(b, C.selected, C.selected)
                b._fs:SetTextColor(T.RGBA(C.text))
            else
                T:Surface(b, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
                b._fs:SetTextColor(T.RGBA(C.muted))
            end
        end
    end
    return seg
end

------------------------------------------------------------
-- CreateChip(parent, icon, text)
-- Pill with a small icon + label; width fits its content.
------------------------------------------------------------
--   :SetContent(icon, text) updates it and re-fits the width.
function W.CreateChip(parent, icon, text)
    local chip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    T:Surface(chip, C.surfaceHi, C.border)
    local ico = T:Icon(chip, 16, icon)
    ico:SetPoint("LEFT", chip, "LEFT", 4, 0)
    local fs = T:Text(chip, 12, C.text)
    fs:SetPoint("LEFT", ico, "RIGHT", 5, 0)

    function chip:SetContent(newIcon, newText)
        ico:SetTexture(newIcon)
        fs:SetText(newText or "")
        self:SetSize(math.ceil(fs:GetStringWidth()) + 16 + 4 + 5 + 8, 22)
    end

    chip:SetContent(icon, text)
    return chip
end

------------------------------------------------------------
-- CreateSearchBox(parent, width, placeholder, onChange)
------------------------------------------------------------
function W.CreateSearchBox(parent, width, placeholder, onChange)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 180, 26)
    box:SetAutoFocus(false)
    box:SetFontObject(T:GetFont(13))
    box:SetTextColor(T.RGBA(C.text))
    box:SetTextInsets(8, 8, 0, 0)
    T:Surface(box, C.header, C.border)

    local ph = T:Text(box, 13, C.faint)
    ph:SetPoint("LEFT", box, "LEFT", 8, 0)
    ph:SetText(placeholder or "")

    box:SetScript("OnEditFocusGained", function(self) T:Surface(self, C.header, C.borderHi) end)
    box:SetScript("OnEditFocusLost",   function(self) T:Surface(self, C.header, C.border) end)
    box:SetScript("OnEscapePressed",   function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed",    function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local txt = self:GetText() or ""
        ph:SetShown(txt == "")
        if onChange then onChange(txt) end
    end)
    return box
end

------------------------------------------------------------
-- CreateScrollArea(parent)
-- Mouse-wheel ScrollFrame with a thin accent thumb (no Blizzard scrollbar art).
-- Returns scrollFrame, scrollChild. Call scrollFrame:UpdateScroll() after changing
-- the child's height.
------------------------------------------------------------
function W.CreateScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)

    local track = sf:CreateTexture(nil, "OVERLAY")
    track:SetWidth(3)
    track:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    track:SetColorTexture(T.RGBA(C.border, 0.5))

    local thumb = sf:CreateTexture(nil, "OVERLAY", nil, 1)
    thumb:SetWidth(3)
    thumb:SetColorTexture(T.RGBA(C.borderHi))

    function sf:UpdateScroll()
        local viewH  = self:GetHeight() or 0
        local totalH = child:GetHeight() or 0
        local maxScroll = math.max(0, totalH - viewH)
        if self:GetVerticalScroll() > maxScroll then self:SetVerticalScroll(maxScroll) end
        if maxScroll <= 0 or viewH <= 0 then
            track:Hide(); thumb:Hide()
            return
        end
        track:Show(); thumb:Show()
        local thumbH = math.max(24, viewH * viewH / totalH)
        local offset = (viewH - thumbH) * (self:GetVerticalScroll() / maxScroll)
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -offset)
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        local v = math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 40))
        self:SetVerticalScroll(v)
        self:UpdateScroll()
    end)
    sf:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(math.max(1, w - 8))
        self:UpdateScroll()
    end)
    return sf, child
end

------------------------------------------------------------
-- CreateCustomDropdown(parent, width, height)
--
-- Flat dropdown button with a custom menu.
--
-- Public API on the returned frame:
--   :SetItems(items)         items = { { label, value [, icon] }, ... }
--   :SetSelected(value)      selects item by value, updates label
--   :ClearSelection()
--   :SetPlaceholder(text)    placeholder shown when nothing is selected
--   :SetOnChanged(fn)        fn(value, label) called on selection change
--   :GetSelected()           returns value, label  (nil, nil if nothing)
--   :HasSelection()
--   :CloseMenu()             hides the dropdown list
--
-- NOTE: value=nil is valid (used for "Default loadout").
------------------------------------------------------------
function W.CreateCustomDropdown(parent, width, height)
    local dropdownWidth = width or 140
    local faceH         = height or 26
    local ITEM_H        = 24

    ------------------------------------------------------------
    -- Button (the "closed" face of the dropdown)
    ------------------------------------------------------------
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(dropdownWidth, faceH)
    T:Surface(btn, C.field, C.border)

    local faceIcon = T:Icon(btn, faceH - 10, nil)
    faceIcon:SetPoint("LEFT", btn, "LEFT", 5, 0)
    faceIcon:Hide()

    local labelText = T:Text(btn, 13, C.muted)
    labelText:SetPoint("LEFT",  btn, "LEFT",   8,  0)
    labelText:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    labelText:SetText("Select...")
    btn.text = labelText

    local arrow = T:Glyph(btn, "chevron-down", 10, C.muted)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)

    btn:SetScript("OnEnter", function(self) T:Surface(self, C.field, C.borderHi) end)
    btn:SetScript("OnLeave", function(self) T:Surface(self, C.field, C.border) end)

    ------------------------------------------------------------
    -- Menu frame (the open dropdown list)
    ------------------------------------------------------------
    -- Parented to UIParent so it is never clipped by a ScrollFrame ancestor.
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    T:Surface(menu, C.surface, C.borderHi)
    menu:Hide()
    menu:EnableMouse(true)
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)

    ------------------------------------------------------------
    -- State
    ------------------------------------------------------------
    local items         = {}
    local selectedValue = nil   -- nil is a valid value (= "Default loadout")
    local hasSelection  = false -- separate flag so we can tell nil-unset from nil-selected
    local onChangedFn   = nil
    local menuButtons   = {}
    local placeholder   = "Select..."

    local function SetFace(label, icon, isPlaceholder)
        labelText:SetText(label)
        labelText:SetTextColor(T.RGBA(isPlaceholder and C.muted or C.text))
        labelText:ClearAllPoints()
        if icon then
            faceIcon:SetTexture(icon)
            faceIcon:Show()
            labelText:SetPoint("LEFT", faceIcon, "RIGHT", 6, 0)
        else
            faceIcon:Hide()
            labelText:SetPoint("LEFT", btn, "LEFT", 8, 0)
        end
        labelText:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    end

    local function UpdateLabel()
        if hasSelection then
            for _, item in ipairs(items) do
                if item.value == selectedValue then
                    SetFace(item.label, item.icon, false)
                    return
                end
            end
        end
        SetFace(placeholder, nil, true)
    end

    local function RebuildMenuItems()
        for _, mb in ipairs(menuButtons) do
            mb:SetParent(nil)
            mb:Hide()
        end
        wipe(menuButtons)

        local ar, ag, ab = T:GetAccent()
        local menuH = 4
        for idx, item in ipairs(items) do
            local mb = CreateFrame("Button", nil, menu)
            mb:SetSize(dropdownWidth - 4, ITEM_H)
            mb:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (idx - 1) * ITEM_H)

            local hl = mb:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(T.RGBA(C.selected))

            local isSelected = hasSelection and item.value == selectedValue
            local textLeft = 10
            if item.icon then
                local ico = T:Icon(mb, 16, item.icon)
                ico:SetPoint("LEFT", mb, "LEFT", 8, 0)
                textLeft = 30
            end

            local lbl = T:Text(mb, 13, isSelected and C.text or C.textDim)
            lbl:SetPoint("LEFT",  mb, "LEFT",  textLeft, 0)
            lbl:SetPoint("RIGHT", mb, "RIGHT", -22,      0)
            lbl:SetText(item.label)

            if isSelected then
                local check = T:Glyph(mb, "check", 12, { ar, ag, ab, 1 }, 2)
                check:SetPoint("RIGHT", mb, "RIGHT", -6, 0)
            end

            local capturedItem = item
            mb:SetScript("OnClick", function()
                selectedValue = capturedItem.value
                hasSelection  = true
                UpdateLabel()
                menu:Hide()
                if onChangedFn then
                    onChangedFn(capturedItem.value, capturedItem.label)
                end
            end)

            tinsert(menuButtons, mb)
            menuH = menuH + ITEM_H
        end

        menu:SetSize(dropdownWidth, menuH)
    end

    menu:SetScript("OnShow", RebuildMenuItems)
    AttachClickOutside(menu, "FULLSCREEN_DIALOG", function() menu:Hide() end)

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            menu:Show()
        end
    end)
    btn:SetScript("OnHide", function() menu:Hide() end)

    ------------------------------------------------------------
    -- Public API
    ------------------------------------------------------------
    function btn:SetItems(newItems)
        items = newItems
        UpdateLabel()
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
        UpdateLabel()
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
