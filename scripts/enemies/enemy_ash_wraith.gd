## EnemyAshWraith — Faith-aligned. Punishes greed.
## Defining rule: Hits harder the more total force the player has accumulated.
## High world pressure = high pain. Forces restraint.
class_name EnemyAshWraith
extends EnemyBase


func _ready() -> void:
	force_affinity = "faith"
	force_reward_type = "violence"
	force_reward_amount = 1.5
	super._ready()


func _perform_attack() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		return
	if not player_ref.has_method("take_damage"):
		return

	# Telegraph
	_is_telegraphing = true
	_telegraph_flash(Color(0.6, 0.7, 1.0))  # Faith blue
	await get_tree().create_timer(0.35).timeout
	if not is_instance_valid(self) or is_dead:
		return
	_is_telegraphing = false

	if not player_ref or not is_instance_valid(player_ref):
		return

	# DEFINING RULE: Damage scales with total world pressure.
	# Base damage at 0 pressure, up to 2.5x at max pressure.
	var pressure_mult := 1.0 + (GameState.world_pressure / 100.0) * 1.5
	var dmg := attack_damage * pressure_mult

	player_ref.take_damage(dmg, global_position)
	WorldMemory.record_ambient("Ash Wraith punished excess force")
