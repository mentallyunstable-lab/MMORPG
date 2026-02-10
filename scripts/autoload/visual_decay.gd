## VisualDecay — The presentation layer. Makes the world's psychological systems VISIBLE.
## This system connects to AnchorStrain, SilenceFallout, TrustDestruction, and AntiSaveScum
## to produce visual effects the player SEES without explanation.
##
## Subsystems:
##   1.1 Truth Strain Visuals — UI jitter, punctuation flicker, alignment drift
##   1.2 Silence Fallout Visuals — light temperature shift, NPC desync, prop loop overshoot
##   2.1 Dialogue Damage — dead air, blink stop, clipped speech, wrong finishes
##   2.2 Social Decay — NPC repositioning, crowd gaps
##   4.1 False Stability Zone — one zone that's TOO clean (TWIST: honest metric decays faster)
##   5.1 Reload Detection Feedback — slower save UI, altered scene blocking, save shame
##   6.1 Keeper Presence — render priority, text timing, pixel-perfect immunity
##   7.1 The Last Honest Metric — one environmental stat that only goes one direction
##   9   Decay-Free Windows — rare clean moments that end abruptly
##   10  Visual Decay Phasing — easing curves shift, transitions stop completing
##   12  NPC Eye Behavior — look-past, held contact, Keeper perfection
##
## RULE: No tooltips. No explanations. Ever.
extends Node

# --- Signals for UI/world systems to react to ---
signal truth_strain_jitter_changed(intensity: float)
signal silence_light_shift(kelvin_offset: float)
signal npc_desync_active(is_active: bool)
signal social_decay_level_changed(level: float)
signal reload_sluggishness_changed(factor: float)
signal honest_metric_changed(metric_name: String, value: float)
signal decay_free_window_changed(is_active: bool)
signal save_shame_event(shame_type: String)

# ============================================================
# 1.1 — TRUTH STRAIN VISUAL LAYER
# ============================================================
# UI text jitter when truth strain > 0.4
# Punctuation flicker when > 0.6
# UI alignment permanently off-center when > 0.8

# Jitter intensity (0.0 = none, 1.0 = max)
var ui_jitter_intensity: float = 0.0

# Punctuation flicker state
var punctuation_flicker_active: bool = false
var _punctuation_flicker_timer: float = 0.0
const PUNCTUATION_FLICKER_INTERVAL := 0.15  # How often punctuation glitches

# Alignment drift — once triggered at >0.8, NEVER snaps back
var alignment_drift_triggered: bool = false
var alignment_drift_offset: Vector2 = Vector2.ZERO
const ALIGNMENT_DRIFT_MAX := 3.0  # Max pixels off-center

# Thresholds (truth strain is 0-100, normalized to 0-1 for visuals)
const JITTER_THRESHOLD := 0.4
const FLICKER_THRESHOLD := 0.6
const DRIFT_THRESHOLD := 0.8


# ============================================================
# 1.2 — SILENCE FALLOUT VISUALS
# ============================================================
# Post-silence: light temperature shifts colder
# NPC idle animations desync
# Environmental props loop one extra frame too long

# Light temperature offset in Kelvin (negative = colder)
var light_kelvin_offset: float = 0.0
const SILENCE_KELVIN_SHIFT_MIN := -300.0
const SILENCE_KELVIN_SHIFT_MAX := -600.0
const KELVIN_RECOVERY_RATE := 30.0  # Kelvin per second recovery

# NPC idle desync — offset in seconds applied to animation timing
var npc_idle_desync_ms: float = 0.0
const NPC_DESYNC_AMOUNT := 200.0  # ±200ms
var _desync_active: bool = false

# Prop loop overshoot — extra frames on looping env animations
var prop_loop_overshoot_frames: int = 0
const PROP_OVERSHOOT_AMOUNT := 1  # 1 extra frame


# ============================================================
# 2.2 — SOCIAL DECAY
# ============================================================
# NPCs physically move farther from player over time
# Crowds form gaps around the player (no collision change)

# Social decay level (0.0 = normal, 1.0 = maximum isolation)
var social_decay_level: float = 0.0
const SOCIAL_DECAY_RATE := 0.001  # Per second when conditions are met
const SOCIAL_DECAY_RECOVERY := 0.0005  # Per second when conditions improve
const SOCIAL_DECAY_DISTANCE_MULT := 2.5  # At max: NPCs 2.5x farther


