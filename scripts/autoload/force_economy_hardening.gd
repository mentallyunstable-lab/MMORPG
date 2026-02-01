## ForceEconomyHardening — Phase G1: Soft caps, cross-force contamination,
## hidden fatigue, and dev-only force gain logging.
## Prevents prayer spam, silence-only runs, violence speedruns, AFK idling.
extends Node

# --- Per-Hour Soft Caps ---
# Each force has a maximum effective gain per rolling hour.
const HOURLY_CAP_PER_FORCE := 60.0  # Max effective gain per force per hour
const HOURLY_WINDOW := 3600.0  # Seconds in an hour

# Rolling gain trackers: force_name -> Array of {time, amount}
var _gain_log: Dictionary = {
	"faith": [],
	"truth": [],
	"violence": [],
}

# --- Cross-Force Contamination ---
# Gaining one force temporarily reduces gain rate of opposing forces.
# This prevents perfectly balanced play — you must commit.
var _contamination: Dictionary = {
	"faith": 0.0,   # Contamination level (0-1) — reduces truth/violence gains
	"truth": 0.0,
	"violence": 0.0,
}
const CONTAMINATION_DECAY_RATE := 0.01  # Per second
const CONTAMINATION_PER_GAIN := 0.02    # Per point of force gained
const CONTAMINATION_PENALTY := 0.4      # Max penalty multiplier (60% of gain at max contamination)

# --- Hidden Fatigue ---
# Player never sees this. Accumulated force activity produces diminishing engagement.
# Resets partially on zone change or significant time gap.
var _fatigue: float = 0.0  # 0 = fresh, 1 = exhausted
const FATIGUE_PER_FORCE_EVENT := 0.02
const FATIGUE_DECAY_RATE := 0.005  # Per second (slow)
const FATIGUE_PENALTY_THRESHOLD := 0.5  # Below this, no penalty
const FATIGUE_MAX_PENALTY := 0.5  # At max fatigue, gains are halved
const FATIGUE_ZONE_RESET := 0.3  # Fatigue reduction on zone change

# --- Dev Overlay Logging ---
# Records why force was gained/lost. Toggle with dev key.
var _force_log: Array[Dictionary] = []  # {time, force, amount, reason, source}
const MAX_LOG_ENTRIES := 100
var dev_overlay_visible: bool = false

signal force_logged(entry: Dictionary)


func _ready() -> void:
	GameState.force_changed.connect(_on_force_changed)
	if WorldManager:
		WorldManager.zone_loaded.connect(_on_zone_loaded)


func _process(delta: float) -> void:
	# Decay contamination
	for force in _contamination:
		_contamination[force] = maxf(_contamination[force] - CONTAMINATION_DECAY_RATE * delta, 0.0)

	# Decay fatigue
	_fatigue = maxf(_fatigue - FATIGUE_DECAY_RATE * delta, 0.0)

	# Prune old gain log entries
	var now := Time.get_ticks_msec() / 1000.0
	for force in _gain_log:
		var log: Array = _gain_log[force]
		while log.size() > 0 and now - log[0]["time"] > HOURLY_WINDOW:
			log.pop_front()

	# Dev overlay toggle (F9)
	if Input.is_action_just_pressed("ui_end"):  # Fallback key
		dev_overlay_visible = not dev_overlay_visible


## Called BEFORE GameState.add_force — returns the effective multiplier.
## This is the main entry point for economy hardening.
func get_gain_multiplier(force_name: String, raw_amount: float, reason: String = "", source: String = "") -> float:
	if raw_amount <= 0:
		return 1.0  # Losses always apply fully

	var mult := 1.0

	# 1. Hourly soft cap
	var hourly_total := _get_hourly_total(force_name)
	if hourly_total >= HOURLY_CAP_PER_FORCE:
		mult *= 0.1  # 90% reduction past cap
	elif hourly_total >= HOURLY_CAP_PER_FORCE * 0.7:
		mult *= 0.5  # 50% reduction approaching cap

	# 2. Cross-force contamination
	var opposing_contamination := _get_opposing_contamination(force_name)
	mult *= (1.0 - opposing_contamination * CONTAMINATION_PENALTY)

	# 3. Hidden fatigue
	if _fatigue > FATIGUE_PENALTY_THRESHOLD:
		var fatigue_ratio := (_fatigue - FATIGUE_PENALTY_THRESHOLD) / (1.0 - FATIGUE_PENALTY_THRESHOLD)
		mult *= (1.0 - fatigue_ratio * FATIGUE_MAX_PENALTY)

	# Record the gain
	_record_gain(force_name, raw_amount * mult, reason, source)

	# Increase contamination for this force
	_contamination[force_name] = clampf(
		_contamination[force_name] + raw_amount * CONTAMINATION_PER_GAIN, 0.0, 1.0)

	# Increase fatigue
	_fatigue = clampf(_fatigue + FATIGUE_PER_FORCE_EVENT, 0.0, 1.0)

	return mult


func _get_hourly_total(force_name: String) -> float:
	var total := 0.0
	for entry in _gain_log[force_name]:
		total += entry["amount"]
	return total


func _get_opposing_contamination(force_name: String) -> float:
	# Average contamination of the OTHER two forces
	var total := 0.0
	var count := 0
	for f in _contamination:
		if f != force_name:
			total += _contamination[f]
			count += 1
	return total / maxf(count, 1)


func _record_gain(force_name: String, effective_amount: float, reason: String, source: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_gain_log[force_name].append({"time": now, "amount": effective_amount})

	var entry := {
		"time": now,
		"force": force_name,
		"amount": effective_amount,
		"reason": reason if reason != "" else "unknown",
		"source": source if source != "" else "unknown",
		"fatigue": _fatigue,
		"contamination": _contamination.duplicate(),
	}
	_force_log.append(entry)
	if _force_log.size() > MAX_LOG_ENTRIES:
		_force_log.pop_front()
	force_logged.emit(entry)


func _on_force_changed(_force_name: String, _old: float, _new: float) -> void:
	pass  # Tracking happens in get_gain_multiplier


func _on_zone_loaded(_zone_id: String) -> void:
	_fatigue = maxf(_fatigue - FATIGUE_ZONE_RESET, 0.0)


## Get current fatigue (hidden from player, visible to dev overlay)
func get_fatigue() -> float:
	return _fatigue


## Get contamination levels
func get_contamination() -> Dictionary:
	return _contamination.duplicate()


## Get recent force log entries
func get_recent_log(count: int = 20) -> Array[Dictionary]:
	var start := maxi(0, _force_log.size() - count)
	return _force_log.slice(start) as Array[Dictionary]


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"fatigue": _fatigue,
		"contamination": _contamination.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	_fatigue = data.get("fatigue", 0.0)
	_contamination = data.get("contamination", {
		"faith": 0.0, "truth": 0.0, "violence": 0.0,
	})
