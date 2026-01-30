## EnemyVoidSeeker — Truth-aligned. Hard-counters dodge spam.
## Defining rule: Tracks dodge patterns. If player dodges twice in 3s,
## the Seeker instantly teleports behind them and attacks.
## Also has wider detection when truth is high.
class_name EnemyVoidSeeker
extends EnemyBase

var _player_dodge_count: int = 0
var _dodge_window_timer: float = 0.0
const DODGE_WINDOW := 3.0
const DODGE_THRESHOLD := 2


func _ready() -> void:
	force_affinity = "truth"
	force_reward_type = "truth"
	force_reward_amount = 1.5
	detection_range = 14.0  # Wider base detection
	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_dead:
		return

	# Track player dodge cooldown window
	if _dodge_window_timer > 0:
		_dodge_window_timer -= delta
		if _dodge_window_timer <= 0:
			_player_dodge_count = 0

	# Monitor player dodge state
	if player_ref and is_instance_valid(player_ref) and player_ref is PlayerController:
		if player_ref.is_dodging and _dodge_window_timer <= 0:
			_dodge_window_timer = DODGE_WINDOW
			_player_dodge_count = 0
		if player_ref.is_dodging:
			# Count dodge starts (check on frame dodge begins)
			if not _was_player_dodging:
				_player_dodge_count += 1
				if _player_dodge_count >= DODGE_THRESHOLD and state != State.DEAD:
					_punish_dodge_spam()
			_was_player_dodging = true
		else:
			_was_player_dodging = false

var _was_player_dodging: bool = false


func _punish_dodge_spam() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		return
	_player_dodge_count = 0
	_dodge_window_timer = 0.0

	# Teleport behind player
	var behind := player_ref.global_position - player_ref.global_transform.basis.z.normalized() * 2.0
	behind.y = global_position.y
	global_position = behind

	# Instant attack — no telegraph, punishment for spam
	if player_ref.has_method("take_damage"):
		player_ref.take_damage(attack_damage * 1.5, global_position)
		WorldMemory.record_ambient("Void Seeker punished dodge spam")

	state = State.ATTACK
