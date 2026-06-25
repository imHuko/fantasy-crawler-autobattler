extends Node2D

const UnitSprite := preload("res://resources/unit_sprite.gd")

# -------------------------------------------------------
# Action Dungeon — Survival Arena
# One large open scrollable arena, no rooms or doors. Enemies spawn
# continuously and escalate the longer you survive. A relocating save
# zone lets you bank gear you've found; only banked gear is safe if you
# die. Run ends when the survival timer runs out, or you retreat/die.
# -------------------------------------------------------

# =========================================================
# BALANCE TUNING
# Every number in this section controls how the dungeon feels.
# Safe to change without touching any logic further below.
# =========================================================

# --- ARENA -----------------------------------------------
const ARENA_W      = 3200   # total width in pixels
const ARENA_H      = 3200   # total height in pixels
const ARENA_WALL_T = 32     # border wall thickness

# --- HERO ------------------------------------------------
# Both HP and attack scale linearly with stage (world progression),
# then get multiplied by the active class profile below.
const HERO_HP_BASE        = 100    # HP at stage 1
const HERO_HP_PER_STAGE   = 8     # flat HP added per stage
const HERO_ATK_BASE       = 12    # attack at stage 1
const HERO_ATK_PER_STAGE  = 2     # flat attack added per stage
const HERO_SPEED_BASE     = 180.0  # movement speed in pixels/sec
const ATTACK_INTERVAL     = 0.9   # base seconds between attacks (scaled by class interval_mult)
const MIN_SPAWN_DIST_FROM_HERO = 220.0  # enemies never spawn closer than this to the player

# Class multipliers applied on top of hero base stats.
# interval_mult < 1.0 = faster attacks. range 99999 = effectively unlimited (ranged classes).
const CLASS_PROFILES = {
	# melee=true: attacks are instant damage in range (no projectile)
	# melee=false: attacks fire a traveling projectile
	"KNIGHT": { "hp_mult": 1.5,  "dmg_mult": 1.0,  "interval_mult": 1.0, "range": 220.0,   "self_heal": false, "melee": true  },
	"ARCHER": { "hp_mult": 1.0,  "dmg_mult": 0.75, "interval_mult": 0.6, "range": 99999.0, "self_heal": false, "melee": false },
	"MAGE":   { "hp_mult": 0.85, "dmg_mult": 1.8,  "interval_mult": 1.4, "range": 99999.0, "self_heal": false, "melee": false },
	"ROGUE":  { "hp_mult": 0.7,  "dmg_mult": 0.8,  "interval_mult": 0.5, "range": 220.0,   "self_heal": false, "melee": true  },
	"HEALER": { "hp_mult": 0.8,  "dmg_mult": 0.5,  "interval_mult": 1.0, "range": 99999.0, "self_heal": true,  "melee": false },
}
const HEALER_SELF_HEAL_INTERVAL = 3.0   # seconds between passive self-heal ticks
const HEALER_SELF_HEAL_PCT      = 0.08  # % of max HP healed per tick

# --- ENEMIES ---------------------------------------------
# Base stats at stage 1. Archetype multipliers and time-scaling stack on top.
const ENEMY_HP_BASE         = 18    # HP at stage 1
const ENEMY_HP_PER_STAGE    = 6     # flat HP added per stage
const ENEMY_ATK_BASE        = 4     # attack at stage 1
const ENEMY_ATK_PER_STAGE   = 2     # flat attack added per stage
const ENEMY_SPEED_BASE      = 62.0  # movement speed at stage 1
const ENEMY_SPEED_PER_STAGE = 4.0   # speed added per stage

# How much tougher enemies get the longer a run goes.
# Applied fresh each spawn wave based on elapsed run time.
const ENEMY_HP_PER_MIN_PCT    = 0.10  # +% max HP per minute
const ENEMY_DMG_PER_MIN_PCT   = 0.06  # +% attack per minute
const ENEMY_SPEED_PER_MIN_PCT = 0.04  # +% speed per minute
const ENEMY_HP_PER_1000_DIST_PCT = 0.08  # +% HP per 1000px from arena center

# Archetype spawn weights (higher = more common) and stat multipliers.
# RANGED only enters the pool after RANGED_UNLOCK_MINUTE minutes.
const ARCHETYPE_WEIGHTS = {
	"MELEE": 100, "BULL": 45, "CHARGER": 30, "RANGED": 18, "BUFFER": 8,
}
const ARENA_ARCHETYPES = {
	"MELEE":   { "hp_mult": 1.0,  "dmg_mult": 1.0,  "speed_mult": 1.0,  "color": Color(0.85, 0.25, 0.25) },
	"BULL":    { "hp_mult": 1.6,  "dmg_mult": 1.4,  "speed_mult": 0.9,  "color": Color(0.55, 0.35, 0.15) },
	"CHARGER": { "hp_mult": 0.4,  "dmg_mult": 2.5,  "speed_mult": 2.4,  "color": Color(0.9, 0.45, 0.1)  },
	"RANGED":  { "hp_mult": 0.75, "dmg_mult": 0.9,  "speed_mult": 0.9,  "color": Color(0.25, 0.6, 0.3)  },
	"BUFFER":  { "hp_mult": 0.5,  "dmg_mult": 0.0,  "speed_mult": 0.85, "color": Color(0.85, 0.75, 0.2) },
}
const RANGED_UNLOCK_MINUTE = 3.0   # minute mark when RANGED enemies enter the pool

# Special behaviors per archetype
const RANGED_ATTACK_RANGE       = 320.0
const BUFFER_AURA_RANGE         = 180.0
const BUFFER_BUFF_INTERVAL      = 4.0
const BUFFER_DMG_BOOST_PCT      = 0.35
const BUFFER_DMG_BOOST_DURATION = 3.0
const BULL_WINDUP_TIME          = 1.0    # seconds of telegraph before charge fires
const BULL_CHARGE_SPEED         = 480.0
const BULL_CHARGE_DISTANCE      = 420.0  # pixels per charge before stopping to recover
const BULL_RECOVER_TIME         = 1.2    # pause after charge before next wind-up

# --- SPAWN PACING ----------------------------------------
const SPAWN_INTERVAL_START        = 2.5    # seconds between waves at run start
const SPAWN_INTERVAL_MIN          = 0.5    # fastest the interval can ever get
const SPAWN_INTERVAL_RAMP_PER_MIN = 0.15   # interval shrinks by this per minute
const SPAWN_COUNT_START           = 2      # enemies per wave at run start
const SPAWN_COUNT_PER_MIN         = 0.4    # extra enemies per wave per minute
const SPAWN_COUNT_MAX             = 12     # hard cap on enemies per wave
const DENSITY_SPAWN_SLOWDOWN_THRESHOLD = 18   # enemy count above this slows spawning
const DENSITY_SPAWN_SLOWDOWN_MULT      = 1.6  # interval multiplied by this above the threshold

# --- MINI-BOSSES -----------------------------------------
const MINIBOSS_BASE_INTERVAL_SECONDS = 90.0   # baseline seconds between mini-boss spawns
const MINIBOSS_KILLS_REDUCE_TIMER_BY = 1.5    # each kill shaves this off the timer
const MINIBOSS_UNIQUE_CHANCE         = 0.3    # chance of a rare unique instead of empowered normal
const MINIBOSS_EMPOWERED_HP_MULT     = 6.0    # HP multiplier vs a normal of the same archetype
const MINIBOSS_EMPOWERED_DMG_MULT    = 2.0
const MINIBOSS_EMPOWERED_SIZE_MULT   = 1.8
const MINIBOSS_GUARANTEED_RARITY_BOOST = 2    # loot rolls this many difficulty levels higher

# --- SAVE ZONE -------------------------------------------
const SAVE_ZONE_RADIUS            = 70.0
const SAVE_ZONE_CHANNEL_TIME      = 5.0    # seconds to stand in zone to bank gear
const SAVE_ZONE_RELOCATE_INTERVAL = 45.0   # seconds before zone moves to a new spot

# --- PROJECTILES -----------------------------------------
const PROJECTILE_SPEED     = 320.0
const PROJECTILE_MAX_RANGE = 700.0   # projectile vanishes after travelling this far

# --- XP & LEVELING ---------------------------------------
const XP_PER_NORMAL_KILL = 3
const XP_PER_BOSS_KILL   = 25
const XP_BASE            = 20    # XP to reach level 1
const XP_PER_LEVEL       = 12    # extra XP needed per subsequent level

# --- SKILL EFFECTS ---------------------------------------
# The actual numbers behind each roguelite skill.
# If you change a value here, update the matching desc string in SKILL_POOL too.
const SKILL_SWIFTNESS_SPEED_BONUS  = 0.15   # speed bonus per stack
const SKILL_IRON_HIDE_HP_BONUS     = 0.25   # % of current max HP added per stack
const SKILL_ARMOR_PLATING_FLAT     = 4      # flat armor per stack
const SKILL_RAPID_FIRE_MULT        = 0.80   # attack interval multiplied by this per stack
const SKILL_POWER_SHOT_MULT        = 1.30   # attack multiplied by this per stack
const SKILL_DEADLY_CRITS_CHANCE    = 0.15   # crit chance added per stack
const SKILL_CRUSHING_BLOW_CRIT_DMG = 50     # crit damage % added per stack
const SKILL_WIDE_RANGE_MULT        = 1.50   # attack range multiplied by this per stack
const SKILL_GLASS_CANNON_DMG_MULT  = 1.60   # attack multiplier (one-time)
const SKILL_GLASS_CANNON_HP_MULT   = 0.80   # max HP multiplier penalty (one-time)
const SKILL_LUCKY_DROP_BONUS       = 0.12   # gear drop chance per stack
const SKILL_VAMPIRIC_HP_PER_KILL   = 1      # HP healed per kill per stack
const SKILL_LIFESTEAL_PCT          = 0.08   # % of damage dealt healed per stack
const SKILL_SECOND_WIND_REVIVE_PCT = 0.30   # HP % restored when triggered
const SKILL_PLUNDER_DROP_BONUS     = 0.25   # gear drop chance (one-time)
const SKILL_PLUNDER_DMG_MULT       = 0.85   # attack multiplier penalty (one-time)

# =========================================================
# END BALANCE TUNING
# =========================================================

# Art mappings — which UnitSprite type each archetype/class displays as.
const ARCHETYPE_UNIT_TYPES = {
	"MELEE":   UnitSprite.UnitType.TREANT,
	"BULL":    UnitSprite.UnitType.BULL,
	"CHARGER": UnitSprite.UnitType.SPORE_BOMBER,
	"RANGED":  UnitSprite.UnitType.FAERIE,
	"BUFFER":  UnitSprite.UnitType.ANCIENT_TOTEM,
}
const CLASS_UNIT_TYPES = {
	"KNIGHT": UnitSprite.UnitType.KNIGHT,
	"ARCHER": UnitSprite.UnitType.ARCHER,
	"MAGE":   UnitSprite.UnitType.MAGE,
	"HEALER": UnitSprite.UnitType.HEALER,
	"ROGUE":  UnitSprite.UnitType.ROGUE,
}