# ============================================================
# 4.1 — FALSE STABILITY ZONE (with 13: THE TWIST)
# ============================================================
# Tracked per-zone: is the player in the "too clean" zone?
# TWIST: honest metric decays FASTER inside, not slower.
# NPC rigidity reads as "calm competence" not malfunction.
# Leaving restores glitches but improves outcomes.
var in_false_stability_zone: bool = false
var false_stability_time_spent: float = 0.0
const FALSE_STABILITY_RIGIDITY_ONSET := 60.0  # Seconds before NPCs get rigid
const FALSE_STABILITY_NARROWING_ONSET := 120.0  # Seconds before options narrow
const FALSE_STABILITY_HONEST_DECAY_MULT := 2.5  # Honest metric decays 2.5x faster here


# ============================================================
# 5.1 — RELOAD DETECTION FEEDBACK (with 14: SAVE SHAME)
# ============================================================
# Save/load screen animation slowdown after detected hesitation/scumming
# Scene blocking subtly altered after reload
# 14: Save thumbnail updates late, load text before bg, one-per-run worsening

var reload_sluggishness: float = 1.0  # 1.0 = normal, 1.3 = 30% slower
const RELOAD_SLOWDOWN_AMOUNT := 0.3  # Added to animation speed on detection
const RELOAD_SLOWDOWN_DECAY := 0.01  # Decay per second back to 1.0

# Scene blocking offset — subtle positional shift after reload
var reload_blocking_offset: Vector3 = Vector3.ZERO
const RELOAD_BLOCKING_MAX_OFFSET := 0.5  # Meters

# 14: Save shame — once per run, a successful reload makes things worse
var _save_shame_used_this_run: bool = false
var save_thumbnail_delay_active: bool = false  # Save slot thumbnail updates late
var load_text_before_bg: bool = false  # Load screen text appears before background


# ============================================================
# 6.1 — KEEPER PRESENCE VISUAL RULES
# ============================================================
# Keeper text renders 1 frame earlier than all other text
# Keeper never overlaps corrupted UI layers
# Keeper UI is always pixel-perfect (immune to jitter/drift)

var keeper_render_frame_advance: int = 1  # Frames ahead of other text
var keeper_immune_to_visual_decay: bool = true  # Always true. Non-negotiable.


# ============================================================
# 7.1 — THE LAST HONEST METRIC
# ============================================================
# One environmental stat that only moves in ONE direction.
# We pick: NPC survival time near the player.
# It only goes DOWN. Never recovers.

var honest_metric_npc_survival: float = 100.0  # Starts at 100, only decreases
const HONEST_METRIC_DECAY_RATE := 0.05  # Per second when conditions are bad
const HONEST_METRIC_FLOOR := 5.0  # Never hits zero — always a trace
var _honest_metric_name: String = "npc_proximity_endurance"


# ============================================================
# 9 — DECAY-FREE WINDOWS
# ============================================================
# Rare 20-40s windows where NOTHING is wrong.
# No jitter. No pauses. NPCs speak cleanly.
# Never twice in a row. End abruptly, not fade.
# Keeper behaves exactly the same (this matters).

var decay_free_active: bool = false
var _decay_free_timer: float = 0.0
var _decay_free_duration: float = 0.0
var _decay_free_cooldown: float = 0.0
var _last_window_was_decay_free: bool = false  # Never twice in a row
const DECAY_FREE_CHECK_INTERVAL := 30.0  # Check every 30s if we should trigger
const DECAY_FREE_CHANCE := 0.06  # 6% chance per check
const DECAY_FREE_DURATION_MIN := 20.0
const DECAY_FREE_DURATION_MAX := 40.0
const DECAY_FREE_COOLDOWN_MIN := 180.0  # At least 3 min between windows
const DECAY_FREE_COOLDOWN_MAX := 420.0  # Up to 7 min
var _decay_free_check_timer: float = 0.0


# ============================================================
# 10 — VISUAL DECAY PHASING
# ============================================================
# At strain >0.6: UI animation easing switches from smooth to snap
# At strain >0.8: UI transitions stop completing (freeze at 70-90%)
# Keeper transitions always complete fully.
# Different movement logic reads subconsciously as "the world changed".

## 0.0 = smooth ease-out, 1.0 = hard snap (no easing)
var ui_easing_hardness: float = 0.0
const EASING_SNAP_THRESHOLD := 0.6

## 0.0 = transitions complete, 1.0 = transitions freeze at ~80%
var transition_incompleteness: float = 0.0
const TRANSITION_FREEZE_THRESHOLD := 0.8


