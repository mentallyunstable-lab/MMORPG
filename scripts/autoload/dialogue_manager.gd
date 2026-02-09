## DialogueManager — Controls dialogue flow, choices, and force-based branching.
##
## E1 Extensions — Dialogue Timing Pass:
##   - Micro-delays (200-800ms) before hard truths
##   - Removal of perfect pacing — add awkward pauses
##   - Occasionally cut Keeper lines short
extends Node

signal dialogue_started(speaker: String)
signal dialogue_line(speaker: String, text: String)
signal dialogue_choices_presented(choices: Array)
signal dialogue_ended()
signal dialogue_line_delayed(speaker: String, text: String, delay_ms: float)

var is_active: bool = false
var current_dialogue: Array = []  # Array of dialogue entries
var current_index: int = -1
var current_speaker: String = ""

# UI node reference — set by DialogueUI when it enters the tree.
var ui_node: Control = null

# Guard against infinite recursion when skipping gated lines.
const _MAX_SKIP_DEPTH := 50

# --- E1: Dialogue Timing ---
# Hard truths get micro-delays. Awkward pauses break perfect pacing.
# Keeper lines can be cut short at high strain.
var _pending_delay_ms: float = 0.0

# Keywords that trigger micro-delays before delivery
const HARD_TRUTH_KEYWORDS := [
	"dead", "dying", "fading", "corrupted", "hostile",
	"strains", "overwhelming", "cannot", "broken", "lost",
	"silence", "gone", "nothing", "never", "worst",
]
const MICRO_DELAY_MIN_MS := 200.0
const MICRO_DELAY_MAX_MS := 800.0
const AWKWARD_PAUSE_CHANCE := 0.15  # 15% chance of extra pause on any line
const AWKWARD_PAUSE_MS := 400.0


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
func advance(_skip_depth: int = 0) -> void:
	if not is_active:
		return

	if _skip_depth > _MAX_SKIP_DEPTH:
		push_warning("DialogueManager: exceeded max skip depth, ending dialogue.")
		end_dialogue()
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

	# If we ran out of entries while skipping ID entries
	if current_index >= current_dialogue.size():
		end_dialogue()
		return

	# Check for force-gated lines
	if entry.has("requires_force"):
		var req_force: String = entry["requires_force"]
		var req_min: float = entry.get("requires_min", 0.0)
		if GameState.get_force(req_force) < req_min:
			# Skip this line — force requirement not met
			advance(_skip_depth + 1)
			return

	var speaker: String = entry.get("speaker", current_speaker)
	var text: String = entry.get("text", "")

	# E1: Calculate timing delay for this line
	var delay_ms := _calculate_line_delay(speaker, text)
	if delay_ms > 0.0 and not (DevToggles and DevToggles.disable_dialogue_timing):
		_pending_delay_ms = delay_ms
		dialogue_line_delayed.emit(speaker, text, delay_ms)
	else:
		_pending_delay_ms = 0.0

	dialogue_line.emit(speaker, text)

	if entry.has("choices"):
		_present_filtered_choices(entry["choices"])


## Filter and present choices, removing force-gated ones the player can't access.
func _present_filtered_choices(choices: Array) -> void:
	var available: Array = []
	for choice in choices:
		if choice.has("requires_force"):
			if GameState.get_force(choice["requires_force"]) >= choice.get("requires_min", 0.0):
				available.append(choice)
		else:
			available.append(choice)
	if available.size() > 0:
		dialogue_choices_presented.emit(available)
	else:
		# All choices gated — just advance
		advance()


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
				_present_filtered_choices(entry["choices"])
			return

	# ID not found — just advance
	advance()


## End dialogue and restore player control.
func end_dialogue() -> void:
	is_active = false
	current_dialogue = []
	current_index = -1
	_pending_delay_ms = 0.0
	dialogue_ended.emit()

	# Restore player input
	get_tree().call_group("player", "set_input_enabled", true)


# --- E1: Dialogue Timing ---

## Calculate delay before displaying a line.
## Hard truths get micro-delays. Random lines get awkward pauses.
## Keeper lines at high strain get additional pause from AnchorStrain.
func _calculate_line_delay(speaker: String, text: String) -> float:
	var delay := 0.0
	var text_lower := text.to_lower()

	# Check for hard truth keywords
	for keyword in HARD_TRUTH_KEYWORDS:
		if keyword in text_lower:
			delay = randf_range(MICRO_DELAY_MIN_MS, MICRO_DELAY_MAX_MS)
			break

	# Random awkward pause on any line
	if delay == 0.0 and randf() < AWKWARD_PAUSE_CHANCE:
		delay = AWKWARD_PAUSE_MS

	# Keeper-specific: AnchorStrain adds hesitation
	if speaker == "The Keeper" and AnchorStrain:
		delay += AnchorStrain.get_dialogue_pause_ms()

	return delay


## Get the current pending delay (for UI to use).
func get_pending_delay_ms() -> float:
	return _pending_delay_ms


## E1: Optionally cut a Keeper line short at high strain.
## Returns the truncated text, or original if no cut.
func maybe_cut_line_short(speaker: String, text: String) -> String:
	if speaker != "The Keeper":
		return text
	if not AnchorStrain:
		return text
	# Only cut at HIGH+ strain, 20% chance
	if AnchorStrain.anchor_strain < AnchorStrain.STRAIN_HIGH:
		return text
	if randf() >= 0.2:
		return text
	# Cut at a sentence boundary or mid-phrase
	var sentences := text.split(". ")
	if sentences.size() <= 1:
		return text
	# Keep first sentence, cut the rest
	return sentences[0] + "."
