## EnemyBloodEcho — Violence-aligned. FEEDS on player violence.
## Defining rule: Heals and grows stronger every time the player deals damage nearby.
## The more you fight, the stronger it becomes. Forces restraint or avoidance.
## Killing it adds massive violence. Ignoring it lets it eventually leave.
class_name EnemyBloodEcho
extends EnemyBase

var _absorbed_violence: float = 0.0  # Tracks how much violence it has absorbed
var _passive_timer: float = 0.0  # If ignored long enough, it wanders away
const PASSIVE_LEAVE_TIME := 60.0  # Leaves after 60s of no nearby violence
const ABSORB_RANGE := 15.0  # Range to detect player violence

# Visual: grows redder and larger as it absorbs violence
var _base_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	force_affinity = "violence"
	force_reward_type = "violence"
	force_reward_amount = 8.0  # Killing it floods the world with violence
	max_health = 80.0
	health = max_health
	move_speed = 2.5  # Slow — it stalks, not chases
	chase_speed = 4.0
	attack_damage = 6.0  # Weak initially
	detection_range = 10.0
	patrol_range = 12.0
	super._ready()
	_base_scale = scale

	# Listen for violence in the world
	GameState.force_changed.connect(_on_world_force_changed)


## Feeds on violence: any violence force gain heals and empowers it.
func _on_world_force_changed(force_name: String, old_value: float, new_value: float) -> void:
	if is_dead:
		return
	if force_name != "violence":
		return
	if new_value <= old_value:
		return  # Only feeds on increases

	var gain := new_value - old_value
	_absorbed_violence += gain
	_passive_timer = 0.0  # Reset leave timer — violence keeps it here

	# Heal proportional to violence absorbed
	health = minf(health + gain * 2.0, max_health + _absorbed_violence * 3.0)

	# Grow stronger
	attack_damage = 6.0 + _absorbed_violence * 0.5
	chase_speed = 4.0 + _absorbed_violence * 0.1

	# Grow visually — redder, larger
	var growth := 1.0 + _absorbed_violence * 0.02
	scale = _base_scale * minf(growth, 2.0)

	# Flash red when absorbing
	if gain > 1.0:
		_telegraph_flash(Color(1.0, 0.0, 0.0))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_dead:
		return

	# Passive departure: if no violence happens nearby for long enough, it wanders off
	_passive_timer += delta
	if _passive_timer >= PASSIVE_LEAVE_TIME:
		_leave_peacefully()


## The Blood Echo leaves — it was never here to fight. It was here to feed.
func _leave_peacefully() -> void:
	is_dead = true
	state = State.DEAD
	velocity = Vector3.ZERO

	WorldEventManager.event_notification.emit(
		"???", "The blood echo disperses. It found nothing to sustain it.")
	WorldMemory.record_ambient("Blood Echo left — starved of violence")

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 2.0) if has_method("modulate") else null
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 2.0)
	tween.tween_callback(queue_free)


func _die() -> void:
	is_dead = true
	state = State.DEAD
	velocity = Vector3.ZERO

	# Massive violence reward — this is the cost of fighting it
	GameState.add_force("violence", force_reward_amount + _absorbed_violence * 0.5)

	WorldEventManager.event_notification.emit(
		"BLOOD ECHO", "It dies screaming. The violence it ate pours back into the world.")
	WorldMemory.record("blood_echo_killed")
	WorldMemory.record_ambient("Blood Echo killed — violence flooded world")

	# Death visual — expands then bursts
	var tween := create_tween()
	tween.tween_property(self, "scale", scale * 1.5, 0.3)
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.2)
	tween.tween_callback(queue_free)


func _exit_tree() -> void:
	super._exit_tree()
	if GameState and GameState.force_changed.is_connected(_on_world_force_changed):
		GameState.force_changed.disconnect(_on_world_force_changed)