# ============================================================
# 12 — NPC EYE BEHAVIOR
# ============================================================
# At low honest metric: NPCs look past the player
# During silence fallout: Eye contact holds 300ms too long, then snaps away
# Keeper eye contact is perfectly timed, always

## Eye behavior mode for current frame
## "normal" = standard look-at, "past" = looking 1-3m behind player,
## "held" = locked eye contact (too long), "snap_away" = just broke contact
var npc_eye_mode: String = "normal"
var _eye_held_timer: float = 0.0
const EYE_HOLD_DURATION := 0.3  # 300ms too long
const EYE_SNAP_DURATION := 0.15  # Quick snap away after hold

## Look-past offset (meters behind player that NPCs look at)
var npc_look_past_offset: float = 0.0
const LOOK_PAST_MAX_OFFSET := 3.0  # meters


# ============================================================
# TIMING
# ============================================================
const VISUAL_UPDATE_INTERVAL := 0.1  # 10 Hz visual update
var _update_timer: float = 0.0


func _ready() -> void:
	# Connect to backend systems
	AnchorStrain.strain_threshold_crossed.connect(_on_strain_threshold)
	SilenceFallout.silence_fallout_active.connect(_on_silence_fallout_changed)
	SilenceFallout.audio_glitch_window_active.connect(_on_audio_glitch_window)
	AntiSaveScum.scum_detected.connect(_on_scum_detected)
	AntiSaveScum.hesitation_detected.connect(_on_hesitation_detected)
	AnchorManager.anchor_state_changed.connect(_on_anchor_state_changed)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < VISUAL_UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	# 9: Decay-free window management (runs regardless of toggles)
	_update_decay_free_window(VISUAL_UPDATE_INTERVAL)

	if not (DevToggles and DevToggles.disable_truth_strain_visuals):
		_update_truth_strain_visuals()
	if not (DevToggles and DevToggles.disable_silence_visuals):
		_update_silence_visuals(VISUAL_UPDATE_INTERVAL)
	if not (DevToggles and DevToggles.disable_social_decay):
		_update_social_decay(VISUAL_UPDATE_INTERVAL)
	_update_false_stability(VISUAL_UPDATE_INTERVAL)
	_update_reload_feedback(VISUAL_UPDATE_INTERVAL)
	if not (DevToggles and DevToggles.disable_honest_metric):
		_update_honest_metric(VISUAL_UPDATE_INTERVAL)

	# 10: Visual decay phasing
	_update_decay_phasing()

	# 12: NPC eye behavior
	_update_eye_behavior(VISUAL_UPDATE_INTERVAL)


# ============================================================
# 9 — DECAY-FREE WINDOW UPDATE
# ============================================================

func _update_decay_free_window(delta: float) -> void:
	if decay_free_active:
		_decay_free_timer += delta
		if _decay_free_timer >= _decay_free_duration:
			# End ABRUPTLY. No fade. Just gone.
			decay_free_active = false
			_last_window_was_decay_free = true
			_decay_free_cooldown = randf_range(DECAY_FREE_COOLDOWN_MIN, DECAY_FREE_COOLDOWN_MAX)
			decay_free_window_changed.emit(false)
		return

	# Cooldown
	if _decay_free_cooldown > 0.0:
		_decay_free_cooldown -= delta
		return

	# Check trigger
	_decay_free_check_timer += delta
	if _decay_free_check_timer < DECAY_FREE_CHECK_INTERVAL:
		return
	_decay_free_check_timer = 0.0

	# Never twice in a row
	if _last_window_was_decay_free:
		_last_window_was_decay_free = false
		return

	# Only trigger when there's actual decay happening (otherwise pointless)
	var strain_norm := AnchorStrain.anchor_strain / 100.0
	if strain_norm < 0.3 and TrustDestruction.trust_level > 0.8:
		return  # Nothing to contrast against

	if randf() < DECAY_FREE_CHANCE:
		decay_free_active = true
		_decay_free_timer = 0.0
		_decay_free_duration = randf_range(DECAY_FREE_DURATION_MIN, DECAY_FREE_DURATION_MAX)
		decay_free_window_changed.emit(true)


## Is the decay-free window currently suppressing all visual decay?
## UI/dialogue systems check this before applying any corruption.
## Keeper behaves EXACTLY the same during these windows.
func is_decay_free() -> bool:
	return decay_free_active


# ============================================================
# 10 — VISUAL DECAY PHASING UPDATE
# ============================================================