# =========================================================
# SKILL POOL — roguelite skills offered on level-up.
# Shared pool, no class gating. Skills with max_stacks > 1
# can be chosen multiple times for compounding effect.
# Numeric effect values live in SKILL EFFECTS in the balance block above.
# =========================================================
const SKILL_POOL = [
	{ "id": "swiftness",     "name": "Swiftness",       "desc": "+15% move speed",                               "max_stacks": 3 },
	{ "id": "iron_hide",     "name": "Iron Hide",        "desc": "+25% max HP, healed immediately",               "max_stacks": 2 },
	{ "id": "armor_plating", "name": "Armor Plating",    "desc": "+4 armor",                                      "max_stacks": 3 },
	{ "id": "rapid_fire",    "name": "Rapid Fire",       "desc": "-20% attack interval",                          "max_stacks": 3 },
	{ "id": "power_shot",    "name": "Power Shot",       "desc": "+30% attack damage",                            "max_stacks": 3 },
	{ "id": "deadly_crits",  "name": "Deadly Crits",     "desc": "+15% crit chance",                              "max_stacks": 2 },
	{ "id": "crushing_blow", "name": "Crushing Blow",    "desc": "+50% crit damage multiplier",                   "max_stacks": 2 },
	{ "id": "wide_range",    "name": "Wide Range",       "desc": "+50% attack range",                             "max_stacks": 2 },
	{ "id": "glass_cannon",  "name": "Glass Cannon",     "desc": "+60% damage, -20% max HP",                      "max_stacks": 1 },
	{ "id": "lucky",         "name": "Lucky",            "desc": "+12% gear drop chance",                         "max_stacks": 2 },
	{ "id": "vampiric",      "name": "Vampiric",         "desc": "Heal 1 HP per kill",                            "max_stacks": 3 },
	{ "id": "multishot",     "name": "Multishot",        "desc": "+1 extra projectile per attack",                "max_stacks": 2 },
	{ "id": "piercing",      "name": "Piercing Shot",    "desc": "Projectiles pass through enemies",              "max_stacks": 1 },
	{ "id": "explosive",     "name": "Explosive Rounds", "desc": "Hits deal 40% AoE splash damage",              "max_stacks": 1 },
	{ "id": "orb_shield",    "name": "Orbital Shield",   "desc": "+2 orbiting projectiles that damage enemies",   "max_stacks": 2 },
	{ "id": "nova_burst",    "name": "Nova Burst",       "desc": "Taking damage emits a damaging pulse nearby",   "max_stacks": 1 },
	{ "id": "death_rattle",  "name": "Death Rattle",     "desc": "Enemies explode on death for area damage",      "max_stacks": 1 },
	{ "id": "berserker",     "name": "Berserker",        "desc": "Gain up to +40% attack speed as HP drops",      "max_stacks": 1 },
	{ "id": "second_wind",   "name": "Second Wind",      "desc": "Once per run, survive a killing blow at 30% HP","max_stacks": 1 },
	{ "id": "lifesteal",     "name": "Lifesteal",        "desc": "Heal for 8% of damage dealt",                  "max_stacks": 2 },
	{ "id": "plunder",       "name": "Plunder",          "desc": "+25% gear drop chance, -15% attack damage",    "max_stacks": 1 },
]

const C_FLOOR    = Color(0.18, 0.16, 0.22)
const C_WALL     = Color(0.30, 0.25, 0.35)
const C_HERO     = Color(0.30, 0.70, 1.00)
# Visual display size for the hero sprite. Larger than the hitbox constant (14)
# because the 512×512 canvas art needs more room for content to appear at a
# readable size. Hitbox logic uses the hardcoded radius in _process_homing_melee.
const HERO_SPRITE_SIZE: float = 96.0
const C_PROJ_H   = Color(0.50, 0.90, 1.00)
const C_PROJ_E   = Color(1.00, 0.55, 0.10)
const C_SAVE_ZONE = Color(0.3, 0.85, 0.5, 0.35)

var run_gear: Array = []          # gear currently held but NOT yet banked — lost (partially) on death
var banked_gear: Array = []       # gear safely banked at the save zone — survives death and retreat
var secured_gear: Array = []      # everything actually kept by the end of the run, for the end screen — never cleared mid-run

var hero_hp: int = HERO_HP_BASE
var hero_max_hp: int = HERO_HP_BASE
var hero_speed: float = HERO_SPEED_BASE
var hero_attack: int = 12
var hero_armor: int = 0
var hero_crit_chance: float = 0.0
var hero_crit_damage: int = 0
var hero_attack_range: float = 99999.0
var hero_attack_interval: float = ATTACK_INTERVAL
var hero_self_heal: bool = false
var hero_is_melee: bool = false
var hero_dodge_chance: float = 0.0
var hero_hp_regen: float = 0.0
var hero_on_kill_heal: int = 0
var hero_melee_power: float = 0.0
var hero_chain_crit: bool = false
var self_heal_timer: float = HEALER_SELF_HEAL_INTERVAL
var attack_timer: float = 0.0
var invincible_timer: float = 0.0

var hero_pos: Vector2 = Vector2(ARENA_W/2, ARENA_H/2)
var _mouse_target: Vector2 = Vector2.ZERO
var _has_mouse_target: bool = false
var _dpad: VirtualDpad = null

var enemies: Array = []        # {pos, hp, max_hp, speed, attack, shoot_t, is_boss, boss_p, boss_t, boss_a}
var hero_projs: Array = []     # {pos, dir}
var enemy_projs: Array = []    # {pos, dir, damage}

var arena_node: Node2D = null
var hero_rect: UnitSprite = null
var hud_hp: Label = null
var hud_timer: Label = null
var hud_gear: Label = null
var pause_btn: Button = null
var is_paused: bool = false
var enemy_rects: Array = []
var hero_proj_rects: Array = []
var enemy_proj_rects: Array = []

var camera: Camera2D = null

var run_duration_seconds: float = 600.0   # set from PlayerInventory.dungeon_duration_seconds in _ready(); this default only matters if the dungeon is entered without going through the picker
var elapsed_seconds: float = 0.0
var spawn_timer: float = SPAWN_INTERVAL_START
var miniboss_timer: float = MINIBOSS_BASE_INTERVAL_SECONDS
var kill_count: int = 0
var ranged_unlocked: bool = false

var save_zone_pos: Vector2 = Vector2.ZERO
var save_zone_relocate_timer: float = SAVE_ZONE_RELOCATE_INTERVAL
var save_zone_channel_progress: float = 0.0
var save_zone_node: ColorRect = null
var save_zone_label: Label = null

var game_over: bool = false

# --- Roguelite skill progression ---
var hero_xp: int = 0
var hero_level: int = 0
var xp_to_next: int = XP_BASE
var skills_taken: Dictionary = {}   # skill_id -> stack count
var pending_level_ups: int = 0
var run_rerolls: int = 0
var run_banishes: int = 0
var banished_skill_ids: Array = []

# Skill effect accumulators / flags
var skill_drop_bonus: float = 0.0      # lucky
var skill_vampiric_hp: int = 0         # vampiric: HP per kill
var skill_extra_projs: int = 0         # multishot: extra projectiles
var skill_piercing: bool = false        # piercing shot
var skill_explosive: bool = false       # explosive rounds
var skill_orb_count: int = 0           # orbital shield: number of orbs
var skill_orb_angle: float = 0.0       # orbital shield: current angle
var skill_orb_rects: Array = []        # orbital shield: visual nodes
var skill_orb_hit_timer: float = 0.0   # orbital shield: global hit cooldown
var skill_nova: bool = false            # nova burst
var skill_death_rattle: bool = false    # death rattle
var skill_berserker: bool = false       # berserker
var iron_will_used: bool = false        # dungeon_iron_will: one-time kill-blow intercept per run
var skill_second_wind: bool = false     # second wind: feature enabled
var skill_second_wind_ready: bool = false  # second wind: hasn't triggered yet this run
var skill_lifesteal: float = 0.0       # lifesteal fraction

var _enemy_id_counter: int = 0   # unique ID for each spawned enemy (used by piercing)
var hud_level: Label = null

func _ready() -> void:
	run_duration_seconds = PlayerInventory.dungeon_duration_seconds
	if PlayerInventory.unlocked_talents.get("dungeon_extended_campaign", false):
		run_duration_seconds += 90.0
	if PlayerInventory.unlocked_talents.get("dungeon_marathon_runner", false):
		run_duration_seconds += 120.0
	_load_hero_stats()
	_setup_camera()
	_build_arena_visuals()
	_start_run()
	_build_hud()
	if PlayerInventory.mobile_mode:
		_dpad = VirtualDpad.new()
		add_child(_dpad)

var _sandbox_class_override: String = ""   # set by sandbox_set_hero_class() — empty means "use commander_class"
var _sandbox_god_mode: bool = false

func _load_hero_stats() -> void:
	var class_key = _sandbox_class_override if _sandbox_class_override != "" else PlayerInventory.commander_class
	var profile = CLASS_PROFILES.get(class_key, CLASS_PROFILES["ARCHER"])
	var stage = PlayerInventory.current_stage

	# Commander stats scale with world progression (stage), not gear.
	# Roguelite skill picks are the run's personal power curve.
	var base_hp     = HERO_HP_BASE + stage * HERO_HP_PER_STAGE
	var base_attack = HERO_ATK_BASE + stage * HERO_ATK_PER_STAGE

	hero_max_hp          = max(50,  int(base_hp * profile["hp_mult"]))
	hero_speed           = HERO_SPEED_BASE
	hero_attack          = max(5,   int(base_attack * profile["dmg_mult"]))
	hero_armor           = 0
	if PlayerInventory.unlocked_talents.get("dungeon_veteran_commander", false):
		hero_max_hp += 20
	if PlayerInventory.unlocked_talents.get("dungeon_combat_drilling", false):
		hero_attack += 10
	hero_crit_chance     = 0.0
	hero_crit_damage     = 0
	hero_attack_range    = profile["range"]
	hero_attack_interval = ATTACK_INTERVAL * profile["interval_mult"]
	hero_self_heal       = profile["self_heal"]
	hero_is_melee        = profile.get("melee", false)

	# Apply equipped Commander gear on top of base/talent stats
	for slot_key in PlayerInventory.commander_gear:
		var g: GearItem = PlayerInventory.commander_gear[slot_key]
		if g == null: continue
		var gs = g.get_effective_stats()
		hero_attack        += gs.get("attack", 0)
		hero_max_hp        += gs.get("hp", 0)
		hero_armor         += gs.get("armor", 0)
		hero_crit_chance   += gs.get("crit_chance", 0.0)
		hero_crit_damage   += gs.get("crit_damage", 0)
		hero_dodge_chance  += gs.get("dodge_chance", 0.0)
		hero_hp_regen      += gs.get("hp_regen", 0.0)
		hero_on_kill_heal  += gs.get("on_kill_heal", 0)
		skill_lifesteal    += gs.get("lifesteal", 0.0)
		if gs.has("attack_speed"):
			hero_attack_interval *= max(0.3, 1.0 - gs["attack_speed"])
		if hero_is_melee:
			hero_melee_power += gs.get("melee_power", 0.0)

	# Commander set bonuses (max 2-piece — only WEAPON + RING slots available)
	var cmdr_set_counts: Dictionary = {}
	for slot_key in PlayerInventory.commander_gear:
		var g: GearItem = PlayerInventory.commander_gear[slot_key]
		if g != null and g.set_name != "":
			cmdr_set_counts[g.set_name] = cmdr_set_counts.get(g.set_name, 0) + 1
	for set_name in cmdr_set_counts:
		var count = cmdr_set_counts[set_name]
		var bonuses = GearGenerator.SET_BONUSES.get(set_name, {})
		for threshold in bonuses:
			if count >= threshold:
				for key in bonuses[threshold]:
					match key:
						"hp_pct":       hero_max_hp    = int(hero_max_hp * (1.0 + bonuses[threshold][key]))
						"armor":        hero_armor     += int(bonuses[threshold][key])
						"crit_chance":  hero_crit_chance += bonuses[threshold][key]
						"dodge_chance": hero_dodge_chance += bonuses[threshold][key]
						"on_kill_heal": hero_on_kill_heal += int(bonuses[threshold][key])
						"chain_crit":   hero_chain_crit = true
						# spell_power only affects Mage/Healer — not a Commander stat yet

	hero_hp = hero_max_hp

