## DialogueManager — Controls dialogue flow, choices, and force-based branching.
extends Node

signal dialogue_started(speaker: String)
signal dialogue_line(speaker: String, text: String)
signal dialogue_choices_presented(choices: Array)
signal dialogue_ended()

var is_active: bool = false
var current_dialogue: Array = []  # Array of dialogue entries
var current_index: int = -1
var current_speaker: String = ""

# UI node reference — set by DialogueUI when it enters the tree.
var ui_node: Control = null


## Start a dialogue sequence.
## dialogue_data format:
## [
##   { "speaker": "NPC", "text": "Hello traveler." },
##   { "speaker": "NPC", "text": "Choose your path.",
##     "choices": [
##       { "text": "Pray", "force": "faith", "amount": 5.0, "next_id": "pray_response" },
##       { "text": "Question", "force": "truth", "amount": 5.0, "next_id": "question_response" },
##       { "text": "Threaten", "force": "violence", "amount": 5.0, "next_id": "threaten_response" },
##     ]
##   },
##   { "id": "pray_response", "speaker": "NPC", "text": "Your faith is noted." },
##   { "id": "question_response", "speaker": "NPC", "text": "You seek the truth." },
##   { "id": "threaten_response", "speaker": "NPC", "text": "Violence it is." },
## ]
func start_dialogue(dialogue_data: Array, speaker_name: String = "???") -> void:
	if is_active:
		return

	current_dialogue = dialogue_data
	current_index = -1
	current_speaker = speaker_name
	is_active = true
	dialogue_started.emit(speaker_name)

	# Pause player input during dialogue
	get_tree().call_group("player", "set_input_enabled", false)

	advance()


## Advance to next line or end dialogue.
func advance() -> void:
	if not is_active:
		return

	current_index += 1

	if current_index >= current_dialogue.size():
		end_dialogue()
		return

	var entry: Dictionary = current_dialogue[current_index]

	# Skip entries with IDs unless explicitly jumped to
	while entry.has("id") and current_index < current_dialogue.size() - 1:
		current_index += 1
		entry = current_dialogue[current_index]

	var speaker: String = entry.get("speaker", current_speaker)
	var text: String = entry.get("text", "")

	# Check for force-gated lines
	if entry.has("requires_force"):
		var req_force: String = entry["requires_force"]
		var req_min: float = entry.get("requires_min", 0.0)
		if GameState.get_force(req_force) < req_min:
			# Skip this line — force requirement not met
			advance()
			return

	dialogue_line.emit(speaker, text)

	if entry.has("choices"):
		var choices: Array = entry["choices"]
		# Filter choices by force requirements
		var available: Array = []
		for choice in choices:
			if choice.has("requires_force"):
				if GameState.get_force(choice["requires_force"]) >= choice.get("requires_min", 0.0):
					available.append(choice)
			else:
				available.append(choice)
		dialogue_choices_presented.emit(available)


## Player selected a choice.
func select_choice(choice_index: int) -> void:
	if not is_active:
		return

	var entry: Dictionary = current_dialogue[current_index]
	if not entry.has("choices"):
		return

	var choices: Array = entry["choices"]
	if choice_index < 0 or choice_index >= choices.size():
		return

	var choice: Dictionary = choices[choice_index]

	# Apply force change
	if choice.has("force") and choice.has("amount"):
		GameState.add_force(choice["force"], choice["amount"])

	# Jump to target if specified
	if choice.has("next_id"):
		_jump_to_id(choice["next_id"])
	else:
		advance()


func _jump_to_id(id: String) -> void:
	for i in range(current_dialogue.size()):
		if current_dialogue[i].get("id", "") == id:
			current_index = i
			var entry: Dictionary = current_dialogue[current_index]
			var speaker: String = entry.get("speaker", current_speaker)
			dialogue_line.emit(speaker, entry.get("text", ""))
			if entry.has("choices"):
				dialogue_choices_presented.emit(entry["choices"])
			return

	# ID not found — just advance
	advance()


## End dialogue and restore player control.
func end_dialogue() -> void:
	is_active = false
	current_dialogue = []
	current_index = -1
	dialogue_ended.emit()

	# Restore player input
	get_tree().call_group("player", "set_input_enabled", true)
