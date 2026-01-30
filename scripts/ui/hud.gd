## HUD — Displays player health, Three Forces, floating text, and force bar effects.
extends Control

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var faith_bar: ProgressBar = $MarginContainer/VBoxContainer/ForceBars/FaithBar
@onready var truth_bar: ProgressBar = $MarginContainer/VBoxContainer/ForceBars/TruthBar
@onready var violence_bar: ProgressBar = $MarginContainer/VBoxContainer/ForceBars/ViolenceBar
@onready var interact_prompt: Label = $InteractPrompt

# Force colors
const FORCE_COLORS := {
	"faith": Color(0.6, 0.7, 1.0),
	"truth": Color(1.0, 1.0, 0.6),
	"violence": Color(1.0, 0.4, 0.3),
}

# Screen tint for force feedback
var _tint_overlay: ColorRect = null


func _ready() -> void:
	GameState.force_changed.connect(_on_force_changed)
	interact_prompt.visible = false

	# Create tint overlay for force pulses
	_tint_overlay = ColorRect.new()
	_tint_overlay.color = Color(0, 0, 0, 0)
	_tint_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_tint_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint_overlay)
	move_child(_tint_overlay, 0)

	# Initialize
	_update_forces()
	_update_health()


func _exit_tree() -> void:
	if GameState and GameState.force_changed.is_connected(_on_force_changed):
		GameState.force_changed.disconnect(_on_force_changed)


func _process(_delta: float) -> void:
	_update_health()

	# Show interact prompt when player has a target
	var player := get_tree().get_first_node_in_group("player")
	if player and player is PlayerController:
		interact_prompt.visible = player.current_interactable != null
		# Show stamina feedback — dim HUD when stamina is low
		if player.stamina < 20.0:
			modulate.a = lerpf(modulate.a, 0.6, _delta * 3.0)
		else:
			modulate.a = lerpf(modulate.a, 1.0, _delta * 3.0)
	else:
		interact_prompt.visible = false

	# Force bar glow at high thresholds
	_update_bar_effects(faith_bar, GameState.faith, FORCE_COLORS["faith"])
	_update_bar_effects(truth_bar, GameState.truth, FORCE_COLORS["truth"])
	_update_bar_effects(violence_bar, GameState.violence, FORCE_COLORS["violence"])

	# Subtle save degradation — UI corruption at extreme states
	_apply_degradation_effects()


func _on_force_changed(force_name: String, old_value: float, new_value: float) -> void:
	_update_forces()

	# Floating text feedback
	var delta_val := new_value - old_value
	if absf(delta_val) >= 0.05:
		_spawn_floating_text(force_name, delta_val)
		_pulse_screen_tint(force_name, delta_val)


func _update_forces() -> void:
	faith_bar.value = GameState.faith
	truth_bar.value = GameState.truth
	violence_bar.value = GameState.violence


func _update_health() -> void:
	health_bar.value = (GameState.player_health / GameState.player_max_health) * 100.0


func _update_bar_effects(bar: ProgressBar, value: float, color: Color) -> void:
	if not bar:
		return
	var stylebox := bar.get("theme_override_styles/fill") as StyleBox
	if value >= 90.0:
		# Flash at critical
		var flash := absf(sin(Time.get_ticks_msec() * 0.008))
		bar.modulate = color.lerp(Color.WHITE, flash * 0.6)
	elif value >= 70.0:
		# Glow at high
		bar.modulate = color.lerp(Color.WHITE, 0.3)
	else:
		bar.modulate = Color.WHITE


## Spawn floating text like "+5 Faith" or "-2 Truth" near the force bars.
func _spawn_floating_text(force_name: String, delta_val: float) -> void:
	var label := Label.new()
	var sign_str := "+" if delta_val > 0 else ""
	label.text = "%s%.1f %s" % [sign_str, delta_val, force_name.capitalize()]
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", FORCE_COLORS.get(force_name, Color.WHITE))
	label.position = Vector2(330, 60)
	label.z_index = 10
	add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40, 1.2)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.2)
	tween.tween_callback(label.queue_free)


## Brief screen tint pulse in force color when force changes.
func _pulse_screen_tint(force_name: String, delta_val: float) -> void:
	if not _tint_overlay:
		return
	var color: Color = FORCE_COLORS.get(force_name, Color.WHITE)
	var intensity := clampf(absf(delta_val) / 20.0, 0.02, 0.15)
	_tint_overlay.color = Color(color.r, color.g, color.b, intensity)
	var tween := create_tween()
	tween.tween_property(_tint_overlay, "color:a", 0.0, 0.6)


## Subtle UI corruption after extreme states. Not explained.
func _apply_degradation_effects() -> void:
	var pressure := GameState.world_pressure

	# Bar jitter at high pressure — bars twitch slightly
	if pressure >= 75.0:
		var jitter := (pressure - 75.0) / 25.0  # 0-1 at 75-100
		if faith_bar:
			faith_bar.position.x = faith_bar.get_meta("_base_x", faith_bar.position.x) + randf_range(-jitter * 2.0, jitter * 2.0)
			if not faith_bar.has_meta("_base_x"):
				faith_bar.set_meta("_base_x", faith_bar.position.x)
		if truth_bar:
			truth_bar.position.x = truth_bar.get_meta("_base_x", truth_bar.position.x) + randf_range(-jitter * 2.0, jitter * 2.0)
			if not truth_bar.has_meta("_base_x"):
				truth_bar.set_meta("_base_x", truth_bar.position.x)
		if violence_bar:
			violence_bar.position.x = violence_bar.get_meta("_base_x", violence_bar.position.x) + randf_range(-jitter * 2.0, jitter * 2.0)
			if not violence_bar.has_meta("_base_x"):
				violence_bar.set_meta("_base_x", violence_bar.position.x)

	# Health bar flickers when ending has triggered
	if GameState.save_closed and health_bar:
		health_bar.modulate.a = 0.3 + randf() * 0.4  # Ghostly flicker

	# Interact prompt glitches at extreme states
	if interact_prompt and interact_prompt.visible and pressure >= 85.0:
		if randf() < 0.05:  # 5% chance per frame
			interact_prompt.text = "[???]"
		else:
			interact_prompt.text = "[E] Interact"
