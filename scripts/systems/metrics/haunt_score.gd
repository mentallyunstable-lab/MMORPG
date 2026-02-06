extends Node
## HauntScore - Meaningful metrics that drive game behavior
##
## PRIORITY #14
## "Metrics without interpretation are decoration."
##
## Requirements:
## - Correlate haunt score with: player pauses, reload frequency, menu open time
## - Define thresholds that unlock/lock behaviors
## - Ensure haunt score never soft-bricks progression

signal haunt_score_changed(old_score: float, new_score: float)
signal threshold_crossed(threshold_name: String, direction: String)  # "up" or "down"
signal behavior_unlocked(behavior: String)
signal behavior_locked(behavior: String)
signal soft_brick_prevented(reason: String)

## Haunt score range: 0.0 (calm) to 100.0 (maximum haunting)
var haunt_score: float = 0.0

## Input metrics
var pause_count: int = 0
var total_pause_duration: float = 0.0
var reload_count: int = 0
var menu_open_time: float = 0.0
var hesitation_events: int = 0  # Player stops moving when shouldn't

## Metric tracking
var session_start_time: float = 0.0
var last_pause_time: float = 0.0
var is_paused: bool = false
var is_menu_open: bool = false
var menu_open_start: float = 0.0

## Thresholds for behavior changes
var thresholds: Dictionary = {
	"subtle_unease": 15.0,      # Minor environmental oddities start
	"active_haunting": 35.0,    # Witness mode stage 1-2 enabled
	"intense_haunting": 55.0,   # Audio lies more frequent, gods more active
	"overwhelming": 75.0,       # Witness mode stage 3-4, heavy god interference
	"maximum_terror": 90.0,     # All systems at maximum
}

## Behaviors locked/unlocked by thresholds
var threshold_behaviors: Dictionary = {
	"subtle_unease": ["environment_flicker", "npc_glance"],
	"active_haunting": ["witness_stage_1", "witness_stage_2", "minor_audio_lies"],
	"intense_haunting": ["witness_stage_3", "major_audio_lies", "god_whispers"],
	"overwhelming": ["witness_stage_4", "witness_stage_5", "god_direct_action"],
	"maximum_terror": ["witness_stage_6", "reality_breakdown"],
}

## Currently unlocked behaviors
var unlocked_behaviors: Array[String] = []

## Soft-brick prevention
@export var max_haunt_score: float = 95.0  # Never reach 100 to prevent soft-brick
@export var recovery_rate: float = 0.5  # Per second when not accumulating
@export var emergency_reduction: float = 20.0  # Applied when soft-brick detected


func _ready() -> void:
	session_start_time = Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	_track_menu_time(delta)
	_apply_passive_recovery(delta)
	_update_haunt_score()


func record_pause() -> void:
	## Called when player pauses the game
	if not is_paused:
		is_paused = true
		pause_count += 1
		last_pause_time = Time.get_ticks_msec() / 1000.0


func record_unpause() -> void:
	## Called when player unpauses
	if is_paused:
		is_paused = false
		var pause_duration := (Time.get_ticks_msec() / 1000.0) - last_pause_time
		total_pause_duration += pause_duration


func record_reload() -> void:
	## Called when player reloads a save
	reload_count += 1
	# Reloads are a strong signal of distress
	_add_to_haunt_score(5.0)


func record_menu_open() -> void:
	## Called when player opens menu
	if not is_menu_open:
		is_menu_open = true
		menu_open_start = Time.get_ticks_msec() / 1000.0


func record_menu_close() -> void:
	## Called when player closes menu
	if is_menu_open:
		is_menu_open = false
		var duration := (Time.get_ticks_msec() / 1000.0) - menu_open_start
		menu_open_time += duration


func record_hesitation() -> void:
	## Called when player shows hesitation behavior
	hesitation_events += 1
	_add_to_haunt_score(1.0)


func _track_menu_time(delta: float) -> void:
	## Track continuous menu time as hesitation signal
	if is_menu_open:
		# Long menu time contributes to haunt score
		var current_menu_session := (Time.get_ticks_msec() / 1000.0) - menu_open_start
		if current_menu_session > 10.0:  # More than 10 seconds in menu
			_add_to_haunt_score(delta * 0.5)


func _apply_passive_recovery(delta: float) -> void:
	## Haunt score slowly recovers when not being fed
	if haunt_score > 0 and not is_paused and not is_menu_open:
		_set_haunt_score(haunt_score - (recovery_rate * delta))


func _add_to_haunt_score(amount: float) -> void:
	_set_haunt_score(haunt_score + amount)


func _set_haunt_score(new_score: float) -> void:
	var old_score := haunt_score

	# Clamp and prevent soft-brick
	new_score = clamp(new_score, 0.0, max_haunt_score)

	if new_score != old_score:
		haunt_score = new_score
		haunt_score_changed.emit(old_score, new_score)
		_check_thresholds(old_score, new_score)