func _update_decay_phasing() -> void:
	var strain_norm := AnchorStrain.anchor_strain / 100.0

	# Easing hardness: at >0.6, transitions snap instead of easing
	if strain_norm > EASING_SNAP_THRESHOLD:
		var t := (strain_norm - EASING_SNAP_THRESHOLD) / (1.0 - EASING_SNAP_THRESHOLD)
		ui_easing_hardness = clampf(t, 0.0, 1.0)
	else:
		ui_easing_hardness = 0.0

	# Transition incompleteness: at >0.8, UI elements stop finishing animations
	if strain_norm > TRANSITION_FREEZE_THRESHOLD:
		var t := (strain_norm - TRANSITION_FREEZE_THRESHOLD) / (1.0 - TRANSITION_FREEZE_THRESHOLD)
		transition_incompleteness = clampf(t * 0.3, 0.0, 0.3)  # Max 30% incomplete
	else:
		transition_incompleteness = 0.0


## Get the completion fraction for a UI transition.
## At 0 incompleteness: returns 1.0 (fully complete).
## At max: returns 0.7-0.9 (freezes before finishing).
## Keeper transitions always return 1.0.
func get_transition_completion(is_keeper: bool = false) -> float:
	if is_keeper:
		return 1.0  # Keeper always completes
	if decay_free_active:
		return 1.0
	if transition_incompleteness <= 0.0:
		return 1.0
	return 1.0 - transition_incompleteness * randf_range(0.7, 1.0)


## Get the easing curve power for UI animations.
## 1.0 = normal ease-out, higher = snappier (approaches step function).
## Keeper always returns 1.0.
func get_easing_power(is_keeper: bool = false) -> float:
	if is_keeper:
		return 1.0
	if decay_free_active:
		return 1.0
	return 1.0 + ui_easing_hardness * 4.0  # 1.0 to 5.0


# ============================================================
# 12 — NPC EYE BEHAVIOR UPDATE
# ============================================================

func _update_eye_behavior(delta: float) -> void:
	var endurance := honest_metric_npc_survival
	var in_fallout := SilenceFallout.is_in_fallout_window() or SilenceFallout.is_active

	# During silence fallout: eye contact holds too long
	if in_fallout:
		if npc_eye_mode == "normal" or npc_eye_mode == "past":
			npc_eye_mode = "held"
			_eye_held_timer = 0.0
		elif npc_eye_mode == "held":
			_eye_held_timer += delta
			if _eye_held_timer >= EYE_HOLD_DURATION:
				npc_eye_mode = "snap_away"
				_eye_held_timer = 0.0
		elif npc_eye_mode == "snap_away":
			_eye_held_timer += delta
			if _eye_held_timer >= EYE_SNAP_DURATION:
				npc_eye_mode = "held"  # Cycle back
				_eye_held_timer = 0.0
		return

	# Low honest metric: NPCs look past the player
	if endurance < 50.0:
		npc_eye_mode = "past"
		# Offset scales with how degraded the metric is
		var t := 1.0 - clampf((endurance - HONEST_METRIC_FLOOR) / (50.0 - HONEST_METRIC_FLOOR), 0.0, 1.0)
		npc_look_past_offset = t * LOOK_PAST_MAX_OFFSET
	else:
		npc_eye_mode = "normal"
		npc_look_past_offset = 0.0


## Get the eye target offset for an NPC looking at the player.
## Returns a world-space offset to add to the player's position.
## Keeper ALWAYS returns Vector3.ZERO (perfect eye contact).
func get_npc_eye_target_offset(is_keeper: bool = false) -> Vector3:
	if is_keeper:
		return Vector3.ZERO  # Keeper eye contact is perfectly timed, always
	if decay_free_active:
		return Vector3.ZERO

	match npc_eye_mode:
		"past":
			# Look 1-3m behind the player (through them)
			return Vector3(0, 0, npc_look_past_offset)
		"held":
			return Vector3.ZERO  # Direct eye contact (too long)
		"snap_away":
			# Look sharply to the side
			var side := 1.0 if randf() > 0.5 else -1.0
			return Vector3(side * 2.0, 0.3, 0)
		_:
			return Vector3.ZERO


## Is this NPC currently in the "held too long" eye contact state?
func is_eye_contact_held() -> bool:
	return npc_eye_mode == "held" and not decay_free_active


# ============================================================
# 1.1 — TRUTH STRAIN VISUAL UPDATE
# ============================================================

