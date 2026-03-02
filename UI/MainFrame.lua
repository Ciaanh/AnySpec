-- AnySpec/UI/MainFrame.lua
-- Custom main configuration window (no Blizzard options panel).
-- Left panel  : drag-to-action-bar macro buttons + general settings.
-- Right panel : per-instance spec assignments (Dungeons / Raids) using the EJ API.

AnySpec     = AnySpec     or {}
AnySpec.UI  = AnySpec.UI  or {}
AnySpec.UI.MainFrame = AnySpec.UI.MainFrame or {}
local MF = AnySpec.UI.MainFrame
local L  = AnySpec.L

------------------------------------------------------------
-- Layout constants
------------------------------------------------------------
local FRAME_NAME = "AnySpecFrame"
local FRAME_W    = 800
local FRAME_H    = 530
local HEADER_H   = 38
local LEFT_W     = 225          -- left panel width
local DIVIDER_W  = 1
-- right panel occupies the rest; computed at build time.

------------------------------------------------------------
-- Module state
------------------------------------------------------------
local frame          = nil
local currentView    = "locations"  -- "locations" or "settings"
local currentTab     = "dungeons"   -- "dungeons" or "raids"
local currentTierIdx = nil          -- nil → default to newest tier on first open
local instanceRows   = {}
local tierList       = {}           -- { { index, name }, ... } newest-first
local tierDropdown   = nil
local scrollFrame    = nil
local scrollChild    = nil
local viewContainer  = nil          -- container for switchable views

-- Assignment dialog state
local assignmentDialog    = nil   -- modal dialog frame (created once in Init)
local dialogRows          = {}    -- pair-row frames currently in the dialog
local currentDialogInstID = nil   -- instanceID the dialog is currently open for
local instanceRowRefreshFns = {}  -- [instanceID] = fn(), refreshes the row button text

------------------------------------------------------------
-- Macro helpers  (Plumber-style drag-to-action-bar)
------------------------------------------------------------
local MACRO_TAG = "#anyspec"

local function AcquireMacro(command, name, icon, clickTarget)
    if InCombatLockdown() then return nil end
    local _, numChar = GetNumMacros()
    local base = MAX_ACCOUNT_MACROS + 1
    for idx = base, base + numChar - 1 do
        local body = GetMacroBody(idx)
        if body then
            local tag = body:match(MACRO_TAG .. ":(%S+)")
            if tag == command then return idx end
        end
    end
    if numChar < MAX_CHARACTER_MACROS then
        local body = MACRO_TAG .. ":" .. command .. "\n/click " .. clickTarget
        return CreateMacro(name, icon, body, true)
    end
    return nil
end

