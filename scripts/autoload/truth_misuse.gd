## TruthMisuse — Truth can still be used wrongly.
## Tracks when the player receives true info from the Keeper, applies it without context,
## and the outcome is disastrous despite the truth being correct.
##
## "Truth doesn't absolve you from understanding."
##
## This reinforces epistemic responsibility: knowing a fact is not the same as
## understanding how to act on it. The Keeper tells truth — but truth misapplied
## can be worse than a lie.
## B3 Extensions — Truth Misuse Social Decay:
##   - NPCs withhold context after misuse events (not lying, just less helpful)
##   - Player reputation shifts: "liar" → "technically correct but dangerous"
##   - One NPC defends the player using truth — and makes everything worse
extends Node

signal truth_misused(event_id: String, details: Dictionary)
signal misuse_consequence(event_id: String, npc_reaction: String)
signal context_withheld(npc_name: String)
signal reputation_shifted(new_reputation: String)
signal defender_backfire(defender_line: String, consequence: String)

# --- Tracking ---
# When the Keeper shares truth, we snapshot what was revealed.
# When the player acts on that truth (force changes, faction changes),
# we check if the outcome was harmful relative to the context.
var _keeper_revelations: Array[Dictionary] = []
const MAX_REVELATIONS := 10

# Actions taken shortly after Keeper interaction
var _post_keeper_actions: Array[Dictionary] = []
const ACTION_WINDOW := 180.0  # 3 minutes after Keeper visit

# Misuse events
var _misuse_events: Array[Dictionary] = []
const MAX_MISUSE_EVENTS := 15

var _last_keeper_time: float = 0.0

# --- Detection ---
const CHECK_INTERVAL := 30.0
var _check_timer: float = 0.0

# --- B3: Context Withholding ---
# After misuse events, NPCs give less context. Not lying — just... less.
# context_withholding_level: 0.0 = full context, 1.0 = minimal context
var context_withholding_level: float = 0.0
const WITHHOLDING_PER_MISUSE := 0.15   # Each misuse increases withholding
const WITHHOLDING_DECAY_RATE := 0.001  # Very slow decay per tick
const WITHHOLDING_MAX := 0.8           # Never fully silent — that's the Keeper's domain

# --- B3: Reputation System ---
# Not binary "trusted/untrusted" — a spectrum of how NPCs perceive truth usage.
var misuse_reputation: String = "unknown"  # "unknown", "careless", "dangerous", "weaponized"
const REPUTATION_THRESHOLDS := {
	"careless": 2,      # After 2 misuse events
	"dangerous": 5,     # After 5 misuse events
	"weaponized": 10,   # After 10 misuse events
}

# NPC lines for each reputation level — these are what they SAY about you
const REPUTATION_LINES := {
	"unknown": [],
	"careless": [
		"You know things. You just don't know what they mean yet.",
		"Careful with what you've learned. It cuts both ways.",
	],
	"dangerous": [
		"You're technically correct. That's the most dangerous kind of correct.",
		"The truth in your hands is a weapon you don't know how to hold.",
		"You're not wrong. That's what makes you dangerous.",
		"Knowing the truth and understanding it are different skills. You have one.",
	],
	"weaponized": [
		"Don't tell me what you know. I've seen what happens when you share.",
		"The last person you 'helped' with the truth is still paying for it.",
		"You speak truth like it's a hammer. Everything looks like a nail to you.",
	],
}

# --- B3: The Defender ---
# One NPC archetype who defends the player's truth usage — and makes it worse.
# Their defense validates the player but escalates NPC distrust.
const DEFENDER_LINES := [
	"They're not wrong, you know. Everything they said was accurate.",
	"I checked. What they told us was true. Every word.",
	"You blame them for knowing? For TELLING you?",
	"The truth they shared saved lives. That it also cost lives isn't their fault.",
	"At least someone is willing to say what's real. Even if it hurts.",
]
const DEFENDER_CONSEQUENCES := [
	"The defense lands badly. Other NPCs trust the player less, not more.",
	"The defender's insistence makes others suspicious of BOTH of them.",
	"Being defended makes the player look like they NEED defending.",
	"The truth of the defense makes the damage feel more intentional.",
	"Other NPCs now avoid the defender too.",
]
var _defender_active: bool = false
var _defender_event_count: int = 0


func _ready() -> void:
	AnchorManager.anchor_spoke.connect(_on_keeper_spoke)
	GameState.force_changed.connect(_on_force_changed)
	FactionManager.faction_attitude_changed.connect(_on_faction_changed)


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	if GameState.witness_mode:
		return

	_evaluate_misuse()


