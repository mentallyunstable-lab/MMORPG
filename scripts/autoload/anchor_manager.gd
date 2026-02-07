## AnchorManager — Guards the single point of truth in a world of lies.
## The anchor is a specific NPC (The Keeper) that NEVER lies, NEVER contradicts itself,
## and can disappear but NEVER deceives.
##
## Rules:
##   1. The anchor bypasses ALL god interference (gods cannot warp the Keeper)
##   2. The anchor is immune to trust_destruction.gd (always tells truth)
##   3. Silence and presence are logged distinctly (the game knows when truth is available)
##   4. The anchor can be PRESENT, SILENT, or ABSENT — never CORRUPTED
##
## This is the single most important system for preventing the game from collapsing into noise.
## If the player has no reliable reference point, every betrayal feels identical and meaningless.
extends Node

signal anchor_state_changed(old_state: String, new_state: String)
signal anchor_spoke(topic: String)
signal anchor_went_silent(reason: String)
signal anchor_returned()

# --- Anchor States ---
# PRESENT:  Anchor is in the current zone and will speak truthfully
# SILENT:   Anchor is present but will not speak (too much noise/pressure)
# ABSENT:   Anchor is not in the current zone (player must find them)
enum AnchorState { PRESENT, SILENT, ABSENT }

var current_state: AnchorState = AnchorState.ABSENT
var _state_names := {
	AnchorState.PRESENT: "present",
	AnchorState.SILENT: "silent",
	AnchorState.ABSENT: "absent",
}

# --- Anchor Identity ---
# The anchor node reference (set by The Keeper when it enters the tree)
var _anchor_node: Node = null
var anchor_id: String = "the_keeper"

# --- Presence Tracking ---
var _time_present: float = 0.0      # Total time anchor has been present this session
var _time_silent: float = 0.0       # Total time anchor has been silent this session
var _time_absent: float = 0.0       # Total time anchor has been absent this session
var _last_state_change: float = 0.0 # Timestamp of last state change
var _interactions_count: int = 0    # Times player has spoken to the anchor

# --- Silence Conditions ---
# The Keeper goes silent when the world is too loud/unstable to speak clearly.
# This is NOT deception — it's the honest acknowledgment that truth is obscured.
const SILENCE_PRESSURE_THRESHOLD := 75.0  # World pressure above this = silence
const SILENCE_ATTENTION_THRESHOLD := 80.0 # Any god attention above this = silence
const SILENCE_RECOVERY_HYSTERESIS := 5.0  # Must drop this far below threshold to recover

var _silence_locked: bool = false  # Prevents rapid toggling

# --- Absence Rules ---
# The Keeper appears in specific zones, not everywhere.
# Absence is meaningful — finding the Keeper requires effort.
var keeper_zones: Array[String] = ["test_zone", "hub_zone", "sanctuary"]
var _current_zone: String = ""

const PRESENCE_CHECK_INTERVAL := 2.0
var _check_timer: float = 0.0


func _ready() -> void:
	WorldManager.zone_loaded.connect(_on_zone_loaded) if WorldManager.has_signal("zone_loaded") else null


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < PRESENCE_CHECK_INTERVAL:
		return
	_check_timer = 0.0

	_update_state()
	_track_time(PRESENCE_CHECK_INTERVAL)


## Register the anchor node (called by The Keeper NPC when it enters the tree).
func register_anchor(node: Node) -> void:
	_anchor_node = node
	_set_state(AnchorState.PRESENT)
	WorldMemory.record("anchor_first_encountered")
	WorldMemory.record_ambient("The Keeper appeared")


## Unregister (called when anchor leaves the tree).
func unregister_anchor(node: Node) -> void:
	if _anchor_node == node:
		_anchor_node = null
		_set_state(AnchorState.ABSENT)


## Core query: Is this node the anchor?
## Called by TrustDestruction, GodManager, and any system that needs to check immunity.
func is_anchor(node: Node) -> bool:
	return node != null and node == _anchor_node


## Is the anchor immune to god interference? Always yes.
func is_immune_to_god_interference(node: Node) -> bool:
	return is_anchor(node)


## Is the anchor immune to trust destruction? Always yes.
func is_immune_to_trust_destruction(node: Node) -> bool:
	return is_anchor(node)


## Get current state as a string.
func get_state_name() -> String:
	return _state_names.get(current_state, "unknown")


## Is the anchor currently available and willing to speak?
func is_anchor_available() -> bool:
	return current_state == AnchorState.PRESENT and _anchor_node != null


## Record that the player interacted with the anchor.
func record_interaction(topic: String = "") -> void:
	_interactions_count += 1
	anchor_spoke.emit(topic)
	WorldMemory.record_ambient("The Keeper spoke about: %s" % topic if topic != "" else "The Keeper spoke")


