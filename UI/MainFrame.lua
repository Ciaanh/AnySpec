-- AnySpec/UI/MainFrame.lua
-- Custom main configuration window (no Blizzard options panel).
-- Left panel  : drag-to-action-bar macro buttons + general settings.
-- Right panel : per-instance spec assignments (Dungeons / Raids) using the EJ API.

AnySpec     = AnySpec     or {}
AnySpec.UI  = AnySpec.UI  or {}
AnySpec.UI.MainFrame = AnySpec.UI.MainFrame or {}
local MF = AnySpec.UI.MainFrame

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
local currentTab     = "dungeons"   -- "dungeons" or "raids"
local currentTierIdx = nil          -- nil → default to newest tier on first open
local instanceRows   = {}
local tierList       = {}           -- { { index, name }, ... } newest-first
local tierDropdown   = nil
local scrollFrame    = nil
local scrollChild    = nil

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
    hint:SetText("drag")

    btn:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            print("|cff00aaffAnySpec|r: Cannot create macros during combat.")
            return
        end
        local id = acquireFn()
        if id then
            PickupMacro(id)
        else
            print("|cff00aaffAnySpec|r: No character macro slot available.")
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
-- Per-instance assignment button
------------------------------------------------------------
local function GetAssignmentLabel(instanceID)
    local asgn = AnySpec.charDB and AnySpec.charDB.instanceAssignments[instanceID]
    if asgn and asgn.specs and #asgn.specs > 0 then
        local names = {}
        for _, specIdx in ipairs(asgn.specs) do
            local info = AnySpec.SpecManager:GetSpecInfo(specIdx)
            if info then tinsert(names, info.name) end
        end
        if #names > 0 then
            return table.concat(names, ", ")
        end
    end
    return "|cff555555None|r"
end

