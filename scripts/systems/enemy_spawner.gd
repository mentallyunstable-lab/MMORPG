## EnemySpawner — Spawns enemies at designated points. Enemy types and frequency
## shift based on the dominant world force.
class_name EnemySpawner
extends Node3D

@export var spawn_interval: float = 15.0
@export var max_enemies: int = 5
@export var spawn_radius: float = 3.0
@export var spawn_on_ready: bool = true

# Enemy scenes by force affinity
@export var enemy_neutral: PackedScene = null
@export var enemy_faith: PackedScene = null
@export var enemy_truth: PackedScene = null
@export var enemy_violence: PackedScene = null

var _timer: float = 0.0
var _spawned: Array = []


func _ready() -> void:
	add_to_group("spawners")
	if spawn_on_ready:
		_spawn_enemy()

	ForceEffects.force_tier_changed.connect(_on_force_tier_changed)


func _process(delta: float) -> void:
	# Clean dead references
	_spawned = _spawned.filter(func(e): return is_instance_valid(e) and not e.is_dead)

	_timer += delta
	if _timer >= spawn_interval and _spawned.size() < max_enemies:
		_timer = 0.0
		_spawn_enemy()


func _spawn_enemy() -> void:
	var scene := _pick_enemy_scene()
	if not scene:
		return

	var enemy: Node3D = scene.instantiate()
	var offset := Vector3(
		randf_range(-spawn_radius, spawn_radius),
		0,
		randf_range(-spawn_radius, spawn_radius)
	)
	enemy.global_position = global_position + offset

	get_parent().add_child(enemy)
	_spawned.append(enemy)


func _pick_enemy_scene() -> PackedScene:
	var dominant := GameState.get_dominant_force()
	var dom_value := GameState.get_force(dominant)

	# If dominant force is high enough, bias spawns toward that type
	if dom_value >= 50.0:
		var roll := randf()
		# 60% chance to spawn force-aligned enemy, 40% neutral
		if roll < 0.6:
			match dominant:
				"faith":
					if enemy_faith:
						return enemy_faith
				"truth":
					if enemy_truth:
						return enemy_truth
				"violence":
					if enemy_violence:
						return enemy_violence

	# Fallback to neutral
	if enemy_neutral:
		return enemy_neutral

	# Last resort — use whatever is available
	for scene in [enemy_faith, enemy_truth, enemy_violence]:
		if scene:
			return scene
	return null


func _on_force_tier_changed(_force_name: String, tier: String) -> void:
	# Ramp up spawning at higher tiers
	match tier:
		"high":
			spawn_interval = max(spawn_interval * 0.8, 5.0)
		"critical":
			spawn_interval = max(spawn_interval * 0.6, 3.0)
			max_enemies += 2
