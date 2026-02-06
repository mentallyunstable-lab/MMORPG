extends Node
## BetrayalController - Orchestrates betrayal pacing
##
## PRIORITY #3
## "Horror needs rhythm. You don't have one yet."
##
## Rules:
## - Global betrayal cooldown
## - Hard rule: only ONE core system betrayal per X minutes
## - Soft rule: audio lies do not overlap save lies

signal betrayal_executed(betrayal_type: String, system: String)
signal betrayal_blocked(betrayal_type: String, reason: String)
signal cooldown_started(duration: float)
signal cooldown_ended

## Betrayal categories
enum BetrayalCategory {
	CORE_SYSTEM,    # Save corruption, UI lies, etc.
	AUDIO,          # Phantom sounds, false cues
	VISUAL,         # Environmental deception
	NPC,            # Character betrayals
	ENVIRONMENTAL,  # World state lies
}

## Cooldown configuration (in seconds)
@export var core_betrayal_cooldown: float = 300.0  # 5 minutes between core betrayals
@export var audio_lie_cooldown: float = 45.0
@export var min_betrayal_spacing: float = 30.0  # Minimum time between ANY betrayal

## Tracking
var last_betrayal_time: float = 0.0
var last_betrayal_by_category: Dictionary = {}
var betrayal_history: Array[Dictionary] = []
var current_cooldown_end: float = 0.0

## Overlap prevention
var active_betrayals: Array[String] = []


func _ready() -> void:
	_initialize_cooldowns()


func _initialize_cooldowns() -> void:
	for category in BetrayalCategory.values():
		last_betrayal_by_category[category] = 0.0


func can_execute_betrayal(category: BetrayalCategory, betrayal_type: String) -> Dictionary:
	## Check if a betrayal can be executed
	## Returns: { "allowed": bool, "reason": String, "wait_time": float }

	var current_time := Time.get_ticks_msec() / 1000.0

	# Check minimum spacing
	var time_since_last := current_time - last_betrayal_time
	if time_since_last < min_betrayal_spacing:
		return {
			"allowed": false,
			"reason": "Minimum betrayal spacing not met",
			"wait_time": min_betrayal_spacing - time_since_last
		}

	# Check category-specific cooldown
	var category_cooldown := _get_category_cooldown(category)
	var time_since_category := current_time - last_betrayal_by_category.get(category, 0.0)
	if time_since_category < category_cooldown:
		return {
			"allowed": false,
			"reason": "Category cooldown active: %s" % BetrayalCategory.keys()[category],
			"wait_time": category_cooldown - time_since_category
		}

	# Check overlap rules
	if not _check_overlap_rules(category, betrayal_type):
		return {
			"allowed": false,
			"reason": "Overlap rule violation",
			"wait_time": 0.0
		}

	# First 90 minutes special rules
	if GameManager.is_in_first_90_minutes():
		if not _check_first_90_rules(category, betrayal_type):
			return {
				"allowed": false,
				"reason": "First 90 minutes rule violation",
				"wait_time": 0.0
			}

	return {
		"allowed": true,
		"reason": "",
		"wait_time": 0.0
	}


func execute_betrayal(category: BetrayalCategory, betrayal_type: String, system: String) -> bool:
	## Attempt to execute a betrayal

	var check := can_execute_betrayal(category, betrayal_type)
	if not check["allowed"]:
		betrayal_blocked.emit(betrayal_type, check["reason"])
		_log_blocked_betrayal(category, betrayal_type, check["reason"])
		return false

	var current_time := Time.get_ticks_msec() / 1000.0

	# Update tracking
	last_betrayal_time = current_time
	last_betrayal_by_category[category] = current_time
	active_betrayals.append(betrayal_type)

	# Log betrayal
	var entry := {
		"timestamp": current_time,
		"category": BetrayalCategory.keys()[category],
		"type": betrayal_type,
		"system": system,
		"session_time": GameManager.get_session_duration(),
	}
	betrayal_history.append(entry)

	# Start cooldown
	var cooldown := _get_category_cooldown(category)
	current_cooldown_end = current_time + cooldown
	cooldown_started.emit(cooldown)

	# Track first 90 minutes events
	if GameManager.is_in_first_90_minutes():
		_track_first_90_event(betrayal_type)

	betrayal_executed.emit(betrayal_type, system)
	return true


func end_betrayal(betrayal_type: String) -> void:
	## Mark a betrayal as ended (for overlap tracking)
	active_betrayals.erase(betrayal_type)


func _get_category_cooldown(category: BetrayalCategory) -> float:
	match category:
		BetrayalCategory.CORE_SYSTEM:
			return core_betrayal_cooldown
		BetrayalCategory.AUDIO:
			return audio_lie_cooldown
		_:
			return min_betrayal_spacing


func _check_overlap_rules(category: BetrayalCategory, betrayal_type: String) -> bool:
	## Soft rule: audio lies do not overlap save lies

	if category == BetrayalCategory.AUDIO:
		if "save_lie" in active_betrayals:
			return false

	if betrayal_type == "save_lie":
		for active in active_betrayals:
			if active.begins_with("audio_"):
				return false

	return true


func _check_first_90_rules(category: BetrayalCategory, betrayal_type: String) -> bool:
	## First 90 minutes: Zero overlapping betrayals

	if active_betrayals.size() > 0:
		return false

	# No god obsession before player understands gods exist
	if betrayal_type.contains("god_") and not _player_knows_gods_exist():
		return false

	return true


func _player_knows_gods_exist() -> bool:
	## Check if player has been introduced to gods
	## TODO: Implement proper check against game progression
	return false


func _track_first_90_event(betrayal_type: String) -> void:
	if betrayal_type.contains("lie"):
		GameManager.mark_first_90_event("lie_delivered")
	if betrayal_type.contains("silence"):
		GameManager.mark_first_90_event("silence_delivered")
	if betrayal_type.contains("refusal"):
		GameManager.mark_first_90_event("refusal_delivered")


func _log_blocked_betrayal(category: BetrayalCategory, betrayal_type: String, reason: String) -> void:
	if GameManager.debug_mode:
		print("[BetrayalController] BLOCKED: %s (%s) - %s" % [
			betrayal_type,
			BetrayalCategory.keys()[category],
			reason
		])


## Debug overlay data (Priority #3 requirement)
func get_debug_overlay_data() -> Dictionary:
	var current_time := Time.get_ticks_msec() / 1000.0
	return {
		"last_betrayal_timestamp": last_betrayal_time,
		"time_since_last": current_time - last_betrayal_time,
		"next_allowed_window": max(0.0, current_cooldown_end - current_time),
		"active_betrayals": active_betrayals.duplicate(),
		"cooldowns_by_category": _get_all_cooldown_states(),
	}


func _get_all_cooldown_states() -> Dictionary:
	var current_time := Time.get_ticks_msec() / 1000.0
	var states := {}

	for category in BetrayalCategory.values():
		var last_time: float = last_betrayal_by_category.get(category, 0.0)
		var cooldown := _get_category_cooldown(category)
		var remaining := max(0.0, (last_time + cooldown) - current_time)

		states[BetrayalCategory.keys()[category]] = {
			"last_triggered": last_time,
			"cooldown": cooldown,
			"remaining": remaining,
			"ready": remaining == 0.0
		}

	return states


func get_betrayal_history() -> Array[Dictionary]:
	return betrayal_history.duplicate()
