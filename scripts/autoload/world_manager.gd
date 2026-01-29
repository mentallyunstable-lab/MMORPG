## WorldManager — Handles zone loading, transitions, and persistent zone state.
extends Node

signal zone_loaded(zone_id: String)
signal zone_unloaded(zone_id: String)

const ZONE_DIR := "res://scenes/world/"

var current_zone_id: String = ""
var current_zone_node: Node = null

# Persistent per-zone data (enemy states, opened chests, etc.)
var zone_persistent_data: Dictionary = {}


func _ready() -> void:
	pass


## Load a zone scene by ID (filename without extension).
## Optionally place the player at a spawn_point name within the zone.
func load_zone(zone_id: String, spawn_point: String = "default") -> void:
	# Save current zone state before leaving
	if current_zone_node:
		_save_zone_state(current_zone_id, current_zone_node)
		current_zone_node.queue_free()
		zone_unloaded.emit(current_zone_id)

	var scene_path := ZONE_DIR + zone_id + ".tscn"
	var scene := load(scene_path) as PackedScene
	if not scene:
		push_error("WorldManager: Failed to load zone '%s' at '%s'" % [zone_id, scene_path])
		return

	current_zone_id = zone_id
	current_zone_node = scene.instantiate()
	get_tree().root.add_child(current_zone_node)

	# Restore persistent data if we've been here before
	_restore_zone_state(zone_id, current_zone_node)

	# Mark region as visited in GameState
	GameState.set_region_value(zone_id, "visited", true)

	# Position player at spawn point
	_move_player_to_spawn(current_zone_node, spawn_point)

	zone_loaded.emit(zone_id)


func _save_zone_state(zone_id: String, zone_node: Node) -> void:
	var data := {}

	# Save state of all enemies (alive/dead, position)
	for enemy in zone_node.get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("save_state"):
			data[enemy.name] = enemy.save_state()

	# Save interactable states
	for obj in zone_node.get_tree().get_nodes_in_group("interactables"):
		if obj.has_method("save_state"):
			data[obj.name] = obj.save_state()

	zone_persistent_data[zone_id] = data


func _restore_zone_state(zone_id: String, zone_node: Node) -> void:
	if not zone_persistent_data.has(zone_id):
		return

	var data: Dictionary = zone_persistent_data[zone_id]

	for enemy in zone_node.get_tree().get_nodes_in_group("enemies"):
		if data.has(enemy.name) and enemy.has_method("load_state"):
			enemy.load_state(data[enemy.name])

	for obj in zone_node.get_tree().get_nodes_in_group("interactables"):
		if data.has(obj.name) and obj.has_method("load_state"):
			obj.load_state(data[obj.name])


func _move_player_to_spawn(zone_node: Node, spawn_name: String) -> void:
	var spawn := zone_node.find_child("SpawnPoint_" + spawn_name, true, false)
	if not spawn and spawn_name != "default":
		spawn = zone_node.find_child("SpawnPoint_default", true, false)
	if not spawn:
		return

	var player := get_tree().get_first_node_in_group("player")
	if player and spawn is Node3D:
		player.global_position = (spawn as Node3D).global_position
