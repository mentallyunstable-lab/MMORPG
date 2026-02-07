## SilenceMemory — Makes silence remembered, not skipped.
## Logs silence periods with duration, player proximity, and decisions made during silence.
## Later NPCs may reference these periods: "You acted when even the Keeper would not speak."
##
## This system exists to give WEIGHT to silence. If silence leaves no trace,
## players learn to ignore it. If it's recorded and reflected back,
## silence becomes a meaningful part of the player's story.
extends Node

signal silence_period_recorded(period: Dictionary)

# --- Silence Period Tracking ---
var _current_period: Dictionary = {}
var _is_tracking: bool = false
var recorded_periods: Array[Dictionary] = []
const MAX_RECORDED_PERIODS := 20

# --- Decision Tracking During Silence ---
var _decisions_during_current_silence: Array[Dictionary] = []

# --- NPC Reference Phrases ---
# These are templates NPCs can pull from when referencing past silence periods.
const SILENCE_REFERENCES := [
	"You acted when even the Keeper would not speak.",
	"I remember the quiet. You moved through it without certainty.",
	"The Keeper's silence tested you. You chose anyway.",
	"There was a time the world had no anchor. You found your own footing.",
	"When the Keeper went quiet, you didn't stop. That says something.",
	"Some break in silence. You made decisions.",
	"The quiet time... you remember it too, don't you?",
]

const LONG_SILENCE_REFERENCES := [
	"The Keeper was silent for a long time. You survived it.",
	"That long silence changed you. I can see it.",
	"When truth went quiet for that long... most people freeze. You didn't.",
]


func _ready() -> void:
	AnchorManager.anchor_state_changed.connect(_on_anchor_state_changed)
	GameState.force_changed.connect(_on_force_changed_during_silence)


## Track anchor state transitions.
func _on_anchor_state_changed(_old: String, new_state: String) -> void:
	if new_state == "silent":
		_begin_tracking()
	elif _is_tracking and new_state != "silent":
		_end_tracking()


## Begin recording a silence period.
func _begin_tracking() -> void:
	_is_tracking = true
	_decisions_during_current_silence.clear()
	_current_period = {
		"start_time": Time.get_unix_time_from_system(),
		"duration": 0.0,
		"decisions_made": 0,
		"decision_types": [],
		"player_proximity": "near",  # Updated by proximity checks
	}


## End recording and store the silence period.
func _end_tracking() -> void:
	if not _is_tracking:
		return
	_is_tracking = false

	_current_period["duration"] = Time.get_unix_time_from_system() - _current_period.get("start_time", 0.0)
	_current_period["decisions_made"] = _decisions_during_current_silence.size()

	# Classify decisions
	var types: Array[String] = []
	for decision in _decisions_during_current_silence:
		var force: String = decision.get("force", "")
		if force != "" and force not in types:
			types.append(force)
	_current_period["decision_types"] = types

	# Only record meaningful silence periods (> 30 seconds)
	if _current_period["duration"] > 30.0:
		recorded_periods.append(_current_period.duplicate())
		if recorded_periods.size() > MAX_RECORDED_PERIODS:
			recorded_periods.pop_front()
		silence_period_recorded.emit(_current_period)

		# Log to WorldMemory
		var duration_str := "%.0f seconds" % _current_period["duration"]
		var decisions_str := "%d decisions" % _current_period["decisions_made"]
		WorldMemory.record_ambient("Keeper silence lasted %s, player made %s" % [duration_str, decisions_str])

		if _current_period["duration"] > 300.0:  # 5+ minutes
			WorldMemory.record("keeper_long_silence_%d" % recorded_periods.size())

	_current_period = {}
	_decisions_during_current_silence.clear()


## Track force changes during silence as "decisions."
func _on_force_changed_during_silence(force_name: String, old_value: float, new_value: float) -> void:
	if not _is_tracking:
		return
	if GameState.witness_mode:
		return

	# Only track meaningful changes (not passive drift)
	if absf(new_value - old_value) > 1.0:
		_decisions_during_current_silence.append({
			"force": force_name,
			"old": old_value,
			"new": new_value,
			"timestamp": Time.get_unix_time_from_system(),
		})


## Get a silence reference phrase for NPC dialogue.
## Returns empty string if player hasn't experienced notable silence.
func get_silence_reference() -> String:
	if recorded_periods.is_empty():
		return ""

	var last_period: Dictionary = recorded_periods[recorded_periods.size() - 1]
	var duration: float = last_period.get("duration", 0.0)

	if duration > 300.0:
		return LONG_SILENCE_REFERENCES[randi() % LONG_SILENCE_REFERENCES.size()]
	elif duration > 30.0:
		return SILENCE_REFERENCES[randi() % SILENCE_REFERENCES.size()]
	return ""


## Get total time spent in silence across all recorded periods.
func get_total_silence_time() -> float:
	var total := 0.0
	for period in recorded_periods:
		total += period.get("duration", 0.0)
	return total


## Get total decisions made during all silence periods.
func get_total_silence_decisions() -> int:
	var total := 0
	for period in recorded_periods:
		total += period.get("decisions_made", 0)
	return total


## Check if the player has experienced significant silence.
func has_notable_silence() -> bool:
	return get_total_silence_time() > 60.0


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"is_tracking": _is_tracking,
		"current_duration": Time.get_unix_time_from_system() - _current_period.get("start_time", 0.0) if _is_tracking else 0.0,
		"recorded_periods": recorded_periods.size(),
		"total_silence_time": get_total_silence_time(),
		"total_silence_decisions": get_total_silence_decisions(),
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"recorded_periods": recorded_periods.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	var loaded = data.get("recorded_periods", [])
	recorded_periods.clear()
	for period in loaded:
		recorded_periods.append(period)
