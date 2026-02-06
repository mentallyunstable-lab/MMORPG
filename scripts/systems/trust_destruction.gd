extends Node
## TrustDestruction - Core system for breaking player trust
##
## Referenced throughout the roadmap as a key system.
## This is the meta-system that coordinates trust-breaking events.
##
## IMPORTANT: The Anchor is IMMUNE to this system.

signal trust_broken(system_name: String, severity: float)
signal trust_partially_restored(system_name: String, amount: float)

## Systems that can be corrupted
enum TrustableSystem {
	SAVE_SYSTEM,
	UI_DISPLAY,
	AUDIO_CUES,
	NPC_DIALOGUE,
	MAP_ACCURACY,
	ITEM_DESCRIPTIONS,
	QUEST_MARKERS,
	ENVIRONMENTAL_HINTS,
}

## Current trust levels (1.0 = fully trusted, 0.0 = completely unreliable)
var trust_levels: Dictionary = {}

## Corruption tracking
var corruption_events: Array[Dictionary] = []


func _ready() -> void:
	_initialize_trust_levels()


func _initialize_trust_levels() -> void:
	for system in TrustableSystem.values():
		trust_levels[system] = 1.0  # Start fully trusted


func can_corrupt(target_id: String) -> bool:
	## Check if a target can be corrupted (anchor is immune)
	return AnchorSystem.can_be_affected_by_trust_destruction(target_id)


func corrupt_system(system: TrustableSystem, severity: float, source: String = "") -> bool:
	## Reduce trust in a system

	# Check with betrayal controller
	var check := BetrayalController.can_execute_betrayal(
		BetrayalController.BetrayalCategory.CORE_SYSTEM,
		"trust_%s" % TrustableSystem.keys()[system].to_lower()
	)

	if not check["allowed"]:
		return false

	var old_trust: float = trust_levels[system]
	trust_levels[system] = max(0.0, old_trust - severity)

	var event := {
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"system": TrustableSystem.keys()[system],
		"severity": severity,
		"source": source,
		"old_trust": old_trust,
		"new_trust": trust_levels[system],
	}
	corruption_events.append(event)

	# Register with betrayal controller
	BetrayalController.execute_betrayal(
		BetrayalController.BetrayalCategory.CORE_SYSTEM,
		"trust_%s" % TrustableSystem.keys()[system].to_lower(),
		"trust_destruction"
	)

	trust_broken.emit(TrustableSystem.keys()[system], severity)
	return true


func restore_trust(system: TrustableSystem, amount: float) -> void:
	## Partially restore trust (never fully - broken trust leaves marks)

	var old_trust: float = trust_levels[system]
	# Can never restore to 1.0 - max is 0.9 after first corruption
	var max_trust := 1.0 if corruption_events.filter(func(e): return e["system"] == TrustableSystem.keys()[system]).size() == 0 else 0.9

	trust_levels[system] = min(max_trust, old_trust + amount)

	trust_partially_restored.emit(TrustableSystem.keys()[system], amount)


func get_trust_level(system: TrustableSystem) -> float:
	return trust_levels.get(system, 1.0)


func is_system_reliable(system: TrustableSystem) -> bool:
	## Returns true if system should behave normally
	return trust_levels.get(system, 1.0) > 0.7


func should_system_lie(system: TrustableSystem) -> bool:
	## Returns true if system should produce unreliable output

	var trust: float = trust_levels.get(system, 1.0)

	# Below 0.5 trust = 50% chance of lying
	# Below 0.3 trust = 70% chance of lying
	# Below 0.1 trust = 90% chance of lying

	var lie_chance := 0.0
	if trust < 0.5:
		lie_chance = 0.5
	if trust < 0.3:
		lie_chance = 0.7
	if trust < 0.1:
		lie_chance = 0.9

	return randf() < lie_chance


func get_corruption_history() -> Array[Dictionary]:
	return corruption_events.duplicate()


func get_trust_summary() -> Dictionary:
	var summary := {}

	for system in TrustableSystem.values():
		var system_name: String = TrustableSystem.keys()[system]
		summary[system_name] = {
			"trust_level": trust_levels[system],
			"is_reliable": is_system_reliable(system),
			"corruption_count": corruption_events.filter(func(e): return e["system"] == system_name).size(),
		}

	return summary
