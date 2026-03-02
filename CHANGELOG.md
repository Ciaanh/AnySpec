# Changelog

All notable changes to AnySpec will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-03

### Added
- Initial release of AnySpec addon
- Minimap button for quick access (draggable, left-click for settings, right-click for spec selector)
- Spec selector popup showing all available specializations
- Draggable quick-access buttons (Plumber-style) for creating action bar macros
- Content-based spec assignments:
  - Per-category assignments (Open World, Dungeon, Mythic+, Raid, PvP, Arena, Delve)
  - Per-instance assignments
  - Per-difficulty assignments
  - Combined instance+difficulty assignments
- Smart assignment resolution (most specific match wins)
- Loadout support - pair spec switches with talent loadout configurations
- Auto-switch proposal toasts when entering content with configured assignments
- Proposal suppression during combat (queued for out-of-combat)
- Temporary proposal dismissal (60-second cooldown)
- Localization system with English (enUS) as default
- Slash commands: `/anyspec`, `/anyspec switch`, `/anyspec config`, `/anyspec help`
- Account-wide settings (AnySpecDB) and per-character assignments (AnySpecCharDB)

### Fixed
- Locale table initialization error when loading localization files via XML

[0.1.0]: https://github.com/Ciaanh/AnySpec/releases/tag/v0.1.0
