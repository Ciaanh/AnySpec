-- AnySpec/Core.lua
-- Initialization, event frame, saved variables, slash commands

AnySpec = AnySpec or {}
local AS = AnySpec

-- Saved variable defaults
local DB_DEFAULTS = {
    version = 1,
    proposalEnabled = true,
    minimapButton = true,
    minimapButtonAngle = 2.5,
    framePosition = nil,
}

local CHAR_DB_DEFAULTS = {
    version = 1,
    categoryAssignments = {},
    difficultyAssignments = {},
    instanceAssignments = {},
    instanceDifficultyAssignments = {},
    quickSwitchPosition = { x = 0, y = 0 },
    dismissedProposals = {},
}

-- Initialize saved variables, merging defaults for missing keys
local function InitDB(saved, defaults)
    if type(saved) ~= "table" then
        return CopyTable(defaults)
    end
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            if type(v) == "table" then
                saved[k] = CopyTable(v)
            else
                saved[k] = v
            end
        end
    end
    return saved
end

-- Event frame
local eventFrame = CreateFrame("Frame", "AnySpecEventFrame")

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= "AnySpec" then return end

        AnySpecDB = InitDB(AnySpecDB, DB_DEFAULTS)
        AnySpecCharDB = InitDB(AnySpecCharDB, CHAR_DB_DEFAULTS)

        AS.db = AnySpecDB
        AS.charDB = AnySpecCharDB

        self:UnregisterEvent("ADDON_LOADED")

        -- Notify modules that the addon is loaded
        AS.SpecManager:Init()
        AS.ZoneDetector:Init()
        AS.AutoSwitch:Init()
        AS.UI.MainFrame:Init()
        AS.UI.SpecButtons:Init()
        AS.UI.QuickSwitch:Init()
        AS.UI.Proposal:Init()
        AS.UI.Config:Init()

    elseif event == "PLAYER_LOGIN" then
        -- Safe point: all saved variables loaded, player data available
        AS.ZoneDetector:OnPlayerLogin()
        AS.AutoSwitch:OnPlayerLogin()
        AS.UI.MinimapButton:Init()  -- Now spec info is available
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", OnEvent)

-- Slash commands
SLASH_ANYSPEC1 = "/anyspec"
SLASH_ANYSPEC2 = "/as"

SlashCmdList["ANYSPEC"] = function(msg)
    local cmd = msg and strtrim(msg:lower()) or ""

    if cmd == "" or cmd == "config" or cmd == "options" or cmd == "settings" then
        AS.UI.MainFrame:Toggle()
    elseif cmd == "switch" then
        AS.UI.QuickSwitch:Toggle()
    elseif cmd == "help" then
        print("|cff00aaffAnySpec|r commands:")
        print("  /anyspec           - Open settings")
        print("  /anyspec switch    - Toggle quick-switch panel")
        print("  /anyspec config    - Open settings")
        print("  /anyspec help      - Show this help")
    else
        print("|cff00aaffAnySpec|r: Unknown command '" .. cmd .. "'. Type /anyspec help for usage.")
    end
end
