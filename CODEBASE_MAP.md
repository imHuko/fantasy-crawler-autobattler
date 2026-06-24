# Gear Crawler — Codebase Map

Companion to `CLAUDE.md`. That file covers architecture concepts; this file covers **where things physically live and how they connect**. Start here when you need to find something fast.

---

## Project Root Layout

```
fantasy-crawler-autobattler/
├── project.godot               # Godot 4.6 project config — lists autoloads, main scene
├── CLAUDE.md                   # Architecture + concepts guide (read first)
├── CODEBASE_MAP.md             # This file
│
├── autoloads/                  # Godot singletons — always in scope, no import needed
├── resources/                  # Shared GDScript resource classes (class_name'd)
├── scenes/                     # Scene scripts + .tscn files
│
├── settings_screen.gd          # ⚠ ROOT LEVEL — not in scenes/. Script for settings_screen.tscn
├── recruit_screen.gd           # ⚠ ROOT LEVEL — mirrors scenes/recruit_screen.gd (check both)
├── defense_scene.tscn          # ⚠ ROOT LEVEL — duplicate .tscn; canonical script is scenes/defense_scene.gd
│
├── art/                        # Sprite PNGs — art/sprites/<key>_walk1.png etc (see unit_sprite.gd)
├── assets/                     # Enemy sprite sheets (skeleton set etc)
└── addons/godot_ai/            # MCP editor plugin — do NOT edit
```

---

## Autoloads (`autoloads/`)

All available globally by singleton name. Registered in `project.godot`.

| File | Singleton | Key responsibility |
|---|---|---|
| `player_inventory.gd` | `PlayerInventory` | **All persistent state** — gear, troops, resources, map zones, tutorial progress, settings flags |
| `gear_generator.gd` | `GearGenerator` | Procedural gear creation — rarity/stat/quality rolls |
| `save_manager.gd` | `SaveManager` | JSON save/load at `user://savegame.json`; new-game setup; recruit generation |
| `tutorial_overlay.gd` | `TutorialOverlay` | Renders tutorial overlay UI; `blocking_enabled` flag gates input |
| `tutorial_router.gd` | `TutorialRouter` | Advances tutorial steps; call `resolve_current_step(scene)` from each scene's `_ready` |
| `tutorial_steps.gd` | *(loaded by TutorialRouter)* | Step content — NOT an autoload, just a data file |
| `admin_panel.gd` | `AdminPanel` | Debug/cheat panel; persistent ⚙ button top-right; Shift+F9 also toggles |
| `telemetry_manager.gd` | `Telemetry` | Opt-in event logging; `Telemetry.log_event(name, dict)`; uploads to Supabase |
| `talent_tree_data.gd` | `TalentTreeData` | Talent definitions — read by talent_tree_screen and PlayerInventory |

### PlayerInventory key vars (most-referenced)

```gdscript
# Economy
PlayerInventory.gold                   # int
PlayerInventory.food                   # int
PlayerInventory.can_afford(cost_dict)  # bool — always use this, never read sub-dicts
PlayerInventory.spend_resources(cost)  # deducts gold/food

# Progression
PlayerInventory.current_stage          # int 1–10
PlayerInventory.commander_class        # String: "ARCHER", "MAGE", "KNIGHT", etc.

# Roster
PlayerInventory.troop_roster           # Array[TroopData]
PlayerInventory.unlocked_troop_slots   # int

# Gear
PlayerInventory.gear_inventory         # Array[GearItem]

# Map
PlayerInventory.map_zones              # Array of dicts: {id, name, type, pos, owner, troops, buildings, connections}
PlayerInventory.current_battle_zone    # int — zone ID set by world_map before scene change
PlayerInventory.current_battle_forge_level   # int — zone Forge buff passed to defense_scene
PlayerInventory.current_battle_shrine_level  # int — zone Shrine buff passed to defense_scene

# Tutorial
PlayerInventory.tutorial_step_index   # int — current step
PlayerInventory.tutorial_complete     # bool

# Settings (persisted in user://settings.cfg)
PlayerInventory.confirm_before_disposing_gear   # bool
PlayerInventory.mobile_mode                     # bool — shows VirtualDpad in dungeons
PlayerInventory.settings_return_scene           # String — set before navigating to settings so Back returns correctly

# Defense context (set by world_map before launching defense_scene)
PlayerInventory.conquering_zone        # bool
PlayerInventory.current_attack_force   # float
```

