## EnemyBase — Simple enemy AI with patrol, chase, and attack states.
## Behavior shifts based on world pressure (Faith/Truth/Violence).
class_name EnemyBase
extends CharacterBody3D

enum State { IDLE, PATROL, CHASE, ATTACK, DEAD }

@export var max_health: float = 50.0
@export var move_speed: float = 3.5
@export var chase_speed: float = 5.5
@export var attack_damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.0
@export var detection_range: float = 12.0
@export var patrol_range: float = 8.0
@export var gravity: float = 20.0

# Force affinity — determines behavior shifts.
# Options: "faith", "truth", "violence", "neutral"
@export var force_affinity: String = "neutral"

# Rewards when killed
@export var force_reward_type: String = "violence"
@export var force_reward_amount: float = 1.0

var health: float = 50.0
var state: State = State.IDLE
var home_position: Vector3 = Vector3.ZERO
var patrol_target: Vector3 = Vector3.ZERO
var attack_timer: float = 0.0
var player_ref: Node3D = null
var is_dead: bool = false
var _is_telegraphing: bool = false
var _mesh_node: MeshInstance3D = null
var _stalking_timer: float = 0.0  # Cooldown for stalking behavior in EARLY phase
var _lying_telegraph_used: bool = false  # Each enemy lies once, then never again


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	home_position = global_position
	_pick_patrol_target()
	_mesh_node = _find_mesh()

	# React to world pressure changes
	GameState.force_changed.connect(_on_force_changed)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Timers
	if attack_timer > 0:
		attack_timer -= delta
	if _stalking_timer > 0:
		_stalking_timer -= delta

	# Find player
	_find_player()

	# State machine
	match state:
		State.IDLE:
			_state_idle(delta)
		State.PATROL:
			_state_patrol(delta)
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			_state_attack(delta)

	move_and_slide()


# --- State Logic ---

