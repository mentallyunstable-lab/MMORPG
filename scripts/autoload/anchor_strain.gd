## AnchorStrain — The anchor resists, not dominates. Hidden variable tracking
## how much pressure the Keeper is under from divine interference and world instability.
##
## anchor_strain increases with:
##   - Max god_attention
##   - Repeated nearby interventions (from GodInterferenceEvents)
##   - Extreme world pressure
##
## At high strain:
##   - Keeper goes SILENT faster (lower threshold)
##   - Absence lasts longer
##   - Silence periods extend
##
## This meter is NEVER exposed directly to the player.
## They should sense it through the Keeper's behavior, not through a number.
##
## C1 Extensions — Anchor Strain Feedback (Invisible):
##   - High strain: Keeper answers remain correct but important info comes LAST
##   - High strain: longer pauses before the Keeper speaks (query for dialogue timing)
##   - Strain recovery: at high levels, only recovers through independent player action
##     (force changes without Keeper visit, NPC dialogue without Keeper, etc.)
extends Node

signal strain_threshold_crossed(level: String)
signal strain_recovery_event(source: String, amount: float)

# --- Hidden Strain Variable ---
# 0.0 = no strain, 100.0 = maximum strain
var anchor_strain: float = 0.0

# --- Strain Sources ---
const STRAIN_PER_GOD_ATTENTION_POINT := 0.003  # Per point of max god attention per tick
const STRAIN_PER_INTERFERENCE := 8.0            # Per failed god interference event
const STRAIN_PER_PRESSURE_POINT := 0.002        # Per world pressure point per tick
const STRAIN_DECAY_RATE := 0.1                   # Natural decay per tick
const STRAIN_DECAY_WHEN_ABSENT := 0.3            # Faster decay when Keeper is absent

# --- Strain Thresholds ---
const STRAIN_LOW := 25.0
const STRAIN_MEDIUM := 50.0
const STRAIN_HIGH := 75.0
const STRAIN_CRITICAL := 90.0

var _current_level: String = "none"

# --- Effect on Keeper ---
# At high strain, the Keeper's silence threshold drops (goes silent more easily).
# This modifies AnchorManager's SILENCE_PRESSURE_THRESHOLD effectively.
var silence_threshold_reduction: float = 0.0  # 0.0 = no change, 20.0 = threshold drops by 20

# At high strain, silence duration extends.
var silence_duration_multiplier: float = 1.0  # 1.0 = normal, 2.0 = double duration

# --- Timing ---
const CHECK_INTERVAL := 5.0
var _check_timer: float = 0.0

# --- C1: Info Reordering ---
# At high strain, the Keeper's answers are still correct but reordered:
# important information comes last, trivial details first.
# 0.0 = normal order, 1.0 = completely reversed priority
var info_reorder_factor: float = 0.0

# --- C1: Dialogue Pause ---
# At high strain, the Keeper hesitates longer before speaking.
# Base delay in milliseconds added before dialogue lines.
var dialogue_pause_ms: float = 0.0
const PAUSE_BASE_MS := 0.0       # No pause at zero strain
const PAUSE_MAX_MS := 800.0      # 800ms at max strain

# --- C1: Independent Recovery ---
# At MEDIUM+ strain, time-based decay stops. Strain only drops through
# player actions taken WITHOUT consulting the Keeper first.
var _independent_actions_since_keeper: int = 0
const INDEPENDENT_ACTIONS_FOR_RECOVERY := 3  # Need 3 actions without Keeper
const INDEPENDENT_RECOVERY_AMOUNT := 5.0     # How much strain drops per independent action set
var _last_keeper_interaction_time: float = 0.0
const INDEPENDENT_ACTION_WINDOW := 300.0     # Actions must be >5 min after Keeper visit


func _ready() -> void:
	GodInterferenceEvents.interference_failed.connect(_on_interference_failed)
	GameState.force_changed.connect(_on_force_changed)
	AnchorManager.anchor_spoke.connect(_on_keeper_spoke_for_strain)


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	_update_strain()
	_update_effects()


