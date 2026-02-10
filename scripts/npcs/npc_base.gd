## NPCBase — Interactable NPC with dialogue and force-reactive behavior.
## Regular NPCs are subject to TrustDestruction — they may report corrupted world state.
## The Keeper (anchor NPC) overrides this behavior and always tells truth.
## Use _get_reported_force() and _get_reported_god_state() instead of reading GameState directly
## when building dialogue that describes the world to the player.
##
## E2 Extensions — Language Degradation:
##   - As trust drops, NPC grammar simplifies and vocabulary shrinks
##   - Certainty words increase ("always", "never") as uncertainty grows
##   - Keeper language never degrades — the contrast must hurt
##
## E3 Extensions — Player Self-Doubt Hooks:
##   - NPCs ask reflective questions with no response option
##   - Journal auto-fills with interpretations, not facts
##   - Some entries later contradict earlier ones
class_name NPCBase
extends CharacterBody3D

@export var npc_name: String = "Stranger"
@export var force_affinity: String = "neutral"  # "faith", "truth", "violence", "neutral"

# Dialogue data — set in the editor or via code.
@export var dialogue_data: Array = []

# Whether this NPC has already been talked to
var has_spoken: bool = false

# Visual reaction state
var _mesh_node: MeshInstance3D = null
var _base_emission_energy: float = 0.3


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("npcs")

	# Cache mesh for visual reactions
	_mesh_node = _find_mesh()
	if _mesh_node and _mesh_node.get_surface_override_material(0):
		var mat: StandardMaterial3D = _mesh_node.get_surface_override_material(0)
		_base_emission_energy = mat.emission_energy_multiplier

	# React to force changes
	GameState.force_changed.connect(_on_force_changed)


## --- 2.2 / 7.1: Physical reactions to social decay and proximity endurance ---
## NPCs fidget, step back, and become physically uncomfortable near the player.
## No collision changes. No verbal acknowledgment. Only body language.
var _social_decay_reposition_timer: float = 0.0
const SOCIAL_DECAY_CHECK_INTERVAL := 3.0


func _process(delta: float) -> void:
	if not VisualDecay:
		return
	if DevToggles and DevToggles.disable_social_decay:
		return

	_social_decay_reposition_timer += delta
	if _social_decay_reposition_timer < SOCIAL_DECAY_CHECK_INTERVAL:
		return
	_social_decay_reposition_timer = 0.0

	# 9: During decay-free windows, all physical unease pauses (the contrast)
	if VisualDecay.is_decay_free():
		if _mesh_node:
			_mesh_node.scale = Vector3.ONE  # Reset fidget
		return

	# 7.1: NPC proximity endurance — physical fidgeting
	if not (DevToggles and DevToggles.disable_honest_metric):
		var endurance := VisualDecay.get_npc_proximity_endurance()
		if endurance < 50.0 and _mesh_node:
			# Subtle fidget: micro-scale pulse (NPCs are uncomfortable)
			var fidget := randf_range(0.98, 1.02)
			_mesh_node.scale = Vector3(fidget, fidget, fidget)

	# 12: NPC eye behavior — look-past, held contact
	if not (DevToggles and DevToggles.disable_eye_behavior):
		_apply_eye_behavior()

	# 2.2: Social decay — NPCs subtly reposition farther from player
	var player := get_tree().get_first_node_in_group("player")
	if not player or not player is Node3D:
		return
	var distance_mult := VisualDecay.get_npc_distance_multiplier()
	if distance_mult <= 1.05:
		return
	# Nudge NPC position away from player (very subtle, 0.1m per check max)
	var dir_away := (global_position - player.global_position).normalized()
	if dir_away.length() > 0.01:
		global_position += dir_away * minf(0.1, (distance_mult - 1.0) * 0.15)