local function CreateDragButton(parent, iconTex, text, tip, acquireFn)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(LEFT_W - 24, 28)
    btn:RegisterForDrag("LeftButton")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.3, 0.5, 0.8, 0.25)

    local ico = btn:CreateTexture(nil, "ARTWORK")
    ico:SetSize(20, 20)
    ico:SetPoint("LEFT", btn, "LEFT", 4, 0)
    ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ico:SetTexture(iconTex)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", ico, "RIGHT", 5, 0)
    lbl:SetPoint("RIGHT", btn, "RIGHT", -30, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetText(text)

    local hint = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    hint:SetTextColor(0.45, 0.45, 0.45)
    hint:SetText(L["QUICKACCESS_DRAG_HINT"])

    btn:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            print(L["ERR_COMBAT_MACRO"])
            return
        end
        local id = acquireFn()
        if id then
            PickupMacro(id)
        else
            print(L["ERR_NO_MACRO_SLOT"])
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip, 1, 1, 1)
        GameTooltip:AddLine("Drag to your action bar to create a shortcut.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

------------------------------------------------------------
-- Encounter Journal helpers
------------------------------------------------------------
local function LoadEJ()
    if not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end
end

-- Returns tier list newest-first: { { index, name } }
local function BuildTierList()
    LoadEJ()
    if not EJ_GetNumTiers then return {} end
    local list = {}
    for i = EJ_GetNumTiers(), 1, -1 do
        local name = EJ_GetTierInfo(i)
        if name and name ~= "" then
            tinsert(list, { index = i, name = name })
        end
    end
    return list
end

-- Returns instances for the given tier + type, restoring the original tier.
local function GetInstances(tierIndex, isRaid)
    LoadEJ()
    if not EJ_GetInstanceByIndex then return {} end
    local savedTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or 1
    EJ_SelectTier(tierIndex)
    local out = {}
    for i = 1, 999 do
        local id, name, _, _, icon = EJ_GetInstanceByIndex(i, isRaid)
        if not id then break end
        tinsert(out, { id = id, name = name, icon = icon })
    end
    EJ_SelectTier(savedTier)
    return out
end

------------------------------------------------------------
-- Per-instance assignment: summary helpers
------------------------------------------------------------

-- Returns display text for the instance row button ("None" or "Holy, Protection").
-- Loadout names are shown only in the tooltip (via CreateAssignButton).
local function GetAssignmentSummary(instanceID)
    local asgn = AnySpec.charDB and AnySpec.charDB.instanceAssignments[instanceID]
    if not asgn or #asgn == 0 then
        return L["ASSIGNMENT_NONE"]
    end
    local parts = {}
    for _, pair in ipairs(asgn) do
        local info = AnySpec.SpecManager:GetSpecInfo(pair.specIndex)
        if info then tinsert(parts, info.name) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "|cff555555None|r"
end

-- Builds a multi-line tooltip string with full spec+loadout details.
local function GetAssignmentTooltip(instanceID)
    local asgn = AnySpec.charDB and AnySpec.charDB.instanceAssignments[instanceID]
    if not asgn or #asgn == 0 then return nil end
    local lines = {}
    for i, pair in ipairs(asgn) do
        local info = AnySpec.SpecManager:GetSpecInfo(pair.specIndex)
        local specName = info and info.name or ("Spec " .. pair.specIndex)
        local loadoutName = "Default loadout"
        if pair.loadoutID then
            local cfg = C_Traits.GetConfigInfo(pair.loadoutID)
            if cfg and cfg.name and cfg.name ~= "" then
                loadoutName = cfg.name
            end
        end
        tinsert(lines, i .. ".  " .. specName .. "  \124cff888888" .. loadoutName .. "\124r")
    end
    return table.concat(lines, "\n")
end

------------------------------------------------------------
-- Assignment dialog
------------------------------------------------------------
local DIALOG_W        = 374
local DIALOG_HDR_H    = 34
local DIALOG_ROW_H    = 34
local DIALOG_ROW_GAP  = 4
local DIALOG_PAD      = 12
local DIALOG_MAX_ROWS = 3
local ROWS_START_Y    = -(DIALOG_HDR_H + 4)  -- y offset where first row starts

local function GetLoadoutItemsForSpec(specIndex)
    local items = { { label = L["LOADOUT_DEFAULT"], value = nil } }
    for _, l in ipairs(AnySpec.SpecManager:GetLoadoutsForSpec(specIndex)) do
        tinsert(items, { label = l.name, value = l.configID })
    end
    return items
end

local function SaveDialogAssignments()
    if not currentDialogInstID then
        return
    end
    local charDB = AnySpec.charDB
    if not charDB then
        return
    end

    local pairs = {}
    for i, r in ipairs(dialogRows) do
        local specVal = r.specDD:GetSelected()
        if specVal then
            local loadoutVal = r.loadoutDD:GetSelected()
            tinsert(pairs, { specIndex = specVal, loadoutID = loadoutVal })
        end
    end

    if #pairs == 0 then
        charDB.instanceAssignments[currentDialogInstID] = nil
    else
        charDB.instanceAssignments[currentDialogInstID] = pairs
    end

    local fn = instanceRowRefreshFns[currentDialogInstID]
    if fn then fn() end
end

local function ResizeDialog()
    if not assignmentDialog then return end
    local n = #dialogRows
    local rowsH  = n > 0 and (n * DIALOG_ROW_H + (n - 1) * DIALOG_ROW_GAP) or 0
    local totalH = DIALOG_HDR_H + 4 + rowsH + (n > 0 and 6 or 0)
                   + (n < DIALOG_MAX_ROWS and (8 + 24) or 0) + 10
    assignmentDialog:SetHeight(math.max(totalH, DIALOG_HDR_H + 4 + 24 + 10))

    -- Reposition Add button
    local addBtn = assignmentDialog._addBtn
    if addBtn then
        addBtn:ClearAllPoints()
        local addY = ROWS_START_Y - n * (DIALOG_ROW_H + DIALOG_ROW_GAP) - (n > 0 and 2 or 0)
        addBtn:SetPoint("TOPLEFT", assignmentDialog, "TOPLEFT", DIALOG_PAD, addY - 6)
        addBtn:SetShown(n < DIALOG_MAX_ROWS)
    end

    -- Renumber rows
    for i, r in ipairs(dialogRows) do
        if r._numLbl then r._numLbl:SetText(tostring(i)) end
    end
end

-- Adds one pair row to the open dialog. specIndex may be nil (placeholder).
local function AddDialogRow(specIndex, loadoutID)
    if not assignmentDialog then
        return
    end
    if #dialogRows >= DIALOG_MAX_ROWS then
        return
    end

    local rowIdx  = #dialogRows + 1
    local rowTopY = ROWS_START_Y - (rowIdx - 1) * (DIALOG_ROW_H + DIALOG_ROW_GAP)

    local row = CreateFrame("Frame", nil, assignmentDialog, "BackdropTemplate")
    row:SetSize(DIALOG_W - DIALOG_PAD * 2, DIALOG_ROW_H)
    row:SetPoint("TOPLEFT", assignmentDialog, "TOPLEFT", DIALOG_PAD, rowTopY)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    row:SetBackdropColor(0.11, 0.11, 0.11, 0.6)
    row:SetBackdropBorderColor(0.25, 0.25, 0.28, 0.8)

    -- Pair number label
    local numLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    numLbl:SetSize(16, DIALOG_ROW_H)
    numLbl:SetPoint("LEFT", row, "LEFT", 6, 0)
    numLbl:SetJustifyH("CENTER")
    numLbl:SetText(tostring(rowIdx))
    numLbl:SetTextColor(0.5, 0.5, 0.7)
    row._numLbl = numLbl

    -- Spec dropdown
    local specDD = AnySpec.UI.Widgets.CreateCustomDropdown(row, 110)
    specDD:SetPoint("LEFT", numLbl, "RIGHT", 6, 0)
    specDD:SetPlaceholder(L["DIALOG_SPEC_PLACEHOLDER"])
    local specs = AnySpec.SpecManager:GetAllSpecs()
    local specItems = {}
    for _, s in ipairs(specs) do
        tinsert(specItems, { label = s.name, value = s.specIndex, icon = s.icon })
    end
    specDD:SetItems(specItems)
    row.specDD = specDD

    -- Loadout dropdown
    local loadoutDD = AnySpec.UI.Widgets.CreateCustomDropdown(row, 168)
    loadoutDD:SetPoint("LEFT", specDD, "RIGHT", 8, 0)
    loadoutDD:SetPlaceholder("Default loadout")
    row.loadoutDD = loadoutDD

    -- Wire spec → loadout rebuild
    specDD:SetOnChanged(function(value, label)
        loadoutDD:SetItems(GetLoadoutItemsForSpec(value))
        loadoutDD:ClearSelection()
        SaveDialogAssignments()
    end)
    loadoutDD:SetOnChanged(function() SaveDialogAssignments() end)

    -- Remove (✕) button
    local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    removeBtn:SetSize(20, 20)
    removeBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    removeBtn:SetScript("OnClick", function()
        row:Hide()
        row:SetParent(nil)
        for i = #dialogRows, 1, -1 do
            if dialogRows[i] == row then
                tremove(dialogRows, i)
                break
            end
        end
        -- Re-anchor remaining rows
        for i, r in ipairs(dialogRows) do
            local y = ROWS_START_Y - (i - 1) * (DIALOG_ROW_H + DIALOG_ROW_GAP)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", assignmentDialog, "TOPLEFT", DIALOG_PAD, y)
        end
        ResizeDialog()
        SaveDialogAssignments()
    end)

    -- Initialise dropdowns with existing values
    if specIndex then
        specDD:SetSelected(specIndex)
        loadoutDD:SetItems(GetLoadoutItemsForSpec(specIndex))
        if loadoutID ~= nil then
            loadoutDD:SetSelected(loadoutID)
        end
    end

    tinsert(dialogRows, row)
    ResizeDialog()
end

local function CreateAssignmentDialog()
    local d = CreateFrame("Frame", "AnySpecAssignmentDialog", UIParent, "BackdropTemplate")
    d:SetFrameStrata("DIALOG")
    d:SetWidth(DIALOG_W)
    d:SetHeight(DIALOG_HDR_H + 4 + 24 + 10)  -- minimum (no rows)
    d:SetClampedToScreen(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop",  d.StopMovingOrSizing)
    d:Hide()
    tinsert(UISpecialFrames, "AnySpecAssignmentDialog")

    d:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    d:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    d:SetBackdropBorderColor(0.28, 0.28, 0.32, 1)

    -- Header background
    local hdrBg = d:CreateTexture(nil, "BACKGROUND", nil, 1)
    hdrBg:SetPoint("TOPLEFT",  d, "TOPLEFT",  1, -1)
    hdrBg:SetPoint("TOPRIGHT", d, "TOPRIGHT", -1, -1)
    hdrBg:SetHeight(DIALOG_HDR_H)
    hdrBg:SetColorTexture(0.04, 0.04, 0.04, 1)

    -- Title
    local title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT",  d, "TOPLEFT",  DIALOG_PAD, -7)
    title:SetPoint("TOPRIGHT", d, "TOPRIGHT", -32, -7)
    title:SetJustifyH("LEFT")
    d._title = title

    -- Close (X)
    local closeBtn = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", d, "TOPRIGHT", 2, -2)
    closeBtn:SetScript("OnClick", function() d:Hide() end)

    -- Header separator
    local sep = d:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  d, "TOPLEFT",  1,  -DIALOG_HDR_H)
    sep:SetPoint("TOPRIGHT", d, "TOPRIGHT", -1, -DIALOG_HDR_H)
    sep:SetColorTexture(0.28, 0.28, 0.32, 1)

    -- Add button (repositioned by ResizeDialog)
    local addBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    addBtn:SetSize(90, 24)
    addBtn:SetText(L["DIALOG_ADD_PAIR"])
    addBtn:SetPoint("TOPLEFT", d, "TOPLEFT", DIALOG_PAD, ROWS_START_Y - 6)
    d._addBtn = addBtn

    addBtn:SetScript("OnClick", function()
        if #dialogRows >= DIALOG_MAX_ROWS then return end
        local usedSpecs = {}
        for _, r in ipairs(dialogRows) do
            local sv = r.specDD:GetSelected()
            if sv then usedSpecs[sv] = true end
        end
        local specs = AnySpec.SpecManager:GetAllSpecs()
        local defaultSpec = nil
        for _, s in ipairs(specs) do
            if not usedSpecs[s.specIndex] then
                defaultSpec = s.specIndex
                break
            end
        end
        if not defaultSpec and #specs > 0 then defaultSpec = specs[1].specIndex end
        AddDialogRow(defaultSpec, nil)
        SaveDialogAssignments()
    end)

    d:Hide()
    return d
end

-- Opens (or re-populates) the assignment dialog for the given instance.
local function OpenAssignmentDialog(instanceID, instanceName)
    if not assignmentDialog then
        return
    end

    -- Clear old rows
    for _, r in ipairs(dialogRows) do
        r:Hide()
        r:SetParent(nil)
    end
    wipe(dialogRows)

    currentDialogInstID = instanceID
    assignmentDialog._title:SetText(instanceName or L["DIALOG_INSTANCE_FALLBACK"])

    -- Populate from saved data
    local saved = AnySpec.charDB and AnySpec.charDB.instanceAssignments[instanceID]
    if saved and #saved > 0 then
        for i, pair in ipairs(saved) do
            AddDialogRow(pair.specIndex, pair.loadoutID)
        end
    end

    ResizeDialog()

    -- Centre near the main frame if open, otherwise screen centre
    assignmentDialog:ClearAllPoints()
    if frame and frame:IsShown() then
        assignmentDialog:SetPoint("CENTER", frame, "CENTER", 0, 0)
    else
        assignmentDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    assignmentDialog:Show()
end

------------------------------------------------------------
-- Per-instance row button (opens the dialog)
------------------------------------------------------------
local function CreateAssignButton(parent, instanceID, instanceName, width)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)

    local function Refresh()
        btn:SetText(GetAssignmentSummary(instanceID))
    end
    instanceRowRefreshFns[instanceID] = Refresh
    Refresh()

    btn:SetScript("OnClick", function()
        OpenAssignmentDialog(instanceID, instanceName)
    end)

    btn:SetScript("OnEnter", function(self)
        local tip = GetAssignmentTooltip(instanceID)
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(instanceName or "", 1, 1, 1)
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, false)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

