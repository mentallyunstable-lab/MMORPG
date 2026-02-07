## KeeperOverreliance — Detects when the player is treating the Keeper as a debug console.
## Tracks an anchor_dependency_score based on decision patterns relative to Keeper interactions.
## Response is PURELY PSYCHOLOGICAL — no mechanical punishment.
##
## Threshold tiers:
##   LOW (0-30):    No response. Player is using Keeper normally.
##   MEDIUM (30-60): Keeper becomes briefer. Less volunteered info.
##   HIGH (60+):    Keeper warns the player explicitly. Dialogue shifts tone.
##
## The goal is to make the player FEEL the cost of certainty-seeking
## without ever breaking the Keeper's core promise of truthfulness.
extends Node

signal dependency_changed(old_tier: String, new_tier: String)
signal keeper_brevity_level_changed(level: float)

# --- Dependency Score ---
# 0.0 = fully independent, 100.0 = fully dependent on Keeper
var anchor_dependency_score: float = 0.0

# --- Tracking Data ---
var _total_decisions: int = 0            # All force-changing decisions
var _decisions_after_keeper: int = 0     # Decisions made within window of Keeper visit
var _contradictory_returns: int = 0      # Times player returned after getting contradictory info
var _last_keeper_visit_time: float = 0.0
var _last_keeper_info: Dictionary = {}   # What the Keeper last reported

const DECISION_WINDOW := 120.0  # Seconds after Keeper visit that count as "after Keeper"
const CHECK_INTERVAL := 10.0
var _check_timer: float = 0.0

# --- Tier Thresholds ---
const TIER_LOW_MAX := 30.0
const TIER_MEDIUM_MAX := 60.0
# Above 60 = HIGH

var _current_tier: String = "low"

# --- Keeper Brevity ---
# 0.0 = normal verbosity, 1.0 = maximally brief
var brevity_level: float = 0.0


func _ready() -> void:
	AnchorManager.anchor_spoke.connect(_on_keeper_spoke)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	GameState.force_changed.connect(_on_force_changed)


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL:
		_check_timer = 0.0
		_recalculate_dependency()


## Track when Keeper speaks.
func _on_keeper_spoke(topic: String) -> void:
	_last_keeper_visit_time = Time.get_unix_time_from_system()

	# Snapshot what the Keeper told the player
	_last_keeper_info = {
		"faith": GameState.faith,
		"truth": GameState.truth,
		"violence": GameState.violence,
		"dominant": GameState.get_dominant_force(),
		"timestamp": _last_keeper_visit_time,
	}

	# Check for contradictory return pattern:
	# Player comes back, world hasn't changed much, but they still need reassurance
	if topic == "world_state" and _total_decisions == 0:
		# Returned without making any decisions since last visit
		_contradictory_returns += 1


## Track dialogue ending (proxy for a "decision cycle").
func _on_dialogue_ended() -> void:
	pass  # Decisions are tracked via force changes instead


## Track force-changing decisions as player actions.
func _on_force_changed(_force: String, _old: float, _new: float) -> void:
	if GameState.witness_mode:
		return

	_total_decisions += 1

	var now := Time.get_unix_time_from_system()
	var time_since_keeper := now - _last_keeper_visit_time

	if time_since_keeper < DECISION_WINDOW and _last_keeper_visit_time > 0.0:
		_decisions_after_keeper += 1


## Recalculate the dependency score.
func _recalculate_dependency() -> void:
	var old_score := anchor_dependency_score

	# Factor 1: Percentage of decisions made after Keeper interaction
	var decision_ratio := 0.0
	if _total_decisions > 5:  # Need minimum sample
		decision_ratio = float(_decisions_after_keeper) / float(_total_decisions)

	# Factor 2: Frequency of contradictory returns
	var return_pressure := clampf(_contradictory_returns * 5.0, 0.0, 30.0)

	# Factor 3: Raw visit frequency from KeeperAccessCost
	var visit_pressure := clampf(KeeperAccessCost.keeper_visits_last_hour * 4.0, 0.0, 30.0)

	# Weighted sum
	anchor_dependency_score = clampf(
		decision_ratio * 50.0 + return_pressure + visit_pressure,
		0.0, 100.0
	)

	# Determine tier
	var old_tier := _current_tier
	if anchor_dependency_score <= TIER_LOW_MAX:
		_current_tier = "low"
	elif anchor_dependency_score <= TIER_MEDIUM_MAX:
		_current_tier = "medium"
	else:
		_current_tier = "high"

	if old_tier != _current_tier:
		dependency_changed.emit(old_tier, _current_tier)
		WorldMemory.record("keeper_dependency_%s" % _current_tier)

	# Update brevity level
	var old_brevity := brevity_level
	match _current_tier:
		"low":
			brevity_level = 0.0
		"medium":
			brevity_level = clampf((anchor_dependency_score - TIER_LOW_MAX) / (TIER_MEDIUM_MAX - TIER_LOW_MAX), 0.0, 0.6)
		"high":
			brevity_level = clampf(0.6 + (anchor_dependency_score - TIER_MEDIUM_MAX) / (100.0 - TIER_MEDIUM_MAX) * 0.4, 0.6, 1.0)

	if absf(old_brevity - brevity_level) > 0.01:
		keeper_brevity_level_changed.emit(brevity_level)


## Get the current dependency tier.
func get_dependency_tier() -> String:
	return _current_tier


## Get whether the Keeper should issue an overreliance warning.
func should_warn_player() -> bool:
	return _current_tier == "high"


## Get the warning dialogue line (called by npc_keeper.gd).
func get_warning_dialogue() -> Array:
	var warnings := [
		"You return too often. Certainty rots when leaned on.",
		"I have told you what is. You do not need me to tell you again.",
		"My presence is not a substitute for your judgment.",
		"You seek safety in knowing. But knowing and deciding are not the same.",
		"The world outside is uncertain. That is where your choices live, not here.",
	]
	return [{"speaker": "The Keeper", "text": warnings[randi() % warnings.size()]}]


## Get brevity-modified dialogue (fewer lines at higher dependency).
## Returns the number of detail lines the Keeper should include.
func get_max_detail_lines() -> int:
	if brevity_level <= 0.0:
		return 10  # Full verbosity
	elif brevity_level <= 0.3:
		return 6
	elif brevity_level <= 0.6:
		return 3
	else:
		return 1  # Minimal: just the essential truth


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"dependency_score": anchor_dependency_score,
		"tier": _current_tier,
		"brevity": brevity_level,
		"total_decisions": _total_decisions,
		"decisions_after_keeper": _decisions_after_keeper,
		"contradictory_returns": _contradictory_returns,
		"max_detail_lines": get_max_detail_lines(),
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"dependency_score": anchor_dependency_score,
		"total_decisions": _total_decisions,
		"decisions_after_keeper": _decisions_after_keeper,
		"contradictory_returns": _contradictory_returns,
	}


func load_state(data: Dictionary) -> void:
	anchor_dependency_score = data.get("dependency_score", 0.0)
	_total_decisions = data.get("total_decisions", 0)
	_decisions_after_keeper = data.get("decisions_after_keeper", 0)
	_contradictory_returns = data.get("contradictory_returns", 0)
	_recalculate_dependency()