func _update_truth_strain_visuals() -> void:
	var strain_normalized := AnchorStrain.anchor_strain / 100.0

	# 9: During decay-free windows, suppress all strain visuals
	if decay_free_active:
		ui_jitter_intensity = 0.0
		punctuation_flicker_active = false
		truth_strain_jitter_changed.emit(0.0)
		return

	# Jitter: 1-2px at >0.4 strain, scales up
	if strain_normalized > JITTER_THRESHOLD:
		var jitter_t := (strain_normalized - JITTER_THRESHOLD) / (1.0 - JITTER_THRESHOLD)
		ui_jitter_intensity = lerpf(0.0, 2.0, jitter_t)
	else:
		ui_jitter_intensity = 0.0

	# Punctuation flicker at >0.6
	punctuation_flicker_active = strain_normalized > FLICKER_THRESHOLD

	# Alignment drift at >0.8 — PERMANENT once triggered
	if strain_normalized > DRIFT_THRESHOLD and not alignment_drift_triggered:
		alignment_drift_triggered = true
		alignment_drift_offset = Vector2(
			randf_range(-ALIGNMENT_DRIFT_MAX, ALIGNMENT_DRIFT_MAX),
			randf_range(-ALIGNMENT_DRIFT_MAX * 0.5, ALIGNMENT_DRIFT_MAX * 0.5)
		)

	truth_strain_jitter_changed.emit(ui_jitter_intensity)


## Get a jittered position offset for UI elements. Call per-frame in UI scripts.
func get_ui_jitter() -> Vector2:
	if decay_free_active:
		return Vector2.ZERO
	if ui_jitter_intensity <= 0.0:
		return Vector2.ZERO
	return Vector2(
		randf_range(-ui_jitter_intensity, ui_jitter_intensity),
		randf_range(-ui_jitter_intensity, ui_jitter_intensity)
	)


## Get permanent alignment drift offset.
func get_alignment_drift() -> Vector2:
	if not alignment_drift_triggered:
		return Vector2.ZERO
	return alignment_drift_offset


## Process text for punctuation flicker. Call before displaying dialogue text.
func apply_punctuation_flicker(text: String) -> String:
	if decay_free_active:
		return text
	if not punctuation_flicker_active:
		return text
	_punctuation_flicker_timer += VISUAL_UPDATE_INTERVAL
	if _punctuation_flicker_timer < PUNCTUATION_FLICKER_INTERVAL:
		return text
	_punctuation_flicker_timer = 0.0

	# Randomly remove or elongate punctuation
	if randf() < 0.3:
		# Remove a period
		var idx := text.rfind(".")
		if idx > 0 and idx < text.length() - 1:
			text = text.substr(0, idx) + text.substr(idx + 1)
	elif randf() < 0.3:
		# Elongate an em dash
		text = text.replace("—", "———")
		text = text.replace(" - ", " --- ")
	return text


## Returns true if this is the Keeper — immune to all visual decay.
func is_keeper_immune(speaker: String) -> bool:
	return speaker == "The Keeper" and keeper_immune_to_visual_decay


# ============================================================
# 1.2 — SILENCE FALLOUT VISUAL UPDATE
# ============================================================

func _update_silence_visuals(delta: float) -> void:
	# 9: During decay-free windows, recover silence visuals
	if decay_free_active:
		if absf(light_kelvin_offset) > 1.0:
			light_kelvin_offset = move_toward(light_kelvin_offset, 0.0, KELVIN_RECOVERY_RATE * 5.0 * delta)
		if _desync_active:
			_desync_active = false
			npc_idle_desync_ms = 0.0
			npc_desync_active.emit(false)
		return

	# Light temperature shift during/after silence
	if SilenceFallout.is_active or SilenceFallout.is_in_fallout_window():
		var target := randf_range(SILENCE_KELVIN_SHIFT_MIN, SILENCE_KELVIN_SHIFT_MAX)
		light_kelvin_offset = lerpf(light_kelvin_offset, target, delta * 0.5)
	else:
		# Recover slowly
		if absf(light_kelvin_offset) > 1.0:
			light_kelvin_offset = move_toward(light_kelvin_offset, 0.0, KELVIN_RECOVERY_RATE * delta)
		else:
			light_kelvin_offset = 0.0

	# NPC idle desync
	var should_desync := SilenceFallout.is_active or SilenceFallout.is_in_fallout_window()
	if should_desync and not _desync_active:
		_desync_active = true
		npc_idle_desync_ms = randf_range(-NPC_DESYNC_AMOUNT, NPC_DESYNC_AMOUNT)
		npc_desync_active.emit(true)
	elif not should_desync and _desync_active:
		_desync_active = false
		npc_idle_desync_ms = 0.0
		npc_desync_active.emit(false)

	# Prop loop overshoot
	if SilenceFallout.is_active:
		prop_loop_overshoot_frames = PROP_OVERSHOOT_AMOUNT
	else:
		prop_loop_overshoot_frames = 0

	if absf(light_kelvin_offset) > 1.0:
		silence_light_shift.emit(light_kelvin_offset)


