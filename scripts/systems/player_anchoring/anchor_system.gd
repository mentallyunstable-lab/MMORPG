extends Node
## AnchorSystem - The player's one constant truth
##
## PRIORITY #1 - MANDATORY
## "If you skip this, the game collapses into noise. Period."
##
## Rules:
## - Never lies
## - Never contradicts itself
## - Can disappear, but never deceive
## - Immune to god interference
## - Immune to trust_destruction.gd

signal anchor_appeared
signal anchor_disappeared
signal anchor_state_changed(is_present: bool)

## Anchor types - pick ONE and implement fully
enum AnchorType {
	NONE,       # Not configured - INVALID STATE
	NPC,        # Single NPC that never lies
	AUDIO,      # Single audio motif that's always real
	UI_ELEMENT, # Single UI element that's always accurate
}

## Current anchor configuration
var anchor_type: AnchorType = AnchorType.NONE
var anchor_id: String = ""
var anchor_is_present: bool = false
var anchor_is_silent: bool = false

## Presence/silence logging (distinct tracking required)
var presence_log: Array[Dictionary] = []
var silence_log: Array[Dictionary] = []

## Configuration validation
var _is_configured: bool = false


func _ready() -> void:
	# Anchor must be configured before game can properly start
	_load_anchor_configuration()


func _load_anchor_configuration() -> void:
	## Load anchor config from game data
	## TODO: Implement actual config loading

	# TEMPORARY: Default to unconfigured to force explicit setup
	anchor_type = AnchorType.NONE
	_is_configured = false

	if anchor_type == AnchorType.NONE:
		push_warning("[AnchorSystem] Anchor not configured! Game will collapse into noise.")


func configure_anchor(type: AnchorType, id: String) -> bool:
	## Configure the anchor. Can only be done once per game instance.
	if _is_configured:
		push_error("[AnchorSystem] Anchor already configured. Cannot reconfigure.")
		return false

	if type == AnchorType.NONE:
		push_error("[AnchorSystem] Cannot configure anchor as NONE.")
		return false

	anchor_type = type
	anchor_id = id
	_is_configured = true

	print("[AnchorSystem] Anchor configured: %s (%s)" % [AnchorType.keys()[type], id])
	return true


func is_configured() -> bool:
	return _is_configured


func is_anchor(entity_id: String) -> bool:
	## Check if an entity is the anchor
	return _is_configured and entity_id == anchor_id


func can_be_affected_by_gods(entity_id: String) -> bool:
	## Anchor bypasses ALL god interference
	if is_anchor(entity_id):
		return false
	return true


func can_be_affected_by_trust_destruction(entity_id: String) -> bool:
	## Anchor is immune to trust_destruction.gd
	if is_anchor(entity_id):
		return false
	return true


func set_anchor_present(is_present: bool) -> void:
	## Anchor can disappear, but never deceive
	if anchor_is_present != is_present:
		anchor_is_present = is_present
		anchor_state_changed.emit(is_present)

		var timestamp := Time.get_ticks_msec() / 1000.0

		if is_present:
			anchor_appeared.emit()
			presence_log.append({
				"timestamp": timestamp,
				"event": "appeared"
			})
		else:
			anchor_disappeared.emit()
			silence_log.append({
				"timestamp": timestamp,
				"event": "disappeared",
				"was_silent": anchor_is_silent
			})


func set_anchor_silent(is_silent: bool) -> void:
	## Anchor can be silent (different from absent)
	## Silence vs presence must be logged distinctly
	if anchor_is_silent != is_silent:
		anchor_is_silent = is_silent

		var timestamp := Time.get_ticks_msec() / 1000.0
		silence_log.append({
			"timestamp": timestamp,
			"event": "silence_changed",
			"is_silent": is_silent
		})


func get_anchor_info() -> Dictionary:
	return {
		"configured": _is_configured,
		"type": AnchorType.keys()[anchor_type] if _is_configured else "NONE",
		"id": anchor_id,
		"is_present": anchor_is_present,
		"is_silent": anchor_is_silent,
	}


func get_presence_history() -> Array[Dictionary]:
	return presence_log.duplicate()


func get_silence_history() -> Array[Dictionary]:
	return silence_log.duplicate()


## Validation: Ensure anchor never lies or contradicts
func validate_anchor_statement(statement: String, context: Dictionary) -> bool:
	## All anchor statements must pass through here
	## Returns true only if statement is truthful and consistent

	# TODO: Implement statement validation against game state
	# TODO: Implement contradiction detection against previous statements

	return true  # Placeholder - must implement properly


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Log final state on shutdown
		print("[AnchorSystem] Final presence events: %d, silence events: %d" % [
			presence_log.size(),
			silence_log.size()
		])
