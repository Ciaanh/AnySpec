# AnySpec

A World of Warcraft (Retail) addon that automates talent specialization and loadout management based on the content you enter, with quick-switch buttons and smart proposal toasts.

## Features

- **Minimap Button** — Left-click opens the settings panel; right-click toggles the spec selector popup. Draggable around the minimap edge.
- **Quick Spec Switching** — A spec selector popup with all your specs listed. Individual per-spec buttons can be dragged from the config panel to action bars for one-click switching (Plumber-style macro drag).
- **Content-Based Assignments** — Assign a preferred spec per content category (Open World, Dungeon, Mythic+, Raid, PvP, Arena, Delve) directly in the configuration panel. The most specific match always wins.
- **Auto-Switch Proposals** — When you enter content that has a configured assignment, a toast notification asks if you'd like to switch. Proposals are suppressed in combat and queued until you're out.
- **Loadout Support** — Spec switches can be paired with a talent loadout that applies automatically once the specialization change completes.

## Installation

1. Download or clone this repository.
2. Copy the `AnySpec` folder to your addons directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\AnySpec
   ```
3. Launch World of Warcraft and enable **AnySpec** in the AddOns list on the character select screen.

## Usage

### Minimap Button

- **Left-click** — Open the settings/configuration panel.
- **Right-click** — Toggle the spec selector popup.
- **Drag** — Reposition around the minimap.

### Slash Commands

```
/anyspec             Open the settings panel
/anyspec switch      Toggle the spec selector popup
/anyspec config      Open the settings panel
/anyspec help        Show available commands
```

### Action Bar Buttons

Open the settings panel (`/anyspec`) and look at the **Quick Access Buttons** section. You can drag any of these to your action bars:

- **Spec Selector** — Opens the spec selector popup (`/click ANYSPEC_SWITCH`).
- **Per-spec buttons** — Directly switch to a specific spec (`/click ANYSPEC_SPEC1`, etc.).

### Configuring Assignments

In the settings panel under **Content Assignments**, select a spec for each content type using the dropdown. The resolution order from most to least specific is:

1. Instance + Difficulty (e.g. Nerub-ar Palace — Mythic)
2. Instance (any difficulty)
3. Category + Difficulty (e.g. Raid — Heroic)
4. Category (e.g. Raid)

### Proposal Toasts

When you zone into content with an assignment that differs from your current spec, a toast will appear asking you to confirm the switch. You can:

- **Accept** — switches spec (and applies the linked loadout if set).
- **Dismiss** — suppresses the same proposal for 60 seconds.

Proposals are automatically hidden when you enter combat and re-evaluated when you leave combat.

## Saved Variables

| Variable | Scope | Contents |
|---|---|---|
| `AnySpecDB` | Account-wide | Global settings (proposal timeout, sounds, minimap button) |
| `AnySpecCharDB` | Per-character | Spec/loadout assignments, dismissed proposals |

## Project Structure

```
AnySpec/
├── AnySpec.toc           # Addon manifest
├── Core.lua              # Initialization, events, slash commands, saved variables
├── SpecManager.lua       # Spec/loadout switching logic and API wrappers
├── ZoneDetector.lua      # Zone/instance/difficulty detection
├── AutoSwitch.lua        # Assignment storage, resolution hierarchy, proposal triggering
└── UI/
    ├── MinimapButton.lua # Minimap button (opens config / spec selector)
    ├── QuickSwitch.lua   # Spec selector popup + hidden ANYSPEC_SWITCH click handler
    ├── SpecButtons.lua   # Per-spec click handlers (ANYSPEC_SPEC1..4)
    ├── Proposal.lua      # Auto-switch proposal toast
    └── Config.lua        # Settings panel with drag buttons and assignment UI
```

## Requirements

- World of Warcraft Retail (Interface version 120001+)

## License

See [LICENSE](LICENSE).
