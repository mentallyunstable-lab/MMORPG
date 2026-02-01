## HUD — Diegetic force feedback. No numbers, no popups. Only consequences.
## Violence = screen grain. Faith = golden warmth. Truth = UI misalignment.
extends Control

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var faith_bar: ProgressBar = $MarginContainer/VBoxContainer/ForceBars/FaithBar
@onready var truth_bar: ProgressBar = $MarginContainer/VBoxContainer/ForceBars/TruthBar
@onready var violence_bar: ProgressBar = $MarginContainer/VBoxContainer/ForceBars/ViolenceBar
@onready var interact_prompt: Label = $InteractPrompt

# Force colors (used internally for bar tinting, not for popups)
const FORCE_COLORS := {
	"faith": Color(0.6, 0.7, 1.0),
	"truth": Color(1.0, 1.0, 0.6),
	"violence": Color(1.0, 0.4, 0.3),
}

# --- Diegetic overlay layers ---
var _tint_overlay: ColorRect = null       # Force pulse tint
var _grain_overlay: ColorRect = null       # Violence screen grain
var _grain_noise_timer: float = 0.0

# Diegetic indicator state
var _violence_grain_intensity: float = 0.0  # 0=clean, 1=heavy grain
var _truth_flicker_timer: float = 0.0       # Countdown for UI misalignment
var _faith_warmth: float = 0.0              # 0=neutral, 1=golden glow


func _ready() -> void:
	GameState.force_changed.connect(_on_force_changed)
	interact_prompt.visible = false

	# Listen for witness mode
	if WorldEventManager.has_signal("witness_mode_entered"):
		WorldEventManager.witness_mode_entered.connect(_on_witness_mode)

	# Create tint overlay for force pulses (subtle color wash)
	_tint_overlay = ColorRect.new()
	_tint_overlay.color = Color(0, 0, 0, 0)
	_tint_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_tint_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint_overlay)
	move_child(_tint_overlay, 0)

	# Grain overlay for violence — rendered as semi-transparent noise pattern
	_grain_overlay = ColorRect.new()
	_grain_overlay.color = Color(0, 0, 0, 0)
	_grain_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_grain_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grain_overlay)
	move_child(_grain_overlay, 0)

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
		# Show stamina feedback — dim HUD when stamina is low (clamped for readability)
		if player.stamina < 20.0:
			modulate.a = maxf(lerpf(modulate.a, 0.6, _delta * 3.0), MIN_HUD_ALPHA)
		else:
			modulate.a = lerpf(modulate.a, 1.0, _delta * 3.0)
	else:
		interact_prompt.visible = false

	# Force bar glow at high thresholds
	_update_bar_effects(faith_bar, GameState.faith, FORCE_COLORS["faith"])
	_update_bar_effects(truth_bar, GameState.truth, FORCE_COLORS["truth"])
	_update_bar_effects(violence_bar, GameState.violence, FORCE_COLORS["violence"])

	# --- Diegetic indicators (every frame) ---
	_update_violence_grain(_delta)
	_update_truth_flicker(_delta)
	_update_faith_warmth(_delta)

	# Subtle save degradation — UI corruption at extreme states
	_apply_degradation_effects()


func _on_force_changed(force_name: String, old_value: float, new_value: float) -> void:
	_update_forces()

	# NO floating text. Only diegetic consequences.
	var delta_val := new_value - old_value
	if absf(delta_val) < 0.05:
		return

	# Diegetic pulse: a brief color wash that fades. No numbers.
	_pulse_screen_tint(force_name, delta_val)

	# Violence spike → screen grain burst
	if force_name == "violence" and delta_val > 0:
		_violence_grain_intensity = clampf(_violence_grain_intensity + delta_val * 0.02, 0.0, 0.6)

	# Truth spike → UI misalignment (bars offset briefly)
	if force_name == "truth" and delta_val > 0:
		_truth_flicker_timer = clampf(delta_val * 0.1, 0.2, 1.5)

	# Faith spike → warmth pulse
	if force_name == "faith" and delta_val > 0:
		_faith_warmth = clampf(_faith_warmth + delta_val * 0.03, 0.0, 0.5)


