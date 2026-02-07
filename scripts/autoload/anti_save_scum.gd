## AntiSaveScum — Detects when the player is reloading to fish for different betrayal outcomes.
## Does NOT punish explicitly. Instead:
##   - Next betrayal shifts category (so reloading doesn't avoid it)
##   - Or delays longer but hits harder
##   - The system "adjusts" — the player should FEEL it responding, not SEE it.
##
## This is soft detection. False positives are acceptable because the response is subtle.
## The goal: make save-scumming unrewarding, not impossible.
extends Node

signal scum_detected(confidence: float)
signal betrayal_adjusted(adjustment_type: String)

# --- Detection ---
# Track load events and their proximity to betrayal events.
var _load_timestamps: Array[float] = []
var _betrayal_before_load: Array[Dictionary] = []  # Betrayals that happened right before a load
const LOAD_BETRAYAL_WINDOW := 30.0  # If a load happens within 30s of a betrayal, suspicious

# Confidence score: 0.0 = no evidence, 1.0 = definitely scumming
var scum_confidence: float = 0.0
const CONFIDENCE_PER_SUSPICIOUS_LOAD := 0.25
const CONFIDENCE_DECAY_RATE := 0.01  # Decays per check if no suspicious loads

# --- Adjustments ---
# When confidence is high, the betrayal system shifts behavior.
var _category_shift_active: bool = false
var _next_betrayal_override: String = ""  # Force next betrayal to be this type
var _betrayal_intensity_mult: float = 1.0  # Multiplier on betrayal impact

const CHECK_INTERVAL := 10.0
var _check_timer: float = 0.0

# --- Last Betrayal Tracking ---
var _last_betrayal_type: String = ""
var _last_betrayal_time: float = 0.0


func _ready() -> void:
	BetrayalPacing.betrayal_occurred.connect(_on_betrayal_occurred)


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	# Natural confidence decay
	if scum_confidence > 0.0:
		scum_confidence = maxf(scum_confidence - CONFIDENCE_DECAY_RATE, 0.0)


## Called when a betrayal occurs — record it for cross-reference with loads.
func _on_betrayal_occurred(betrayal_type: String, timestamp: float) -> void:
	_last_betrayal_type = betrayal_type
	_last_betrayal_time = timestamp


## Called when the game is loaded (from GameState.load_game or similar).
## This is the key detection point.
func on_game_loaded() -> void:
	var now := Time.get_unix_time_from_system()
	_load_timestamps.append(now)

	# Check if a betrayal happened right before this load
	if _last_betrayal_time > 0.0 and (now - _last_betrayal_time) < LOAD_BETRAYAL_WINDOW:
		_betrayal_before_load.append({
			"betrayal_type": _last_betrayal_type,
			"betrayal_time": _last_betrayal_time,
			"load_time": now,
			"gap": now - _last_betrayal_time,
		})
		scum_confidence = clampf(scum_confidence + CONFIDENCE_PER_SUSPICIOUS_LOAD, 0.0, 1.0)
		scum_detected.emit(scum_confidence)

		# Apply adjustments based on confidence
		if scum_confidence >= 0.5:
			_apply_adjustment()

	# Prune old timestamps (keep last 20)
	while _load_timestamps.size() > 20:
		_load_timestamps.pop_front()
	while _betrayal_before_load.size() > 10:
		_betrayal_before_load.pop_front()


## Apply a subtle adjustment to the betrayal system.
func _apply_adjustment() -> void:
	# Strategy 1: Category shift — next betrayal is a DIFFERENT type
	# So reloading to avoid a dialogue_lie might get you a god_interference instead
	if randf() < 0.6:
		_category_shift_active = true
		var categories := ["dialogue_lie", "env_misdirect", "god_interference", "audio_phantom"]
		categories.erase(_last_betrayal_type)
		_next_betrayal_override = categories[randi() % categories.size()]
		betrayal_adjusted.emit("category_shift")
	else:
		# Strategy 2: Delay + intensity — betrayal comes later but hits harder
		_betrayal_intensity_mult = 1.5
		betrayal_adjusted.emit("delayed_intensity")

	WorldMemory.record_ambient("The world adjusts to repetition")


## Query: should the next betrayal be overridden to a different category?
## Called by BetrayalPacing or TrustDestruction before firing a betrayal.
func get_betrayal_override() -> String:
	if _category_shift_active and _next_betrayal_override != "":
		var override := _next_betrayal_override
		_category_shift_active = false
		_next_betrayal_override = ""
		return override
	return ""


## Query: get the current betrayal intensity multiplier.
func get_intensity_multiplier() -> float:
	var mult := _betrayal_intensity_mult
	# Reset after use
	if _betrayal_intensity_mult > 1.0:
		_betrayal_intensity_mult = 1.0
	return mult


## Query: is the system currently suspicious?
func is_suspicious() -> bool:
	return scum_confidence >= 0.25


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"scum_confidence": scum_confidence,
		"suspicious_loads": _betrayal_before_load.size(),
		"total_loads": _load_timestamps.size(),
		"category_shift_active": _category_shift_active,
		"next_override": _next_betrayal_override,
		"intensity_mult": _betrayal_intensity_mult,
	}


# --- Persistence ---
# Intentionally NOT persisted — reloading clears the detection state.
# This is by design: the system detects PATTERNS of reloading,
# not individual loads. A fresh session starts clean.

func save_state() -> Dictionary:
	return {}


func load_state(_data: Dictionary) -> void:
	# Detection resets on load — but on_game_loaded() is called AFTER this,
	# so the pattern detection still works across loads.
	pass
