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
    print("|cff00aaffAnySpec|r: DEBUG - SwitchSpec called: specIndex=" .. tostring(specIndex) .. ", loadoutID=" .. tostring(loadoutID))
    
    if InCombatLockdown() then
        print("|cff00aaffAnySpec|r: DEBUG - Cannot switch: in combat")
        return false, "Cannot switch specs in combat."
    end

    local canUse, failureReason = C_SpecializationInfo.CanPlayerUseTalentSpecUI()
    if not canUse then
        print("|cff00aaffAnySpec|r: DEBUG - Cannot use talent spec UI: " .. tostring(failureReason))
        return false, failureReason or "Spec UI unavailable."
    end

    local currentSpec = self:GetCurrentSpecIndex()
    print("|cff00aaffAnySpec|r: DEBUG - Current spec: " .. tostring(currentSpec) .. ", target spec: " .. tostring(specIndex))
    
    if currentSpec == specIndex then
        -- Already on this spec; apply loadout directly if provided
        print("|cff00aaffAnySpec|r: DEBUG - Already on target spec, applying loadout directly")
        if loadoutID then
            self:ApplyLoadout(loadoutID)
        else
            print("|cff00aaffAnySpec|r: DEBUG - No loadout to apply (already on spec)")
        end
        return true
    end

    print("|cff00aaffAnySpec|r: DEBUG - Switching spec, queuing loadout for after switch")
    pendingLoadoutID = loadoutID or nil
    C_SpecializationInfo.SetSpecialization(specIndex)
    return true
end

-- Apply a talent loadout by configID. Assumes current spec matches the loadout's spec.
function SM:ApplyLoadout(configID)
    print("|cff00aaffAnySpec|r: DEBUG - ApplyLoadout called: configID=" .. tostring(configID))
    
    if not configID then
        print("|cff00aaffAnySpec|r: DEBUG - No configID provided, aborting")
        return
    end

    local canChange, failureReason = C_ClassTalents.CanChangeTalents()
    print("|cff00aaffAnySpec|r: DEBUG - CanChangeTalents: " .. tostring(canChange) .. ", reason: " .. tostring(failureReason or "nil"))
    
    if not canChange then
        print("|cff00aaffAnySpec|r: Cannot change talents right now" .. (failureReason and (": " .. failureReason) or ""))
        
        -- Retry after a short delay if it's just a temporary restriction
        if not failureReason or failureReason == "" then
            print("|cff00aaffAnySpec|r: DEBUG - Retrying in 0.5 seconds...")
            C_Timer.After(0.5, function()
                SM:ApplyLoadout(configID)
            end)
        end
        return
    end

    -- Get current spec ID for UpdateLastSelectedSavedConfigID
    local currentSpec = self:GetCurrentSpecIndex()
    local spec = self:GetSpecInfo(currentSpec)
    if not spec then
        print("|cff00aaffAnySpec|r: ERROR - Could not get current spec info")
        return
    end
    local specID = spec.specID
    
    print("|cff00aaffAnySpec|r: DEBUG - Calling LoadConfig with configID=" .. tostring(configID) .. ", autoApply=true")
    local result = C_ClassTalents.LoadConfig(configID, true)
    print("|cff00aaffAnySpec|r: DEBUG - LoadConfig result: " .. tostring(result) .. " (0=Error, 1=NoChanges, 2=InProgress, 3=Ready)")
    
    -- result: 0=Error, 1=NoChangesNecessary, 2=LoadInProgress, 3=Ready
    if result == 1 then
        -- NoChangesNecessary - already active, but still update last selected
        print("|cff00aaffAnySpec|r: DEBUG - Loadout already active, updating last selected config ID")
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
        print("|cff00aaffAnySpec|r: Loadout already active")
        
    elseif result == 3 then
        -- Ready - needs commit
        print("|cff00aaffAnySpec|r: DEBUG - Config ready, committing...")
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
        C_ClassTalents.CommitConfig(configID)
        print("|cff00aaffAnySpec|r: Loadout applied successfully")
        
    elseif result == 2 then
        -- LoadInProgress - autoApply=true means system will auto-commit
        print("|cff00aaffAnySpec|r: DEBUG - Load in progress, system will auto-commit")
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
        print("|cff00aaffAnySpec|r: Loadout changes in progress...")
        
    elseif result == 0 then
        print("|cff00aaffAnySpec|r: ERROR - Failed to load loadout config")
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
