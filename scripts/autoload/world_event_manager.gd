## WorldEventManager — Triggers one-time and recurring world events based on force thresholds,
## god states, faction attitudes, and region corruption.
## Events are the connective tissue between systems.
## DO NOT WRITE INTO OTHER SINGLETONS DIRECTLY — use controlled APIs (add_force, set_god_stability, etc.)
extends Node

signal event_triggered(event_id: String, data: Dictionary)
signal event_notification(title: String, description: String)
signal ending_reached(ending_type: String, description: String)

# Track which one-time events have fired
var triggered_events: Dictionary = {}
var _ending_triggered: bool = false

# Pending event queue (for sequencing)
var _event_queue: Array = []
var _processing_queue: bool = false

# Tick rate for checking conditions
const CHECK_INTERVAL := 3.0
var _timer: float = 0.0


func _ready() -> void:
	# Connect to all the systems that can trigger events
	ForceEffects.world_effect_triggered.connect(_on_world_effect)
	ForceEffects.force_tier_changed.connect(_on_force_tier_changed)
	GodManager.god_state_changed.connect(_on_god_state_changed)
	GodManager.god_event.connect(_on_god_event)
	FactionManager.faction_attitude_changed.connect(_on_faction_attitude_changed)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= CHECK_INTERVAL:
		_timer = 0.0
		_check_threshold_events()

	# Process event queue
	if not _processing_queue and _event_queue.size() > 0:
		_process_next_event()


## Check for events that should fire based on current world state.
func _check_threshold_events() -> void:
	# --- Violence destabilization ---
	if GameState.violence >= 80.0:
		_try_trigger("violence_world_crisis", {
			"title": "The World Bleeds",
			"description": "Unchecked violence has destabilized the region. Enemies grow stronger.\n[Triggered by Violence >= 80]",
			"effect": "enemy_buff",
		})

	# --- Faith dominance ---
	if GameState.faith >= 70.0 and GameState.truth < 30.0:
		_try_trigger("blind_faith_rising", {
			"title": "Blind Faith Rising",
			"description": "Faith smothers inquiry. Technology fails. Miracles manifest.\n[Triggered by high Faith, low Truth]",
			"effect": "tech_suppression",
		})

	# --- Truth dominance ---
	if GameState.truth >= 70.0 and GameState.faith < 30.0:
		_try_trigger("veil_torn", {
			"title": "The Veil Torn",
			"description": "Reality strips bare. The gods flicker. Nothing hides.\n[Triggered by high Truth, low Faith]",
			"effect": "god_erosion",
		})

	# --- Combined extremes ---
	if GameState.faith >= 60.0 and GameState.truth >= 60.0:
		_try_trigger("paradox_zone", {
			"title": "Paradox Zone",
			"description": "Faith and Truth collide. The world cannot reconcile both.\n[Triggered by Faith + Truth both >= 60]",
			"effect": "reality_fracture",
		})

	if GameState.violence >= 60.0 and GameState.faith >= 60.0:
		_try_trigger("holy_war", {
			"title": "Holy War",
			"description": "Faith fuels violence. Crusaders march.\n[Triggered by Violence + Faith both >= 60]",
			"effect": "faction_conflict",
		})

	if GameState.violence >= 60.0 and GameState.truth >= 60.0:
		_try_trigger("revolution", {
			"title": "Revolution",
			"description": "Truth seen, violence chosen. The old order burns.\n[Triggered by Violence + Truth both >= 60]",
			"effect": "faction_overthrow",
		})

	# --- All three critical ---
	if GameState.world_pressure >= 85.0:
		_try_trigger("ashfall", {
			"title": "Ashfall",
			"description": "The world pressure exceeds what reality can contain. Ash falls from a sky that shouldn't exist.\n[Triggered by World Pressure >= 85]",
			"effect": "world_transformation",
		})
		_check_ending("ashfall", "The ash falls. Reality buckles under the weight of all three forces.")

	# --- Region corruption ---
	for zone_id in GameState.region_state:
		var region: Dictionary = GameState.get_region(zone_id)
		var corruption: float = region.get("corruption", 0.0)
		if corruption >= 75.0:
			_try_trigger("corrupt_zone_" + zone_id, {
				"title": "Zone Corrupted: %s" % zone_id,
				"description": "This region has been consumed by instability.",
				"effect": "zone_corruption",
				"zone_id": zone_id,
			})


## Try to trigger a one-time event.
func _try_trigger(event_id: String, data: Dictionary) -> void:
	if triggered_events.has(event_id):
		return
	triggered_events[event_id] = true
	_event_queue.append({"id": event_id, "data": data})


