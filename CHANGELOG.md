# Changelog

All notable changes to AnySpec will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Content-type assignments: set a default spec/loadout per content type (Open World, Dungeon, Mythic+, Raid, Delve, Battleground, Arena) with optional per-difficulty overrides, in a new "Content types" view. Per-instance assignments still take priority.

### Changed
- Modern flat UI: dark surfaces, 1px borders and a class-colored accent across every window (new `UI/Theme.lua`)
- Settings window: sidebar navigation, current spec + loadout in the header, Dungeons/Raids toggle, instance filter
- Content assignments are edited inline in the instance list instead of a separate dialog; assigned specs show as chips
- Settings view uses switches and a visual toast-position picker
- Spec selector and proposal toast restyled (active badge, number badges, countdown in seconds)
- The saved toast position is now applied at login instead of only after opening the settings window
- Instance list, proposal toast, and quick-switch rows are pooled and reused to avoid leaking UI frames over a session.

### Fixed
- Auto-switch proposals now match raids (not only dungeons) and resolve the current instance reliably; the Encounter Journal lookup is cached instead of rescanned on every zone change.
- Quick-switch now reports spec-switch failures (e.g. in combat) instead of failing silently.

## [0.1.0] - 2026-03-03

### Added
- Initial release of AnySpec addon
- Minimap button for quick access (draggable, left-click for settings, right-click for spec selector)
- Spec selector popup showing all available specializations
- Draggable quick-access Spec Selector button for creating an action bar macro
- Content-based spec assignments
- Loadout support - pair spec switches with talent loadout configurations
- Auto-switch proposal toasts when entering content with configured assignments
- Auto-switch proposal toasts auto-hide after 8 seconds; explicit dismissal suppresses the same proposal for 60 seconds
- Localization system with English (enUS) as default
- Slash commands: `/anyspec`, `/anyspec switch`, `/anyspec config`, `/anyspec help`
- Account-wide settings (AnySpecDB) and per-character assignments (AnySpecCharDB)

[0.1.0]: https://github.com/Ciaanh/AnySpec/releases/tag/v0.1.0