# Admin sandbox — swaps which class profile + art the Commander uses this run.
func sandbox_set_hero_class(class_key: String) -> void:
	if not CLASS_PROFILES.has(class_key):
		return
	_sandbox_class_override = class_key
	_load_hero_stats()
	_build_hero_rect()
	_refresh_hud()

func sandbox_toggle_god_mode() -> bool:
	_sandbox_god_mode = not _sandbox_god_mode
	return _sandbox_god_mode

func sandbox_skip_time(seconds: float) -> void:
	elapsed_seconds = min(elapsed_seconds + seconds, run_duration_seconds - 5.0)
	if not ranged_unlocked and _scaled_minutes() >= RANGED_UNLOCK_MINUTE:
		ranged_unlocked = true
	_refresh_hud()

func sandbox_force_miniboss() -> void:
	_spawn_miniboss()

func sandbox_force_levelup() -> void:
	_grant_xp(xp_to_next - hero_xp)

func sandbox_apply_skill(skill_id: String) -> void:
	_apply_skill(skill_id)
	_refresh_hud()

func sandbox_get_skill_pool() -> Array:
	return SKILL_POOL

func sandbox_get_skill_stacks(skill_id: String) -> int:
	return skills_taken.get(skill_id, 0)

func sandbox_get_run_stats() -> Dictionary:
	var stage = PlayerInventory.current_stage
	var tier_mult = {"Quick": 0.8, "Standard": 1.0, "Deep Delve": 1.4}.get(PlayerInventory.dungeon_tier, 1.0)
	var hp_scale  = _get_hp_scale()
	var dmg_scale = _get_dmg_scale()
	var spd_scale = _get_speed_scale()
	var minutes   = _scaled_minutes()

	var archetype_stats = {}
	for arch in ARENA_ARCHETYPES:
		var p = ARENA_ARCHETYPES[arch]
		archetype_stats[arch] = {
			"hp":  int((ENEMY_HP_BASE  + stage * ENEMY_HP_PER_STAGE)  * tier_mult * p["hp_mult"]  * hp_scale),
			"atk": int((ENEMY_ATK_BASE + stage * ENEMY_ATK_PER_STAGE) * tier_mult * p["dmg_mult"] * dmg_scale),
			"spd": snappedf((ENEMY_SPEED_BASE + stage * ENEMY_SPEED_PER_STAGE) * p["speed_mult"] * spd_scale, 0.1),
		}

	return {
		"minute":      snappedf(minutes, 0.1),
		"remaining":   snappedf(max(0.0, run_duration_seconds - elapsed_seconds), 1.0),
		"level":       hero_level,
		"kill_count":  kill_count,
		"enemy_count": enemies.size(),
		"hp_scale":    snappedf(hp_scale, 0.01),
		"dmg_scale":   snappedf(dmg_scale, 0.01),
		"spd_scale":   snappedf(spd_scale, 0.01),
		"hero_hp":     hero_hp,
		"hero_max_hp": hero_max_hp,
		"hero_atk":    hero_attack,
		"hero_spd":    snappedf(hero_speed, 0.1),
		"archetypes":  archetype_stats,
	}

# -------------------------------------------------------
# Room generation
# -------------------------------------------------------
# Camera follows the hero and scrolls with the arena — this is the core
# of the Vampire Survivors feel. Limits are clamped to the arena bounds
# so the camera never shows empty space past the edges.
func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.position = hero_pos
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ARENA_W
	camera.limit_bottom = ARENA_H
	camera.enabled = true
	add_child(camera)

# -------------------------------------------------------
# Arena
# -------------------------------------------------------
func _build_arena_visuals() -> void:
	arena_node = Node2D.new()
	add_child(arena_node)
	move_child(arena_node, 0)

	# Floor fills the whole arena
	_add_rect(arena_node, Vector2.ZERO, Vector2(ARENA_W, ARENA_H), C_FLOOR)

	# Solid border around the entire arena — no doors, nowhere to exit
	# except retreating via the HUD button.
	_add_rect(arena_node, Vector2(-ARENA_WALL_T, -ARENA_WALL_T), Vector2(ARENA_W + ARENA_WALL_T*2, ARENA_WALL_T), C_WALL)
	_add_rect(arena_node, Vector2(-ARENA_WALL_T, ARENA_H), Vector2(ARENA_W + ARENA_WALL_T*2, ARENA_WALL_T), C_WALL)
	_add_rect(arena_node, Vector2(-ARENA_WALL_T, -ARENA_WALL_T), Vector2(ARENA_WALL_T, ARENA_H + ARENA_WALL_T*2), C_WALL)
	_add_rect(arena_node, Vector2(ARENA_W, -ARENA_WALL_T), Vector2(ARENA_WALL_T, ARENA_H + ARENA_WALL_T*2), C_WALL)

	_build_floor_props()

# Scatters small debris rects across the floor so the player can
# perceive movement against the otherwise-solid background.
# Purely decorative — fixed seed keeps the layout identical every run.
func _build_floor_props() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	var prop_colors = [
		Color(0.24, 0.22, 0.28),   # slightly lighter stone
		Color(0.13, 0.11, 0.17),   # slightly darker shadow
		Color(0.27, 0.23, 0.22),   # warm brown chip
		Color(0.21, 0.20, 0.26),   # neutral mid tone
	]

	var margin = ARENA_WALL_T + 30.0
	var center = Vector2(ARENA_W / 2.0, ARENA_H / 2.0)
	var clear_radius = 120.0

	# ~600 props gives the same visual density as the tutorial dungeon
	# (80 props on 1400×1000) scaled to this 3200×3200 arena.
	for i in range(600):
		var pos = Vector2(
			rng.randf_range(margin, ARENA_W - margin),
			rng.randf_range(margin, ARENA_H - margin)
		)
		if pos.distance_to(center) < clear_radius:
			continue
		var sz = Vector2(
			rng.randf_range(4.0, 14.0),
			rng.randf_range(3.0, 10.0)
		)
		_add_rect(arena_node, pos, sz, prop_colors[rng.randi() % prop_colors.size()])

# -------------------------------------------------------
# Enter room
# -------------------------------------------------------
# -------------------------------------------------------
# Run setup — happens once at scene start, no per-room re-entry
# -------------------------------------------------------
func _start_run() -> void:
	game_over = false
	hero_pos = Vector2(ARENA_W/2, ARENA_H/2)
	_has_mouse_target = false
	secured_gear.clear()
	var class_key = _sandbox_class_override if _sandbox_class_override != "" else PlayerInventory.commander_class
	Telemetry.log_event("dungeon_started", {
		"class": class_key,
		"stage": PlayerInventory.current_stage,
		"tier": PlayerInventory.dungeon_tier,
	})

	# Reset skill state for this run
	hero_xp = 0
	hero_level = 0
	xp_to_next = XP_BASE
	skills_taken.clear()
	pending_level_ups = 0
	skill_drop_bonus = 0.0
	skill_vampiric_hp = 0
	skill_extra_projs = 0
	skill_piercing = false
	skill_explosive = false
	skill_orb_count = 0
	skill_orb_angle = 0.0
	for r in skill_orb_rects:
		if is_instance_valid(r): r.queue_free()
	skill_orb_rects.clear()
	skill_orb_hit_timer = 0.0
	skill_nova = false
	skill_death_rattle = false
	skill_berserker = false
	skill_second_wind = false
	skill_second_wind_ready = false
	skill_lifesteal = 0.0
	iron_will_used = false
	hero_dodge_chance = 0.0
	hero_hp_regen     = 0.0
	hero_on_kill_heal = 0
	hero_melee_power  = 0.0
	hero_chain_crit   = false
	banished_skill_ids.clear()
	var has_loaded_dice = PlayerInventory.unlocked_talents.get("dungeon_loaded_dice", false)
	run_rerolls = 2 if has_loaded_dice else 0
	run_banishes = 1 if has_loaded_dice else 0
	_enemy_id_counter = 0

	enemies.clear()
	enemy_rects.clear()
	hero_projs.clear()
	enemy_projs.clear()
	hero_proj_rects.clear()
	enemy_proj_rects.clear()

	_build_hero_rect()
	_relocate_save_zone()
	_refresh_hud()
	if PlayerInventory.unlocked_talents.get("dungeon_opening_gambit", false):
		var free_skills = _get_random_skills(1)
		if not free_skills.is_empty():
			_apply_skill(free_skills[0]["id"])

func _build_hero_rect() -> void:
	if hero_rect:
		hero_rect.queue_free()
	hero_rect = UnitSprite.new()
	var class_key = _sandbox_class_override if _sandbox_class_override != "" else PlayerInventory.commander_class
	var hero_unit_type = CLASS_UNIT_TYPES.get(class_key, UnitSprite.UnitType.HERO)
	hero_rect.setup(hero_unit_type, Color.WHITE, HERO_SPRITE_SIZE)
	arena_node.add_child(hero_rect)
	hero_rect.position = hero_pos - Vector2(HERO_SPRITE_SIZE / 2, HERO_SPRITE_SIZE / 2)

# -------------------------------------------------------
# Save zone — an "extraction point" you channel at to bank held gear.
# Relocates randomly on its own timer, and again immediately after a
# successful bank, so it's never something you can just camp forever.
# Placeholder ground marker for now — swap save_zone_node's visuals
# for real art/animation once available, the position/timing logic
# underneath won't need to change.
# -------------------------------------------------------
func _relocate_save_zone() -> void:
	save_zone_pos = Vector2(
		randf_range(ARENA_WALL_T + 150, ARENA_W - ARENA_WALL_T - 150),
		randf_range(ARENA_WALL_T + 150, ARENA_H - ARENA_WALL_T - 150)
	)
	save_zone_relocate_timer = SAVE_ZONE_RELOCATE_INTERVAL
	save_zone_channel_progress = 0.0
	_build_save_zone_visual()

func _build_save_zone_visual() -> void:
	if save_zone_node and is_instance_valid(save_zone_node):
		save_zone_node.queue_free()
	if save_zone_label and is_instance_valid(save_zone_label):
		save_zone_label.queue_free()

	save_zone_node = ColorRect.new()
	save_zone_node.size = Vector2(SAVE_ZONE_RADIUS * 2, SAVE_ZONE_RADIUS * 2)
	save_zone_node.position = save_zone_pos - Vector2(SAVE_ZONE_RADIUS, SAVE_ZONE_RADIUS)
	save_zone_node.color = C_SAVE_ZONE
	arena_node.add_child(save_zone_node)
	arena_node.move_child(save_zone_node, 1)   # draws above the floor; never visually overlaps the border walls since the zone always spawns well inside them

	save_zone_label = Label.new()
	save_zone_label.text = "Excavation Site"
	save_zone_label.add_theme_font_size_override("font_size", 12)
	save_zone_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	save_zone_label.position = save_zone_pos - Vector2(SAVE_ZONE_RADIUS, SAVE_ZONE_RADIUS + 20)
	arena_node.add_child(save_zone_label)

# Called every frame from _process(). Handles the relocation timer,
# whether the player is currently inside the zone, and channel
# progress — stepping out resets progress to zero, but taking damage
# while still inside does not interrupt the channel.
func _process_save_zone(delta: float) -> void:
	save_zone_relocate_timer -= delta
	if save_zone_relocate_timer <= 0:
		_relocate_save_zone()
		return

	var inside = hero_pos.distance_to(save_zone_pos) <= SAVE_ZONE_RADIUS
	if inside:
		save_zone_channel_progress += delta
		if save_zone_channel_progress >= SAVE_ZONE_CHANNEL_TIME:
			_bank_held_gear()
			return   # _relocate_save_zone() (called by _bank_held_gear) already resets progress
		if save_zone_node and is_instance_valid(save_zone_node):
			save_zone_node.color = C_SAVE_ZONE.lerp(Color(0.5, 1.0, 0.6, 0.6), save_zone_channel_progress / SAVE_ZONE_CHANNEL_TIME)
	else:
		if save_zone_channel_progress > 0.0 and save_zone_node and is_instance_valid(save_zone_node):
			save_zone_node.color = C_SAVE_ZONE
		save_zone_channel_progress = 0.0

	if save_zone_label and is_instance_valid(save_zone_label):
		if inside and save_zone_channel_progress > 0.0:
			save_zone_label.text = "Excavating... %d%%" % int(100.0 * save_zone_channel_progress / SAVE_ZONE_CHANNEL_TIME)
		else:
			save_zone_label.text = "Excavation Site"

