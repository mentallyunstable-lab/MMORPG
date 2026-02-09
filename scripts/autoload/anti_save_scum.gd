## AntiSaveScum — Detects when the player is reloading to fish for different betrayal outcomes.
## Does NOT punish explicitly. Instead:
##   - Next betrayal shifts category (so reloading doesn't avoid it)
##   - Or delays longer but hits harder
##   - The system "adjusts" — the player should FEEL it responding, not SEE it.
##
## This is soft detection. False positives are acceptable because the response is subtle.
## The goal: make save-scumming unrewarding, not impossible.
##
## D1 Extensions — Anti-Save-Scum Refinement:
##   - Hesitation reloads: detect reloads without any failure (reloaded from uncertainty)
##   - Delayed consequences: instead of escalating, delay consequences to appear later
##   - False success: reloads sometimes appear to work — then collapse later
extends Node

signal scum_detected(confidence: float)
signal betrayal_adjusted(adjustment_type: String)
signal hesitation_detected(confidence: float)
signal delayed_consequence_queued(delay: float)
signal false_success_triggered()

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

# --- D1: Hesitation Reload Detection ---
# Detects when the player reloads WITHOUT a preceding betrayal or failure.
# This is the most psychologically revealing pattern: pure uncertainty.
var _last_significant_event_time: float = 0.0  # Any betrayal, death, or major event
var hesitation_confidence: float = 0.0
const HESITATION_WINDOW := 60.0  # If load happens >60s after any event, it's hesitation
const HESITATION_CONFIDENCE_PER_LOAD := 0.15

# --- D1: Delayed Consequences ---
# Instead of making the next betrayal harder, queue a consequence for LATER.
# The player thinks the reload worked. It didn't.
var _delayed_consequences: Array[Dictionary] = []
const MAX_DELAYED_CONSEQUENCES := 5
const DELAYED_CONSEQUENCE_MIN := 120.0   # 2 minutes delay
const DELAYED_CONSEQUENCE_MAX := 480.0   # 8 minutes delay

# --- D1: False Success ---
# Sometimes the reload genuinely appears to have changed the outcome.
# The betrayal doesn't fire. The player relaxes. Then it fires later, harder.
var _false_success_active: bool = false
var _false_success_timer: float = 0.0
var _false_success_payload: Dictionary = {}
const FALSE_SUCCESS_CHANCE := 0.3  # 30% of detected scums trigger false success
const FALSE_SUCCESS_COLLAPSE_MIN := 180.0  # Collapse 3-8 minutes later
const FALSE_SUCCESS_COLLAPSE_MAX := 480.0


func _ready() -> void:
	BetrayalPacing.betrayal_occurred.connect(_on_betrayal_occurred)
	GameState.force_changed.connect(_on_significant_event)


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	# Natural confidence decay
	if scum_confidence > 0.0:
		scum_confidence = maxf(scum_confidence - CONFIDENCE_DECAY_RATE, 0.0)

	# D1: Process delayed consequences
	_process_delayed_consequences(CHECK_INTERVAL)

	# D1: Process false success collapse
	if _false_success_active:
		_false_success_timer += CHECK_INTERVAL
		var collapse_time: float = _false_success_payload.get("collapse_at", FALSE_SUCCESS_COLLAPSE_MAX)
		if _false_success_timer >= collapse_time:
			_trigger_false_success_collapse()


## Track significant events to distinguish hesitation from reaction.
func _on_significant_event(_a, _b, _c) -> void:
	_last_significant_event_time = Time.get_unix_time_from_system()


## Called when a betrayal occurs — record it for cross-reference with loads.
func _on_betrayal_occurred(betrayal_type: String, timestamp: float) -> void:
	_last_betrayal_type = betrayal_type
	_last_betrayal_time = timestamp


## Called when the game is loaded (from GameState.load_game or similar).
## This is the key detection point.
func on_game_loaded() -> void:
	var now := Time.get_unix_time_from_system()
	_load_timestamps.append(now)

	# D1: Hesitation detection — reload without recent significant event
	if _last_significant_event_time > 0.0 and (now - _last_significant_event_time) > HESITATION_WINDOW:
		hesitation_confidence = clampf(hesitation_confidence + HESITATION_CONFIDENCE_PER_LOAD, 0.0, 1.0)
		hesitation_detected.emit(hesitation_confidence)
	elif _last_betrayal_time <= 0.0:
		# No betrayal ever happened — pure hesitation
		hesitation_confidence = clampf(hesitation_confidence + HESITATION_CONFIDENCE_PER_LOAD, 0.0, 1.0)
		hesitation_detected.emit(hesitation_confidence)

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


