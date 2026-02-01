## CombatPsychology — Phase K: Combat communicates meaning, not skill.
## K1: Emotional Combat States (camera, sound, enemy behavior shift with force)
## K2: Enemy Memory (remembers kills, flee patterns, adapts patrols)
extends Node

# --- K1: Emotional Combat States ---

signal combat_mood_changed(mood: String, intensity: float)
signal enemy_memory_event(enemy_type: String, memory_type: String, data: Dictionary)

# Combat mood — derived from recent combat actions + force state
enum CombatMood { NEUTRAL, FRENZY, DREAD, DISSOCIATION, ECSTASY, EMPTINESS }
var current_mood: CombatMood = CombatMood.NEUTRAL
var mood_intensity: float = 0.0  # 0-1

# Recent combat tracking
var _recent_kills: int = 0
var _recent_kills_decay_timer: float = 0.0
var _recent_damage_taken: float = 0.0
var _recent_damage_decay_timer: float = 0.0
var _flee_count: int = 0
var _total_kills: int = 0
var _kill_methods: Dictionary = {}  # "melee"/"ranged" -> count

# Camera modifiers based on mood
var camera_fov_modifier: float = 0.0      # Added to base FOV
var camera_shake_modifier: float = 0.0    # Added to shake intensity
var camera_tilt_modifier: float = 0.0     # Degrees of camera roll

# Sound modifiers
var sound_dampening: float = 0.0          # 0 = normal, 1 = muted
var sound_distortion: float = 0.0         # 0 = clean, 1 = heavy distortion

# --- K2: Enemy Memory ---
# Global memory: enemies share knowledge about player behavior.

var _player_kill_patterns: Dictionary = {}  # enemy_force_affinity -> kill_count
var _player_flee_history: Array[float] = []  # Timestamps of fleeing
var _enemy_adaptation_level: float = 0.0     # 0-1, how much enemies have adapted

const KILL_DECAY_INTERVAL := 3.0  # Seconds before recent kills decay
const DAMAGE_DECAY_INTERVAL := 5.0
const FLEE_WINDOW := 120.0  # Track fleeing over last 2 minutes
const ADAPTATION_PER_KILL := 0.01  # How much each kill teaches enemies
const MAX_ADAPTATION := 0.8  # Enemies never fully adapt — always beatable


func _ready() -> void:
	GameState.force_changed.connect(_on_force_changed)


func _process(delta: float) -> void:
	# Decay recent activity
	_recent_kills_decay_timer += delta
	if _recent_kills_decay_timer >= KILL_DECAY_INTERVAL:
		_recent_kills_decay_timer = 0.0
		_recent_kills = maxi(_recent_kills - 1, 0)

	_recent_damage_decay_timer += delta
	if _recent_damage_decay_timer >= DAMAGE_DECAY_INTERVAL:
		_recent_damage_decay_timer = 0.0
		_recent_damage_taken = maxf(_recent_damage_taken - 5.0, 0.0)

	# Prune old flee history
	var now := Time.get_ticks_msec() / 1000.0
	while _player_flee_history.size() > 0 and now - _player_flee_history[0] > FLEE_WINDOW:
		_player_flee_history.pop_front()

	# Update combat mood
	_update_mood(delta)


func _update_mood(delta: float) -> void:
	var old_mood := current_mood
	var faith := GameState.faith
	var truth := GameState.truth
	var violence := GameState.violence

	# Determine mood based on combat state + forces
	if _recent_kills >= 4 and violence >= 50.0:
		# FRENZY: killing spree + high violence
		current_mood = CombatMood.FRENZY
		mood_intensity = clampf(float(_recent_kills) / 8.0 + violence / 200.0, 0.0, 1.0)
	elif _recent_damage_taken > 30.0 and faith < 30.0:
		# DREAD: taking heavy damage with no faith to comfort
		current_mood = CombatMood.DREAD
		mood_intensity = clampf(_recent_damage_taken / 80.0, 0.0, 1.0)
	elif truth >= 70.0 and _recent_kills >= 2:
		# DISSOCIATION: killing while truth is high — you see too clearly
		current_mood = CombatMood.DISSOCIATION
		mood_intensity = clampf(truth / 100.0, 0.3, 1.0)
	elif faith >= 70.0 and _recent_kills >= 1:
		# ECSTASY: killing in faith's name
		current_mood = CombatMood.ECSTASY
		mood_intensity = clampf(faith / 100.0, 0.3, 0.9)
	elif GameState.world_pressure < 20.0 and _recent_kills == 0:
		# EMPTINESS: nothing happening, forces low
		current_mood = CombatMood.EMPTINESS
		mood_intensity = clampf(1.0 - GameState.world_pressure / 40.0, 0.0, 0.5)
	else:
		current_mood = CombatMood.NEUTRAL
		mood_intensity = lerpf(mood_intensity, 0.0, delta * 0.5)

	# Apply mood effects
	_apply_mood_effects(delta)

	if old_mood != current_mood:
		combat_mood_changed.emit(_mood_to_string(current_mood), mood_intensity)


