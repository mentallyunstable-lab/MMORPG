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
	if witness_mode:
		return  # Dead world cannot change
	var effective := _apply_diminishing_returns(force_name, amount)
	match force_name:
		"faith":
			faith += effective
		"truth":
			truth += effective
		"violence":
			violence += effective


## Diminishing returns: gains reduce as a force climbs.
## At 0-50: full gain. At 50-80: 70% gain. At 80+: 40% gain.
## Negative amounts (decay) are NOT diminished — penalties always hit full.
func _apply_diminishing_returns(force_name: String, amount: float) -> float:
	if amount <= 0:
		return amount  # Losses always apply fully
	var current := get_force(force_name)
	if current >= 80.0:
		return amount * 0.4
	elif current >= 50.0:
		return amount * 0.7
	return amount


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


# --- Ending Lock-in ---
# Once an ending triggers, the save is "closed". No reloading to before the ending.
# Witness mode: player can still walk the dead world, but cannot change it.
var save_closed: bool = false
var ending_type: String = ""
var ending_message: String = ""
var witness_mode: bool = false  # True when exploring post-ending world

const SAVE_PATH := "user://ashborn_save.dat"
const CLOSED_MESSAGE := "This world has concluded."

# --- Save Restrictions (Step 7) ---
# Manual save only. No saving during god attention spikes. Witness mode = no saving.
# Save zones are designated safe areas (interactables with "save_point" group).
var save_allowed: bool = true  # Set false during attention spikes, combat, etc.

signal save_blocked(reason: String)


## Check if saving is currently permitted.
func can_save() -> bool:
	# Never in witness mode
	if witness_mode:
		return false
	# Never when save is already closed
	if save_closed:
		return false
	# Block during god attention spikes (any god at watching+ level)
	for god_id in GodManager.god_defs:
		var attention := GodManager.get_god_attention(god_id)
		if attention >= GodManager.ATTENTION_WATCHING:
			return false
	# Block during active dialogue
	if DialogueManager.is_active:
		return false
	return save_allowed


## Save the game to disk. If ending has triggered, marks save as closed.
## In witness mode, don't overwrite — the world is frozen.
## Returns true if save succeeded, false if blocked.
func save_game() -> bool:
	if witness_mode:
		save_blocked.emit("The world is dead. There is nothing left to save.")
		return false
	if not can_save():
		# Determine reason
		for god_id in GodManager.god_defs:
			if GodManager.get_god_attention(god_id) >= GodManager.ATTENTION_WATCHING:
				save_blocked.emit("Something is watching. You cannot save here.")
				return false
		save_blocked.emit("You cannot save right now.")
		return false
	var data := save_state()
	data["save_closed"] = save_closed
	data["ending_type"] = ending_type
	data["ending_message"] = ending_message
	data["world_memory"] = WorldMemory.save_state()
	data["god_attention"] = GodManager.save_attention()
	data["quests"] = QuestManager.save_state()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		return true
	return false


## Load the game from disk. Refuses to load if save is closed.
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return false

	var data: Dictionary = json.data

	# ENDING LOCK-IN: if save is closed, enter witness mode instead of refusing
	if data.get("save_closed", false):
		save_closed = true
		witness_mode = true
		ending_type = data.get("ending_type", "")
		ending_message = data.get("ending_message", CLOSED_MESSAGE)
		# Load the world state so the player can walk through it
		load_state(data)
		if data.has("world_memory"):
			WorldMemory.load_state(data["world_memory"])
		if data.has("god_attention"):
			GodManager.load_attention(data["god_attention"])
		# Don't load quests — they're done
		WorldEventManager.event_notification.emit(
			"WITNESS", "This world has ended. You may walk its remains.")
		WorldMemory.record("witness_mode_entered")
		return true

	load_state(data)
	if data.has("world_memory"):
		WorldMemory.load_state(data["world_memory"])
	if data.has("god_attention"):
		GodManager.load_attention(data["god_attention"])
	if data.has("quests"):
		QuestManager.load_state(data["quests"])
	return true


## Called when an ending is reached — locks the save permanently.
func lock_ending(type: String, message: String) -> void:
	save_closed = true
	ending_type = type
	ending_message = message
	save_game()


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
