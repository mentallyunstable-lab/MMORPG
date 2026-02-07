## SilenceFallout — Silence must feel worse than lies.
## While the Keeper is SILENT, the world degrades epistemically:
##   - NPC trust decay accelerates (+25-40%)
##   - Contradictory rumors increase (probabilistic, not guaranteed)
##   - A silence_pressure_radius makes the area around the Keeper epistemically unstable
##   - Player receives fragmented truths: individually true but incompatible
##
## CRITICAL RULE: Never attribute lies to the Keeper during silence.
## The WORLD degrades, not the anchor. The Keeper's absence of voice
## creates a vacuum that unreliability fills.
extends Node

signal silence_fallout_active(is_active: bool)
signal fragmented_truth_generated(truths: Array)

# --- State ---
var is_active: bool = false
var _silence_duration: float = 0.0  # How long current silence has lasted

# --- Trust Decay Acceleration ---
# During Keeper silence, NPC trust decays 25-40% faster.
# The range creates unpredictability — players can't calculate exact decay.
const TRUST_DECAY_BOOST_MIN := 0.25
const TRUST_DECAY_BOOST_MAX := 0.40
var trust_decay_multiplier: float = 1.0  # Applied to TrustDestruction decay rate

# --- Contradictory Rumors ---
# Probability that an NPC will generate a contradictory rumor during silence.
const RUMOR_BASE_CHANCE := 0.15
const RUMOR_CHANCE_PER_MINUTE := 0.05  # Increases the longer silence lasts
var _rumor_timer: float = 0.0
const RUMOR_CHECK_INTERVAL := 30.0  # Check every 30 seconds

# --- Silence Pressure Radius ---
# The area around the Keeper becomes epistemically unstable during silence.
# This affects NPC dialogue and environmental feedback in Keeper zones.
var silence_pressure_radius: float = 0.0  # 0.0 = no effect, 1.0 = maximum distortion
const RADIUS_GROWTH_RATE := 0.02  # Per second of silence
const RADIUS_MAX := 1.0
const RADIUS_DECAY_RATE := 0.05  # Decays after silence ends

# --- Fragmented Truths ---
# Statements that are individually true but incompatible with each other.
# The player must determine which truths apply to their situation.
var _fragment_pool: Array[Dictionary] = []

const CHECK_INTERVAL := 2.0
var _timer: float = 0.0


func _ready() -> void:
	AnchorManager.anchor_state_changed.connect(_on_anchor_state_changed)
	_build_fragment_pool()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0

	var was_active := is_active
	is_active = AnchorManager.current_state == AnchorManager.AnchorState.SILENT

	if is_active:
		_silence_duration += CHECK_INTERVAL
		_update_silence_effects()
		_check_rumors()
	else:
		if was_active:
			_end_silence_effects()
		# Decay pressure radius even when silence ends
		if silence_pressure_radius > 0.0:
			silence_pressure_radius = maxf(silence_pressure_radius - RADIUS_DECAY_RATE * CHECK_INTERVAL, 0.0)

	if was_active != is_active:
		silence_fallout_active.emit(is_active)


## Called when anchor state changes.
func _on_anchor_state_changed(_old: String, new_state: String) -> void:
	if new_state == "silent":
		_silence_duration = 0.0
		trust_decay_multiplier = 1.0 + randf_range(TRUST_DECAY_BOOST_MIN, TRUST_DECAY_BOOST_MAX)
		WorldMemory.record_ambient("The Keeper's silence weighs on the world")
	elif new_state == "present":
		_end_silence_effects()


## Update effects that scale with silence duration.
func _update_silence_effects() -> void:
	# Grow pressure radius
	silence_pressure_radius = clampf(
		silence_pressure_radius + RADIUS_GROWTH_RATE * CHECK_INTERVAL,
		0.0, RADIUS_MAX
	)

	# Trust decay boost increases slightly over time
	var duration_factor := clampf(_silence_duration / 600.0, 0.0, 1.0)  # Max at 10 min
	trust_decay_multiplier = 1.0 + lerpf(TRUST_DECAY_BOOST_MIN, TRUST_DECAY_BOOST_MAX, duration_factor)