func _apply_mood_effects(delta: float) -> void:
	match current_mood:
		CombatMood.FRENZY:
			# Camera closes in, shakes, sound distorts
			camera_fov_modifier = lerpf(camera_fov_modifier, -10.0 * mood_intensity, delta * 2.0)
			camera_shake_modifier = lerpf(camera_shake_modifier, 0.05 * mood_intensity, delta * 3.0)
			camera_tilt_modifier = lerpf(camera_tilt_modifier, 3.0 * mood_intensity * sin(Time.get_ticks_msec() * 0.003), delta * 5.0)
			sound_dampening = lerpf(sound_dampening, 0.3 * mood_intensity, delta * 2.0)
			sound_distortion = lerpf(sound_distortion, 0.4 * mood_intensity, delta * 2.0)

		CombatMood.DREAD:
			# Camera pulls back, everything gets quieter, FOV widens
			camera_fov_modifier = lerpf(camera_fov_modifier, 8.0 * mood_intensity, delta * 1.5)
			camera_shake_modifier = lerpf(camera_shake_modifier, 0.02 * mood_intensity, delta)
			camera_tilt_modifier = lerpf(camera_tilt_modifier, 0.0, delta * 2.0)
			sound_dampening = lerpf(sound_dampening, 0.5 * mood_intensity, delta * 1.5)
			sound_distortion = lerpf(sound_distortion, 0.1 * mood_intensity, delta)

		CombatMood.DISSOCIATION:
			# Camera drifts slightly, sound becomes distant, slight desaturation
			camera_fov_modifier = lerpf(camera_fov_modifier, 5.0 * mood_intensity, delta)
			camera_shake_modifier = lerpf(camera_shake_modifier, 0.0, delta * 3.0)
			camera_tilt_modifier = lerpf(camera_tilt_modifier, 1.5 * sin(Time.get_ticks_msec() * 0.001), delta * 2.0)
			sound_dampening = lerpf(sound_dampening, 0.6 * mood_intensity, delta * 2.0)
			sound_distortion = lerpf(sound_distortion, 0.0, delta * 2.0)

		CombatMood.ECSTASY:
			# Camera tightens, warmth, sound becomes resonant
			camera_fov_modifier = lerpf(camera_fov_modifier, -5.0 * mood_intensity, delta * 2.0)
			camera_shake_modifier = lerpf(camera_shake_modifier, 0.0, delta * 3.0)
			camera_tilt_modifier = lerpf(camera_tilt_modifier, 0.0, delta * 3.0)
			sound_dampening = lerpf(sound_dampening, -0.1 * mood_intensity, delta)  # Louder
			sound_distortion = lerpf(sound_distortion, 0.0, delta * 2.0)

		CombatMood.EMPTINESS:
			# Everything neutral but slightly too quiet
			camera_fov_modifier = lerpf(camera_fov_modifier, 0.0, delta)
			camera_shake_modifier = lerpf(camera_shake_modifier, 0.0, delta * 2.0)
			camera_tilt_modifier = lerpf(camera_tilt_modifier, 0.0, delta * 2.0)
			sound_dampening = lerpf(sound_dampening, 0.2, delta * 0.5)
			sound_distortion = lerpf(sound_distortion, 0.0, delta)

		CombatMood.NEUTRAL:
			# Decay all modifiers
			camera_fov_modifier = lerpf(camera_fov_modifier, 0.0, delta)
			camera_shake_modifier = lerpf(camera_shake_modifier, 0.0, delta * 2.0)
			camera_tilt_modifier = lerpf(camera_tilt_modifier, 0.0, delta * 3.0)
			sound_dampening = lerpf(sound_dampening, 0.0, delta * 2.0)
			sound_distortion = lerpf(sound_distortion, 0.0, delta * 2.0)


# --- K1: Force-Specific Combat Behaviors ---

## Get enemy behavior modification based on dominant force.
## Called by EnemyBase during combat.
func get_enemy_combat_modifier(force_affinity: String) -> Dictionary:
	var mods := {
		"hesitation_chance": 0.0,     # Chance to pause before attacking
		"fake_death_chance": 0.0,     # Chance to fake death (truth enemies)
		"delayed_reaction": 0.0,      # Seconds of delayed hit reaction
		"miracle_cost_future": 0.0,   # Faith miracle chance that costs future certainty
		"frenzy_chance": 0.0,         # Chance to attack in a burst
	}

	# Truth-heavy builds: enemies fake deaths
	if GameState.truth >= 60.0 and force_affinity == "truth":
		mods["fake_death_chance"] = (GameState.truth - 60.0) / 100.0  # 0-0.4
		mods["delayed_reaction"] = (GameState.truth - 60.0) / 200.0  # 0-0.2s

	# Faith-heavy builds: miracles cost future certainty
	if GameState.faith >= 60.0 and force_affinity == "faith":
		mods["miracle_cost_future"] = (GameState.faith - 60.0) / 100.0

	# Violence-heavy: enemies get frenzied or hesitant
	if GameState.violence >= 70.0:
		if force_affinity == "violence":
			mods["frenzy_chance"] = (GameState.violence - 70.0) / 100.0
		else:
			# Non-violence enemies hesitate against violence-dominant players
			mods["hesitation_chance"] = (GameState.violence - 70.0) / 150.0

	return mods


