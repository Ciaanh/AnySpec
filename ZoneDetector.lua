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

-- Classify current zone into a category and return full zone info.
-- Returns: { category, instanceType, instanceID, difficultyID, instanceName } or nil
-- Helper: look up EJ dungeon ID by instance name
local function GetEJDungeonIDByName(instanceName)
    if not EJ_GetInstanceByIndex or not EJ_GetCurrentTier then return nil end
    
    local savedTier = EJ_GetCurrentTier()
    -- Check tiers 1-20 for the matching instance
    for tier = 1, 20 do
        EJ_SelectTier(tier)
        for i = 1, 999 do
            local id, name = EJ_GetInstanceByIndex(i, false)  -- false = dungeons
            if not id then break end
            if name and name == instanceName then
                EJ_SelectTier(savedTier)
                return id
            end
        end
    end
    EJ_SelectTier(savedTier)
    return nil
end

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

    -- Try to find the EJ dungeon ID by matching the instance name
    local ejDungeonID = GetEJDungeonIDByName(instName)
    local usedID = ejDungeonID or lfgDungeonID or instID

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
