## DialogueUI — Displays dialogue lines and choices on screen.
extends Control

@onready var panel: PanelContainer = $DialoguePanel
@onready var speaker_label: Label = $DialoguePanel/MarginContainer/VBoxContainer/SpeakerLabel
@onready var text_label: RichTextLabel = $DialoguePanel/MarginContainer/VBoxContainer/TextLabel
@onready var choices_container: VBoxContainer = $DialoguePanel/MarginContainer/VBoxContainer/ChoicesContainer
@onready var continue_label: Label = $DialoguePanel/MarginContainer/VBoxContainer/ContinueLabel

# Force color mapping
const FORCE_COLORS := {
	"faith": Color(0.6, 0.7, 1.0),     # Soft blue
	"truth": Color(1.0, 1.0, 0.6),     # Pale yellow
	"violence": Color(1.0, 0.4, 0.3),  # Red
}


# E1: Delayed line display
var _delay_timer: Timer = null
var _delayed_speaker: String = ""
var _delayed_text: String = ""


func _ready() -> void:
	DialogueManager.ui_node = self
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_line.connect(_on_dialogue_line)
	DialogueManager.dialogue_choices_presented.connect(_on_choices_presented)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	DialogueManager.dialogue_line_delayed.connect(_on_dialogue_line_delayed)

	# E1: Create delay timer
	_delay_timer = Timer.new()
	_delay_timer.one_shot = true
	_delay_timer.timeout.connect(_on_delay_finished)
	add_child(_delay_timer)

	panel.visible = false


func _exit_tree() -> void:
	if DialogueManager:
		if DialogueManager.dialogue_started.is_connected(_on_dialogue_started):
			DialogueManager.dialogue_started.disconnect(_on_dialogue_started)
		if DialogueManager.dialogue_line.is_connected(_on_dialogue_line):
			DialogueManager.dialogue_line.disconnect(_on_dialogue_line)
		if DialogueManager.dialogue_choices_presented.is_connected(_on_choices_presented):
			DialogueManager.dialogue_choices_presented.disconnect(_on_choices_presented)
		if DialogueManager.dialogue_ended.is_connected(_on_dialogue_ended):
			DialogueManager.dialogue_ended.disconnect(_on_dialogue_ended)


func _unhandled_input(event: InputEvent) -> void:
	if not DialogueManager.is_active:
		return

	# Click or E to advance (when no choices are shown)
	if choices_container.get_child_count() == 0:
		if event.is_action_pressed("interact") or event.is_action_pressed("attack_melee"):
			DialogueManager.advance()
			get_viewport().set_input_as_handled()


func _on_dialogue_started(_speaker: String) -> void:
	panel.visible = true
	choices_container.visible = false
	continue_label.visible = false
	_clear_choices()


func _on_dialogue_line(speaker: String, text: String) -> void:
	# --- VisualDecay integration: dialogue damage pipeline ---
	var processed_text := _apply_dialogue_damage(speaker, text)

	# E1: If there's a pending delay, show "..." first, then reveal after timer
	var delay_ms := DialogueManager.get_pending_delay_ms()

	# 2.1: Additional dead air before hard truths
	if VisualDecay:
		var dead_air := VisualDecay.get_dialogue_dead_air(processed_text)
		if dead_air > 0.0:
			delay_ms = maxf(delay_ms, dead_air)

	if delay_ms > 0.0:
		speaker_label.text = speaker
		text_label.text = "..."
		_delayed_speaker = speaker
		# E1: Apply line cutting for strained Keeper
		_delayed_text = DialogueManager.maybe_cut_line_short(speaker, processed_text)
		_delay_timer.start(delay_ms / 1000.0)
		_clear_choices()
		choices_container.visible = false
		continue_label.visible = false
		return
	speaker_label.text = speaker
	text_label.text = DialogueManager.maybe_cut_line_short(speaker, processed_text)
	_clear_choices()
	choices_container.visible = false
	continue_label.visible = true
	continue_label.text = "[E] Continue"


func _on_choices_presented(choices: Array) -> void:
	_clear_choices()
	continue_label.visible = false
	choices_container.visible = true

	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = "[%d] %s" % [i + 1, choice.get("text", "...")]

		# Color-code by force
		if choice.has("force"):
			var force_color: Color = FORCE_COLORS.get(choice["force"], Color.WHITE)
			btn.add_theme_color_override("font_color", force_color)

		btn.pressed.connect(_on_choice_selected.bind(i))
		choices_container.add_child(btn)


func _on_choice_selected(index: int) -> void:
	DialogueManager.select_choice(index)


func _on_dialogue_ended() -> void:
	panel.visible = false
	_clear_choices()


## E1: Called when a delayed line signal fires (used for internal tracking).
func _on_dialogue_line_delayed(_speaker: String, _text: String, _delay_ms: float) -> void:
	pass  # Actual delay handling is in _on_dialogue_line


## E1: Delay timer finished — reveal the actual text.
func _on_delay_finished() -> void:
	text_label.text = _delayed_text

	# 2.1: After dead air, NPC might finish the player's thought WRONG
	if VisualDecay:
		var wrong_finish := VisualDecay.get_wrong_sentence_finish(_delayed_speaker)
		if wrong_finish != "":
			text_label.text = _delayed_text + " " + wrong_finish

	continue_label.visible = true
	continue_label.text = "[E] Continue"


func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()


# --- 2.1: Dialogue Damage Pipeline ---
# Processes text through VisualDecay's damage systems:
#   - Punctuation flicker (periods vanish, em dashes elongate)
#   - Sentence clipping (starts confident, ends mid-word)
#   - Keeper text is IMMUNE to all damage

func _apply_dialogue_damage(speaker: String, text: String) -> String:
	if not VisualDecay:
		return text
	if DevToggles and DevToggles.disable_dialogue_damage:
		return text

	# Keeper immunity — pixel-perfect always
	if VisualDecay.is_keeper_immune(speaker):
		return text

	# 1.1: Punctuation flicker
	text = VisualDecay.apply_punctuation_flicker(text)

	# 2.1: Sentence clipping (starts confident, ends clipped mid-word)
	text = VisualDecay.maybe_clip_sentence(speaker, text)

	return text
