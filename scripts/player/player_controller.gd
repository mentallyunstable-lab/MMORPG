## PlayerController — Third-person character with movement, camera, combat, and interaction.
class_name PlayerController
extends CharacterBody3D

# --- Movement ---
@export var move_speed: float = 6.0
@export var sprint_speed: float = 10.0
@export var jump_force: float = 8.0
@export var gravity: float = 20.0
@export var rotation_speed: float = 10.0
@export var dodge_speed: float = 14.0
@export var dodge_duration: float = 0.3

# --- Camera ---
@export var mouse_sensitivity: float = 0.002
@export var camera_min_pitch: float = -80.0
@export var camera_max_pitch: float = 60.0

# --- Combat ---
@export var melee_damage: float = 20.0
@export var melee_range: float = 2.5
@export var ranged_damage: float = 15.0
@export var ranged_speed: float = 30.0
@export var attack_cooldown: float = 0.4

# --- Stamina ---
@export var max_stamina: float = 100.0
@export var stamina_regen: float = 20.0  # per second
@export var dodge_stamina_cost: float = 30.0
@export var attack_stamina_cost: float = 15.0
@export var stamina_regen_delay: float = 0.8  # seconds after last use before regen starts

# --- Respawn ---
@export var respawn_delay: float = 2.0

# --- Nodes ---
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var mesh: Node3D = $PlayerMesh
@onready var melee_area: Area3D = $PlayerMesh/MeleeArea
@onready var interaction_ray: RayCast3D = $PlayerMesh/InteractionRay
@onready var projectile_spawn: Marker3D = $PlayerMesh/ProjectileSpawn
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# --- State ---
var input_enabled: bool = true
var is_attacking: bool = false
var is_dodging: bool = false
var is_invulnerable: bool = false
var is_dead: bool = false
var dodge_timer: float = 0.0
var dodge_direction: Vector3 = Vector3.ZERO
var attack_timer: float = 0.0
var current_interactable: Node = null
var _spawn_position: Vector3 = Vector3.ZERO
var _camera_shake_intensity: float = 0.0
var stamina: float = 100.0
var _stamina_regen_timer: float = 0.0
var _dodge_recovery: bool = false  # Vulnerability window after dodge ends


