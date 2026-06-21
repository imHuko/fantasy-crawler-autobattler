extends RefCounted
class_name TalentTreeLayout

# -------------------------------------------------------
# Free-form layout for the talent screen.
#
# Each entry maps a node id to a NORMALIZED position (x, y),
# both in the 0.0–1.0 range, representing where the node's
# CENTER sits as a fraction of the talent canvas's width/height.
# Normalized (not pixel) coordinates so the layout scales
# cleanly to any screen size without distortion.
#
# This came from the free-form drag-and-drop layout designer —
# positions are NOT locked to a grid, so icons can sit at any
# offset relative to each other (staggered rows, off-center
# branches, etc).
#
# Wilds Pact (toggle_invasions) is intentionally placed near the
# very top (y ~0.05) since it's granted free to the player and
# needs to be visible early for the tutorial flow.
#
# Edit these x/y values directly to nudge any node; everything
# else (connector lines, locking, purchasing) is driven off
# TalentTreeData and updates automatically.
# -------------------------------------------------------

const POSITIONS: Dictionary = {
	"toggle_invasions":                 {"x": 0.0995, "y": 0.0513},

	"gear_sharper_eye":                 {"x": 0.0995, "y": 0.1886},
	"gear_set_seeker":                  {"x": 0.2566, "y": 0.1817},
	"gear_awakened_quality":            {"x": 0.4215, "y": 0.1886},
	"gear_ascendant_quality":           {"x": 0.5910, "y": 0.1914},
	"gear_transcendent_quality":        {"x": 0.7667, "y": 0.1928},

	"buildings_efficient_construction": {"x": 0.0964, "y": 0.3773},
	"buildings_expanded_lots":          {"x": 0.2566, "y": 0.3065},
	"buildings_reinforced_towers":      {"x": 0.2551, "y": 0.4313},
	"buildings_wider_reach":            {"x": 0.4152, "y": 0.3107},

	"recruiting_talent_scout":          {"x": 0.1026, "y": 0.5645},
	"recruiting_pick_of_the_litter":    {"x": 0.2551, "y": 0.5645},
	"recruiting_cream_of_the_crop":     {"x": 0.3904, "y": 0.5673},

	"combat_hardened_ranks":            {"x": 0.1026, "y": 0.6810},
	"combat_forced_march":              {"x": 0.2504, "y": 0.6796},
	"combat_sharpened_blades":          {"x": 0.7434, "y": 0.4716},
	"combat_heros_resolve":             {"x": 0.9036, "y": 0.4702},

	"economy_bountiful_harvest":        {"x": 0.1058, "y": 0.7933},
	"economy_trade_routes":             {"x": 0.2519, "y": 0.7920},
	"economy_steady_coffers":           {"x": 0.2473, "y": 0.9140},

	"diplomatic_tongue":                {"x": 0.1058, "y": 0.9140},

	# --- GEAR additions ---
	"gear_salvage_mastery":             {"x": 0.0995, "y": 0.2900},

	# --- BUILDINGS additions ---
	"buildings_fortified_walls":        {"x": 0.2551, "y": 0.5250},

	# --- RECRUITING additions ---
	"recruiting_veteran_enrollment":    {"x": 0.5300, "y": 0.5645},

	# --- COMBAT additions ---
	"combat_veterans_grit":             {"x": 0.4200, "y": 0.6810},
	"combat_last_stand":                {"x": 0.7434, "y": 0.5750},

	# --- ECONOMY additions ---
	"economy_guild_contracts":          {"x": 0.4300, "y": 0.9140},
	"economy_supply_network":           {"x": 0.4300, "y": 0.7920},

	# --- DUNGEON branch (right side, lower half) ---
	"dungeon_extended_campaign":        {"x": 0.5700, "y": 0.6810},
	"dungeon_marathon_runner":          {"x": 0.5700, "y": 0.7920},
	"dungeon_loaded_dice":              {"x": 0.5700, "y": 0.9000},
	"dungeon_quick_study":              {"x": 0.6900, "y": 0.6810},
	"dungeon_skill_mastery":            {"x": 0.6900, "y": 0.7920},
	"dungeon_opening_gambit":           {"x": 0.6900, "y": 0.9000},
	"dungeon_veteran_commander":        {"x": 0.8100, "y": 0.6810},
	"dungeon_relentless":               {"x": 0.8100, "y": 0.7920},
	"dungeon_iron_will":                {"x": 0.8100, "y": 0.9000},
	"dungeon_combat_drilling":          {"x": 0.9200, "y": 0.6810},
	"dungeon_treasure_hunter":          {"x": 0.9200, "y": 0.7920},
	"dungeon_spoils":                   {"x": 0.9200, "y": 0.9000},
}

static func get_position(node_id: String) -> Vector2:
	var p = POSITIONS.get(node_id, {"x": 0.1, "y": 0.1})
	return Vector2(p["x"], p["y"])
