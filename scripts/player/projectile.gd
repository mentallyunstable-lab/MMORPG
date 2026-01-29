## Projectile — Flies forward, damages enemies on contact, adds violence force.
class_name Projectile
extends Area3D

var direction := Vector3.ZERO
var speed := 30.0
var damage := 15.0
var lifetime := 3.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage, global_position)
		GameState.add_force("violence", 0.3)
	if not body.is_in_group("player"):
		queue_free()
