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

# --- Phase Gating ---
# Escalation scales with game phase: early/mid/late.
# Phase is derived from world_pressure + max god attention + total force levels.
enum GamePhase { EARLY, MID, LATE }
var current_phase: GamePhase = GamePhase.EARLY

# Phase thresholds: calculated from combined escalation score (0-100)
const PHASE_MID_THRESHOLD := 30.0
const PHASE_LATE_THRESHOLD := 60.0

signal phase_changed(new_phase: int)


func get_escalation_score() -> float:
	var pressure_score := GameState.world_pressure  # 0-100
	var max_attention := 0.0
	for god_id in _god_attention:
		max_attention = maxf(max_attention, _god_attention[god_id])
	var force_sum := GameState.faith + GameState.truth + GameState.violence  # 0-300
	# Weighted blend: pressure matters most, then attention, then raw forces
	return clampf(pressure_score * 0.5 + max_attention * 0.3 + (force_sum / 300.0) * 100.0 * 0.2, 0.0, 100.0)


func _update_phase() -> void:
	var score := get_escalation_score()
	var old_phase := current_phase
	if score >= PHASE_LATE_THRESHOLD:
		current_phase = GamePhase.LATE
	elif score >= PHASE_MID_THRESHOLD:
		current_phase = GamePhase.MID
	else:
		current_phase = GamePhase.EARLY
	if old_phase != current_phase:
		phase_changed.emit(current_phase)


## Get a multiplier (0.0-1.0) that gates effect intensity by phase.
## early_mult: effect strength in early game, mid_mult: mid game, late_mult: late game
func get_phase_gate(early_mult: float = 0.0, mid_mult: float = 0.5, late_mult: float = 1.0) -> float:
	match current_phase:
		GamePhase.EARLY:
			return early_mult
		GamePhase.MID:
			return mid_mult
		GamePhase.LATE:
			return late_mult
	return 1.0


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

	# Update game phase
	_update_phase()

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

	# Check for retaliation (mid+ phase only)
	if current_phase != GamePhase.EARLY:
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
## Phase-gated: early phase suppresses most effects, mid allows watching, late unlocks obsessed.
## ANCHOR RULE: God attention events cannot target or affect anchor-immune nodes.
## The anchor's zone of influence is respected — gods cannot warp truth near the Keeper.
func _check_attention_events() -> void:
	# If the anchor is present, god interference events are suppressed near it.
	# Gods can still act, but their reality-warping effects are reduced.
	var anchor_present := AnchorManager.is_anchor_available()

	for god_id in _god_attention:
		var attention: float = _god_attention[god_id]
		if attention < ATTENTION_NOTICED:
			continue

		var god_name := get_god_name(god_id)

		# Noticed: occasional whisper hallucinations (all phases, reduced in early)
		if attention >= ATTENTION_NOTICED and attention < ATTENTION_WATCHING:
			var chance := 0.15 * get_phase_gate(0.3, 0.7, 1.0)
			if randf() < chance:
				var whispers := [
					"You hear something. A voice — maybe your own.",
					"The ash shifts. Something is paying attention.",
					"A pressure behind your eyes. Brief, then gone.",
				]
				WorldEventManager.event_notification.emit(
					"???", whispers[randi() % whispers.size()])

		# Watching: environmental hostility + stronger hallucinations (mid+ only)
		elif attention >= ATTENTION_WATCHING and attention < ATTENTION_OBSESSED:
			var gate := get_phase_gate(0.0, 0.6, 1.0)
			if gate <= 0.0:
				continue
			if randf() < 0.2 * gate:
				var messages := [
					"%s watches. You can feel it like heat on skin." % god_name,
					"The air bends around you. %s is aware." % god_name,
					"Your shadow moves wrong. %s is looking through it." % god_name,
				]
				WorldEventManager.event_notification.emit(
					god_name, messages[randi() % messages.size()])
			# Environmental hostility — force shifts
			if randf() < 0.1 * gate:
				GameState.add_force("faith", randf_range(-2.0, 2.0))

		# Obsessed: forced encounters + reality warping (late phase only)
		# ANCHOR RULE: When the anchor is present, obsession events are dampened.
		# Gods cannot fully warp reality when truth has a foothold.
		elif attention >= ATTENTION_OBSESSED:
			var gate := get_phase_gate(0.0, 0.2, 1.0)
			if gate <= 0.0:
				continue
			# Anchor dampening: halve obsession event chance when Keeper is present
			var obsession_chance := 0.25
			if anchor_present:
				obsession_chance *= 0.5
			if randf() < obsession_chance * gate:
				_emit_god_obsession_event(god_id, god_name)
			# Force inversion — gods warp the rules
			# ANCHOR RULE: Force inversions blocked entirely when anchor is present
			if not anchor_present and randf() < 0.08 * gate:
				# Check betrayal pacing before god interference
				if BetrayalPacing.can_betray("god_interference"):
					var forces := ["faith", "truth", "violence"]
					var target: String = forces[randi() % forces.size()]
					GameState.add_force(target, randf_range(-3.0, 3.0))
					WorldEventManager.event_notification.emit(
						god_name, "The forces shift without reason. %s interferes." % god_name)
					BetrayalPacing.record_betrayal("god_interference")


