## BetrayalPacing — Horror needs rhythm. This provides it.
## Controls the tempo of betrayals so the game doesn't degenerate into noise.
##
## Hard rule: Only ONE core system betrayal per cooldown window.
## Soft rule: Audio lies do not overlap save lies. God interference doesn't stack with NPC lies.
## The anchor's truthfulness is more powerful when lies are spaced, not constant.
##
## Betrayal categories:
##   dialogue_lie    — NPC says something false about world state
##   env_misdirect   — Interactable gives wrong feedback (shrine, item)
##   quest_corruption — Quest description mutates subtly
##   god_interference — God warps forces, UI, or environment
##   audio_phantom    — Sound cue for something that isn't there
##   save_corruption  — Save feedback lies (says saved, didn't / says failed, did)
extends Node

signal betrayal_occurred(betrayal_type: String, timestamp: float)
signal cooldown_started(duration: float)

# --- Global Cooldown ---
# After any core betrayal, no other core betrayal can fire for this duration.
const GLOBAL_COOLDOWN_BASE := 90.0  # seconds
const GLOBAL_COOLDOWN_MIN := 45.0   # minimum even at high pressure
const GLOBAL_COOLDOWN_MAX := 180.0  # maximum at low pressure

var _global_cooldown_remaining: float = 0.0
var _last_betrayal_type: String = ""
var _last_betrayal_time: float = 0.0

# --- Per-Category Cooldowns ---
# Some betrayal types have their own additional cooldowns.
var _category_cooldowns: Dictionary = {
	"dialogue_lie": 0.0,
	"env_misdirect": 0.0,
	"quest_corruption": 0.0,
	"god_interference": 0.0,
	"audio_phantom": 0.0,
	"save_corruption": 0.0,
}

const CATEGORY_COOLDOWN_DEFAULTS := {
	"dialogue_lie": 60.0,
	"env_misdirect": 120.0,
	"quest_corruption": 300.0,   # Quest lies are rare and devastating
	"god_interference": 30.0,    # Gods are more active, shorter cooldown
	"audio_phantom": 45.0,
	"save_corruption": 600.0,    # Save lies are EXTREMELY rare
}

# --- Overlap Prevention (Soft Rules) ---
# These pairs cannot fire within OVERLAP_WINDOW seconds of each other.
const OVERLAP_WINDOW := 20.0
const CONFLICTING_PAIRS := [
	["audio_phantom", "save_corruption"],
	["dialogue_lie", "god_interference"],
	["env_misdirect", "quest_corruption"],
]

# --- History (for debug overlay) ---
var _betrayal_history: Array = []  # [{type, timestamp}]
const MAX_HISTORY := 30


func _process(delta: float) -> void:
	# Tick down global cooldown
	if _global_cooldown_remaining > 0:
		_global_cooldown_remaining -= delta

	# Tick down category cooldowns
	for cat in _category_cooldowns:
		if _category_cooldowns[cat] > 0:
			_category_cooldowns[cat] -= delta


## Core API: Can a betrayal of this type fire right now?
## Called by TrustDestruction, GodManager, AudioManager, etc.
func can_betray(betrayal_type: String) -> bool:
	# Global cooldown active — no betrayals allowed
	if _global_cooldown_remaining > 0:
		return false

	# Category-specific cooldown
	if _category_cooldowns.get(betrayal_type, 0.0) > 0:
		return false

	# Overlap check — would this conflict with a recent betrayal?
	if _would_overlap(betrayal_type):
		return false

	# Witness mode — no betrayals in the dead world
	if GameState.witness_mode:
		return false

	return true


## Record that a betrayal occurred. Starts cooldowns.
func record_betrayal(betrayal_type: String) -> void:
	var now := Time.get_unix_time_from_system()

	_last_betrayal_type = betrayal_type
	_last_betrayal_time = now

	# Start global cooldown (scales with world pressure — more pressure = shorter cooldowns)
	var pressure_factor := clampf(GameState.world_pressure / 100.0, 0.0, 1.0)
	var cooldown := lerpf(GLOBAL_COOLDOWN_MAX, GLOBAL_COOLDOWN_MIN, pressure_factor)
	_global_cooldown_remaining = cooldown
	cooldown_started.emit(cooldown)

	# Start category cooldown
	var cat_cooldown: float = CATEGORY_COOLDOWN_DEFAULTS.get(betrayal_type, 60.0)
	_category_cooldowns[betrayal_type] = cat_cooldown

	# Record in history
	_betrayal_history.append({"type": betrayal_type, "timestamp": now})
	if _betrayal_history.size() > MAX_HISTORY:
		_betrayal_history.pop_front()

	betrayal_occurred.emit(betrayal_type, now)


## Check overlap rules — would this betrayal type conflict with a recent one?
func _would_overlap(betrayal_type: String) -> bool:
	if _betrayal_history.is_empty():
		return false

	var now := Time.get_unix_time_from_system()
	var recent_cutoff := now - OVERLAP_WINDOW

	for pair in CONFLICTING_PAIRS:
		if betrayal_type in pair:
			var partner: String = pair[0] if pair[1] == betrayal_type else pair[1]
			# Check if partner fired recently
			for entry in _betrayal_history:
				if entry["type"] == partner and entry["timestamp"] > recent_cutoff:
					return true

	return false


# --- Debug API ---

## Get debug info for overlay display.
func get_debug_info() -> Dictionary:
	return {
		"global_cooldown": maxf(_global_cooldown_remaining, 0.0),
		"last_betrayal_type": _last_betrayal_type,
		"last_betrayal_time": _last_betrayal_time,
		"next_allowed_in": maxf(_global_cooldown_remaining, 0.0),
		"category_cooldowns": _category_cooldowns.duplicate(),
		"total_betrayals": _betrayal_history.size(),
		"history": _betrayal_history.duplicate(),
	}


## Get time until next betrayal is possible.
func get_time_until_available() -> float:
	return maxf(_global_cooldown_remaining, 0.0)


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"global_cooldown": _global_cooldown_remaining,
		"last_betrayal_type": _last_betrayal_type,
		"category_cooldowns": _category_cooldowns.duplicate(),
		"history": _betrayal_history.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	_global_cooldown_remaining = data.get("global_cooldown", 0.0)
	_last_betrayal_type = data.get("last_betrayal_type", "")
	_category_cooldowns = data.get("category_cooldowns", _category_cooldowns)
	var loaded_history = data.get("history", [])
	_betrayal_history.clear()
	for entry in loaded_history:
		_betrayal_history.append(entry)