## Update anchor state based on world conditions.
func _update_state() -> void:
	if _anchor_node == null:
		if current_state != AnchorState.ABSENT:
			_set_state(AnchorState.ABSENT)
		return

	# Check silence conditions
	var should_be_silent := _check_silence_conditions()

	if should_be_silent and current_state == AnchorState.PRESENT:
		_silence_locked = true
		_set_state(AnchorState.SILENT)
	elif not should_be_silent and current_state == AnchorState.SILENT:
		if not _silence_locked:
			_set_state(AnchorState.PRESENT)
		else:
			# Hysteresis: need to drop further below threshold to unlock
			var pressure := GameState.world_pressure
			var max_attention := _get_max_god_attention()
			if pressure < (SILENCE_PRESSURE_THRESHOLD - SILENCE_RECOVERY_HYSTERESIS) \
				and max_attention < (SILENCE_ATTENTION_THRESHOLD - SILENCE_RECOVERY_HYSTERESIS):
				_silence_locked = false
				_set_state(AnchorState.PRESENT)


## Check if the world is too unstable for the anchor to speak.
## Integrates with AnchorStrain (Phase 4.8): high strain lowers the silence threshold,
## making the Keeper go silent more easily under pressure.
func _check_silence_conditions() -> bool:
	# Witness mode: The Keeper is always present and always speaks (post-ending reflection)
	if GameState.witness_mode:
		return false

	# Use strain-adjusted thresholds when AnchorStrain is available
	var eff_pressure_threshold := SILENCE_PRESSURE_THRESHOLD
	var eff_attention_threshold := SILENCE_ATTENTION_THRESHOLD
	if AnchorStrain:
		eff_pressure_threshold = AnchorStrain.get_effective_silence_threshold()
		eff_attention_threshold = AnchorStrain.get_effective_attention_threshold()

	var pressure := GameState.world_pressure
	if pressure >= eff_pressure_threshold:
		return true

	var max_attention := _get_max_god_attention()
	if max_attention >= eff_attention_threshold:
		return true

	return false


func _get_max_god_attention() -> float:
	var max_att := 0.0
	for god_id in GodManager.god_defs:
		max_att = maxf(max_att, GodManager.get_god_attention(god_id))
	return max_att


## Set state and emit signals + log to WorldMemory.
func _set_state(new_state: AnchorState) -> void:
	var old_state := current_state
	if old_state == new_state:
		return

	current_state = new_state
	_last_state_change = Time.get_unix_time_from_system()

	var old_name := _state_names.get(old_state, "unknown")
	var new_name := _state_names.get(new_state, "unknown")
	anchor_state_changed.emit(old_name, new_name)

	# Log distinctly to WorldMemory
	match new_state:
		AnchorState.PRESENT:
			WorldMemory.record_ambient("The Keeper is present")
			anchor_returned.emit()
		AnchorState.SILENT:
			var reason := _get_silence_reason()
			WorldMemory.record_ambient("The Keeper fell silent: %s" % reason)
			anchor_went_silent.emit(reason)
		AnchorState.ABSENT:
			WorldMemory.record_ambient("The Keeper is absent")


func _get_silence_reason() -> String:
	if GameState.world_pressure >= SILENCE_PRESSURE_THRESHOLD:
		return "the world is too loud"
	if _get_max_god_attention() >= SILENCE_ATTENTION_THRESHOLD:
		return "divine attention is too intense"
	return "unknown"


## Track time spent in each state (for metrics/debug).
func _track_time(delta: float) -> void:
	match current_state:
		AnchorState.PRESENT:
			_time_present += delta
		AnchorState.SILENT:
			_time_silent += delta
		AnchorState.ABSENT:
			_time_absent += delta


## Zone change handler — determine if the Keeper should be in this zone.
func _on_zone_loaded(zone_id: String) -> void:
	_current_zone = zone_id
	# The Keeper appears in specific zones only
	if zone_id in keeper_zones and _anchor_node != null:
		_set_state(AnchorState.PRESENT)
	elif _anchor_node != null:
		_set_state(AnchorState.ABSENT)


# --- Debug API ---

## Get debug summary for overlay.
func get_debug_info() -> Dictionary:
	return {
		"state": get_state_name(),
		"time_present": _time_present,
		"time_silent": _time_silent,
		"time_absent": _time_absent,
		"interactions": _interactions_count,
		"last_change": _last_state_change,
		"silence_locked": _silence_locked,
		"trust_level": TrustDestruction.trust_level,
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"state": current_state,
		"time_present": _time_present,
		"time_silent": _time_silent,
		"time_absent": _time_absent,
		"interactions_count": _interactions_count,
		"silence_locked": _silence_locked,
	}


func load_state(data: Dictionary) -> void:
	current_state = data.get("state", AnchorState.ABSENT)
	_time_present = data.get("time_present", 0.0)
	_time_silent = data.get("time_silent", 0.0)
	_time_absent = data.get("time_absent", 0.0)
	_interactions_count = data.get("interactions_count", 0)
	_silence_locked = data.get("silence_locked", false)