## Get the silence-induced color shift for lights/environment.
## Returns a Color multiplier (apply to ambient/directional light).
func get_silence_light_tint() -> Color:
	if decay_free_active:
		return Color.WHITE
	if absf(light_kelvin_offset) < 1.0:
		return Color.WHITE
	# Map Kelvin offset to a blue-shift tint
	# -300K = slight blue, -600K = noticeable blue/cold
	var t := clampf(absf(light_kelvin_offset) / 600.0, 0.0, 1.0)
	return Color(
		1.0 - t * 0.08,   # Slightly less red
		1.0 - t * 0.03,   # Slightly less green
		1.0 + t * 0.05,   # Slightly more blue
		1.0
	)


# ============================================================
# 2.1 — DIALOGUE DAMAGE (helper functions for dialogue_ui.gd)
# ============================================================

## Insert forced dead air (400-900ms) before a hard truth line.
## Returns the delay in ms, or 0 if no dead air should be inserted.
func get_dialogue_dead_air(text: String) -> float:
	if decay_free_active:
		return 0.0
	var strain_norm := AnchorStrain.anchor_strain / 100.0
	if strain_norm < 0.3:
		return 0.0
	var text_lower := text.to_lower()
	var is_hard_truth := false
	for keyword in DialogueManager.HARD_TRUTH_KEYWORDS:
		if keyword in text_lower:
			is_hard_truth = true
			break
	if not is_hard_truth:
		return 0.0
	return randf_range(400.0, 900.0)


## At high strain, NPCs finish player sentences INCORRECTLY.
## Returns a wrong completion, or empty string if not applicable.
func get_wrong_sentence_finish(speaker: String) -> String:
	if decay_free_active:
		return ""
	if is_keeper_immune(speaker):
		return ""
	var strain_norm := AnchorStrain.anchor_strain / 100.0
	if strain_norm < 0.7:
		return ""
	if randf() >= 0.15:
		return ""

	var wrong_finishes := [
		"...you already knew that, didn't you?",
		"...but you don't care about that.",
		"...which is exactly what you wanted to hear.",
		"...and it doesn't matter anymore.",
		"...but you weren't listening anyway.",
		"...so there's nothing left to say.",
		"...just like last time. And the time before.",
	]
	return wrong_finishes[randi() % wrong_finishes.size()]


## NPC sentences that start confidently, end clipped mid-word.
## Returns the clipped version, or original if no clip.
func maybe_clip_sentence(speaker: String, text: String) -> String:
	if decay_free_active:
		return text
	if is_keeper_immune(speaker):
		return text
	var strain_norm := AnchorStrain.anchor_strain / 100.0
	if strain_norm < 0.5:
		return text
	if randf() >= 0.12:
		return text

	# Clip at ~70-90% of the sentence
	var words := text.split(" ")
	if words.size() < 4:
		return text
	var clip_point := int(words.size() * randf_range(0.7, 0.9))
	var clipped := " ".join(words.slice(0, clip_point))
	# Cut the last word partway through
	var last_word: String = words[clip_point] if clip_point < words.size() else ""
	if last_word.length() > 2:
		clipped += " " + last_word.substr(0, int(last_word.length() * 0.5)) + "—"
	else:
		clipped += "—"
	return clipped


# ============================================================
# 2.2 — SOCIAL DECAY UPDATE
# ============================================================

func _update_social_decay(delta: float) -> void:
	# 9: During decay-free windows, social decay pauses (not recovers)
	if decay_free_active:
		return

	# Social decay increases when trust is low and strain is high
	var trust := TrustDestruction.trust_level
	var strain_norm := AnchorStrain.anchor_strain / 100.0

	var should_decay := trust < 0.5 or strain_norm > 0.5
	if should_decay:
		social_decay_level = clampf(
			social_decay_level + SOCIAL_DECAY_RATE * delta, 0.0, 1.0)
	else:
		social_decay_level = clampf(
			social_decay_level - SOCIAL_DECAY_RECOVERY * delta, 0.0, 1.0)

	social_decay_level_changed.emit(social_decay_level)