## Process next queued event.
func _process_next_event() -> void:
	if _event_queue.size() == 0:
		return

	_processing_queue = true
	var entry: Dictionary = _event_queue.pop_front()
	var event_id: String = entry["id"]
	var data: Dictionary = entry["data"]

	event_triggered.emit(event_id, data)
	event_notification.emit(data.get("title", ""), data.get("description", ""))

	_apply_event_effects(event_id, data)

	# Brief delay between events
	await get_tree().create_timer(0.5).timeout
	_processing_queue = false


## Apply mechanical effects of an event.
func _apply_event_effects(event_id: String, data: Dictionary) -> void:
	var effect: String = data.get("effect", "")

	match effect:
		"enemy_buff":
			# All current enemies get stronger
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if "attack_damage" in enemy:
					enemy.attack_damage *= 1.25
				if "max_health" in enemy:
					enemy.max_health *= 1.2
					enemy.health = enemy.max_health

		"tech_suppression":
			# Ranged attacks weakened (player debuff — applied via GameState)
			# Placeholder: reduce ranged damage via a state flag
			GameState.set_region_value("global", "tech_suppressed", true)

		"god_erosion":
			# All gods lose stability
			for god_id in GodManager.god_defs:
				var current := GameState.get_god_stability(god_id)
				GameState.set_god_stability(god_id, current - 10.0)

		"reality_fracture":
			# Both faith and truth factions become unfriendly
			GameState.change_faction_reputation("ashwalkers", -20.0)
			GameState.change_faction_reputation("truthseekers", -20.0)

		"faction_conflict":
			# Faith and violence factions clash
			GameState.change_faction_reputation("hollow_church", -15.0)
			GameState.change_faction_reputation("ironvow", 10.0)

		"faction_overthrow":
			# Truth and violence alliance
			GameState.change_faction_reputation("truthseekers", 10.0)
			GameState.change_faction_reputation("ironvow", 5.0)

		"world_transformation":
			# Major event — could trigger endgame content
			for zone_id in GameState.region_state:
				var region: Dictionary = GameState.get_region(zone_id)
				region["corruption"] = minf(region.get("corruption", 0.0) + 25.0, 100.0)

		"zone_corruption":
			# Specific zone fully corrupted
			var zone_id: String = data.get("zone_id", "")
			if zone_id != "":
				GameState.set_region_value(zone_id, "fully_corrupted", true)


## Check if an ending condition has been reached. Fires once.
func _check_ending(ending_type: String, description: String) -> void:
	if _ending_triggered:
		return
	_ending_triggered = true
	ending_reached.emit(ending_type, description)
	event_notification.emit("THE END", description)


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"triggered_events": triggered_events.duplicate(),
		"ending_triggered": _ending_triggered,
	}


func load_state(save_data: Dictionary) -> void:
	triggered_events = save_data.get("triggered_events", {})
	_ending_triggered = save_data.get("ending_triggered", false)


# --- Listener callbacks ---

func _on_world_effect(effect_id: String, data: Dictionary) -> void:
	# ForceEffects fires these for critical thresholds
	event_triggered.emit("force_effect_" + effect_id, data)


func _on_force_tier_changed(force_name: String, tier: String) -> void:
	if tier == "critical":
		event_notification.emit(
			"%s Critical" % force_name.capitalize(),
			"The force of %s has reached critical levels." % force_name
		)


func _on_god_state_changed(god_id: String, _old_state: String, new_state: String) -> void:
	var god_name := GodManager.get_god_name(god_id)
	match new_state:
		"dead":
			event_notification.emit("God Slain", "%s has fallen." % god_name)
			_check_ending("god_death", "A god has died. The world will never be the same.")
		"ascended":
			event_notification.emit("God Ascended", "%s transcends." % god_name)
			_check_ending("god_ascension", "A god has transcended. Faith remade the world.")
		"fading":
			event_notification.emit("God Fading", "%s grows dim..." % god_name)


func _on_god_event(god_id: String, event_type: String, data: Dictionary) -> void:
	event_triggered.emit("god_" + event_type + "_" + god_id, data)


func _on_faction_attitude_changed(faction_id: String, _old: String, new_attitude: String) -> void:
	var faction_name := FactionManager.get_faction_name(faction_id)
	match new_attitude:
		"hostile":
			event_notification.emit("Faction Hostile", "%s now considers you an enemy." % faction_name)
		"allied":
			event_notification.emit("Faction Allied", "%s pledges support." % faction_name)
