-- AnySpec/SpecManager.lua
-- Spec and loadout switching logic, API wrappers

AnySpec = AnySpec or {}
AnySpec.SpecManager = AnySpec.SpecManager or {}
local SM = AnySpec.SpecManager

-- Pending post-spec-switch loadout ID (set before spec switch, applied on PLAYER_SPECIALIZATION_CHANGED)
local pendingLoadoutID = nil

local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, ...)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end

        if pendingLoadoutID then
            local loadoutID = pendingLoadoutID
            pendingLoadoutID = nil
            SM:ApplyLoadout(loadoutID)
        end

        AnySpec.UI.SpecButtons:Refresh()
        AnySpec.UI.QuickSwitch:Refresh()

    elseif event == "SPECIALIZATION_CHANGE_CAST_FAILED" then
        pendingLoadoutID = nil
        AnySpec.UI.Proposal:OnSpecSwitchFailed()
    end
end

eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPECIALIZATION_CHANGE_CAST_FAILED")
eventFrame:SetScript("OnEvent", OnEvent)

function SM:Init()
    -- Nothing to init yet; event frame handles ongoing updates
end

-- Returns the current 1-based spec index, or nil if not available
function SM:GetCurrentSpecIndex()
    if not C_SpecializationInfo.IsInitialized() then return nil end
    return C_SpecializationInfo.GetSpecialization()
end

-- Returns table: { specID, name, description, icon, role, primaryStat } for specIndex
function SM:GetSpecInfo(specIndex)
    local specID, name, description, icon, role, primaryStat =
        C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if not specID then return nil end
    return {
        specIndex = specIndex,
        specID = specID,
        name = name,
        description = description,
        icon = icon,
        role = role,
        primaryStat = primaryStat,
    }
end

-- Returns array of spec info tables for all player specs
function SM:GetAllSpecs()
    local specs = {}
    local numSpecs = GetNumSpecializations()
    for i = 1, numSpecs do
        specs[i] = self:GetSpecInfo(i)
    end
    return specs
end

-- Attempt to switch to specIndex. Optionally queue loadoutID to apply after switch.
-- Returns false (with reason string) if the switch cannot be initiated.
function SM:SwitchSpec(specIndex, loadoutID)
    if InCombatLockdown() then
        return false, "Cannot switch specs in combat."
    end

    local canUse, failureReason = C_SpecializationInfo.CanPlayerUseTalentSpecUI()
    if not canUse then
        return false, failureReason or "Spec UI unavailable."
    end

    local currentSpec = self:GetCurrentSpecIndex()
    if currentSpec == specIndex then
        -- Already on this spec; apply loadout directly if provided
        if loadoutID then self:ApplyLoadout(loadoutID) end
        return true
    end

    pendingLoadoutID = loadoutID or nil
    C_SpecializationInfo.SetSpecialization(specIndex)
    return true
end

-- Apply a talent loadout by configID. Assumes current spec matches the loadout's spec.
function SM:ApplyLoadout(configID)
    if not configID then return end

    local canChange, failureReason = C_ClassTalents.CanChangeTalents()
    if not canChange then
        -- Temporary restriction: retry once after a short delay
        if not failureReason or failureReason == "" then
            C_Timer.After(0.5, function() SM:ApplyLoadout(configID) end)
        end
        return
    end

    local currentSpec = self:GetCurrentSpecIndex()
    local spec = self:GetSpecInfo(currentSpec)
    if not spec then return end
    local specID = spec.specID

    -- result: 0=Error, 1=NoChangesNecessary, 2=LoadInProgress, 3=Ready
    local result = C_ClassTalents.LoadConfig(configID, true)
    if result == 1 then
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
    elseif result == 3 then
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
        C_ClassTalents.CommitConfig(configID)
    elseif result == 2 then
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
    end
end

-- Get available loadout configs for a given spec
function SM:GetLoadoutsForSpec(specIndex)
    if not C_ClassTalents.GetConfigIDsBySpecID then return {} end
    
    local spec = self:GetSpecInfo(specIndex)
    if not spec then return {} end
    
    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(spec.specID)
    if not configIDs or #configIDs == 0 then return {} end
    
    local loadouts = {}
    for _, configID in ipairs(configIDs) do
        local configInfo = C_Traits.GetConfigInfo(configID)
        if configInfo then
            table.insert(loadouts, {
                configID = configID,
                name = configInfo.name or "Loadout " .. configID,
            })
        end
    end
    
    return loadouts
end

------------------------------------------------------------
-- Current loadout state detection
------------------------------------------------------------

-- Returns the configID of the currently selected saved loadout for the active spec,
-- or nil if the player is on the "Default loadout" (no saved loadout selected).
function SM:GetCurrentLoadoutConfigID()
    local specIndex = self:GetCurrentSpecIndex()
    if not specIndex then return nil end
    local spec = self:GetSpecInfo(specIndex)
    if not spec then return nil end

    if C_ClassTalents.GetLastSelectedSavedConfigID then
        return C_ClassTalents.GetLastSelectedSavedConfigID(spec.specID)
    end
    return nil
end

-- Returns a descriptive table about the current loadout state:
--   { configID = number|nil, name = string, isDefault = bool, isStarterBuild = bool }
function SM:GetCurrentLoadoutInfo()
    local info = { configID = nil, name = "Default loadout", isDefault = true, isStarterBuild = false }

    -- Check starter build first
    if C_ClassTalents.GetStarterBuildActive and C_ClassTalents.GetStarterBuildActive() then
        info.name = "Starter Build"
        info.isDefault = false
        info.isStarterBuild = true
        return info
    end

    local configID = self:GetCurrentLoadoutConfigID()
    if configID then
        info.configID = configID
        info.isDefault = false
        local cfg = C_Traits.GetConfigInfo(configID)
        if cfg and cfg.name and cfg.name ~= "" then
            info.name = cfg.name
        else
            info.name = "Loadout " .. configID
        end
    end

    return info
end

-- Returns true if the player is currently on the default (unsaved) loadout.
function SM:IsOnDefaultLoadout()
    if C_ClassTalents.GetStarterBuildActive and C_ClassTalents.GetStarterBuildActive() then
        return false
    end
    return self:GetCurrentLoadoutConfigID() == nil
end
