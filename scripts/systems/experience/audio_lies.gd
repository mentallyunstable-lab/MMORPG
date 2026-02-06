extends Node
## AudioLies - Deceptive audio system with frequency management
##
## PRIORITY #9
## "Phantom footsteps every 30 seconds = trash horror."
##
## Requirements:
## - Probability decay per session
## - Context sensitivity (combat vs traversal)
## - Distance-based believability checks

signal audio_lie_played(lie_type: String, position: Vector3)
signal audio_lie_blocked(lie_type: String, reason: String)
signal believability_check_failed(lie_type: String, distance: float)

## Lie types
enum AudioLieType {
	FOOTSTEPS,
	BREATHING,
	WHISPER,
	DOOR_CREAK,
	ITEM_DROP,
	NPC_CALL,
	AMBIENT_WRONG,  # Wrong ambient sound for location
	MUSIC_STING,    # False danger music
}

## Session tracking
var session_start_time: float = 0.0
var lies_played_this_session: int = 0
var lies_by_type: Dictionary = {}  # AudioLieType -> count

## Probability configuration
@export var base_lie_probability: float = 0.3
@export var probability_decay_rate: float = 0.02  # Per lie played
@export var min_lie_probability: float = 0.05
@export var probability_recovery_rate: float = 0.001  # Per second

## Current probability (decays with use)
var current_probability: float = 0.3

## Context multipliers
var context_multipliers: Dictionary = {
	"combat": 0.2,      # Very low during combat
	"traversal": 1.0,   # Normal during exploration
	"dialogue": 0.1,    # Almost none during dialogue
	"puzzle": 0.5,      # Reduced during puzzles
	"rest": 1.5,        # Slightly elevated at rest points
	"high_tension": 0.7,# Reduced when already tense
}

## Current context
var current_context: String = "traversal"

## Cooldowns per lie type (in seconds)
var lie_cooldowns: Dictionary = {
	AudioLieType.FOOTSTEPS: 45.0,
	AudioLieType.BREATHING: 60.0,
	AudioLieType.WHISPER: 90.0,
	AudioLieType.DOOR_CREAK: 30.0,
	AudioLieType.ITEM_DROP: 40.0,
	AudioLieType.NPC_CALL: 120.0,
	AudioLieType.AMBIENT_WRONG: 180.0,
	AudioLieType.MUSIC_STING: 300.0,  # Very rare
}

## Last play time per type
var last_played: Dictionary = {}

## Distance-based believability
@export var min_believable_distance: float = 5.0
@export var max_believable_distance: float = 30.0


func _ready() -> void:
	session_start_time = Time.get_ticks_msec() / 1000.0
	current_probability = base_lie_probability

	for lie_type in AudioLieType.values():
		lies_by_type[lie_type] = 0
		last_played[lie_type] = 0.0


func _process(delta: float) -> void:
	# Slowly recover probability over time
	if current_probability < base_lie_probability:
		current_probability += probability_recovery_rate * delta
		current_probability = min(current_probability, base_lie_probability)


func set_context(context: String) -> void:
	if context in context_multipliers:
		current_context = context


func request_audio_lie(lie_type: AudioLieType, source_position: Vector3, player_position: Vector3) -> bool:
	## Attempt to play an audio lie. Returns true if played.

	# Check with betrayal controller first
	var betrayal_check := BetrayalController.can_execute_betrayal(
		BetrayalController.BetrayalCategory.AUDIO,
		"audio_%s" % AudioLieType.keys()[lie_type].to_lower()
	)

	if not betrayal_check["allowed"]:
		audio_lie_blocked.emit(AudioLieType.keys()[lie_type], betrayal_check["reason"])
		return false

	# Check cooldown
	var current_time := Time.get_ticks_msec() / 1000.0
	var cooldown: float = lie_cooldowns[lie_type]
	var time_since_last: float = current_time - last_played.get(lie_type, 0.0)

	if time_since_last < cooldown:
		audio_lie_blocked.emit(AudioLieType.keys()[lie_type], "Cooldown active")
		return false

	# Check probability with context
	var effective_probability := current_probability * context_multipliers.get(current_context, 1.0)
	if randf() > effective_probability:
		return false

	# Check distance believability
	var distance := source_position.distance_to(player_position)
	if not _is_distance_believable(lie_type, distance):
		believability_check_failed.emit(AudioLieType.keys()[lie_type], distance)
		return false

	# Play the lie
	_execute_audio_lie(lie_type, source_position)
	return true


