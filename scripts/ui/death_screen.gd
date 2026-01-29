## DeathScreen — Overlay shown when the player dies. Fades in, shows message, fades out on respawn.
extends Control

@onready var overlay: ColorRect = $Overlay
@onready var death_label: Label = $DeathMessage
@onready var force_hint: Label = $ForceHint

var _active: bool = false


func _ready() -> void:
	visible = false
	overlay.color = Color(0, 0, 0, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if _active:
		return

	if not GameState.player_alive and not _active:
		_show_death()


func _show_death() -> void:
	_active = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Pick message based on dominant force
	var dominant := GameState.get_dominant_force()
	match dominant:
		"faith":
			death_label.text = "The gods watch you fall."
			force_hint.text = "Faith: %.0f" % GameState.faith
			force_hint.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
		"truth":
			death_label.text = "Reality does not mourn."
			force_hint.text = "Truth: %.0f" % GameState.truth
			force_hint.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
		"violence":
			death_label.text = "The strong survive. You didn't."
			force_hint.text = "Violence: %.0f" % GameState.violence
			force_hint.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		_:
			death_label.text = "You have fallen."
			force_hint.text = ""

	# Fade in
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.85, 0.8)
	tween.parallel().tween_property(death_label, "modulate:a", 1.0, 1.0)
	tween.parallel().tween_property(force_hint, "modulate:a", 1.0, 1.2)

	# Wait for respawn
	await _wait_for_respawn()

	# Fade out
	var out_tween := create_tween()
	out_tween.tween_property(overlay, "color:a", 0.0, 0.5)
	out_tween.parallel().tween_property(death_label, "modulate:a", 0.0, 0.3)
	out_tween.parallel().tween_property(force_hint, "modulate:a", 0.0, 0.3)
	out_tween.tween_callback(_hide_death)


func _wait_for_respawn() -> void:
	while not GameState.player_alive:
		await get_tree().process_frame


func _hide_death() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_active = false
