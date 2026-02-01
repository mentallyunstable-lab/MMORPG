## WitnessExpansion — Phase L: Witness Mode is not a reward. It's a sentence.
## L1: Witness-only interactions (doors that respond but don't open, NPCs that
##     notice but refuse to acknowledge, objects that react once ever)
## L2: World decay over time (textures fade, sounds drop, UI loses labels)
extends Node

signal witness_interaction(object_id: String, interaction_type: String)
signal witness_decay_tick(decay_stage: int, elapsed: float)
signal ui_label_lost(label_name: String)

# --- L1: Witness-Only Interactions ---
# Objects that only exist or respond in witness mode.

var _witness_objects: Dictionary = {}  # object_id -> {type, used, data}
var _one_time_reactions: Dictionary = {}  # object_id -> bool (true = already used)

# --- L2: World Decay ---
var _witness_elapsed: float = 0.0  # Total seconds spent in witness mode
var _decay_stage: int = 0  # 0=fresh, 1=fading, 2=simplifying, 3=dissolving, 4=minimal
var _active_sounds: int = 10  # Number of "active" sound layers (decreases over time)
var _active_labels: Array[String] = []  # UI labels that still exist
var _texture_saturation: float = 1.0  # 1.0 = full color, 0.0 = gone
var _ambient_complexity: float = 1.0  # 1.0 = full detail, 0.0 = empty

# Decay stage thresholds (seconds spent in witness mode)
const STAGE_FADING := 60.0       # 1 minute: colors start draining
const STAGE_SIMPLIFYING := 180.0  # 3 minutes: sounds drop out, UI degrades
const STAGE_DISSOLVING := 360.0   # 6 minutes: significant visual loss
const STAGE_MINIMAL := 600.0      # 10 minutes: world is barely there


func _ready() -> void:
	WorldEventManager.witness_mode_entered.connect(_on_witness_mode_entered)
	_initialize_witness_objects()
	_initialize_labels()


func _process(delta: float) -> void:
	if not GameState.witness_mode:
		return

	_witness_elapsed += delta
	_update_decay(delta)
	_check_decay_stage()


# --- L1: Witness-Only Interaction Definitions ---

func _initialize_witness_objects() -> void:
	# Door that responds but never opens
	_witness_objects["witness_door_01"] = {
		"type": "responsive_door",
		"used": false,
		"interaction_sequence": [
			"The handle turns. The door does not move.",
			"You push. Something pushes back. Not resistance — recognition.",
			"The door knows you're here. It will never open.",
			"You stop trying. The handle slowly returns to its resting position.",
			"It waits. Like you.",
		],
		"interaction_index": 0,
		"max_interactions": 5,  # After this, silence
	}

	# NPC that notices but refuses to acknowledge
	_witness_objects["witness_npc_01"] = {
		"type": "refusing_npc",
		"used": false,
		"interaction_sequence": [
			"They look at you. Through you. Past you.",
			"Their mouth moves. No sound reaches you.",
			"They turn away. Not with hostility. With finality.",
			"You stand in their space. They navigate around you like furniture.",
		],
		"interaction_index": 0,
		"max_interactions": 4,
	}

	# Object that reacts exactly once, ever
	_witness_objects["witness_bell_01"] = {
		"type": "one_time_object",
		"used": false,
		"reaction_text": "You touch the bell. It rings — once. Clear, perfect, and utterly alone. It will never ring again.",
		"after_text": "The bell is silent. You already heard the only sound it had left.",
	}

	# Mirror that shows what was, not what is
	_witness_objects["witness_mirror_01"] = {
		"type": "memory_mirror",
		"used": false,
		"interaction_sequence": [
			"The mirror shows the room as it was. People move. Fires burn. None of it is real anymore.",
			"You try to focus on a face in the reflection. It blurs when you look directly.",
			"The mirror cracks. Not from impact — from grief.",
		],
		"interaction_index": 0,
		"max_interactions": 3,
	}

	# Footstep echo that follows but arrives late
	_witness_objects["witness_echo_01"] = {
		"type": "delayed_echo",
		"used": false,
		"interaction_sequence": [
			"Footsteps behind you. Yours, from a moment ago. Or someone else's, from long ago.",
			"The echo is slower now. It's falling behind.",
			"The footsteps stop. You keep walking. The silence is heavier.",
		],
		"interaction_index": 0,
		"max_interactions": 3,
	}


func _initialize_labels() -> void:
	_active_labels = [
		"Health", "Faith", "Truth", "Violence",
		"Interact", "Quest", "Force", "Stamina",
		"Zone", "God",
	]


## Interact with a witness-only object.
## Called by interactable nodes that detect witness mode.
func interact_witness_object(object_id: String) -> String:
	if not _witness_objects.has(object_id):
		return "Nothing here responds."

	var obj: Dictionary = _witness_objects[object_id]
	var obj_type: String = obj.get("type", "")

	match obj_type:
		"responsive_door", "refusing_npc", "memory_mirror", "delayed_echo":
			return _interact_sequential(object_id, obj)
		"one_time_object":
			return _interact_one_time(object_id, obj)

	return "..."


