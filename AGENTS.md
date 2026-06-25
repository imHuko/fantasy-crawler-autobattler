# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

**Gear Crawler** is a Godot 4.6 fantasy strategy game combining world-map conquest, gear management, auto-battler tower defense, and a player-controlled survival arena. Written entirely in GDScript; no build step or compilation required.

## Running the Game

Open `project.godot` in the Godot 4.6 editor and press **F5** (or Run → Run Project). To run a specific scene directly, open it and press **F6**.

There are no tests, linter, or CI commands. Validation is done by running the game in the editor.

## Architecture

### Autoloads (globals, always available)

| Singleton | File | Purpose |
|---|---|---|
| `PlayerInventory` | `autoloads/player_inventory.gd` | All persistent game state: gear inventory, troop roster, resources, map state, tutorial progress, settings |
| `GearGenerator` | `autoloads/gear_generator.gd` | Procedural gear creation — rarity rolls, stat rolls, quality tiers, set names |
| `SaveManager` | `autoloads/save_manager.gd` | JSON save/load (`user://savegame.json`), new-game setup, recruit generation |
| `TutorialOverlay` | `autoloads/tutorial_overlay.gd` | Renders the tutorial overlay UI |
| `TutorialRouter` | `autoloads/tutorial_router.gd` | Advances tutorial steps, resolves `resolve_current_step(scene)` calls |
| `AdminPanel` | `autoloads/admin_panel.gd` | Debug/cheat panel |

`TutorialSteps` (not an autoload — loaded by `TutorialRouter`) holds all step content separately from the progress tracker in `PlayerInventory`.

### Core Resources

- **`GearItem`** (`resources/gear_item.gd`) — `Rarity` (COMMON→LEGENDARY), `Slot` (WEAPON/ARMOR/RING/ACCESSORY), `Quality` (NORMAL/AWAKENED/ASCENDANT/TRANSCENDENT), `upgrade_level` (0–6). Call `get_effective_stats()` (not `stats` directly) to include the upgrade bonus.
- **`TroopData`** (`resources/troop_data.gd`) — `TroopType` enum (KNIGHT/ARCHER/MAGE/HEALER/ROGUE), `equipped_gear` dict, persistent `current_hp`. Call `get_effective_stats()` to include gear and talent bonuses.

### Scene Flow

```
main_menu → new_game_screen → (management_screen ↔ world_map)
                                     │
              ┌──────────────────────┼──────────────────────┐
        dungeon_picker          recruit_screen          talent_tree_screen
              │                                         gear_shop_screen
        ┌─────┴──────┐
  defense_scene   action_dungeon
```

- **`management_screen`** — equip/swap gear on troops; drag-and-drop via `DraggableGearButton` / `DroppableSlotButton`. All UI is code-built in `_build_ui()` — no scene-tree nodes are set up in the `.tscn`.
- **`world_map`** — procedural zone conquest; real-time troop marching and attack rolls. Zone data lives in `PlayerInventory.map_zones` (array of dicts with `id, name, type, pos, owner, troops, buildings, connections`). Transitions to `defense_scene` or `dungeon_picker_screen`.
- **`defense_scene`** — auto-battler wave defense. Player places troops; enemies walk right-to-left. Zone context is set in `PlayerInventory` by world_map before scene change.
- **`action_dungeon`** — survival arena. Player controls the Commander directly. Commander is **not** a `TroopData` roster slot — it's a separate entity with class profiles defined in `CLASS_PROFILES`.

### Commander vs. Troops

The Commander is separate from the troop roster:
- `PlayerInventory.commander_class` stores the current class (string: `"ARCHER"`, `"MAGE"`, etc.)
- The Commander appears only in `action_dungeon`, never in `defense_scene`
- Gear is equipped on `TroopData` roster members only; the Commander has no gear slots
- Save/load strips any legacy `is_hero` troop entries (prior architecture artifact)

### Economy

- **Resources**: `food` + `gold` are interchangeable — always check/spend via `PlayerInventory.can_afford()` and `spend_resources()`, never read the sub-dicts directly.
- **Salvage**: rarity-keyed (`COMMON/RARE/EPIC/LEGENDARY`), NOT interchangeable with food/gold. Used only for gear upgrades, always matching the item's own rarity.

### UI Convention

Most screens build their entire UI in code inside `_build_ui()` rather than using scene-tree nodes. Don't expect `@onready` variables to point at pre-existing nodes — they get assigned inside `_build_ui()`. When the tutorial needs a stable node reference, it's stored as a `var` on the scene script and handed to `TutorialRouter`.

### `godot_ai/` Plugin

The `addons/godot_ai/` directory is an MCP plugin for editor AI integration. It registers itself as an editor plugin and injects `_mcp_game_helper` as a runtime autoload. Do not edit files in this directory.
