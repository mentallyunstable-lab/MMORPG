## FactionManager — Defines factions, tracks reputation, and drives NPC/world reactions.
## Factions have a force alignment. Their attitude toward the player depends on
## both direct reputation AND the state of their aligned force.
extends Node

signal faction_attitude_changed(faction_id: String, old_attitude: String, new_attitude: String)

# Attitude thresholds (based on effective reputation)
const HOSTILE_BELOW := -50.0
const UNFRIENDLY_BELOW := -15.0
const FRIENDLY_ABOVE := 15.0
const ALLIED_ABOVE := 50.0

# Faction definitions: id -> data
var faction_defs: Dictionary = {}


func _ready() -> void:
	_register_default_factions()
	GameState.force_changed.connect(_on_force_changed)


## Register the game's starting factions.
func _register_default_factions() -> void:
	register_faction("ashwalkers", {
		"name": "The Ash Walkers",
		"force_alignment": "faith",
		"description": "Pilgrims who walk the ash wastes, seeking signs of the old gods.",
	})
	register_faction("truthseekers", {
		"name": "The Shattered Lens",
		"force_alignment": "truth",
		"description": "Scholars and heretics who believe only observable reality matters.",
	})
	register_faction("ironvow", {
		"name": "The Iron Vow",
		"force_alignment": "violence",
		"description": "Warlords who believe strength is the only honest currency.",
	})
	register_faction("hollow_church", {
		"name": "The Hollow Church",
		"force_alignment": "faith",
		"description": "A dying religion clinging to rituals no god answers.",
	})

	# Initialize reputations in GameState
	for faction_id in faction_defs:
		if GameState.get_faction_reputation(faction_id) == 0.0:
			GameState.set_faction_reputation(faction_id, 0.0)


func register_faction(faction_id: String, data: Dictionary) -> void:
	faction_defs[faction_id] = data


## Get effective reputation = direct rep + force bonus.
## If the player's aligned force is high, factions sharing that alignment like them more.
func get_effective_reputation(faction_id: String) -> float:
	var base_rep := GameState.get_faction_reputation(faction_id)
	var def: Dictionary = faction_defs.get(faction_id, {})
	var alignment: String = def.get("force_alignment", "")

	if alignment == "":
		return base_rep

	# Bonus: +0.3 per point of aligned force
	var force_value := GameState.get_force(alignment)
	var bonus := force_value * 0.3

	# Penalty for opposing forces being high
	var penalty := 0.0
	match alignment:
		"faith":
			penalty = GameState.truth * 0.15  # Truth erodes faith factions
		"truth":
			penalty = GameState.faith * 0.1   # Faith factions distrust truth seekers
		"violence":
			# Violence factions don't care about other forces as much
			penalty = 0.0

	return clampf(base_rep + bonus - penalty, -100.0, 100.0)


## Get attitude string based on effective reputation.
func get_attitude(faction_id: String) -> String:
	var rep := get_effective_reputation(faction_id)
	if rep <= HOSTILE_BELOW:
		return "hostile"
	elif rep <= UNFRIENDLY_BELOW:
		return "unfriendly"
	elif rep >= ALLIED_ABOVE:
		return "allied"
	elif rep >= FRIENDLY_ABOVE:
		return "friendly"
	else:
		return "neutral"


## Check if a faction is hostile to the player.
func is_hostile(faction_id: String) -> bool:
	return get_attitude(faction_id) == "hostile"


## Check if a faction is allied with the player.
func is_allied(faction_id: String) -> bool:
	return get_attitude(faction_id) == "allied"


## Get all factions matching a force alignment.
func get_factions_by_force(force_name: String) -> Array:
	var result: Array = []
	for faction_id in faction_defs:
		if faction_defs[faction_id].get("force_alignment", "") == force_name:
			result.append(faction_id)
	return result


## Get the display name for a faction.
func get_faction_name(faction_id: String) -> String:
	return faction_defs.get(faction_id, {}).get("name", faction_id)


func _on_force_changed(force_name: String, _old: float, _new: float) -> void:
	# When a force changes, check if any faction attitudes shifted
	for faction_id in faction_defs:
		var def: Dictionary = faction_defs[faction_id]
		if def.get("force_alignment", "") == force_name:
			# Recalculate — emit signal if attitude changed
			var attitude := get_attitude(faction_id)
			# Store previous attitude for comparison
			var prev: String = def.get("_last_attitude", "neutral")
			if prev != attitude:
				def["_last_attitude"] = attitude
				faction_attitude_changed.emit(faction_id, prev, attitude)
