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

	# False-positive escalation cue (fires once in MID phase)
	_check_false_positive()

	# Track attention drops — escalation never resets silently
	_check_attention_decay_notification()

	# God obsession arc progression
	_check_obsession_arc()


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
func _check_attention_events() -> void:
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
		elif attention >= ATTENTION_OBSESSED:
			var gate := get_phase_gate(0.0, 0.2, 1.0)
			if gate <= 0.0:
				continue
			if randf() < 0.25 * gate:
				_emit_god_obsession_event(god_id, god_name)
			# Force inversion — gods warp the rules
			if randf() < 0.08 * gate:
				var forces := ["faith", "truth", "violence"]
				var target: String = forces[randi() % forces.size()]
				GameState.add_force(target, randf_range(-3.0, 3.0))
				WorldEventManager.event_notification.emit(
					god_name, "The forces shift without reason. %s interferes." % god_name)


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


# --- False-Positive Escalation Cue ---
# The world lies once: in MID phase, emit a fake god-watching message when no god
# is actually watching. Creates paranoia. Only fires once per playthrough.

func _check_false_positive() -> void:
	if _false_positive_fired:
		return
	if current_phase != GamePhase.MID:
		return
	var score := get_escalation_score()
	if score < FALSE_POSITIVE_THRESHOLD or score > FALSE_POSITIVE_THRESHOLD + 10.0:
		return
	# Check that no god is actually watching
	for god_id in _god_attention:
		if _god_attention[god_id] >= ATTENTION_WATCHING:
			return  # Real watching — no need to lie
	# The lie: emit a fake watching notification
	_false_positive_fired = true
	var fake_messages := [
		"Something shifts in the periphery. A presence — or the memory of one.",
		"The ash stirs as if disturbed by breath. But there is no breath here.",
		"For a moment, the world feels watched. Then it doesn't. You're not sure which is worse.",
	]
	WorldEventManager.event_notification.emit(
		"???", fake_messages[randi() % fake_messages.size()])
	WorldMemory.record("false_positive_escalation")


# --- Escalation Decay Notification ---
# When god attention drops below a threshold, notify the player.
# Escalation never resets silently — the world acknowledges the shift.

func _check_attention_decay_notification() -> void:
	for god_id in _god_attention:
		var attention: float = _god_attention[god_id]
		var last_level: String = _last_notified_attention.get(god_id, "")
		var current_level := _get_attention_level(attention)

		# Detect drops: was at a level, now below it
		if last_level != "" and current_level == "" and last_level == "noticed":
			var god_name := get_god_name(god_id)
			WorldEventManager.event_notification.emit(
				god_name, "The pressure eases. %s turns away — for now." % god_name)
			WorldMemory.record_ambient("%s attention decayed from noticed" % god_name)
		elif last_level == "watching" and current_level in ["noticed", ""]:
			var god_name := get_god_name(god_id)
			WorldEventManager.event_notification.emit(
				god_name, "%s releases its gaze. The world breathes." % god_name)
			WorldMemory.record_ambient("%s attention decayed from watching" % god_name)
		elif last_level == "obsessed" and current_level in ["watching", "noticed", ""]:
			var god_name := get_god_name(god_id)
			WorldEventManager.event_notification.emit(
				god_name, "%s withdraws. The obsession fades — but nothing is forgotten." % god_name)
			WorldMemory.record_ambient("%s attention decayed from obsessed" % god_name)

		_last_notified_attention[god_id] = current_level


# --- God Retaliation Events ---
# Gods punish BOTH silence (neglect) and devotion (obsession).
# Effects are non-combat: UI distortion, NPC fear, force inversion.

var _retaliation_timer: float = 0.0
const RETALIATION_INTERVAL := 15.0
var _silence_tracker: Dictionary = {}  # god_id -> float (seconds since last interaction)

# --- False-Positive Cue (Phase 1.2) ---
# The world lies once: emits a fake escalation cue in MID phase to create paranoia.
var _false_positive_fired: bool = false
const FALSE_POSITIVE_THRESHOLD := 40.0  # escalation score where the lie happens

# --- Escalation Reset Tracking (Phase 1.2) ---
# Escalation never resets silently — notify when attention decays significantly.
var _last_notified_attention: Dictionary = {}  # god_id -> last notified level


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


# --- God Obsession Arc (Phase 3) ---
# Three stages: ambiguous early → system interruption mid → binary choice late.
# Each god has its own arc. The arc advances based on attention + phase.

signal obsession_arc_advanced(god_id: String, arc_stage: String)
signal obsession_invasion_started(god_id: String)
signal obsession_binary_choice(god_id: String)

var _obsession_arc_stage: Dictionary = {}  # god_id -> "none" | "ambiguous" | "interruption" | "choice"
var _invasion_active: Dictionary = {}  # god_id -> bool
var _invasion_timer: float = 0.0
const INVASION_CHECK_INTERVAL := 20.0

