extends Node
## CombatPsychology - Player mood recognition through subtle cues
##
## PRIORITY #7
## "If they can't recognize it, it's just VFX."
##
## Six moods with recognition cues:
## - Breathing rhythm
## - Camera inertia signature
## - Audio filter fingerprint
##
## Players must be able to internally label moods without UI

signal mood_changed(old_mood: CombatMood, new_mood: CombatMood)
signal mood_cue_applied(mood: CombatMood, cue_type: String)

## Combat moods
enum CombatMood {
	CALM,       # Baseline state
	FOCUSED,    # Heightened awareness, controlled
	AGGRESSIVE, # Attack-oriented, reckless
	DEFENSIVE,  # Self-preservation dominant
	PANICKED,   # Fight-or-flight, erratic
	DISSOCIATED,# Detached, witness-like state
}

## Current mood state
var current_mood: CombatMood = CombatMood.CALM
var mood_intensity: float = 0.0  # 0.0 to 1.0
var mood_duration: float = 0.0

## Mood cue configurations
## Each mood has unique, subtle, recurring cues
var mood_cues: Dictionary = {
	CombatMood.CALM: {
		"breathing_rhythm": 4.0,        # Seconds per breath cycle
		"breathing_depth": 0.3,         # Animation intensity
		"camera_inertia": 0.1,          # Low inertia, responsive
		"camera_sway": 0.0,             # No sway
		"audio_filter": "none",         # Clean audio
		"audio_reverb": 0.0,
	},
	CombatMood.FOCUSED: {
		"breathing_rhythm": 3.0,        # Slightly faster
		"breathing_depth": 0.4,
		"camera_inertia": 0.05,         # Very responsive
		"camera_sway": 0.0,
		"audio_filter": "slight_clarity", # Sounds slightly sharper
		"audio_reverb": -0.1,           # Less reverb
	},
	CombatMood.AGGRESSIVE: {
		"breathing_rhythm": 2.0,        # Fast, heavy
		"breathing_depth": 0.7,
		"camera_inertia": 0.15,         # Slight lag, momentum
		"camera_sway": 0.02,            # Subtle forward lean
		"audio_filter": "bass_boost",   # Heavier sounds
		"audio_reverb": 0.1,
	},
	CombatMood.DEFENSIVE: {
		"breathing_rhythm": 2.5,        # Quick, shallow
		"breathing_depth": 0.2,
		"camera_inertia": 0.2,          # Heavier, reluctant
		"camera_sway": -0.01,           # Slight backward lean
		"audio_filter": "muffled",      # Sounds slightly distant
		"audio_reverb": 0.2,
	},
	CombatMood.PANICKED: {
		"breathing_rhythm": 1.5,        # Rapid, erratic
		"breathing_depth": 0.9,
		"camera_inertia": 0.3,          # Jerky, delayed
		"camera_sway": 0.05,            # Visible shake
		"audio_filter": "heartbeat",    # Heartbeat overlay
		"audio_reverb": 0.4,            # Sounds echo
	},
	CombatMood.DISSOCIATED: {
		"breathing_rhythm": 6.0,        # Slow, detached
		"breathing_depth": 0.1,         # Barely visible
		"camera_inertia": 0.5,          # Floaty, disconnected
		"camera_sway": 0.01,            # Gentle drift
		"audio_filter": "underwater",   # Muted, distant
		"audio_reverb": 0.6,            # Heavy echo
	},
}

## Transition configuration
var transition_speed: float = 2.0  # Seconds for full transition
var _transition_progress: float = 0.0
var _transitioning_from: CombatMood = CombatMood.CALM
var _is_transitioning: bool = false


func _ready() -> void:
	current_mood = CombatMood.CALM


func _process(delta: float) -> void:
	mood_duration += delta

	if _is_transitioning:
		_update_transition(delta)


func set_mood(new_mood: CombatMood, intensity: float = 1.0) -> void:
	if new_mood == current_mood:
		mood_intensity = intensity
		return

	var old_mood := current_mood
	_transitioning_from = current_mood
	current_mood = new_mood
	mood_intensity = intensity
	mood_duration = 0.0

	_is_transitioning = true
	_transition_progress = 0.0

	mood_changed.emit(old_mood, new_mood)