func _update_haunt_score() -> void:
	## Calculate haunt score from all metrics

	var session_duration := (Time.get_ticks_msec() / 1000.0) - session_start_time
	if session_duration < 1.0:
		return

	# Normalize metrics to session length
	var pause_rate := pause_count / (session_duration / 60.0)  # Pauses per minute
	var reload_rate := reload_count / (session_duration / 60.0)
	var menu_ratio := menu_open_time / session_duration
	var hesitation_rate := hesitation_events / (session_duration / 60.0)

	# Calculate base score from metrics
	var calculated_score := 0.0
	calculated_score += pause_rate * 5.0       # Each pause per minute = 5 points
	calculated_score += reload_rate * 15.0     # Each reload per minute = 15 points
	calculated_score += menu_ratio * 30.0      # Menu time ratio * 30
	calculated_score += hesitation_rate * 3.0  # Each hesitation per minute = 3 points

	# Smooth transition to calculated score
	var target := min(calculated_score, max_haunt_score)
	haunt_score = lerp(haunt_score, target, 0.01)  # Slow transition

	_check_soft_brick()


func _check_thresholds(old_score: float, new_score: float) -> void:
	## Check if any thresholds were crossed

	for threshold_name in thresholds:
		var threshold_value: float = thresholds[threshold_name]

		# Crossed upward
		if old_score < threshold_value and new_score >= threshold_value:
			threshold_crossed.emit(threshold_name, "up")
			_unlock_threshold_behaviors(threshold_name)

		# Crossed downward
		if old_score >= threshold_value and new_score < threshold_value:
			threshold_crossed.emit(threshold_name, "down")
			_lock_threshold_behaviors(threshold_name)


func _unlock_threshold_behaviors(threshold_name: String) -> void:
	if not threshold_name in threshold_behaviors:
		return

	for behavior in threshold_behaviors[threshold_name]:
		if not behavior in unlocked_behaviors:
			unlocked_behaviors.append(behavior)
			behavior_unlocked.emit(behavior)


func _lock_threshold_behaviors(threshold_name: String) -> void:
	if not threshold_name in threshold_behaviors:
		return

	for behavior in threshold_behaviors[threshold_name]:
		if behavior in unlocked_behaviors:
			unlocked_behaviors.erase(behavior)
			behavior_locked.emit(behavior)


func is_behavior_unlocked(behavior: String) -> bool:
	return behavior in unlocked_behaviors


func _check_soft_brick() -> void:
	## Ensure haunt score never soft-bricks progression

	# Check for soft-brick conditions
	if haunt_score >= max_haunt_score:
		# Force reduction
		haunt_score -= emergency_reduction
		soft_brick_prevented.emit("Maximum haunt score reached")
		return

	# Check if player is stuck (high haunt + lots of reloads + long session)
	var session_duration := (Time.get_ticks_msec() / 1000.0) - session_start_time
	if haunt_score > 70 and reload_count > 5 and session_duration > 1800:
		# Player seems stuck - reduce haunt
		haunt_score -= emergency_reduction * 0.5
		soft_brick_prevented.emit("Player appears stuck - reducing haunt")


func get_haunt_metrics() -> Dictionary:
	var session_duration := (Time.get_ticks_msec() / 1000.0) - session_start_time

	return {
		"haunt_score": haunt_score,
		"max_possible": max_haunt_score,
		"current_threshold": _get_current_threshold(),
		"pause_count": pause_count,
		"pause_rate": pause_count / max(session_duration / 60.0, 1.0),
		"reload_count": reload_count,
		"menu_time_seconds": menu_open_time,
		"menu_time_ratio": menu_open_time / max(session_duration, 1.0),
		"hesitation_events": hesitation_events,
		"unlocked_behaviors": unlocked_behaviors.duplicate(),
		"session_duration": session_duration,
	}


func _get_current_threshold() -> String:
	var current := "none"

	for threshold_name in thresholds:
		if haunt_score >= thresholds[threshold_name]:
			current = threshold_name

	return current


func get_interpretation() -> Dictionary:
	## Interpret the haunt score for designers/debug
	var threshold := _get_current_threshold()

	var interpretation := ""
	var recommendation := ""

	match threshold:
		"none":
			interpretation = "Player is calm, not showing signs of distress"
			recommendation = "Safe to introduce minor unsettling elements"
		"subtle_unease":
			interpretation = "Player showing mild discomfort"
			recommendation = "Good time for environmental oddities"
		"active_haunting":
			interpretation = "Player is engaged and somewhat tense"
			recommendation = "Witness mode stages 1-2 appropriate"
		"intense_haunting":
			interpretation = "Player showing significant stress"
			recommendation = "Be careful with additional stressors"
		"overwhelming":
			interpretation = "Player is highly stressed"
			recommendation = "Consider mercy moments, avoid stacking betrayals"
		"maximum_terror":
			interpretation = "Player at maximum documented stress"
			recommendation = "Do not add more - allow recovery"

	return {
		"threshold": threshold,
		"interpretation": interpretation,
		"recommendation": recommendation,
		"score": haunt_score,
	}
