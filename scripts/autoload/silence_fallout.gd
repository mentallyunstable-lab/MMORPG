## SilenceFallout — Silence must feel worse than lies.
## While the Keeper is SILENT, the world degrades epistemically:
##   - NPC trust decay accelerates (+25-40%)
##   - Contradictory rumors increase (probabilistic, not guaranteed)
##   - A silence_pressure_radius makes the area around the Keeper epistemically unstable
##   - Player receives fragmented truths: individually true but incompatible
##
## A3 Extensions — Silence Fallout Intensification:
##   - Secondary silence waves: silence ends → delayed rumor spike 5-10 min later
##   - NPC memory conflicts: two NPCs remember different versions of what happened
##   - Environmental audio glitch windows: wind, footsteps, ambient sounds trigger
##     only during silence fallout decay windows
##
## CRITICAL RULE: Never attribute lies to the Keeper during silence.
## The WORLD degrades, not the anchor. The Keeper's absence of voice
## creates a vacuum that unreliability fills.
extends Node

signal silence_fallout_active(is_active: bool)
signal fragmented_truth_generated(truths: Array)
signal secondary_wave_triggered(wave_number: int)
signal npc_memory_conflict(npc_a_version: String, npc_b_version: String)
signal audio_glitch_window_active(is_active: bool)

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

# --- A3: Secondary Silence Waves ---
# Silence ends → delayed rumor spike 5-10 minutes later.
# The player thinks the silence is over. It is not.
var _secondary_wave_pending: bool = false
var _secondary_wave_timer: float = 0.0
var _secondary_wave_delay: float = 0.0  # Randomized on each silence end
var _secondary_wave_count: int = 0
const SECONDARY_WAVE_DELAY_MIN := 300.0  # 5 minutes
const SECONDARY_WAVE_DELAY_MAX := 600.0  # 10 minutes
const SECONDARY_WAVE_TRUST_HIT := 0.03   # Direct trust level reduction
const SECONDARY_WAVE_RUMOR_BURST := 3     # Multiple rumors fire at once

# --- A3: NPC Memory Conflicts ---
# During silence fallout windows, two NPCs remember different versions of events.
# Neither is lying. Both are wrong. This is worse than a single lie.
var _memory_conflict_pool: Array[Dictionary] = []
var _active_conflicts: Array[Dictionary] = []
const MAX_ACTIVE_CONFLICTS := 5

# --- A3: Environmental Audio Glitches ---
# Wind, footsteps, ambient sounds that trigger only during silence fallout windows.
# Not random — specifically during the decay period after silence ends.
var audio_glitch_active: bool = false
var _audio_glitch_timer: float = 0.0
const AUDIO_GLITCH_CHECK_INTERVAL := 8.0
const AUDIO_GLITCH_CHANCE_BASE := 0.0     # No glitches normally
const AUDIO_GLITCH_CHANCE_FALLOUT := 0.35  # 35% chance during fallout window

# Glitch types: what the player hears that isn't real
const AUDIO_GLITCH_TYPES := [
	"wind_shift",      # Wind direction changes abruptly
	"phantom_steps",   # Footsteps behind the player
	"silence_echo",    # A brief moment of total silence, then return
	"voice_fragment",  # Unintelligible whisper — NOT the Keeper
	"ambient_drop",    # All ambient sound cuts for 1-2 seconds
]


func _ready() -> void:
	AnchorManager.anchor_state_changed.connect(_on_anchor_state_changed)
	_build_fragment_pool()
	_build_memory_conflict_pool()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0

	if DevToggles and DevToggles.disable_silence_fallout:
		return

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

	# --- A3: Secondary wave processing ---
	if _secondary_wave_pending:
		_secondary_wave_timer += CHECK_INTERVAL
		if _secondary_wave_timer >= _secondary_wave_delay:
			_trigger_secondary_wave()

	# --- A3: Audio glitch window ---
	_update_audio_glitch_window(CHECK_INTERVAL)

	if was_active != is_active:
		silence_fallout_active.emit(is_active)


## Called when anchor state changes.
func _on_anchor_state_changed(_old: String, new_state: String) -> void:
	if new_state == "silent":
		_silence_duration = 0.0
		trust_decay_multiplier = 1.0 + randf_range(TRUST_DECAY_BOOST_MIN, TRUST_DECAY_BOOST_MAX)
		WorldMemory.record_ambient("The Keeper's silence weighs on the world")
	elif new_state == "present":
		# A3: Queue secondary wave before ending effects
		if _silence_duration > 30.0:
			_queue_secondary_wave()
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
	# A3: Enable audio glitch window during decay
	audio_glitch_active = true
	audio_glitch_window_active.emit(true)
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


# --- A3: Secondary Silence Waves ---

## Queue a secondary wave to fire 5-10 minutes after silence ends.
func _queue_secondary_wave() -> void:
	_secondary_wave_pending = true
	_secondary_wave_timer = 0.0
	_secondary_wave_delay = randf_range(SECONDARY_WAVE_DELAY_MIN, SECONDARY_WAVE_DELAY_MAX)


