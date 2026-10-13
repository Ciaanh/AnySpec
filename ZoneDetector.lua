-- AnySpec/ZoneDetector.lua
-- Zone and instance detection, content category classification

AnySpec = AnySpec or {}
AnySpec.ZoneDetector = AnySpec.ZoneDetector or {}
local ZD = AnySpec.ZoneDetector

-- Category constants
ZD.CATEGORY = {
    OPEN_WORLD  = "open_world",
    DUNGEON     = "dungeon",
    MYTHIC_PLUS = "mythic_plus",
    RAID        = "raid",
    PVP         = "pvp",
    ARENA       = "arena",
    DELVE       = "delve",
}

-- Difficulty IDs
local DIFFICULTY_MYTHIC_KEYSTONE = 8

local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        ZD:OnZoneChanged()
    end
end

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", OnEvent)

function ZD:Init()
    -- Nothing to init; event frame handles updates
end

function ZD:OnPlayerLogin()
    self:OnZoneChanged()
end

------------------------------------------------------------
-- EJ instance-ID resolution
--
-- The config UI (UI/MainFrame.lua) keys assignments by Encounter Journal
-- instance ID. At runtime GetInstanceInfo() returns a different ID, so we
-- bridge the two by instance name. The lookup covers BOTH dungeons and raids,
-- and the name→ID map is built once and cached — rebuilding it on every zone
-- change (20 tiers × up to 999 instances) would be far too expensive.
------------------------------------------------------------
local ejNameToID = nil  -- lazily-built { [instanceName] = ejInstanceID }

local function EnsureEJLoaded()
    if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end
end

-- Build { [instanceName] = ejInstanceID } across all tiers, dungeons and raids.
local function BuildEJNameCache()
    if not EJ_GetInstanceByIndex or not EJ_GetNumTiers then return {} end
    EnsureEJLoaded()

    local cache = {}
    local savedTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or nil
    for tier = 1, EJ_GetNumTiers() do
        EJ_SelectTier(tier)
        for _, isRaid in ipairs({ false, true }) do  -- false = dungeons, true = raids
            for i = 1, 999 do
                local id, name = EJ_GetInstanceByIndex(i, isRaid)
                if not id then break end
                if name and name ~= "" then
                    cache[name] = id
                end
            end
        end
    end
    if savedTier then EJ_SelectTier(savedTier) end
    return cache
end

-- Resolve an instance name to its EJ instance ID, building the cache on first use.
local function GetEJInstanceIDByName(instanceName)
    if not instanceName then return nil end
    if not ejNameToID then
        local cache = BuildEJNameCache()
        if next(cache) == nil then
            -- EJ data not ready yet; leave uncached so we retry on the next zone change.
            return nil
        end
        ejNameToID = cache
    end
    return ejNameToID[instanceName]
end

-- Classify current zone into a category and return full zone info.
-- Returns: { category, instanceType, instanceID, difficultyID, instanceName } or nil
function ZD:GetCurrentZoneInfo()
    local inInstance, instanceType = IsInInstance()

    if not inInstance then
        return {
            category = self.CATEGORY.OPEN_WORLD,
            instanceType = "none",
            instanceID = nil,
            difficultyID = nil,
            instanceName = GetRealZoneText(),
        }
    end

    -- GetInstanceInfo returns: name, type, difficultyID, difficultyName, maxPlayers,
    --   dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, lfgDungeonID
    local instName, instType, instDiff, _, _, _, _, instID, _, lfgDungeonID = GetInstanceInfo()

    local category = self:ClassifyInstance(instType, instDiff)

    -- Resolve the EJ instance ID (dungeons and raids) so it matches the config's key space.
    local ejInstanceID = GetEJInstanceIDByName(instName)
    local usedID = ejInstanceID or lfgDungeonID or instID

    return {
        category = category,
        instanceType = instType,
        instanceID = usedID,
        difficultyID = instDiff,
        instanceName = instName,
    }
end

-- Map instanceType + difficultyID to a content category key
function ZD:ClassifyInstance(instanceType, difficultyID)
    if instanceType == "party" then
        if difficultyID == DIFFICULTY_MYTHIC_KEYSTONE then
            return self.CATEGORY.MYTHIC_PLUS
        else
            return self.CATEGORY.DUNGEON
        end
    elseif instanceType == "raid" then
        return self.CATEGORY.RAID
    elseif instanceType == "pvp" then
        return self.CATEGORY.PVP
    elseif instanceType == "arena" then
        return self.CATEGORY.ARENA
    elseif instanceType == "scenario" then
        return self.CATEGORY.DELVE
    else
        return self.CATEGORY.OPEN_WORLD
    end
end

-- Called whenever the zone changes; notifies AutoSwitch
function ZD:OnZoneChanged()
    local zoneInfo = self:GetCurrentZoneInfo()

    if zoneInfo then
        AnySpec.AutoSwitch:OnZoneChanged(zoneInfo)
    end
end
