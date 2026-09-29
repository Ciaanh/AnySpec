-- AnySpec/UI/MainFrame.lua
-- Custom main configuration window (no Blizzard options panel).
-- Header  : wordmark, current spec + loadout, close button.
-- Sidebar : view navigation + drag-to-action-bar Quick Access tile.
-- Views   : "locations" (per-instance spec assignments, edited inline),
--           "content_types" (per-category / per-difficulty defaults, same inline editor)
--           and "settings".

AnySpec     = AnySpec     or {}
AnySpec.UI  = AnySpec.UI  or {}
AnySpec.UI.MainFrame = AnySpec.UI.MainFrame or {}
local MF = AnySpec.UI.MainFrame
local L  = AnySpec.L
local T  = AnySpec.UI.Theme
local W  = AnySpec.UI.Widgets
local C  = T.C

------------------------------------------------------------
-- Layout constants
------------------------------------------------------------
local FRAME_NAME = "AnySpecFrame"
local FRAME_W    = 820
local FRAME_H    = 560
local HEADER_H   = 48
local SIDEBAR_W  = 200
local CONTENT_PAD = 22

local ROW_H          = 44     -- collapsed instance row
local ROW_GAP        = 2
local PAIR_H         = 28     -- one spec+loadout line in the inline editor
local PAIR_GAP       = 6
local EDITOR_HINT_H  = 22
local EDITOR_ADD_H   = 30
local EDITOR_PAD_B   = 10
local EDITOR_INDENT  = 50
local MAX_PAIRS      = 3
local MAX_CHIPS      = 3

------------------------------------------------------------
-- Module state
------------------------------------------------------------
local frame          = nil
local currentView    = "locations"  -- "locations", "content_types" or "settings"
local currentTab     = "dungeons"   -- "dungeons" or "raids"
local currentTierIdx = nil          -- nil → default to newest tier on first open
local tierList       = {}           -- { { index, name }, ... } newest-first
local filterText     = ""
local instanceCache  = {}           -- ["tier:isRaid"] = instances

local tierDropdown   = nil
local tabControl     = nil
local emptyLabel     = nil

-- An assignment list: { scrollFrame, scrollChild, pool = {}, active = {} }.
-- Each row edits one assignment target: AnySpec.charDB[row._tblName][row._key].
local instList       = nil          -- per-instance rows (pooled, rebuilt per tier/tab/filter)
local ctList         = nil          -- content type + difficulty rows (static)

local expandedRow    = nil          -- row whose editor is open
local expTblName     = nil          -- its target, kept so an instance-list rebuild
local expKey         = nil          --   can find the row again
local editor         = nil          -- the single shared inline editor
local editorPairs    = {}           -- working copy: { { specIndex, loadoutID }, ... }

local specPill       = nil
local quickAccessIcon = nil

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

local function GetCurrentSpecIcon()
    local cur = AnySpec.SpecManager:GetCurrentSpecIndex()
    local info = cur and AnySpec.SpecManager:GetSpecInfo(cur)
    return info and info.icon or 134063
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

-- Returns instances for the given tier + type (cached), restoring the original tier.
-- Open-world boss entries (named like the tier itself) are skipped.
local function GetInstances(tierIndex, isRaid)
    local key = tierIndex .. ":" .. tostring(isRaid)
    if instanceCache[key] then return instanceCache[key] end

    LoadEJ()
    if not EJ_GetInstanceByIndex then return {} end
    local tierName = EJ_GetTierInfo and EJ_GetTierInfo(tierIndex) or ""
    local savedTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or 1
    EJ_SelectTier(tierIndex)
    local out = {}
    for i = 1, 999 do
        local id, name, _, _, icon = EJ_GetInstanceByIndex(i, isRaid)
        if not id then break end
        if name ~= tierName then
            tinsert(out, { id = id, name = name, icon = icon })
        end
    end
    EJ_SelectTier(savedTier)
    instanceCache[key] = out
    return out
end

------------------------------------------------------------
-- Assignment data helpers
------------------------------------------------------------
local function GetAssignments(tblName, key)
    local charDB = AnySpec.charDB
    local tbl = charDB and charDB[tblName]
    return (tbl and key ~= nil) and tbl[key] or nil
end

local function GetLoadoutItemsForSpec(specIndex)
    local items = { { label = L["LOADOUT_DEFAULT"], value = nil } }
    if specIndex then
        for _, l in ipairs(AnySpec.SpecManager:GetLoadoutsForSpec(specIndex)) do
            tinsert(items, { label = l.name, value = l.configID })
        end
    end
    return items
end

local function GetSpecItems()
    local items = {}
    for _, s in ipairs(AnySpec.SpecManager:GetAllSpecs()) do
        tinsert(items, { label = s.name, value = s.specIndex, icon = s.icon })
    end
    return items