func _update_forces() -> void:
	faith_bar.value = GameState.faith
	truth_bar.value = GameState.truth
	violence_bar.value = GameState.violence


func _update_health() -> void:
	health_bar.value = (GameState.player_health / GameState.player_max_health) * 100.0


func _update_bar_effects(bar: ProgressBar, value: float, color: Color) -> void:
	if not bar:
		return
	if value >= 90.0:
		var flash := absf(sin(Time.get_ticks_msec() * 0.008))
		bar.modulate = color.lerp(Color.WHITE, flash * 0.6)
	elif value >= 70.0:
		bar.modulate = color.lerp(Color.WHITE, 0.3)
	else:
		bar.modulate = Color.WHITE


# --- Diegetic: Violence → Screen Grain ---
# Persistent grain that thickens with violence, fades slowly when violence drops.

func _update_violence_grain(delta: float) -> void:
	# Target grain based on current violence level
	var target := clampf(GameState.violence / 100.0, 0.0, 1.0) * 0.3
	_violence_grain_intensity = lerpf(_violence_grain_intensity, target, delta * 0.8)

	if _grain_overlay and _violence_grain_intensity > 0.01:
		# Simulate grain: rapidly flickering dark spots (approximated with alpha noise)
		_grain_noise_timer += delta
		if _grain_noise_timer > 0.05:  # 20fps grain update
			_grain_noise_timer = 0.0
			var r := randf_range(0.0, 0.15) * _violence_grain_intensity
			_grain_overlay.color = Color(r, 0, 0, _violence_grain_intensity * 0.4)
	elif _grain_overlay:
		_grain_overlay.color = Color(0, 0, 0, 0)


# --- Diegetic: Truth → UI Misalignment ---
# When truth spikes, UI elements shift slightly — reality becomes too precise.

func _update_truth_flicker(delta: float) -> void:
	if _truth_flicker_timer > 0:
		_truth_flicker_timer -= delta
		# Offset force bars slightly during flicker
		var offset := randf_range(-1.5, 1.5) * (_truth_flicker_timer / 1.5)
		if faith_bar:
			faith_bar.position.y = offset
		if truth_bar:
			truth_bar.position.y = -offset
		if violence_bar:
			violence_bar.position.y = offset * 0.5
	else:
		# Persistent truth-based micro-misalignment at high values
		var truth_t := GameState.truth / 100.0
		if truth_t > 0.5 and faith_bar and truth_bar and violence_bar:
			var micro := sin(Time.get_ticks_msec() * 0.003) * truth_t * 0.8
			faith_bar.position.y = micro
			truth_bar.position.y = -micro * 0.5
			violence_bar.position.y = micro * 0.3
		elif faith_bar:
			faith_bar.position.y = 0
			if truth_bar: truth_bar.position.y = 0
			if violence_bar: violence_bar.position.y = 0


# --- Diegetic: Faith → Golden Warmth ---
# High faith tints the screen warm. Not informational — atmospheric.

func _update_faith_warmth(delta: float) -> void:
	var target := clampf(GameState.faith / 100.0, 0.0, 1.0) * 0.15
	_faith_warmth = lerpf(_faith_warmth, target, delta * 0.5)

	if _tint_overlay and _faith_warmth > 0.01:
		# Blend the tint overlay toward muted amber — NOT golden-heroic.
		# This is atmospheric, not a "buff". Desaturated to avoid looking like a power-up.
		var current_a := _tint_overlay.color.a
		if current_a < 0.01:  # Only apply warmth when no pulse is active
			# Muted amber-brown, not bright gold — faith is pressure, not a blessing
			_tint_overlay.color = Color(0.7, 0.55, 0.35, _faith_warmth * 0.8)


## Brief screen tint pulse in force color when force changes. No numbers. Just color.
func _pulse_screen_tint(force_name: String, delta_val: float) -> void:
	if not _tint_overlay:
		return
	var color: Color = FORCE_COLORS.get(force_name, Color.WHITE)
	var intensity := clampf(absf(delta_val) / 20.0, 0.02, 0.12)
	_tint_overlay.color = Color(color.r, color.g, color.b, intensity)
	var tween := create_tween()
	tween.tween_property(_tint_overlay, "color:a", 0.0, 0.8)


