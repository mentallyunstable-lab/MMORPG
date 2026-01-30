## WorldMemory — Stores irreversible flags about what the player has done.
## Once recorded, a memory cannot be unrecorded. The world remembers.
## Used by NPCs, quests, and events to react to player history.
extends Node

signal memory_recorded(flag: String)

# Irreversible flags — once set, they stay set forever (even across saves).
var _flags: Dictionary = {}

# Ambient memory — things NPCs can reference in dialogue
var _ambient: Array[String] = []
const MAX_AMBIENT := 20


## Record an irreversible world memory. Cannot be undone.
func record(flag: String) -> void:
	if _flags.has(flag):
		return
	_flags[flag] = Time.get_unix_time_from_system()
	memory_recorded.emit(flag)


## Check if a memory exists.
func has_memory(flag: String) -> bool:
	return _flags.has(flag)


## Record an ambient event (recent context for NPC dialogue).
func record_ambient(text: String) -> void:
	_ambient.append(text)
	if _ambient.size() > MAX_AMBIENT:
		_ambient.pop_front()


## Get recent ambient memories.
func get_recent_ambient(count: int = 5) -> Array[String]:
	var start := maxi(0, _ambient.size() - count)
	return _ambient.slice(start) as Array[String]


## Get all memory flags as a list.
func get_all_flags() -> Array:
	return _flags.keys()


# --- Auto-recording from signals ---

func _ready() -> void:
	WorldEventManager.ending_reached.connect(_on_ending)
	WorldEventManager.event_triggered.connect(_on_event)
	GodManager.god_state_changed.connect(_on_god_state)
	FactionManager.faction_attitude_changed.connect(_on_faction_change)


func _on_ending(ending_type: String, _desc: String) -> void:
	record("ending_%s" % ending_type)


func _on_event(event_id: String, _data: Dictionary) -> void:
	record("event_%s" % event_id)
	record_ambient("World event: %s" % event_id)


func _on_god_state(god_id: String, _old: String, new_state: String) -> void:
	if new_state == "dead":
		record("god_killed_%s" % god_id)
		record_ambient("%s has died" % god_id)
	elif new_state == "ascended":
		record("god_ascended_%s" % god_id)
		record_ambient("%s has ascended" % god_id)


func _on_faction_change(faction_id: String, _old: String, new_attitude: String) -> void:
	if new_attitude == "hostile":
		record("faction_hostile_%s" % faction_id)
		record_ambient("%s turned hostile" % faction_id)
	elif new_attitude == "allied":
		record("faction_allied_%s" % faction_id)


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"flags": _flags.duplicate(),
		"ambient": _ambient.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	_flags = data.get("flags", {})
	var loaded_ambient = data.get("ambient", [])
	_ambient.clear()
	for item in loaded_ambient:
		_ambient.append(str(item))