# Moves everything currently held into the safe pool, then immediately
# relocates the zone — every successful bank also triggers a fresh move,
# so it's never something you can just camp at repeatedly.
func _bank_held_gear() -> void:
	var banked_count = run_gear.size()
	for gear in run_gear:
		banked_gear.append(gear)
	run_gear.clear()
	_refresh_hud()
	if banked_count > 0:
		_show_bank_notification(banked_count)
	_relocate_save_zone()

func _show_bank_notification(count: int) -> void:
	var lbl = Label.new()
	lbl.text = "Banked %d item%s!" % [count, "" if count == 1 else "s"]
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	lbl.position = hero_pos - Vector2(40, 50)
	arena_node.add_child(lbl)
	var tw = create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 30, 1.2)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.2)
	tw.tween_callback(lbl.queue_free)

func _add_rect(parent: Node, pos: Vector2, sz: Vector2, col: Color) -> ColorRect:
	var r = ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = col
	parent.add_child(r)
	return r

# -------------------------------------------------------
# Enemies
# -------------------------------------------------------
# -------------------------------------------------------
# Enemy spawning — picks an archetype by weight (respecting the
# Ranged time-gate), then scales its stats by time survived, distance
# from the arena center, and current enemy density.
# -------------------------------------------------------
func _get_available_archetypes() -> Dictionary:
	# Sandbox weight override — any archetype with a non-zero weight in
	# AdminPanel.dungeon_sandbox replaces the normal pool entirely.
	if Engine.has_singleton("AdminPanel"):
		var sb = Engine.get_singleton("AdminPanel").dungeon_sandbox
		if sb.get("enabled", false):
			var overrides = sb.get("spawn_weights", {})
			var custom: Dictionary = {}
			for arch in overrides:
				if overrides[arch] > 0:
					custom[arch] = overrides[arch]
			if not custom.is_empty():
				return custom
	if ranged_unlocked:
		return ARCHETYPE_WEIGHTS
	var without_ranged = ARCHETYPE_WEIGHTS.duplicate()
	without_ranged.erase("RANGED")
	return without_ranged

func _roll_archetype() -> String:
	var weights = _get_available_archetypes()
	var total = 0
	for w in weights.values(): total += w
	var roll = randi() % total
	var cumulative = 0
	for archetype in weights:
		cumulative += weights[archetype]
		if roll < cumulative:
			return archetype
	return "MELEE"

# Combined difficulty multipliers — used for both regular spawns and
# as the base mini-bosses scale further on top of.
func _scaled_minutes() -> float:
	var mult = 1.0
	if Engine.has_singleton("AdminPanel"):
		mult = Engine.get_singleton("AdminPanel").dungeon_sandbox.get("scaling_mult", 1.0)
	return elapsed_seconds * mult / 60.0

func _get_hp_scale() -> float:
	var minutes = _scaled_minutes()
	var dist_from_center = hero_pos.distance_to(Vector2(ARENA_W/2, ARENA_H/2))
	var time_mult = 1.0 + minutes * ENEMY_HP_PER_MIN_PCT
	var dist_mult = 1.0 + (dist_from_center / 1000.0) * ENEMY_HP_PER_1000_DIST_PCT
	return time_mult * dist_mult

func _get_dmg_scale() -> float:
	return 1.0 + _scaled_minutes() * ENEMY_DMG_PER_MIN_PCT

func _get_speed_scale() -> float:
	return 1.0 + _scaled_minutes() * ENEMY_SPEED_PER_MIN_PCT

func _spawn_enemy_wave(count: int) -> void:
	var stage = PlayerInventory.current_stage
	var tier_mult = {"Quick": 0.8, "Standard": 1.0, "Deep Delve": 1.4}.get(PlayerInventory.dungeon_tier, 1.0)
	var hp_scale = _get_hp_scale()
	var dmg_scale = _get_dmg_scale()
	var speed_scale = _get_speed_scale()

	# Sandbox overrides — stack on top of the normal scaling so you can
	# push individual axes without affecting the others.
	if Engine.has_singleton("AdminPanel"):
		var sb = Engine.get_singleton("AdminPanel").dungeon_sandbox
		if sb.get("enabled", false):
			hp_scale *= sb.get("hp_mult", 1.0)
			dmg_scale *= sb.get("dmg_mult", 1.0)
			speed_scale *= sb.get("speed_mult", 1.0)

	for i in range(count):
		var archetype = _roll_archetype()
		_spawn_one_enemy(archetype, stage, tier_mult, hp_scale, dmg_scale, speed_scale, false)

func _spawn_one_enemy(archetype: String, stage: int, tier_mult: float, hp_scale: float, dmg_scale: float, speed_scale: float, is_miniboss: bool, miniboss_unique: bool = false) -> void:
	var profile = ARENA_ARCHETYPES.get(archetype, ARENA_ARCHETYPES["MELEE"])

	var base_sz = 28.0
	var base_hp  = (ENEMY_HP_BASE    + stage * ENEMY_HP_PER_STAGE)    * tier_mult * profile["hp_mult"]
	var base_spd = (ENEMY_SPEED_BASE + stage * ENEMY_SPEED_PER_STAGE) * profile["speed_mult"]
	var base_atk = (ENEMY_ATK_BASE   + stage * ENEMY_ATK_PER_STAGE)   * tier_mult * profile["dmg_mult"]

	var sz = base_sz
	var max_hp = int(base_hp * hp_scale)
	var spd = base_spd * speed_scale
	var atk = int(base_atk * dmg_scale)

	if is_miniboss:
		sz *= MINIBOSS_EMPOWERED_SIZE_MULT
		max_hp = int(max_hp * MINIBOSS_EMPOWERED_HP_MULT)
		atk = int(atk * MINIBOSS_EMPOWERED_DMG_MULT)

	var ex: float
	var ey: float
	var tries = 0
	while true:
		ex = randf_range(hero_pos.x - 500, hero_pos.x + 500)
		ey = randf_range(hero_pos.y - 500, hero_pos.y + 500)
		ex = clamp(ex, ARENA_WALL_T + 80, ARENA_W - ARENA_WALL_T - 80)
		ey = clamp(ey, ARENA_WALL_T + 80, ARENA_H - ARENA_WALL_T - 80)
		tries += 1
		if hero_pos.distance_to(Vector2(ex, ey)) >= MIN_SPAWN_DIST_FROM_HERO or tries >= 20:
			break
	var epos = Vector2(ex, ey)

	var display_color = profile["color"]
	if is_miniboss:
		display_color = Color(1.0, 0.1, 0.1) if miniboss_unique else display_color.lightened(0.3)

	var erect = UnitSprite.new()
	var enemy_unit_type = ARCHETYPE_UNIT_TYPES.get(archetype, UnitSprite.UnitType.ENEMY_BASIC)
	erect.setup(enemy_unit_type, display_color, sz)
	erect.position = epos - Vector2(sz/2, sz/2)
	arena_node.add_child(erect)

	var hp_bar_bg = null
	var hp_bar = null
	if is_miniboss:
		hp_bar_bg = ColorRect.new()
		hp_bar_bg.size = Vector2(80, 8)
		hp_bar_bg.color = Color(0.3, 0.1, 0.1)
		hp_bar_bg.position = epos - Vector2(40, sz/2 + 16)
		arena_node.add_child(hp_bar_bg)

		hp_bar = ColorRect.new()
		hp_bar.size = Vector2(80, 8)
		hp_bar.color = Color(0.9, 0.2, 0.2)
		hp_bar.position = epos - Vector2(40, sz/2 + 16)
		arena_node.add_child(hp_bar)

	var e = {
		"eid": _enemy_id_counter,
		"pos": epos, "hp": max_hp, "max_hp": max_hp,
		"speed": spd, "attack": atk,
		"shoot_t": randf_range(1.5, 3.0),
		"archetype": archetype,
		"is_boss": is_miniboss, "is_miniboss_unique": miniboss_unique, "sz": sz,
		"boss_p": 0, "boss_t": 2.0, "boss_a": 0.0,
		"hp_bar": hp_bar, "hp_bar_bg": hp_bar_bg,
		# Bull-specific charge state
		"bull_state": "seeking",   # seeking -> winding_up -> charging -> recovering
		"bull_state_t": 0.0,
		"bull_charge_dir": Vector2.ZERO,
		"bull_charge_traveled": 0.0,
		# Buffer-specific
		"buff_t": BUFFER_BUFF_INTERVAL,
		"dmg_boost_t": 0.0,
	}
	_enemy_id_counter += 1
	enemies.append(e)
	enemy_rects.append(erect)

# -------------------------------------------------------
# Process loop
# -------------------------------------------------------
func _process(delta: float) -> void:
	if game_over: return
	if is_paused: return

	elapsed_seconds += delta
	if elapsed_seconds >= run_duration_seconds:
		_on_survival_complete()
		return

	_move_hero(delta)
	_attack_tick(delta)
	_move_projectiles(delta)
	_process_enemies(delta)
	_process_spawn_timer(delta)
	_process_save_zone(delta)
	_update_orbs(delta)
	_self_heal_tick(delta)
	_update_visuals()
	_refresh_hud()

# Reaching the chosen survival duration is a genuine win — all
# currently-held (unbanked) gear is treated as successfully extracted
# along with anything already banked, since making it to the end alive
# is itself the win condition the save zone risk was building toward.
func _on_survival_complete() -> void:
	game_over = true
	Telemetry.log_event("dungeon_result", {
		"outcome": "survived",
		"kills": kill_count,
		"level_reached": hero_level,
		"skills": skills_taken.keys(),
		"gear_secured": secured_gear.size() + banked_gear.size() + run_gear.size(),
	})
	for gear in banked_gear:
		PlayerInventory.add_gear(gear)
		secured_gear.append(gear)
	for gear in run_gear:
		PlayerInventory.add_gear(gear)
		secured_gear.append(gear)
	run_gear.clear()
	banked_gear.clear()
	_show_end_screen("survived")

# Basic continuous spawn placeholder for Step 1 testing — fixed
# interval and count for now. Step 2 replaces this with the real
# time-based ramp using the SPAWN_* constants up top.
func _process_spawn_timer(delta: float) -> void:
	if not ranged_unlocked and _scaled_minutes() >= RANGED_UNLOCK_MINUTE:
		ranged_unlocked = true

	spawn_timer -= delta
	if spawn_timer <= 0:
		var minutes = _scaled_minutes()
		var interval = max(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_START - minutes * SPAWN_INTERVAL_RAMP_PER_MIN)
		# Density slowdown — if the screen is already crowded, ease off
		# spawning more rather than piling stat-boosted enemies on top
		# of an already-overwhelming fight.
		if enemies.size() >= DENSITY_SPAWN_SLOWDOWN_THRESHOLD:
			interval *= DENSITY_SPAWN_SLOWDOWN_MULT
		spawn_timer = interval

		var count = min(SPAWN_COUNT_MAX, SPAWN_COUNT_START + int(minutes * SPAWN_COUNT_PER_MIN))
		_spawn_enemy_wave(count)

	_process_miniboss_timer(delta)

