## ZoneTrigger — Area3D that transitions the player to another zone.
class_name ZoneTrigger
extends Area3D

@export var target_zone_id: String = ""
@export var target_spawn_point: String = "default"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and target_zone_id != "":
		WorldManager.load_zone(target_zone_id, target_spawn_point)
