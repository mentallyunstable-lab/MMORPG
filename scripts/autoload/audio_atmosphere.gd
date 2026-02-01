## AudioAtmosphere — Phase M: Sound does half the narrative work.
## Per-force ambient layers, silence as a mechanic, god whispers (directional,
## sometimes incorrect), audio lies (footsteps with no source).
## DO NOT RUSH THIS. Audio is the invisible storyteller.
extends Node

signal audio_layer_changed(layer_name: String, volume: float)
signal god_whisper(god_id: String, text: String, is_truthful: bool)
signal audio_lie(lie_type: String, data: Dictionary)
signal silence_mechanic_active(intensity: float)

# --- Per-Force Ambient Layers ---
# Each force has its own audio identity. They blend based on force levels.
# These are DESIGN specs — actual AudioStreamPlayer nodes attach to these.

var _force_audio_state: Dictionary = {
	"faith": {
		"volume": 0.0,           # 0-1 mix level
		"target_volume": 0.0,
		"description": "Low drone. Humming. Choir fragments. Distant bells that resolve into nothing.",
		"characteristics": [
			"warm_undertone",      # Low-frequency warmth
			"distant_bells",       # Periodic, irregular
			"choir_fragments",     # Brief vocal snippets, never complete melodies
			"breathing_rhythm",    # Subtle rhythmic pulse, like group breathing
		],
	},
	"truth": {
		"volume": 0.0,
		"target_volume": 0.0,
		"description": "Precise clicks. Machine hum. Static bursts. Detuned overtones.",
		"characteristics": [
			"mechanical_clicks",   # Precise, metronomic
			"static_pops",         # Random, sharp
			"detuned_harmonics",   # Slightly wrong notes
			"paper_rustle",        # Like pages turning by wind
		],
	},
	"violence": {
		"volume": 0.0,
		"target_volume": 0.0,
		"description": "Subsonic rumble. Heartbeat. Metal stress. Distorted impacts.",
		"characteristics": [
			"subsonic_rumble",     # Below hearing threshold, felt in chest
			"heartbeat_pulse",     # Irregular, speeds with violence level
			"metal_stress",        # Creaking, groaning metal
			"distorted_impacts",   # Muffled thuds, like something hitting earth far away
		],
	},
}

# --- Silence as a Mechanic ---
# Not just "audio turns off." Active silence — the removal of specific sounds
# to create discomfort. Silence is a presence, not an absence.

var _silence_intensity: float = 0.0    # 0 = normal, 1 = complete active silence
var _silence_target: float = 0.0
var _silence_layers_removed: int = 0   # How many audio layers have been ducked
const MAX_SILENCE_LAYERS := 8

# Which audio elements to remove in silence (ordered by removal priority)
var _silence_removal_order: Array[String] = [
	"ambient_wind",
	"distant_activity",
	"footstep_echo",
	"force_layer_secondary",
	"force_layer_primary",
	"environmental_hum",
	"ui_feedback_sounds",
	"player_breathing",  # Last to go — most intimate, most unsettling
]

# --- God Whispers ---
# Directional. Sometimes incorrect. Sometimes in the wrong god's voice.

var _whisper_timer: float = 0.0
var _whisper_cooldown: float = 15.0  # Minimum seconds between whispers

# --- Audio Lies ---
# Footsteps with no source. Doors closing that didn't close.
# Environmental sounds that have no environmental cause.

var _audio_lie_timer: float = 0.0
var _audio_lie_cooldown: float = 20.0
var _lies_told: int = 0  # Total audio lies — frequency increases with pressure


func _ready() -> void:
	GameState.force_changed.connect(_on_force_changed)
	ForceEffects.atmosphere_changed.connect(_on_atmosphere_changed)
	GodManager.god_attention_threshold.connect(_on_attention_threshold)


func _process(delta: float) -> void:
	_update_force_layers(delta)
	_update_silence(delta)
	_update_whispers(delta)
	_update_audio_lies(delta)


# --- Force Audio Layer Management ---

func _update_force_layers(delta: float) -> void:
	# Calculate target volumes based on force levels
	_force_audio_state["faith"]["target_volume"] = clampf(GameState.faith / 80.0, 0.0, 1.0)
	_force_audio_state["truth"]["target_volume"] = clampf(GameState.truth / 80.0, 0.0, 1.0)
	_force_audio_state["violence"]["target_volume"] = clampf(GameState.violence / 80.0, 0.0, 1.0)

	# Apply silence reduction
	for force in _force_audio_state:
		var state: Dictionary = _force_audio_state[force]
		var target: float = state["target_volume"] * (1.0 - _silence_intensity)
		state["volume"] = lerpf(state["volume"], target, delta * 0.5)

		# Only emit when volume changes significantly
		if absf(state["volume"] - state.get("_last_emitted", -1.0)) > 0.05:
			state["_last_emitted"] = state["volume"]
			audio_layer_changed.emit("force_%s" % force, state["volume"])


