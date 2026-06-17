class_name GearItem
extends Resource

enum Rarity  { COMMON, RARE, EPIC, LEGENDARY }
enum Slot    { WEAPON, ARMOR, RING, ACCESSORY }
enum Quality { NORMAL, AWAKENED, ASCENDANT, TRANSCENDENT }

@export var item_name: String = ""
@export var rarity:  Rarity  = Rarity.COMMON
@export var slot:    Slot    = Slot.WEAPON
@export var quality: Quality = Quality.NORMAL
@export var item_level: int = 1   # the stage/difficulty this item dropped at (1-10); scales stat ranges
@export var stats: Dictionary = {}
@export var stat_ranges: Dictionary = {}
# stat_ranges stores the rolled ceiling for each stat so we can show the bar
# format: { "attack": {"rolled": 22, "min": 16, "max": 38, "is_quality": false} }
@export var set_name: String = ""
@export var upgrade_level: int = 0   # 0-6; each level adds a small % to this item's own rolled stats

func get_rarity_name() -> String:
	return Rarity.keys()[rarity]

func get_slot_name() -> String:
	return Slot.keys()[slot]

func get_quality_name() -> String:
	match quality:
		Quality.AWAKENED:      return "Awakened"
		Quality.ASCENDANT:     return "Ascendant"
		Quality.TRANSCENDENT:  return "Transcendent"
	return ""

# Base sell value by rarity, scaled up by quality tier to reflect the same
# power gap quality gives in stats (Transcendent ~3x a Normal item's worth).
const SELL_BASE_PRICE = {
	"COMMON": 5, "RARE": 15, "EPIC": 40, "LEGENDARY": 100,
}
const SELL_QUALITY_MULT = {
	"": 1.0, "Awakened": 1.4, "Ascendant": 2.0, "Transcendent": 2.8,
}

func get_sell_price() -> int:
	var base = SELL_BASE_PRICE.get(get_rarity_name(), 5)
	var quality_mult = SELL_QUALITY_MULT.get(get_quality_name(), 1.0)
	var price = base * quality_mult
	if set_name != "":
		price *= 1.2   # set-bonus items are slightly more valuable
	return max(1, int(round(price)))

# Salvage value follows the same shape as sell price (rarity base x
# quality multiplier) but returns a count of this item's own rarity's
# salvage material instead of gold, and is deliberately a smaller
# number than the gold sell price — salvage is meant to feel like a
# byproduct of breaking an item down, not a replacement currency.
const SALVAGE_BASE_AMOUNT = {
	"COMMON": 1, "RARE": 2, "EPIC": 4, "LEGENDARY": 8,
}
const SALVAGE_QUALITY_MULT = {
	"": 1.0, "Awakened": 1.3, "Ascendant": 1.8, "Transcendent": 2.5,
}

func get_salvage_amount() -> int:
	var base = SALVAGE_BASE_AMOUNT.get(get_rarity_name(), 1)
	var quality_mult = SALVAGE_QUALITY_MULT.get(get_quality_name(), 1.0)
	return max(1, int(round(base * quality_mult)))

# -------------------------------------------------------
# Upgrades — 6 levels, each adding a small % on top of this item's own
# rolled stats. Paid for with salvage material matching the item's
# RARITY (not quality) — quality instead makes each level cost more,
# so a Transcendent item needs real commitment to fully upgrade.
# -------------------------------------------------------
const MAX_UPGRADE_LEVEL = 6
const UPGRADE_STAT_BONUS_PER_LEVEL = 0.04   # +4% of this item's own rolled stats, per level

# Base salvage cost for the FIRST upgrade level, by rarity — later
# levels cost progressively more, see get_next_upgrade_cost() below.
const UPGRADE_BASE_COST = {
	"COMMON": 2, "RARE": 4, "EPIC": 8, "LEGENDARY": 15,
}
# Quality multiplies the cost on top of the rarity base — Transcendent
# gear demands a lot more salvage to fully upgrade than a Normal item
# of the same rarity.
const UPGRADE_QUALITY_COST_MULT = {
	"": 1.0, "Awakened": 1.6, "Ascendant": 2.4, "Transcendent": 3.5,
}

func is_max_upgrade() -> bool:
	return upgrade_level >= MAX_UPGRADE_LEVEL

# Cost in salvage (of this item's own rarity) to go from the current
# upgrade_level to the next one. Each successive level costs more than
# the last, so the final levels are a real investment.
func get_next_upgrade_cost() -> int:
	if is_max_upgrade(): return 0
	var base = UPGRADE_BASE_COST.get(get_rarity_name(), 2)
	var quality_mult = UPGRADE_QUALITY_COST_MULT.get(get_quality_name(), 1.0)
	# Level 0->1 costs the base amount; each level after that costs 35% more
	# than the previous level's cost, giving a real but gentle ramp.
	var level_mult = pow(1.35, upgrade_level)
	return max(1, int(round(base * quality_mult * level_mult)))

