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
extends Node

signal strain_threshold_crossed(level: String)

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


func _ready() -> void:
	GodInterferenceEvents.interference_failed.connect(_on_interference_failed)


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

	# Natural decay — the anchor recovers when not stressed
	var decay := STRAIN_DECAY_RATE
	if AnchorManager.current_state == AnchorManager.AnchorState.ABSENT:
		decay = STRAIN_DECAY_WHEN_ABSENT  # Faster recovery when away
	anchor_strain -= decay * CHECK_INTERVAL

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
	# This means the Keeper goes silent at pressure 55 instead of 75
	silence_threshold_reduction = clampf(anchor_strain / 100.0 * 20.0, 0.0, 20.0)

	# Silence duration multiplier: at max strain, silence lasts 2x longer
	silence_duration_multiplier = 1.0 + clampf(anchor_strain / 100.0, 0.0, 1.0)


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


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"anchor_strain": anchor_strain,
		"strain_level": _current_level,
		"silence_threshold_reduction": silence_threshold_reduction,
		"silence_duration_multiplier": silence_duration_multiplier,
		"effective_silence_threshold": get_effective_silence_threshold(),
		"effective_attention_threshold": get_effective_attention_threshold(),
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"anchor_strain": anchor_strain,
	}


func load_state(data: Dictionary) -> void:
	anchor_strain = data.get("anchor_strain", 0.0)
	_update_effects()