func _apply_adjustment() -> void:
	if DevToggles and DevToggles.disable_anti_save_scum:
		return

	# D1: False success — 30% chance the betrayal appears to vanish
	if randf() < FALSE_SUCCESS_CHANCE:
		_false_success_active = true
		_false_success_timer = 0.0
		_false_success_payload = {
			"original_type": _last_betrayal_type,
			"collapse_at": randf_range(FALSE_SUCCESS_COLLAPSE_MIN, FALSE_SUCCESS_COLLAPSE_MAX),
			"intensity": 1.5,
		}
		false_success_triggered.emit()
		WorldMemory.record_ambient("The world appears to have corrected itself")
		return

	# D1: Delayed consequence — 40% chance
	if randf() < 0.4:
		var delay := randf_range(DELAYED_CONSEQUENCE_MIN, DELAYED_CONSEQUENCE_MAX)
		_delayed_consequences.append({
			"type": _last_betrayal_type,
			"queued_at": Time.get_unix_time_from_system(),
			"fire_at": delay,
			"elapsed": 0.0,
			"intensity": 1.3,
		})
		if _delayed_consequences.size() > MAX_DELAYED_CONSEQUENCES:
			_delayed_consequences.pop_front()
		delayed_consequence_queued.emit(delay)
		WorldMemory.record_ambient("Something shifts beneath the surface")
		return

	# Original behavior: category shift or delayed intensity
	if randf() < 0.6:
		_category_shift_active = true
		var categories := ["dialogue_lie", "env_misdirect", "god_interference", "audio_phantom"]
		categories.erase(_last_betrayal_type)
		_next_betrayal_override = categories[randi() % categories.size()]
		betrayal_adjusted.emit("category_shift")
	else:
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


# --- D1: Delayed Consequences Processing ---

## Process queued delayed consequences — fire them when their timer expires.
func _process_delayed_consequences(delta: float) -> void:
	if DevToggles and DevToggles.disable_delayed_consequences:
		return
	var to_remove: Array[int] = []
	for i in range(_delayed_consequences.size()):
		_delayed_consequences[i]["elapsed"] = _delayed_consequences[i].get("elapsed", 0.0) + delta
		if _delayed_consequences[i]["elapsed"] >= _delayed_consequences[i].get("fire_at", 300.0):
			var dc: Dictionary = _delayed_consequences[i]
			var dc_type: String = dc.get("type", "dialogue_lie")
			var dc_intensity: float = dc.get("intensity", 1.0)
			_betrayal_intensity_mult = dc_intensity
			betrayal_adjusted.emit("delayed_consequence_%s" % dc_type)
			WorldMemory.record_ambient("A consequence arrived late")
			to_remove.append(i)
	to_remove.reverse()
	for idx in to_remove:
		if idx < _delayed_consequences.size():
			_delayed_consequences.remove_at(idx)


## D1: False success collapse — the reload APPEARED to work, now it doesn't.
func _trigger_false_success_collapse() -> void:
	_false_success_active = false
	_false_success_timer = 0.0
	var payload_type: String = _false_success_payload.get("original_type", "dialogue_lie")
	var payload_intensity: float = _false_success_payload.get("intensity", 1.5)
	_betrayal_intensity_mult = payload_intensity
	_category_shift_active = true
	_next_betrayal_override = payload_type
	betrayal_adjusted.emit("false_success_collapse")
	WorldMemory.record_ambient("What seemed corrected reveals itself as unchanged")
	_false_success_payload = {}


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"scum_confidence": scum_confidence,
		"hesitation_confidence": hesitation_confidence,
		"suspicious_loads": _betrayal_before_load.size(),
		"total_loads": _load_timestamps.size(),
		"category_shift_active": _category_shift_active,
		"next_override": _next_betrayal_override,
		"intensity_mult": _betrayal_intensity_mult,
		"delayed_consequences": _delayed_consequences.size(),
		"false_success_active": _false_success_active,
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