## Get the distance multiplier NPCs should use when positioning near the player.
func get_npc_distance_multiplier() -> float:
	if decay_free_active:
		return 1.0
	return 1.0 + social_decay_level * (SOCIAL_DECAY_DISTANCE_MULT - 1.0)


## Get the gap radius for crowd formations around the player.
func get_crowd_gap_radius() -> float:
	if decay_free_active:
		return 0.0
	return social_decay_level * 3.0  # 0-3 meters


# ============================================================
# 4.1 — FALSE STABILITY UPDATE (with 13: THE TWIST)
# ============================================================

func _update_false_stability(delta: float) -> void:
	if not in_false_stability_zone:
		false_stability_time_spent = 0.0
		return
	false_stability_time_spent += delta


## Query: should NPCs in this zone be rigid? (After spending too long in false stability)
## 13: Rigidity feels like "calm competence" — NPCs are polite, precise, helpful.
func should_npcs_be_rigid() -> bool:
	return in_false_stability_zone and false_stability_time_spent > FALSE_STABILITY_RIGIDITY_ONSET


## Query: should dialogue options be narrowed?
func should_narrow_options() -> bool:
	return in_false_stability_zone and false_stability_time_spent > FALSE_STABILITY_NARROWING_ONSET


## 13: Get the honest metric decay multiplier for false stability zones.
## The "safe" zone accelerates honest metric decay — safety is harmful.
func get_false_stability_honest_mult() -> float:
	if in_false_stability_zone:
		return FALSE_STABILITY_HONEST_DECAY_MULT
	return 1.0


# ============================================================
# 5.1 — RELOAD DETECTION FEEDBACK UPDATE (with 14: SAVE SHAME)
# ============================================================

func _update_reload_feedback(delta: float) -> void:
	# Sluggishness decays back to normal over time
	if reload_sluggishness > 1.0:
		reload_sluggishness = maxf(1.0, reload_sluggishness - RELOAD_SLOWDOWN_DECAY * delta)

	# Blocking offset decays
	if reload_blocking_offset.length() > 0.01:
		reload_blocking_offset = reload_blocking_offset.move_toward(Vector3.ZERO, 0.02 * delta)
	else:
		reload_blocking_offset = Vector3.ZERO

	# 14: Save shame visuals decay
	if save_thumbnail_delay_active and reload_sluggishness <= 1.05:
		save_thumbnail_delay_active = false
	if load_text_before_bg and reload_sluggishness <= 1.05:
		load_text_before_bg = false


func _on_scum_detected(confidence: float) -> void:
	if confidence > 0.3:
		reload_sluggishness = 1.0 + RELOAD_SLOWDOWN_AMOUNT * confidence
		reload_blocking_offset = Vector3(
			randf_range(-RELOAD_BLOCKING_MAX_OFFSET, RELOAD_BLOCKING_MAX_OFFSET),
			0.0,
			randf_range(-RELOAD_BLOCKING_MAX_OFFSET, RELOAD_BLOCKING_MAX_OFFSET)
		)
		reload_sluggishness_changed.emit(reload_sluggishness)

		# 14: Save shame effects
		if not (DevToggles and DevToggles.disable_save_shame):
			save_thumbnail_delay_active = true
			load_text_before_bg = true

		# 14: Once per run — successful reload makes things WORSE
		if not _save_shame_used_this_run and confidence > 0.5 and not (DevToggles and DevToggles.disable_save_shame):
			_save_shame_used_this_run = true
			# Quietly worsen honest metric
			honest_metric_npc_survival = maxf(
				HONEST_METRIC_FLOOR,
				honest_metric_npc_survival - 5.0
			)
			# Quietly increase social decay
			social_decay_level = clampf(social_decay_level + 0.1, 0.0, 1.0)
			save_shame_event.emit("reload_worsened")


func _on_hesitation_detected(confidence: float) -> void:
	if confidence > 0.2:
		reload_sluggishness = 1.0 + RELOAD_SLOWDOWN_AMOUNT * 0.5 * confidence
		reload_sluggishness_changed.emit(reload_sluggishness)


## 14: Get save thumbnail delay factor.
## Returns 0.0 when normal, 0.5-1.5 seconds of delay when shamed.
func get_save_thumbnail_delay() -> float:
	if not save_thumbnail_delay_active:
		return 0.0
	return reload_sluggishness * 0.8  # Scales with sluggishness


## 14: Should load screen text appear before the background finishes loading?
func should_load_text_lead() -> bool:
	return load_text_before_bg


# ============================================================
# 7.1 — THE LAST HONEST METRIC UPDATE
# ============================================================