## Snapshot world state when Keeper speaks.
func _on_keeper_spoke(topic: String) -> void:
	_last_keeper_time = Time.get_unix_time_from_system()

	var revelation := {
		"topic": topic,
		"timestamp": _last_keeper_time,
		"faith": GameState.faith,
		"truth": GameState.truth,
		"violence": GameState.violence,
		"pressure": GameState.world_pressure,
		"god_states": {},
		"faction_attitudes": {},
	}

	for god_id in GodManager.god_defs:
		revelation["god_states"][god_id] = GodManager.get_god_state(god_id)

	for fid in FactionManager.faction_defs:
		revelation["faction_attitudes"][fid] = FactionManager.get_attitude(fid)

	_keeper_revelations.append(revelation)
	if _keeper_revelations.size() > MAX_REVELATIONS:
		_keeper_revelations.pop_front()

	_post_keeper_actions.clear()


## Track force changes as potential truth-informed actions.
func _on_force_changed(force_name: String, old_value: float, new_value: float) -> void:
	var now := Time.get_unix_time_from_system()
	if now - _last_keeper_time > ACTION_WINDOW:
		return
	if _last_keeper_time <= 0.0:
		return

	_post_keeper_actions.append({
		"type": "force_change",
		"force": force_name,
		"old": old_value,
		"new": new_value,
		"delta": new_value - old_value,
		"timestamp": now,
	})


## Track faction changes as potential truth-informed outcomes.
func _on_faction_changed(faction_id: String, old_attitude: String, new_attitude: String) -> void:
	var now := Time.get_unix_time_from_system()
	if now - _last_keeper_time > ACTION_WINDOW:
		return
	if _last_keeper_time <= 0.0:
		return

	_post_keeper_actions.append({
		"type": "faction_change",
		"faction": faction_id,
		"old": old_attitude,
		"new": new_attitude,
		"timestamp": now,
	})


## Evaluate whether recent actions after Keeper interaction resulted in harm.
func _evaluate_misuse() -> void:
	if _keeper_revelations.is_empty() or _post_keeper_actions.is_empty():
		return

	var latest_revelation: Dictionary = _keeper_revelations[_keeper_revelations.size() - 1]
	var now := Time.get_unix_time_from_system()
	var revelation_age: float = now - latest_revelation.get("timestamp", 0.0)

	# Only evaluate after the action window closes
	if revelation_age < ACTION_WINDOW:
		return

	# Check for harmful outcomes
	for action in _post_keeper_actions:
		match action.get("type", ""):
			"force_change":
				_check_force_misuse(action, latest_revelation)
			"faction_change":
				_check_faction_misuse(action, latest_revelation)

	# B3: Update context withholding and reputation after each evaluation
	_update_social_decay()

	_post_keeper_actions.clear()


## Check if a force change after Keeper visit led to harmful escalation.
func _check_force_misuse(action: Dictionary, revelation: Dictionary) -> void:
	var force_name: String = action.get("force", "")
	var delta: float = action.get("delta", 0.0)

	# Misuse: player pushed a force that was already near critical
	var original: float = revelation.get(force_name, 0.0)
	if original >= 70.0 and delta > 0.0:
		# Player knew the force was high (Keeper told them) and pushed higher
		if GameState.world_pressure > revelation.get("pressure", 0.0) + 10.0:
			_record_misuse("force_escalation", {
				"force": force_name,
				"original": original,
				"pushed_to": GameState.get_force(force_name),
				"pressure_increase": GameState.world_pressure - revelation.get("pressure", 0.0),
			})

	# Misuse: player ignored a force imbalance the Keeper revealed
	var pressure_diff: float = GameState.world_pressure - revelation.get("pressure", 0.0)
	if pressure_diff > 15.0:
		_record_misuse("pressure_ignored", {
			"force": force_name,
			"pressure_increase": pressure_diff,
		})


## Check if a faction attitude shift was a consequence of misapplied truth.
func _check_faction_misuse(action: Dictionary, _revelation: Dictionary) -> void:
	var new_attitude: String = action.get("new", "")
	var old_attitude: String = action.get("old", "")

	# Misuse: faction went hostile after player acted on Keeper info
	if new_attitude == "hostile" and old_attitude != "hostile":
		_record_misuse("faction_hostile", {
			"faction": action.get("faction", ""),
			"old_attitude": old_attitude,
		})