func upgrade() -> bool:
	if is_max_upgrade(): return false
	upgrade_level += 1
	return true

# The % bonus this item's upgrade levels currently add to its rolled
# stats — applied on top of whatever stats/stat_ranges already rolled,
# never changing the base roll itself.
func get_upgrade_bonus_pct() -> float:
	return upgrade_level * UPGRADE_STAT_BONUS_PER_LEVEL

# Returns this item's stats with the upgrade bonus applied — use this
# instead of reading `stats` directly anywhere upgrade levels should
# matter (combat stat totals, tooltips, etc).
func get_effective_stats() -> Dictionary:
	if upgrade_level <= 0: return stats
	var bonus_mult = 1.0 + get_upgrade_bonus_pct()
	var result: Dictionary = {}
	for stat_key in stats:
		var val = stats[stat_key]
		if val is float:
			result[stat_key] = val * bonus_mult
		else:
			result[stat_key] = int(round(val * bonus_mult))
	return result

func get_quality_suffix() -> String:
	match quality:
		Quality.AWAKENED:      return " ✦"
		Quality.ASCENDANT:     return " ✦✦"
		Quality.TRANSCENDENT:  return " ✦✦✦"
	return ""

# Returns item level's stat scaling as a % of the maximum possible (item
# level 10). Gives players a concrete sense of how much headroom this
# specific item still has compared to its absolute ceiling.
# NOTE: kept in sync manually with GearGenerator.ITEM_LEVEL_MULT — this is
# a local copy since GearItem (a Resource) shouldn't reach into the
# GearGenerator autoload. If that table's numbers change, update both.
const ITEM_LEVEL_MULT_REF = {
	1: 0.55, 2: 0.65, 3: 0.78, 4: 0.92, 5: 1.05,
	6: 1.25, 7: 1.50, 8: 1.80, 9: 2.20, 10: 2.70,
}
func get_stat_budget_pct() -> int:
	var mult = ITEM_LEVEL_MULT_REF.get(clamp(item_level, 1, 10), 1.0)
	var max_mult = ITEM_LEVEL_MULT_REF[10]
	return int(round((mult / max_mult) * 100))

func get_rarity_color() -> Color:
	match rarity:
		Rarity.COMMON:    return Color(0.75, 0.75, 0.75)
		Rarity.RARE:      return Color(0.25, 0.50, 1.00)
		Rarity.EPIC:      return Color(0.65, 0.25, 0.90)
		Rarity.LEGENDARY: return Color(1.00, 0.65, 0.10)
	return Color.WHITE

func get_display_color() -> Color:
	var base = get_rarity_color()
	match quality:
		Quality.AWAKENED:
			return base.lightened(0.25)
		Quality.ASCENDANT:
			return base.lightened(0.45)
		Quality.TRANSCENDENT:
			return Color(1.0, 1.0, 1.0)  # Pure white/gold
	return base

func get_suggested_units() -> Array:
	var suggestions = []
	var tank_score = 0
	var dps_score = 0
	var mage_score = 0
	var heal_score = 0
	var rogue_score = 0

	for stat in stats:
		match stat:
			"hp":           tank_score  += 2; heal_score += 1
			"armor":        tank_score  += 3
			"attack":       dps_score   += 2; mage_score += 1; rogue_score += 2
			"attack_speed": dps_score   += 2; mage_score += 2; rogue_score += 2
			"crit_chance":  dps_score   += 2; mage_score += 1; rogue_score += 3
			"crit_damage":  dps_score   += 2; mage_score += 2; rogue_score += 3
			# Decisive rather than fuzzy — these stats only do anything for
			# specific archetypes, so the suggestion should reflect that clearly.
			"spell_power":  mage_score  += 4; heal_score += 4
			"lifesteal":    tank_score  += 1; dps_score += 2; mage_score += 1; rogue_score += 2
			"thorns":       tank_score  += 3; rogue_score += 1
			"move_speed":   tank_score  += 1; rogue_score += 3

	var scores = {"KNIGHT": tank_score, "ARCHER": dps_score,
				  "MAGE": mage_score, "HEALER": heal_score, "ROGUE": rogue_score}
	var max_score = 0
	for s in scores.values():
		if s > max_score: max_score = s
	if max_score == 0: return []

	for unit in scores:
		if scores[unit] >= max_score * 0.7:
			suggestions.append(unit)
	return suggestions

func print_info() -> void:
	print("--- Gear Item ---")
	print("Name:    ", item_name, get_quality_suffix())
	print("Rarity:  ", get_rarity_name())
	print("Quality: ", get_quality_name() if quality != Quality.NORMAL else "Normal")
	print("Slot:    ", get_slot_name())
	print("Set:     ", set_name if set_name != "" else "None")
	print("Stats:   ", stats)
	print("-----------------")
