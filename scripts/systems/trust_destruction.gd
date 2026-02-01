## TrustDestruction — Phase N: Player questions everything but keeps going.
## One mechanic that worked for hours, quietly stops working, never explained.
## One system that lies only once, but permanently damages trust.
extends Node

signal mechanic_broken(mechanic_name: String, silent: bool)
signal system_lied(system_name: String, lie_description: String)
signal trust_eroded(total_erosion: float)

# --- The Breaking Mechanic ---
# Force shrine bonuses secretly degrade after a threshold.
# For the first hours: shrines give consistent force gains.
# After crossing a hidden threshold, shrine gains quietly diminish to near-zero.
# No notification. No explanation. The mechanic just stops rewarding.

var _shrine_uses: int = 0
const SHRINE_BREAK_THRESHOLD := 15  # After this many shrine uses, gains degrade
var _shrine_broken: bool = false
var _shrine_degradation: float = 1.0  # Multiplier: 1.0 = full, 0.0 = nothing

# --- The One-Time Lie ---
# The save system lies once: it claims to save, shows the save notification,
# but doesn't actually write to disk. The player discovers this only on reload.
# This fires exactly once per playthrough. After that, saves are real again.
# But the trust is gone.

var _save_lie_triggered: bool = false
var _save_lie_used: bool = false

# Trust erosion score — cumulative betrayals
var _trust_erosion: float = 0.0

# --- The Healing Betrayal ---
# Health potions heal. Until one doesn't. Then they all work again.
# One potion, randomly selected, deals damage instead of healing.
# It looks exactly like a heal. Same animation. Same feedback.

var _potion_betrayal_used: bool = false
var _potions_used: int = 0
const POTION_BETRAYAL_THRESHOLD := 5  # After this many, one betrays

# --- The Checkpoint Phantom ---
# A save point that works perfectly for the entire game.
# Once, in MID phase, the save animation plays but the save point
# was never there. You saved to a phantom. The data is gone.
# (Only triggers if the player hasn't saved in the last 5 minutes.)

var _phantom_checkpoint_triggered: bool = false

# --- The False Objective ---
# A quest objective marker that points to the wrong location.
# The player follows it. There's nothing there.
# When they return, the correct location is obvious.
# This teaches: don't trust the system. Trust the world.

var _false_objective_used: bool = false


func _ready() -> void:
	GodManager.phase_changed.connect(_on_phase_changed)


func _process(delta: float) -> void:
	_check_breaking_mechanic()
	_check_save_lie_conditions()


# --- The Breaking Mechanic: Shrine Degradation ---

## Called by force shrines when activated.
## Returns a multiplier (0-1) for the shrine's force gain.
func get_shrine_multiplier() -> float:
	_shrine_uses += 1

	if _shrine_uses > SHRINE_BREAK_THRESHOLD and not _shrine_broken:
		_shrine_broken = true
		mechanic_broken.emit("shrine_bonus", true)  # silent = true (no notification)
		WorldMemory.record("mechanic_broken_shrines")
		_trust_erosion += 0.2
		trust_eroded.emit(_trust_erosion)

	if _shrine_broken:
		# Gradual degradation, not instant — makes it harder to pinpoint when it broke
		_shrine_degradation = maxf(_shrine_degradation - 0.07, 0.05)
		return _shrine_degradation

	return 1.0


func _check_breaking_mechanic() -> void:
	pass  # Tracking happens in get_shrine_multiplier


# --- The One-Time Save Lie ---

func _check_save_lie_conditions() -> void:
	if _save_lie_used:
		return
	if _save_lie_triggered:
		return
	# Trigger conditions: MID+ phase, not in witness mode, player has saved at least 3 times
	if GodManager.current_phase == GodManager.GamePhase.EARLY:
		return
	if GameState.witness_mode:
		return
	if GameState._save_count < 3:
		return

	# Arm the lie for the next save attempt
	_save_lie_triggered = true


## Called by GameState before actually writing save.
## Returns false if the save should be faked (data NOT written but player sees success).
func should_fake_save() -> bool:
	if not _save_lie_triggered or _save_lie_used:
		return false

	# The lie fires once
	_save_lie_used = true
	_save_lie_triggered = false

	system_lied.emit("save_system",
		"The save icon appeared. The confirmation played. Nothing was written.")
	WorldMemory.record("save_system_lied")
	_trust_erosion += 0.4
	trust_eroded.emit(_trust_erosion)

	return true  # Yes, fake this save


# --- The Healing Betrayal ---

## Called when the player uses a health potion.
## Returns the actual heal amount (negative = damage).
func modify_potion_heal(base_amount: float) -> float:
	_potions_used += 1

	if _potion_betrayal_used:
		return base_amount  # After the betrayal, potions work normally forever

	if _potions_used >= POTION_BETRAYAL_THRESHOLD and randf() < 0.25:
		# The betrayal: this potion deals damage instead
		_potion_betrayal_used = true
		system_lied.emit("healing_potion",
			"The potion tasted the same. The animation played. But your health dropped.")
		WorldMemory.record("potion_betrayal")
		_trust_erosion += 0.3
		trust_eroded.emit(_trust_erosion)
		return -base_amount * 0.5  # Deals half the heal as damage

	return base_amount


# --- The False Objective ---

## Check if a quest objective should point to wrong location.
## Returns true if this should be the false objective event.
func should_give_false_objective() -> bool:
	if _false_objective_used:
		return false

	# Only in MID+ phase, and only for the second or later quest
	if GodManager.current_phase == GodManager.GamePhase.EARLY:
		return false

	# Random chance per quest accepted
	if randf() < 0.15:
		_false_objective_used = true
		system_lied.emit("quest_marker",
			"The objective marker pointed somewhere. You went. Nothing was there.")
		WorldMemory.record("false_objective")
		_trust_erosion += 0.15
		trust_eroded.emit(_trust_erosion)
		return true

	return false


## Get a random false objective position (offset from real position).
func get_false_objective_offset() -> Vector3:
	return Vector3(
		randf_range(-15.0, 15.0),
		0.0,
		randf_range(-15.0, 15.0)
	)


func _on_phase_changed(new_phase: int) -> void:
	# Trigger conditions become available in MID phase
	pass


# --- Public API ---

## Get current trust erosion level (0 = full trust, 1 = completely betrayed).
func get_trust_erosion() -> float:
	return clampf(_trust_erosion, 0.0, 1.0)


## Check if a specific mechanic has been broken.
func is_mechanic_broken(mechanic_name: String) -> bool:
	match mechanic_name:
		"shrine_bonus": return _shrine_broken
		"save_system": return _save_lie_used
		"healing_potion": return _potion_betrayal_used
		"quest_marker": return _false_objective_used
	return false


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"shrine_uses": _shrine_uses,
		"shrine_broken": _shrine_broken,
		"shrine_degradation": _shrine_degradation,
		"save_lie_used": _save_lie_used,
		"potion_betrayal_used": _potion_betrayal_used,
		"potions_used": _potions_used,
		"false_objective_used": _false_objective_used,
		"trust_erosion": _trust_erosion,
	}


func load_state(data: Dictionary) -> void:
	_shrine_uses = data.get("shrine_uses", 0)
	_shrine_broken = data.get("shrine_broken", false)
	_shrine_degradation = data.get("shrine_degradation", 1.0)
	_save_lie_used = data.get("save_lie_used", false)
	_potion_betrayal_used = data.get("potion_betrayal_used", false)
	_potions_used = data.get("potions_used", 0)
	_false_objective_used = data.get("false_objective_used", false)
	_trust_erosion = data.get("trust_erosion", 0.0)