---

## Resources (`resources/`)

`class_name`'d — usable without preload.

### `gear_item.gd` → `GearItem`

```gdscript
enum Rarity   { COMMON, RARE, EPIC, LEGENDARY }
enum Slot     { WEAPON, ARMOR, RING, ACCESSORY }
enum Quality  { NORMAL, AWAKENED, ASCENDANT, TRANSCENDENT }

var rarity: Rarity
var slot: Slot
var quality: Quality
var upgrade_level: int    # 0–6
var stats: Dictionary     # raw base stats

func get_effective_stats() -> Dictionary  # always use this — includes upgrade bonus
```

### `troop_data.gd` → `TroopData`

```gdscript
enum TroopType { KNIGHT, ARCHER, MAGE, HEALER, ROGUE }

var troop_name: String
var troop_type: TroopType
var equipped_gear: Dictionary  # slot name → GearItem
var current_hp: int            # persists between battles

func get_type_name() -> String              # "KNIGHT" etc.
func get_effective_stats() -> Dictionary   # includes gear + talent bonuses — always use this
func get_current_hp() -> int
func get_max_hp() -> int
```

### `unit_sprite.gd` → `UnitSprite` (extends Node2D)

Renders a troop/enemy as either animated art or procedural fallback.

```gdscript
enum UnitType { KNIGHT, ARCHER, MAGE, HEALER, ROGUE, TREANT, FAERIE, BULL, SPORE_BOMBER, ANCIENT_TOTEM }

func setup(type: UnitType, color: Color, unit_size: float)
func set_color(c: Color)
func set_moving(moving: bool)
func face(dir: Vector2)
```

**Art lookup**: `art/sprites/<key>_walk1.png` — if found, uses AnimatedSprite2D.
Walk frames 2–5 and attack frames are only loaded if file size ≥ 10 KB (placeholder guard).
Scale = `unit_size / idle_texture_height` — use a large unit_size for sprites with big canvases (hero uses 96.0).

---

## Scenes (`scenes/`)

### Scene Flow

```
main_menu → new_game_screen → management_screen ↔ world_map
                                      │
              ┌───────────────────────┼────────────────────┐
        dungeon_picker           recruit_screen       talent_tree_screen
              │                                       gear_shop_screen
        ┌─────┴──────┐
  defense_scene   action_dungeon
                  tutorial_dungeon (tutorial only)
```

### Scene-by-scene