# --- Silence Mechanic ---

func _update_silence(delta: float) -> void:
	# Silence target from ForceEffects
	_silence_target = ForceEffects.silence_level

	# Additional silence triggers
	# After kills: brief silence (the world holds its breath)
	# At high pressure: ambient silence bleeds in
	if GameState.world_pressure >= 80.0:
		_silence_target = maxf(_silence_target, 0.3)

	# Witness mode: silence deepens over time
	if GameState.witness_mode:
		_silence_target = maxf(_silence_target, 0.5 + ForceEffects.decay_level * 0.4)

	# Smooth approach to target
	_silence_intensity = lerpf(_silence_intensity, _silence_target, delta * 0.8)

	# Calculate how many layers to remove
	var target_removed := int(_silence_intensity * MAX_SILENCE_LAYERS)
	if target_removed != _silence_layers_removed:
		var old_removed := _silence_layers_removed
		_silence_layers_removed = target_removed

		# Emit what was removed or restored
		if target_removed > old_removed and target_removed <= _silence_removal_order.size():
			var removed_name: String = _silence_removal_order[target_removed - 1]
			audio_layer_changed.emit(removed_name, 0.0)
		elif target_removed < old_removed and old_removed <= _silence_removal_order.size():
			var restored_name: String = _silence_removal_order[old_removed - 1]
			audio_layer_changed.emit(restored_name, 1.0)

	if _silence_intensity > 0.1:
		silence_mechanic_active.emit(_silence_intensity)


# --- God Whispers ---

func _update_whispers(delta: float) -> void:
	_whisper_timer += delta
	if _whisper_timer < _whisper_cooldown:
		return
	_whisper_timer = 0.0

	# Only whisper when a god is at least noticed
	var whispering_gods: Array = []
	for god_id in GodManager.god_defs:
		if GodManager.get_god_attention(god_id) >= GodManager.ATTENTION_NOTICED:
			if GodManager.get_god_state(god_id) != "dead":
				whispering_gods.append(god_id)

	if whispering_gods.size() == 0:
		return

	# Phase gate whispers
	var gate := GodManager.get_phase_gate(0.1, 0.5, 1.0)
	if randf() > 0.3 * gate:
		return

	# Pick a god to whisper
	var god_id: String = whispering_gods[randi() % whispering_gods.size()]
	var attention := GodManager.get_god_attention(god_id)

	# Determine whisper content
	var whisper_text := ""
	var is_truthful := true

	# Higher attention = more frequent, more intense whispers
	if attention >= GodManager.ATTENTION_OBSESSED:
		whisper_text = _get_obsessed_whisper(god_id)
		# Obsessed whispers are sometimes lies
		is_truthful = randf() > 0.4
	elif attention >= GodManager.ATTENTION_WATCHING:
		whisper_text = _get_watching_whisper(god_id)
		is_truthful = randf() > 0.2
	else:
		whisper_text = _get_noticed_whisper(god_id)
		is_truthful = true  # Early whispers are always truthful

	# Sometimes the whisper comes from the WRONG god's voice
	if whispering_gods.size() > 1 and randf() < 0.15:
		# Voice swap — the text is from one god but attributed to another
		var wrong_god: String = whispering_gods[randi() % whispering_gods.size()]
		while wrong_god == god_id and whispering_gods.size() > 1:
			wrong_god = whispering_gods[randi() % whispering_gods.size()]
		god_id = wrong_god
		is_truthful = false

	god_whisper.emit(god_id, whisper_text, is_truthful)

	# Directional: whispers come from a specific direction
	var direction := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()

	# Don't show as notification — this is audio-only.
	# The text is for subtitle/accessibility systems.
	WorldMemory.record_ambient("Whisper from %s: '%s'" % [
		GodManager.get_god_name(god_id), whisper_text])


func _get_noticed_whisper(god_id: String) -> String:
	var whispers := {
		"verath": [
			"...return...",
			"...the soil waits...",
			"...everything grows back...",
		],
		"kael": [
			"...look closer...",
			"...you missed something...",
			"...the truth is simpler than you think...",
		],
		"null_throne": [
			"...",
			"...       ...",
			"...you forgot...",
		],
	}
	var pool: Array = whispers.get(god_id, ["..."])
	return pool[randi() % pool.size()]


