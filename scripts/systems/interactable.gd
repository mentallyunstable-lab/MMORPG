## Interactable — Base class for world objects the player can interact with.
## Extend this for chests, levers, shrines, lore items, zone transitions, etc.
class_name Interactable
extends StaticBody3D

@export var interaction_text: String = "Interact"
@export var one_time: bool = false

var has_been_used: bool = false


func _ready() -> void:
	add_to_group("interactables")


## Called by PlayerController.
func interact(player: Node) -> void:
	if one_time and has_been_used:
		return
	has_been_used = true
	_on_interact(player)


## Override in subclasses to define behavior.
func _on_interact(_player: Node) -> void:
	pass


func save_state() -> Dictionary:
	return {"has_been_used": has_been_used}


func load_state(data: Dictionary) -> void:
	has_been_used = data.get("has_been_used", false)
