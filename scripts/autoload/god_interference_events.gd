## GodInterferenceEvents — Failed god interference near the Keeper.
## When gods attempt manipulation near the anchor:
##   - World trembles (audio, animation, NPC reactions)
##   - Effect FAILS, but leaves residue
##   - Logged: god name, attempted action, failure reason
##
## These events are RARE. Extremely rare.
## The player should feel pressure from divine attention, not safety from the Keeper.
## The Keeper resists — that costs something. The player should sense the strain.
extends Node

signal interference_attempted(god_id: String, action: String)
signal interference_failed(god_id: String, action: String, reason: String)
signal residue_applied(god_id: String, residue_type: String)

# --- Configuration ---
const CHECK_INTERVAL := 15.0
var _check_timer: float = 0.0

# Base probability of an interference attempt when a god is obsessed and Keeper is present.
# This should be VERY low. These are rare, dramatic moments.
const BASE_ATTEMPT_CHANCE := 0.03  # 3% per check when conditions are met
const ATTEMPT_COOLDOWN := 300.0    # Minimum 5 minutes between attempts
var _last_attempt_time: float = -999.0

# --- Event Log ---
var _interference_log: Array[Dictionary] = []
const MAX_LOG := 10

# --- Residue Types ---
# Failed interference leaves traces. Not full effects, just echoes.
# These are cosmetic/atmospheric, not mechanical.
const RESIDUE_TYPES := {
	"verath": "decay_residue",      # Faint rot smell, brief visual distortion
	"kael": "light_residue",        # Flash of blinding light, brief blindness
	"null_throne": "void_residue",  # Brief silence, shadow flicker
}


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	if GameState.witness_mode:
		return

	_check_for_interference_attempts()


## Check if any god should attempt interference near the Keeper.
func _check_for_interference_attempts() -> void:
	# Only when Keeper is present (not silent, not absent)
	if not AnchorManager.is_anchor_available():
		return

	var now := Time.get_unix_time_from_system()
	if now - _last_attempt_time < ATTEMPT_COOLDOWN:
		return

	# Phase gate: only mid+ game
	var phase_gate := GodManager.get_phase_gate(0.0, 0.3, 1.0)
	if phase_gate <= 0.0:
		return

	# Check each god
	for god_id in GodManager.god_defs:
		var attention := GodManager.get_god_attention(god_id)
		var state := GodManager.get_god_state(god_id)

		if state == "dead":
			continue

		# Gods must be at least watching (60+) and preferably obsessed (90+)
		if attention < GodManager.ATTENTION_WATCHING:
			continue

		# Higher attention = higher attempt chance, but still rare
		var attention_mult := clampf((attention - GodManager.ATTENTION_WATCHING) / 40.0, 0.0, 1.0)
		var attempt_chance := BASE_ATTEMPT_CHANCE * phase_gate * attention_mult

		if randf() < attempt_chance:
			_execute_failed_interference(god_id)
			_last_attempt_time = now
			return  # Only one attempt per check cycle


## Execute a failed interference event.
func _execute_failed_interference(god_id: String) -> void:
	var god_name := GodManager.get_god_name(god_id)
	var action := _get_attempted_action(god_id)
	var reason := _get_failure_reason(god_id)

	interference_attempted.emit(god_id, action)

	# The attempt FAILS near the Keeper
	interference_failed.emit(god_id, action, reason)

	# World trembles — NPC reactions, visual/audio cues
	_emit_tremble_effects(god_id, god_name, action)

	# Leave residue — not the full effect, just a trace
	_apply_residue(god_id)

	# Log the event
	var log_entry := {
		"god_id": god_id,
		"god_name": god_name,
		"action": action,
		"reason": reason,
		"timestamp": Time.get_unix_time_from_system(),
	}
	_interference_log.append(log_entry)
	if _interference_log.size() > MAX_LOG:
		_interference_log.pop_front()

	WorldMemory.record("god_interference_failed_%s_%d" % [god_id, _interference_log.size()])
	WorldMemory.record_ambient("%s tried to reach through. The Keeper held." % god_name)