# Mini-bosses are paced by a mix of time and kills — staying aggressive
# and clearing enemies speeds up the next one rather than just waiting.
func _process_miniboss_timer(delta: float) -> void:
	miniboss_timer -= delta
	if miniboss_timer <= 0:
		miniboss_timer = MINIBOSS_BASE_INTERVAL_SECONDS
		_spawn_miniboss()

func _spawn_miniboss() -> void:
	var stage = PlayerInventory.current_stage
	var tier_mult = {"Quick": 0.8, "Standard": 1.0, "Deep Delve": 1.4}.get(PlayerInventory.dungeon_tier, 1.0)
	var hp_scale = _get_hp_scale()
	var dmg_scale = _get_dmg_scale()
	var speed_scale = _get_speed_scale()

	var is_unique = randf() < MINIBOSS_UNIQUE_CHANCE
	# Empowered mini-bosses are a bigger version of a normal type the
	# player already recognizes. Uniques pick from the same pool for now
	# but are flagged for a real attack pattern in _process_boss.
	var archetype = _roll_archetype()
	if archetype == "BUFFER":   # a giga-Buffer buffing a huge area isn't a fun "boss" moment — reroll once
		archetype = _roll_archetype()

	_spawn_one_enemy(archetype, stage, tier_mult, hp_scale, dmg_scale, speed_scale, true, is_unique)

# Healer's passive sustain — periodically heals a % of max HP. This is
# Healer's actual strength in the dungeon despite being the weakest
# attacker by far: outlasting a fight rather than winning it quickly.
func _self_heal_tick(delta: float) -> void:
	if hero_hp <= 0: return
	# Healer class passive heal
	if hero_self_heal:
		self_heal_timer -= delta
		if self_heal_timer <= 0:
			self_heal_timer = HEALER_SELF_HEAL_INTERVAL
			var healed = max(1, int(hero_max_hp * HEALER_SELF_HEAL_PCT))
			hero_hp = min(hero_hp + healed, hero_max_hp)
			_refresh_hud()
	# hp_regen gear stat (all classes)
	if hero_hp_regen > 0.0 and hero_hp < hero_max_hp:
		hero_hp = min(hero_hp + int(hero_hp_regen * delta), hero_max_hp)

const MOUSE_MOVE_DEAD_ZONE = 20.0   # pixels from target before hero stops

func _move_hero(delta: float) -> void:
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if _dpad and dir == Vector2.ZERO:
		dir = _dpad.get_direction()

	if dir != Vector2.ZERO:
		_has_mouse_target = false   # keyboard / dpad cancels any pending click-target
	elif _has_mouse_target:
		var to_target = _mouse_target - hero_pos
		if to_target.length() > MOUSE_MOVE_DEAD_ZONE:
			dir = to_target.normalized()
		else:
			_has_mouse_target = false

	var is_moving = dir.length() > 0

	if hero_rect:
		hero_rect.set_moving(is_moving)
		if is_moving:
			hero_rect.face(dir)

	hero_pos += dir * hero_speed * delta

	# Clamp inside the arena's solid border — no doors, no exits
	hero_pos.x = clamp(hero_pos.x, ARENA_WALL_T + 12, ARENA_W - ARENA_WALL_T - 12)
	hero_pos.y = clamp(hero_pos.y, ARENA_WALL_T + 12, ARENA_H - ARENA_WALL_T - 12)

	# Camera follows the hero, scrolling the arena as they move — this
	# is the core Vampire Survivors feel: the world is much bigger than
	# any single screen, and the view stays centered on the player.
	if camera:
		camera.position = hero_pos

	# Invincibility frames
	if invincible_timer > 0:
		invincible_timer -= get_process_delta_time()

func _attack_tick(delta: float) -> void:
	attack_timer -= delta
	if attack_timer > 0 or enemies.is_empty(): return

	var nearest = null
	var nearest_dist = INF
	for e in enemies:
		var d = hero_pos.distance_to(e["pos"])
		if d < nearest_dist:
			nearest_dist = d
			nearest = e

	if nearest and nearest_dist <= hero_attack_range:
		var effective_interval = hero_attack_interval
		if skill_berserker:
			var missing_pct = 1.0 - float(hero_hp) / float(hero_max_hp)
			effective_interval *= max(0.60, 1.0 - missing_pct * 0.40)
		attack_timer = effective_interval

		var dmg = hero_attack
		if hero_is_melee and hero_melee_power > 0.0:
			dmg = int(dmg * (1.0 + hero_melee_power))
		var is_crit = randf() < hero_crit_chance
		if is_crit:
			dmg = int(dmg * (1.0 + hero_crit_damage / 100.0))

		if hero_is_melee:
			# Collect targets first (safe: avoid modifying enemies during iteration)
			var targets: Array = [nearest]
			if skill_extra_projs > 0:
				var extra = skill_extra_projs
				for e in enemies:
					if extra <= 0: break
					if e == nearest: continue
					if hero_pos.distance_to(e["pos"]) <= hero_attack_range:
						targets.append(e)
						extra -= 1
			if hero_rect and is_instance_valid(hero_rect):
				hero_rect.face((nearest["pos"] - hero_pos).normalized())
				hero_rect.play_attack()
			for t in targets:
				_melee_strike(t, dmg)
		else:
			_fire(hero_pos, nearest["pos"], true, dmg, hero_rect)
			# Multishot: additional projectiles with a small angular spread
			for k in range(skill_extra_projs):
				var sign = 1 if k % 2 == 0 else -1
				var spread = deg_to_rad(18.0 * (k / 2 + 1) * sign)
				var base_dir = (nearest["pos"] - hero_pos).normalized()
				var spread_target = hero_pos + base_dir.rotated(spread) * 200.0
				_fire(hero_pos, spread_target, true, dmg, null)

		# Storm Aegis 4-piece: crits arc to the nearest other enemy for 40% damage
		if is_crit and hero_chain_crit:
			var chain_target = null
			var chain_dist = INF
			for e in enemies:
				if e == nearest: continue
				var d = hero_pos.distance_to(e["pos"])
				if d < chain_dist:
					chain_dist = d
					chain_target = e
			if chain_target:
				_melee_strike(chain_target, int(dmg * 0.40))

func _melee_strike(e: Dictionary, dmg: int) -> void:
	var eidx = enemies.find(e)
	if eidx < 0: return  # already dead/removed

	e["hp"] -= dmg
	_update_boss_bar(e)

	if skill_lifesteal > 0.0:
		hero_hp = min(hero_hp + max(1, int(dmg * skill_lifesteal)), hero_max_hp)
	if skill_explosive:
		_trigger_explosion(e["pos"], int(dmg * 0.4), eidx)

	var flash = ColorRect.new()
	flash.size = Vector2(22, 22)
	flash.color = Color(1.0, 0.95, 0.4, 0.9)
	flash.position = e["pos"] - Vector2(11, 11)
	arena_node.add_child(flash)
	var tw = flash.create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.15)
	tw.tween_callback(flash.queue_free)

	if e["hp"] <= 0:
		var kill_idx = enemies.find(e)
		if kill_idx >= 0:
			_kill_enemy(kill_idx)

func _fire(from: Vector2, toward: Vector2, is_hero: bool, dmg: int, attacker_sprite: UnitSprite = null) -> void:
	var dir = (toward - from).normalized()
	var proj = {"pos": Vector2(from.x, from.y), "origin": Vector2(from.x, from.y),
				"dir": dir, "damage": dmg, "is_hero": is_hero, "pierced": {}}

	if attacker_sprite and is_instance_valid(attacker_sprite):
		attacker_sprite.face(dir)
		attacker_sprite.play_attack()

	var prect = ColorRect.new()
	prect.size = Vector2(10, 10)
	prect.color = C_PROJ_H if is_hero else C_PROJ_E
	prect.position = from - Vector2(5, 5)
	arena_node.add_child(prect)

	if is_hero:
		hero_projs.append(proj)
		hero_proj_rects.append(prect)
	else:
		enemy_projs.append(proj)
		enemy_proj_rects.append(prect)

func _move_projectiles(delta: float) -> void:
	# Hero projectiles
	var new_hprojs = []
	var new_hprects = []
	for i in range(hero_projs.size()):
		var p = hero_projs[i]
		var pr = hero_proj_rects[i]
		p["pos"] += p["dir"] * PROJECTILE_SPEED * delta

		var oob = p["pos"].distance_to(p["origin"]) > PROJECTILE_MAX_RANGE
		if oob:
			if is_instance_valid(pr): pr.queue_free()
			continue

		var consumed = false
		var to_kill: Array = []
		# Iterate descending so later removals don't shift earlier indices
		for ei in range(enemies.size() - 1, -1, -1):
			var eid = enemies[ei].get("eid", -1)
			# Piercing: skip enemies this projectile already passed through
			if skill_piercing and p["pierced"].has(eid):
				continue
			if p["pos"].distance_to(enemies[ei]["pos"]) < enemies[ei]["sz"] / 2 + 5:
				var dmg = p["damage"]
				enemies[ei]["hp"] -= dmg
				_update_boss_bar(enemies[ei])
				if skill_lifesteal > 0.0:
					hero_hp = min(hero_hp + max(1, int(dmg * skill_lifesteal)), hero_max_hp)
				if skill_explosive:
					_trigger_explosion(enemies[ei]["pos"], int(dmg * 0.4), ei)
				if enemies[ei]["hp"] <= 0:
					to_kill.append(ei)
				if skill_piercing:
					p["pierced"][eid] = true   # mark but keep projectile alive
				else:
					if is_instance_valid(pr): pr.queue_free()
					consumed = true
					break
		# Kill collected enemies (indices are descending — safe removal order)
		for kill_idx in to_kill:
			if kill_idx < enemies.size():
				_kill_enemy(kill_idx)
		if not consumed:
			new_hprojs.append(p)
			new_hprects.append(pr)

	hero_projs = new_hprojs
	hero_proj_rects = new_hprects

	# Enemy projectiles (unchanged)
	var new_eprojs = []
	var new_eprects = []
	for i in range(enemy_projs.size()):
		var p = enemy_projs[i]
		var pr = enemy_proj_rects[i]
		p["pos"] += p["dir"] * (PROJECTILE_SPEED * 0.65) * delta

		var oob = p["pos"].distance_to(p["origin"]) > PROJECTILE_MAX_RANGE
		if oob:
			if is_instance_valid(pr): pr.queue_free()
			continue

		if invincible_timer <= 0 and p["pos"].distance_to(hero_pos) < 16:
			_take_damage(p["damage"])
			if is_instance_valid(pr): pr.queue_free()
		else:
			new_eprojs.append(p)
			new_eprects.append(pr)

	enemy_projs = new_eprojs
	enemy_proj_rects = new_eprects

func _process_enemies(delta: float) -> void:
	# Iterate backwards — _kill_enemy_no_loot / _kill_enemy remove the
	# element at the given index, which would shift all higher indices down
	# and leave the original range() count stale. Iterating backwards means
	# any removal only affects already-processed (higher) indices, so the
	# remaining (lower) indices stay valid for the rest of the loop.
	for i in range(enemies.size() - 1, -1, -1):
		var e = enemies[i]
		var e_sprite = enemy_rects[i] if i < enemy_rects.size() else null

		if e["is_boss"] and e["is_miniboss_unique"]:
			# Rare unique mini-bosses get a real attack pattern on top of
			# their bigger stats, reusing the same boss-pattern system.
			_process_boss(e, delta, e_sprite)
			continue

		var archetype = e.get("archetype", "MELEE")
		match archetype:
			"BULL":
				_process_bull(e, delta, e_sprite)
			"RANGED":
				_process_ranged(e, delta, e_sprite)
			"BUFFER":
				_process_buffer(e, delta, e_sprite)
			_:
				_process_homing_melee(e, delta, e_sprite, i)