func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_spawn_position = global_position
	print("[PlayerController] _ready() fired — script is loaded. input_enabled=", input_enabled)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("move_forward"):
		print("[PlayerController] W pressed! input_enabled=", input_enabled, " is_dead=", is_dead)
	if Input.is_action_just_pressed("jump"):
		print("[PlayerController] Space pressed! input_enabled=", input_enabled, " is_dead=", is_dead)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	# Camera look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if not camera_pivot or not spring_arm:
			return
		var motion := event as InputEventMouseMotion
		camera_pivot.rotate_y(-motion.relative.x * mouse_sensitivity)
		spring_arm.rotate_x(-motion.relative.y * mouse_sensitivity)
		spring_arm.rotation.x = clamp(
			spring_arm.rotation.x,
			deg_to_rad(camera_min_pitch),
			deg_to_rad(camera_max_pitch)
		)

	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if not input_enabled or is_dead:
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.x = 0
			velocity.z = 0
		move_and_slide()
		return

	# Timers
	if attack_timer > 0:
		attack_timer -= delta
	if is_dodging:
		dodge_timer -= delta
		if dodge_timer <= 0:
			is_dodging = false
			is_invulnerable = false
			# Dodge recovery vulnerability — brief window where you take 1.5x damage
			_dodge_recovery = true
			await get_tree().create_timer(0.15).timeout
			if is_instance_valid(self):
				_dodge_recovery = false

	# Stamina regen
	if _stamina_regen_timer > 0:
		_stamina_regen_timer -= delta
	elif stamina < max_stamina:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)

	# Camera shake decay
	if _camera_shake_intensity > 0 and camera:
		camera.h_offset = randf_range(-_camera_shake_intensity, _camera_shake_intensity)
		camera.v_offset = randf_range(-_camera_shake_intensity, _camera_shake_intensity)
		_camera_shake_intensity = move_toward(_camera_shake_intensity, 0.0, delta * 2.0)
	elif camera:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_dodging:
		velocity.y = jump_force

	# Movement
	if is_dodging:
		velocity.x = dodge_direction.x * dodge_speed
		velocity.z = dodge_direction.z * dodge_speed
	elif not is_attacking:
		var input_dir := Vector2.ZERO
		input_dir.x = Input.get_axis("move_left", "move_right")
		input_dir.y = Input.get_axis("move_forward", "move_backward")
		input_dir = input_dir.normalized()

		# Direction relative to camera
		var cam_basis := camera_pivot.global_transform.basis
		var direction := (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		direction.y = 0

		var speed := move_speed
		if direction.length() > 0.1:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed

			# Rotate mesh to face movement direction
			var target_angle := atan2(direction.x, direction.z)
			mesh.rotation.y = lerp_angle(mesh.rotation.y, target_angle, rotation_speed * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, speed * delta * 10.0)
			velocity.z = move_toward(velocity.z, 0, speed * delta * 10.0)

	# Dodge (requires stamina)
	if Input.is_action_just_pressed("dodge") and not is_dodging and is_on_floor() and stamina >= dodge_stamina_cost:
		_start_dodge()

	# Combat (requires stamina)
	if Input.is_action_just_pressed("attack_melee") and attack_timer <= 0 and not is_dodging and stamina >= attack_stamina_cost:
		_melee_attack()

	if Input.is_action_just_pressed("attack_ranged") and attack_timer <= 0 and not is_dodging and stamina >= attack_stamina_cost:
		_ranged_attack()

	# Interaction
	if Input.is_action_just_pressed("interact"):
		_try_interact()

	move_and_slide()

	# Check for nearby interactables
	_check_interactables()


# --- Combat ---

func _melee_attack() -> void:
	is_attacking = true
	attack_timer = attack_cooldown
	_consume_stamina(attack_stamina_cost)

	# Deal damage to all bodies in melee area
	var hit_count := 0
	for body in melee_area.get_overlapping_bodies():
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(melee_damage, global_position)
			# Enemy hit flash
			if body.has_method("hit_flash"):
				body.hit_flash()
			hit_count += 1

	# Hit feedback
	if hit_count > 0:
		GameState.add_force("violence", 0.5)
		DebugTimer.mark_first_combat()
		_camera_shake_intensity = 0.08
		# Hitstop — brief freeze frame
		Engine.time_scale = 0.05
		await get_tree().create_timer(0.05 * 0.05).timeout  # Real-time ~0.0025s
		if is_instance_valid(self):
			Engine.time_scale = 1.0

	# Brief attack state
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		is_attacking = false


func _ranged_attack() -> void:
	is_attacking = true
	attack_timer = attack_cooldown
	_consume_stamina(attack_stamina_cost)

	# Spawn projectile
	var projectile := _create_projectile()
	if projectile:
		get_tree().root.add_child(projectile)

	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(self):
		is_attacking = false


func _create_projectile() -> Projectile:
	var proj := Projectile.new()
	proj.name = "Projectile"
	proj.add_to_group("projectiles")

	# Collision shape
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	col.shape = sphere
	proj.add_child(col)

	# Visual
	var mesh_instance := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.15
	sphere_mesh.height = 0.3
	mesh_instance.mesh = sphere_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.3, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat
	proj.add_child(mesh_instance)

	# Position and direction
	proj.global_position = projectile_spawn.global_position
	var forward := -camera_pivot.global_transform.basis.z.normalized()
	forward.y = -spring_arm.rotation.x  # Account for vertical aim

	proj.direction = forward
	proj.speed = ranged_speed
	proj.damage = ranged_damage

	# Collision setup
	proj.collision_layer = 16  # Layer 5: Projectiles
	proj.collision_mask = 1 | 4  # Layer 1: World, Layer 3: Enemies

	return proj


func _start_dodge() -> void:
	is_dodging = true
	is_invulnerable = true
	dodge_timer = dodge_duration
	_consume_stamina(dodge_stamina_cost)

	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_forward", "move_backward")

	if input_dir.length() < 0.1:
		# Dodge backward if no direction
		dodge_direction = -mesh.global_transform.basis.z
	else:
		var cam_basis := camera_pivot.global_transform.basis
		dodge_direction = (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		dodge_direction.y = 0

	# Visual cue — brief scale squash + transparency
	if mesh:
		var tween := create_tween()
		tween.tween_property(mesh, "scale", Vector3(1.2, 0.6, 1.2), dodge_duration * 0.3)
		tween.tween_property(mesh, "scale", Vector3.ONE, dodge_duration * 0.7)


# --- Interaction ---

func _check_interactables() -> void:
	if not interaction_ray:
		return

	if interaction_ray.is_colliding():
		var collider := interaction_ray.get_collider()
		if collider and collider.is_in_group("interactables"):
			current_interactable = collider
		else:
			current_interactable = null
	else:
		current_interactable = null


func _try_interact() -> void:
	if DialogueManager.is_active:
		DialogueManager.advance()
		return

	if current_interactable and is_instance_valid(current_interactable) and current_interactable.has_method("interact"):
		current_interactable.interact(self)


# --- Damage ---

func take_damage(amount: float, _source_position: Vector3 = Vector3.ZERO) -> void:
	if is_dead or is_invulnerable:
		return

	# Dodge recovery vulnerability — 1.5x damage right after dodge ends
	var effective_amount := amount * (1.5 if _dodge_recovery else 1.0)

	GameState.player_health -= effective_amount
	if GameState.player_health <= 0:
		GameState.player_health = 0
		GameState.player_alive = false
		_die()


func _die() -> void:
	is_dead = true
	input_enabled = false
	velocity = Vector3.ZERO

	# Visual death feedback — fade mesh
	if mesh:
		var tween := create_tween()
		tween.tween_property(mesh, "scale", Vector3(0.8, 0.2, 0.8), 0.5)

	# Respawn after delay
	await get_tree().create_timer(respawn_delay).timeout
	if is_instance_valid(self):
		_respawn()


func _respawn() -> void:
	is_dead = false
	input_enabled = true
	GameState.player_health = GameState.player_max_health
	GameState.player_alive = true
	stamina = max_stamina
	global_position = _spawn_position

	# Restore scale
	if mesh:
		mesh.scale = Vector3.ONE

	# Add violence from dying
	GameState.add_force("violence", 1.0)


func heal(amount: float) -> void:
	GameState.player_health = min(GameState.player_health + amount, GameState.player_max_health)


# --- Stamina ---

func _consume_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_stamina_regen_timer = stamina_regen_delay


# --- External API ---

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
