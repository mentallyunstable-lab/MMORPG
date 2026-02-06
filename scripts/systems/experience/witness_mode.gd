extends Node
## WitnessMode - Staged escalation of reality breakdown
##
## PRIORITY #8
## "Currently linear. Make it staged."
##
## Stages:
## 1. Objects respond once
## 2. NPCs notice but deny
## 3. Environmental decay
## 4. UI erosion
## 5. Sensory dropout
## 6. Forced stillness moments
##
## Requirements:
## - Hard caps so it never eats the entire UI too early
## - Reset rules that feel like mercy, not rollback

signal stage_changed(old_stage: int, new_stage: int)
signal witness_event(stage: int, event_type: String, details: Dictionary)
signal mercy_reset(from_stage: int, to_stage: int, reason: String)
signal forced_stillness_started
signal forced_stillness_ended

## Witness stages
enum WitnessStage {
	NONE = 0,
	OBJECTS_RESPOND = 1,
	NPCS_NOTICE_DENY = 2,
	ENVIRONMENTAL_DECAY = 3,
	UI_EROSION = 4,
	SENSORY_DROPOUT = 5,
	FORCED_STILLNESS = 6,
}

## Current state
var current_stage: WitnessStage = WitnessStage.NONE
var witness_intensity: float = 0.0  # 0.0 to 1.0 within current stage
var total_witness_accumulation: float = 0.0

## Stage thresholds (accumulation needed to advance)
var stage_thresholds: Dictionary = {
	WitnessStage.OBJECTS_RESPOND: 10.0,
	WitnessStage.NPCS_NOTICE_DENY: 25.0,
	WitnessStage.ENVIRONMENTAL_DECAY: 45.0,
	WitnessStage.UI_EROSION: 70.0,
	WitnessStage.SENSORY_DROPOUT: 90.0,
	WitnessStage.FORCED_STILLNESS: 100.0,
}

## Hard caps - UI erosion limits
@export var max_ui_erosion_percentage: float = 0.6  # Never eat more than 60% of UI
@export var ui_erosion_rate: float = 0.1  # Per second at max intensity
var current_ui_erosion: float = 0.0

## Stage behaviors
var stage_active_effects: Dictionary = {}

## Mercy reset configuration
@export var mercy_threshold_time: float = 180.0  # 3 minutes at max stage
@export var mercy_stage_reduction: int = 2  # How many stages to reduce
var time_at_max_stage: float = 0.0

## Forced stillness
var is_in_stillness: bool = false
var stillness_duration: float = 0.0
@export var min_stillness_duration: float = 3.0
@export var max_stillness_duration: float = 8.0


func _ready() -> void:
	current_stage = WitnessStage.NONE


func _process(delta: float) -> void:
	if is_in_stillness:
		_process_stillness(delta)
	else:
		_process_witness_accumulation(delta)
		_check_mercy_reset(delta)
		_apply_stage_effects(delta)


func add_witness_accumulation(amount: float) -> void:
	## Add to witness accumulation (triggers stage progression)
	total_witness_accumulation += amount
	_check_stage_progression()


func _check_stage_progression() -> void:
	var new_stage := WitnessStage.NONE

	# Find appropriate stage based on accumulation
	for stage in WitnessStage.values():
		if stage == WitnessStage.NONE:
			continue
		if total_witness_accumulation >= stage_thresholds[stage]:
			new_stage = stage

	if new_stage != current_stage:
		_transition_to_stage(new_stage)


func _transition_to_stage(new_stage: WitnessStage) -> void:
	var old_stage := current_stage
	current_stage = new_stage

	# Calculate intensity within new stage
	if new_stage != WitnessStage.NONE:
		var prev_threshold := 0.0
		if new_stage > WitnessStage.OBJECTS_RESPOND:
			prev_threshold = stage_thresholds[new_stage - 1]
		var next_threshold: float = stage_thresholds[new_stage]
		witness_intensity = (total_witness_accumulation - prev_threshold) / (next_threshold - prev_threshold)
		witness_intensity = clamp(witness_intensity, 0.0, 1.0)
	else:
		witness_intensity = 0.0

	# Special handling for forced stillness
	if new_stage == WitnessStage.FORCED_STILLNESS:
		_trigger_forced_stillness()

	stage_changed.emit(old_stage, new_stage)
	witness_event.emit(new_stage, "stage_entered", {"from": old_stage})


func _process_witness_accumulation(delta: float) -> void:
	## Passive accumulation decay (slow recovery when not witnessing)
	if total_witness_accumulation > 0:
		total_witness_accumulation -= delta * 0.5  # Slow decay
		total_witness_accumulation = max(0.0, total_witness_accumulation)
		_check_stage_progression()


