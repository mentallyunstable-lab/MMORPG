## GodManager — Tracks gods, their stability, and how they manifest (or die).
## Gods weaken when Truth rises. Gods strengthen when Faith rises.
## Violence accelerates whatever is already happening.
## DO NOT WRITE INTO OTHER SINGLETONS DIRECTLY — use controlled APIs (add_force, set_god_stability, etc.)
extends Node

signal god_state_changed(god_id: String, old_state: String, new_state: String)
signal god_event(god_id: String, event_type: String, data: Dictionary)

# God state thresholds (based on stability 0-100)
const DEAD_BELOW := 5.0
const FADING_BELOW := 25.0
const WEAKENED_BELOW := 45.0
const MANIFEST_ABOVE := 75.0
const ASCENDED_ABOVE := 95.0

# God definitions
var god_defs: Dictionary = {}


func _ready() -> void:
	_register_default_gods()
	GameState.force_changed.connect(_on_force_changed)


func _register_default_gods() -> void:
	register_god("verath", {
		"name": "Verath, the Ash Mother",
		"domain": "death_and_rebirth",
		"starting_stability": 60.0,
		"description": "Goddess of cycles — death feeds life, ash feeds soil.",
	})
	register_god("kael", {
		"name": "Kael, the Blind Sun",
		"domain": "light_and_judgment",
		"starting_stability": 50.0,
		"description": "A god who burned his own eyes to judge without seeing.",
	})
	register_god("null_throne", {
		"name": "The Null Throne",
		"domain": "absence_and_void",
		"starting_stability": 30.0,
		"description": "Not a god — a place where a god should be. It still answers prayers.",
	})

	# Initialize stability in GameState
	for god_id in god_defs:
		var def: Dictionary = god_defs[god_id]
		if GameState.get_god_stability(god_id) == 50.0:  # default
			GameState.set_god_stability(god_id, def.get("starting_stability", 50.0))


func register_god(god_id: String, data: Dictionary) -> void:
	god_defs[god_id] = data
	data["_last_state"] = ""


## Get the state of a god based on stability.
func get_god_state(god_id: String) -> String:
	var stability := GameState.get_god_stability(god_id)
	if stability <= DEAD_BELOW:
		return "dead"
	elif stability <= FADING_BELOW:
		return "fading"
	elif stability <= WEAKENED_BELOW:
		return "weakened"
	elif stability >= ASCENDED_ABOVE:
		return "ascended"
	elif stability >= MANIFEST_ABOVE:
		return "manifest"
	else:
		return "dormant"


## Get display name.
func get_god_name(god_id: String) -> String:
	return god_defs.get(god_id, {}).get("name", god_id)


## Get all gods in a specific state.
func get_gods_in_state(state: String) -> Array:
	var result: Array = []
	for god_id in god_defs:
		if get_god_state(god_id) == state:
			result.append(god_id)
	return result


## Check if any god is dead.
func any_god_dead() -> bool:
	for god_id in god_defs:
		if get_god_state(god_id) == "dead":
			return true
	return false


## Check if any god has ascended.
func any_god_ascended() -> bool:
	for god_id in god_defs:
		if get_god_state(god_id) == "ascended":
			return true
	return false


func _on_force_changed(force_name: String, _old: float, new_value: float) -> void:
	for god_id in god_defs:
		var old_state := get_god_state(god_id)

		match force_name:
			"faith":
				# Faith reinforces all gods
				if new_value > 50.0:
					var boost := (new_value - 50.0) * 0.02
					var current := GameState.get_god_stability(god_id)
					GameState.set_god_stability(god_id, current + boost)

			"truth":
				# Truth erodes all gods
				if new_value > 30.0:
					var erosion := (new_value - 30.0) * 0.03
					var current := GameState.get_god_stability(god_id)
					GameState.set_god_stability(god_id, current - erosion)

			"violence":
				# Violence accelerates current trajectory
				if new_value > 60.0:
					var current := GameState.get_god_stability(god_id)
					if current > 50.0:
						# God is strong — violence pushes higher
						GameState.set_god_stability(god_id, current + 0.5)
					elif current < 50.0:
						# God is weak — violence pushes lower
						GameState.set_god_stability(god_id, current - 0.5)

		var new_state := get_god_state(god_id)
		if old_state != new_state:
			var def: Dictionary = god_defs[god_id]
			def["_last_state"] = new_state
			god_state_changed.emit(god_id, old_state, new_state)

			# Emit specific events for major transitions
			if new_state == "dead":
				god_event.emit(god_id, "god_died", {"name": get_god_name(god_id)})
			elif new_state == "ascended":
				god_event.emit(god_id, "god_ascended", {"name": get_god_name(god_id)})
			elif new_state == "fading":
				god_event.emit(god_id, "god_fading", {"name": get_god_name(god_id)})