| File | Purpose | Notes |
|---|---|---|
| `main_menu.gd/tscn` | Title screen | Continue / New Game / Delete Save / telemetry opt-in |
| `new_game_screen.gd/tscn` | Commander class select, troop picks | Sets `PlayerInventory.commander_class` |
| `management_screen.gd/tscn` | Equip gear on troops; drag-and-drop | Entire UI built in `_build_ui()` — no scene-tree nodes pre-placed |
| `world_map.gd/tscn` | Procedural zone conquest | Real-time troop marching; sets battle context on `PlayerInventory` before scene change; `TUTORIAL_DEFENSE_FORCE_MULT = 1.0` |
| `defense_scene.gd/tscn` | Auto-battler wave defense | Troops placed pre-battle; supports drag-to-reposition placed troops; autotest mode flag inside |
| `action_dungeon.gd/tscn` | Survival arena — player controls hero | Click-to-move + WASD + VirtualDpad; camera follows hero; roguelite skill picks on level-up |
| `tutorial_dungeon.gd/tscn` | Scripted intro version of action_dungeon | Smaller arena (1400×1000 vs 3200×3200); 8 kills to clear; guarantees 4 gear drops + 1 recruit |
| `dungeon_picker_screen.gd/tscn` | Choose action dungeon difficulty | |
| `gear_shop_screen.gd/tscn` | Buy, upgrade, sell gear | |
| `recruit_screen.gd/tscn` | Hire new troops | Script also lives at root `recruit_screen.gd` |
| `recruit_choice_screen.gd/tscn` | Choose from a selection of recruits | |
| `talent_tree_screen.gd/tscn` | Spend talent points | |
| `talent_tree_layout.gd` | Tree structure data for talent_tree_screen | |
| `dungeon_scene.gd/tscn` | Old fixed-room dungeon (legacy) | Mostly superseded by action_dungeon |
| `seed_and_launch.gd/tscn` | Debug seed launcher | |
| `debug_scene.gd/tscn` | Dev test scene | |
| `debug_scene2.gd/tscn` | Dev test scene 2 | |

### Drag-and-drop helpers

| File | Purpose |
|---|---|
| `draggable_gear_button.gd` | A gear item button you can drag off |
| `droppable_slot_button.gd` | A troop's gear slot that accepts drops |
| `draggable_roster_button.gd` | A roster troop card you can drag onto the defense field |
| `placement_drop_zone.gd` | Invisible Control in defense_scene that receives roster drops |

### VirtualDpad

`scenes/virtual_dpad.gd` — `class_name VirtualDpad extends CanvasLayer`

Created by dungeons when `PlayerInventory.mobile_mode == true`.

```gdscript
var dpad = VirtualDpad.new()
add_child(dpad)
# then in _move_hero():
var dir = dpad.get_direction()  # Vector2, normalised
```

Renders 4 circular buttons (↑↓←→) bottom-left. Layer 15 so it sits above game but below modals.

---

## Settings System

Settings are stored in `user://settings.cfg` (a `ConfigFile`). Sections and keys:

```
[display]
width       = int
height      = int
fullscreen  = bool
borderless  = bool     # WINDOW_FLAG_BORDERLESS; mutually exclusive with fullscreen

[gameplay]
confirm_before_disposing_gear = bool

[controls]
mobile_mode = bool
```

**Loading** — `PlayerInventory._apply_saved_settings()` runs at startup.  
First launch (no file): goes fullscreen automatically.

**Saving** — `settings_screen.gd` (`_save_settings()`) writes all keys on every change.  
The script lives at **root level** (`settings_screen.gd`), not in `scenes/`.

**Settings screen** is opened from any scene by:
```gdscript
PlayerInventory.settings_return_scene = get_tree().current_scene.scene_file_path
get_tree().change_scene_to_file("res://scenes/settings_screen.tscn")
```

---

## Economy Rules

```gdscript
# ✅ Correct
if PlayerInventory.can_afford({"gold": 50}):
    PlayerInventory.spend_resources({"gold": 50})

# ❌ Never read sub-dicts directly
if PlayerInventory.gold >= 50: ...
```

**Salvage** uses rarity keys (`"COMMON"`, `"RARE"`, `"EPIC"`, `"LEGENDARY"`) — completely separate from gold/food. Only consumed by gear upgrades.

---

## Combat Formula Reference

### Defense (percentage-based)

```gdscript
damage_dealt = max(1, int(incoming_atk * 100.0 / (100.0 + defense)))
```
DEF=100 → 50% reduction. DEF=1000 → ~9%. Never reaches zero.
Armor gear stat is added to defense stat: `defense + armor` (both contribute).

### Troop effective stats
Always call `troop.get_effective_stats()` — never read `troop.stats` raw. Includes gear bonuses, talent bonuses, upgrade levels.

---

## Tutorial System