func _is_distance_believable(lie_type: AudioLieType, distance: float) -> bool:
	## Check if the lie would be believable at this distance

	# Too close = obviously fake (player would see nothing)
	if distance < min_believable_distance:
		return false

	# Too far = not scary, just ambient
	if distance > max_believable_distance:
		return false

	# Type-specific checks
	match lie_type:
		AudioLieType.FOOTSTEPS:
			# Footsteps need to be close enough to matter
			return distance < 20.0
		AudioLieType.BREATHING:
			# Breathing should be very close
			return distance < 10.0
		AudioLieType.WHISPER:
			# Whispers can be close to medium
			return distance < 15.0
		AudioLieType.NPC_CALL:
			# NPC calls can be further away
			return distance < 40.0
		_:
			return true


func _execute_audio_lie(lie_type: AudioLieType, position: Vector3) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0

	# Update tracking
	last_played[lie_type] = current_time
	lies_played_this_session += 1
	lies_by_type[lie_type] += 1

	# Decay probability
	current_probability -= probability_decay_rate
	current_probability = max(current_probability, min_lie_probability)

	# Register with betrayal controller
	BetrayalController.execute_betrayal(
		BetrayalController.BetrayalCategory.AUDIO,
		"audio_%s" % AudioLieType.keys()[lie_type].to_lower(),
		"audio_lies"
	)

	# Emit signal for audio system to play
	audio_lie_played.emit(AudioLieType.keys()[lie_type], position)

	# TODO: Actually trigger audio playback


func get_audio_lie_stats() -> Dictionary:
	var session_duration := (Time.get_ticks_msec() / 1000.0) - session_start_time

	return {
		"session_duration": session_duration,
		"total_lies_played": lies_played_this_session,
		"lies_per_minute": lies_played_this_session / max(session_duration / 60.0, 1.0),
		"current_probability": current_probability,
		"context": current_context,
		"context_multiplier": context_multipliers.get(current_context, 1.0),
		"effective_probability": current_probability * context_multipliers.get(current_context, 1.0),
		"lies_by_type": _get_lies_by_type_names(),
	}


func _get_lies_by_type_names() -> Dictionary:
	var result := {}
	for lie_type in lies_by_type:
		result[AudioLieType.keys()[lie_type]] = lies_by_type[lie_type]
	return result


func get_cooldown_status() -> Dictionary:
	var current_time := Time.get_ticks_msec() / 1000.0
	var result := {}

	for lie_type in AudioLieType.values():
		var cooldown: float = lie_cooldowns[lie_type]
		var time_since: float = current_time - last_played.get(lie_type, 0.0)
		var remaining := max(0.0, cooldown - time_since)

		result[AudioLieType.keys()[lie_type]] = {
			"cooldown": cooldown,
			"remaining": remaining,
			"ready": remaining == 0.0,
			"times_played": lies_by_type[lie_type],
		}

	return result


## Quality check - ensure lies aren't becoming annoying
func check_lie_frequency_health() -> Dictionary:
	var session_duration := (Time.get_ticks_msec() / 1000.0) - session_start_time
	var lies_per_minute := lies_played_this_session / max(session_duration / 60.0, 1.0)

	var health := "good"
	var recommendation := ""

	if lies_per_minute > 2.0:
		health = "too_frequent"
		recommendation = "Reduce base probability or increase cooldowns"
	elif lies_per_minute > 1.0:
		health = "slightly_high"
		recommendation = "Monitor player engagement metrics"
	elif lies_per_minute < 0.1 and session_duration > 300:
		health = "too_rare"
		recommendation = "Consider increasing probability"

	return {
		"health": health,
		"lies_per_minute": lies_per_minute,
		"recommendation": recommendation,
	}
