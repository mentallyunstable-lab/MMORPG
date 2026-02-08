## KeeperOverreliance — Detects when the player is treating the Keeper as a debug console.
## Tracks an anchor_dependency_score based on decision patterns relative to Keeper interactions.
## Response is PURELY PSYCHOLOGICAL — no mechanical punishment.
##
## Threshold tiers:
##   LOW (0-30):    No response. Player is using Keeper normally.
##   MEDIUM (30-60): Keeper becomes briefer. Less volunteered info.
##   HIGH (60+):    Keeper warns the player explicitly. Dialogue shifts tone.
##
## A2 Extensions:
##   - Pre-emptive NPC doubt: NPCs question player agency at high dependency
##   - Keeper-before-attempt detection: dependency rises faster if player asks Keeper
##     before trying other dialogue sources
##   - Empathy word stripping: Keeper loses warmth before losing information
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

# --- A2: Pre-emptive Seeking Detection ---
# Tracks if player talks to Keeper BEFORE attempting other NPCs.
# If this pattern repeats, dependency rises faster.
var _last_npc_dialogue_time: float = 0.0  # Last time player talked to a non-Keeper NPC
var _keeper_before_attempt_count: int = 0  # Times Keeper was consulted before any NPC
const KEEPER_FIRST_PENALTY := 1.5  # Dependency multiplier when Keeper is always first

# --- A2: Empathy Erosion ---
# Keeper dialogue loses empathy words before losing information.
# This tracks the erosion level (0.0 = warm, 1.0 = clinical).
var empathy_erosion: float = 0.0

# --- A2: NPC Agency Doubt ---
# At medium+ dependency, NPCs begin questioning player autonomy.
const NPC_DOUBT_LINES := [
	"Did you decide that, or did someone tell you?",
	"You sound certain. Whose certainty is it?",
	"That's not your voice. That's something you were told.",
	"You came here already knowing what to say. Who told you?",
	"I can hear the Keeper in your words. Where are YOUR words?",
	"Strange — you speak like someone who already has the answer.",
]


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
	var now := Time.get_unix_time_from_system()
	_last_keeper_visit_time = now

	# Snapshot what the Keeper told the player
	_last_keeper_info = {
		"faith": GameState.faith,
		"truth": GameState.truth,
		"violence": GameState.violence,
		"dominant": GameState.get_dominant_force(),
		"timestamp": _last_keeper_visit_time,
	}

	# --- A2: Keeper-before-attempt detection ---
	# If player hasn't talked to any NPC since last Keeper visit, they're seeking
	# Keeper first. This accelerates dependency.
	if _last_npc_dialogue_time < _last_keeper_visit_time - DECISION_WINDOW:
		_keeper_before_attempt_count += 1

	# Check for contradictory return pattern:
	# Player comes back, world hasn't changed much, but they still need reassurance
	if topic == "world_state" and _total_decisions == 0:
		# Returned without making any decisions since last visit
		_contradictory_returns += 1


## Track dialogue ending — also used to track non-Keeper NPC interaction.
func _on_dialogue_ended() -> void:
	# Track when player talks to anyone other than the Keeper
	if DialogueManager.current_speaker != "The Keeper" and DialogueManager.current_speaker != "":
		_last_npc_dialogue_time = Time.get_unix_time_from_system()


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

	# --- A2: Factor 4: Keeper-before-attempt penalty ---
	# If player consistently consults Keeper before trying other NPCs,
	# dependency rises faster.
	var keeper_first_mult := 1.0
	if _keeper_before_attempt_count > 3:
		keeper_first_mult = KEEPER_FIRST_PENALTY

	# Weighted sum
	anchor_dependency_score = clampf(
		(decision_ratio * 50.0 + return_pressure + visit_pressure) * keeper_first_mult,
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

	# --- A2: Empathy erosion ---
	# Keeper loses warmth before losing information.
	# Erosion tracks with dependency but leads it slightly.
	empathy_erosion = clampf(anchor_dependency_score / 80.0, 0.0, 1.0)


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


## A2: Should an NPC pre-emptively doubt the player's agency?
## Returns a doubt line, or empty string if no doubt should occur.
func get_npc_agency_doubt() -> String:
	if DevToggles.disable_psychological_hooks:
		return ""
	if _current_tier == "low":
		return ""
	# Medium: 15% chance. High: 35% chance.
	var doubt_chance := 0.15 if _current_tier == "medium" else 0.35
	if randf() >= doubt_chance:
		return ""
	return NPC_DOUBT_LINES[randi() % NPC_DOUBT_LINES.size()]


## A2: Strip empathy words from Keeper dialogue.
## Returns the text with warmth removed at high erosion levels.
## Empathy goes first, information stays.
func strip_empathy(text: String) -> String:
	if empathy_erosion < 0.3:
		return text
	# Progressive stripping: soft words first, then qualifiers
	var result := text
	if empathy_erosion >= 0.3:
		# Remove hedging and softeners
		result = result.replace("I think ", "")
		result = result.replace("Perhaps ", "")
		result = result.replace("It seems ", "")
		result = result.replace("I believe ", "")
	if empathy_erosion >= 0.5:
		# Remove emotional acknowledgment
		result = result.replace("I understand.", "")
		result = result.replace("I see.", "")
		result = result.replace("That is hard.", "")
		result = result.replace("That must be difficult.", "")
	if empathy_erosion >= 0.7:
		# Remove all courtesy
		result = result.replace("Be careful.", "")
		result = result.replace("Take care.", "")
		result = result.replace("I am sorry.", "")
		result = result.replace("I wish I could help more.", "")
	return result.strip_edges()


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"dependency_score": anchor_dependency_score,
		"tier": _current_tier,
		"brevity": brevity_level,
		"empathy_erosion": empathy_erosion,
		"keeper_before_attempt": _keeper_before_attempt_count,
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