func _state_idle(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0

	# Phase-gated aggression: enemies are less aggressive in EARLY phase
	var patrol_chance := delta * 0.5
	if GodManager.current_phase == GodManager.GamePhase.EARLY:
		patrol_chance *= 0.4  # Much slower to patrol — let player explore

	# Transition to patrol after a moment
	if randf() < patrol_chance:
		state = State.PATROL
		_pick_patrol_target()

	# Detect player — reduced range in EARLY phase
	if _can_see_player():
		if GodManager.current_phase == GodManager.GamePhase.EARLY and _stalking_timer <= 0:
			# EARLY: stalk instead of chase — shadow the player from a distance
			_stalking_timer = randf_range(4.0, 8.0)
			state = State.PATROL
			_pick_patrol_target_toward_player()
		else:
			state = State.CHASE


func _state_patrol(delta: float) -> void:
	var direction := (patrol_target - global_position)
	direction.y = 0

	if direction.length() < 1.0:
		state = State.IDLE
		return

	direction = direction.normalized()

	# Force-driven patrol styles (Phase 2.6)
	var patrol_speed := move_speed
	match force_affinity:
		"violence":
			# Violence-heavy: reckless paths — faster, less cautious
			patrol_speed = move_speed * (1.0 + GameState.violence * 0.005)
		"truth":
			# Truth-heavy: hesitant — pause mid-patrol, change direction
			if GameState.truth >= 50.0 and randf() < delta * 0.3:
				# Hesitation: brief stop
				velocity.x = 0
				velocity.z = 0
				return
		"faith":
			# Faith-heavy: cluster toward other faith enemies
			patrol_speed *= 0.9  # Slightly slower — more deliberate
			if GameState.faith >= 50.0 and randf() < delta * 0.2:
				_pick_patrol_target_near_ally()

	velocity.x = direction.x * patrol_speed
	velocity.z = direction.z * patrol_speed
	_face_direction(direction, delta)

	if _can_see_player():
		state = State.CHASE


func _state_chase(delta: float) -> void:
	if not player_ref or not is_instance_valid(player_ref):
		state = State.IDLE
		return

	var to_player := player_ref.global_position - global_position
	to_player.y = 0
	var dist := to_player.length()

	if dist > detection_range * 1.5:
		# Lost player
		state = State.IDLE
		return

	if dist <= attack_range:
		state = State.ATTACK
		velocity.x = 0
		velocity.z = 0
		return

	var direction := to_player.normalized()
	var speed := chase_speed

	# Violence-aligned enemies are faster when world violence is high
	if force_affinity == "violence":
		speed += GameState.violence * 0.03

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_face_direction(direction, delta)


func _state_attack(delta: float) -> void:
	if not player_ref or not is_instance_valid(player_ref):
		state = State.IDLE
		return

	velocity.x = 0
	velocity.z = 0

	var dist := global_position.distance_to(player_ref.global_position)

	if dist > attack_range * 1.3:
		state = State.CHASE
		return

	# Face the player
	var to_player := (player_ref.global_position - global_position).normalized()
	_face_direction(to_player, delta)

	# Attack on cooldown — violence makes enemies attack faster
	if attack_timer <= 0:
		_perform_attack()
		var cd := attack_cooldown
		if GameState.violence >= 70.0:
			cd *= maxf(1.0 - (GameState.violence - 70.0) / 100.0, 0.5)  # Up to 50% faster
		attack_timer = cd


func _perform_attack() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		return
	if not player_ref.has_method("take_damage"):
		return

	# --- Force-Modified Combat (Step 5) ---

	# HIGH TRUTH: Enemy abilities fail — attacks misfire (chance to skip)
	# Misfire signal: blue flash + scale shrink = "I tried and failed"
	if GameState.truth >= 70.0:
		var fail_chance := (GameState.truth - 70.0) / 100.0  # 0-0.3 at 70-100
		if randf() < fail_chance:
			_telegraph_flash(Color(0.3, 0.5, 1.0))  # Blue = misfire
			_telegraph_scale_pulse(Vector3(0.8, 0.8, 0.8), 0.3)  # Shrink = failure
			await get_tree().create_timer(0.5).timeout
			if is_instance_valid(self):
				_is_telegraphing = false
			WorldMemory.record_ambient("Enemy attack misfired — truth disrupted")
			return

	# HIGH FAITH: Miracles interrupt combat — brief invulnerability for player
	# Miracle signal: golden flash + upward scale = "divine intervention"
	if GameState.faith >= 70.0 and randf() < 0.12:
		_telegraph_flash(Color(0.9, 0.8, 0.4))  # Golden = miracle
		_telegraph_scale_pulse(Vector3(0.9, 1.3, 0.9), 0.4)  # Tall = divine
		await get_tree().create_timer(0.4).timeout
		if not is_instance_valid(self) or is_dead:
			return
		_is_telegraphing = false
		if player_ref.has_method("heal"):
			player_ref.heal(attack_damage * 0.3)
		WorldMemory.record_ambient("Miracle interrupted enemy attack")
		return

	# LYING TELEGRAPH: Once per enemy, telegraph a color that doesn't match the attack.
	# The enemy fakes a misfire (blue flash) then attacks anyway. Teaches distrust.
	if not _lying_telegraph_used and randf() < 0.08:
		_lying_telegraph_used = true
		_is_telegraphing = true
		_telegraph_flash(Color(0.3, 0.5, 1.0))  # Blue = looks like misfire...
		_telegraph_scale_pulse(Vector3(0.8, 0.8, 0.8), 0.25)  # Looks like shrink...
		await get_tree().create_timer(0.3).timeout
		if not is_instance_valid(self) or is_dead:
			return
		# ...but then the real attack comes (red flash, fast)
		_telegraph_flash(Color(1.0, 0.0, 0.0))
		await get_tree().create_timer(0.15).timeout  # Very short — less time to react
		if not is_instance_valid(self) or is_dead:
			return
		_is_telegraphing = false
		if player_ref and is_instance_valid(player_ref) and player_ref.has_method("take_damage"):
			player_ref.take_damage(attack_damage * 1.2, global_position)  # Extra damage for the lie
		WorldMemory.record_ambient("Enemy used lying telegraph — faked misfire")
		return

	# Standard telegraph — clear color per affinity
	_is_telegraphing = true
	var telegraph_color := Color(1.0, 0.2, 0.1)  # Default red
	match force_affinity:
		"faith": telegraph_color = Color(0.6, 0.7, 1.0)  # Blue-white
		"truth": telegraph_color = Color(1.0, 1.0, 0.4)  # Yellow-white
		"violence": telegraph_color = Color(1.0, 0.15, 0.0)  # Deep red-orange
	_telegraph_flash(telegraph_color)
	_telegraph_scale_pulse(Vector3(1.15, 1.15, 1.15), 0.35)  # Expand = incoming
	await get_tree().create_timer(0.35).timeout
	if not is_instance_valid(self) or is_dead:
		return
	_is_telegraphing = false

	if not player_ref or not is_instance_valid(player_ref):
		return

	var dmg := attack_damage

	# Faith-aligned enemies deal more when faith is low
	if force_affinity == "faith" and GameState.faith < 20.0:
		dmg *= 1.5

	# HIGH VIOLENCE: All enemies hit harder and faster
	if GameState.violence >= 70.0:
		var violence_mult := 1.0 + (GameState.violence - 70.0) / 100.0  # 1.0-1.3
		dmg *= violence_mult

	player_ref.take_damage(dmg, global_position)


# --- Detection ---

func _find_player() -> void:
	if player_ref and is_instance_valid(player_ref):
		return
	player_ref = get_tree().get_first_node_in_group("player")


func _can_see_player() -> bool:
	if not player_ref or not is_instance_valid(player_ref):
		return false
	var dist := global_position.distance_to(player_ref.global_position)

	var effective_range := detection_range
	# Phase-gated detection: reduced in EARLY, expanded in LATE
	match GodManager.current_phase:
		GodManager.GamePhase.EARLY:
			effective_range *= 0.6  # 40% less aware — player can explore
		GodManager.GamePhase.LATE:
			effective_range *= 1.2  # 20% more alert — world tightens

	# Truth-aligned enemies detect further when truth is high
	if force_affinity == "truth":
		effective_range += GameState.truth * 0.1

	return dist <= effective_range


# --- Damage ---

func take_damage(amount: float, source_position: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return

	health -= amount

	# Knockback direction
	if source_position != Vector3.ZERO:
		var knockback := (global_position - source_position).normalized()
		knockback.y = 0
		velocity += knockback * 5.0

	if health <= 0:
		_die()
	else:
		# Aggro on damage
		state = State.CHASE


func _die() -> void:
	is_dead = true
	state = State.DEAD
	velocity = Vector3.ZERO

	# Reward force
	GameState.add_force(force_reward_type, force_reward_amount)

	# Placeholder death effect — scale down and remove
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.5)
	tween.tween_callback(queue_free)


# --- Helpers ---

func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.001:
		var target_angle := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 8.0 * delta)


