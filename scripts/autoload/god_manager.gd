## GodManager — Tracks gods, their stability, and how they manifest (or die).
## Gods weaken when Truth rises. Gods strengthen when Faith rises.
## Violence accelerates whatever is already happening.
## DO NOT WRITE INTO OTHER SINGLETONS DIRECTLY — use controlled APIs (add_force, set_god_stability, etc.)
extends Node

signal god_state_changed(god_id: String, old_state: String, new_state: String)
signal god_event(god_id: String, event_type: String, data: Dictionary)
signal god_attention_threshold(god_id: String, level: String)  # "noticed", "watching", "obsessed"

# God state thresholds (based on stability 0-100)
const DEAD_BELOW := 5.0
const FADING_BELOW := 25.0
const WEAKENED_BELOW := 45.0
const MANIFEST_ABOVE := 75.0
const ASCENDED_ABOVE := 95.0

# God attention thresholds (hidden)
const ATTENTION_NOTICED := 30.0
const ATTENTION_WATCHING := 60.0
const ATTENTION_OBSESSED := 90.0

# God definitions
var god_defs: Dictionary = {}

# Hidden attention per god — rises with prayers, force spikes, dialogue defiance
var _god_attention: Dictionary = {}  # god_id -> float (0-100)
var _attention_check_timer: float = 0.0
const ATTENTION_CHECK_INTERVAL := 5.0


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
	_god_attention[god_id] = 0.0


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

		# Force spikes raise attention for all gods
		if absf(new_value - _old) > 3.0:
			add_god_attention(god_id, absf(new_value - _old) * 0.3)


# --- God Attention System (Hidden) ---

func _process(delta: float) -> void:
	_attention_check_timer += delta
	if _attention_check_timer < ATTENTION_CHECK_INTERVAL:
		return
	_attention_check_timer = 0.0

	# Attention naturally decays slowly — gods lose interest
	for god_id in _god_attention:
		if get_god_state(god_id) == "dead":
			_god_attention[god_id] = 0.0
			continue
		_god_attention[god_id] = maxf(_god_attention[god_id] - 0.5, 0.0)

	# Track silence (time since last god interaction)
	for god_id in _silence_tracker:
		_silence_tracker[god_id] += ATTENTION_CHECK_INTERVAL

	# Check for attention-based events
	_check_attention_events()

	# Check for retaliation
	_check_retaliation()


## Add attention from a specific god. Called externally by GodEncounter, shrines, etc.
func add_god_attention(god_id: String, amount: float) -> void:
	if get_god_state(god_id) == "dead":
		return
	var old_attention: float = _god_attention.get(god_id, 0.0)
	var new_attention := clampf(old_attention + amount, 0.0, 100.0)
	_god_attention[god_id] = new_attention

	# Check threshold crossings
	var old_level := _get_attention_level(old_attention)
	var new_level := _get_attention_level(new_attention)
	if old_level != new_level and new_level != "":
		god_attention_threshold.emit(god_id, new_level)
		WorldMemory.record("god_attention_%s_%s" % [god_id, new_level])


## Get attention level string for a value.
func _get_attention_level(value: float) -> String:
	if value >= ATTENTION_OBSESSED:
		return "obsessed"
	elif value >= ATTENTION_WATCHING:
		return "watching"
	elif value >= ATTENTION_NOTICED:
		return "noticed"
	return ""


## Get current attention value for a god.
func get_god_attention(god_id: String) -> float:
	return _god_attention.get(god_id, 0.0)


