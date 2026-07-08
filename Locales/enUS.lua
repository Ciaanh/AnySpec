-- AnySpec/Locales/enUS.lua
-- Default (English) locale strings.
-- Other locales should copy this file and translate the values.
-- Pattern: Each locale file populates the same shared AnySpec.L table.
-- This allows WoW to load all relevant locales, with locale guards in non-default files.

local L = AnySpec.L

-- ── General ───────────────────────────────────────────────────────────────────
L["ADDON_PREFIX"]               = "|cff00aaffAny|r|cffffffffSpec|r"

-- ── Quick Access (left panel drag buttons) ────────────────────────────────────
L["QUICKACCESS_TITLE"]          = "Quick Access"
L["QUICKACCESS_DESC"]           = "Drag to action bars to create macro shortcuts."
L["QUICKACCESS_DRAG_HINT"]      = "drag"
L["QUICKACCESS_SWITCH_NAME"]    = "Spec Selector"
L["QUICKACCESS_SWITCH_TIP"]     = "Opens a popup to choose any specialization."

-- ── Navigation (left panel links) ─────────────────────────────────────────────
L["NAV_TITLE"]                  = "Navigate"
L["NAV_LOCATIONS"]              = "> Instances"
L["NAV_CONTENT_TYPES"]          = "> Content Types"
L["NAV_SETTINGS"]               = "> Settings"

-- ── View titles ───────────────────────────────────────────────────────────────
L["VIEW_LOCATIONS"]             = "Instance Assignments"
L["VIEW_CONTENT_TYPES"]         = "Content Type Assignments"
L["VIEW_SETTINGS"]              = "Settings"

-- ── Content Types view ─────────────────────────────────────────────────────────
L["CONTENT_TYPES_DESC"]         = "Set a default spec for a whole content type, or override it per difficulty. Per-instance assignments take priority over these."
L["CAT_OPEN_WORLD"]             = "Open World"
L["CAT_DUNGEON"]                = "Dungeon"
L["CAT_MYTHIC_PLUS"]            = "Mythic+"
L["CAT_RAID"]                   = "Raid"
L["CAT_DELVE"]                  = "Delve"
L["CAT_PVP"]                    = "Battleground"
L["CAT_ARENA"]                  = "Arena"
L["DIFF_NORMAL"]                = "Normal"
L["DIFF_HEROIC"]                = "Heroic"
L["DIFF_MYTHIC"]                = "Mythic"
L["DIFF_LFR"]                   = "Raid Finder"

-- ── Instance list (right panel – Locations view) ──────────────────────────────
L["TAB_DUNGEONS"]               = "Dungeons"
L["TAB_RAIDS"]                  = "Raids"
L["TIER_DROPDOWN_DEFAULT"]      = "Expansion..."
L["INSTANCES_EMPTY"]            = "No instances for this combination."

-- ── Assignment dialog ─────────────────────────────────────────────────────────
L["DIALOG_ADD_PAIR"]            = "+ Add"
L["DIALOG_SPEC_PLACEHOLDER"]    = "Select spec…"
L["DIALOG_INSTANCE_FALLBACK"]   = "Instance"
L["ASSIGNMENT_NONE"]            = "|cff555555None|r"

-- ── Loadouts ──────────────────────────────────────────────────────────────────
L["LOADOUT_DEFAULT"]            = "Default loadout"

-- ── Settings view ─────────────────────────────────────────────────────────────
L["SETTINGS_TOAST_POSITION"]      = "Toast Position"
L["SETTINGS_TOAST_POSITION_DESC"] = "Choose where the spec+loadout proposal toast appears:"
L["SETTINGS_MINIMAP"]             = "Minimap button"
L["SETTINGS_AUTO_SWITCH"]         = "Enable auto-switch proposals"
L["SETTINGS_TEST_TOAST"]          = "Test Proposal Toast"

-- ── Toast position labels ─────────────────────────────────────────────────────
L["POS_TOP_CENTER"]             = "Top Center"
L["POS_CENTER"]                 = "Center"
L["POS_TOP_RIGHT"]              = "Top Right"
L["POS_BOTTOM_CENTER"]          = "Bottom Center"

-- ── Proposal toast ────────────────────────────────────────────────────────────
-- %s will be replaced by the key sequence, e.g. "1-2-3"
L["PROPOSAL_HINT"]              = "Press %s or click  ·  ESC to dismiss"
-- %s will be replaced by the spec/loadout label
L["PROPOSAL_SWITCHING"]         = "Switching to %s…"
L["PROPOSAL_SWITCH_FAILED"]     = "Spec switch failed."

-- ── Quick-switch popup ────────────────────────────────────────────────────────
L["QS_LOADOUT_LABEL"]           = "Loadout:"
L["QS_LOADOUT_UNSAVED"]         = "Unsaved"
L["QS_LOADOUT_SELECT"]          = "Select..."
L["QS_INTRO_TIP"]               = "Select a loadout (or keep current), then click the spec to switch (ESC to close)"
-- %s = loadout name, %s = spec name
L["QS_SELECTED_LOADOUT"]        = "AnySpec: Selected loadout '%s' for %s"
-- %s = spec name
L["QS_SWITCHING_WITH_LOADOUT"]  = "AnySpec: Switching to %s and applying selected loadout..."
L["QS_SWITCHING"]               = "AnySpec: Switching to %s"

-- ── Minimap button ────────────────────────────────────────────────────────────
L["MINIMAP_TOOLTIP"]            = "AnySpec"

-- ── Slash commands ────────────────────────────────────────────────────────────
L["CMD_HELP_HEADER"]            = "AnySpec commands:"
L["CMD_HELP_OPEN"]              = "  /anyspec           - Open settings"
L["CMD_HELP_SWITCH"]            = "  /anyspec switch    - Toggle quick-switch panel"
L["CMD_HELP_CONFIG"]            = "  /anyspec config    - Open settings"
L["CMD_HELP_HELP"]              = "  /anyspec help      - Show this help"
-- %s will be replaced by the unknown command string
L["CMD_ERR_UNKNOWN"]            = "AnySpec: Unknown command '%s'. Type /anyspec help for usage."

-- ── Error messages ────────────────────────────────────────────────────────────
L["ERR_COMBAT_MACRO"]           = "AnySpec: Cannot create macros during combat."
L["ERR_NO_MACRO_SLOT"]          = "AnySpec: No character macro slot available."
