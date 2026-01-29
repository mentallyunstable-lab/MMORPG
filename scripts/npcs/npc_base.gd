## NPCBase — Interactable NPC with dialogue and force-reactive behavior.
class_name NPCBase
extends CharacterBody3D

@export var npc_name: String = "Stranger"
@export var force_affinity: String = "neutral"  # "faith", "truth", "violence", "neutral"

# Dialogue data — set in the editor or via code.
@export var dialogue_data: Array = []

# Whether this NPC has already been talked to
var has_spoken: bool = false


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("npcs")

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
				greeting = "The gods smile upon this land."
			elif dominant == "truth":
				greeting = "Your questioning shakes the pillars of belief..."
			else:
				greeting = "Blood stains even the sacred ground."
		"truth":
			if dominant == "truth":
				greeting = "Reality becomes clearer."
			elif dominant == "faith":
				greeting = "Blind faith clouds what is real."
			else:
				greeting = "Violence solves nothing — only reveals."
		"violence":
			if dominant == "violence":
				greeting = "Strength rules. As it should."
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


func _on_force_changed(force_name: String, _old_value: float, _new_value: float) -> void:
	# NPCs with matching affinity could visually react (glow, change stance, etc.)
	if force_name == force_affinity:
		pass  # Placeholder for visual reactions


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"has_spoken": has_spoken,
	}


func load_state(data: Dictionary) -> void:
	has_spoken = data.get("has_spoken", false)