## Check for attention-driven events — hallucinations, hostile env, forced encounters.
func _check_attention_events() -> void:
	for god_id in _god_attention:
		var attention: float = _god_attention[god_id]
		if attention < ATTENTION_NOTICED:
			continue

		var god_name := get_god_name(god_id)

		# Noticed: occasional whisper hallucinations
		if attention >= ATTENTION_NOTICED and attention < ATTENTION_WATCHING:
			if randf() < 0.15:  # 15% chance per check
				var whispers := [
					"You hear something. A voice — maybe your own.",
					"The ash shifts. Something is paying attention.",
					"A pressure behind your eyes. Brief, then gone.",
				]
				WorldEventManager.event_notification.emit(
					"???", whispers[randi() % whispers.size()])

		# Watching: environmental hostility + stronger hallucinations
		elif attention >= ATTENTION_WATCHING and attention < ATTENTION_OBSESSED:
			if randf() < 0.2:
				var messages := [
					"%s watches. You can feel it like heat on skin." % god_name,
					"The air bends around you. %s is aware." % god_name,
					"Your shadow moves wrong. %s is looking through it." % god_name,
				]
				WorldEventManager.event_notification.emit(
					god_name, messages[randi() % messages.size()])
			# Environmental hostility — force shifts
			if randf() < 0.1:
				GameState.add_force("faith", randf_range(-2.0, 2.0))

		# Obsessed: forced encounters + reality warping
		elif attention >= ATTENTION_OBSESSED:
			if randf() < 0.25:
				var messages := [
					"%s SEES YOU. There is nowhere to hide." % god_name.to_upper(),
					"Reality folds. %s is reaching through." % god_name,
					"Your hands are not your own for a moment. %s is here." % god_name,
				]
				WorldEventManager.event_notification.emit(
					"DIVINE PRESENCE", messages[randi() % messages.size()])
			# Force inversion — gods warp the rules
			if randf() < 0.08:
				var forces := ["faith", "truth", "violence"]
				var target: String = forces[randi() % forces.size()]
				GameState.add_force(target, randf_range(-3.0, 3.0))
				WorldEventManager.event_notification.emit(
					god_name, "The forces shift without reason. %s interferes." % god_name)


# --- God Retaliation Events ---
# Gods punish BOTH silence (neglect) and devotion (obsession).
# Effects are non-combat: UI distortion, NPC fear, force inversion.

var _retaliation_timer: float = 0.0
const RETALIATION_INTERVAL := 15.0
var _silence_tracker: Dictionary = {}  # god_id -> float (seconds since last interaction)


## Called externally whenever the player interacts with anything god-related.
func mark_god_interaction(god_id: String) -> void:
	_silence_tracker[god_id] = 0.0
	add_god_attention(god_id, 5.0)


func _check_retaliation() -> void:
	_retaliation_timer += ATTENTION_CHECK_INTERVAL
	if _retaliation_timer < RETALIATION_INTERVAL:
		return
	_retaliation_timer = 0.0

	for god_id in god_defs:
		var state := get_god_state(god_id)
		if state == "dead":
			continue

		var god_name := get_god_name(god_id)
		var silence: float = _silence_tracker.get(god_id, 999.0)
		var attention: float = _god_attention.get(god_id, 0.0)

		# PUNISHMENT FOR SILENCE: manifest+ gods that are ignored
		if state in ["manifest", "ascended"] and silence > 120.0:
			if randf() < 0.2:
				_retaliate_silence(god_id, god_name)

		# PUNISHMENT FOR DEVOTION: gods smothered by obsession
		if attention >= ATTENTION_OBSESSED:
			if randf() < 0.15:
				_retaliate_devotion(god_id, god_name)


func _retaliate_silence(god_id: String, god_name: String) -> void:
	var effect := randi() % 3
	match effect:
		0:
			WorldEventManager.event_notification.emit(
				god_name, "The air grows heavy. %s does not appreciate being forgotten." % god_name)
			WorldMemory.record_ambient("%s punished silence" % god_name)
		1:
			GameState.add_force("faith", -3.0)
			GameState.add_force("truth", 2.0)
			WorldEventManager.event_notification.emit(
				god_name, "Your certainties crack. %s withdraws warmth." % god_name)
		2:
			var current := GameState.get_god_stability(god_id)
			GameState.set_god_stability(god_id, current - 3.0)
			WorldEventManager.event_notification.emit(
				god_name, "%s dims. Silence is its own kind of violence." % god_name)
	WorldMemory.record("god_retaliation_silence_%s" % god_id)


func _retaliate_devotion(god_id: String, god_name: String) -> void:
	var effect := randi() % 3
	match effect:
		0:
			god_event.emit(god_id, "ui_distortion", {"intensity": 0.5, "duration": 3.0})
			WorldEventManager.event_notification.emit(
				"???", "Your vision warps. Too much devotion. %s pushes back." % god_name)
		1:
			GameState.add_force("violence", 4.0)
			WorldEventManager.event_notification.emit(
				god_name, "Worship turned to pressure. The world absorbs it as violence.")
		2:
			WorldEventManager.event_notification.emit(
				god_name, "NPCs flinch when you pass. %s clings to you like smoke." % god_name)
			WorldMemory.record_ambient("NPCs fear divine presence of %s" % god_name)
	WorldMemory.record("god_retaliation_devotion_%s" % god_id)


# --- Persistence ---

func save_attention() -> Dictionary:
	return _god_attention.duplicate()


func load_attention(data: Dictionary) -> void:
	for god_id in data:
		_god_attention[god_id] = data[god_id]
