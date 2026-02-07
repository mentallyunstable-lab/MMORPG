## NPCBase — Interactable NPC with dialogue and force-reactive behavior.
## Regular NPCs are subject to TrustDestruction — they may report corrupted world state.
## The Keeper (anchor NPC) overrides this behavior and always tells truth.
## Use _get_reported_force() and _get_reported_god_state() instead of reading GameState directly
## when building dialogue that describes the world to the player.
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

	if dialogue.size() > 0:
		DialogueManager.start_dialogue(dialogue, npc_name)
		has_spoken = true


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
