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


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	home_position = global_position
	_pick_patrol_target()

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

	# Transition to patrol after a moment
	if randf() < delta * 0.5:  # ~every 2 seconds on average
		state = State.PATROL
		_pick_patrol_target()

	# Detect player
	if _can_see_player():
		state = State.CHASE


func _state_patrol(delta: float) -> void:
	var direction := (patrol_target - global_position)
	direction.y = 0

	if direction.length() < 1.0:
		state = State.IDLE
		return

	direction = direction.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
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

	# Attack on cooldown
	if attack_timer <= 0:
		_perform_attack()
		attack_timer = attack_cooldown


func _perform_attack() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		return
	if not player_ref.has_method("take_damage"):
		return

	var dmg := attack_damage

	# Faith-aligned enemies deal more when faith is low
	if force_affinity == "faith" and GameState.faith < 20.0:
		dmg *= 1.5

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
	}


func load_state(data: Dictionary) -> void:
	health = data.get("health", max_health)
	is_dead = data.get("is_dead", false)
	if data.has("position"):
		global_position = str_to_var(data["position"])
	if is_dead:
		queue_free()
