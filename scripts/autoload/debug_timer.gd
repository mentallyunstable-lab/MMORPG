## DebugTimer — Logs playtest milestones: first force gain, first combat, first world event.
## Toggle with GameState debug_mode. Outputs to console on session end or on demand.
extends Node

# Milestone timestamps (seconds since session start, -1 = not yet)
var _session_start: float = 0.0
var _first_force_gain: float = -1.0
var _first_combat: float = -1.0
var _first_world_event: float = -1.0
var _first_dialogue: float = -1.0
var _first_quest_accept: float = -1.0
var _first_god_encounter: float = -1.0

# Force economy tracking
var _force_gains: Dictionary = {"faith": 0.0, "truth": 0.0, "violence": 0.0}
var _force_gain_count: Dictionary = {"faith": 0, "truth": 0, "violence": 0}

var enabled: bool = true


func _ready() -> void:
	_session_start = Time.get_unix_time_from_system()
	GameState.force_changed.connect(_on_force_changed)
	WorldEventManager.event_triggered.connect(_on_world_event)
	WorldEventManager.event_notification.connect(_on_event_notification)
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	QuestManager.quest_accepted.connect(_on_quest_accepted)


func _elapsed() -> float:
	return Time.get_unix_time_from_system() - _session_start


func _on_force_changed(force_name: String, old_value: float, new_value: float) -> void:
	if not enabled:
		return
	var delta := new_value - old_value
	if delta > 0:
		if _first_force_gain < 0:
			_first_force_gain = _elapsed()
		_force_gains[force_name] = _force_gains.get(force_name, 0.0) + delta
		_force_gain_count[force_name] = _force_gain_count.get(force_name, 0) + 1


func _on_world_event(_event_id: String, _data: Dictionary) -> void:
	if not enabled:
		return
	if _first_world_event < 0:
		_first_world_event = _elapsed()


func _on_event_notification(title: String, _desc: String) -> void:
	if not enabled:
		return
	if "God Encounter" in title and _first_god_encounter < 0:
		_first_god_encounter = _elapsed()


func _on_dialogue_started(_speaker: String = "") -> void:
	if not enabled:
		return
	if _first_dialogue < 0:
		_first_dialogue = _elapsed()


func _on_quest_accepted(_quest_id: String) -> void:
	if not enabled:
		return
	if _first_quest_accept < 0:
		_first_quest_accept = _elapsed()


## Call this to get a full playtest report as a string.
func get_report() -> String:
	var elapsed := _elapsed()
	var lines: PackedStringArray = []
	lines.append("=== PLAYTEST REPORT (%.0fs elapsed) ===" % elapsed)
	lines.append("First force gain:    %s" % _fmt(_first_force_gain))
	lines.append("First dialogue:      %s" % _fmt(_first_dialogue))
	lines.append("First quest accept:  %s" % _fmt(_first_quest_accept))
	lines.append("First combat:        %s" % _fmt(_first_combat))
	lines.append("First world event:   %s" % _fmt(_first_world_event))
	lines.append("First god encounter: %s" % _fmt(_first_god_encounter))
	lines.append("")
	lines.append("--- Force Economy ---")
	for force_name in ["faith", "truth", "violence"]:
		var total: float = _force_gains.get(force_name, 0.0)
		var count: int = _force_gain_count.get(force_name, 0)
		var rate := total / maxf(elapsed / 60.0, 0.01)
		lines.append("  %s: total=%.1f  count=%d  rate=%.1f/min" % [force_name.capitalize(), total, count, rate])
	lines.append("")
	lines.append("--- Current State ---")
	lines.append("  Faith=%.1f  Truth=%.1f  Violence=%.1f  Pressure=%.1f" % [
		GameState.faith, GameState.truth, GameState.violence, GameState.world_pressure])
	lines.append("=== END REPORT ===")
	return "\n".join(lines)


func _fmt(timestamp: float) -> String:
	if timestamp < 0:
		return "NEVER"
	return "%.0fs" % timestamp


## Mark first combat (called externally when player deals/takes damage)
func mark_first_combat() -> void:
	if _first_combat < 0:
		_first_combat = _elapsed()