# Melee and Charger share this — continuously home in on the player.
# Charger is meant to feel like a suicide bomber: relentless tracking,
# but it can be kited, baited, or killed before it closes the gap.
func _process_homing_melee(e: Dictionary, delta: float, e_sprite: UnitSprite, idx: int) -> void:
	var effective_atk = e["attack"]
	if e.get("dmg_boost_t", 0.0) > 0.0:
		e["dmg_boost_t"] -= delta
		effective_atk = int(effective_atk * (1.0 + BUFFER_DMG_BOOST_PCT))

	var move_dir = (hero_pos - e["pos"]).normalized()
	e["pos"] += move_dir * e["speed"] * delta
	e["pos"].x = clamp(e["pos"].x, ARENA_WALL_T + e["sz"]/2, ARENA_W - ARENA_WALL_T - e["sz"]/2)
	e["pos"].y = clamp(e["pos"].y, ARENA_WALL_T + e["sz"]/2, ARENA_H - ARENA_WALL_T - e["sz"]/2)
	if e_sprite and is_instance_valid(e_sprite):
		e_sprite.set_moving(true)
		e_sprite.face(move_dir)

	if invincible_timer <= 0 and e["pos"].distance_to(hero_pos) < e["sz"]/2 + 14:
		_take_damage(effective_atk)
		if e.get("archetype", "") == "CHARGER":
			# Detonates on contact, suicide-bomber style
			_kill_enemy_no_loot(idx)

# Ranged holds distance and fires from range rather than closing in —
# this is exactly why it's time-gated: dangerous in a crowd, fine alone.
func _process_ranged(e: Dictionary, delta: float, e_sprite: UnitSprite) -> void:
	var effective_atk = e["attack"]
	if e.get("dmg_boost_t", 0.0) > 0.0:
		e["dmg_boost_t"] -= delta
		effective_atk = int(effective_atk * (1.0 + BUFFER_DMG_BOOST_PCT))

	var dist = e["pos"].distance_to(hero_pos)
	if dist > RANGED_ATTACK_RANGE:
		var move_dir = (hero_pos - e["pos"]).normalized()
		e["pos"] += move_dir * e["speed"] * delta
		e["pos"].x = clamp(e["pos"].x, ARENA_WALL_T + e["sz"]/2, ARENA_W - ARENA_WALL_T - e["sz"]/2)
		e["pos"].y = clamp(e["pos"].y, ARENA_WALL_T + e["sz"]/2, ARENA_H - ARENA_WALL_T - e["sz"]/2)
		if e_sprite and is_instance_valid(e_sprite):
			e_sprite.set_moving(true)
			e_sprite.face(move_dir)
	elif e_sprite and is_instance_valid(e_sprite):
		e_sprite.set_moving(false)

	e["shoot_t"] -= delta
	if e["shoot_t"] <= 0 and dist <= RANGED_ATTACK_RANGE:
		_fire(e["pos"], hero_pos, false, effective_atk, e_sprite)
		e["shoot_t"] = randf_range(1.6, 2.4)

# Buffer doesn't attack the player at all — it periodically grants
# nearby enemies a temporary damage boost, making it the priority kill
# whenever it shows up.
func _process_buffer(e: Dictionary, delta: float, e_sprite: UnitSprite = null) -> void:
	var dist = e["pos"].distance_to(hero_pos)
	if dist > BUFFER_AURA_RANGE * 1.5:
		var move_dir = (hero_pos - e["pos"]).normalized()
		e["pos"] += move_dir * e["speed"] * delta * 0.7
		e["pos"].x = clamp(e["pos"].x, ARENA_WALL_T + e["sz"]/2, ARENA_W - ARENA_WALL_T - e["sz"]/2)
		e["pos"].y = clamp(e["pos"].y, ARENA_WALL_T + e["sz"]/2, ARENA_H - ARENA_WALL_T - e["sz"]/2)
		if e_sprite and is_instance_valid(e_sprite):
			e_sprite.set_moving(true)
			e_sprite.face(move_dir)
	elif e_sprite and is_instance_valid(e_sprite):
		e_sprite.set_moving(false)

	e["buff_t"] -= delta
	if e["buff_t"] <= 0:
		e["buff_t"] = BUFFER_BUFF_INTERVAL
		for other in enemies:
			if other == e: continue
			if e["pos"].distance_to(other["pos"]) <= BUFFER_AURA_RANGE:
				other["dmg_boost_t"] = BUFFER_DMG_BOOST_DURATION

# Bull — winds up with a visible telegraph (color flash for now; swap
# for a real animation/glow once art exists), then commits to a fixed
# straight line regardless of where the player moves afterward. This is
# what makes it dodgeable rather than an inescapable homing threat.
func _process_bull(e: Dictionary, delta: float, e_sprite: UnitSprite) -> void:
	var effective_atk = e["attack"]
	if e.get("dmg_boost_t", 0.0) > 0.0:
		e["dmg_boost_t"] -= delta
		effective_atk = int(effective_atk * (1.0 + BUFFER_DMG_BOOST_PCT))

	match e["bull_state"]:
		"seeking":
			var move_dir = (hero_pos - e["pos"]).normalized()
			e["pos"] += move_dir * e["speed"] * delta * 0.6   # slower while seeking, the charge is the real threat
			e["pos"].x = clamp(e["pos"].x, ARENA_WALL_T + e["sz"]/2, ARENA_W - ARENA_WALL_T - e["sz"]/2)
			e["pos"].y = clamp(e["pos"].y, ARENA_WALL_T + e["sz"]/2, ARENA_H - ARENA_WALL_T - e["sz"]/2)
			if e_sprite and is_instance_valid(e_sprite):
				e_sprite.set_moving(true)
				e_sprite.face(move_dir)
			if e["pos"].distance_to(hero_pos) < 600:
				e["bull_state"] = "winding_up"
				e["bull_state_t"] = BULL_WINDUP_TIME
				e["bull_charge_dir"] = (hero_pos - e["pos"]).normalized()
				if e_sprite and is_instance_valid(e_sprite):
					e_sprite.set_color(Color(1, 1, 0.3))   # telegraph flash — placeholder until real art/animation
					e_sprite.set_moving(false)   # plants and braces during the windup

		"winding_up":
			e["bull_state_t"] -= delta
			if e["bull_state_t"] <= 0:
				e["bull_state"] = "charging"
				e["bull_charge_traveled"] = 0.0
				if e_sprite and is_instance_valid(e_sprite):
					e_sprite.set_color(ARENA_ARCHETYPES["BULL"]["color"])
					e_sprite.set_moving(true)
					e_sprite.face(e["bull_charge_dir"])

		"charging":
			var move = e["bull_charge_dir"] * BULL_CHARGE_SPEED * delta
			e["pos"] += move
			e["bull_charge_traveled"] += move.length()
			e["pos"].x = clamp(e["pos"].x, ARENA_WALL_T + e["sz"]/2, ARENA_W - ARENA_WALL_T - e["sz"]/2)
			e["pos"].y = clamp(e["pos"].y, ARENA_WALL_T + e["sz"]/2, ARENA_H - ARENA_WALL_T - e["sz"]/2)
			if invincible_timer <= 0 and e["pos"].distance_to(hero_pos) < e["sz"]/2 + 14:
				_take_damage(effective_atk)
			if e["bull_charge_traveled"] >= BULL_CHARGE_DISTANCE:
				e["bull_state"] = "recovering"
				e["bull_state_t"] = BULL_RECOVER_TIME
				if e_sprite and is_instance_valid(e_sprite):
					e_sprite.set_moving(false)

		"recovering":
			e["bull_state_t"] -= delta
			if e["bull_state_t"] <= 0:
				e["bull_state"] = "seeking"

# Charger detonates on contact rather than dying for loot like a normal
# kill — it's a hazard, not a farmable enemy in the same sense.
func _kill_enemy_no_loot(idx: int) -> void:
	var e = enemies[idx]
	var er = enemy_rects[idx]
	if is_instance_valid(er): er.queue_free()
	if e["hp_bar"] != null and is_instance_valid(e["hp_bar"]):
		e["hp_bar"].queue_free()
	if e["hp_bar_bg"] != null and is_instance_valid(e["hp_bar_bg"]):
		e["hp_bar_bg"].queue_free()
	enemies.remove_at(idx)
	enemy_rects.remove_at(idx)

func _process_boss(e: Dictionary, delta: float, e_sprite: UnitSprite = null) -> void:
	e["boss_t"] -= delta
	e["boss_a"] += delta * 120.0

	if e["boss_t"] <= 0:
		var pattern = e["boss_p"] % 3
		match pattern:
			0:  # Ring of 8
				for i in range(8):
					var angle = deg_to_rad(i * 45.0)
					_fire(e["pos"], e["pos"] + Vector2(cos(angle), sin(angle)) * 80, false, e["attack"], e_sprite)
				e["boss_t"] = 2.5
				e["boss_p"] += 1
			1:  # Spiral
				for i in range(3):
					var angle = deg_to_rad(e["boss_a"] + i * 120.0)
					_fire(e["pos"], e["pos"] + Vector2(cos(angle), sin(angle)) * 80, false, e["attack"], e_sprite)
				e["boss_t"] = 0.15
				if e["boss_a"] > 360.0:
					e["boss_a"] = 0.0
					e["boss_p"] += 1
					e["boss_t"] = 2.0
			2:  # Aimed burst of 5
				for i in range(5):
					var spread = deg_to_rad((i - 2) * 18.0)
					var base_dir = (hero_pos - e["pos"]).normalized()
					var rot = base_dir.rotated(spread)
					_fire(e["pos"], e["pos"] + rot * 80, false, e["attack"], e_sprite)
				e["boss_t"] = 2.0
				e["boss_p"] += 1

	# Unique mini-bosses still move toward the player between attack
	# patterns, same as the homing melee behavior, just without the
	# Charger-style detonate-on-contact.
	var move_dir = (hero_pos - e["pos"]).normalized()
	e["pos"] += move_dir * e["speed"] * delta * 0.5
	e["pos"].x = clamp(e["pos"].x, ARENA_WALL_T + e["sz"]/2, ARENA_W - ARENA_WALL_T - e["sz"]/2)
	e["pos"].y = clamp(e["pos"].y, ARENA_WALL_T + e["sz"]/2, ARENA_H - ARENA_WALL_T - e["sz"]/2)
	if e_sprite and is_instance_valid(e_sprite):
		e_sprite.set_moving(true)
		e_sprite.face(move_dir)
	if invincible_timer <= 0 and e["pos"].distance_to(hero_pos) < e["sz"]/2 + 14:
		_take_damage(e["attack"])

func _update_boss_bar(e: Dictionary) -> void:
	if e["hp_bar"] == null or not is_instance_valid(e["hp_bar"]): return
	var pct = float(e["hp"]) / float(e["max_hp"])
	e["hp_bar"].size.x = 80.0 * pct