func _pick_patrol_target() -> void:
	var offset := Vector3(
		randf_range(-patrol_range, patrol_range),
		0,
		randf_range(-patrol_range, patrol_range)
	)
	patrol_target = home_position + offset


## Pick a patrol target near an ally with the same force affinity — clustering behavior.
func _pick_patrol_target_near_ally() -> void:
	var allies := get_tree().get_nodes_in_group("enemies")
	var closest_ally: Node3D = null
	var closest_dist := 999.0
	for ally in allies:
		if ally == self or not is_instance_valid(ally):
			continue
		if ally is EnemyBase and ally.force_affinity == force_affinity and not ally.is_dead:
			var d := global_position.distance_to(ally.global_position)
			if d < closest_dist and d > 2.0:  # Not too close, not too far
				closest_dist = d
				closest_ally = ally
	if closest_ally:
		# Move toward the ally, stop partway
		var to_ally := closest_ally.global_position - global_position
		to_ally.y = 0
		patrol_target = global_position + to_ally * 0.5
	else:
		_pick_patrol_target()


## Pick a patrol target that's between the enemy and the player — stalking behavior.
## The enemy moves toward the player but stops at a distance, creating unease.
func _pick_patrol_target_toward_player() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		_pick_patrol_target()
		return
	var to_player := player_ref.global_position - global_position
	to_player.y = 0
	var stalk_distance := detection_range * 0.7  # Stay at 70% of detection range
	if to_player.length() > stalk_distance:
		patrol_target = global_position + to_player.normalized() * (to_player.length() - stalk_distance)
	else:
		# Already close enough — circle around
		var perp := Vector3(-to_player.z, 0, to_player.x).normalized()
		patrol_target = global_position + perp * randf_range(3.0, 6.0)