func _update_transition(delta: float) -> void:
	_transition_progress += delta / transition_speed

	if _transition_progress >= 1.0:
		_transition_progress = 1.0
		_is_transitioning = false

	# Apply interpolated cues during transition
	_apply_blended_cues()


func _apply_blended_cues() -> void:
	var from_cues: Dictionary = mood_cues[_transitioning_from]
	var to_cues: Dictionary = mood_cues[current_mood]
	var t := _transition_progress

	var blended := {
		"breathing_rhythm": lerp(from_cues["breathing_rhythm"], to_cues["breathing_rhythm"], t),
		"breathing_depth": lerp(from_cues["breathing_depth"], to_cues["breathing_depth"], t),
		"camera_inertia": lerp(from_cues["camera_inertia"], to_cues["camera_inertia"], t),
		"camera_sway": lerp(from_cues["camera_sway"], to_cues["camera_sway"], t),
		"audio_reverb": lerp(from_cues["audio_reverb"], to_cues["audio_reverb"], t),
	}

	# Audio filter crossfade handled separately
	if t > 0.5:
		blended["audio_filter"] = to_cues["audio_filter"]
	else:
		blended["audio_filter"] = from_cues["audio_filter"]

	_apply_cues(blended)


func _apply_cues(cues: Dictionary) -> void:
	## Apply cues to game systems
	## TODO: Connect to actual breathing, camera, and audio systems

	mood_cue_applied.emit(current_mood, "breathing")
	mood_cue_applied.emit(current_mood, "camera")
	mood_cue_applied.emit(current_mood, "audio")


func get_current_cues() -> Dictionary:
	if _is_transitioning:
		var from_cues: Dictionary = mood_cues[_transitioning_from]
		var to_cues: Dictionary = mood_cues[current_mood]
		var t := _transition_progress

		return {
			"breathing_rhythm": lerp(from_cues["breathing_rhythm"], to_cues["breathing_rhythm"], t),
			"breathing_depth": lerp(from_cues["breathing_depth"], to_cues["breathing_depth"], t),
			"camera_inertia": lerp(from_cues["camera_inertia"], to_cues["camera_inertia"], t),
			"camera_sway": lerp(from_cues["camera_sway"], to_cues["camera_sway"], t),
			"audio_filter": mood_cues[current_mood]["audio_filter"],
			"audio_reverb": lerp(from_cues["audio_reverb"], to_cues["audio_reverb"], t),
		}

	return mood_cues[current_mood].duplicate()


func get_mood_info() -> Dictionary:
	return {
		"current_mood": CombatMood.keys()[current_mood],
		"intensity": mood_intensity,
		"duration": mood_duration,
		"is_transitioning": _is_transitioning,
		"transition_progress": _transition_progress,
	}


## Recognition validation - ensure cues are distinguishable
func validate_mood_recognition() -> Dictionary:
	## Debug function to check if moods are sufficiently different
	var issues: Array[String] = []

	for mood_a in CombatMood.values():
		for mood_b in CombatMood.values():
			if mood_a >= mood_b:
				continue

			var cues_a: Dictionary = mood_cues[mood_a]
			var cues_b: Dictionary = mood_cues[mood_b]

			# Check breathing difference
			var breath_diff := abs(cues_a["breathing_rhythm"] - cues_b["breathing_rhythm"])
			if breath_diff < 0.5:
				issues.append("Breathing too similar: %s vs %s" % [
					CombatMood.keys()[mood_a],
					CombatMood.keys()[mood_b]
				])

			# Check camera difference
			var inertia_diff := abs(cues_a["camera_inertia"] - cues_b["camera_inertia"])
			if inertia_diff < 0.05:
				issues.append("Camera inertia too similar: %s vs %s" % [
					CombatMood.keys()[mood_a],
					CombatMood.keys()[mood_b]
				])

	return {
		"valid": issues.size() == 0,
		"issues": issues,
	}