## Record a truth misuse event.
func _record_misuse(event_type: String, details: Dictionary) -> void:
	var event_id := "misuse_%s_%d" % [event_type, _misuse_events.size()]
	var event := {
		"id": event_id,
		"type": event_type,
		"details": details,
		"timestamp": Time.get_unix_time_from_system(),
	}

	_misuse_events.append(event)
	if _misuse_events.size() > MAX_MISUSE_EVENTS:
		_misuse_events.pop_front()

	truth_misused.emit(event_id, details)
	WorldMemory.record("truth_misuse_%s" % event_type)
	WorldMemory.record_ambient("Truth was known but applied without understanding")

	# Generate NPC reaction
	var reactions := [
		"Truth doesn't absolve you from understanding.",
		"You knew what was true. You didn't know what it meant.",
		"The Keeper told you honestly. What you did with it was yours.",
		"Knowing the shape of fire doesn't prevent the burn.",
	]
	var reaction: String = reactions[randi() % reactions.size()]
	misuse_consequence.emit(event_id, reaction)


# --- B3: Social Decay ---

## Update withholding level and reputation based on accumulated misuse.
func _update_social_decay() -> void:
	# Context withholding scales with misuse count
	var target := clampf(_misuse_events.size() * WITHHOLDING_PER_MISUSE, 0.0, WITHHOLDING_MAX)
	context_withholding_level = lerpf(context_withholding_level, target, 0.1)

	# Reputation shifts
	var old_rep := misuse_reputation
	var count := _misuse_events.size()
	if count >= REPUTATION_THRESHOLDS["weaponized"]:
		misuse_reputation = "weaponized"
	elif count >= REPUTATION_THRESHOLDS["dangerous"]:
		misuse_reputation = "dangerous"
	elif count >= REPUTATION_THRESHOLDS["careless"]:
		misuse_reputation = "careless"
	else:
		misuse_reputation = "unknown"

	if old_rep != misuse_reputation:
		reputation_shifted.emit(misuse_reputation)

	# Withholding natural decay (very slow)
	context_withholding_level = maxf(context_withholding_level - WITHHOLDING_DECAY_RATE, 0.0)


## B3: Should an NPC withhold context from the player?
## Returns true if the NPC should give less detail than normal.
func should_withhold_context() -> bool:
	return randf() < context_withholding_level


## B3: Get a reputation-aware NPC line about the player.
func get_reputation_line() -> String:
	var lines: Array = REPUTATION_LINES.get(misuse_reputation, [])
	if lines.is_empty():
		return ""
	return lines[randi() % lines.size()]


## B3: Trigger the defender NPC event.
## One NPC defends the player using truth — and makes things worse.
## Returns the defender's line and the consequence description.
func trigger_defender_event() -> Dictionary:
	if _misuse_events.size() < 3:
		return {}  # Need at least 3 misuse events before defender appears

	_defender_active = true
	_defender_event_count += 1

	var line: String = DEFENDER_LINES[randi() % DEFENDER_LINES.size()]
	var consequence: String = DEFENDER_CONSEQUENCES[randi() % DEFENDER_CONSEQUENCES.size()]

	# The defense INCREASES withholding — the opposite of what the defender intended
	context_withholding_level = clampf(context_withholding_level + 0.1, 0.0, WITHHOLDING_MAX)

	defender_backfire.emit(line, consequence)
	return {"line": line, "consequence": consequence}


## B3: Has the defender been triggered?
func is_defender_active() -> bool:
	return _defender_active


## Get NPC dialogue referencing truth misuse (for npc_base integration).
## Now reputation-aware (B3): lines change based on accumulated misuse.
func get_misuse_reference() -> String:
	if _misuse_events.is_empty():
		return ""
	# Prefer reputation-specific lines when available
	var rep_line := get_reputation_line()
	if rep_line != "":
		return rep_line
	var references := [
		"You knew the truth and still chose wrong. That's worse than ignorance.",
		"The Keeper's words were honest. Your interpretation was not.",
		"Knowledge without wisdom. I've seen it before.",
	]
	return references[randi() % references.size()]


## Get total misuse events.
func get_total_misuse() -> int:
	return _misuse_events.size()


## Has truth been misused? (For NPC dialogue gating.)
func has_misuse_history() -> bool:
	return _misuse_events.size() > 0


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"total_misuse": _misuse_events.size(),
		"pending_actions": _post_keeper_actions.size(),
		"revelations": _keeper_revelations.size(),
		"events": _misuse_events.duplicate(),
		"context_withholding": context_withholding_level,
		"reputation": misuse_reputation,
		"defender_active": _defender_active,
		"defender_events": _defender_event_count,
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"misuse_events": _misuse_events.duplicate(),
		"context_withholding": context_withholding_level,
		"reputation": misuse_reputation,
		"defender_event_count": _defender_event_count,
	}


func load_state(data: Dictionary) -> void:
	var loaded = data.get("misuse_events", [])
	_misuse_events.clear()
	for event in loaded:
		_misuse_events.append(event)
	context_withholding_level = data.get("context_withholding", 0.0)
	misuse_reputation = data.get("reputation", "unknown")
	_defender_event_count = data.get("defender_event_count", 0)
