## DelayedValidation — Makes truth recognition retrospective.
## An NPC says something questionable. Hours later, world state confirms it subtly.
## No UI confirmation. No fanfare. The player simply realizes: "That one was true."
##
## This is essential for rebuilding belief without collapsing uncertainty.
## If truth is always immediate, players just check facts. If truth is delayed,
## players must hold ambiguity — and that's where real epistemic engagement lives.
extends Node

signal claim_recorded(claim_id: String, npc_name: String)
signal claim_validated(claim_id: String, npc_name: String)

# --- Pending Claims ---
# Claims are statements NPCs make that CAN be verified later.
# They are NOT flagged to the player. Validation happens silently.
var _pending_claims: Dictionary = {}  # claim_id -> claim_data
const MAX_PENDING := 15

# --- Validated Claims ---
# Claims that turned out to be true, stored for NPC reference.
var _validated_claims: Array[Dictionary] = []
const MAX_VALIDATED := 20

# --- Timing ---
const VALIDATION_CHECK_INTERVAL := 60.0  # Check every minute
var _check_timer: float = 0.0

# Minimum delay before a claim can be validated (in seconds).
# Claims validated too quickly feel like immediate confirmation.
const MIN_VALIDATION_DELAY := 300.0   # 5 minutes
const MAX_CLAIM_AGE := 7200.0         # Claims expire after 2 hours


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < VALIDATION_CHECK_INTERVAL:
		return
	_check_timer = 0.0

	if GameState.witness_mode:
		return

	_check_pending_claims()
	_expire_old_claims()


## Record a claim an NPC has made about the world.
## Called by NPC dialogue systems when an NPC makes a verifiable statement.
## claim_type: "force_prediction", "god_prediction", "faction_prediction", "event_prediction"
func record_claim(npc_name: String, claim_type: String, claim_data: Dictionary) -> String:
	if _pending_claims.size() >= MAX_PENDING:
		# Remove oldest claim
		var oldest_id := ""
		var oldest_time := INF
		for cid in _pending_claims:
			var t: float = _pending_claims[cid].get("timestamp", 0.0)
			if t < oldest_time:
				oldest_time = t
				oldest_id = cid
		if oldest_id != "":
			_pending_claims.erase(oldest_id)

	var claim_id := "claim_%s_%d" % [npc_name.to_lower().replace(" ", "_"), randi()]
	var now := Time.get_unix_time_from_system()

	_pending_claims[claim_id] = {
		"npc_name": npc_name,
		"claim_type": claim_type,
		"data": claim_data,
		"timestamp": now,
		"world_state_at_claim": _snapshot_world_state(),
	}

	claim_recorded.emit(claim_id, npc_name)
	return claim_id


## Check all pending claims against current world state.
func _check_pending_claims() -> void:
	var now := Time.get_unix_time_from_system()
	var validated_ids: Array[String] = []

	for claim_id in _pending_claims:
		var claim: Dictionary = _pending_claims[claim_id]
		var age := now - claim.get("timestamp", 0.0)

		# Must wait minimum delay
		if age < MIN_VALIDATION_DELAY:
			continue

		# Check if the claim is now verifiably true
		if _is_claim_validated(claim):
			validated_ids.append(claim_id)
			_validated_claims.append({
				"claim_id": claim_id,
				"npc_name": claim.get("npc_name", ""),
				"claim_type": claim.get("claim_type", ""),
				"data": claim.get("data", {}),
				"validated_at": now,
				"delay": age,
			})
			if _validated_claims.size() > MAX_VALIDATED:
				_validated_claims.pop_front()

			claim_validated.emit(claim_id, claim.get("npc_name", ""))
			WorldMemory.record_ambient("A claim by %s proved true" % claim.get("npc_name", "someone"))

	for cid in validated_ids:
		_pending_claims.erase(cid)


## Check if a specific claim has been validated by world state.
func _is_claim_validated(claim: Dictionary) -> bool:
	var claim_type: String = claim.get("claim_type", "")
	var data: Dictionary = claim.get("data", {})

	match claim_type:
		"force_prediction":
			# NPC predicted a force would rise/fall
			var force_name: String = data.get("force", "")
			var predicted_direction: String = data.get("direction", "")  # "rise" or "fall"
			var original_value: float = data.get("original_value", 0.0)
			var current := GameState.get_force(force_name)

			if predicted_direction == "rise" and current > original_value + 5.0:
				return true
			elif predicted_direction == "fall" and current < original_value - 5.0:
				return true

		"god_prediction":
			# NPC predicted a god state change
			var god_id: String = data.get("god_id", "")
			var predicted_state: String = data.get("predicted_state", "")
			return GodManager.get_god_state(god_id) == predicted_state

		"faction_prediction":
			# NPC predicted faction attitude shift
			var faction_id: String = data.get("faction_id", "")
			var predicted_attitude: String = data.get("predicted_attitude", "")
			return FactionManager.get_attitude(faction_id) == predicted_attitude

		"event_prediction":
			# NPC predicted a world event
			var event_flag: String = data.get("event_flag", "")
			return WorldMemory.has_memory(event_flag)

	return false


## Remove claims that are too old to matter.
func _expire_old_claims() -> void:
	var now := Time.get_unix_time_from_system()
	var to_erase: Array[String] = []

	for claim_id in _pending_claims:
		var age := now - _pending_claims[claim_id].get("timestamp", 0.0)
		if age > MAX_CLAIM_AGE:
			to_erase.append(claim_id)

	for cid in to_erase:
		_pending_claims.erase(cid)


## Take a snapshot of key world state values for comparison.
func _snapshot_world_state() -> Dictionary:
	return {
		"faith": GameState.faith,
		"truth": GameState.truth,
		"violence": GameState.violence,
		"pressure": GameState.world_pressure,
	}


## Get the number of validated claims from a specific NPC.
func get_validated_count_for_npc(npc_name: String) -> int:
	var count := 0
	for vc in _validated_claims:
		if vc.get("npc_name", "") == npc_name:
			count += 1
	return count


## Get total validated claims.
func get_total_validated() -> int:
	return _validated_claims.size()


## Check if any claims have been validated (for NPC dialogue gating).
func has_validated_claims() -> bool:
	return _validated_claims.size() > 0


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"pending_claims": _pending_claims.size(),
		"validated_claims": _validated_claims.size(),
		"claim_ids": _pending_claims.keys(),
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"pending_claims": _pending_claims.duplicate(true),
		"validated_claims": _validated_claims.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	_pending_claims = data.get("pending_claims", {})
	var loaded_validated = data.get("validated_claims", [])
	_validated_claims.clear()
	for vc in loaded_validated:
		_validated_claims.append(vc)