func _check_obsession_arc() -> void:
	_invasion_timer += ATTENTION_CHECK_INTERVAL
	if _invasion_timer < INVASION_CHECK_INTERVAL:
		return
	_invasion_timer = 0.0

	for god_id in _god_attention:
		var attention: float = _god_attention[god_id]
		var stage: String = _obsession_arc_stage.get(god_id, "none")
		var god_name := get_god_name(god_id)

		# Stage 1: Ambiguous (EARLY phase, attention >= noticed)
		# The god is maybe watching. Could be paranoia. Ambiguous signals.
		if stage == "none" and attention >= ATTENTION_NOTICED:
			_obsession_arc_stage[god_id] = "ambiguous"
			obsession_arc_advanced.emit(god_id, "ambiguous")
			var hints := [
				"Something changed in the way the ash settles near %s's territory." % god_name,
				"A sound that might be breathing. Or wind. Or nothing.",
				"The shadows move differently here. Probably nothing.",
			]
			WorldEventManager.event_notification.emit("???", hints[randi() % hints.size()])
			WorldMemory.record("obsession_ambiguous_%s" % god_id)

		# Stage 2: System Interruption (MID phase, attention >= watching)
		# The god interferes with game mechanics — not just narrative.
		elif stage == "ambiguous" and attention >= ATTENTION_WATCHING and current_phase != GamePhase.EARLY:
			_obsession_arc_stage[god_id] = "interruption"
			obsession_arc_advanced.emit(god_id, "interruption")
			_apply_system_interruption(god_id, god_name)
			WorldMemory.record("obsession_interruption_%s" % god_id)

		# Stage 3: Binary Choice (LATE phase, attention >= obsessed)
		# The player must choose: submit to the god or reject them. No middle ground.
		elif stage == "interruption" and attention >= ATTENTION_OBSESSED and current_phase == GamePhase.LATE:
			_obsession_arc_stage[god_id] = "choice"
			obsession_arc_advanced.emit(god_id, "choice")
			obsession_binary_choice.emit(god_id)
			WorldMemory.record("obsession_choice_%s" % god_id)

		# Invasion: if attention is obsessed and in MID+ phase, trigger zone alteration
		if attention >= ATTENTION_OBSESSED and not _invasion_active.get(god_id, false):
			if current_phase != GamePhase.EARLY:
				_trigger_obsession_invasion(god_id, god_name)


## System Interruption: the god interferes with game mechanics.
func _apply_system_interruption(god_id: String, god_name: String) -> void:
	match god_id:
		"verath":
			# Verath locks healing — wounds close on her schedule, not yours
			WorldEventManager.event_notification.emit(
				"ASH MOTHER", "Your wounds seal themselves. You didn't ask. Verath decided.")
			god_event.emit(god_id, "lock_healing", {"duration": 15.0})
			GameState.player_health = minf(GameState.player_health + 20.0, GameState.player_max_health)
		"kael":
			# Kael reveals hidden information — quest objectives glow, enemies visible through walls
			WorldEventManager.event_notification.emit(
				"THE BLIND SUN", "Everything is visible. Every secret, every hidden thing. Kael strips the world bare.")
			god_event.emit(god_id, "reveal_all", {"duration": 10.0})
			GameState.add_force("truth", 5.0)
		"null_throne":
			# Null Throne erases UI elements — HUD components vanish temporarily
			WorldEventManager.event_notification.emit(
				"...", "Parts of your awareness dissolve. The Null Throne is editing reality.")
			god_event.emit(god_id, "erase_ui", {"duration": 8.0})
			ForceEffects.trigger_silence(8.0, 0.95)


## Obsession Invasion: permanent zone alteration. No cutscene. Only mechanics change.
func _trigger_obsession_invasion(god_id: String, god_name: String) -> void:
	_invasion_active[god_id] = true
	obsession_invasion_started.emit(god_id)

	match god_id:
		"verath":
			# Permanent: ground spawns occasional heal-then-harm zones
			WorldEventManager.event_notification.emit(
				"", "The ground pulses. Verath has rooted herself into the terrain. This will not undo.")
			WorldMemory.record("invasion_verath")
			# Permanent corruption increase across all zones
			for zone_id in GameState.region_state:
				var region: Dictionary = GameState.get_region(zone_id)
				region["corruption"] = minf(region.get("corruption", 0.0) + 15.0, 100.0)
			# Faith permanently elevated
			GameState.add_force("faith", 8.0)
		"kael":
			# Permanent: all force changes are doubled (judgment intensifies everything)
			WorldEventManager.event_notification.emit(
				"", "Light sears from the ground. Kael has fused with the zone. Every action weighs more now.")
			WorldMemory.record("invasion_kael")
			GameState.add_force("truth", 10.0)
			# Signal to other systems that Kael's invasion amplifies forces
			god_event.emit(god_id, "force_amplify", {"multiplier": 2.0, "permanent": true})
		"null_throne":
			# Permanent: periodic silence pulses, force drain zone
			WorldEventManager.event_notification.emit(
				"", "Silence. Not the absence of sound — the absence of everything. The Null Throne is here now.")
			WorldMemory.record("invasion_null_throne")
			# Drain all forces
			GameState.add_force("faith", -5.0)
			GameState.add_force("truth", -5.0)
			GameState.add_force("violence", -5.0)
			god_event.emit(god_id, "void_zone", {"permanent": true})

	WorldMemory.record("obsession_invasion_%s" % god_id)
	WorldMemory.record_ambient("God invasion: %s has permanently altered the zone" % god_name)


# --- Persistence ---

func save_attention() -> Dictionary:
	return _god_attention.duplicate()


func load_attention(data: Dictionary) -> void:
	for god_id in data:
		_god_attention[god_id] = data[god_id]