func _apply_stage_effects(delta: float) -> void:
	match current_stage:
		WitnessStage.OBJECTS_RESPOND:
			_apply_objects_respond()
		WitnessStage.NPCS_NOTICE_DENY:
			_apply_npcs_notice_deny()
		WitnessStage.ENVIRONMENTAL_DECAY:
			_apply_environmental_decay(delta)
		WitnessStage.UI_EROSION:
			_apply_ui_erosion(delta)
		WitnessStage.SENSORY_DROPOUT:
			_apply_sensory_dropout(delta)


func _apply_objects_respond() -> void:
	## Stage 1: Objects respond once
	## Objects acknowledge player's presence subtly, then return to normal
	pass  # TODO: Implement object response system


func _apply_npcs_notice_deny() -> void:
	## Stage 2: NPCs notice but deny
	## NPCs show awareness then pretend nothing happened
	pass  # TODO: Implement NPC awareness system


func _apply_environmental_decay(delta: float) -> void:
	## Stage 3: Environmental decay
	## World starts showing wear, subtle wrongness
	pass  # TODO: Implement environmental decay visuals


func _apply_ui_erosion(delta: float) -> void:
	## Stage 4: UI erosion - WITH HARD CAPS

	# Apply erosion with cap
	var erosion_amount := ui_erosion_rate * witness_intensity * delta
	current_ui_erosion += erosion_amount
	current_ui_erosion = min(current_ui_erosion, max_ui_erosion_percentage)

	# Never eat more than the cap
	witness_event.emit(current_stage, "ui_erosion", {
		"erosion": current_ui_erosion,
		"capped": current_ui_erosion >= max_ui_erosion_percentage
	})


func _apply_sensory_dropout(delta: float) -> void:
	## Stage 5: Sensory dropout
	## Audio cuts, vision tunnels, inputs feel delayed
	pass  # TODO: Implement sensory dropout effects


func _trigger_forced_stillness() -> void:
	## Stage 6: Forced stillness moments
	is_in_stillness = true
	stillness_duration = randf_range(min_stillness_duration, max_stillness_duration)

	# Notify game to freeze player
	forced_stillness_started.emit()
	witness_event.emit(current_stage, "stillness_started", {
		"duration": stillness_duration
	})


func _process_stillness(delta: float) -> void:
	stillness_duration -= delta

	if stillness_duration <= 0:
		is_in_stillness = false
		forced_stillness_ended.emit()

		# After stillness, apply mercy reset
		_apply_mercy_reset("stillness_completed")


func _check_mercy_reset(delta: float) -> void:
	## Check if player has been suffering long enough to deserve mercy

	if current_stage == WitnessStage.SENSORY_DROPOUT or current_stage == WitnessStage.UI_EROSION:
		time_at_max_stage += delta

		if time_at_max_stage >= mercy_threshold_time:
			_apply_mercy_reset("extended_suffering")


func _apply_mercy_reset(reason: String) -> void:
	## Reset feels like mercy, not rollback

	var old_stage := current_stage
	var reduction := mercy_stage_reduction

	# Calculate new stage
	var new_stage_value: int = max(0, int(current_stage) - reduction)
	var new_stage: WitnessStage = new_stage_value as WitnessStage

	# Adjust accumulation to match
	if new_stage == WitnessStage.NONE:
		total_witness_accumulation = 0.0
	else:
		total_witness_accumulation = stage_thresholds[new_stage] * 0.5  # Middle of that stage

	# Partial UI recovery
	current_ui_erosion *= 0.5

	# Reset timer
	time_at_max_stage = 0.0

	# Transition
	_transition_to_stage(new_stage)

	mercy_reset.emit(old_stage, new_stage, reason)
	witness_event.emit(new_stage, "mercy_reset", {
		"from_stage": old_stage,
		"reason": reason
	})


func get_witness_state() -> Dictionary:
	return {
		"current_stage": WitnessStage.keys()[current_stage],
		"stage_number": current_stage,
		"intensity": witness_intensity,
		"total_accumulation": total_witness_accumulation,
		"ui_erosion": current_ui_erosion,
		"ui_erosion_capped": current_ui_erosion >= max_ui_erosion_percentage,
		"is_in_stillness": is_in_stillness,
		"time_at_high_stage": time_at_max_stage,
	}


func get_stage_description(stage: WitnessStage) -> String:
	match stage:
		WitnessStage.NONE:
			return "Normal perception"
		WitnessStage.OBJECTS_RESPOND:
			return "Objects respond once to your presence"
		WitnessStage.NPCS_NOTICE_DENY:
			return "NPCs notice but deny seeing anything"
		WitnessStage.ENVIRONMENTAL_DECAY:
			return "The environment shows signs of decay"
		WitnessStage.UI_EROSION:
			return "Interface becomes unreliable"
		WitnessStage.SENSORY_DROPOUT:
			return "Senses begin to fail"
		WitnessStage.FORCED_STILLNESS:
			return "Forced to be still and witness"
	return "Unknown"
