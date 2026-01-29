## PauseMenu — Esc toggles. Shows force summary, faction standings, god states.
extends Control

@onready var force_summary: VBoxContainer = $Panel/MarginContainer/Tabs/Forces/ForceList
@onready var faction_summary: VBoxContainer = $Panel/MarginContainer/Tabs/Factions/FactionList
@onready var god_summary: VBoxContainer = $Panel/MarginContainer/Tabs/Gods/GodList

var _paused: bool = false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if DialogueManager.is_active:
			return
		_toggle_pause()


func _toggle_pause() -> void:
	_paused = not _paused
	visible = _paused
	get_tree().paused = _paused

	if _paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_refresh_all()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _refresh_all() -> void:
	_refresh_forces()
	_refresh_factions()
	_refresh_gods()


func _refresh_forces() -> void:
	_clear(force_summary)

	_add_force_row(force_summary, "Faith", GameState.faith, Color(0.6, 0.7, 1.0))
	_add_force_row(force_summary, "Truth", GameState.truth, Color(1.0, 1.0, 0.6))
	_add_force_row(force_summary, "Violence", GameState.violence, Color(1.0, 0.4, 0.3))

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	force_summary.add_child(spacer)

	var pressure_label := Label.new()
	pressure_label.text = "World Pressure: %.1f" % GameState.world_pressure
	pressure_label.add_theme_font_size_override("font_size", 13)
	pressure_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.3))
	force_summary.add_child(pressure_label)

	var dominant_label := Label.new()
	dominant_label.text = "Dominant: %s" % GameState.get_dominant_force().capitalize()
	dominant_label.add_theme_font_size_override("font_size", 13)
	force_summary.add_child(dominant_label)

	var tier_label := Label.new()
	tier_label.text = "Tier: %s" % ForceEffects.force_tier
	tier_label.add_theme_font_size_override("font_size", 12)
	tier_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	force_summary.add_child(tier_label)


func _add_force_row(parent: VBoxContainer, label_text: String, value: float, color: Color) -> void:
	var hbox := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size.x = 80
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(name_label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(180, 16)
	bar.max_value = 100.0
	bar.value = value
	bar.show_percentage = false
	hbox.add_child(bar)

	var val_label := Label.new()
	val_label.text = "%.0f" % value
	val_label.custom_minimum_size.x = 40
	val_label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(val_label)

	parent.add_child(hbox)


func _refresh_factions() -> void:
	_clear(faction_summary)

	for faction_id in FactionManager.faction_defs:
		var def: Dictionary = FactionManager.faction_defs[faction_id]
		var hbox := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = def.get("name", faction_id)
		name_label.custom_minimum_size.x = 180
		name_label.add_theme_font_size_override("font_size", 13)

		var alignment: String = def.get("force_alignment", "")
		match alignment:
			"faith":
				name_label.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
			"truth":
				name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
			"violence":
				name_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		hbox.add_child(name_label)

		var attitude := FactionManager.get_attitude(faction_id)
		var eff_rep := FactionManager.get_effective_reputation(faction_id)
		var att_label := Label.new()
		att_label.text = "%s (%.0f)" % [attitude.capitalize(), eff_rep]
		att_label.add_theme_font_size_override("font_size", 12)

		match attitude:
			"hostile":
				att_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
			"unfriendly":
				att_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.3))
			"friendly":
				att_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
			"allied":
				att_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			_:
				att_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		hbox.add_child(att_label)

		faction_summary.add_child(hbox)


func _refresh_gods() -> void:
	_clear(god_summary)

	for god_id in GodManager.god_defs:
		var def: Dictionary = GodManager.god_defs[god_id]
		var state := GodManager.get_god_state(god_id)
		var stability := GameState.get_god_stability(god_id)

		var hbox := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = def.get("name", god_id)
		name_label.custom_minimum_size.x = 200
		name_label.add_theme_font_size_override("font_size", 13)
		hbox.add_child(name_label)

		var state_label := Label.new()
		state_label.text = "%s (%.0f)" % [state.capitalize(), stability]
		state_label.add_theme_font_size_override("font_size", 12)

		match state:
			"dead":
				state_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			"fading":
				state_label.add_theme_color_override("font_color", Color(0.6, 0.5, 0.4))
			"weakened":
				state_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.4))
			"dormant":
				state_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			"manifest":
				state_label.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
			"ascended":
				state_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
		hbox.add_child(state_label)

		god_summary.add_child(hbox)


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
