## HUD — Displays player health and the Three Forces.
extends Control

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var faith_bar: ProgressBar = $MarginContainer/VBoxContainer/ForceBars/FaithBar
@onready var truth_bar: ProgressBar = $MarginContainer/VBoxContainer/ForceBars/TruthBar
@onready var violence_bar: ProgressBar = $MarginContainer/VBoxContainer/ForceBars/ViolenceBar
@onready var interact_prompt: Label = $InteractPrompt


func _ready() -> void:
	GameState.force_changed.connect(_on_force_changed)
	interact_prompt.visible = false

	# Initialize
	_update_forces()
	_update_health()


func _process(_delta: float) -> void:
	_update_health()

	# Show interact prompt when player has a target
	var player := get_tree().get_first_node_in_group("player")
	if player and "current_interactable" in player:
		interact_prompt.visible = player.current_interactable != null
	else:
		interact_prompt.visible = false


func _on_force_changed(_force_name: String, _old_value: float, _new_value: float) -> void:
	_update_forces()


func _update_forces() -> void:
	faith_bar.value = GameState.faith
	truth_bar.value = GameState.truth
	violence_bar.value = GameState.violence


func _update_health() -> void:
	health_bar.value = (GameState.player_health / GameState.player_max_health) * 100.0