## Fire the secondary wave: rumor burst + trust hit.
func _trigger_secondary_wave() -> void:
	_secondary_wave_pending = false
	_secondary_wave_count += 1
	secondary_wave_triggered.emit(_secondary_wave_count)

	# Direct trust reduction — compounds with natural decay
	TrustDestruction.trust_level = maxf(
		TrustDestruction.trust_level - SECONDARY_WAVE_TRUST_HIT,
		TrustDestruction.TRUST_FLOOR
	)

	# Fire multiple fragmented truths at once
	for i in range(SECONDARY_WAVE_RUMOR_BURST):
		_generate_fragmented_truths()

	# Generate a memory conflict
	_generate_npc_memory_conflict()

	WorldMemory.record_ambient("Silence echoed back — the world remembered wrong")


# --- A3: NPC Memory Conflicts ---

## Build pool of memory conflict templates.
func _build_memory_conflict_pool() -> void:
	_memory_conflict_pool = [
		{
			"topic": "force_state",
			"version_a": "The dominant force was %s before the silence.",
			"version_b": "No — %s was dominant. I'm certain of it.",
		},
		{
			"topic": "keeper_words",
			"version_a": "The Keeper said the world was stable before going quiet.",
			"version_b": "The Keeper warned us. They said the pressure was unbearable.",
		},
		{
			"topic": "duration",
			"version_a": "The silence lasted only moments. Barely noticeable.",
			"version_b": "It went on forever. I counted. It was an eternity.",
		},
		{
			"topic": "cause",
			"version_a": "The gods pressed down. That's why the Keeper went silent.",
			"version_b": "The world was too loud. The Keeper couldn't hear itself think.",
		},
		{
			"topic": "aftermath",
			"version_a": "Things calmed down after the silence ended.",
			"version_b": "It got worse after. Much worse. You must have noticed.",
		},
	]


## Generate a memory conflict between two hypothetical NPCs.
func _generate_npc_memory_conflict() -> void:
	if _memory_conflict_pool.is_empty():
		return

	var template: Dictionary = _memory_conflict_pool[randi() % _memory_conflict_pool.size()]
	var version_a: String = template.get("version_a", "")
	var version_b: String = template.get("version_b", "")

	# Fill in dynamic values where needed
	if template.get("topic", "") == "force_state":
		var forces := ["faith", "truth", "violence"]
		var f1: String = forces[randi() % forces.size()]
		var f2: String = forces[randi() % forces.size()]
		while f2 == f1:
			f2 = forces[randi() % forces.size()]
		version_a = version_a % f1.capitalize()
		version_b = version_b % f2.capitalize()

	var conflict := {
		"version_a": version_a,
		"version_b": version_b,
		"topic": template.get("topic", "unknown"),
		"timestamp": Time.get_unix_time_from_system(),
	}
	_active_conflicts.append(conflict)
	if _active_conflicts.size() > MAX_ACTIVE_CONFLICTS:
		_active_conflicts.pop_front()

	npc_memory_conflict.emit(version_a, version_b)


## Get a memory conflict pair for NPC dialogue.
## Returns two contradictory versions of the same event, or empty dict.
func get_npc_memory_conflict() -> Dictionary:
	if _active_conflicts.is_empty():
		return {}
	return _active_conflicts[randi() % _active_conflicts.size()]


# --- A3: Environmental Audio Glitches ---

## Update audio glitch window state.
func _update_audio_glitch_window(delta: float) -> void:
	if not audio_glitch_active:
		return

	# Audio glitches are active during silence pressure decay
	if silence_pressure_radius <= 0.0 and not _secondary_wave_pending:
		audio_glitch_active = false
		audio_glitch_window_active.emit(false)
		return

	_audio_glitch_timer += delta
	if _audio_glitch_timer >= AUDIO_GLITCH_CHECK_INTERVAL:
		_audio_glitch_timer = 0.0
		if randf() < AUDIO_GLITCH_CHANCE_FALLOUT:
			# Signal that an audio glitch should play
			var glitch_type: String = AUDIO_GLITCH_TYPES[randi() % AUDIO_GLITCH_TYPES.size()]
			WorldMemory.record_ambient("Audio distortion: %s" % glitch_type)


## Query: should an audio glitch play right now?
## Returns a glitch type string or empty string.
func get_audio_glitch() -> String:
	if not audio_glitch_active:
		return ""
	if randf() >= AUDIO_GLITCH_CHANCE_FALLOUT:
		return ""
	return AUDIO_GLITCH_TYPES[randi() % AUDIO_GLITCH_TYPES.size()]


## Query: is the silence fallout window active? (For audio/visual systems.)
func is_in_fallout_window() -> bool:
	return audio_glitch_active or _secondary_wave_pending


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
		"secondary_wave_pending": _secondary_wave_pending,
		"secondary_wave_timer": _secondary_wave_timer,
		"secondary_wave_count": _secondary_wave_count,
		"audio_glitch_active": audio_glitch_active,
		"active_memory_conflicts": _active_conflicts.size(),
		"in_fallout_window": is_in_fallout_window(),
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"silence_duration": _silence_duration,
		"silence_pressure_radius": silence_pressure_radius,
		"secondary_wave_count": _secondary_wave_count,
	}


func load_state(data: Dictionary) -> void:
	_silence_duration = data.get("silence_duration", 0.0)
	silence_pressure_radius = data.get("silence_pressure_radius", 0.0)
	_secondary_wave_count = data.get("secondary_wave_count", 0)
