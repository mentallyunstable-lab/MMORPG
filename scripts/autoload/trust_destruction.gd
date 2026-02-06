## TrustDestruction — The system that makes the world unreliable.
## NPCs lie about world state. Interactables give wrong feedback. Quest info mutates.
## Scales with world pressure, god attention, and game phase.
## The anchor (The Keeper) is explicitly IMMUNE to this system.
##
## --- Player Mental Model Kill Map ---
## Phase EARLY:
##   Belief: "NPCs tell the truth" → Breaker: rare dialogue lies → Replacement: "Most NPCs are reliable"
##   Belief: "Shrines are safe" → Breaker: shrine feedback mismatch → Replacement: "Shrines mostly work"
## Phase MID:
##   Belief: "I can trust force readings" → Breaker: environmental misdirection → Replacement: "Something is wrong with the world"
##   Belief: "Quest descriptions are accurate" → Breaker: quest text mutation → Replacement: "I should verify quest info myself"
## Phase LATE:
##   Belief: "Nothing is reliable" → Anchor provides: "The Keeper still tells the truth"
##   Belief: "The game itself lies" → Anchor provides: "One thing is always honest"
##
## If any assumption breaks with no replacement, the player rage-quits.
## The Keeper IS the replacement belief for the late game.
extends Node

signal trust_event(event_type: String, details: Dictionary)

# --- Trust Level ---
# 1.0 = world is fully truthful, 0.0 = everything lies.
# This is a READ-ONLY metric — systems query it to decide how honest to be.
var trust_level: float = 1.0

# --- Configuration ---
const BASE_LIE_CHANCE := 0.05       # 5% base chance any given info is a lie
const PRESSURE_LIE_SCALE := 0.003   # +0.3% per world pressure point
const ATTENTION_LIE_SCALE := 0.002  # +0.2% per max god attention point
const TRUST_DECAY_RATE := 0.01      # Trust decays per tick at high pressure
const TRUST_RECOVERY_RATE := 0.005  # Trust recovers per tick at low pressure
const TRUST_FLOOR := 0.15           # Trust never drops below this (always SOME truth)

const CHECK_INTERVAL := 4.0
var _timer: float = 0.0

# --- Corruption tracking ---
var _active_corruptions: Dictionary = {}  # id -> {type, original, corrupted, timestamp}
var _total_lies_told: int = 0


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	_update_trust_level()


## Recalculate trust level based on current world state.
func _update_trust_level() -> void:
	var pressure := GameState.world_pressure
	var max_attention := 0.0
	for god_id in GodManager.god_defs:
		max_attention = maxf(max_attention, GodManager.get_god_attention(god_id))

	# Trust decays when world is unstable
	if pressure > 50.0 or max_attention > 40.0:
		trust_level -= TRUST_DECAY_RATE
	else:
		trust_level += TRUST_RECOVERY_RATE

	trust_level = clampf(trust_level, TRUST_FLOOR, 1.0)


## Core API: Should a given piece of information be corrupted?
## Call this before presenting any world-state info to the player.
## Returns true if the info should be TRUTHFUL, false if it should be a LIE.
## The anchor is immune — always returns true for anchor nodes.
func should_tell_truth(source_node: Node = null) -> bool:
	# Anchor immunity — the Keeper ALWAYS tells truth
	if source_node and AnchorManager.is_anchor(source_node):
		return true

	# Witness mode — the dead world doesn't lie, it just IS
	if GameState.witness_mode:
		return true

	# Calculate lie probability
	var lie_chance := _get_lie_chance()

	# Ask betrayal pacing if a lie is even allowed right now
	if not BetrayalPacing.can_betray("dialogue_lie"):
		return true

	if randf() < lie_chance:
		return false
	return true


## Get the current probability that any given info will be a lie.
func _get_lie_chance() -> float:
	var pressure := GameState.world_pressure
	var max_attention := 0.0
	for god_id in GodManager.god_defs:
		max_attention = maxf(max_attention, GodManager.get_god_attention(god_id))

	var phase_mult := GodManager.get_phase_gate(0.2, 0.6, 1.0)

	var chance := BASE_LIE_CHANCE
	chance += pressure * PRESSURE_LIE_SCALE
	chance += max_attention * ATTENTION_LIE_SCALE
	chance *= phase_mult

	return clampf(chance, 0.0, 0.5)  # Cap at 50% — even at worst, coin flip


## Corrupt a force value for display purposes. Returns a plausible wrong number.
## Only call this after should_tell_truth() returns false.
func corrupt_force_value(real_value: float) -> float:
	var offset := randf_range(-15.0, 15.0)
	# Bias lies toward being close enough to be believable
	if absf(offset) < 3.0:
		offset = sign(offset) * randf_range(5.0, 12.0)
	return clampf(real_value + offset, 0.0, 100.0)


## Corrupt a god state string. Returns a plausible wrong state.
func corrupt_god_state(real_state: String) -> String:
	var states := ["dead", "fading", "weakened", "dormant", "manifest", "ascended"]
	var real_idx := states.find(real_state)
	if real_idx < 0:
		return real_state
	# Shift by 1-2 positions in either direction
	var shift := randi_range(1, 2) * (1 if randf() > 0.5 else -1)
	var new_idx := clampi(real_idx + shift, 0, states.size() - 1)
	if new_idx == real_idx:
		new_idx = clampi(real_idx + 1, 0, states.size() - 1)
	return states[new_idx]


## Corrupt a faction attitude. Returns a plausible wrong attitude.
func corrupt_faction_attitude(real_attitude: String) -> String:
	var attitudes := ["hostile", "unfriendly", "neutral", "friendly", "allied"]
	var real_idx := attitudes.find(real_attitude)
	if real_idx < 0:
		return real_attitude
	var shift := randi_range(1, 2) * (1 if randf() > 0.5 else -1)
	var new_idx := clampi(real_idx + shift, 0, attitudes.size() - 1)
	if new_idx == real_idx:
		new_idx = clampi(real_idx + 1, 0, attitudes.size() - 1)
	return attitudes[new_idx]


## Record that a lie was told (for metrics and debug).
func record_lie(lie_type: String, details: Dictionary = {}) -> void:
	_total_lies_told += 1
	var entry := {
		"type": lie_type,
		"timestamp": Time.get_unix_time_from_system(),
		"trust_level": trust_level,
	}
	entry.merge(details)
	_active_corruptions[str(_total_lies_told)] = entry
	trust_event.emit(lie_type, entry)

	# Prune old corruption records
	if _active_corruptions.size() > 50:
		var keys := _active_corruptions.keys()
		_active_corruptions.erase(keys[0])

	# Notify betrayal pacing
	BetrayalPacing.record_betrayal(lie_type)


## Get current trust level as a descriptive string (for debug/NPC reference).
func get_trust_description() -> String:
	if trust_level > 0.8:
		return "reliable"
	elif trust_level > 0.6:
		return "mostly truthful"
	elif trust_level > 0.4:
		return "unreliable"
	elif trust_level > 0.2:
		return "deeply corrupted"
	else:
		return "nothing can be trusted"


## Debug: get total lies told this session.
func get_total_lies() -> int:
	return _total_lies_told


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"trust_level": trust_level,
		"total_lies_told": _total_lies_told,
	}


func load_state(data: Dictionary) -> void:
	trust_level = data.get("trust_level", 1.0)
	_total_lies_told = data.get("total_lies_told", 0)