## Called by PlayerController when player presses interact.
func interact(_player: Node) -> void:
	if DialogueManager.is_active:
		return

	# --- Witness Mode (Step 6): NPCs are gone. Only traces remain. ---
	if GameState.witness_mode:
		var witness_dialogue := _get_witness_dialogue()
		if witness_dialogue.size() > 0:
			DialogueManager.start_dialogue(witness_dialogue, "...")
		return

	# Check if faction is hostile — refuse dialogue
	if _is_faction_hostile():
		var refusal := _get_hostile_refusal()
		DialogueManager.start_dialogue(refusal, npc_name)
		return

	var dialogue := _get_dialogue()

	# --- Micro-truth injection (Phase 3.5) ---
	# Regular NPCs may inject small verifiable truths even at low trust levels.
	# These are mundane, unrewarded, and verifiable — preventing total epistemic collapse.
	if dialogue.size() > 0 and MicroTruthEvents:
		var micro_truth := MicroTruthEvents.get_random_truth_for_npc()
		if not micro_truth.is_empty() and randf() < 0.3:
			dialogue.insert(dialogue.size() - 1 if dialogue.size() > 1 else 0,
				{"speaker": npc_name, "text": micro_truth.get("text", "")})

	# --- Silence memory reference (Phase 2.4) ---
	# NPCs may reference past Keeper silence periods.
	if dialogue.size() > 0 and SilenceMemory and SilenceMemory.has_notable_silence():
		if randf() < 0.15:
			var ref := SilenceMemory.get_silence_reference()
			if ref != "":
				dialogue.append({"speaker": npc_name, "text": ref})

	# --- Truth misuse reference (Phase 5.9) ---
	if dialogue.size() > 0 and TruthMisuse and TruthMisuse.has_misuse_history():
		if randf() < 0.1:
			var ref := TruthMisuse.get_misuse_reference()
			if ref != "":
				dialogue.append({"speaker": npc_name, "text": ref})

	# --- E2: Language degradation ---
	if dialogue.size() > 0 and not (DevToggles and DevToggles.disable_language_degradation):
		dialogue = _apply_language_degradation(dialogue)

	# --- E3: Self-doubt hooks ---
	if dialogue.size() > 0 and not (DevToggles and DevToggles.disable_psychological_hooks):
		dialogue = _inject_self_doubt_hooks(dialogue)

	# --- B3: Context withholding (from TruthMisuse) ---
	if dialogue.size() > 0 and TruthMisuse and TruthMisuse.should_withhold_context():
		dialogue = _apply_context_withholding(dialogue)

	# --- A3: NPC memory conflict injection ---
	if dialogue.size() > 0 and SilenceFallout and SilenceFallout.is_in_fallout_window():
		var conflict := SilenceFallout.get_npc_memory_conflict()
		if not conflict.is_empty() and randf() < 0.2:
			dialogue.append({"speaker": npc_name, "text": conflict.get("version_a", "")})

	# --- A2: NPC agency doubt ---
	if dialogue.size() > 0 and KeeperOverreliance:
		var doubt_line := KeeperOverreliance.get_agency_doubt_line()
		if doubt_line != "":
			dialogue.append({"speaker": npc_name, "text": doubt_line})

	# --- 3.2: Memory conflict injection (JournalViolence) ---
	# NPC references events with swapped cause/effect or inverted emotions
	# 9: Suppressed during decay-free windows (everything should feel normal)
	var _decay_free := VisualDecay and VisualDecay.is_decay_free()
	if dialogue.size() > 0 and JournalViolence and not _decay_free:
		if randf() < 0.1:  # 10% chance
			var swapped := JournalViolence.get_swapped_memory_line()
			if swapped != "":
				dialogue.append({"speaker": npc_name, "text": swapped})
		elif randf() < 0.08:  # 8% chance for emotion inversion
			var inversion := JournalViolence.get_emotion_inversion()
			if not inversion.is_empty():
				# This NPC states one version; another NPC will state the other
				dialogue.append({"speaker": npc_name, "text": inversion.get("npc_a", "")})

	# --- C2: Keeper misquote ---
	if dialogue.size() > 0 and AnchorAbsenceLegacy and AnchorManager.current_state != AnchorManager.AnchorState.PRESENT:
		if randf() < 0.12:
			var misquote := AnchorAbsenceLegacy.get_keeper_misquote()
			if misquote != "":
				dialogue.append({"speaker": npc_name, "text": misquote})

	if dialogue.size() > 0:
		DialogueManager.start_dialogue(dialogue, npc_name)
		has_spoken = true

		# E3: Auto-fill journal with interpretation (not fact)
		if not (DevToggles and DevToggles.disable_psychological_hooks):
			_auto_journal_interpretation()