func _kill_enemy(idx: int) -> void:
	var e = enemies[idx]
	var death_pos = e["pos"]
	var er = enemy_rects[idx]
	if is_instance_valid(er): er.queue_free()

	if e["hp_bar"] != null and is_instance_valid(e["hp_bar"]):
		e["hp_bar"].queue_free()
	if e["hp_bar_bg"] != null and is_instance_valid(e["hp_bar_bg"]):
		e["hp_bar_bg"].queue_free()

	enemies.remove_at(idx)
	enemy_rects.remove_at(idx)

	kill_count += 1
	miniboss_timer = max(10.0, miniboss_timer - MINIBOSS_KILLS_REDUCE_TIMER_BY)
	if PlayerInventory.unlocked_talents.get("dungeon_treasure_hunter", false) and randf() < 0.10:
		PlayerInventory.resources["gold"] = PlayerInventory.resources.get("gold", 0) + 1

	# Roguelite: XP grant
	var xp_gain = XP_PER_BOSS_KILL if e["is_boss"] else XP_PER_NORMAL_KILL
	_grant_xp(xp_gain)

	# Vampiric skill + on_kill_heal gear stat both heal on kill
	if skill_vampiric_hp > 0:
		hero_hp = min(hero_hp + skill_vampiric_hp, hero_max_hp)
	if hero_on_kill_heal > 0:
		hero_hp = min(hero_hp + hero_on_kill_heal, hero_max_hp)

	# Death Rattle: small AoE explosion at the kill site
	if skill_death_rattle:
		_trigger_explosion(death_pos, max(3, int(hero_attack * 0.2)))

	# Gear drop (background — player sees at end screen)
	var drop_chance = min(1.0, (1.0 if e["is_boss"] else 0.16) + skill_drop_bonus)
	if randf() < drop_chance:
		var diff = clamp(PlayerInventory.current_stage + (MINIBOSS_GUARANTEED_RARITY_BOOST if e["is_boss"] else 0), 1, 10)
		if PlayerInventory.dungeon_tier == "Deep Delve":
			diff = clamp(diff + 1, 1, 10)
		var biomes = ["crypt","forest_ruins","dragon_lair"]
		var gear = GearGenerator.generate(biomes[randi() % biomes.size()], diff)
		run_gear.append(gear)
		_refresh_hud()

func _take_damage(amount: int) -> void:
	if _sandbox_god_mode or invincible_timer > 0 or is_paused: return
	if hero_dodge_chance > 0.0 and randf() < hero_dodge_chance: return
	var reduced = max(1, amount - int(hero_armor * 0.5))

	# Iron Will: one-time kill-blow intercept from the talent tree
	if not iron_will_used and PlayerInventory.unlocked_talents.get("dungeon_iron_will", false) and (hero_hp - reduced) <= 0:
		iron_will_used = true
		hero_hp = 1
		invincible_timer = 1.5
		_refresh_hud()
		return

	# Second Wind: intercept a killing blow before HP hits 0
	if skill_second_wind_ready and (hero_hp - reduced) <= 0:
		skill_second_wind_ready = false
		hero_hp = int(hero_max_hp * SKILL_SECOND_WIND_REVIVE_PCT)
		invincible_timer = 1.5
		_refresh_hud()
		_show_second_wind_notification()
		return

	hero_hp -= reduced
	hero_hp = max(0, hero_hp)
	invincible_timer = 0.6
	_refresh_hud()

	# Nova Burst: retaliate with a damaging pulse
	if skill_nova:
		_trigger_explosion(hero_pos, max(5, int(hero_attack * 0.5)))

	if hero_hp <= 0 and not game_over:
		game_over = true
		_play_death_visual()

# A brief defeated flash before the run actually ends — placeholder
# until real death art/animation exists. The world keeps running
# during this; only the player's own sprite is affected.
func _play_death_visual() -> void:
	if hero_rect and is_instance_valid(hero_rect):
		hero_rect.set_color(Color(0.15, 0.15, 0.15))
	var tw = create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(_on_death_resolved)

func _on_death_resolved() -> void:
	Telemetry.log_event("dungeon_result", {
		"outcome": "died",
		"kills": kill_count,
		"level_reached": hero_level,
		"skills": skills_taken.keys(),
		"gear_secured": secured_gear.size(),
	})
	_apply_death_penalty()
	_show_end_screen("lost")

# Death is a worse outcome than retreating, on purpose: unbanked gear
# is forfeited entirely (same as retreat), AND roughly half of what
# was already banked is randomly lost too. Whatever survives the roll
# is still committed to the permanent inventory. The troop itself is
# never permanently killed — its persistent HP is set to a 1 HP floor
# outside the dungeon, mirroring the same no-permanent-death rule
# already used for defense battles.
func _apply_death_penalty() -> void:
	run_gear.clear()   # unbanked gear forfeited entirely, same as retreat

	var kept: Array = []
	var lost_count = 0
	for gear in banked_gear:
		if randf() < 0.5:
			lost_count += 1
		else:
			kept.append(gear)
	banked_gear = kept

	for gear in banked_gear:
		PlayerInventory.add_gear(gear)
		secured_gear.append(gear)
	banked_gear.clear()

# -------------------------------------------------------
# Visual updates each frame
# -------------------------------------------------------
func _update_visuals() -> void:
	if hero_rect and is_instance_valid(hero_rect):
		hero_rect.position = hero_pos - Vector2(HERO_SPRITE_SIZE / 2, HERO_SPRITE_SIZE / 2)
		# Flash blue when invincible; show natural art colors otherwise
		if invincible_timer > 0:
			hero_rect.set_color(Color(1,1,1) if fmod(invincible_timer, 0.15) > 0.075 else C_HERO)
		else:
			hero_rect.set_color(Color.WHITE)

	for i in range(min(enemies.size(), enemy_rects.size())):
		var e = enemies[i]
		var er = enemy_rects[i]
		if is_instance_valid(er):
			er.position = e["pos"] - Vector2(e["sz"]/2, e["sz"]/2)
		if e["hp_bar"] != null and is_instance_valid(e["hp_bar"]):
			e["hp_bar"].position = e["pos"] - Vector2(40, 44)
		if e["hp_bar_bg"] != null and is_instance_valid(e["hp_bar_bg"]):
			e["hp_bar_bg"].position = e["pos"] - Vector2(40, 44)

	for i in range(min(hero_projs.size(), hero_proj_rects.size())):
		var pr = hero_proj_rects[i]
		if is_instance_valid(pr):
			pr.position = hero_projs[i]["pos"] - Vector2(5,5)

	for i in range(min(enemy_projs.size(), enemy_proj_rects.size())):
		var pr = enemy_proj_rects[i]
		if is_instance_valid(pr):
			pr.position = enemy_projs[i]["pos"] - Vector2(5,5)

# -------------------------------------------------------
# HUD
# -------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			_toggle_pause()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not game_over and not is_paused:
			_mouse_target = get_global_mouse_position()
			_has_mouse_target = true

func _toggle_pause() -> void:
	if game_over: return
	is_paused = not is_paused
	if pause_btn:
		pause_btn.text = "Resume" if is_paused else "Pause"
		pause_btn.add_theme_color_override("font_color",
			Color(0.4, 0.9, 0.4) if is_paused else Color(0.8, 0.8, 0.4))

func _build_hud() -> void:
	var hud = CanvasLayer.new()
	add_child(hud)

	var panel = PanelContainer.new()
	panel.position = Vector2(8, 8)
	hud.add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	hud_hp = Label.new()
	hud_hp.add_theme_font_size_override("font_size", 14)
	vbox.add_child(hud_hp)

	hud_timer = Label.new()
	hud_timer.add_theme_font_size_override("font_size", 13)
	hud_timer.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	vbox.add_child(hud_timer)

	hud_gear = Label.new()
	hud_gear.add_theme_font_size_override("font_size", 11)
	hud_gear.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2))
	vbox.add_child(hud_gear)

	hud_level = Label.new()
	hud_level.add_theme_font_size_override("font_size", 12)
	hud_level.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	vbox.add_child(hud_level)

	var controls = Label.new()
	controls.text = "Move: mouse cursor or WASD  |  P to pause"
	controls.add_theme_font_size_override("font_size", 10)
	controls.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(controls)

	pause_btn = Button.new()
	pause_btn.text = "Pause"
	pause_btn.custom_minimum_size = Vector2(0, 32)
	pause_btn.add_theme_font_size_override("font_size", 12)
	pause_btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	pause_btn.pressed.connect(_toggle_pause)
	vbox.add_child(pause_btn)

	var retreat_btn = Button.new()
	retreat_btn.text = "Retreat"
	retreat_btn.custom_minimum_size = Vector2(0, 32)
	retreat_btn.add_theme_font_size_override("font_size", 12)
	retreat_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
	retreat_btn.pressed.connect(_on_retreat_pressed)
	vbox.add_child(retreat_btn)

	_refresh_hud()

func _refresh_hud() -> void:
	if hud_hp:
		hud_hp.text = "HP: %d / %d" % [hero_hp, hero_max_hp]
		var col = Color(0.9,0.2,0.2) if hero_hp < hero_max_hp * 0.3 else (
			Color(0.9,0.7,0.2) if hero_hp < hero_max_hp * 0.6 else Color(0.3,0.9,0.3))
		hud_hp.add_theme_color_override("font_color", col)
	if hud_timer:
		var remaining = max(0, run_duration_seconds - elapsed_seconds)
		var mins = int(remaining) / 60
		var secs = int(remaining) % 60
		hud_timer.text = "Survive: %d:%02d" % [mins, secs]
	if hud_gear:
		hud_gear.text = "Held: %d   Banked: %d" % [run_gear.size(), banked_gear.size()]
	if hud_level:
		hud_level.text = "Lv %d  XP: %d / %d" % [hero_level, hero_xp, xp_to_next]

# -------------------------------------------------------
# End states
# -------------------------------------------------------
func _on_retreat_pressed() -> void:
	if game_over: return
	_show_retreat_confirm()

func _show_retreat_confirm() -> void:
	var overlay = CanvasLayer.new()
	add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Retreat?"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var msg = Label.new()
	var held_count = run_gear.size()
	if held_count > 0:
		msg.text = "You'll keep your %d banked item(s), but lose %d item(s) you haven't banked yet." % [banked_gear.size(), held_count]
	else:
		msg.text = "You'll keep all %d banked item(s). Nothing unbanked to lose." % banked_gear.size()
	msg.add_theme_font_size_override("font_size", 13)
	msg.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg.custom_minimum_size = Vector2(280, 0)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox)

	var cancel_btn = Button.new()
	cancel_btn.text = "Keep Fighting"
	cancel_btn.custom_minimum_size = Vector2(140, 40)
	cancel_btn.pressed.connect(func(): overlay.queue_free())
	hbox.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "Retreat"
	confirm_btn.custom_minimum_size = Vector2(140, 40)
	confirm_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
	confirm_btn.pressed.connect(func():
		overlay.queue_free()
		_do_retreat())
	hbox.add_child(confirm_btn)

func _do_retreat() -> void:
	game_over = true
	Telemetry.log_event("dungeon_result", {
		"outcome": "retreated",
		"kills": kill_count,
		"level_reached": hero_level,
		"skills": skills_taken.keys(),
		"gear_secured": secured_gear.size() + banked_gear.size(),
	})
	# Banked gear is committed to the permanent inventory now. Unbanked
	# (held) gear is forfeited, per the retreat loot rule.
	for gear in banked_gear:
		PlayerInventory.add_gear(gear)
		secured_gear.append(gear)
	run_gear.clear()
	_show_end_screen("retreated")

