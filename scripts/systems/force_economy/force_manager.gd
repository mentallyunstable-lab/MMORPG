extends Node
## ForceManager - Hidden fatigue/force economy system
##
## PRIORITY #4
## "Hidden ≠ unfair. Right now you're close to unfair."
##
## Requirements:
## - Visualize hidden fatigue in dev tools
## - Simulate 10-hour playthrough force curves
## - Ensure no force permanently soft-locks progress
## - Add emergency decay floor so fatigue always recovers

signal force_changed(old_value: float, new_value: float)
signal fatigue_warning(level: String)  # "low", "medium", "high", "critical"
signal emergency_decay_activated

## Force configuration
@export var max_force: float = 100.0
@export var base_recovery_rate: float = 1.0  # Per second
@export var emergency_decay_floor: float = 10.0  # Minimum force that's always recoverable to
@export var soft_lock_threshold: float = 5.0  # Below this, emergency measures activate

## Current state
var current_force: float = 100.0
var fatigue_level: float = 0.0  # Inverse of force, for tracking
var is_emergency_decay_active: bool = false

## Tracking for simulation/visualization
var force_history: Array[Dictionary] = []
var _history_sample_interval: float = 1.0
var _last_sample_time: float = 0.0

## Actions and their costs
var action_costs: Dictionary = {
	"sprint": 0.5,
	"attack_light": 1.0,
	"attack_heavy": 3.0,
	"dodge": 2.0,
	"ability_use": 5.0,
	"witness_mode_tick": 0.1,
}

## Recovery modifiers
var recovery_modifiers: Dictionary = {
	"resting": 2.0,
	"shrine_proximity": 1.5,
	"combat": 0.5,
	"witness_mode": 0.25,
}


func _ready() -> void:
	current_force = max_force


func _process(delta: float) -> void:
	_apply_recovery(delta)
	_check_soft_lock_prevention()
	_sample_history()


func _apply_recovery(delta: float) -> void:
	var recovery := base_recovery_rate * _get_current_recovery_modifier() * delta

	if is_emergency_decay_active:
		# Emergency decay: guaranteed minimum recovery
		recovery = max(recovery, base_recovery_rate * 0.5 * delta)

	if current_force < max_force:
		set_force(min(current_force + recovery, max_force))


func _get_current_recovery_modifier() -> float:
	## Get the current recovery modifier based on game state
	## TODO: Integrate with actual game state
	return 1.0


func _check_soft_lock_prevention() -> void:
	## Ensure no force permanently soft-locks progress

	if current_force <= soft_lock_threshold and not is_emergency_decay_active:
		is_emergency_decay_active = true
		emergency_decay_activated.emit()
		print("[ForceManager] Emergency decay activated - preventing soft-lock")

	if is_emergency_decay_active and current_force >= emergency_decay_floor:
		is_emergency_decay_active = false
		print("[ForceManager] Emergency decay deactivated - force recovered")


func consume_force(action: String, multiplier: float = 1.0) -> bool:
	## Attempt to consume force for an action
	## Returns false if insufficient force

	var cost: float = action_costs.get(action, 0.0) * multiplier

	if cost <= 0.0:
		return true

	if current_force < cost:
		# Check if this would soft-lock
		if current_force - cost < soft_lock_threshold:
			fatigue_warning.emit("critical")
		return false

	set_force(current_force - cost)
	return true


func set_force(value: float) -> void:
	var old_value := current_force
	current_force = clamp(value, 0.0, max_force)
	fatigue_level = max_force - current_force

	if old_value != current_force:
		force_changed.emit(old_value, current_force)
		_emit_fatigue_warning()


func _emit_fatigue_warning() -> void:
	var percentage := current_force / max_force

	if percentage <= 0.1:
		fatigue_warning.emit("critical")
	elif percentage <= 0.25:
		fatigue_warning.emit("high")
	elif percentage <= 0.5:
		fatigue_warning.emit("medium")
	elif percentage <= 0.75:
		fatigue_warning.emit("low")


func _sample_history() -> void:
	var current_time := Time.get_ticks_msec() / 1000.0

	if current_time - _last_sample_time >= _history_sample_interval:
		force_history.append({
			"timestamp": current_time,
			"force": current_force,
			"fatigue": fatigue_level,
			"emergency_active": is_emergency_decay_active,
		})
		_last_sample_time = current_time

		# Keep history manageable (last hour of data at 1 sample/sec)
		if force_history.size() > 3600:
			force_history.pop_front()


## Dev tools visualization (Priority #4 requirement)
func get_force_visualization_data() -> Dictionary:
	return {
		"current_force": current_force,
		"max_force": max_force,
		"fatigue_level": fatigue_level,
		"percentage": current_force / max_force,
		"emergency_active": is_emergency_decay_active,
		"recovery_rate": base_recovery_rate * _get_current_recovery_modifier(),
		"history": force_history.duplicate(),
	}


## Simulate 10-hour playthrough (Priority #4 requirement)
func simulate_playthrough(duration_hours: float = 10.0, actions_per_minute: float = 5.0) -> Dictionary:
	## Run a simulation to check force curves
	## Returns analysis of potential soft-lock scenarios

	var sim_force := max_force
	var sim_duration := duration_hours * 3600.0  # Convert to seconds
	var time_step := 1.0
	var sim_history: Array[float] = []
	var soft_lock_moments: Array[float] = []
	var min_force := max_force
	var min_force_time := 0.0

	var action_types := action_costs.keys()

	for t in range(int(sim_duration / time_step)):
		var current_time := t * time_step

		# Simulate random action consumption
		if randf() < (actions_per_minute / 60.0):
			var action: String = action_types[randi() % action_types.size()]
			sim_force -= action_costs[action]

		# Apply recovery
		sim_force += base_recovery_rate * time_step
		sim_force = clamp(sim_force, 0.0, max_force)

		# Emergency decay simulation
		if sim_force < soft_lock_threshold:
			sim_force += base_recovery_rate * 0.5 * time_step

		# Track
		sim_history.append(sim_force)

		if sim_force < min_force:
			min_force = sim_force
			min_force_time = current_time

		if sim_force < soft_lock_threshold:
			soft_lock_moments.append(current_time)

	return {
		"duration_hours": duration_hours,
		"min_force_reached": min_force,
		"min_force_time_seconds": min_force_time,
		"soft_lock_moments_count": soft_lock_moments.size(),
		"average_force": sim_history.reduce(func(a, b): return a + b, 0.0) / sim_history.size(),
		"emergency_decay_effective": min_force >= 0.0,
		"recommendation": _generate_simulation_recommendation(min_force, soft_lock_moments.size()),
	}


func _generate_simulation_recommendation(min_force: float, soft_lock_count: int) -> String:
	if soft_lock_count == 0:
		return "Force economy is well balanced."
	elif soft_lock_count < 10:
		return "Minor soft-lock risk. Emergency decay should handle it."
	elif min_force < 0:
		return "CRITICAL: Force can go negative. Adjust emergency decay floor."
	else:
		return "High soft-lock frequency. Consider reducing action costs or increasing recovery."


func get_fatigue_percentage() -> float:
	return fatigue_level / max_force
