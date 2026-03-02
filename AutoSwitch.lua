-- AnySpec/AutoSwitch.lua
-- Assignment storage, zone→spec resolution, proposal triggering

AnySpec = AnySpec or {}
AnySpec.AutoSwitch = AnySpec.AutoSwitch or {}
local AS_MOD = AnySpec.AutoSwitch

-- Seconds before the same dismissed proposal can be reshown
local DISMISS_COOLDOWN = 60

local pendingZoneInfo = nil  -- zone info queued during combat

local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Left combat; show any queued proposal
        if pendingZoneInfo then
            local info = pendingZoneInfo
            pendingZoneInfo = nil
            AS_MOD:EvaluateAndPropose(info)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat; hide any active proposal
        AnySpec.UI.Proposal:Hide()
    end
end

eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", OnEvent)

function AS_MOD:Init()
    -- Nothing to init; db is set in Core.lua before Init() calls
end

function AS_MOD:OnPlayerLogin()
    -- Initial zone check is handled via ZoneDetector -> OnZoneChanged
end

-- Called by ZoneDetector whenever the zone changes
function AS_MOD:OnZoneChanged(zoneInfo)
    if not AnySpec.db or not AnySpec.db.proposalEnabled then 
        print("|cff00aaffAnySpec|r: DEBUG - Zone changed but proposals disabled")
        return 
    end

    print("|cff00aaffAnySpec|r: DEBUG - Zone changed: " .. tostring(zoneInfo.category))

    if InCombatLockdown() then
        print("|cff00aaffAnySpec|r: DEBUG - In combat, queueing zone change proposal")
        pendingZoneInfo = zoneInfo
        return
    end

    self:EvaluateAndPropose(zoneInfo)
end

-- Look up the assignment for the given zone using the resolution hierarchy.
-- Returns { specIndex = ..., loadoutID = ..., specs = { ... } } or nil
function AS_MOD:GetAssignment(zoneInfo)
    local charDB = AnySpec.charDB
    if not charDB then return nil end

    local instanceID = zoneInfo.instanceID
    local difficultyID = zoneInfo.difficultyID
    local category = zoneInfo.category

    print("|cff00aaffAnySpec|r: DEBUG - GetAssignment for zone: category=" .. tostring(category) 
        .. ", instanceID=" .. tostring(instanceID) .. ", difficultyID=" .. tostring(difficultyID))

    -- Most specific to least specific
    if instanceID and difficultyID then
        local key = instanceID .. ":" .. difficultyID
        if charDB.instanceDifficultyAssignments[key] then
            print("|cff00aaffAnySpec|r: DEBUG - Found instanceDiffi assignment for " .. key)
            return charDB.instanceDifficultyAssignments[key]
        end
    end

    if instanceID then
        local assignment = charDB.instanceAssignments[instanceID]
        if assignment then
            print("|cff00aaffAnySpec|r: DEBUG - Found instance assignment for " .. instanceID)
            -- Handle new multi-spec format: { specs = { 1, 2, 3 } }
            if assignment.specs then
                if #assignment.specs > 0 then
                    -- Return assignment with specIndex set to the first spec
                    return {
                        specIndex = assignment.specs[1],
                        loadoutID = assignment.loadoutID,
                        specs = assignment.specs,
                    }
                end
            elseif assignment.specIndex then
                -- Old single-spec format: { specIndex = ..., loadoutID = ... }
                return assignment
            end
        end
    end

    if category and difficultyID then
        local key = category .. ":" .. difficultyID
        if charDB.difficultyAssignments[key] then
            print("|cff00aaffAnySpec|r: DEBUG - Found categoryDifficulty assignment for " .. key)
            return charDB.difficultyAssignments[key]
        end
    end

    if category then
        if charDB.categoryAssignments[category] then
            print("|cff00aaffAnySpec|r: DEBUG - Found category assignment for " .. category)
            return charDB.categoryAssignments[category]
        end
    end

    print("|cff00aaffAnySpec|r: DEBUG - No assignment found")
    return nil
end

-- Save an assignment. level is one of: "category", "difficulty", "instance", "instanceDifficulty"
function AS_MOD:SetAssignment(level, key, specIndex, loadoutID)
    local charDB = AnySpec.charDB
    if not charDB then return end

    local entry = { specIndex = specIndex, loadoutID = loadoutID or nil }

    if level == "category" then
        charDB.categoryAssignments[key] = entry
    elseif level == "difficulty" then
        charDB.difficultyAssignments[key] = entry
    elseif level == "instance" then
        charDB.instanceAssignments[key] = entry
    elseif level == "instanceDifficulty" then
        charDB.instanceDifficultyAssignments[key] = entry
    end
end

function AS_MOD:ClearAssignment(level, key)
    local charDB = AnySpec.charDB
    if not charDB then return end

    if level == "category" then
        charDB.categoryAssignments[key] = nil
    elseif level == "difficulty" then
        charDB.difficultyAssignments[key] = nil
    elseif level == "instance" then
        charDB.instanceAssignments[key] = nil
    elseif level == "instanceDifficulty" then
        charDB.instanceDifficultyAssignments[key] = nil
    end
end

-- Evaluate whether a proposal should be shown for the current zone
function AS_MOD:EvaluateAndPropose(zoneInfo)
    local assignment = self:GetAssignment(zoneInfo)
    if not assignment then 
        print("|cff00aaffAnySpec|r: DEBUG - No assignment for zone, skipping proposal")
        return 
    end

    local currentSpec = AnySpec.SpecManager:GetCurrentSpecIndex()
    print("|cff00aaffAnySpec|r: DEBUG - Current spec=" .. currentSpec .. ", assignment spec=" .. assignment.specIndex)
    
    if currentSpec == assignment.specIndex then 
        print("|cff00aaffAnySpec|r: DEBUG - Already on assigned spec, skipping proposal")
        return 
    end

    -- Check dismiss cooldown
    local cooldownKey = self:GetDismissCooldownKey(zoneInfo, assignment.specIndex)
    local lastDismiss = AnySpec.charDB.dismissedProposals[cooldownKey]
    if lastDismiss and (GetTime() - lastDismiss) < DISMISS_COOLDOWN then 
        print("|cff00aaffAnySpec|r: DEBUG - Dismissed recently, still in cooldown")
        return 
    end

    print("|cff00aaffAnySpec|r: DEBUG - Showing proposal to switch to spec " .. assignment.specIndex)
    AnySpec.UI.Proposal:Show(assignment, zoneInfo)
end

function AS_MOD:GetDismissCooldownKey(zoneInfo, specIndex)
    return (zoneInfo.category or "unknown") .. ":" .. (zoneInfo.instanceID or "0")
        .. ":" .. (zoneInfo.difficultyID or "0") .. ":" .. specIndex
end

-- Called by Proposal UI when the user dismisses the toast
function AS_MOD:OnProposalDismissed(zoneInfo, specIndex)
    local key = self:GetDismissCooldownKey(zoneInfo, specIndex)
    AnySpec.charDB.dismissedProposals[key] = GetTime()
end