## Check if contradictory rumors should fire.
func _check_rumors() -> void:
	_rumor_timer += CHECK_INTERVAL
	if _rumor_timer < RUMOR_CHECK_INTERVAL:
		return
	_rumor_timer = 0.0

	var minutes_silent := _silence_duration / 60.0
	var rumor_chance := RUMOR_BASE_CHANCE + minutes_silent * RUMOR_CHANCE_PER_MINUTE
	rumor_chance = clampf(rumor_chance, 0.0, 0.6)

	if randf() < rumor_chance:
		_generate_fragmented_truths()


## Generate a pair of individually true but incompatible statements.
func _generate_fragmented_truths() -> void:
	if _fragment_pool.is_empty():
		return

	var pair := _fragment_pool[randi() % _fragment_pool.size()]
	var truths: Array = []

	# Each statement IS true when checked against current state,
	# but they imply contradictory conclusions.
	var dominant := GameState.get_dominant_force()
	var pressure := GameState.world_pressure

	match pair.get("type", ""):
		"force_conflict":
			var force_a: String = pair.get("force_a", "faith")
			var force_b: String = pair.get("force_b", "truth")
			var val_a := GameState.get_force(force_a)
			var val_b := GameState.get_force(force_b)
			# Both true: "Faith is at X" and "Truth is at Y"
			# But they imply different dominant forces when taken alone
			truths = [
				"%s is %s in this region." % [force_a.capitalize(), _vague_intensity(val_a)],
				"%s is %s in this region." % [force_b.capitalize(), _vague_intensity(val_b)],
			]
		"god_status":
			var gods := GodManager.god_defs.keys()
			if gods.size() >= 2:
				var g1: String = gods[randi() % gods.size()]
				var g2: String = gods[randi() % gods.size()]
				while g2 == g1 and gods.size() > 1:
					g2 = gods[randi() % gods.size()]
				truths = [
					"%s is %s." % [GodManager.get_god_name(g1), GodManager.get_god_state(g1)],
					"%s is %s." % [GodManager.get_god_name(g2), GodManager.get_god_state(g2)],
				]
		"pressure_split":
			truths = [
				"The world pressure is %s." % _vague_pressure(pressure),
				"The dominant force is %s." % dominant,
			]

	if truths.size() > 0:
		fragmented_truth_generated.emit(truths)
		WorldMemory.record_ambient("Fragmented truths during Keeper silence")


func _vague_intensity(value: float) -> String:
	if value >= 70.0:
		return "strong"
	elif value >= 40.0:
		return "present"
	elif value >= 15.0:
		return "stirring"
	return "quiet"


func _vague_pressure(value: float) -> String:
	if value >= 70.0:
		return "crushing"
	elif value >= 45.0:
		return "building"
	elif value >= 20.0:
		return "noticeable"
	return "calm"


## End silence effects and begin decay.
func _end_silence_effects() -> void:
	_silence_duration = 0.0
	trust_decay_multiplier = 1.0
	_rumor_timer = 0.0


## Build the pool of fragment types.
func _build_fragment_pool() -> void:
	_fragment_pool = [
		{"type": "force_conflict", "force_a": "faith", "force_b": "truth"},
		{"type": "force_conflict", "force_a": "truth", "force_b": "violence"},
		{"type": "force_conflict", "force_a": "violence", "force_b": "faith"},
		{"type": "god_status"},
		{"type": "pressure_split"},
	]


## Query: get the trust decay multiplier for TrustDestruction to use.
func get_trust_decay_multiplier() -> float:
	return trust_decay_multiplier


## Query: is the area around the Keeper epistemically unstable?
func get_silence_pressure() -> float:
	return silence_pressure_radius


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"is_active": is_active,
		"silence_duration": _silence_duration,
		"trust_decay_multiplier": trust_decay_multiplier,
		"silence_pressure_radius": silence_pressure_radius,
		"rumor_timer": _rumor_timer,
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"silence_duration": _silence_duration,
		"silence_pressure_radius": silence_pressure_radius,
	}


func load_state(data: Dictionary) -> void:
	_silence_duration = data.get("silence_duration", 0.0)
	silence_pressure_radius = data.get("silence_pressure_radius", 0.0)
