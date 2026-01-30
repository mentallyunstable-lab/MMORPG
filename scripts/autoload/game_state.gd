## GameState — Global autoload managing the Three Forces and world pressure.
## Faith, Truth, and Violence shape the world. This is NOT morality — it's world pressure.
extends Node

# --- Three Forces ---
# Range: 0.0 to 100.0 each. They are independent axes, not a triangle.
signal force_changed(force_name: String, old_value: float, new_value: float)
signal world_pressure_changed(pressure: float)
signal faction_reputation_changed(faction: String, value: float)

var faith: float = 0.0:
	set(v):
		var old := faith
		faith = clampf(v, 0.0, 100.0)
		if old != faith:
			force_changed.emit("faith", old, faith)
			_recalculate_pressure()

var truth: float = 0.0:
	set(v):
		var old := truth
		truth = clampf(v, 0.0, 100.0)
		if old != truth:
			force_changed.emit("truth", old, truth)
			_recalculate_pressure()

var violence: float = 0.0:
	set(v):
		var old := violence
		violence = clampf(v, 0.0, 100.0)
		if old != violence:
			force_changed.emit("violence", old, violence)
			_recalculate_pressure()

# Combined instability metric — high total pressure destabilizes the world.
var world_pressure: float = 0.0

# --- Faction Reputation ---
# Keys are faction names, values range -100 to 100.
var factions: Dictionary = {}

# --- God Stability ---
# Keys are god names, values range 0.0 (dead) to 100.0 (fully manifest).
var god_stability: Dictionary = {}

# --- Region State ---
# Key: zone_id, Value: Dictionary with belief_level, corruption, etc.
var region_state: Dictionary = {}

# --- Player Stats ---
var player_health: float = 100.0
var player_max_health: float = 100.0
var player_alive: bool = true


func _ready() -> void:
	pass


func _recalculate_pressure() -> void:
	var old_pressure := world_pressure
	world_pressure = (faith + truth + violence) / 3.0
	if old_pressure != world_pressure:
		world_pressure_changed.emit(world_pressure)


# --- Force API ---

func add_force(force_name: String, amount: float) -> void:
	match force_name:
		"faith":
			faith += amount
		"truth":
			truth += amount
		"violence":
			violence += amount


func get_dominant_force() -> String:
	if faith >= truth and faith >= violence:
		return "faith"
	elif truth >= faith and truth >= violence:
		return "truth"
	else:
		return "violence"


func get_force(force_name: String) -> float:
	match force_name:
		"faith":
			return faith
		"truth":
			return truth
		"violence":
			return violence
	return 0.0


# --- Faction API ---

func set_faction_reputation(faction: String, value: float) -> void:
	factions[faction] = clampf(value, -100.0, 100.0)
	faction_reputation_changed.emit(faction, factions[faction])


func change_faction_reputation(faction: String, delta: float) -> void:
	var current: float = factions.get(faction, 0.0)
	set_faction_reputation(faction, current + delta)


func get_faction_reputation(faction: String) -> float:
	return factions.get(faction, 0.0)


# --- God Stability API ---

func set_god_stability(god_name: String, value: float) -> void:
	god_stability[god_name] = clampf(value, 0.0, 100.0)


func get_god_stability(god_name: String) -> float:
	return god_stability.get(god_name, 50.0)


# --- Region State API ---

func get_region(zone_id: String) -> Dictionary:
	if not region_state.has(zone_id):
		region_state[zone_id] = {
			"belief_level": 50.0,
			"corruption": 0.0,
			"visited": false,
			"events_triggered": [],
		}
	return region_state[zone_id]


func set_region_value(zone_id: String, key: String, value: Variant) -> void:
	var region := get_region(zone_id)
	region[key] = value


# --- Serialization (save/load) ---

func save_state() -> Dictionary:
	return {
		"faith": faith,
		"truth": truth,
		"violence": violence,
		"factions": factions.duplicate(),
		"god_stability": god_stability.duplicate(),
		"region_state": region_state.duplicate(true),
		"player_health": player_health,
		"player_max_health": player_max_health,
		"player_alive": player_alive,
	}


func load_state(data: Dictionary) -> void:
	faith = data.get("faith", 0.0)
	truth = data.get("truth", 0.0)
	violence = data.get("violence", 0.0)
	factions = data.get("factions", {})
	god_stability = data.get("god_stability", {})
	region_state = data.get("region_state", {})
	player_health = data.get("player_health", 100.0)
	player_max_health = data.get("player_max_health", 100.0)
	player_alive = data.get("player_alive", true)