end

------------------------------------------------------------
-- Assignment lists: layout
------------------------------------------------------------
local function EditorHeight()
    local n = #editorPairs
    local h = EDITOR_HINT_H + n * (PAIR_H + PAIR_GAP)
    if n < MAX_PAIRS then h = h + EDITOR_ADD_H end
    return h + EDITOR_PAD_B
end

-- Positions every active row of a list top-down and sizes its scroll child.
local function RelayoutList(list)
    if not list then return end
    local y = 0
    for _, row in ipairs(list.active) do
        local h = ROW_H
        if row == expandedRow then h = ROW_H + EditorHeight() end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  list.scrollChild, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", list.scrollChild, "TOPRIGHT", 0, -y)
        row:SetHeight(h)
        y = y + h + ROW_GAP
    end
    list.scrollChild:SetHeight(math.max(1, y))
    list.scrollFrame:UpdateScroll()
end

local function Relayout()
    RelayoutList(instList)
    RelayoutList(ctList)
end

------------------------------------------------------------
-- Assignment lists: rows
------------------------------------------------------------
local function PaintRow(row)
    local expanded = (row == expandedRow)
    if expanded then
        T:Surface(row, C.surface, C.border)
    else
        T:Surface(row, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    end
    row._chevRight:SetShown(not expanded)
    row._chevDown:SetShown(expanded)
end

-- Refreshes the chips / "+ Assign" button of a row from saved data.
local function UpdateRowContent(row)
    local asgn = GetAssignments(row._tblName, row._key)
    local expanded = (row == expandedRow)
    local shown = 0
    local anchor = row._chevRight
    if asgn and not expanded then
        for i = math.min(#asgn, MAX_CHIPS), 1, -1 do
            local info = AnySpec.SpecManager:GetSpecInfo(asgn[i].specIndex)
            if info then
                shown = shown + 1
                local chip = row._chips[shown]
                chip:SetContent(info.icon, info.name)
                chip:ClearAllPoints()
                chip:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
                chip:Show()
                anchor = chip
            end
        end
    end
    for i = shown + 1, MAX_CHIPS do row._chips[i]:Hide() end
    row._assignBtn:SetShown(not expanded and shown == 0)
    PaintRow(row)
end

local ToggleExpand  -- forward declaration

local function CreateRow(list)
    local row = CreateFrame("Frame", nil, list.scrollChild, "BackdropTemplate")
    row._list = list
    row:SetHeight(ROW_H)

    -- Clickable head (top ROW_H px); the editor sits below it when expanded.
    local head = CreateFrame("Button", nil, row)
    head:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, 0)
    head:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    head:SetHeight(ROW_H)
    local hl = head:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(T.RGBA(C.surfaceHi, 0.6))
    head:SetScript("OnClick", function() ToggleExpand(row) end)

    local ico = T:Icon(head, 28, nil)
    ico:SetPoint("LEFT", head, "LEFT", 10, 0)
    row._icon = ico

    local chevRight = T:Glyph(head, "chevron-right", 12, C.faint)
    chevRight:SetPoint("RIGHT", head, "RIGHT", -12, 0)
    local chevDown = T:Glyph(head, "chevron-down", 12, C.muted)
    chevDown:SetPoint("RIGHT", head, "RIGHT", -12, 0)
    row._chevRight, row._chevDown = chevRight, chevDown

    row._chips = {}
    for i = 1, MAX_CHIPS do
        local chip = W.CreateChip(head, nil, "")
        chip:EnableMouse(false)
        chip:Hide()
        row._chips[i] = chip
    end

    local assignBtn = W.CreateButton(head, "", "default", 84, 24)
    assignBtn:SetText("|cff9aa1b0+|r  " .. L["ASSIGN_BUTTON"])
    assignBtn:SetPoint("RIGHT", chevRight, "LEFT", -10, 0)
    assignBtn:SetScript("OnClick", function()
        ToggleExpand(row, true)
    end)
    row._assignBtn = assignBtn

    local name = T:Text(head, 15, C.text)
    name:SetPoint("LEFT", ico, "RIGHT", 12, 0)
    name:SetPoint("RIGHT", head, "RIGHT", -300, 0)
    row._name = name

    return row
end

local function AcquireRow(list, index)
    local row = list.pool[index]
    if not row then
        row = CreateRow(list)
        list.pool[index] = row
    end
    row:Show()
    return row
end

local function NewList(sf, sc)
    return { scrollFrame = sf, scrollChild = sc, pool = {}, active = {} }
end

------------------------------------------------------------
-- Inline assignment editor (one shared instance)
------------------------------------------------------------
local RenderEditor  -- forward declaration

local function SaveEditor()
    local tbl = AnySpec.charDB and expTblName and AnySpec.charDB[expTblName]
    if not tbl or expKey == nil then return end
    local out = {}
    for _, p in ipairs(editorPairs) do
        if p.specIndex then
            tinsert(out, { specIndex = p.specIndex, loadoutID = p.loadoutID })
        end
    end
    tbl[expKey] = (#out > 0) and out or nil
end

local function AddEditorPair(preferredSpec)
    if #editorPairs >= MAX_PAIRS then return end
    local used = {}
    for _, p in ipairs(editorPairs) do used[p.specIndex] = true end
    local spec = (preferredSpec and not used[preferredSpec]) and preferredSpec or nil
    if not spec then
        for _, s in ipairs(AnySpec.SpecManager:GetAllSpecs()) do
            if not used[s.specIndex] then spec = s.specIndex break end
        end
    end
    tinsert(editorPairs, { specIndex = spec, loadoutID = nil })
    SaveEditor()
    RenderEditor()
    Relayout()
end

local function CreatePairLine(parent, index)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(PAIR_H)

    local badge = CreateFrame("Frame", nil, line, "BackdropTemplate")
    badge:SetSize(22, 22)
    badge:SetPoint("LEFT", line, "LEFT", 0, 0)
    T:Surface(badge, C.surfaceHi, C.borderHi)
    local num = T:Text(badge, 12, C.textDim)
    num:SetJustifyH("CENTER")
    num:SetPoint("CENTER")
    num:SetText(tostring(index))

    local specDD = W.CreateCustomDropdown(line, 150, PAIR_H)
    specDD:SetPoint("LEFT", badge, "RIGHT", 8, 0)
    specDD:SetPlaceholder(L["DIALOG_SPEC_PLACEHOLDER"])

    local removeBtn = W.CreateIconButton(line, "close", PAIR_H, L["EDITOR_REMOVE"])
    removeBtn:SetPoint("RIGHT", line, "RIGHT", 0, 0)

    local loadoutDD = W.CreateCustomDropdown(line, 200, PAIR_H)
    loadoutDD:SetPoint("LEFT", specDD, "RIGHT", 8, 0)
    loadoutDD:SetPoint("RIGHT", removeBtn, "LEFT", -6, 0)
    loadoutDD:SetPlaceholder(L["LOADOUT_DEFAULT"])

    specDD:SetOnChanged(function(value)
        local p = editorPairs[index]
        if not p then return end
        p.specIndex, p.loadoutID = value, nil
        loadoutDD:SetItems(GetLoadoutItemsForSpec(value))
        loadoutDD:SetSelected(nil)
        SaveEditor()
    end)
    loadoutDD:SetOnChanged(function(value)
        local p = editorPairs[index]
        if not p then return end
        p.loadoutID = value
        SaveEditor()
    end)
    removeBtn:SetScript("OnClick", function()
        tremove(editorPairs, index)
        SaveEditor()
        RenderEditor()
        Relayout()
    end)

    line.specDD, line.loadoutDD = specDD, loadoutDD
    return line
end

local function CreateEditor()
    local ed = CreateFrame("Frame", nil, instList.scrollChild)
    ed:Hide()

    local hint = T:Text(ed, 12, C.muted)
    hint:SetPoint("TOPLEFT", ed, "TOPLEFT", 0, -2)
    hint:SetText(L["EDITOR_HINT"])

    ed._lines = {}
    for i = 1, MAX_PAIRS do
        local line = CreatePairLine(ed, i)
        line:SetPoint("TOPLEFT",  ed, "TOPLEFT",  0, -(EDITOR_HINT_H + (i - 1) * (PAIR_H + PAIR_GAP)))
        line:SetPoint("TOPRIGHT", ed, "TOPRIGHT", 0, -(EDITOR_HINT_H + (i - 1) * (PAIR_H + PAIR_GAP)))
        ed._lines[i] = line
    end

    local ar, ag, ab = T:GetAccent()
    local addBtn = CreateFrame("Button", nil, ed)
    addBtn:SetSize(200, 24)
    local plus = T:Glyph(addBtn, "plus", 10, { ar, ag, ab, 1 }, 2)
    plus:SetPoint("LEFT", addBtn, "LEFT", 30, 0)
    local addText = T:Text(addBtn, 13, { ar, ag, ab, 1 })
    addText:SetPoint("LEFT", plus, "RIGHT", 6, 0)
    addText:SetText(L["DIALOG_ADD_PAIR"] .. "  |cff7d8494" .. L["EDITOR_ADD_LIMIT"] .. "|r")
    addBtn:SetScript("OnEnter", function() addText:SetAlpha(0.8) end)
    addBtn:SetScript("OnLeave", function() addText:SetAlpha(1) end)
    addBtn:SetScript("OnClick", function() AddEditorPair() end)
    ed._addBtn = addBtn

    return ed
end

RenderEditor = function()
    if not editor then return end
    local specItems = GetSpecItems()
    local n = #editorPairs
    for i, line in ipairs(editor._lines) do
        local p = editorPairs[i]
        if p then
            line.specDD:SetItems(specItems)
            if p.specIndex then line.specDD:SetSelected(p.specIndex) else line.specDD:ClearSelection() end
            line.loadoutDD:SetItems(GetLoadoutItemsForSpec(p.specIndex))
            line.loadoutDD:SetSelected(p.loadoutID)
            line:Show()
        else
            line.specDD:CloseMenu()
            line.loadoutDD:CloseMenu()
            line:Hide()
        end
    end
    editor._addBtn:ClearAllPoints()
    editor._addBtn:SetPoint("TOPLEFT", editor, "TOPLEFT", 0,
        -(EDITOR_HINT_H + n * (PAIR_H + PAIR_GAP) + 2))
    editor._addBtn:SetShown(n < MAX_PAIRS)
end

local function AnchorEditor(row)
    editor:SetParent(row)
    editor:ClearAllPoints()
    editor:SetPoint("TOPLEFT",     row, "TOPLEFT",     EDITOR_INDENT, -ROW_H)
    editor:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -14, 0)
    editor:Show()
end

local function CollapseEditor()
    local prev = expandedRow
    expandedRow, expTblName, expKey = nil, nil, nil
    wipe(editorPairs)
    RenderEditor()  -- closes any open dropdown menu
    editor:Hide()
    if prev then UpdateRowContent(prev) end
end

-- Expands the given row (collapsing any other). Clicking the open row collapses it.
-- addIfEmpty: start with one pair (current spec) when the target has no assignment.
ToggleExpand = function(row, addIfEmpty)
    if row == expandedRow and not addIfEmpty then
        CollapseEditor()
        Relayout()
        return
    end

    local previous = expandedRow
    expandedRow, expTblName, expKey = row, row._tblName, row._key
    if previous and previous ~= row then UpdateRowContent(previous) end

    wipe(editorPairs)
    for _, p in ipairs(GetAssignments(expTblName, expKey) or {}) do
        tinsert(editorPairs, { specIndex = p.specIndex, loadoutID = p.loadoutID })
    end
    if addIfEmpty and #editorPairs == 0 then
        AddEditorPair(AnySpec.SpecManager:GetCurrentSpecIndex())
    end

    AnchorEditor(row)
    RenderEditor()
    UpdateRowContent(row)
    Relayout()
end

------------------------------------------------------------
-- Instance list: rebuild for current tab / tier / filter
------------------------------------------------------------
local function RefreshInstanceList()
    if not frame or not instList then return end
    local tIdx = currentTierIdx or (tierList[1] and tierList[1].index)
    if not tIdx then return end

    local instances = GetInstances(tIdx, currentTab == "raids")
    local needle = filterText:lower()
    local editingInstance = expandedRow and expandedRow._list == instList

    wipe(instList.active)
    local expandedNow = nil
    for _, inst in ipairs(instances) do
        if needle == "" or inst.name:lower():find(needle, 1, true) then
            local row = AcquireRow(instList, #instList.active + 1)
            row._tblName = "instanceAssignments"
            row._key = inst.id
            row._name:SetText(inst.name)
            row._icon:SetTexture((inst.icon and inst.icon ~= 0) and inst.icon or 134400)
            tinsert(instList.active, row)
            if editingInstance and inst.id == expKey then expandedNow = row end
        end
    end
    for i = #instList.active + 1, #instList.pool do
        instList.pool[i]:Hide()
        instList.pool[i]._key = nil
    end

    -- Pooled rows may now show other instances: follow the edited one, or close it.
    if editingInstance then
        if expandedNow then
            expandedRow = expandedNow
            AnchorEditor(expandedNow)
        else
            CollapseEditor()
        end
    end

    for _, row in ipairs(instList.active) do UpdateRowContent(row) end
    emptyLabel:SetShown(#instList.active == 0)
    Relayout()
end

local function RefreshAllRows()
    for _, list in ipairs({ instList, ctList }) do
        for _, row in ipairs(list.active) do UpdateRowContent(row) end
    end
end

------------------------------------------------------------
-- Header: current spec pill
------------------------------------------------------------
local function UpdateSpecPill()
    if not specPill then return end
    local cur = AnySpec.SpecManager:GetCurrentSpecIndex()
    local info = cur and AnySpec.SpecManager:GetSpecInfo(cur)
    if not info then
        specPill:Hide()
        return
    end
    specPill._icon:SetTexture(info.icon)
    specPill._name:SetText(info.name)
    local lo = AnySpec.SpecManager:GetCurrentLoadoutInfo()
    specPill._loadout:SetText(lo and lo.name or "")
    local w = 6 + 20 + 8 + specPill._name:GetStringWidth() + 8 + specPill._loadout:GetStringWidth() + 12
    specPill:SetWidth(math.ceil(w))
    specPill:Show()
    if quickAccessIcon then quickAccessIcon:SetTexture(info.icon) end
end

------------------------------------------------------------
-- Views
------------------------------------------------------------
local function CreateViewHeader(view, title, subtitle)
    local t = T:Text(view, 22, C.text)
    t:SetPoint("TOPLEFT", view, "TOPLEFT", CONTENT_PAD, -18)
    t:SetText(title)
    local s = T:Text(view, 13, C.muted)
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -5)
    s:SetText(subtitle)
    return t, s
end

local function BuildLocationsView(view)
    CreateViewHeader(view, L["VIEW_LOCATIONS"], L["VIEW_LOCATIONS_DESC"])

    -- Expansion picker (top right)
    tierDropdown = W.CreateCustomDropdown(view, 190, 28)
    tierDropdown:SetPoint("TOPRIGHT", view, "TOPRIGHT", -CONTENT_PAD, -22)
    tierDropdown:SetPlaceholder(L["TIER_DROPDOWN_DEFAULT"])
    tierDropdown:SetOnChanged(function(value)
        currentTierIdx = value
        RefreshInstanceList()
    end)

    -- Dungeons / Raids
    tabControl = W.CreateSegmented(view, {
        { key = "dungeons", label = L["TAB_DUNGEONS"] },
        { key = "raids",    label = L["TAB_RAIDS"] },
    }, function(key)
        currentTab = key
        RefreshInstanceList()
    end)
    tabControl:SetPoint("TOPLEFT", view, "TOPLEFT", CONTENT_PAD, -76)
    tabControl:SetSelected(currentTab)

    -- Filter
    local search = W.CreateSearchBox(view, 190, L["SEARCH_PLACEHOLDER"], function(txt)
        filterText = txt or ""
        RefreshInstanceList()
    end)
    search:SetPoint("TOPRIGHT", view, "TOPRIGHT", -CONTENT_PAD, -78)

    -- List
    local sf, sc = W.CreateScrollArea(view)
    sf:SetPoint("TOPLEFT",     view, "TOPLEFT",     CONTENT_PAD - 4, -120)
    sf:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -CONTENT_PAD + 12, 12)
    instList = NewList(sf, sc)

    emptyLabel = T:Text(view, 14, C.muted)
    emptyLabel:SetPoint("TOP", sf, "TOP", 0, -60)
    emptyLabel:SetText(L["INSTANCES_EMPTY"])
    emptyLabel:Hide()

    editor = CreateEditor()
end

-- Categories and their per-difficulty overrides. Keys match ZoneDetector's
-- categories; difficulty IDs match what GetInstanceInfo() reports at runtime.
local CONTENT_TYPES = {
    { key = "open_world",  label = "CAT_OPEN_WORLD" },
    { key = "dungeon",     label = "CAT_DUNGEON",
      diffs = { { id = 1,  label = "DIFF_NORMAL" },
                { id = 2,  label = "DIFF_HEROIC" },
                { id = 23, label = "DIFF_MYTHIC" } } },
    { key = "mythic_plus", label = "CAT_MYTHIC_PLUS" },
    { key = "raid",        label = "CAT_RAID",
      diffs = { { id = 17, label = "DIFF_LFR" },
                { id = 14, label = "DIFF_NORMAL" },
                { id = 15, label = "DIFF_HEROIC" },
                { id = 16, label = "DIFF_MYTHIC" } } },
    { key = "delve",       label = "CAT_DELVE" },
    { key = "pvp",         label = "CAT_PVP" },
    { key = "arena",       label = "CAT_ARENA" },
}

local function BuildContentTypesView(view)
    CreateViewHeader(view, L["VIEW_CONTENT_TYPES"], L["VIEW_CONTENT_TYPES_DESC"])

    local sf, sc = W.CreateScrollArea(view)
    sf:SetPoint("TOPLEFT",     view, "TOPLEFT",     CONTENT_PAD - 4, -76)
    sf:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -CONTENT_PAD + 12, 12)
    ctList = NewList(sf, sc)

    local function AddRow(tblName, key, label, isOverride)
        local row = AcquireRow(ctList, #ctList.active + 1)
        row._tblName, row._key = tblName, key
        row._icon:Hide()
        row._name:ClearAllPoints()
        row._name:SetPoint("LEFT",  row._icon, "LEFT", isOverride and 24 or 4, 0)
        row._name:SetPoint("RIGHT", row, "RIGHT", -300, 0)
        row._name:SetTextColor(T.RGBA(isOverride and C.textDim or C.text))
        row._name:SetText(label)
        tinsert(ctList.active, row)
    end

    for _, c in ipairs(CONTENT_TYPES) do
        AddRow("categoryAssignments", c.key, L[c.label], false)
        for _, d in ipairs(c.diffs or {}) do
            AddRow("difficultyAssignments", c.key .. ":" .. d.id, L[d.label], true)
        end
    end    RelayoutList(ctList)
end

local function BuildSettingsView(view)
    CreateViewHeader(view, L["VIEW_SETTINGS"], L["VIEW_SETTINGS_DESC"])
    local innerW = FRAME_W - SIDEBAR_W - CONTENT_PAD * 2

    -- ── Card: toggles ─────────────────────────────────────
    local card1 = CreateFrame("Frame", nil, view, "BackdropTemplate")
    T:Surface(card1, C.surface, C.border)
    card1:SetPoint("TOPLEFT", view, "TOPLEFT", CONTENT_PAD, -76)
    card1:SetSize(innerW, 128)

    local switches = {}
    local function ToggleRow(y, title, desc, getter, setter)
        local tl = T:Text(card1, 15, C.text)
        tl:SetPoint("TOPLEFT", card1, "TOPLEFT", 16, y)
        tl:SetText(title)
        local ds = T:Text(card1, 13, C.muted)
        ds:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, -4)
        ds:SetText(desc)
        local sw = W.CreateSwitch(card1, setter)
        sw:SetPoint("TOPRIGHT", card1, "TOPRIGHT", -16, y - 8)
        sw._getter = getter
        tinsert(switches, sw)
    end

    ToggleRow(-14, L["SETTINGS_AUTO_SWITCH"], L["SETTINGS_AUTO_SWITCH_DESC"], function()
        return AnySpec.db and AnySpec.db.proposalEnabled ~= false
    end, function(val)
        if AnySpec.db then AnySpec.db.proposalEnabled = val end
    end)

    local div = card1:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  card1, "TOPLEFT",  1, -64)
    div:SetPoint("TOPRIGHT", card1, "TOPRIGHT", -1, -64)
    div:SetColorTexture(T.RGBA(C.border))

    ToggleRow(-78, L["SETTINGS_MINIMAP"], L["SETTINGS_MINIMAP_DESC"], function()
        return AnySpec.db and AnySpec.db.minimapButton ~= false
    end, function(val)
        if AnySpec.db then AnySpec.db.minimapButton = val end
        AnySpec.UI.MinimapButton:SetShown(val)
    end)

    -- ── Card: toast position ──────────────────────────────
    local card2 = CreateFrame("Frame", nil, view, "BackdropTemplate")
    T:Surface(card2, C.surface, C.border)
    card2:SetPoint("TOPLEFT", card1, "BOTTOMLEFT", 0, -14)
    card2:SetSize(innerW, 196)

    local pt = T:Text(card2, 15, C.text)
    pt:SetPoint("TOPLEFT", card2, "TOPLEFT", 16, -14)
    pt:SetText(L["SETTINGS_TOAST_POSITION"])
    local pd = T:Text(card2, 13, C.muted)
    pd:SetPoint("TOPLEFT", pt, "BOTTOMLEFT", 0, -4)
    pd:SetText(L["SETTINGS_TOAST_POSITION_DESC"])

    local testBtn = W.CreateButton(card2, L["SETTINGS_TEST_TOAST"], "default", 120, 28)
    testBtn:SetPoint("TOPRIGHT", card2, "TOPRIGHT", -16, -16)
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

    local positions = {
        { key = "top_center",    label = L["POS_TOP_CENTER"],    point = "TOP",      x = 0,  y = -6 },
        { key = "center",        label = L["POS_CENTER"],        point = "CENTER",   x = 0,  y = 0 },
        { key = "top_right",     label = L["POS_TOP_RIGHT"],     point = "TOPRIGHT", x = -6, y = -6 },
        { key = "bottom_center", label = L["POS_BOTTOM_CENTER"], point = "BOTTOM",   x = 0,  y = 6 },
    }
    local GAP = 10
    local tileW = math.floor((innerW - 32 - GAP * 3) / 4)
    local tiles = {}

    local function PaintTiles()
        local cur = AnySpec.UI.Proposal:GetPosition()
        local ar, ag, ab = T:GetAccent()
        for _, tile in ipairs(tiles) do
            if tile._key == cur then
                T:Surface(tile, C.selected, { ar, ag, ab, 1 })
                tile._marker:SetColorTexture(ar, ag, ab, 1)
                tile._label:SetTextColor(T.RGBA(C.text))
            else
                T:Surface(tile, C.window, C.border)
                tile._marker:SetColorTexture(T.RGBA(C.borderHi))
                tile._label:SetTextColor(T.RGBA(C.textDim))
            end
        end
    end

    for i, pos in ipairs(positions) do
        local tile = CreateFrame("Button", nil, card2, "BackdropTemplate")
        tile:SetSize(tileW, 104)
        tile:SetPoint("TOPLEFT", card2, "TOPLEFT", 16 + (i - 1) * (tileW + GAP), -76)
        tile._key = pos.key

        local screen = CreateFrame("Frame", nil, tile, "BackdropTemplate")
        screen:SetPoint("TOPLEFT",  tile, "TOPLEFT",  10, -10)
        screen:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -10, -10)
        screen:SetHeight(58)
        screen:EnableMouse(false)
        T:Surface(screen, C.header, C.border)

        local marker = screen:CreateTexture(nil, "OVERLAY")
        marker:SetSize(28, 9)
        marker:SetPoint(pos.point, screen, pos.point, pos.x, pos.y)
        tile._marker = marker

        local lbl = T:Text(tile, 13, C.textDim)
        lbl:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 10, 10)
        lbl:SetText(pos.label)
        tile._label = lbl

        tile:SetScript("OnClick", function()
            if AnySpec.UI.Proposal:SetPosition(pos.key) then
                if AnySpec.db then AnySpec.db.toastPosition = pos.key end
                PaintTiles()
            end
        end)
        tinsert(tiles, tile)
    end

    view:SetScript("OnShow", function()
        for _, sw in ipairs(switches) do sw:SetChecked(sw._getter()) end
        PaintTiles()
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
    f:EnableMouse(true)
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
    T:Surface(f, C.window, C.border)

    -- ESC closes the frame
    tinsert(UISpecialFrames, FRAME_NAME)

    -- ── Header ────────────────────────────────────────────
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H - 1)
    T:Fill(header, C.header):SetAllPoints()
    T:HRule(f, -HEADER_H)

    local title = T:Text(header, 20, C.text)
    title:SetPoint("LEFT", header, "LEFT", 18, 0)
    title:SetText("|cff" .. T:GetAccentHex() .. "Any|rSpec")

    local closeBtn = W.CreateIconButton(header, "close", 30)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -9, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    specPill = CreateFrame("Frame", nil, header, "BackdropTemplate")
    specPill:SetHeight(30)
    specPill:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    T:Surface(specPill, C.surface, C.border)
    specPill._icon = T:Icon(specPill, 20, nil)
    specPill._icon:SetPoint("LEFT", specPill, "LEFT", 6, 0)
    specPill._name = T:Text(specPill, 14, C.text)
    specPill._name:SetPoint("LEFT", specPill._icon, "RIGHT", 8, 0)
    specPill._loadout = T:Text(specPill, 13, C.muted)
    specPill._loadout:SetPoint("LEFT", specPill._name, "RIGHT", 8, 0)

    -- ── Sidebar ───────────────────────────────────────────
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT",    f, "TOPLEFT",    1, -(HEADER_H + 1))
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR_W)
    T:Fill(sidebar, C.sidebar):SetAllPoints()

    local vSep = f:CreateTexture(nil, "ARTWORK")
    vSep:SetPoint("TOPLEFT",    sidebar, "TOPRIGHT",    0, 0)
    vSep:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
    vSep:SetWidth(1)
    vSep:SetColorTexture(T.RGBA(C.border))

    -- ── Views ─────────────────────────────────────────────
    local views = {}
    local navButtons = {}

    local function ShowView(viewName)
        if viewName ~= currentView and expandedRow then
            CollapseEditor()
            Relayout()
        end
        currentView = viewName
        for name, view in pairs(views) do view:SetShown(name == viewName) end
        for name, btn in pairs(navButtons) do
            local active = (name == viewName)
            T:Surface(btn, active and C.selected or { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
            btn._text:SetTextColor(T.RGBA(active and C.text or C.textDim))
        end
    end

    local function NavButton(label, viewName, y)
        local btn = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
        btn:SetSize(SIDEBAR_W - 24, 34)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 12, y)
        local fs = T:Text(btn, 15, C.textDim)
        fs:SetPoint("LEFT", btn, "LEFT", 12, 0)
        fs:SetText(label)
        btn._text = fs
        btn:SetScript("OnClick", function() ShowView(viewName) end)
        btn:SetScript("OnEnter", function(self)
            if currentView ~= viewName then T:Surface(self, T.C.surface, { 0, 0, 0, 0 }) end
        end)
        btn:SetScript("OnLeave", function(self)
            if currentView ~= viewName then T:Surface(self, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }) end
        end)
        navButtons[viewName] = btn
    end
    NavButton(L["NAV_LOCATIONS"],     "locations",     -16)
    NavButton(L["NAV_CONTENT_TYPES"], "content_types", -54)
    NavButton(L["NAV_SETTINGS"],      "settings",      -92)

    -- Quick Access (bottom of sidebar)
    local version = C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("AnySpec", "Version")
    local ver = T:Text(sidebar, 12, C.faint)
    ver:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 16, 14)
    ver:SetText((version and ("v" .. version .. "  ·  ") or "") .. "/anyspec")

    local tile = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
    tile:SetSize(SIDEBAR_W - 24, 52)
    tile:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 12, 36)
    tile:EnableMouse(true)
    tile:SetFrameLevel(sidebar:GetFrameLevel() + 10)  -- stay above every sibling/overlay
    tile:RegisterForClicks("LeftButtonUp")
    tile:RegisterForDrag("LeftButton")
    T:Surface(tile, C.surface, C.borderHi)

    quickAccessIcon = T:Icon(tile, 32, GetCurrentSpecIcon())
    quickAccessIcon:SetPoint("LEFT", tile, "LEFT", 10, 0)
    local qName = T:Text(tile, 14, C.text)
    qName:SetPoint("TOPLEFT", quickAccessIcon, "TOPRIGHT", 10, -1)
    qName:SetText(L["QUICKACCESS_SWITCH_NAME"])
    local qHint = T:Text(tile, 12, C.muted)
    qHint:SetPoint("BOTTOMLEFT", quickAccessIcon, "BOTTOMRIGHT", 10, 1)
    qHint:SetText(L["QUICKACCESS_DESC"])

    tile:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            print(L["ERR_COMBAT_MACRO"])
            return
        end
        local id = AcquireMacro("switch", "AnySpec", GetCurrentSpecIcon(), "ANYSPEC_SWITCH")
        if id then
            ClearCursor()
            PickupMacro(id)
        else
            print(L["ERR_NO_MACRO_SLOT"])
        end
    end)
    -- A plain click used to do nothing at all; say how to use the tile.
    tile:SetScript("OnClick", function()
        print(L["QUICKACCESS_CLICK_HINT"])
    end)
    tile:SetScript("OnEnter", function(self)
        T:Surface(self, C.surfaceHi, C.borderHi)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["QUICKACCESS_SWITCH_NAME"], 1, 1, 1)
        GameTooltip:AddLine(L["QUICKACCESS_SWITCH_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", function(self)
        T:Surface(self, C.surface, C.borderHi)
        GameTooltip:Hide()
    end)

    local qaLabel = T:Text(sidebar, 11, C.faint)
    qaLabel:SetPoint("BOTTOMLEFT", tile, "TOPLEFT", 4, 8)
    qaLabel:SetText(L["QUICKACCESS_TITLE"]:upper())

    -- ── Content area ──────────────────────────────────────
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     f, "TOPLEFT",     SIDEBAR_W + 2, -(HEADER_H + 1))
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    views.locations = CreateFrame("Frame", nil, content)
    views.locations:SetAllPoints()
    BuildLocationsView(views.locations)

    views.content_types = CreateFrame("Frame", nil, content)
    views.content_types:SetAllPoints()
    BuildContentTypesView(views.content_types)

    views.settings = CreateFrame("Frame", nil, content)
    views.settings:SetAllPoints()
    BuildSettingsView(views.settings)

    ShowView(currentView)

    -- ── OnShow: restore position, init tiers, refresh ─────
    f:SetScript("OnShow", function(self)
        if AnySpec.db and AnySpec.db.framePosition then
            local pos = AnySpec.db.framePosition
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        end

        UpdateSpecPill()

        -- Load tier list the first time the frame is opened
        if #tierList == 0 then
            tierList = BuildTierList()
            local items = {}
            for _, t in ipairs(tierList) do tinsert(items, { label = t.name, value = t.index }) end
            tierDropdown:SetItems(items)
        end
        if #tierList > 0 and not currentTierIdx then
            currentTierIdx = tierList[1].index
        end
        if currentTierIdx then tierDropdown:SetSelected(currentTierIdx) end

        RefreshInstanceList()
        RefreshAllRows()
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

-- Called when the player's spec or loadout changes.
function MF:OnSpecChanged()
    if frame and frame:IsShown() then
        UpdateSpecPill()
        RefreshAllRows()
    end
end
