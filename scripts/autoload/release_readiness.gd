## ReleaseReadiness — Phase O: Reality Check.
## O1: Hard Locks (no new mechanics, no new gods, only refinement)
## O2: External Playtest hooks (observation tools, misinterpretation tracking)
## O3: Final Question system (does the game haunt without explanation?)
extends Node

# --- O1: Hard Locks ---
# Feature freeze enforcement. Track what's in the game, prevent scope creep.

const LOCKED_GODS := ["verath", "kael", "null_throne"]
const LOCKED_FORCES := ["faith", "truth", "violence"]
const LOCKED_ZONES := ["test_zone", "hollowed_seminary"]
const LOCKED_FACTIONS := ["ashwalkers", "truthseekers", "ironvow", "hollow_church"]

signal scope_violation(violation_type: String, details: String)

## Validate that no new mechanics/gods/zones have been added beyond the locked set.
func validate_hard_locks() -> Array[String]:
	var violations: Array[String] = []

	# Check gods
	for god_id in GodManager.god_defs:
		if god_id not in LOCKED_GODS:
			violations.append("Unlocked god detected: %s" % god_id)
			scope_violation.emit("new_god", god_id)

	# Check factions
	for faction_id in FactionManager.faction_defs:
		if faction_id not in LOCKED_FACTIONS:
			violations.append("Unlocked faction detected: %s" % faction_id)
			scope_violation.emit("new_faction", faction_id)

	return violations


# --- O2: External Playtest Hooks ---
# Tools for watching players without correcting them.

signal playtest_event(event_type: String, data: Dictionary)

# Track player behaviors for playtest analysis
var _playtest_log: Array[Dictionary] = []
const MAX_PLAYTEST_LOG := 500

# Misinterpretation tracking — when players do something the designer didn't expect
var _unexpected_behaviors: Array[Dictionary] = []

# Session metrics
var _session_start_time: float = 0.0
var _total_play_time: float = 0.0
var _zone_time: Dictionary = {}  # zone_id -> seconds spent
var _system_discovery_order: Array[String] = []  # Order in which player discovered systems
var _first_death_time: float = -1.0
var _first_save_time: float = -1.0
var _first_god_encounter_time: float = -1.0
var _endings_reached: Array[String] = []
var _quests_accepted: int = 0
var _quests_completed: int = 0
var _quests_ignored: int = 0
var _quests_failed: int = 0
var _total_force_gains: Dictionary = {"faith": 0.0, "truth": 0.0, "violence": 0.0}
var _npc_interactions: int = 0
var _shrine_uses: int = 0
var _combat_encounters: int = 0
var _deaths: int = 0

var _playtest_active: bool = false


func _ready() -> void:
	_session_start_time = Time.get_ticks_msec() / 1000.0

	# Connect to systems for passive tracking
	GameState.force_changed.connect(_on_force_changed)
	QuestManager.quest_accepted.connect(_on_quest_accepted)
	QuestManager.quest_completed.connect(_on_quest_completed)
	QuestManager.quest_failed.connect(_on_quest_failed)
	WorldEventManager.ending_reached.connect(_on_ending_reached)
	WorldManager.zone_loaded.connect(_on_zone_loaded)


func _process(delta: float) -> void:
	_total_play_time += delta

	# Track time in current zone
	if WorldManager.current_zone_id != "":
		_zone_time[WorldManager.current_zone_id] = _zone_time.get(WorldManager.current_zone_id, 0.0) + delta


## Enable playtest tracking mode.
func enable_playtest_mode() -> void:
	_playtest_active = true
	_log_playtest_event("session_started", {
		"timestamp": Time.get_unix_time_from_system(),
	})


## Log a playtest event.
func _log_playtest_event(event_type: String, data: Dictionary) -> void:
	var entry := {
		"type": event_type,
		"time": _total_play_time,
		"data": data,
	}
	_playtest_log.append(entry)
	if _playtest_log.size() > MAX_PLAYTEST_LOG:
		_playtest_log.pop_front()
	playtest_event.emit(event_type, data)


## Record unexpected player behavior (for playtest analysis).
func record_unexpected_behavior(behavior: String, context: Dictionary = {}) -> void:
	_unexpected_behaviors.append({
		"behavior": behavior,
		"time": _total_play_time,
		"context": context,
		"forces": {
			"faith": GameState.faith,
			"truth": GameState.truth,
			"violence": GameState.violence,
		},
	})
	_log_playtest_event("unexpected_behavior", {"behavior": behavior, "context": context})


## Get full session report for playtest analysis.
func get_session_report() -> Dictionary:
	return {
		"total_play_time": _total_play_time,
		"zone_time": _zone_time.duplicate(),
		"system_discovery_order": _system_discovery_order.duplicate(),
		"first_death_time": _first_death_time,
		"first_save_time": _first_save_time,
		"first_god_encounter_time": _first_god_encounter_time,
		"endings_reached": _endings_reached.duplicate(),
		"quests": {
			"accepted": _quests_accepted,
			"completed": _quests_completed,
			"ignored": _quests_ignored,
			"failed": _quests_failed,
		},
		"force_totals": _total_force_gains.duplicate(),
		"final_forces": {
			"faith": GameState.faith,
			"truth": GameState.truth,
			"violence": GameState.violence,
		},
		"npc_interactions": _npc_interactions,
		"shrine_uses": _shrine_uses,
		"combat_encounters": _combat_encounters,
		"deaths": _deaths,
		"unexpected_behaviors": _unexpected_behaviors.duplicate(true),
		"dominant_force": GameState.get_dominant_force(),
		"world_pressure": GameState.world_pressure,
		"god_states": _get_god_states(),
		"playtest_log_size": _playtest_log.size(),
	}


