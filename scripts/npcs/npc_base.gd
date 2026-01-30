## NPCBase — Interactable NPC with dialogue and force-reactive behavior.
class_name NPCBase
extends CharacterBody3D

@export var npc_name: String = "Stranger"
@export var force_affinity: String = "neutral"  # "faith", "truth", "violence", "neutral"

# Dialogue data — set in the editor or via code.
@export var dialogue_data: Array = []

# Whether this NPC has already been talked to
var has_spoken: bool = false

# Visual reaction state
var _mesh_node: MeshInstance3D = null
var _base_emission_energy: float = 0.3


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("npcs")

	# Cache mesh for visual reactions
	_mesh_node = _find_mesh()
	if _mesh_node and _mesh_node.get_surface_override_material(0):
		var mat: StandardMaterial3D = _mesh_node.get_surface_override_material(0)
		_base_emission_energy = mat.emission_energy_multiplier

	# React to force changes
	GameState.force_changed.connect(_on_force_changed)


## Called by PlayerController when player presses interact.
func interact(_player: Node) -> void:
	if DialogueManager.is_active:
		return

	var dialogue := _get_dialogue()
	if dialogue.size() > 0:
		DialogueManager.start_dialogue(dialogue, npc_name)
		has_spoken = true


## Override this to provide dynamic dialogue based on game state.
func _get_dialogue() -> Array:
	if dialogue_data.size() > 0:
		return dialogue_data

	# Default fallback dialogue with three-force choices
	return _default_dialogue()


func _default_dialogue() -> Array:
	var greeting := "..."
	var dominant := GameState.get_dominant_force()

	match force_affinity:
		"faith":
			if dominant == "faith":
				greeting = "The air hums. The old rites echo louder."
			elif dominant == "truth":
				greeting = "Your questions pull at the threads of what was certain."
			else:
				greeting = "Blood marks the ground here. The sacred and the brutal coexist."
		"truth":
			if dominant == "truth":
				greeting = "Every surface is legible now. The world hides less."
			elif dominant == "faith":
				greeting = "Belief shapes what people see. That is simply how it works."
			else:
				greeting = "Violence changes what was. Observation records what is."
		"violence":
			if dominant == "violence":
				greeting = "Strength rules here. That's how it is."
			else:
				greeting = "You haven't seen what I've seen."
		_:
			greeting = "Traveler. The ash settles around you."

	return [
		{"speaker": npc_name, "text": greeting},
		{"speaker": npc_name, "text": "What do you seek?",
			"choices": [
				{"text": "Guidance (Faith)", "force": "faith", "amount": 2.0},
				{"text": "Answers (Truth)", "force": "truth", "amount": 2.0},
				{"text": "Power (Violence)", "force": "violence", "amount": 2.0},
			]
		},
	]


func _on_force_changed(force_name: String, _old_value: float, new_value: float) -> void:
	if force_name != force_affinity or force_affinity == "neutral":
		return

	# Visual reaction: NPC glows brighter when their aligned force is strong
	if not _mesh_node:
		return

	var mat: Material = _mesh_node.get_surface_override_material(0)
	if not mat or not mat is StandardMaterial3D:
		return

	var std_mat := mat as StandardMaterial3D
	var intensity := new_value / 100.0
	std_mat.emission_energy_multiplier = _base_emission_energy + intensity * 1.5

	# Scale pulse at high force
	if new_value > 70.0:
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3(1.05, 1.1, 1.05), 0.2)
		tween.tween_property(self, "scale", Vector3.ONE, 0.3)


func _find_mesh() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null


func _exit_tree() -> void:
	if GameState and GameState.force_changed.is_connected(_on_force_changed):
		GameState.force_changed.disconnect(_on_force_changed)


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"has_spoken": has_spoken,
	}


func load_state(data: Dictionary) -> void:
	has_spoken = data.get("has_spoken", false)