## Witness mode: what the player sees instead of a living NPC.
## Override in subclasses for specific NPCs. Default: generic corpse/absence.
## Integrates with AnchorAbsenceLegacy (Phase 7.14): NPCs may unconsciously echo
## the Keeper's phrasing, implying the anchor changed the world, not ruled it.
func _get_witness_dialogue() -> Array:
	var lines: Array = []
	if has_spoken:
		lines.append({"speaker": "...", "text": "A body lies here. You recognize %s." % npc_name})
		lines.append({"speaker": "...", "text": "Whatever they wanted — it doesn't matter now."})
	else:
		lines.append({"speaker": "...", "text": "Someone was here. You never spoke to them."})
		lines.append({"speaker": "...", "text": "Their name is scratched into the wall, but you can't read it."})

	# Anchor Absence Legacy echo (Phase 7.14)
	if AnchorAbsenceLegacy:
		var echo := AnchorAbsenceLegacy.get_witness_echo()
		if echo != "":
			lines.append({"speaker": "...", "text": echo})

	return lines


## Check if this NPC's aligned faction is hostile to the player.
func _is_faction_hostile() -> bool:
	var faction_id := _get_faction_id()
	if faction_id == "":
		return false
	return FactionManager.is_hostile(faction_id)


## Get the faction id for this NPC based on force affinity.
func _get_faction_id() -> String:
	match force_affinity:
		"faith": return "ashwalkers"
		"truth": return "truthseekers"
		"violence": return "ironvow"
	return ""


## What the NPC says when their faction hates the player.
func _get_hostile_refusal() -> Array:
	return [
		{"speaker": npc_name, "text": "..."},
		{"speaker": npc_name, "text": "I have nothing to say to you. Leave."},
	]


## Override this to provide dynamic dialogue based on game state.
func _get_dialogue() -> Array:
	if dialogue_data.size() > 0:
		return dialogue_data

	# Default fallback dialogue with three-force choices
	return _default_dialogue()


func _default_dialogue() -> Array:
	var greeting := "..."
	var dominant := GameState.get_dominant_force()

	match force_affinity:
		"faith":
			if dominant == "faith":
				greeting = "The air hums. The old rites echo louder."
			elif dominant == "truth":
				greeting = "Your questions pull at the threads of what was certain."
			else:
				greeting = "Blood marks the ground here. The sacred and the brutal coexist."
		"truth":
			if dominant == "truth":
				greeting = "Every surface is legible now. The world hides less."
			elif dominant == "faith":
				greeting = "Belief shapes what people see. That is simply how it works."
			else:
				greeting = "Violence changes what was. Observation records what is."
		"violence":
			if dominant == "violence":
				greeting = "Strength rules here. That's how it is."
			else:
				greeting = "You haven't seen what I've seen."
		_:
			greeting = "Traveler. The ash settles around you."

	return [
		{"speaker": npc_name, "text": greeting},
		{"speaker": npc_name, "text": "What do you seek?",
			"choices": [
				{"text": "Guidance (Faith)", "force": "faith", "amount": 2.0},
				{"text": "Answers (Truth)", "force": "truth", "amount": 2.0},
				{"text": "Power (Violence)", "force": "violence", "amount": 2.0},
			]
		},
	]


func _on_force_changed(force_name: String, _old_value: float, new_value: float) -> void:
	if force_name != force_affinity or force_affinity == "neutral":
		return

	# Visual reaction: NPC glows brighter when their aligned force is strong
	if not _mesh_node:
		return

	var mat: Material = _mesh_node.get_surface_override_material(0)
	if not mat or not mat is StandardMaterial3D:
		return

	var std_mat := mat as StandardMaterial3D
	var intensity := new_value / 100.0
	std_mat.emission_energy_multiplier = _base_emission_energy + intensity * 1.5

	# Scale pulse at high force
	if new_value > 70.0:
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3(1.05, 1.1, 1.05), 0.2)
		tween.tween_property(self, "scale", Vector3.ONE, 0.3)


func _find_mesh() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null


func _exit_tree() -> void:
	if GameState and GameState.force_changed.is_connected(_on_force_changed):
		GameState.force_changed.disconnect(_on_force_changed)


# --- E2: Language Degradation ---
# As trust drops, NPC grammar simplifies and vocabulary shrinks.
# Certainty words INCREASE as actual certainty decreases.
# The Keeper never degrades — the contrast is the cruelty.

