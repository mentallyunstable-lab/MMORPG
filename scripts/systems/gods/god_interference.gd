extends Node
## GodInterference - Manages divine meddling in game systems
##
## PRIORITY #5
## "Without this, gods become spammy, not divine."
##
## Arbitration rules needed:
## - Priority when two gods interfere simultaneously
## - What happens when lies cancel truths repeatedly
## - Max number of persistent environmental edits per god
## - Cooldown on god-on-god sabotage

signal god_interfered(god_id: String, interference_type: String, target: String)
signal god_blocked(god_id: String, reason: String)
signal gods_collided(god_a: String, god_b: String, resolution: String)
signal lie_truth_cancellation(god_id: String, count: int)

## God priority tiers (higher = more authority)
enum GodTier {
	MINOR = 0,
	MAJOR = 1,
	ELDER = 2,
	PRIMORDIAL = 3,
}

## Registered gods
var gods: Dictionary = {}  # god_id -> GodData

## Interference limits
@export var max_environmental_edits_per_god: int = 3
@export var god_sabotage_cooldown: float = 120.0  # 2 minutes
@export var lie_truth_cancel_threshold: int = 3  # After this many cancels, force resolution

## Tracking
var active_interferences: Dictionary = {}  # god_id -> Array[InterferenceData]
var environmental_edits: Dictionary = {}   # god_id -> count
var lie_truth_counters: Dictionary = {}    # god_id -> cancel count
var last_sabotage_times: Dictionary = {}   # "godA_godB" -> timestamp


class GodData:
	var id: String
	var name: String
	var tier: int
	var domains: Array[String]
	var current_interference_count: int = 0


class InterferenceData:
	var god_id: String
	var type: String
	var target: String
	var timestamp: float
	var is_persistent: bool
	var is_lie: bool


func _ready() -> void:
	pass


func register_god(id: String, display_name: String, tier: GodTier, domains: Array[String]) -> void:
	var god := GodData.new()
	god.id = id
	god.name = display_name
	god.tier = tier
	god.domains = domains
	gods[id] = god
	environmental_edits[id] = 0
	lie_truth_counters[id] = 0


func request_interference(god_id: String, interference_type: String, target: String, is_lie: bool = false, is_persistent: bool = false) -> bool:
	## Request divine interference. May be blocked by rules.

	# Check if target is the anchor (bypasses ALL god interference)
	if AnchorSystem.is_anchor(target):
		god_blocked.emit(god_id, "Target is the anchor - immune to all gods")
		return false

	if not god_id in gods:
		push_error("[GodInterference] Unknown god: %s" % god_id)
		return false

	var god: GodData = gods[god_id]

	# Check environmental edit limit
	if is_persistent:
		if environmental_edits[god_id] >= max_environmental_edits_per_god:
			god_blocked.emit(god_id, "Max environmental edits reached (%d)" % max_environmental_edits_per_god)
			return false

	# Check for collision with other gods
	var collision := _check_god_collision(god_id, target)
	if collision["has_collision"]:
		var resolution := _resolve_god_collision(god_id, collision["colliding_god"], target)
		if not resolution["allowed"]:
			god_blocked.emit(god_id, resolution["reason"])
			return false

	# Execute interference
	var interference := InterferenceData.new()
	interference.god_id = god_id
	interference.type = interference_type
	interference.target = target
	interference.timestamp = Time.get_ticks_msec() / 1000.0
	interference.is_persistent = is_persistent
	interference.is_lie = is_lie

	if not god_id in active_interferences:
		active_interferences[god_id] = []
	active_interferences[god_id].append(interference)

	if is_persistent:
		environmental_edits[god_id] += 1

	god_interfered.emit(god_id, interference_type, target)
	return true


func _check_god_collision(god_id: String, target: String) -> Dictionary:
	## Check if another god is already affecting this target

	for other_god_id in active_interferences:
		if other_god_id == god_id:
			continue

		for interference: InterferenceData in active_interferences[other_god_id]:
			if interference.target == target:
				return {
					"has_collision": true,
					"colliding_god": other_god_id,
					"interference": interference,
				}

	return {"has_collision": false}


