class_name TutorialSteps

# -------------------------------------------------------
# The full forced walkthrough, in order. Pure data — no logic lives
# here. The routing engine (autoloads/tutorial_router.gd) reads this
# list and TutorialOverlay (autoloads/tutorial_overlay.gd) actually
# shows each step; this file just describes what they say and where
# they belong.
#
# Each step is a Dictionary:
#   "id"          - unique string, also used as the save-resume key
#   "screen"      - which scene this step belongs to, as a scene path.
#                    The router uses this to know whether the player is
#                    currently on the right screen for the active step,
#                    and to navigate them there if the step demands a
#                    specific screen.
#   "mode"        - "info" (just text + Next button) or "click" (must
#                    click a specific control to advance)
#   "text"        - instruction text shown in the overlay
#   "target_id"   - for "click" steps, an identifier the screen itself
#                    resolves to an actual Control (see each screen's
#                    _get_tutorial_target(id) — kept as a string here
#                    rather than a direct node reference, since this
#                    table is static data loaded before any scene
#                    exists, and node references can't survive that)
#
# Content for each screen is filled in by the sub-step that builds
# that screen's actual hookup (sub-steps 3-5). This file holds
# placeholder/best-guess text for all of them now so the routing
# engine in sub-step 2 has a complete real sequence to drive against,
# rather than an empty list — expect later sub-steps to refine the
# wording and target_id values as each screen's hookup is actually
# wired in.
# -------------------------------------------------------