## Get what the god was trying to do.
func _get_attempted_action(god_id: String) -> String:
	match god_id:
		"verath":
			var actions := [
				"corrupt_truth",      # Tried to rot the Keeper's words
				"cycle_force",        # Tried to reset force values
				"decay_environment",  # Tried to destabilize the zone
			]
			return actions[randi() % actions.size()]
		"kael":
			var actions := [
				"expose_player",     # Tried to reveal player's secrets
				"judge_worthy",      # Tried to force a judgment event
				"burn_uncertainty",  # Tried to eliminate ambiguity forcefully
			]
			return actions[randi() % actions.size()]
		"null_throne":
			var actions := [
				"erase_memory",      # Tried to remove a world memory
				"silence_keeper",    # Tried to force the Keeper silent
				"void_zone",         # Tried to create a dead zone
			]
			return actions[randi() % actions.size()]
	return "warp_reality"


## Get why the interference failed.
func _get_failure_reason(god_id: String) -> String:
	var reasons := [
		"The anchor holds. Truth cannot be warped here.",
		"The Keeper's presence repels divine manipulation.",
		"This ground resists. Something older than gods protects it.",
		"The interference scatters like ash against stone.",
	]
	return reasons[randi() % reasons.size()]


## Emit world tremble effects — visual, audio, NPC reactions.
func _emit_tremble_effects(god_id: String, god_name: String, action: String) -> void:
	# Notification to player — they feel something happen and fail
	match god_id:
		"verath":
			WorldEventManager.event_notification.emit(
				"TREMOR", "The ground softens — then hardens. Something tried to take root here and couldn't.")
		"kael":
			WorldEventManager.event_notification.emit(
				"FLASH", "Light slashes across your vision. It recoils. The Keeper stands unchanged.")
		"null_throne":
			WorldEventManager.event_notification.emit(
				"VOID PULSE", "Silence crashes against you like a wave — then recedes. Something was denied entry.")
		_:
			WorldEventManager.event_notification.emit(
				"DIVINE TREMOR", "%s reaches for this place. It fails." % god_name)

	# Brief atmospheric disturbance
	ForceEffects.trigger_silence(1.5, 0.6)


## Apply residue — failed effect leaves traces.
func _apply_residue(god_id: String) -> void:
	var residue_type: String = RESIDUE_TYPES.get(god_id, "generic_residue")
	residue_applied.emit(god_id, residue_type)

	# Minimal mechanical residue — just a tiny force nudge
	# The god's domain bleeds through slightly despite failure
	match god_id:
		"verath":
			# Faint decay — corruption increases slightly in current zone
			for zone_id in GameState.region_state:
				var region: Dictionary = GameState.get_region(zone_id)
				region["corruption"] = minf(region.get("corruption", 0.0) + 1.0, 100.0)
		"kael":
			# Faint truth exposure — tiny truth boost
			GameState.add_force("truth", 0.5)
		"null_throne":
			# Faint void — tiny drain on all forces
			GameState.add_force("faith", -0.3)
			GameState.add_force("truth", -0.3)
			GameState.add_force("violence", -0.3)


## Get the interference log for debug/NPC reference.
func get_interference_log() -> Array[Dictionary]:
	return _interference_log


## Get total failed interferences.
func get_total_failed() -> int:
	return _interference_log.size()


## Has any god failed to interfere near the Keeper?
func has_interference_history() -> bool:
	return _interference_log.size() > 0


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"total_failed": _interference_log.size(),
		"last_attempt_time": _last_attempt_time,
		"log": _interference_log.duplicate(),
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"interference_log": _interference_log.duplicate(),
		"last_attempt_time": _last_attempt_time,
	}


func load_state(data: Dictionary) -> void:
	var loaded_log = data.get("interference_log", [])
	_interference_log.clear()
	for entry in loaded_log:
		_interference_log.append(entry)
	_last_attempt_time = data.get("last_attempt_time", -999.0)