func _get_watching_whisper(god_id: String) -> String:
	var whispers := {
		"verath": [
			"I see your wounds. I could close them. Should I?",
			"The ash remembers you. Do you remember it?",
			"Stop running from the cycle. You are the cycle.",
		],
		"kael": [
			"You already know what I'm going to show you.",
			"The light doesn't lie. But it chooses what to illuminate.",
			"Your secrets have weight. I feel them.",
		],
		"null_throne": [
			"The word you can't remember — it was your name.",
			"I am the space between your thoughts.",
			"Something was removed. You didn't notice. That was the point.",
		],
	}
	var pool: Array = whispers.get(god_id, ["I see you."])
	return pool[randi() % pool.size()]


func _get_obsessed_whisper(god_id: String) -> String:
	var whispers := {
		"verath": [
			"YOU WILL RETURN TO ME. ALL THINGS DO.",
			"Your resistance is compost. I will use it.",
			"I am not angry. I am patient. These are not the same thing. Or they are.",
			"Die for me. Just once. See how it feels.",
		],
		"kael": [
			"EVERY LIE YOU TOLD IS WRITTEN IN LIGHT.",
			"I burned my own eyes so I could see clearly. What have you sacrificed?",
			"The judgment is already rendered. You are just now hearing it.",
			"Look at what you've done. I said LOOK.",
		],
		"null_throne": [
			"                                         ",
			"When you forget this conversation, I win.",
			"I am the god that should not exist. And yet. And yet.",
			"You will fill this throne with meaning. I will empty it again.",
		],
	}
	var pool: Array = whispers.get(god_id, ["You are mine."])
	return pool[randi() % pool.size()]


# --- Audio Lies ---
# Sounds that have no source. The world gaslights you through audio.

func _update_audio_lies(delta: float) -> void:
	_audio_lie_timer += delta

	# Frequency increases with world pressure and god attention
	var lie_frequency := _audio_lie_cooldown
	if GameState.world_pressure >= 60.0:
		lie_frequency *= 0.7
	if GameState.world_pressure >= 80.0:
		lie_frequency *= 0.5

	if _audio_lie_timer < lie_frequency:
		return
	_audio_lie_timer = 0.0

	var gate := GodManager.get_phase_gate(0.0, 0.3, 1.0)
	if randf() > 0.2 * gate:
		return

	var lie_type := randi() % 5
	match lie_type:
		0:
			# Footsteps with no source
			var direction := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			audio_lie.emit("phantom_footsteps", {
				"direction": direction,
				"description": "Footsteps. Close. But there's no one there.",
			})
		1:
			# Door closing that didn't close
			audio_lie.emit("phantom_door", {
				"description": "A door slams shut. Every door you can see is open.",
			})
		2:
			# Voice calling the player's name (they have no name)
			audio_lie.emit("phantom_voice", {
				"description": "Someone calls your name. You don't have one.",
			})
		3:
			# Combat sounds from empty area
			audio_lie.emit("phantom_combat", {
				"direction": Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized(),
				"description": "Steel on steel, far away. When you look, nothing.",
			})
		4:
			# Bell that doesn't exist
			audio_lie.emit("phantom_bell", {
				"description": "A bell tolls. There is no bell. There was never a bell.",
			})

	_lies_told += 1
	WorldMemory.record_ambient("Audio lie #%d" % _lies_told)


func _on_force_changed(_force_name: String, _old: float, _new: float) -> void:
	pass  # Layer updates happen in _process


func _on_atmosphere_changed(silence: float, _decay: float) -> void:
	_silence_target = maxf(_silence_target, silence)


func _on_attention_threshold(god_id: String, level: String) -> void:
	if level == "watching" or level == "obsessed":
		# Reduce whisper cooldown when attention rises
		_whisper_cooldown = maxf(_whisper_cooldown - 3.0, 5.0)


# --- Public API ---

## Get the current audio state for external audio systems.
func get_audio_state() -> Dictionary:
	return {
		"force_volumes": {
			"faith": _force_audio_state["faith"]["volume"],
			"truth": _force_audio_state["truth"]["volume"],
			"violence": _force_audio_state["violence"]["volume"],
		},
		"silence_intensity": _silence_intensity,
		"silence_layers_removed": _silence_layers_removed,
		"active_layer_names": _get_active_layers(),
		"lies_told": _lies_told,
	}


func _get_active_layers() -> Array[String]:
	var active: Array[String] = []
	for i in range(_silence_removal_order.size()):
		if i >= _silence_layers_removed:
			active.append(_silence_removal_order[i])
	return active