func _show_end_screen(outcome: String) -> void:
	var overlay = CanvasLayer.new()
	add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	var title_text = {"won": "RUN COMPLETE!", "lost": "DEFEATED", "retreated": "RETREATED", "survived": "SURVIVED!"}.get(outcome, "RUN OVER")
	var title_color = {"won": Color(0.3,0.9,0.3), "lost": Color(0.9,0.2,0.2), "retreated": Color(0.9,0.6,0.3), "survived": Color(0.3,0.9,0.5)}.get(outcome, Color.WHITE)
	title.text = title_text
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var spoils_gold = 0
	if PlayerInventory.unlocked_talents.get("dungeon_spoils", false) and kill_count > 0:
		spoils_gold = kill_count * 2
		PlayerInventory.resources["gold"] = PlayerInventory.resources.get("gold", 0) + spoils_gold

	var info = Label.new()
	info.text = "Gear secured this run: %d item%s" % [secured_gear.size(), "" if secured_gear.size() == 1 else "s"]
	info.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)

	if spoils_gold > 0:
		var spoils_lbl = Label.new()
		spoils_lbl.text = "Dungeon Spoils: +%d Gold  (%d kills)" % [spoils_gold, kill_count]
		spoils_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
		spoils_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(spoils_lbl)

	if secured_gear.size() > 0:
		var scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(280, min(220, secured_gear.size() * 26))
		vbox.add_child(scroll)

		var gear_list_vbox = VBoxContainer.new()
		gear_list_vbox.add_theme_constant_override("separation", 2)
		scroll.add_child(gear_list_vbox)

		for gear in secured_gear:
			var row = Label.new()
			var quality_tag = (" " + gear.get_quality_name()) if gear.get_quality_name() != "" else ""
			row.text = "%s  [%s%s]" % [gear.item_name, gear.get_rarity_name(), quality_tag]
			row.add_theme_font_size_override("font_size", 12)
			row.add_theme_color_override("font_color", gear.get_display_color())
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			gear_list_vbox.add_child(row)
	else:
		var none_lbl = Label.new()
		none_lbl.text = "No gear found this run."
		none_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		none_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(none_lbl)

	var btn = Button.new()
	var first_time = not PlayerInventory.map_generated
	btn.text = "Continue to World Map" if first_time else "Back to Management"
	btn.custom_minimum_size = Vector2(220, 44)
	btn.pressed.connect(func():
		var dest = "res://scenes/world_map.tscn" if first_time else "res://scenes/management_screen.tscn"
		get_tree().change_scene_to_file(dest))
	vbox.add_child(btn)

# -------------------------------------------------------
# Roguelite skill system
# -------------------------------------------------------

func _grant_xp(amount: int) -> void:
	if PlayerInventory.unlocked_talents.get("dungeon_quick_study", false):
		amount = int(ceil(amount * 1.30))
	hero_xp += amount
	while hero_xp >= xp_to_next:
		hero_xp -= xp_to_next
		hero_level += 1
		xp_to_next = XP_BASE + hero_level * XP_PER_LEVEL
		pending_level_ups += 1
	_refresh_hud()
	if pending_level_ups > 0 and not is_paused and not game_over:
		pending_level_ups -= 1
		_show_skill_pick()

func _show_skill_pick() -> void:
	is_paused = true
	var overlay = CanvasLayer.new()
	overlay.name = "SkillPickOverlay"
	add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "LEVEL %d  —  Choose a Skill" % hero_level
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	if PlayerInventory.unlocked_talents.get("dungeon_relentless", false):
		hero_hp = min(hero_hp + 15, hero_max_hp)
	var skill_offer_count = 4 if PlayerInventory.unlocked_talents.get("dungeon_skill_mastery", false) else 3
	var choices = _get_random_skills(skill_offer_count)
	Telemetry.log_event("dungeon_skills_offered", {
		"level": hero_level,
		"offered": choices.map(func(s): return s["id"]),
	})
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	if choices.is_empty():
		# All skills maxed — consolation HP heal
		var msg = Label.new()
		msg.text = "All skills mastered!\n+20 HP bonus!"
		msg.add_theme_font_size_override("font_size", 16)
		msg.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(msg)
		hero_hp = min(hero_hp + 20, hero_max_hp)
		var tw = create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(func():
			overlay.queue_free()
			if pending_level_ups > 0:
				pending_level_ups -= 1
				_show_skill_pick()
			else:
				is_paused = false)
		return

	for skill in choices:
		var card = _build_skill_card(skill, overlay)
		hbox.add_child(card)

	if run_rerolls > 0:
		var reroll_btn = Button.new()
		reroll_btn.text = "Reroll  (%d left)" % run_rerolls
		reroll_btn.custom_minimum_size = Vector2(180, 36)
		reroll_btn.pressed.connect(func():
			run_rerolls -= 1
			overlay.queue_free()
			_show_skill_pick())
		vbox.add_child(reroll_btn)

func _build_skill_card(skill: Dictionary, overlay: Node) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(190, 150)

	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(inner)

	var name_lbl = Label.new()
	name_lbl.text = skill["name"]
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = skill["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.custom_minimum_size = Vector2(168, 0)
	inner.add_child(desc_lbl)

	var stacks = skills_taken.get(skill["id"], 0)
	if stacks > 0:
		var stack_lbl = Label.new()
		stack_lbl.text = "(%d / %d)" % [stacks, skill["max_stacks"]]
		stack_lbl.add_theme_font_size_override("font_size", 11)
		stack_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		stack_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(stack_lbl)

	var pick_btn = Button.new()
	pick_btn.text = "Choose"
	pick_btn.custom_minimum_size = Vector2(150, 36)
	pick_btn.pressed.connect(func():
		Telemetry.log_event("dungeon_skill_chosen", {"skill": skill["id"], "level": hero_level})
		overlay.queue_free()
		_apply_skill(skill["id"])
		if pending_level_ups > 0:
			pending_level_ups -= 1
			_show_skill_pick()
		else:
			is_paused = false)
	inner.add_child(pick_btn)

	if run_banishes > 0:
		var banish_btn = Button.new()
		banish_btn.text = "Banish"
		banish_btn.custom_minimum_size = Vector2(150, 28)
		banish_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		banish_btn.pressed.connect(func():
			banished_skill_ids.append(skill["id"])
			run_banishes -= 1
			overlay.queue_free()
			_show_skill_pick())
		inner.add_child(banish_btn)

	return panel

func _get_random_skills(count: int) -> Array:
	var available: Array = []
	for skill in SKILL_POOL:
		if skills_taken.get(skill["id"], 0) < skill["max_stacks"]:
			if not banished_skill_ids.has(skill["id"]):
				available.append(skill)
	available.shuffle()
	return available.slice(0, min(count, available.size()))

func _apply_skill(skill_id: String) -> void:
	skills_taken[skill_id] = skills_taken.get(skill_id, 0) + 1
	match skill_id:
		"swiftness":
			hero_speed *= (1.0 + SKILL_SWIFTNESS_SPEED_BONUS)
		"iron_hide":
			var bonus = int(hero_max_hp * SKILL_IRON_HIDE_HP_BONUS)
			hero_max_hp += bonus
			hero_hp = min(hero_hp + bonus, hero_max_hp)
		"armor_plating":
			hero_armor += SKILL_ARMOR_PLATING_FLAT
		"rapid_fire":
			hero_attack_interval *= SKILL_RAPID_FIRE_MULT
		"power_shot":
			hero_attack = int(hero_attack * SKILL_POWER_SHOT_MULT)
		"deadly_crits":
			hero_crit_chance += SKILL_DEADLY_CRITS_CHANCE
		"crushing_blow":
			hero_crit_damage += SKILL_CRUSHING_BLOW_CRIT_DMG
		"wide_range":
			if hero_attack_range < 99999.0:
				hero_attack_range *= SKILL_WIDE_RANGE_MULT
		"glass_cannon":
			hero_attack = int(hero_attack * SKILL_GLASS_CANNON_DMG_MULT)
			hero_max_hp = max(10, int(hero_max_hp * SKILL_GLASS_CANNON_HP_MULT))
			hero_hp = min(hero_hp, hero_max_hp)
		"lucky":
			skill_drop_bonus += SKILL_LUCKY_DROP_BONUS
		"plunder":
			skill_drop_bonus += SKILL_PLUNDER_DROP_BONUS
			hero_attack = max(1, int(hero_attack * SKILL_PLUNDER_DMG_MULT))
		"vampiric":
			skill_vampiric_hp += SKILL_VAMPIRIC_HP_PER_KILL
		"multishot":
			skill_extra_projs += 1
		"piercing":
			skill_piercing = true
		"explosive":
			skill_explosive = true
		"orb_shield":
			skill_orb_count += 2
			_rebuild_orb_rects()
		"nova_burst":
			skill_nova = true
		"death_rattle":
			skill_death_rattle = true
		"berserker":
			skill_berserker = true
		"second_wind":
			skill_second_wind = true
			skill_second_wind_ready = true
		"lifesteal":
			skill_lifesteal += SKILL_LIFESTEAL_PCT
	_refresh_hud()

# -------------------------------------------------------
# Orbital Shield
# -------------------------------------------------------

func _rebuild_orb_rects() -> void:
	for r in skill_orb_rects:
		if is_instance_valid(r): r.queue_free()
	skill_orb_rects.clear()
	for i in range(skill_orb_count):
		var orb = ColorRect.new()
		orb.size = Vector2(12, 12)
		orb.color = Color(0.35, 0.65, 1.0, 0.95)
		arena_node.add_child(orb)
		skill_orb_rects.append(orb)

func _update_orbs(delta: float) -> void:
	if skill_orb_count == 0: return
	skill_orb_angle += delta * 130.0   # degrees per second
	var orb_radius = 64.0
	var orb_dmg = max(3, int(hero_attack * 0.30))

	for i in range(min(skill_orb_count, skill_orb_rects.size())):
		var angle = deg_to_rad(skill_orb_angle + (360.0 / skill_orb_count) * i)
		var orb_pos = hero_pos + Vector2(cos(angle), sin(angle)) * orb_radius
		if is_instance_valid(skill_orb_rects[i]):
			skill_orb_rects[i].position = orb_pos - Vector2(6, 6)

	# Hit detection on a rolling cooldown so orbs don't melt enemies instantly
	if skill_orb_hit_timer > 0:
		skill_orb_hit_timer -= delta
		return

	var to_kill: Array = []
	for i in range(enemies.size() - 1, -1, -1):
		var e = enemies[i]
		var hit_by_orb = false
		for j in range(skill_orb_count):
			var angle = deg_to_rad(skill_orb_angle + (360.0 / skill_orb_count) * j)
			var orb_pos = hero_pos + Vector2(cos(angle), sin(angle)) * orb_radius
			if orb_pos.distance_to(e["pos"]) < e["sz"] / 2 + 8:
				hit_by_orb = true
				break
		if hit_by_orb:
			e["hp"] -= orb_dmg
			_update_boss_bar(e)
			if e["hp"] <= 0:
				to_kill.append(i)
	for kill_idx in to_kill:
		if kill_idx < enemies.size():
			_kill_enemy(kill_idx)
	skill_orb_hit_timer = 0.35

# -------------------------------------------------------
# Shared explosion helper (Explosive Rounds, Nova Burst, Death Rattle)
# -------------------------------------------------------

func _trigger_explosion(center: Vector2, damage: int, ignore_idx: int = -1) -> void:
	var radius = 90.0
	var to_kill: Array = []
	for i in range(enemies.size() - 1, -1, -1):
		if i == ignore_idx: continue
		if center.distance_to(enemies[i]["pos"]) < radius:
			enemies[i]["hp"] -= damage
			_update_boss_bar(enemies[i])
			if enemies[i]["hp"] <= 0:
				to_kill.append(i)
	for kill_idx in to_kill:
		if kill_idx < enemies.size():
			_kill_enemy(kill_idx)
	# Brief visual flash
	var flash = ColorRect.new()
	flash.size = Vector2(radius * 2, radius * 2)
	flash.position = center - Vector2(radius, radius)
	flash.color = Color(1.0, 0.55, 0.1, 0.45)
	arena_node.add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.28)
	tw.tween_callback(flash.queue_free)

func _show_second_wind_notification() -> void:
	var lbl = Label.new()
	lbl.text = "SECOND WIND!"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.3))
	lbl.position = hero_pos - Vector2(65, 65)
	arena_node.add_child(lbl)
	var tw = create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 45, 1.6)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.6)
	tw.tween_callback(lbl.queue_free)