func _update_honest_metric(delta: float) -> void:
	# Decays when world pressure is high or trust is low
	var pressure := GameState.world_pressure
	var trust := TrustDestruction.trust_level

	var should_decay := pressure > 40.0 or trust < 0.6
	if should_decay:
		var decay_factor := 1.0
		if pressure > 70.0:
			decay_factor = 2.0
		if trust < 0.3:
			decay_factor *= 1.5

		# 13: False stability zones accelerate decay
		decay_factor *= get_false_stability_honest_mult()

		honest_metric_npc_survival = maxf(
			HONEST_METRIC_FLOOR,
			honest_metric_npc_survival - HONEST_METRIC_DECAY_RATE * decay_factor * delta
		)
		honest_metric_changed.emit(_honest_metric_name, honest_metric_npc_survival)
	# NEVER recovers. That's the point.


## Get how long NPCs can physically tolerate being near the player.
## 100.0 = NPCs comfortable nearby, 5.0 = NPCs barely tolerate proximity.
## NPCs should react PHYSICALLY (fidgeting, stepping back) not VERBALLY.
func get_npc_proximity_endurance() -> float:
	return honest_metric_npc_survival


# ============================================================
# SIGNAL HANDLERS
# ============================================================

func _on_strain_threshold(_level: String) -> void:
	# Force immediate visual update on threshold cross
	_update_truth_strain_visuals()


func _on_silence_fallout_changed(is_active: bool) -> void:
	if is_active:
		# Immediate cold shift
		light_kelvin_offset = randf_range(SILENCE_KELVIN_SHIFT_MIN, SILENCE_KELVIN_SHIFT_MAX)
		silence_light_shift.emit(light_kelvin_offset)


func _on_audio_glitch_window(is_active: bool) -> void:
	if is_active:
		# Keep desync running during audio glitch window
		_desync_active = true
		npc_idle_desync_ms = randf_range(-NPC_DESYNC_AMOUNT, NPC_DESYNC_AMOUNT)
		npc_desync_active.emit(true)


func _on_anchor_state_changed(_old: String, new_state: String) -> void:
	if new_state == "silent":
		# Immediate visual response
		light_kelvin_offset = SILENCE_KELVIN_SHIFT_MIN
		silence_light_shift.emit(light_kelvin_offset)


# ============================================================
# PERSISTENCE
# ============================================================

func save_state() -> Dictionary:
	return {
		"alignment_drift_triggered": alignment_drift_triggered,
		"alignment_drift_offset_x": alignment_drift_offset.x,
		"alignment_drift_offset_y": alignment_drift_offset.y,
		"social_decay_level": social_decay_level,
		"honest_metric_npc_survival": honest_metric_npc_survival,
		"save_shame_used": _save_shame_used_this_run,
	}


func load_state(data: Dictionary) -> void:
	alignment_drift_triggered = data.get("alignment_drift_triggered", false)
	alignment_drift_offset = Vector2(
		data.get("alignment_drift_offset_x", 0.0),
		data.get("alignment_drift_offset_y", 0.0)
	)
	social_decay_level = data.get("social_decay_level", 0.0)
	honest_metric_npc_survival = data.get("honest_metric_npc_survival", 100.0)
	# save_shame_used intentionally NOT persisted — resets per run


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"ui_jitter_intensity": ui_jitter_intensity,
		"punctuation_flicker": punctuation_flicker_active,
		"alignment_drift": alignment_drift_triggered,
		"alignment_drift_offset": alignment_drift_offset,
		"light_kelvin_offset": light_kelvin_offset,
		"npc_desync_active": _desync_active,
		"npc_desync_ms": npc_idle_desync_ms,
		"social_decay_level": social_decay_level,
		"in_false_stability_zone": in_false_stability_zone,
		"false_stability_time": false_stability_time_spent,
		"reload_sluggishness": reload_sluggishness,
		"reload_blocking_offset": reload_blocking_offset,
		"honest_metric": honest_metric_npc_survival,
		"decay_free_active": decay_free_active,
		"decay_free_timer": _decay_free_timer,
		"ui_easing_hardness": ui_easing_hardness,
		"transition_incompleteness": transition_incompleteness,
		"npc_eye_mode": npc_eye_mode,
		"npc_look_past_offset": npc_look_past_offset,
		"save_thumbnail_delay": save_thumbnail_delay_active,
		"load_text_before_bg": load_text_before_bg,
		"save_shame_used": _save_shame_used_this_run,
	}