## Subtle UI corruption after extreme states. Not explained.
## Accessibility guard: critical info (health, interact prompt) stays readable.
## Jitter is capped, alpha never drops below readable thresholds, glitch text is brief.

# Accessibility minimums
const MIN_HEALTH_ALPHA := 0.5  # Health bar never less visible than this
const MIN_HUD_ALPHA := 0.45    # Overall HUD never dimmer than this
const MAX_BAR_JITTER := 3.0    # Max pixel offset for force bar jitter
const GLITCH_REVERT_FRAMES := 3  # Frames before glitched text reverts to readable
var _glitch_frame_count := 0

func _apply_degradation_effects() -> void:
	var pressure := GameState.world_pressure

	# Bar jitter at high pressure — bars twitch slightly (capped for readability)
	if pressure >= 75.0:
		var jitter := (pressure - 75.0) / 25.0  # 0-1 at 75-100
		var max_offset := minf(jitter * 2.0, MAX_BAR_JITTER)
		if faith_bar:
			if not faith_bar.has_meta("_base_x"):
				faith_bar.set_meta("_base_x", faith_bar.position.x)
			faith_bar.position.x = faith_bar.get_meta("_base_x") + randf_range(-max_offset, max_offset)
		if truth_bar:
			if not truth_bar.has_meta("_base_x"):
				truth_bar.set_meta("_base_x", truth_bar.position.x)
			truth_bar.position.x = truth_bar.get_meta("_base_x") + randf_range(-max_offset, max_offset)
		if violence_bar:
			if not violence_bar.has_meta("_base_x"):
				violence_bar.set_meta("_base_x", violence_bar.position.x)
			violence_bar.position.x = violence_bar.get_meta("_base_x") + randf_range(-max_offset, max_offset)

	# Health bar flickers when ending has triggered (accessibility: clamped alpha)
	if GameState.save_closed and health_bar:
		health_bar.modulate.a = maxf(MIN_HEALTH_ALPHA, 0.3 + randf() * 0.4)

	# Interact prompt glitches at extreme states (accessibility: auto-reverts quickly)
	if interact_prompt and interact_prompt.visible and pressure >= 85.0:
		if randf() < 0.05 and _glitch_frame_count <= 0:
			interact_prompt.text = "[???]"
			_glitch_frame_count = GLITCH_REVERT_FRAMES
		elif _glitch_frame_count > 0:
			_glitch_frame_count -= 1
			if _glitch_frame_count <= 0:
				interact_prompt.text = "[E] Interact"
		else:
			interact_prompt.text = "[E] Interact"

	# Witness mode: decay the entire HUD gradually
	if GameState.witness_mode:
		_apply_witness_decay(_delta)


# --- Witness Mode HUD Decay (Phase 5) ---
# In witness mode: bars fade, colors desaturate, interact prompt becomes mournful.
var _witness_decay_progress: float = 0.0

func _on_witness_mode() -> void:
	_witness_decay_progress = 0.0

func _apply_witness_decay(delta: float) -> void:
	_witness_decay_progress = minf(_witness_decay_progress + delta * 0.02, 1.0)

	# Desaturate all bars
	var desat := _witness_decay_progress
	if faith_bar:
		faith_bar.modulate = faith_bar.modulate.lerp(Color(0.5, 0.5, 0.5, 0.4), desat)
	if truth_bar:
		truth_bar.modulate = truth_bar.modulate.lerp(Color(0.5, 0.5, 0.5, 0.4), desat)
	if violence_bar:
		violence_bar.modulate = violence_bar.modulate.lerp(Color(0.5, 0.5, 0.5, 0.4), desat)

	# Health bar fades to nothing — you can't die anymore
	if health_bar:
		health_bar.modulate.a = maxf(1.0 - _witness_decay_progress, 0.1)

	# Interact prompt changes
	if interact_prompt and interact_prompt.visible:
		interact_prompt.text = "[E] Remember"

	# Tint overlay goes grey
	if _tint_overlay:
		_tint_overlay.color = Color(0.3, 0.3, 0.3, _witness_decay_progress * 0.15)
