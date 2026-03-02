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

-- Called by ZoneDetector whenever the zone changes.
function AS_MOD:OnZoneChanged(zoneInfo)
    print("|cff00aaffAnySpec|r [AutoSwitch] OnZoneChanged: " .. tostring(zoneInfo.instanceID) .. " (" .. tostring(zoneInfo.category) .. ")")
    if not AnySpec.db or not AnySpec.db.proposalEnabled then
        print("|cff00aaffAnySpec|r [AutoSwitch] proposal disabled or db not ready")
        return
    end

    if InCombatLockdown() then
        print("|cff00aaffAnySpec|r [AutoSwitch] in combat, queueing zone info")
        pendingZoneInfo = zoneInfo
        return
    end

    self:EvaluateAndPropose(zoneInfo)
end

-- Look up the assignment for the given zone using the resolution hierarchy.
-- Returns an array of { specIndex, loadoutID } pairs, or nil when nothing is configured.
-- Category/difficulty assignments are wrapped in a single-element array for consistency.
function AS_MOD:GetAssignment(zoneInfo)
    local charDB = AnySpec.charDB
    if not charDB then
        print("|cff00aaffAnySpec|r [AutoSwitch] GetAssignment: charDB not ready")
        return nil
    end

    local instanceID   = zoneInfo.instanceID
    local difficultyID = zoneInfo.difficultyID
    local category     = zoneInfo.category
    print("|cff00aaffAnySpec|r [AutoSwitch] GetAssignment: instanceID=" .. tostring(instanceID) .. ", difficultyID=" .. tostring(difficultyID) .. ", category=" .. tostring(category))

    -- Most specific: per-instance + per-difficulty
    if instanceID and difficultyID then
        local key = instanceID .. ":" .. difficultyID
        local a = charDB.instanceDifficultyAssignments[key]
        print("|cff00aaffAnySpec|r [AutoSwitch] checking instanceDifficulty[" .. key .. "]: " .. tostring(a))
        if a then
            return (type(a[1]) == "table") and a or { a }
        end
    end

    -- Per-instance (array of {specIndex, loadoutID} pairs)
    if instanceID then
        local a = charDB.instanceAssignments[instanceID]
        print("|cff00aaffAnySpec|r [AutoSwitch] checking instance[" .. tostring(instanceID) .. "]: " .. tostring(a))
        if a and #a > 0 then
            return a
        end
    end

    -- Per-category + difficulty
    if category and difficultyID then
        local key = category .. ":" .. difficultyID
        local a = charDB.difficultyAssignments[key]
        print("|cff00aaffAnySpec|r [AutoSwitch] checking categoryDifficulty[" .. key .. "]: " .. tostring(a))
        if a then
            return (type(a[1]) == "table") and a or { a }
        end
    end

    -- Per-category fallback
    if category then
        local a = charDB.categoryAssignments[category]
        print("|cff00aaffAnySpec|r [AutoSwitch] checking category[" .. tostring(category) .. "]: " .. tostring(a))
        if a then
            return (type(a[1]) == "table") and a or { a }
        end
    end

    print("|cff00aaffAnySpec|r [AutoSwitch] GetAssignment: no matches found")
    return nil
end

-- Save instance assignments.
-- pairs is an array of { specIndex, loadoutID }; pass nil or {} to clear.
function AS_MOD:SetInstanceAssignment(instanceID, pairs)
    local charDB = AnySpec.charDB
    if not charDB then return end
    if not pairs or #pairs == 0 then
        charDB.instanceAssignments[instanceID] = nil
    else
        charDB.instanceAssignments[instanceID] = pairs
    end
end

function AS_MOD:ClearInstanceAssignment(instanceID)
    local charDB = AnySpec.charDB
    if not charDB then return end
    charDB.instanceAssignments[instanceID] = nil
end

-- Evaluate whether a proposal should be shown for the current zone.
function AS_MOD:EvaluateAndPropose(zoneInfo)
    local assignments = self:GetAssignment(zoneInfo)
    print("|cff00aaffAnySpec|r [AutoSwitch] EvaluateAndPropose: assignments=" .. tostring(assignments) .. ", count=" .. (assignments and #assignments or "nil"))
    if not assignments or #assignments == 0 then
        print("|cff00aaffAnySpec|r [AutoSwitch] no assignments found, returning")
        return
    end

    local currentSpec      = AnySpec.SpecManager:GetCurrentSpecIndex()
    local currentLoadoutID = AnySpec.SpecManager:GetCurrentLoadoutConfigID()
    print("|cff00aaffAnySpec|r [AutoSwitch] current spec=" .. tostring(currentSpec) .. ", currentLoadoutID=" .. tostring(currentLoadoutID))

    -- Single assignment: skip entirely if already on the correct spec+loadout.
    if #assignments == 1 then
        local a = assignments[1]
        print("|cff00aaffAnySpec|r [AutoSwitch] single assignment: spec=" .. tostring(a.specIndex) .. ", loadout=" .. tostring(a.loadoutID))
        if currentSpec == a.specIndex then
            if not a.loadoutID or a.loadoutID == currentLoadoutID then
                print("|cff00aaffAnySpec|r [AutoSwitch] already on correct spec+loadout, skipping proposal")
                return
            end
            -- Wrong loadout — still worth proposing.
        end
    end
    -- Multiple assignments: always show so the player can pick.

    -- Check dismiss cooldown (per zone entry, not per spec).
    local cooldownKey = self:GetDismissCooldownKey(zoneInfo)
    local lastDismiss = AnySpec.charDB.dismissedProposals[cooldownKey]
    local cooldownRemaining = lastDismiss and (DISMISS_COOLDOWN - (GetTime() - lastDismiss)) or 0
    print("|cff00aaffAnySpec|r [AutoSwitch] cooldown key=" .. cooldownKey .. ", remaining=" .. tostring(cooldownRemaining))
    if lastDismiss and (GetTime() - lastDismiss) < DISMISS_COOLDOWN then
        print("|cff00aaffAnySpec|r [AutoSwitch] proposal on cooldown, skipping")
        return
    end

    print("|cff00aaffAnySpec|r [AutoSwitch] showing proposal toast")
    AnySpec.UI.Proposal:Show(assignments, zoneInfo)
end

-- Cooldown key: per zone entry (no per-spec component).
function AS_MOD:GetDismissCooldownKey(zoneInfo)
    return (zoneInfo.category or "unknown") .. ":"
        .. (zoneInfo.instanceID  or "0") .. ":"
        .. (zoneInfo.difficultyID or "0")
end

-- Called by Proposal UI when the user explicitly dismisses (ESC / outside click).
-- NOT called on timeout — timeout does not set a cooldown.
function AS_MOD:OnProposalDismissed(zoneInfo)
    local key = self:GetDismissCooldownKey(zoneInfo)
    AnySpec.charDB.dismissedProposals[key] = GetTime()
end