------------------------------------------------------------
-- Rebuild the instance scroll list
------------------------------------------------------------
local ROW_H      = 36
local ICON_SIZE  = 26
local BTN_WIDTH  = 150

local function RebuildInstanceList(tierIndex, isRaid)
    if not scrollChild then return end

    -- Remove old rows
    for _, row in ipairs(instanceRows) do
        row:SetParent(nil)
        row:Hide()
    end
    instanceRows = {}
    wipe(instanceRowRefreshFns)
    if scrollChild._emptyLabel then
        scrollChild._emptyLabel:SetParent(nil)
        scrollChild._emptyLabel = nil
    end

    local instances   = GetInstances(tierIndex, isRaid)
    local tierName    = ""
    for _, t in ipairs(tierList) do
        if t.index == tierIndex then
            tierName = t.name
            break
        end
    end
    
    local rowW        = scrollChild:GetWidth()
    
    -- Ensure we have a valid width; if not, estimate based on scrollFrame
    if rowW == 0 or rowW < 100 then
        rowW = (scrollFrame:GetWidth() or 400) - 4
    end
    
    local y           = -6
    local filteredCount = 0

    for i, inst in ipairs(instances) do
        -- Skip open world bosses: if instance name matches the tier name, it's an open world boss encounter
        if inst.name ~= tierName then
            filteredCount = filteredCount + 1
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetSize(rowW, ROW_H)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)

            -- Row background (alternating shading)
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if filteredCount % 2 == 1 then
                bg:SetColorTexture(0.14, 0.14, 0.14, 0.55)
            else
                bg:SetColorTexture(0.09, 0.09, 0.09, 0.35)
            end

            -- Instance icon
            local ico = row:CreateTexture(nil, "ARTWORK")
            ico:SetSize(ICON_SIZE, ICON_SIZE)
            ico:SetPoint("LEFT", row, "LEFT", 8, 0)
            ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if inst.icon and inst.icon ~= 0 then
                ico:SetTexture(inst.icon)
            else
                ico:SetTexture(134400) -- question mark fallback
            end

            -- Instance name
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("LEFT", ico, "RIGHT", 7, 0)
            lbl:SetPoint("RIGHT", row, "RIGHT", -(BTN_WIDTH + 12), 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(inst.name)

            -- Spec assignment button
            local ab = CreateAssignButton(row, inst.id, inst.name, BTN_WIDTH)
            ab:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            ab:SetPoint("CENTER", row, "CENTER", (BTN_WIDTH / 2 + 6), 0)

            y = y - ROW_H
            tinsert(instanceRows, row)
        end
    end

    scrollChild:SetHeight(math.max(1, -y + 6))

    if filteredCount == 0 then
        local empty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        empty:SetPoint("CENTER", scrollChild, "CENTER", 0, -40)
        empty:SetTextColor(0.45, 0.45, 0.45)
        empty:SetText(L["INSTANCES_EMPTY"])
        scrollChild._emptyLabel = empty
    end
end

-- Called whenever the tab or tier changes.
local function RefreshInstanceList()
    if not frame then return end
    local isRaid = (currentTab == "raids")
    local tIdx   = currentTierIdx
    if not tIdx and #tierList > 0 then
        tIdx = tierList[1].index
    end
    if tIdx then
        RebuildInstanceList(tIdx, isRaid)
    end
end

------------------------------------------------------------
-- Left panel (drag buttons + general settings)
------------------------------------------------------------
------------------------------------------------------------
-- Right panel (tabs + tier dropdown + instance scroll list)
------------------------------------------------------------
local tabBtns = {}

local function SelectTab(tab)
    currentTab = tab
    for _, tb in ipairs(tabBtns) do
        if tb._tab == tab then
            tb._text:SetTextColor(0.05, 0.65, 1)
            tb._underline:Show()
        else
            tb._text:SetTextColor(0.55, 0.55, 0.55)
            tb._underline:Hide()
        end
    end
    RefreshInstanceList()
end

local function BuildRightPanel(parent)
    -- ── Tab buttons ───────────────────────────────────────
    local tabDefs = {
        { key = "dungeons", label = L["TAB_DUNGEONS"] },
        { key = "raids",    label = L["TAB_RAIDS"]    },
    }
    local tx = 12
    for _, td in ipairs(tabDefs) do
        local tb = CreateFrame("Button", nil, parent)
        tb:SetSize(100, 26)
        tb:SetPoint("TOPLEFT", parent, "TOPLEFT", tx, -10)
        tb._tab = td.key

        local fs = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetAllPoints()
        fs:SetText(td.label)
        tb._text = fs

        -- Underline indicator
        local ul = tb:CreateTexture(nil, "OVERLAY")
        ul:SetSize(90, 2)
        ul:SetPoint("BOTTOM", tb, "BOTTOM", 0, 0)
        ul:SetColorTexture(0.05, 0.65, 1, 1)
        tb._underline = ul

        tb:SetScript("OnClick", function() SelectTab(td.key) end)
        tinsert(tabBtns, tb)
        tx = tx + 108
    end

    -- ── Expansion / tier dropdown ─────────────────────────
    tierDropdown = CreateFrame("Frame", "AnySpecTierDropdown", parent, "UIDropDownMenuTemplate")
    tierDropdown:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 10, -6)
    UIDropDownMenu_SetWidth(tierDropdown, 165)

    UIDropDownMenu_Initialize(tierDropdown, function(self, level)
        tierList = BuildTierList()
        for _, t in ipairs(tierList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = t.name
            info.value = t.index
            info.func  = function(btn)
                currentTierIdx = btn.value
                UIDropDownMenu_SetSelectedValue(tierDropdown, currentTierIdx)
                UIDropDownMenu_SetText(tierDropdown, btn:GetText())
                RefreshInstanceList()
            end
            info.checked = (t.index == currentTierIdx)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(tierDropdown, L["TIER_DROPDOWN_DEFAULT"])

    -- ── Separator below tabs ──────────────────────────────
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -38)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -38)
    sep:SetHeight(1)
    sep:SetColorTexture(0.3, 0.3, 0.35, 0.8)

    -- ── Scroll frame ──────────────────────────────────────
    scrollFrame = CreateFrame("ScrollFrame", "AnySpecInstanceScroll", parent,
                              "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     parent, "TOPLEFT",     4,   -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26,  4)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollChild:SetWidth(parent:GetWidth() - 100)  -- Initial estimate
    scrollFrame:SetScrollChild(scrollChild)

    -- Keep scrollChild width in sync with scrollFrame
    scrollFrame:SetScript("OnSizeChanged", function(self, w, _)
        local newW = w - 4
        if scrollChild:GetWidth() ~= newW then
            scrollChild:SetWidth(newW)
            -- Rebuild rows if we already loaded data (width changed = frame first shown)
            if currentTierIdx then
                RefreshInstanceList()
            end
        end
    end)
end

------------------------------------------------------------
-- Assemble the main frame
------------------------------------------------------------
local function CreateMainFrame()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if AnySpec.db then
            AnySpec.db.framePosition = {
                x = self:GetLeft(),
                y = self:GetTop(),
            }
        end
    end)

    -- Dark backdrop matching Porter's style
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

    -- ESC closes the frame
    tinsert(UISpecialFrames, FRAME_NAME)

    -- ── Header ────────────────────────────────────────────
    local headerBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    headerBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    headerBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    headerBg:SetHeight(HEADER_H)
    headerBg:SetColorTexture(0.04, 0.04, 0.04, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", f, "LEFT", 14, FRAME_H / 2 - HEADER_H / 2)
    title:SetText("|cff00aaffAny|r|cffffffffSpec|r")

    -- Current spec display next to title
    local specLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specLabel:SetPoint("LEFT", title, "RIGHT", 10, 0)
    specLabel:SetTextColor(0.6, 0.6, 0.6)
    local curSpec = AnySpec.SpecManager:GetCurrentSpecIndex()
    if curSpec then
        local info = AnySpec.SpecManager:GetSpecInfo(curSpec)
        if info then specLabel:SetText(info.name) end
    end
    f._specLabel = specLabel

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Header bottom separator
    local hSep = f:CreateTexture(nil, "ARTWORK")
    hSep:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -(HEADER_H))
    hSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -(HEADER_H))
    hSep:SetHeight(1)
    hSep:SetColorTexture(0.28, 0.28, 0.32, 1)

    ----========════════════════════════════════════════════════
    -- VIEW MANAGEMENT SYSTEM
    ----========════════════════════════════════════════════════
    local viewContainer = CreateFrame("Frame", nil, f)
    viewContainer:SetPoint("TOPLEFT",     f, "TOPLEFT",     1 + LEFT_W + DIVIDER_W, -(HEADER_H + 1))
    viewContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    -- View title strip
    local VIEW_TITLE_H = 32
    local viewTitleBg = viewContainer:CreateTexture(nil, "BACKGROUND")
    viewTitleBg:SetPoint("TOPLEFT",  viewContainer, "TOPLEFT",  0, 0)
    viewTitleBg:SetPoint("TOPRIGHT", viewContainer, "TOPRIGHT", 0, 0)
    viewTitleBg:SetHeight(VIEW_TITLE_H)
    viewTitleBg:SetColorTexture(0.04, 0.04, 0.04, 0.9)

    local viewTitleText = viewContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    viewTitleText:SetPoint("TOPLEFT", viewContainer, "TOPLEFT", 14, -(VIEW_TITLE_H / 2 - 7))
    viewTitleText:SetTextColor(0.9, 0.9, 0.9)

    local viewTitleSep = viewContainer:CreateTexture(nil, "ARTWORK")
    viewTitleSep:SetPoint("TOPLEFT",  viewContainer, "TOPLEFT",  0, -VIEW_TITLE_H)
    viewTitleSep:SetPoint("TOPRIGHT", viewContainer, "TOPRIGHT", 0, -VIEW_TITLE_H)
    viewTitleSep:SetHeight(1)
    viewTitleSep:SetColorTexture(0.28, 0.28, 0.32, 1)

    -- Views will be created as children of viewContainer
    local views     = {}
    local navLinks  = {}  -- keyed by viewName, value = btn
    local viewNames = { locations = L["VIEW_LOCATIONS"], settings = L["VIEW_SETTINGS"] }

    -- Switch to a view
    local function ShowView(viewName)
        for name, view in pairs(views) do
            if name == viewName then
                view:Show()
            else
                view:Hide()
            end
        end
        currentView = viewName
        -- Update title
        viewTitleText:SetText(viewNames[viewName] or viewName)
        -- Update nav link highlights
        for name, btn in pairs(navLinks) do
            local isActive = (name == viewName)
            if btn._text then
                if isActive then
                    btn._text:SetTextColor(1, 1, 1)
                else
                    btn._text:SetTextColor(0.4, 0.8, 1)
                end
            end
            if btn._accent then
                btn._accent:SetShown(isActive)
            end
        end
    end

    ----========════════════════════════════════════════════════
    -- LOCATIONS VIEW (Dungeons/Raids with instance list)
    ----========════════════════════════════════════════════════
    local function CreateLocationsView()
        local view = CreateFrame("Frame", nil, viewContainer)
        view:SetPoint("TOPLEFT",     viewContainer, "TOPLEFT",     0, -(VIEW_TITLE_H + 1))
        view:SetPoint("BOTTOMRIGHT", viewContainer, "BOTTOMRIGHT", 0, 0)
        views.locations = view

        -- This view uses the existing right panel setup
        BuildRightPanel(view)
        return view
    end

    ----========════════════════════════════════════════════════
    -- SETTINGS VIEW (Position, checkboxes, test button)
    ----========════════════════════════════════════════════════
    local function CreateSettingsView()
        local view = CreateFrame("Frame", nil, viewContainer)
        view:SetPoint("TOPLEFT",     viewContainer, "TOPLEFT",     0, -(VIEW_TITLE_H + 1))
        view:SetPoint("BOTTOMRIGHT", viewContainer, "BOTTOMRIGHT", 0, 0)
        views.settings = view
        
        local y = -14
        
        -- ── Toast Position ──────────────────────────────
        local posHdr = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        posHdr:SetPoint("TOPLEFT", view, "TOPLEFT", 12, y)
        posHdr:SetText(L["SETTINGS_TOAST_POSITION"])
        y = y - 26
        
        local posDesc = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        posDesc:SetPoint("TOPLEFT", view, "TOPLEFT", 12, y)
        posDesc:SetWidth(350)
        posDesc:SetJustifyH("LEFT")
        posDesc:SetWordWrap(true)
        posDesc:SetTextColor(0.55, 0.55, 0.55)
        posDesc:SetText(L["SETTINGS_TOAST_POSITION_DESC"])
        y = y - (math.max(14, math.floor(posDesc:GetStringHeight() + 0.5))) - 8
        
        -- Position buttons
        local positions = {
            { key = "top_center",    label = L["POS_TOP_CENTER"] },
            { key = "center",        label = L["POS_CENTER"] },
            { key = "top_right",     label = L["POS_TOP_RIGHT"] },
            { key = "bottom_center", label = L["POS_BOTTOM_CENTER"] },
        }
        
        local posButtons = {}
        
        local function UpdatePositionButtons()
            local currentPos = AnySpec.UI.Proposal:GetPosition()
            for _, btn in ipairs(posButtons) do
                btn:SetEnabled(btn._posKey ~= currentPos)
            end
        end
        
        local function MakePosButton(posKey, posLabel, idx)
            local btn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
            btn:SetSize(170, 28)
            local col = (idx - 1) % 2
            local row = math.floor((idx - 1) / 2)
            btn:SetPoint("TOPLEFT", view, "TOPLEFT", 12 + col * 180, y - row * 34)
            btn:SetText(posLabel)
            btn._posKey = posKey
            
            btn:SetScript("OnClick", function()
                if AnySpec.UI.Proposal:SetPosition(posKey) then
                    if AnySpec.db then
                        AnySpec.db.toastPosition = posKey
                    end
                    UpdatePositionButtons()
                end
            end)
            
            return btn
        end
        
        for idx, posDef in ipairs(positions) do
            local btn = MakePosButton(posDef.key, posDef.label, idx)
            table.insert(posButtons, btn)
        end
        UpdatePositionButtons()
        y = y - 72
        
        -- ── General Settings ────────────────────────────
        y = y - 10
        local setHdr = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        setHdr:SetPoint("TOPLEFT", view, "TOPLEFT", 12, y)
        setHdr:SetText(L["VIEW_SETTINGS"])
        y = y - 26
        
        -- Helper to build a checkbox in settings view
        local function Checkbox(label, getter, setter)
            local cb = CreateFrame("CheckButton", nil, view, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", view, "TOPLEFT", 8, y)
            cb.text:SetText(label)
            cb:SetChecked(getter())
            cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
            y = y - 28
            return cb
        end

        Checkbox(L["SETTINGS_MINIMAP"], function()
            return AnySpec.db and AnySpec.db.minimapButton ~= false
        end, function(val)
            if AnySpec.db then AnySpec.db.minimapButton = val end
            AnySpec.UI.MinimapButton:SetShown(val)
        end)

        Checkbox(L["SETTINGS_AUTO_SWITCH"], function()
            return AnySpec.db and AnySpec.db.proposalEnabled ~= false
        end, function(val)
            if AnySpec.db then AnySpec.db.proposalEnabled = val end
        end)
        
        y = y - 14
        
        -- ── Test Toast ──────────────────────────────────
        local testBtn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        testBtn:SetSize(340, 24)
        testBtn:SetPoint("TOPLEFT", view, "TOPLEFT", 12, y)
        testBtn:SetText(L["SETTINGS_TEST_TOAST"])
        testBtn:SetScript("OnClick", function()
            local specs = AnySpec.SpecManager:GetAllSpecs()
            local testAssignments = {}
            for i = 1, math.min(3, #specs) do
                local spec = specs[i]
                local loadouts = AnySpec.SpecManager:GetLoadoutsForSpec(spec.specIndex)
                local loadoutID = nil
                if #loadouts > 0 and i > 1 then
                    loadoutID = loadouts[1].configID
                end
                table.insert(testAssignments, { specIndex = spec.specIndex, loadoutID = loadoutID })
            end
            
            local testZoneInfo = {
                category = "dungeon",
                instanceType = "party",
                instanceID = 9999,
                difficultyID = 0,
                instanceName = "Test Instance",
            }
            
            AnySpec.UI.Proposal:Show(testAssignments, testZoneInfo)
        end)
        
        -- Refresh button states every time the view becomes visible
        view:SetScript("OnShow", function()
            UpdatePositionButtons()
        end)
        
        view:Hide()
        return view
    end

    ----========════════════════════════════════════════════════
    -- LEFT PANEL (Persistent: drag buttons + view links)
    ----========════════════════════════════════════════════════
    local leftPanel = CreateFrame("Frame", nil, f)
    leftPanel:SetPoint("TOPLEFT",    f, "TOPLEFT",    1, -(HEADER_H + 1))
    leftPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    leftPanel:SetWidth(LEFT_W)

    local y = -14
    
    -- ── Quick Access ──────────────────────────────────────
    local hdr = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
    hdr:SetText(L["QUICKACCESS_TITLE"])
    y = y - 22

    local desc = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
    desc:SetWidth(LEFT_W - 32)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.55, 0.55, 0.55)
    desc:SetText(L["QUICKACCESS_DESC"])
    local descHeight = math.max(14, math.floor(desc:GetStringHeight() + 0.5))
    y = y - descHeight - 8

    -- Spec-selector button
    local switchIcon = 134063
    local curSpec    =AnySpec.SpecManager:GetCurrentSpecIndex()
    if curSpec then
        local info = AnySpec.SpecManager:GetSpecInfo(curSpec)
        if info then switchIcon = info.icon end
    end

    local switchDrag = CreateDragButton(leftPanel, switchIcon, L["QUICKACCESS_SWITCH_NAME"],
        L["QUICKACCESS_SWITCH_TIP"], function()
            return AcquireMacro("switch", "AnySpec", switchIcon, "ANYSPEC_SWITCH")
        end)
    switchDrag:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
    y = y - 32

    y = y - 28
    
    -- ── Navigation separator ──────────────────────────────
    local navSep = leftPanel:CreateTexture(nil, "ARTWORK")
    navSep:SetHeight(1)
    navSep:SetWidth(LEFT_W - 24)
    navSep:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
    navSep:SetColorTexture(0.3, 0.3, 0.35, 0.6)
    y = y - 10

    -- ── Navigation ────────────────────────────────────────
    local navHdr = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    navHdr:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
    navHdr:SetText(L["NAV_TITLE"])
    navHdr:SetTextColor(0.6, 0.6, 0.6)
    y = y - 18
    
    -- ── View Links ──────────────────────────────────────
    local function CreateViewLink(label, viewName, posY)
        local btn = CreateFrame("Button", nil, leftPanel)
        btn:SetSize(LEFT_W - 24, 24)
        btn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, posY)
        
        -- Left-border accent for active state
        local accent = btn:CreateTexture(nil, "ARTWORK")
        accent:SetSize(3, 18)
        accent:SetPoint("LEFT", btn, "LEFT", 0, 0)
        accent:SetColorTexture(0.05, 0.65, 1, 1)
        accent:Hide()
        btn._accent = accent
        
        -- Label, indented past accent
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetPoint("LEFT",  btn, "LEFT",  8, 0)
        fs:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        fs:SetText(label)
        fs:SetTextColor(0.4, 0.8, 1)
        fs:SetJustifyH("LEFT")
        btn._text = fs
        
        btn:SetScript("OnClick", function()
            ShowView(viewName)
        end)
        
        btn:SetScript("OnEnter", function(self)
            if self._text and currentView ~= viewName then
                self._text:SetTextColor(0.7, 0.95, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if self._text and currentView ~= viewName then
                self._text:SetTextColor(0.4, 0.8, 1)
            end
        end)
        
        navLinks[viewName] = btn
        return btn
    end
    
    CreateViewLink(L["NAV_LOCATIONS"], "locations", y)
    y = y - 28
    
    CreateViewLink(L["NAV_SETTINGS"], "settings", y)
    
    -- Vertical divider
    local vSep = f:CreateTexture(nil, "ARTWORK")
    vSep:SetPoint("TOPLEFT",    f, "TOPLEFT",    1 + LEFT_W, -(HEADER_H + 1))
    vSep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1 + LEFT_W, 1)
    vSep:SetWidth(DIVIDER_W)
    vSep:SetColorTexture(0.28, 0.28, 0.32, 1)

    ----========════════════════════════════════════════════════
    -- INITIALIZE VIEWS
    ----========════════════════════════════════════════════════
    CreateLocationsView()
    CreateSettingsView()
    ShowView("locations")

    -- ── OnShow: restore position, init tiers, select tab ─
    f:SetScript("OnShow", function(self)
        -- Restore saved position if available
        if AnySpec.db and AnySpec.db.framePosition then
            local pos = AnySpec.db.framePosition
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        end
        
        -- Restore toast position
        if AnySpec.db and AnySpec.db.toastPosition then
            AnySpec.UI.Proposal:SetPosition(AnySpec.db.toastPosition)
        end

        -- Load tier list the first time the frame is opened
        tierList = BuildTierList()
        if #tierList > 0 and not currentTierIdx then
            currentTierIdx = tierList[1].index
            UIDropDownMenu_SetSelectedValue(tierDropdown, currentTierIdx)
            UIDropDownMenu_SetText(tierDropdown, tierList[1].name)
        end

        SelectTab(currentTab)
    end)

    f:Hide()
    return f
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------
function MF:Init()
    frame = CreateMainFrame()
    assignmentDialog = CreateAssignmentDialog()
end

function MF:Toggle()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function MF:Open()
    if frame then frame:Show() end
end

function MF:Close()
    if frame then frame:Hide() end
end