const STEPS: Array = [
	# --- World Map orientation ---
	{
		"id": "map_time",
		"screen": "res://scenes/world_map.tscn",
		"mode": "info",
		"text": "Welcome! Time passes continuously here, even while you're away on other screens.",
		"target_id": "",
	},
	{
		"id": "map_pause",
		"screen": "res://scenes/world_map.tscn",
		"mode": "click",
		"text": "Try pausing time with this button. You can do this any time you need a moment to think.",
		"target_id": "pause_button",
	},
	{
		"id": "map_speed",
		"screen": "res://scenes/world_map.tscn",
		"mode": "info",
		"text": "This slider speeds time up, handy when nothing urgent is happening.",
		"target_id": "speed_slider",
	},
	{
		"id": "map_overview",
		"screen": "res://scenes/world_map.tscn",
		"mode": "info",
		"text": "This is the World Map. Each marker is a zone you can own, build on, or send troops to.",
		"target_id": "",
	},

	# --- Building ---
	{
		"id": "build_intro",
		"screen": "res://scenes/world_map.tscn",
		"mode": "info",
		"text": "Zones you own can have buildings. We've given you a free Farm to place — let's try it.",
		"target_id": "",
	},
	{
		"id": "build_open_zone",
		"screen": "res://scenes/world_map.tscn",
		"mode": "click",
		"text": "Click your starting zone to open it.",
		"target_id": "owned_zone_marker",
	},
	{
		"id": "build_here",
		"screen": "res://scenes/world_map.tscn",
		"mode": "click",
		"text": "Click Build Here to see what you can build.",
		"target_id": "build_here_button",
	},
	{
		"id": "build_place_farm",
		"screen": "res://scenes/world_map.tscn",
		"mode": "click",
		"text": "Build a Farm — it's free for this tutorial.",
		"target_id": "farm_button",
	},

	# --- Recruiting (deliberate failure, into the dungeon) ---
	{
		"id": "recruit_intro",
		"screen": "res://scenes/management_screen.tscn",
		"mode": "click",
		"text": "You can recruit new units here. Let's try it.",
		"target_id": "recruit_button",
		"nav_target_id": "mgmt_button",   # shown on world_map when directing to Management — highlights the Management button in the top HUD
	},
	{
		"id": "recruit_no_gold",
		"screen": "res://scenes/recruit_screen.tscn",
		"mode": "info",
		"text": "You don't have any Gold yet — recruiting isn't possible until you earn some. The dungeon is the fastest way to get started.",
		"target_id": "",
	},
	{
		"id": "dungeon_send",
		"screen": "res://scenes/management_screen.tscn",
		"mode": "click",
		"text": "Head into the dungeon to find gear you can sell for Gold.",
		"target_id": "dungeon_button",
		"nav_target_id": "mgmt_button",         # shown on recruit_screen — highlights Back to Management
		"nav_action_label": "Go to Management",
		"nav_action_scene": "res://scenes/management_screen.tscn",
	},

	# --- Dungeon & gear ---
	{
		"id": "dungeon_run",
		"screen": "res://scenes/tutorial_dungeon.tscn",
		"mode": "info",
		"text": "Defeat 8 enemies. Use WASD to move \u2014 you auto-attack the nearest one.",
		"target_id": "",
		"nodim": true,
		"nav_target_id": "dungeon_button",
		"nav_action_label": "Go to Dungeon",
		"nav_action_scene": "res://scenes/tutorial_dungeon.tscn",
	},

	# --- Equipping (each is genuinely 2 clicks: pick the item, then the
	# slot — split into 2 steps each rather than 1, since the overlay
	# can only spotlight one target per step) ---
	{
		"id": "equip_hero_pick_item",
		"screen": "res://scenes/management_screen.tscn",
		"mode": "click",
		"text": "Click this weapon to select it.",
		"target_id": "gear_item_weapon",
	},
	{
		"id": "equip_hero_pick_slot",
		"screen": "res://scenes/management_screen.tscn",
		"mode": "click",
		"text": "Now click your Hero's empty weapon slot to equip it.",
		"target_id": "hero_weapon_slot",
	},
	{
		"id": "equip_recruit_pick_item",
		"screen": "res://scenes/management_screen.tscn",
		"mode": "click",
		"text": "Click this weapon to select it.",
		"target_id": "gear_item_weapon",
	},
	{
		"id": "equip_recruit_pick_slot",
		"screen": "res://scenes/management_screen.tscn",
		"mode": "click",
		"text": "Now click your new recruit's empty weapon slot to equip it.",
		"target_id": "recruit_weapon_slot",
	},

	# --- Inventory / Selling, Salvaging, Upgrading (all in one gear shop visit) ---
	{
		"id": "inventory_sell",
		"screen": "res://scenes/gear_shop_screen.tscn",
		"mode": "click",
		"text": "Sell one of your Practice Swords for Gold.",
		"target_id": "sell_item_button",
		"nav_target_id": "gear_shop_button",
		"nav_action_label": "Go to Gear Shop",
		"nav_action_scene": "res://scenes/gear_shop_screen.tscn",
	},
	{
		"id": "click_salvage_tab",
		"screen": "res://scenes/gear_shop_screen.tscn",
		"mode": "click",
		"text": "Click the Salvage tab.",
		"target_id": "salvage_tab_button",
	},
	{
		"id": "salvage_intro",
		"screen": "res://scenes/gear_shop_screen.tscn",
		"mode": "click",
		"text": "Salvage your last spare Practice Sword to break it down into upgrade material.",
		"target_id": "salvage_item_button",
	},
	{
		"id": "click_upgrade_tab",
		"screen": "res://scenes/gear_shop_screen.tscn",
		"mode": "click",
		"text": "Click the Upgrade tab.",
		"target_id": "upgrade_tab_button",
	},
	{
		"id": "upgrade_intro",
		"screen": "res://scenes/gear_shop_screen.tscn",
		"mode": "click",
		"text": "Now upgrade your Hero's equipped weapon. Your first upgrade is free.",
		"target_id": "first_upgrade_button",
	},

	# --- Scripted Defense ---
	{
		"id": "defense_intro",
		"screen": "res://scenes/world_map.tscn",
		"mode": "info",
		"text": "Careful \u2014 something is approaching your capital!",
		"target_id": "",
		"nav_target_id": "",
		"nav_action_label": "Go to World Map",
		"nav_action_scene": "res://scenes/world_map.tscn",
	},
	{
		"id": "defense_battle",
		"screen": "res://scenes/defense_scene.tscn",
		"mode": "info",
		"text": "Place your units, then begin the battle.",
		"target_id": "",
		"nodim": true,
	},

	# --- Healing via Food ---
	{
		"id": "heal_intro",
		"screen": "res://scenes/management_screen.tscn",
		"mode": "click",
		"text": "That unit took damage in the battle. Use your Food to heal them \u2014 your Farm generates more over time.",
		"target_id": "heal_button",
		"nav_target_id": "mgmt_button",
		"nav_action_label": "Go to Management",
		"nav_action_scene": "res://scenes/management_screen.tscn",
	},

	# --- Talents ---
	{
		"id": "talents_intro",
		"screen": "res://scenes/management_screen.tscn",
		"mode": "click",
		"text": "You've now learned two ways to earn Gold and one way to earn Food. Let's look at Talents, which can be spent on permanent upgrades.",
		"target_id": "talents_button",
	},
	{
		"id": "talents_wilds_pact",
		"screen": "res://scenes/talent_tree_screen.tscn",
		"mode": "info",
		"text": "Wilds Pact is free \u2014 once unlocked, it lets you turn random attacks on or off (on Easy/Normal difficulty).",
		"target_id": "",
	},
]

static func get_step(index: int) -> Dictionary:
	if index < 0 or index >= STEPS.size():
		return {}
	return STEPS[index]

static func get_step_count() -> int:
	return STEPS.size()

static func find_step_index(step_id: String) -> int:
	for i in range(STEPS.size()):
		if STEPS[i]["id"] == step_id:
			return i
	return -1

# Human-readable names for every screen any step in STEPS references —
# used for the "head to X to continue" reminder shown when the active
# step's screen differs from wherever the player currently is.
const SCREEN_DISPLAY_NAMES = {
	"res://scenes/world_map.tscn": "the World Map",
	"res://scenes/management_screen.tscn": "Management",
	"res://scenes/recruit_screen.tscn": "the Recruit screen",
	"res://scenes/gear_shop_screen.tscn": "the Gear Shop",
	"res://scenes/talent_tree_screen.tscn": "the Talent Tree",
	"res://scenes/tutorial_dungeon.tscn": "the Dungeon",
	"res://scenes/defense_scene.tscn": "the Defense battle",
}

static func get_screen_display_name(screen_path: String) -> String:
	return SCREEN_DISPLAY_NAMES.get(screen_path, "the next screen")
