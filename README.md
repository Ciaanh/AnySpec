# AnySpec

A World of Warcraft addon that automates talent specialization and loadout management based on the content you enter, with quick-switch buttons and smart proposal toasts.

## Features

- **Minimap Button** — Left-click opens the settings panel; right-click toggles the spec selector popup. Draggable around the minimap edge.
- **Quick Spec Switching** — A spec selector popup with all your specs listed, plus a draggable **Spec Selector** quick-access button you can place on your action bars.
- **Per-Instance Assignments** — Assign a preferred spec (and optional loadout) to individual dungeons and raids, browsed by expansion, directly in the configuration panel.
- **Content-Type Assignments** — Set a default spec per content type (Open World, Dungeon, Mythic+, Raid, Delve, Battleground, Arena), with optional per-difficulty overrides (e.g. Heroic vs Mythic raid). Per-instance assignments take priority over these.
- **Auto-Switch Proposals** — When you enter content that has a configured assignment, a toast notification asks if you'd like to switch.
- **Loadout Support** — Spec switches can be paired with a talent loadout that applies automatically once the specialization change completes.

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

`/as` is a short alias for `/anyspec` (e.g. `/as switch`).

### Action Bar Buttons

Open the settings panel (`/anyspec`) and look at the **Quick Access Buttons** section. You can drag this button to your action bars:

- **Spec Selector** — Opens the spec selector popup (`/click ANYSPEC_SWITCH`).

### Configuring Assignments

The settings panel offers two levels of assignment, chosen from the left navigation:

- **Instances** — pick the **Dungeons** or **Raids** tab and use the expansion dropdown to browse instances. Click an instance's row to open its inline editor and assign one or more spec (+ optional loadout) pairs to it.
- **Content types** — set a default spec per content type, and optionally override it per difficulty. These apply whenever a matching instance has no per-instance assignment of its own.

In either case the inline editor lets you add up to three spec/loadout pairs; if you configure more than one, the proposal toast lets you choose between them on entry.

### Proposal Toasts

When you zone into content with an assignment that differs from your current spec, a toast will appear asking you to confirm the switch. You can:

- **Accept** — switches spec (and applies the linked loadout if set).
- **Dismiss** — suppresses the same proposal for 60 seconds.

Proposals are automatically hidden after a short period of time if nothing is selected.

## Saved Variables

| Variable        | Scope         | Contents                                                   |
| --------------- | ------------- | ---------------------------------------------------------- |
| `AnySpecDB`     | Account-wide  | Global settings (auto-switch toggle, toast position, minimap button) |
| `AnySpecCharDB` | Per-character | Spec/loadout assignments, dismissed proposals              |

## License

See [LICENSE](LICENSE).