const CERTAINTY_WORDS := ["always", "never", "definitely", "absolutely", "everyone", "no one", "certain"]
const DEGRADED_CONNECTORS := ["and", "but", "so"]
const REFLECTIVE_QUESTIONS := [
	"Do you even know why you came here?",
	"When was the last time you decided something on your own?",
	"What would you do if the Keeper stopped speaking?",
	"Are you looking for truth or just for someone to tell you what's true?",
	"Did you decide that, or were you told to?",
	"How many of your choices were actually yours?",
	"What are you afraid of finding out?",
]

## E2: Apply language degradation to dialogue based on trust level.
func _apply_language_degradation(dialogue: Array) -> Array:
	var trust := TrustDestruction.trust_level
	if trust > 0.7:
		return dialogue  # No degradation at high trust

	var degradation := 1.0 - clampf((trust - 0.15) / 0.55, 0.0, 1.0)  # 0.0 at trust 0.7, 1.0 at trust 0.15

	for i in range(dialogue.size()):
		var entry: Dictionary = dialogue[i]
		if not entry.has("text"):
			continue
		var text: String = entry["text"]

		# Simplify sentence structure at medium degradation
		if degradation > 0.3:
			text = _simplify_grammar(text, degradation)

		# Insert certainty words at high degradation
		if degradation > 0.5 and randf() < degradation * 0.4:
			text = _inject_certainty(text)

		dialogue[i]["text"] = text

	return dialogue


## Simplify grammar: shorter sentences, simpler connectors.
func _simplify_grammar(text: String, degradation: float) -> String:
	# Replace complex punctuation with periods
	if degradation > 0.6:
		text = text.replace(";", ".")
		text = text.replace(" — ", ". ")
	# At extreme degradation, strip subordinate clauses (rough heuristic)
	if degradation > 0.8:
		var sentences := text.split(". ")
		if sentences.size() > 2:
			# Keep only first two sentences
			text = sentences[0] + ". " + sentences[1] + "."
	return text


## Inject certainty words — the more uncertain the world, the more certain the NPC sounds.
func _inject_certainty(text: String) -> String:
	var word: String = CERTAINTY_WORDS[randi() % CERTAINTY_WORDS.size()]
	# Prepend certainty as emphasis
	if randf() < 0.5:
		return "%s, %s" % [word.capitalize(), text[0].to_lower() + text.substr(1)]
	return text


# --- E3: Self-Doubt Hooks ---

## Inject reflective questions that have no response option.
## These are questions the player cannot answer. They sit there.
func _inject_self_doubt_hooks(dialogue: Array) -> Array:
	# Only inject at lower trust or after misuse
	var should_inject := TrustDestruction.trust_level < 0.6
	if not should_inject and TruthMisuse and TruthMisuse.has_misuse_history():
		should_inject = true
	if not should_inject:
		return dialogue

	# 12% chance per interaction
	if randf() >= 0.12:
		return dialogue

	var question: String = REFLECTIVE_QUESTIONS[randi() % REFLECTIVE_QUESTIONS.size()]
	# Insert before the last line (before choices if present)
	var insert_pos := dialogue.size() - 1
	if insert_pos < 0:
		insert_pos = 0
	dialogue.insert(insert_pos, {"speaker": npc_name, "text": question})

	return dialogue


# --- E3: Journal Auto-Fill ---

## Auto-fill the player journal with an interpretation of the NPC interaction.
## These are NOT facts — they're what the player THINKS happened.
func _auto_journal_interpretation() -> void:
	if randf() >= 0.25:  # 25% chance per interaction
		return

	var dominant := GameState.get_dominant_force()
	var trust := TrustDestruction.trust_level
	var interpretations := []

	if trust < 0.4:
		interpretations = [
			"%s seemed nervous. Probably lying." % npc_name,
			"I don't think %s was telling the truth about %s." % [npc_name, dominant],
			"%s knows more than they're saying." % npc_name,
			"Can't trust %s. Can't trust anyone right now." % npc_name,
		]
	elif trust < 0.7:
		interpretations = [
			"%s mentioned %s. Hard to know if it matters." % [npc_name, dominant],
			"Spoke to %s. They seemed... uncertain about things." % npc_name,
			"I think %s was being honest. I think." % npc_name,
		]
	else:
		interpretations = [
			"Spoke to %s. Nothing unusual." % npc_name,
			"%s seems to know what's happening around here." % npc_name,
		]

	var text: String = interpretations[randi() % interpretations.size()]

	# E3: Check for contradiction with existing entries
	var contradiction := GameState.check_journal_contradiction(text)
	GameState.add_journal_interpretation(text, true)