local function CreateAssignButton(parent, instanceID, width)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    btn:SetText(GetAssignmentLabel(instanceID))

    local function Refresh()
        btn:SetText(GetAssignmentLabel(instanceID))
    end

    btn:SetScript("OnClick", function(self)
        local specs   = AnySpec.SpecManager:GetAllSpecs()
        local charDB  = AnySpec.charDB
        local cur     = charDB and charDB.instanceAssignments[instanceID]
        local curSpecs = cur and cur.specs or {}
        local curSet = {}
        for _, s in ipairs(curSpecs) do
            curSet[s] = true
        end

        local menuFrame = CreateFrame("Frame", nil, UIParent, "UIDropDownMenuTemplate")
        local menuList  = {}
        
        for _, s in ipairs(specs) do
            local spec = s
            tinsert(menuList, {
                text    = spec.name,
                icon    = spec.icon,
                checked = (curSet[spec.specIndex] == true),
                func    = function()
                    if curSet[spec.specIndex] then
                        curSet[spec.specIndex] = nil
                    else
                        curSet[spec.specIndex] = true
                    end
                    
                    -- Save the updated list
                    local newSpecs = {}
                    for specIdx = 1, 4 do
                        if curSet[specIdx] then
                            tinsert(newSpecs, specIdx)
                        end
                    end
                    
                    if #newSpecs == 0 then
                        AnySpec.AutoSwitch:ClearAssignment("instance", instanceID)
                        print("|cff00aaffAnySpec|r: Cleared assignment for instance " .. instanceID)
                    else
                        charDB.instanceAssignments[instanceID] = { specs = newSpecs }
                        print("|cff00aaffAnySpec|r: Assigned specs to instance " .. instanceID .. ": " .. table.concat(newSpecs, ", "))
                    end
                    
                    Refresh()
                    CloseDropDownMenus()
                end,
                isNotRadio = true,
            })
        end
        
        EasyMenu(menuList, menuFrame, self, 0, 0, "MENU")
    end)

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
        print("|cff00aaffAnySpec|r: DEBUG - Estimated scrollChild width to " .. rowW)
    end
    
    print("|cff00aaffAnySpec|r: DEBUG - Rebuilding instance list for " .. (isRaid and "raids" or "dungeons") 
        .. " (tier " .. tierIndex .. "), found " .. #instances .. " instances, width=" .. rowW)
    
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
            local ab = CreateAssignButton(row, inst.id, BTN_WIDTH)
            ab:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            ab:SetPoint("CENTER", row, "CENTER", (BTN_WIDTH / 2 + 6), 0)

            y = y - ROW_H
            tinsert(instanceRows, row)
        else
            print("|cff00aaffAnySpec|r: DEBUG - Skipping open world boss: " .. inst.name)
        end
    end

    scrollChild:SetHeight(math.max(1, -y + 6))

    if filteredCount == 0 then
        local empty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        empty:SetPoint("CENTER", scrollChild, "CENTER", 0, -40)
        empty:SetTextColor(0.45, 0.45, 0.45)
        empty:SetText("No instances for this combination.")
        scrollChild._emptyLabel = empty
    end
    
    print("|cff00aaffAnySpec|r: DEBUG - Instance list rebuilt, " .. filteredCount .. " instances shown, scrollChild height=" .. scrollChild:GetHeight())
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
        { key = "dungeons", label = "Dungeons" },
        { key = "raids",    label = "Raids"    },
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
    UIDropDownMenu_SetText(tierDropdown, "Expansion...")

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
            print("|cff00aaffAnySpec|r: DEBUG - ScrollFrame resized to " .. w .. ", setting scrollChild width to " .. newW)
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

    -- ── Left panel ────────────────────────────────────────
    -- Create a scroll frame for the left panel content (it can get tall)
    local leftPanelScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    leftPanelScroll:SetPoint("TOPLEFT",    f, "TOPLEFT",    1, -(HEADER_H + 1))
    leftPanelScroll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    leftPanelScroll:SetWidth(LEFT_W)

    local leftPanel = CreateFrame("Frame", nil, leftPanelScroll)
    leftPanel:SetHeight(1)  -- Will be adjusted below
    leftPanel:SetWidth(LEFT_W - 4)  -- Account for scrollbar
    leftPanelScroll:SetScrollChild(leftPanel)

    print("|cff00aaffAnySpec|r: DEBUG - Left panel scroll created, initial width=" .. leftPanel:GetWidth())
    
    -- Now build the content into leftPanel
    local y = -14
    
    print("|cff00aaffAnySpec|r: DEBUG - BuildLeftPanel: panel width=" .. leftPanel:GetWidth())

    -- ── Quick Access ──────────────────────────────────────
    local hdr = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
    hdr:SetText("Quick Access")
    y = y - 22

    local desc = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
    desc:SetWidth(LEFT_W - 32)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.55, 0.55, 0.55)
    desc:SetText("Drag to action bars to create macro shortcuts.")

    local descHeight = math.max(14, math.floor(desc:GetStringHeight() + 0.5))
    y = y - descHeight - 8

    -- Spec-selector button (ANYSPEC_SWITCH)
    local switchIcon = 134063
    local curSpec    = AnySpec.SpecManager:GetCurrentSpecIndex()
    if curSpec then
        local info = AnySpec.SpecManager:GetSpecInfo(curSpec)
        if info then switchIcon = info.icon end
    end

    local switchDrag = CreateDragButton(leftPanel, switchIcon, "Spec Selector",
        "Opens a popup to choose any specialization.", function()
            return AcquireMacro("switch", "AnySpec", switchIcon, "ANYSPEC_SWITCH")
        end)
    switchDrag:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
    print("|cff00aaffAnySpec|r: DEBUG - Switch button at y=" .. y)
    y = y - 32

    -- Per-spec drag buttons
    local specs = AnySpec.SpecManager:GetAllSpecs()
    print("|cff00aaffAnySpec|r: DEBUG - Found " .. #specs .. " specs")
    for i, spec in ipairs(specs) do
        local s = spec
        print("|cff00aaffAnySpec|r: DEBUG - Creating button for spec " .. s.specIndex .. ": " .. s.name .. " at y=" .. y)
        local btn = CreateDragButton(leftPanel, s.icon, s.name,
            "Switch directly to " .. s.name .. ".", function()
                return AcquireMacro("spec" .. s.specIndex, s.name, s.icon, "ANYSPEC_SPEC" .. s.specIndex)
            end)
        btn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
        y = y - 32
    end

    y = y - 10

    -- ── Settings ──────────────────────────────────────────
    local hdr2 = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr2:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 12, y)
    hdr2:SetText("Settings")
    print("|cff00aaffAnySpec|r: DEBUG - Settings section at y=" .. y)
    y = y - 24

    -- Helper to build a checkbox
    local function Checkbox(label, getter, setter)
        local cb = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 8, y)
        cb.text:SetText(label)
        cb:SetChecked(getter())
        cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
        y = y - 28
        return cb
    end

    Checkbox("Minimap button", function()
        return AnySpec.db and AnySpec.db.minimapButton ~= false
    end, function(val)
        if AnySpec.db then AnySpec.db.minimapButton = val end
        AnySpec.UI.MinimapButton:SetShown(val)
    end)

    Checkbox("Enable auto-switch proposals", function()
        return AnySpec.db and AnySpec.db.proposalEnabled ~= false
    end, function(val)
        if AnySpec.db then AnySpec.db.proposalEnabled = val end
    end)

    y = y - 8
    
    -- Set scroll child height
    leftPanel:SetHeight(math.abs(y) + 20)
    print("|cff00aaffAnySpec|r: DEBUG - Left panel content height set to " .. leftPanel:GetHeight())

    -- Vertical divider
    local vSep = f:CreateTexture(nil, "ARTWORK")
    vSep:SetPoint("TOPLEFT",    f, "TOPLEFT",    1 + LEFT_W, -(HEADER_H + 1))
    vSep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1 + LEFT_W, 1)
    vSep:SetWidth(DIVIDER_W)
    vSep:SetColorTexture(0.28, 0.28, 0.32, 1)

    -- ── Right panel ───────────────────────────────────────
    local rightPanel = CreateFrame("Frame", nil, f)
    rightPanel:SetPoint("TOPLEFT",     f, "TOPLEFT",     1 + LEFT_W + DIVIDER_W, -(HEADER_H + 1))
    rightPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    BuildRightPanel(rightPanel)

    -- ── OnShow: restore position, init tiers, select tab ─
    f:SetScript("OnShow", function(self)
        print("|cff00aaffAnySpec|r: DEBUG - MainFrame OnShow: frame width=" .. self:GetWidth() .. ", height=" .. self:GetHeight())
        print("|cff00aaffAnySpec|r: DEBUG - Left panel should be: width=" .. LEFT_W .. ", right panel: width=" .. (FRAME_W - LEFT_W - DIVIDER_W))
        
        -- Restore saved position if available
        if AnySpec.db and AnySpec.db.framePosition then
            local pos = AnySpec.db.framePosition
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
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
