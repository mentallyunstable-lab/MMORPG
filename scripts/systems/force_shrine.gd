## ForceShrine — An interactable world object that lets the player channel
## a specific force. Each shrine is aligned to Faith, Truth, or Violence.
## Using it shifts the world.
class_name ForceShrine
extends Interactable

@export var shrine_force: String = "faith"  # "faith", "truth", "violence"
@export var force_amount: float = 10.0
@export var cooldown_time: float = 30.0

var _cooldown_timer: float = 0.0
var times_used: int = 0


func _ready() -> void:
	super._ready()
	one_time = false
	interaction_text = "Channel %s" % shrine_force.capitalize()


func _process(delta: float) -> void:
	if _cooldown_timer > 0:
		_cooldown_timer -= delta


func _on_interact(player: Node) -> void:
	if _cooldown_timer > 0:
		return

	GameState.add_force(shrine_force, force_amount)
	times_used += 1
	_cooldown_timer = cooldown_time

	# Opposing force drain
	match shrine_force:
		"faith":
			GameState.add_force("truth", -force_amount * 0.3)
		"truth":
			GameState.add_force("faith", -force_amount * 0.3)
		"violence":
			# Violence doesn't oppose, it destabilizes
			GameState.add_force("faith", -force_amount * 0.15)
			GameState.add_force("truth", -force_amount * 0.15)

	# Faction reputation shift
	match shrine_force:
		"faith":
			GameState.change_faction_reputation("ashwalkers", 3.0)
			GameState.change_faction_reputation("hollow_church", 2.0)
			GameState.change_faction_reputation("truthseekers", -2.0)
		"truth":
			GameState.change_faction_reputation("truthseekers", 3.0)
			GameState.change_faction_reputation("ashwalkers", -2.0)
			GameState.change_faction_reputation("hollow_church", -2.0)
		"violence":
			GameState.change_faction_reputation("ironvow", 3.0)
			GameState.change_faction_reputation("ashwalkers", -1.0)
			GameState.change_faction_reputation("truthseekers", -1.0)

	# God stability shift
	for god_id in GodManager.god_defs:
		match shrine_force:
			"faith":
				var current := GameState.get_god_stability(god_id)
				GameState.set_god_stability(god_id, current + 3.0)
			"truth":
				var current := GameState.get_god_stability(god_id)
				GameState.set_god_stability(god_id, current - 5.0)

	# Notify
	WorldEventManager.event_notification.emit(
		"Shrine Activated",
		"You channeled the force of %s." % shrine_force.capitalize()
	)


func save_state() -> Dictionary:
	var base := super.save_state()
	base["times_used"] = times_used
	return base


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	times_used = data.get("times_used", 0)