func _find_mesh() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null


## Flash enemy white on hit — called by PlayerController on melee impact.
func hit_flash() -> void:
	if not _mesh_node:
		return
	var mat := _mesh_node.get_surface_override_material(0)
	if not mat or not mat is StandardMaterial3D:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.2, 0.2, 1)
		_mesh_node.set_surface_override_material(0, mat)
	var original_emission: bool = mat.emission_enabled
	var original_energy: float = mat.emission_energy_multiplier
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 3.0
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self) and mat:
		mat.emission_enabled = original_emission
		mat.emission_energy_multiplier = original_energy


## Flash enemy with telegraph color before attack.
func _telegraph_flash(color: Color) -> void:
	if not _mesh_node:
		return
	var mat := _mesh_node.get_surface_override_material(0)
	if not mat or not mat is StandardMaterial3D:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.2, 0.2, 1)
		_mesh_node.set_surface_override_material(0, mat)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	# Pulse via tween
	var tween := create_tween().set_loops(2)
	tween.tween_property(mat, "emission_energy_multiplier", 0.5, 0.15)
	tween.tween_property(mat, "emission_energy_multiplier", 2.0, 0.15)


## Scale pulse telegraph — size change indicates attack type.
## Expand = incoming attack, Shrink = failure/misfire, Tall = divine intervention.
func _telegraph_scale_pulse(target_scale: Vector3, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", target_scale, duration * 0.4)
	tween.tween_property(self, "scale", Vector3.ONE, duration * 0.6)


# --- Lifecycle ---

func _exit_tree() -> void:
	if GameState and GameState.force_changed.is_connected(_on_force_changed):
		GameState.force_changed.disconnect(_on_force_changed)


# --- World Pressure Reaction ---

var _force_buff_applied: bool = false

func _on_force_changed(force_name: String, _old_value: float, new_value: float) -> void:
	if is_dead:
		return
	# Apply once when matching force exceeds threshold
	if force_name == force_affinity and new_value > 70.0 and not _force_buff_applied:
		_force_buff_applied = true
		detection_range *= 1.2
		attack_damage *= 1.1


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"health": health,
		"is_dead": is_dead,
		"position": var_to_str(global_position),
		"state": state,
		"force_buff_applied": _force_buff_applied,
		"home_position": var_to_str(home_position),
	}


func load_state(data: Dictionary) -> void:
	health = data.get("health", max_health)
	is_dead = data.get("is_dead", false)
	if data.has("position"):
		global_position = str_to_var(data["position"])
	if data.has("home_position"):
		home_position = str_to_var(data["home_position"])
	_force_buff_applied = data.get("force_buff_applied", false)
	if is_dead:
		queue_free()
	else:
		state = data.get("state", State.IDLE)