func _get_god_states() -> Dictionary:
	var states := {}
	for god_id in GodManager.god_defs:
		states[god_id] = {
			"state": GodManager.get_god_state(god_id),
			"stability": GameState.get_god_stability(god_id),
			"attention": GodManager.get_god_attention(god_id),
		}
	return states


## Record system discovery.
func record_system_discovery(system_name: String) -> void:
	if system_name not in _system_discovery_order:
		_system_discovery_order.append(system_name)
		_log_playtest_event("system_discovered", {"system": system_name, "order": _system_discovery_order.size()})


## Record player death.
func record_death() -> void:
	_deaths += 1
	if _first_death_time < 0:
		_first_death_time = _total_play_time
	_log_playtest_event("player_death", {"death_number": _deaths})


## Record first save.
func record_save() -> void:
	if _first_save_time < 0:
		_first_save_time = _total_play_time
	_log_playtest_event("save", {})


## Record god encounter.
func record_god_encounter(god_id: String) -> void:
	if _first_god_encounter_time < 0:
		_first_god_encounter_time = _total_play_time
	_log_playtest_event("god_encounter", {"god_id": god_id})


## Record NPC interaction.
func record_npc_interaction(npc_id: String) -> void:
	_npc_interactions += 1
	_log_playtest_event("npc_interaction", {"npc_id": npc_id})


## Record shrine use.
func record_shrine_use(force: String) -> void:
	_shrine_uses += 1
	_log_playtest_event("shrine_use", {"force": force})


# --- O3: Final Question ---
# "If I stopped explaining this game entirely... would it still haunt someone?"
# This isn't code. It's a design checkpoint. But we can measure proxies.

## Calculate a "haunt score" — how likely is the game to stick with a player?
## Based on: unexplained events witnessed, systems discovered without help,
## emotional combat moments, trust betrayals experienced, god encounters.
func calculate_haunt_score() -> Dictionary:
	var score := 0.0
	var factors := {}

	# Unexplained events (WorldMemory flags that contain "env_edit" or "audio_lie")
	var unexplained := 0
	for flag in WorldMemory.get_all_flags():
		if "env_edit" in str(flag) or "audio_lie" in str(flag) or "phantom" in str(flag):
			unexplained += 1
	factors["unexplained_events"] = unexplained
	score += minf(unexplained * 2.0, 20.0)

	# Trust betrayals
	var betrayals := 0
	for flag in WorldMemory.get_all_flags():
		if "betrayal" in str(flag) or "lied" in str(flag) or "false" in str(flag):
			betrayals += 1
	factors["trust_betrayals"] = betrayals
	score += minf(betrayals * 5.0, 20.0)

	# God encounters depth
	var god_depth := 0
	for flag in WorldMemory.get_all_flags():
		if "god_obsession" in str(flag) or "obsession_invasion" in str(flag):
			god_depth += 1
	factors["god_encounter_depth"] = god_depth
	score += minf(god_depth * 3.0, 15.0)

	# Systems discovered organically (without explicit prompts)
	factors["systems_discovered"] = _system_discovery_order.size()
	score += minf(_system_discovery_order.size() * 2.0, 15.0)

	# Emotional combat moments
	var emotional_moments := 0
	for flag in WorldMemory.get_all_flags():
		if "combat_mood" in str(flag) or "miracle" in str(flag) or "misfire" in str(flag):
			emotional_moments += 1
	factors["emotional_combat"] = emotional_moments
	score += minf(emotional_moments * 2.0, 10.0)

	# Witness mode depth
	if WorldMemory.has_memory("witness_mode_entered"):
		score += 10.0
		factors["witnessed_ending"] = true
	else:
		factors["witnessed_ending"] = false

	# NPC death impact
	var npc_deaths := 0
	for flag in WorldMemory.get_all_flags():
		if "npc_killed" in str(flag):
			npc_deaths += 1
	factors["npc_deaths"] = npc_deaths
	score += minf(npc_deaths * 4.0, 10.0)

	factors["total_score"] = score
	factors["verdict"] = _get_haunt_verdict(score)

	return factors


func _get_haunt_verdict(score: float) -> String:
	if score >= 80.0:
		return "This game will haunt someone."
	elif score >= 60.0:
		return "This game will linger. Most players will remember it."
	elif score >= 40.0:
		return "This game has moments. Needs more unexplained presence."
	elif score >= 20.0:
		return "The systems work but the mystery is thin. Go back to Phase I or J."
	else:
		return "Not enough. The game is explainable. That's the problem."


# --- Signal Callbacks ---

func _on_force_changed(force_name: String, old_value: float, new_value: float) -> void:
	if new_value > old_value:
		_total_force_gains[force_name] = _total_force_gains.get(force_name, 0.0) + (new_value - old_value)


func _on_quest_accepted(_quest_id: String) -> void:
	_quests_accepted += 1


func _on_quest_completed(_quest_id: String) -> void:
	_quests_completed += 1


func _on_quest_failed(_quest_id: String) -> void:
	_quests_failed += 1


func _on_ending_reached(ending_type: String, _desc: String) -> void:
	_endings_reached.append(ending_type)
	_log_playtest_event("ending_reached", {"type": ending_type})


func _on_zone_loaded(zone_id: String) -> void:
	_log_playtest_event("zone_loaded", {"zone": zone_id})