## Update strain based on current world state.
func _update_strain() -> void:
	var old_strain := anchor_strain

	# Accumulate strain from god attention
	var max_attention := 0.0
	for god_id in GodManager.god_defs:
		max_attention = maxf(max_attention, GodManager.get_god_attention(god_id))
	anchor_strain += max_attention * STRAIN_PER_GOD_ATTENTION_POINT * CHECK_INTERVAL

	# Accumulate strain from world pressure
	anchor_strain += GameState.world_pressure * STRAIN_PER_PRESSURE_POINT * CHECK_INTERVAL

	# Natural decay — modified by C1 independent recovery
	# At low strain: normal time-based decay
	# At MEDIUM+ strain: decay requires independent player action
	if anchor_strain < STRAIN_MEDIUM:
		var decay := STRAIN_DECAY_RATE
		if AnchorManager.current_state == AnchorManager.AnchorState.ABSENT:
			decay = STRAIN_DECAY_WHEN_ABSENT
		anchor_strain -= decay * CHECK_INTERVAL
	else:
		# High strain: minimal time decay, primary recovery through independence
		var minimal_decay := STRAIN_DECAY_RATE * 0.1  # 10% of normal
		if AnchorManager.current_state == AnchorManager.AnchorState.ABSENT:
			minimal_decay = STRAIN_DECAY_RATE * 0.2
		anchor_strain -= minimal_decay * CHECK_INTERVAL

	anchor_strain = clampf(anchor_strain, 0.0, 100.0)

	# Check threshold crossings
	var old_level := _current_level
	if anchor_strain >= STRAIN_CRITICAL:
		_current_level = "critical"
	elif anchor_strain >= STRAIN_HIGH:
		_current_level = "high"
	elif anchor_strain >= STRAIN_MEDIUM:
		_current_level = "medium"
	elif anchor_strain >= STRAIN_LOW:
		_current_level = "low"
	else:
		_current_level = "none"

	if old_level != _current_level:
		strain_threshold_crossed.emit(_current_level)
		if _current_level in ["high", "critical"]:
			WorldMemory.record("anchor_strain_%s" % _current_level)


## Update the Keeper behavior modifications based on strain.
func _update_effects() -> void:
	# Silence threshold reduction: at max strain, threshold drops by 20 points
	silence_threshold_reduction = clampf(anchor_strain / 100.0 * 20.0, 0.0, 20.0)
	# Silence duration multiplier: at max strain, silence lasts 2x longer
	silence_duration_multiplier = 1.0 + clampf(anchor_strain / 100.0, 0.0, 1.0)

	# C1: Info reordering — important info moves to the end at high strain
	info_reorder_factor = clampf((anchor_strain - STRAIN_MEDIUM) / (100.0 - STRAIN_MEDIUM), 0.0, 1.0)

	# C1: Dialogue pause — Keeper hesitates longer at high strain
	dialogue_pause_ms = lerpf(PAUSE_BASE_MS, PAUSE_MAX_MS, clampf(anchor_strain / 100.0, 0.0, 1.0))


## Called when a god fails to interfere near the Keeper.
func _on_interference_failed(_god_id: String, _action: String, _reason: String) -> void:
	anchor_strain += STRAIN_PER_INTERFERENCE
	anchor_strain = clampf(anchor_strain, 0.0, 100.0)


## Get the effective silence pressure threshold (modified by strain).
## Used by AnchorManager to determine when the Keeper goes silent.
func get_effective_silence_threshold() -> float:
	return AnchorManager.SILENCE_PRESSURE_THRESHOLD - silence_threshold_reduction


## Get the effective silence attention threshold (modified by strain).
func get_effective_attention_threshold() -> float:
	return AnchorManager.SILENCE_ATTENTION_THRESHOLD - silence_threshold_reduction * 0.5


## Get the current strain level as a string (for debug only).
func get_strain_level() -> String:
	return _current_level


# --- C1: Independent Action Tracking ---

## Track when the Keeper speaks (resets independent action counter).
func _on_keeper_spoke_for_strain(_topic: String) -> void:
	_last_keeper_interaction_time = Time.get_unix_time_from_system()
	_independent_actions_since_keeper = 0


## Track force changes as potential independent actions.
func _on_force_changed(_force: String, _old: float, _new: float) -> void:
	if GameState.witness_mode:
		return
	var now := Time.get_unix_time_from_system()
	# Only count as independent if sufficiently after last Keeper visit
	if now - _last_keeper_interaction_time < INDEPENDENT_ACTION_WINDOW:
		return
	_independent_actions_since_keeper += 1
	if _independent_actions_since_keeper >= INDEPENDENT_ACTIONS_FOR_RECOVERY:
		_independent_actions_since_keeper = 0
		var recovery := INDEPENDENT_RECOVERY_AMOUNT
		anchor_strain = maxf(anchor_strain - recovery, 0.0)
		strain_recovery_event.emit("independent_action", recovery)


## C1: Get the info reorder factor for Keeper dialogue.
## 0.0 = normal order, 1.0 = reversed (important info last).
func get_info_reorder_factor() -> float:
	return info_reorder_factor


## C1: Get dialogue pause duration in milliseconds.
func get_dialogue_pause_ms() -> float:
	if DevToggles and DevToggles.disable_dialogue_timing:
		return 0.0
	return dialogue_pause_ms


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"anchor_strain": anchor_strain,
		"strain_level": _current_level,
		"silence_threshold_reduction": silence_threshold_reduction,
		"silence_duration_multiplier": silence_duration_multiplier,
		"effective_silence_threshold": get_effective_silence_threshold(),
		"effective_attention_threshold": get_effective_attention_threshold(),
		"info_reorder_factor": info_reorder_factor,
		"dialogue_pause_ms": dialogue_pause_ms,
		"independent_actions": _independent_actions_since_keeper,
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"anchor_strain": anchor_strain,
	}


func load_state(data: Dictionary) -> void:
	anchor_strain = data.get("anchor_strain", 0.0)
	_update_effects()