Steps live in `autoloads/tutorial_steps.gd`.
Progress tracked in `PlayerInventory.tutorial_step_index`.

At the start of each relevant scene:
```gdscript
TutorialRouter.resolve_current_step(self)
```

`TutorialOverlay.blocking_enabled = false` to allow interaction mid-tutorial.

Key steps (by name): `welcome` → `move_intro` → `attack_intro` → `dungeon_clear` → `management_intro` → `equip_intro` → `world_map_intro` → `defense_battle` → `heal_intro` → `talents_intro` → `talents_wilds_pact` (step 25 = complete).

---

## Defense Scene Details

`scenes/defense_scene.gd` — key vars:

```gdscript
var placed_troops: Array   # {troop, pos, hp, max_hp, attack, defense, rect, hp_bar, hp_bar_bg, label, sz, ...}
var enemies: Array         # {pos, hp, max_hp, attack, speed, rect, hp_bar, ...}
var projectiles: Array
var roster_slots: Array    # {troop_data, btn, placed}
var battle_active: bool    # false during placement phase
var autotest_mode := false # set true to run 5-stage self-play simulation
```

**Placement** — click roster card → click field to place. Also supports drag-and-drop.  
**Repositioning** — click-and-drag an already-placed troop to move it (pre-battle only). Drops outside valid zone snap back. `_apply_troop_position(idx, pos)` moves all 4 visual nodes together.

Valid placement zone: `x > BASE_X+30 and x < FIELD_W/2` and `y > 10 and y < FIELD_H-120`.

---

## Action Dungeon Details

`scenes/action_dungeon.gd` — key constants:

```gdscript
const ARENA_W = 3200
const ARENA_H = 3200
const ARENA_WALL_T = 32
const HERO_SPRITE_SIZE = 96.0   # visual size; scale = 96/sprite_canvas_height
```

**Movement priority** (highest to lowest):
1. Keyboard (WASD / arrow keys) — cancels click target
2. VirtualDpad — only when no keyboard held, only if `_dpad` exists
3. Click-to-move (`_has_mouse_target`) — left-click sets `_mouse_target` in world space

**Hero is NOT a TroopData slot.** Commander class stored in `PlayerInventory.commander_class`. Stats scale with `current_stage`, not gear.

**Save zone**: colored rect on the arena floor. Standing inside channels progress to secure dropped gear.

**Floor props**: `_build_floor_props()` scatters ~600 small debris rects (fixed seed=42) for movement parallax feedback.

---

## Art / Sprite Conventions

- Player sprites: `art/sprites/<class_lower>_walk1.png` etc.
  - Classes: `archer`, `knight`, `mage`, `healer`, `rogue`
  - Frames: `_walk1` (idle), `_walk2–5` (walk anim), `_attack1–2` (attack anim)
- Enemy sprites: `art/sprites/<enemy>_walk1.png`
  - Types: `treant`, `faerie`, `bull`, `spore_bomber`, `ancient_totem`
- **Placeholder guard**: frames < 10 KB are skipped (32×32 icon in 512×512 canvas = ~3–7 KB)
- Canvas size is 512×512 for all sprites; actual art occupies a sub-region
- `unit_size / canvas_height` = scale factor — use large unit_size for hero (96.0 → ~18% scale)

---

## Known Quirks

- `settings_screen.gd` is at the **project root**, not `scenes/` — the `.tscn` references it from there.
- `defense_scene.tscn` exists at both root and `scenes/` — the canonical script is `scenes/defense_scene.gd`.
- `recruit_screen.gd` exists at both root and `scenes/recruit_screen.gd`.
- Most screen UIs are **entirely code-built** in `_build_ui()` — don't expect pre-placed nodes in the `.tscn`.
- `@onready` vars are assigned inside `_build_ui()`, not from the scene tree.
- `addons/godot_ai/` is the MCP editor plugin — never edit it.
- `godot_ai/` at root is a separate older copy — also don't edit.