# --- K2: Enemy Memory System ---

## Called when the player kills an enemy.
func record_kill(enemy_force_affinity: String, kill_method: String) -> void:
	_total_kills += 1
	_recent_kills += 1
	_recent_kills_decay_timer = 0.0

	# Track by affinity
	_player_kill_patterns[enemy_force_affinity] = _player_kill_patterns.get(enemy_force_affinity, 0) + 1

	# Track by method
	_kill_methods[kill_method] = _kill_methods.get(kill_method, 0) + 1

	# Increase enemy adaptation
	_enemy_adaptation_level = clampf(_enemy_adaptation_level + ADAPTATION_PER_KILL, 0.0, MAX_ADAPTATION)

	enemy_memory_event.emit(enemy_force_affinity, "kill_recorded", {
		"method": kill_method,
		"total_kills_this_type": _player_kill_patterns[enemy_force_affinity],
		"adaptation_level": _enemy_adaptation_level,
	})


## Called when the player flees from combat.
func record_flee() -> void:
	_flee_count += 1
	_player_flee_history.append(Time.get_ticks_msec() / 1000.0)

	enemy_memory_event.emit("", "flee_recorded", {
		"total_flees": _flee_count,
		"recent_flees": _player_flee_history.size(),
	})


## Called when the player takes damage.
func record_damage_taken(amount: float) -> void:
	_recent_damage_taken += amount
	_recent_damage_decay_timer = 0.0


## Get patrol behavior adaptation based on enemy memory.
## Returns modifiers that enemy_base.gd uses to adjust behavior.
func get_patrol_adaptation(enemy_force_affinity: String) -> Dictionary:
	var adaptation := {
		"avoid_player_path": false,     # Patrol away from player's common routes
		"ambush_tendency": 0.0,         # 0-1, tendency to set ambushes
		"group_up": false,              # Cluster with allies
		"expanded_detection": 0.0,      # Extra detection range
	}

	# If player kills many of this type, survivors adapt
	var kills_of_type: int = _player_kill_patterns.get(enemy_force_affinity, 0)
	if kills_of_type >= 5:
		adaptation["avoid_player_path"] = true
		adaptation["group_up"] = true

	if kills_of_type >= 10:
		adaptation["ambush_tendency"] = clampf(float(kills_of_type - 10) / 20.0, 0.0, 0.5)
		adaptation["expanded_detection"] = 2.0  # +2m detection range

	# If player flees often, enemies pursue more aggressively
	if _player_flee_history.size() >= 3:
		adaptation["expanded_detection"] += 3.0
		adaptation["ambush_tendency"] += 0.2

	# Scale all by adaptation level
	adaptation["ambush_tendency"] *= _enemy_adaptation_level
	adaptation["expanded_detection"] *= _enemy_adaptation_level

	return adaptation


## Get the player's most used kill method.
func get_preferred_kill_method() -> String:
	var best := ""
	var best_count := 0
	for method in _kill_methods:
		if _kill_methods[method] > best_count:
			best_count = _kill_methods[method]
			best = method
	return best


func _mood_to_string(mood: CombatMood) -> String:
	match mood:
		CombatMood.NEUTRAL: return "neutral"
		CombatMood.FRENZY: return "frenzy"
		CombatMood.DREAD: return "dread"
		CombatMood.DISSOCIATION: return "dissociation"
		CombatMood.ECSTASY: return "ecstasy"
		CombatMood.EMPTINESS: return "emptiness"
	return "neutral"


func _on_force_changed(_force_name: String, _old: float, _new: float) -> void:
	pass  # Mood update happens in _process


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"total_kills": _total_kills,
		"kill_patterns": _player_kill_patterns.duplicate(),
		"kill_methods": _kill_methods.duplicate(),
		"flee_count": _flee_count,
		"enemy_adaptation": _enemy_adaptation_level,
	}


func load_state(data: Dictionary) -> void:
	_total_kills = data.get("total_kills", 0)
	_player_kill_patterns = data.get("kill_patterns", {})
	_kill_methods = data.get("kill_methods", {})
	_flee_count = data.get("flee_count", 0)
	_enemy_adaptation_level = data.get("enemy_adaptation", 0.0)