# --- B3: Context Withholding ---

## Remove detail lines from dialogue when context is being withheld.
func _apply_context_withholding(dialogue: Array) -> Array:
	if dialogue.size() <= 2:
		return dialogue  # Don't strip if too short
	# Remove 1-2 non-essential lines (not first, not last, not choices)
	var removable: Array[int] = []
	for i in range(1, dialogue.size() - 1):
		if not dialogue[i].has("choices") and not dialogue[i].has("id"):
			removable.append(i)
	if removable.is_empty():
		return dialogue
	# Remove one line
	var idx: int = removable[randi() % removable.size()]
	dialogue.remove_at(idx)
	return dialogue


# --- 12: NPC Eye Behavior ---
# At low honest metric: NPCs look past the player (through them, 1-3m behind)
# During silence fallout: eye contact holds 300ms too long, then snaps away
# Keeper eye contact is perfectly timed, always (handled by VisualDecay)
# This adjusts the NPC's visual look-at target. No verbal acknowledgment.

## Cached look-at offset for smooth interpolation
var _eye_target_offset: Vector3 = Vector3.ZERO


## Apply eye behavior offset to this NPC's look-at target.
## The NPC looks at player_position + offset, creating subtle wrongness.
func _apply_eye_behavior() -> void:
	if not VisualDecay:
		return
	var target_offset := VisualDecay.get_npc_eye_target_offset(false)
	# Smooth interpolation — don't snap between modes
	_eye_target_offset = _eye_target_offset.lerp(target_offset, 0.15)

	# Apply to mesh rotation if we have a player to look at
	var player := get_tree().get_first_node_in_group("player")
	if not player or not player is Node3D or not _mesh_node:
		return

	# Only adjust if there's a meaningful offset
	if _eye_target_offset.length() < 0.05:
		return

	# Look toward player position + offset (creates "looking through/past" effect)
	var look_target: Vector3 = player.global_position + _eye_target_offset
	var dir_to_target := (look_target - _mesh_node.global_position).normalized()
	if dir_to_target.length() > 0.01:
		# Subtle rotation toward offset target (head turn, not full body)
		var current_basis := _mesh_node.global_transform.basis
		var target_basis := Basis.looking_at(dir_to_target)
		_mesh_node.global_transform.basis = current_basis.slerp(target_basis, 0.08)


# --- Trust-Aware World State Queries ---
# Regular NPCs should use these instead of reading GameState directly.
# These methods check TrustDestruction and may return corrupted values.
# The Keeper NPC bypasses this entirely by reading GameState directly.

## Get a force value as this NPC would report it (potentially corrupted).
func _get_reported_force(force_name: String) -> float:
	var real_value := GameState.get_force(force_name)
	if TrustDestruction.should_tell_truth(self):
		return real_value
	TrustDestruction.record_lie("dialogue_lie", {"npc": npc_name, "force": force_name})
	return TrustDestruction.corrupt_force_value(real_value)


## Get a god state as this NPC would report it (potentially corrupted).
func _get_reported_god_state(god_id: String) -> String:
	var real_state := GodManager.get_god_state(god_id)
	if TrustDestruction.should_tell_truth(self):
		return real_state
	TrustDestruction.record_lie("dialogue_lie", {"npc": npc_name, "god": god_id})
	return TrustDestruction.corrupt_god_state(real_state)


## Get the dominant force as this NPC would report it (potentially wrong).
func _get_reported_dominant_force() -> String:
	if TrustDestruction.should_tell_truth(self):
		return GameState.get_dominant_force()
	# Lie: report a different force as dominant
	var forces := ["faith", "truth", "violence"]
	var real_dominant := GameState.get_dominant_force()
	forces.erase(real_dominant)
	var false_dominant: String = forces[randi() % forces.size()]
	TrustDestruction.record_lie("dialogue_lie", {"npc": npc_name, "type": "dominant_force"})
	return false_dominant


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"has_spoken": has_spoken,
	}


func load_state(data: Dictionary) -> void:
	has_spoken = data.get("has_spoken", false)
