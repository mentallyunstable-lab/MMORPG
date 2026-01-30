## EnemyFanatic — Violence-aligned. Explodes on death.
## Defining rule: On death, detonates in an AoE that:
## 1. Damages the player if nearby
## 2. Adds violence force to the world
## 3. Corrupts the current zone
## Killing fanatics makes the world worse. You must choose: fight or avoid.
class_name EnemyFanatic
extends EnemyBase

@export var explosion_radius: float = 5.0
@export var explosion_damage: float = 15.0
@export var violence_on_death: float = 3.0


func _ready() -> void:
	force_affinity = "violence"
	force_reward_type = "violence"
	force_reward_amount = 0.5  # Low base — the explosion is the real cost
	max_health = 35.0  # Fragile
	health = max_health
	chase_speed = 7.0  # Fast — rushes the player
	attack_damage = 8.0  # Weak melee — the explosion is the point
	super._ready()


func _die() -> void:
	is_dead = true
	state = State.DEAD
	velocity = Vector3.ZERO

	# Reward base force
	GameState.add_force(force_reward_type, force_reward_amount)

	# DEFINING RULE: Explode on death
	_explode()

	# Death visual — expand then vanish
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(2.0, 2.0, 2.0), 0.2)
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tween.tween_callback(queue_free)


func _explode() -> void:
	# Damage nearby player
	if player_ref and is_instance_valid(player_ref):
		var dist := global_position.distance_to(player_ref.global_position)
		if dist <= explosion_radius:
			var falloff := 1.0 - (dist / explosion_radius)
			if player_ref.has_method("take_damage"):
				player_ref.take_damage(explosion_damage * falloff, global_position)

	# Spread violence to the world
	GameState.add_force("violence", violence_on_death)

	# Corrupt current zone
	for zone_id in GameState.region_state:
		var region: Dictionary = GameState.get_region(zone_id)
		region["corruption"] = minf(region.get("corruption", 0.0) + 5.0, 100.0)

	# Notify
	WorldEventManager.event_notification.emit("Detonation", "A fanatic detonated. The world absorbs the violence.")
	WorldMemory.record_ambient("Fanatic exploded — violence spread")
