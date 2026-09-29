-- AnySpec/Locales/enUS.lua
-- Default (English) locale strings.
-- Other locales should copy this file and translate the values.
-- Pattern: Each locale file populates the same shared AnySpec.L table.
-- This allows WoW to load all relevant locales, with locale guards in non-default files.

local L = AnySpec.L

-- ── General ───────────────────────────────────────────────────────────────────
L["ADDON_PREFIX"]               = "|cff00aaffAny|r|cffffffffSpec|r"

-- ── Quick Access (left panel drag buttons) ────────────────────────────────────
L["QUICKACCESS_TITLE"]          = "Quick access"
L["QUICKACCESS_DESC"]           = "Drag to an action bar"
L["QUICKACCESS_SWITCH_NAME"]    = "Spec Selector"
L["QUICKACCESS_SWITCH_TIP"]     = "Opens a popup to choose any specialization."

-- ── Navigation (left panel links) ─────────────────────────────────────────────
L["NAV_LOCATIONS"]              = "Assignments"
L["NAV_SETTINGS"]               = "Settings"

-- ── View titles ───────────────────────────────────────────────────────────────
L["VIEW_LOCATIONS"]             = "Content assignments"
L["VIEW_LOCATIONS_DESC"]        = "Choose which specs AnySpec offers when you zone in."
L["VIEW_SETTINGS"]              = "Settings"
L["VIEW_SETTINGS_DESC"]         = "Saved for your whole account."

-- ── Instance list (right panel – Locations view) ──────────────────────────────
L["TAB_DUNGEONS"]               = "Dungeons"
L["TAB_RAIDS"]                  = "Raids"
L["TIER_DROPDOWN_DEFAULT"]      = "Expansion..."
L["INSTANCES_EMPTY"]            = "No instances for this combination."
L["SEARCH_PLACEHOLDER"]         = "Filter instances"
L["ASSIGN_BUTTON"]              = "Assign"

-- ── Inline assignment editor ──────────────────────────────────────────────────
L["DIALOG_ADD_PAIR"]            = "Add spec"
L["DIALOG_SPEC_PLACEHOLDER"]    = "Select spec…"
L["EDITOR_ADD_LIMIT"]           = "(up to 3)"
L["EDITOR_HINT"]                = "Offered in this order. Press the number on the toast to pick."
L["EDITOR_REMOVE"]              = "Remove"

-- ── Loadouts ──────────────────────────────────────────────────────────────────
L["LOADOUT_DEFAULT"]            = "Default loadout"

-- ── Settings view ─────────────────────────────────────────────────────────────
L["SETTINGS_TOAST_POSITION"]      = "Toast Position"
L["SETTINGS_TOAST_POSITION_DESC"] = "Where the proposal appears on screen."
L["SETTINGS_MINIMAP"]             = "Minimap button"
L["SETTINGS_MINIMAP_DESC"]        = "Left-click opens this window, right-click opens the spec selector."
L["SETTINGS_AUTO_SWITCH"]         = "Auto-switch proposals"
L["SETTINGS_AUTO_SWITCH_DESC"]    = "Show a toast when you enter content that has an assignment."
L["SETTINGS_TEST_TOAST"]          = "Preview toast"

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
-- %s will be replaced by the current spec name
L["PROPOSAL_SUBTITLE"]          = "You're %s. Switch for this instance?"
L["PROPOSAL_CURRENT"]           = "Current"

-- ── Quick-switch popup ────────────────────────────────────────────────────────
L["QS_TITLE"]                   = "Switch specialization"
L["QS_ACTIVE"]                  = "Active"
L["QS_LOADOUT_UNSAVED"]         = "Unsaved"
L["QS_LOADOUT_SELECT"]          = "Select..."
L["QS_INTRO_TIP"]               = "Pick a loadout, then click a spec"
L["QS_UNSAVED_TIP"]             = "Current talents are not saved as a loadout."
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
