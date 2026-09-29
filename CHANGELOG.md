# Changelog

All notable changes to AnySpec will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Modern flat UI: dark surfaces, 1px borders and a class-colored accent across every window (new `UI/Theme.lua`)
- Settings window: sidebar navigation, current spec + loadout in the header, Dungeons/Raids toggle, instance filter
- Content assignments are edited inline in the instance list instead of a separate dialog; assigned specs show as chips
- Settings view uses switches and a visual toast-position picker
- Spec selector and proposal toast restyled (active badge, number badges, countdown in seconds)
- The saved toast position is now applied at login instead of only after opening the settings window

## [0.1.0] - 2026-03-03

### Added
- Initial release of AnySpec addon
- Minimap button for quick access (draggable, left-click for settings, right-click for spec selector)
- Spec selector popup showing all available specializations
- Draggable quick-access Spec Selector button for creating an action bar macro
- Content-based spec assignments
- Loadout support - pair spec switches with talent loadout configurations
- Auto-switch proposal toasts when entering content with configured assignments
- Temporary proposal dismissal (8-second cooldown)
- Localization system with English (enUS) as default
- Slash commands: `/anyspec`, `/anyspec switch`, `/anyspec config`, `/anyspec help`
- Account-wide settings (AnySpecDB) and per-character assignments (AnySpecCharDB)

[0.1.0]: https://github.com/Ciaanh/AnySpec/releases/tag/v0.1.0
