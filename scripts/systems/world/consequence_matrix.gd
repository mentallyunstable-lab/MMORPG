extends Node
## ConsequenceMatrix - Cross-zone consequence system
##
## PRIORITY #10
## "Everything being delayed = confusion. Everything being instant = obvious."
##
## Requirements:
## - Track decisions in Zone A that affect Zone B
## - Variable delays before effects
## - Some consequences traceable, some plausibly deniable

signal consequence_registered(consequence_id: String, source_zone: String, target_zone: String)
signal consequence_triggered(consequence_id: String, target_zone: String)
signal consequence_traced(consequence_id: String, player_discovered: bool)

## Consequence data
class ConsequenceEntry:
	var id: String
	var source_zone: String
	var source_action: String
	var target_zone: String
	var effect: String
	var delay_seconds: float
	var is_traceable: bool
	var traceability_hints: Array[String]
	var registered_time: float
	var triggered: bool = false
	var player_has_traced: bool = false


## Pending consequences
var pending_consequences: Array[ConsequenceEntry] = []
var triggered_consequences: Array[ConsequenceEntry] = []

## Consequence templates - define relationships between zones
var consequence_templates: Array[Dictionary] = []


func _ready() -> void:
	_load_consequence_templates()


func _process(delta: float) -> void:
	_check_pending_consequences()


func _load_consequence_templates() -> void:
	## Load predefined consequence relationships
	## TODO: Load from data file

	# Example templates
	consequence_templates = [
		{
			"source_zone": "village",
			"source_action": "npc_killed",
			"target_zone": "forest",
			"effect": "wolves_aggressive",
			"delay_range": [60.0, 300.0],  # 1-5 minutes
			"is_traceable": true,
			"hints": ["The wolves seem angrier since that incident in the village..."],
		},
		{
			"source_zone": "shrine",
			"source_action": "offering_made",
			"target_zone": "dungeon",
			"effect": "traps_reduced",
			"delay_range": [0.0, 30.0],  # Near instant
			"is_traceable": false,
			"hints": [],
		},
		{
			"source_zone": "forest",
			"source_action": "sacred_tree_damaged",
			"target_zone": "village",
			"effect": "crops_withering",
			"delay_range": [600.0, 1800.0],  # 10-30 minutes
			"is_traceable": true,
			"hints": [
				"The crops started dying after something happened in the forest...",
				"An elder mutters about the sacred tree...",
			],
		},
	]


func register_action(zone: String, action: String, context: Dictionary = {}) -> void:
	## Register a player action that might have consequences

	for template in consequence_templates:
		if template["source_zone"] == zone and template["source_action"] == action:
			_create_consequence(template, context)


func _create_consequence(template: Dictionary, context: Dictionary) -> void:
	var consequence := ConsequenceEntry.new()
	consequence.id = _generate_consequence_id()
	consequence.source_zone = template["source_zone"]
	consequence.source_action = template["source_action"]
	consequence.target_zone = template["target_zone"]
	consequence.effect = template["effect"]

	# Random delay within range
	var delay_range: Array = template["delay_range"]
	consequence.delay_seconds = randf_range(delay_range[0], delay_range[1])

	consequence.is_traceable = template["is_traceable"]
	consequence.traceability_hints = template.get("hints", [])
	consequence.registered_time = Time.get_ticks_msec() / 1000.0

	pending_consequences.append(consequence)

	consequence_registered.emit(
		consequence.id,
		consequence.source_zone,
		consequence.target_zone
	)


func _generate_consequence_id() -> String:
	return "csq_%d_%d" % [Time.get_ticks_msec(), randi()]


func _check_pending_consequences() -> void:
	var current_time := Time.get_ticks_msec() / 1000.0

	for i in range(pending_consequences.size() - 1, -1, -1):
		var consequence: ConsequenceEntry = pending_consequences[i]
		var elapsed := current_time - consequence.registered_time

		if elapsed >= consequence.delay_seconds:
			_trigger_consequence(consequence)
			pending_consequences.remove_at(i)


func _trigger_consequence(consequence: ConsequenceEntry) -> void:
	consequence.triggered = true
	triggered_consequences.append(consequence)

	# Apply the effect
	_apply_effect(consequence.target_zone, consequence.effect)

	consequence_triggered.emit(consequence.id, consequence.target_zone)

	# If traceable, make hints available
	if consequence.is_traceable and consequence.traceability_hints.size() > 0:
		_register_hints(consequence)


func _apply_effect(zone: String, effect: String) -> void:
	## Apply the consequence effect to the target zone
	## TODO: Implement actual zone state modifications

	print("[ConsequenceMatrix] Applying effect '%s' to zone '%s'" % [effect, zone])


func _register_hints(consequence: ConsequenceEntry) -> void:
	## Make traceability hints available through the rumor system

	for hint in consequence.traceability_hints:
		var hint_rumor := {
			"content": hint,
			"source": "consequence_hint",
			"consequence_id": consequence.id,
			"zone": consequence.target_zone,
		}

		if RumorSystem:
			RumorSystem.inject_rumor(hint_rumor)


func player_attempts_trace(consequence_id: String) -> Dictionary:
	## Player tries to figure out what caused an effect

	for consequence in triggered_consequences:
		if consequence.id == consequence_id:
			if consequence.is_traceable:
				consequence.player_has_traced = true
				consequence_traced.emit(consequence_id, true)
				return {
					"success": true,
					"source_zone": consequence.source_zone,
					"source_action": consequence.source_action,
					"hints": consequence.traceability_hints,
				}
			else:
				consequence_traced.emit(consequence_id, false)
				return {
					"success": false,
					"reason": "This consequence cannot be traced",
				}

	return {
		"success": false,
		"reason": "Unknown consequence",
	}


func get_pending_consequences() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current_time := Time.get_ticks_msec() / 1000.0

	for consequence in pending_consequences:
		var elapsed := current_time - consequence.registered_time
		var remaining := consequence.delay_seconds - elapsed

		result.append({
			"id": consequence.id,
			"source_zone": consequence.source_zone,
			"target_zone": consequence.target_zone,
			"effect": consequence.effect,
			"time_remaining": remaining,
			"is_traceable": consequence.is_traceable,
		})

	return result


func get_triggered_consequences(zone: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for consequence in triggered_consequences:
		if zone == "" or consequence.target_zone == zone:
			result.append({
				"id": consequence.id,
				"source_zone": consequence.source_zone,
				"target_zone": consequence.target_zone,
				"effect": consequence.effect,
				"is_traceable": consequence.is_traceable,
				"player_traced": consequence.player_has_traced,
			})

	return result


func get_traceability_stats() -> Dictionary:
	var total := triggered_consequences.size()
	var traceable := 0
	var traced_by_player := 0

	for consequence in triggered_consequences:
		if consequence.is_traceable:
			traceable += 1
			if consequence.player_has_traced:
				traced_by_player += 1

	return {
		"total_consequences": total,
		"traceable_count": traceable,
		"untraceable_count": total - traceable,
		"traced_by_player": traced_by_player,
		"trace_rate": float(traced_by_player) / max(traceable, 1),
	}