# --- God Obsession Asymmetry ---
# Each god invades differently when obsessed. Not a generic "divine presence" — each has personality.

func _emit_god_obsession_event(god_id: String, god_name: String) -> void:
	match god_id:
		"verath":
			# Verath (death/rebirth): Decay invasion — health flickers, world rots
			var effect := randi() % 3
			match effect:
				0:
					WorldEventManager.event_notification.emit(
						god_name, "Your skin itches. Something underneath is changing. Verath recycles.")
					# Health fluctuation — brief damage + heal
					GameState.player_health = maxf(GameState.player_health - 8.0, 1.0)
					god_event.emit(god_id, "health_pulse", {"damage": 8.0, "heal_delay": 2.0})
				1:
					WorldEventManager.event_notification.emit(
						"ASH MOTHER", "The ground softens. Roots push through stone. Verath is composting the world.")
					# Corruption spike in current zone
					for zone_id in GameState.region_state:
						var region: Dictionary = GameState.get_region(zone_id)
						region["corruption"] = minf(region.get("corruption", 0.0) + 5.0, 100.0)
				2:
					WorldEventManager.event_notification.emit(
						god_name, "You smell soil after rain. Your wounds ache, then ease. The cycle does not ask permission.")
					GameState.player_health = minf(GameState.player_health + 5.0, GameState.player_max_health)
		"kael":
			# Kael (light/judgment): Exposure invasion — forces revealed, truth forced
			var effect := randi() % 3
			match effect:
				0:
					WorldEventManager.event_notification.emit(
						"THE BLIND SUN", "Light pours from nowhere. Your sins are legible. Kael reads you.")
					# Truth spike — judgment exposes
					GameState.add_force("truth", 3.0)
				1:
					WorldEventManager.event_notification.emit(
						god_name, "Your eyes burn. For a moment you see every lie you've told rendered in gold.")
					god_event.emit(god_id, "ui_distortion", {"intensity": 0.7, "duration": 2.5})
				2:
					WorldEventManager.event_notification.emit(
						"JUDGMENT", "Kael's gaze strips away pretense. Faith wavers under scrutiny.")
					GameState.add_force("faith", -2.0)
					GameState.add_force("truth", 2.0)
		"null_throne":
			# Null Throne (void/absence): Erasure invasion — things disappear, silence deepens
			var effect := randi() % 3
			match effect:
				0:
					WorldEventManager.event_notification.emit(
						"...", "A word vanishes from your vocabulary. You can't remember which one.")
					ForceEffects.trigger_silence(3.0, 0.9)
				1:
					WorldEventManager.event_notification.emit(
						"THE ABSENCE", "Your shadow is gone. It will return, but not all of it.")
					god_event.emit(god_id, "ui_erasure", {"duration": 4.0})
				2:
					WorldEventManager.event_notification.emit(
						"", "Something was here. You're sure of it. The Null Throne answers prayers by subtraction.")
					# All forces drain slightly — the void takes
					GameState.add_force("faith", -1.5)
					GameState.add_force("truth", -1.5)
					GameState.add_force("violence", -1.5)
		_:
			# Fallback for any future gods
			WorldEventManager.event_notification.emit(
				"DIVINE PRESENCE", "%s SEES YOU. There is nowhere to hide." % god_name.to_upper())
	WorldMemory.record("god_obsession_%s_%d" % [god_id, randi() % 1000])


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
		# ANCHOR RULE: Retaliation is dampened (not blocked) near the Keeper.
		# Gods still notice silence, but the Keeper's presence softens the blow.
		if state in ["manifest", "ascended"] and silence > 120.0:
			var retaliation_chance := 0.2
			if AnchorManager.is_anchor_available():
				retaliation_chance *= 0.6
			if randf() < retaliation_chance:
				if BetrayalPacing.can_betray("god_interference"):
					_retaliate_silence(god_id, god_name)
					BetrayalPacing.record_betrayal("god_interference")

		# PUNISHMENT FOR DEVOTION: gods smothered by obsession
		if attention >= ATTENTION_OBSESSED:
			var devotion_chance := 0.15
			if AnchorManager.is_anchor_available():
				devotion_chance *= 0.6
			if randf() < devotion_chance:
				if BetrayalPacing.can_betray("god_interference"):
					_retaliate_devotion(god_id, god_name)
					BetrayalPacing.record_betrayal("god_interference")


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
