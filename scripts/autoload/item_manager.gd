## ItemManager — Manages the player's inventory and item definitions.
## Items can be force-aligned, granting bonuses when the matching force is high.
extends Node

signal item_added(item_id: String, count: int)
signal item_removed(item_id: String, count: int)
signal item_used(item_id: String)

# Inventory: item_id -> count
var inventory: Dictionary = {}

# Item definitions: item_id -> data
var item_defs: Dictionary = {}


func _ready() -> void:
	_register_default_items()


func _register_default_items() -> void:
	register_item("health_potion", {
		"name": "Ashen Salve",
		"description": "Heals 30 HP. Tastes like regret.",
		"type": "consumable",
		"use_effect": "heal",
		"heal_amount": 30.0,
		"stackable": true,
		"max_stack": 10,
	})
	register_item("faith_charm", {
		"name": "Prayer Bead",
		"description": "A bead worn smooth by a million prayers. +5 Faith on use.",
		"type": "consumable",
		"use_effect": "force",
		"force": "faith",
		"force_amount": 5.0,
		"stackable": true,
		"max_stack": 5,
	})
	register_item("truth_lens", {
		"name": "Cracked Lens",
		"description": "See the world as it truly is. +5 Truth on use.",
		"type": "consumable",
		"use_effect": "force",
		"force": "truth",
		"force_amount": 5.0,
		"stackable": true,
		"max_stack": 5,
	})
	register_item("violence_shard", {
		"name": "Iron Splinter",
		"description": "A fragment of something that was once part of a weapon — or a person. +5 Violence on use.",
		"type": "consumable",
		"use_effect": "force",
		"force": "violence",
		"force_amount": 5.0,
		"stackable": true,
		"max_stack": 5,
	})
	register_item("ash_relic", {
		"name": "Ash Relic",
		"description": "A relic from before the ashfall. It hums with faint warmth.",
		"type": "quest",
		"stackable": false,
	})
	register_item("void_fragment", {
		"name": "Void Fragment",
		"description": "A piece of the Null Throne. It shouldn't exist, but it does.",
		"type": "quest",
		"stackable": false,
	})


func register_item(item_id: String, data: Dictionary) -> void:
	item_defs[item_id] = data


## Add item to inventory.
func add_item(item_id: String, count: int = 1) -> bool:
	if not item_defs.has(item_id):
		push_warning("ItemManager: unknown item '%s'." % item_id)
		return false

	var def: Dictionary = item_defs[item_id]
	var current: int = inventory.get(item_id, 0)

	if def.get("stackable", false):
		var max_stack: int = def.get("max_stack", 99)
		var new_count := mini(current + count, max_stack)
		inventory[item_id] = new_count
	else:
		if current > 0:
			return false  # Already have non-stackable item
		inventory[item_id] = 1

	item_added.emit(item_id, inventory[item_id])

	WorldEventManager.event_notification.emit(
		"Item Acquired",
		def.get("name", item_id)
	)
	return true


## Remove item from inventory.
func remove_item(item_id: String, count: int = 1) -> bool:
	var current: int = inventory.get(item_id, 0)
	if current < count:
		return false

	inventory[item_id] = current - count
	if inventory[item_id] <= 0:
		inventory.erase(item_id)

	item_removed.emit(item_id, count)
	return true


## Use a consumable item.
func use_item(item_id: String) -> bool:
	if not has_item(item_id):
		return false

	var def: Dictionary = item_defs.get(item_id, {})
	var item_type: String = def.get("type", "")
	if item_type != "consumable":
		return false

	var effect: String = def.get("use_effect", "")

	match effect:
		"heal":
			var amount: float = def.get("heal_amount", 0.0)
			var player := get_tree().get_first_node_in_group("player")
			if player and player.has_method("heal"):
				player.heal(amount)
		"force":
			var force_name: String = def.get("force", "")
			var force_amount: float = def.get("force_amount", 0.0)
			if force_name != "":
				GameState.add_force(force_name, force_amount)

	remove_item(item_id)
	item_used.emit(item_id)
	return true


## Check if player has at least one of an item.
func has_item(item_id: String, min_count: int = 1) -> bool:
	return inventory.get(item_id, 0) >= min_count


## Get item count.
func get_item_count(item_id: String) -> int:
	return inventory.get(item_id, 0)


## Get display name for an item.
func get_item_name(item_id: String) -> String:
	return item_defs.get(item_id, {}).get("name", item_id)


## Get all inventory entries as [{id, count, def}].
func get_inventory_list() -> Array:
	var result: Array = []
	for item_id in inventory:
		if inventory[item_id] > 0:
			result.append({
				"id": item_id,
				"count": inventory[item_id],
				"def": item_defs.get(item_id, {}),
			})
	return result


# --- Persistence ---

func save_state() -> Dictionary:
	return {"inventory": inventory.duplicate()}


func load_state(data: Dictionary) -> void:
	inventory = data.get("inventory", {})
