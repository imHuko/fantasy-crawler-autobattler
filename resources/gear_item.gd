class_name GearItem
extends Resource

enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }
enum Slot { WEAPON, ARMOR, RING, ACCESSORY }

@export var item_name: String = ""
@export var rarity: Rarity = Rarity.COMMON
@export var slot: Slot = Slot.WEAPON
@export var stats: Dictionary = {}
# e.g. { "attack": 5, "defense": 3, "crit_chance": 0.1 }
@export var set_name: String = ""
# e.g. "Dragon Scale", "Iron Oath"

func get_rarity_name() -> String:
	return Rarity.keys()[rarity]

func get_slot_name() -> String:
	return Slot.keys()[slot]

func print_info() -> void:
	print("--- Gear Item ---")
	print("Name:    ", item_name)
	print("Rarity:  ", get_rarity_name())
	print("Slot:    ", get_slot_name())
	print("Set:     ", set_name if set_name != "" else "None")
	print("Stats:   ", stats)
	print("-----------------")
