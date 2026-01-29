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


func _ready() -> void:
	DialogueManager.ui_node = self
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_line.connect(_on_dialogue_line)
	DialogueManager.dialogue_choices_presented.connect(_on_choices_presented)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)

	panel.visible = false


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
	speaker_label.text = speaker
	text_label.text = text
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


func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()