func _interact_sequential(object_id: String, obj: Dictionary) -> String:
	var sequence: Array = obj.get("interaction_sequence", [])
	var index: int = obj.get("interaction_index", 0)
	var max_interactions: int = obj.get("max_interactions", sequence.size())

	if index >= max_interactions or index >= sequence.size():
		# Exhausted — permanent silence
		witness_interaction.emit(object_id, "exhausted")
		return "..."

	var text: String = sequence[index]
	obj["interaction_index"] = index + 1

	witness_interaction.emit(object_id, "sequential_%d" % index)
	WorldMemory.record("witness_interact_%s_%d" % [object_id, index])
	return text


func _interact_one_time(object_id: String, obj: Dictionary) -> String:
	if obj.get("used", false):
		witness_interaction.emit(object_id, "already_used")
		return obj.get("after_text", "It doesn't respond. It already gave everything it had.")

	obj["used"] = true
	_one_time_reactions[object_id] = true
	witness_interaction.emit(object_id, "first_and_only")
	WorldMemory.record("witness_one_time_%s" % object_id)
	return obj.get("reaction_text", "Something happened. It won't happen again.")


# --- L2: World Decay Over Time ---

func _update_decay(delta: float) -> void:
	# Textures fade
	var target_saturation := 1.0
	match _decay_stage:
		1: target_saturation = 0.7
		2: target_saturation = 0.4
		3: target_saturation = 0.15
		4: target_saturation = 0.0
	_texture_saturation = lerpf(_texture_saturation, target_saturation, delta * 0.05)

	# Ambient complexity reduces
	var target_complexity := 1.0
	match _decay_stage:
		1: target_complexity = 0.8
		2: target_complexity = 0.5
		3: target_complexity = 0.2
		4: target_complexity = 0.05
	_ambient_complexity = lerpf(_ambient_complexity, target_complexity, delta * 0.03)

	# Sounds drop out periodically in stages 2+
	if _decay_stage >= 2 and _active_sounds > 0:
		if randf() < delta * 0.01 * _decay_stage:
			_active_sounds -= 1
			WorldMemory.record_ambient("A sound stopped. You can't remember which one.")

	# UI labels vanish in stages 3+
	if _decay_stage >= 3 and _active_labels.size() > 0:
		if randf() < delta * 0.005 * _decay_stage:
			var lost_label: String = _active_labels[randi() % _active_labels.size()]
			_active_labels.erase(lost_label)
			ui_label_lost.emit(lost_label)
			WorldMemory.record_ambient("The word '%s' disappeared from your awareness." % lost_label)


func _check_decay_stage() -> void:
	var old_stage := _decay_stage

	if _witness_elapsed >= STAGE_MINIMAL:
		_decay_stage = 4
	elif _witness_elapsed >= STAGE_DISSOLVING:
		_decay_stage = 3
	elif _witness_elapsed >= STAGE_SIMPLIFYING:
		_decay_stage = 2
	elif _witness_elapsed >= STAGE_FADING:
		_decay_stage = 1
	else:
		_decay_stage = 0

	if old_stage != _decay_stage:
		witness_decay_tick.emit(_decay_stage, _witness_elapsed)
		_on_decay_stage_changed(old_stage, _decay_stage)


func _on_decay_stage_changed(_old: int, new_stage: int) -> void:
	match new_stage:
		1:
			WorldEventManager.event_notification.emit(
				"", "Colors drain from the edges first. You barely notice.")
		2:
			WorldEventManager.event_notification.emit(
				"", "A sound you didn't know existed stops. The world simplifies.")
		3:
			WorldEventManager.event_notification.emit(
				"", "Words lose their labels. Things are just shapes now. You remember what they were.")
		4:
			WorldEventManager.event_notification.emit(
				"", "Almost nothing left. Lines. Silence. The memory of a world.")


func _on_witness_mode_entered() -> void:
	_witness_elapsed = 0.0
	_decay_stage = 0


## Get current decay values for rendering systems.
func get_decay_state() -> Dictionary:
	return {
		"saturation": _texture_saturation,
		"complexity": _ambient_complexity,
		"active_sounds": _active_sounds,
		"active_labels": _active_labels.duplicate(),
		"stage": _decay_stage,
		"elapsed": _witness_elapsed,
	}


## Check if a UI label is still "active" (not yet decayed away).
func is_label_active(label_name: String) -> bool:
	return label_name in _active_labels


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"witness_elapsed": _witness_elapsed,
		"decay_stage": _decay_stage,
		"active_sounds": _active_sounds,
		"active_labels": _active_labels.duplicate(),
		"one_time_reactions": _one_time_reactions.duplicate(),
		"witness_objects": _witness_objects.duplicate(true),
	}


func load_state(data: Dictionary) -> void:
	_witness_elapsed = data.get("witness_elapsed", 0.0)
	_decay_stage = data.get("decay_stage", 0)
	_active_sounds = data.get("active_sounds", 10)
	_active_labels.clear()
	for label in data.get("active_labels", []):
		_active_labels.append(str(label))
	if _active_labels.size() == 0:
		_initialize_labels()
	_one_time_reactions = data.get("one_time_reactions", {})
	var loaded_objects = data.get("witness_objects", {})
	for obj_id in loaded_objects:
		if _witness_objects.has(obj_id):
			var obj_data: Dictionary = loaded_objects[obj_id]
			_witness_objects[obj_id]["used"] = obj_data.get("used", false)
			_witness_objects[obj_id]["interaction_index"] = obj_data.get("interaction_index", 0)