func _resolve_god_collision(god_a: String, god_b: String, target: String) -> Dictionary:
	## Resolve collision between two gods
	## Higher tier wins. Equal tier = first-come-first-served.

	var tier_a: int = gods[god_a].tier
	var tier_b: int = gods[god_b].tier

	var resolution: String
	var allowed: bool

	if tier_a > tier_b:
		resolution = "%s overrides %s (higher tier)" % [gods[god_a].name, gods[god_b].name]
		allowed = true
		_remove_interference(god_b, target)
	elif tier_b > tier_a:
		resolution = "%s blocks %s (higher tier)" % [gods[god_b].name, gods[god_a].name]
		allowed = false
	else:
		# Equal tier - first come first served
		resolution = "%s blocks %s (equal tier, already active)" % [gods[god_b].name, gods[god_a].name]
		allowed = false

	gods_collided.emit(god_a, god_b, resolution)

	return {
		"allowed": allowed,
		"reason": resolution,
	}


func _remove_interference(god_id: String, target: String) -> void:
	if not god_id in active_interferences:
		return

	var interferences: Array = active_interferences[god_id]
	for i in range(interferences.size() - 1, -1, -1):
		var interference: InterferenceData = interferences[i]
		if interference.target == target:
			if interference.is_persistent:
				environmental_edits[god_id] -= 1
			interferences.remove_at(i)


func request_god_sabotage(saboteur_id: String, target_god_id: String) -> bool:
	## One god sabotages another. Has cooldown.

	var pair_key := "%s_%s" % [saboteur_id, target_god_id]
	var current_time := Time.get_ticks_msec() / 1000.0

	if pair_key in last_sabotage_times:
		var time_since := current_time - last_sabotage_times[pair_key]
		if time_since < god_sabotage_cooldown:
			god_blocked.emit(saboteur_id, "Sabotage cooldown active (%.1fs remaining)" % (god_sabotage_cooldown - time_since))
			return false

	# Execute sabotage
	last_sabotage_times[pair_key] = current_time

	# Remove one random interference from target god
	if target_god_id in active_interferences and active_interferences[target_god_id].size() > 0:
		var idx := randi() % active_interferences[target_god_id].size()
		var removed: InterferenceData = active_interferences[target_god_id][idx]
		active_interferences[target_god_id].remove_at(idx)

		if removed.is_persistent:
			environmental_edits[target_god_id] -= 1

		return true

	return false


func report_lie_truth_cancellation(god_id: String) -> void:
	## Track when lies cancel truths repeatedly

	lie_truth_counters[god_id] += 1

	if lie_truth_counters[god_id] >= lie_truth_cancel_threshold:
		lie_truth_cancellation.emit(god_id, lie_truth_counters[god_id])
		# Force a resolution - reduce god's active interferences
		_force_lie_resolution(god_id)


func _force_lie_resolution(god_id: String) -> void:
	## When lies have canceled truths too many times, force cleanup

	if god_id in active_interferences:
		var lies_removed := 0
		var interferences: Array = active_interferences[god_id]

		for i in range(interferences.size() - 1, -1, -1):
			var interference: InterferenceData = interferences[i]
			if interference.is_lie:
				if interference.is_persistent:
					environmental_edits[god_id] -= 1
				interferences.remove_at(i)
				lies_removed += 1
				if lies_removed >= 2:  # Remove up to 2 lies
					break

	lie_truth_counters[god_id] = 0


func get_god_activity(god_id: String) -> Dictionary:
	var interferences: Array = active_interferences.get(god_id, [])
	return {
		"god_id": god_id,
		"name": gods[god_id].name if god_id in gods else "Unknown",
		"tier": gods[god_id].tier if god_id in gods else -1,
		"active_interferences": interferences.size(),
		"environmental_edits": environmental_edits.get(god_id, 0),
		"lie_truth_cancellations": lie_truth_counters.get(god_id, 0),
	}


func get_all_active_interferences() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for god_id in active_interferences:
		for interference: InterferenceData in active_interferences[god_id]:
			result.append({
				"god_id": god_id,
				"god_name": gods[god_id].name if god_id in gods else "Unknown",
				"type": interference.type,
				"target": interference.target,
				"is_lie": interference.is_lie,
				"is_persistent": interference.is_persistent,
				"age": (Time.get_ticks_msec() / 1000.0) - interference.timestamp,
			})

	return result
