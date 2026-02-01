## CrossZonePersistence — Phase H2: Decisions in one zone change other zones.
## Patrol routes, ambient events, god memory of what you did AND refused to do.
extends Node

signal cross_zone_effect_applied(source_zone: String, target_zone: String, effect: String)

# Tracks decisions per zone that affect other zones
var _zone_decisions: Dictionary = {}  # zone_id -> Array of decision strings

# Patrol route modifiers: zone_id -> Dictionary of modifier data
var _patrol_modifiers: Dictionary = {}

# Locked/unlocked ambient events per zone
var _ambient_event_locks: Dictionary = {}  # zone_id -> {event_id: bool}


func _ready() -> void:
	WorldManager.zone_loaded.connect(_on_zone_loaded)
	WorldMemory.memory_recorded.connect(_on_memory_recorded)


func _on_zone_loaded(zone_id: String) -> void:
	_apply_pending_effects(zone_id)


## Record a zone decision that will ripple outward.
func record_zone_decision(source_zone: String, decision: String) -> void:
	if not _zone_decisions.has(source_zone):
		_zone_decisions[source_zone] = []
	if decision not in _zone_decisions[source_zone]:
		_zone_decisions[source_zone].append(decision)
		_propagate_decision(source_zone, decision)


## Apply pending cross-zone effects when a zone loads.
func _apply_pending_effects(zone_id: String) -> void:
	# Ashborn Depth decisions affecting Hollowed Seminary
	if zone_id == "hollowed_seminary":
		_apply_ashborn_to_seminary()
	elif zone_id == "test_zone":
		_apply_seminary_to_ashborn()


func _apply_ashborn_to_seminary() -> void:
	# Violence in Ashborn Depth -> Seminary patrols tighten
	if WorldMemory.has_memory("event_violence_world_crisis"):
		_patrol_modifiers["hollowed_seminary"] = {
			"detection_range_mult": 1.3,
			"patrol_speed_mult": 1.2,
			"aggression_bias": "violence",
		}
		cross_zone_effect_applied.emit("test_zone", "hollowed_seminary", "patrol_tighten")

	# God deaths propagate fear
	for god_id in ["verath", "kael", "null_throne"]:
		if WorldMemory.has_memory("god_killed_%s" % god_id):
			_ambient_event_locks["hollowed_seminary"] = _ambient_event_locks.get("hollowed_seminary", {})
			_ambient_event_locks["hollowed_seminary"]["god_shrine_%s" % god_id] = false  # Shrine disabled
			_ambient_event_locks["hollowed_seminary"]["god_mourning_%s" % god_id] = true  # Mourning event unlocked
			cross_zone_effect_applied.emit("test_zone", "hollowed_seminary", "god_death_echo_%s" % god_id)

	# Holy war in Ashborn -> Seminary becomes a war zone
	if WorldMemory.has_memory("event_holy_war"):
		_patrol_modifiers["hollowed_seminary"] = _patrol_modifiers.get("hollowed_seminary", {})
		_patrol_modifiers["hollowed_seminary"]["faction_conflict"] = true
		cross_zone_effect_applied.emit("test_zone", "hollowed_seminary", "holy_war_spillover")

	# Quest outcomes propagate
	if WorldMemory.has_memory("quest_failed_ashes_of_forgotten"):
		# The Hollow Church blames the player — Seminary is more hostile
		GameState.change_faction_reputation("hollow_church", -10.0)
		cross_zone_effect_applied.emit("test_zone", "hollowed_seminary", "quest_failure_reputation")


func _apply_seminary_to_ashborn() -> void:
	# Resonance Hall revealed -> truth seekers gain influence in Ashborn
	if WorldMemory.has_memory("resonance_hall_revealed"):
		GameState.change_faction_reputation("truthseekers", 5.0)
		cross_zone_effect_applied.emit("hollowed_seminary", "test_zone", "truth_influence_spread")

	# Bell tower accessed -> all zones gain mild corruption
	if WorldMemory.has_memory("bell_tower_accessed"):
		for zone_id in GameState.region_state:
			var region: Dictionary = GameState.get_region(zone_id)
			region["corruption"] = minf(region.get("corruption", 0.0) + 5.0, 100.0)
		cross_zone_effect_applied.emit("hollowed_seminary", "test_zone", "bell_tower_corruption")


func _propagate_decision(source_zone: String, decision: String) -> void:
	WorldMemory.record("zone_decision_%s_%s" % [source_zone, decision])
	WorldMemory.record_ambient("Decision in %s: %s" % [source_zone, decision])


## God memory: what you REFUSED to do matters as much as what you did.
func _on_memory_recorded(flag: String) -> void:
	# Track god-related refusals by checking what HASN'T happened
	# This is checked periodically, not on every memory
	pass


## Get patrol modifiers for a zone (used by enemy spawners).
func get_patrol_modifiers(zone_id: String) -> Dictionary:
	return _patrol_modifiers.get(zone_id, {})


## Check if an ambient event is locked/unlocked for a zone.
func is_event_available(zone_id: String, event_id: String) -> bool:
	if not _ambient_event_locks.has(zone_id):
		return true
	return _ambient_event_locks.get(zone_id, {}).get(event_id, true)


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"zone_decisions": _zone_decisions.duplicate(true),
		"patrol_modifiers": _patrol_modifiers.duplicate(true),
		"ambient_event_locks": _ambient_event_locks.duplicate(true),
	}


func load_state(data: Dictionary) -> void:
	_zone_decisions = data.get("zone_decisions", {})
	_patrol_modifiers = data.get("patrol_modifiers", {})
	_ambient_event_locks = data.get("ambient_event_locks", {})
