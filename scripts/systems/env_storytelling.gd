## EnvironmentalStorytelling — Static micro-scenes that tell stories without dialogue.
## 3 micro-scenes, 1 lying scene, 1 unreachable landmark.
## Interacting reads a narration. The lying scene gives false information.
class_name EnvironmentalStorytelling
extends Interactable

enum SceneType { MICRO_SCENE, LYING_SCENE, UNREACHABLE }

@export var scene_type: SceneType = SceneType.MICRO_SCENE
@export var scene_id: String = ""

# Each micro-scene has a narration that changes based on world state
var _narrations: Dictionary = {}


func _ready() -> void:
	super._ready()
	one_time = false
	_setup_narrations()


func _setup_narrations() -> void:
	# --- Micro-Scene 1: Burned Shrine ---
	# A small shrine that was burned by violence. Tells you about faith's cost.
	_narrations["burned_shrine"] = {
		"default": [
			{"speaker": "Narration", "text": "A shrine, half-collapsed. Candle stubs melted into the stone."},
			{"speaker": "Narration", "text": "Someone prayed here once. The scorch marks suggest someone else disagreed."},
		],
		"high_faith": [
			{"speaker": "Narration", "text": "The candle stubs flicker — impossible, since there's no wick left."},
			{"speaker": "Narration", "text": "The shrine hums. It remembers devotion. Even in ruin, faith persists."},
		],
		"high_violence": [
			{"speaker": "Narration", "text": "The scorch marks are fresh. Or they look fresh. Violence refreshes its own evidence."},
			{"speaker": "Narration", "text": "Someone added new burns recently. The cycle repeats."},
		],
	}

	# --- Micro-Scene 2: Broken Machine ---
	# Old technology, partially dismantled by truth seekers.
	_narrations["broken_machine"] = {
		"default": [
			{"speaker": "Narration", "text": "A machine of unknown purpose. Gears exposed, panels removed."},
			{"speaker": "Narration", "text": "Tool marks suggest methodical disassembly. Someone wanted to understand this."},
		],
		"high_truth": [
			{"speaker": "Narration", "text": "The machine's internal structure is precisely documented in chalk on the floor."},
			{"speaker": "Narration", "text": "Someone understood it completely. Then left it open, exposed. Knowledge without repair."},
		],
		"high_violence": [
			{"speaker": "Narration", "text": "Several gears have been bent by force — not curiosity. Someone hit this."},
			{"speaker": "Narration", "text": "Understanding and destruction wear different faces, but the machine is broken either way."},
		],
	}

	# --- Micro-Scene 3: Mass Grave ---
	# A shallow depression with personal effects scattered.
	_narrations["mass_grave"] = {
		"default": [
			{"speaker": "Narration", "text": "A depression in the ground. Shoes, broken tools, a child's toy."},
			{"speaker": "Narration", "text": "No headstones. No names. Just objects that outlived their owners."},
		],
		"high_faith": [
			{"speaker": "Narration", "text": "Someone placed flowers here recently. They've already wilted in the ash."},
			{"speaker": "Narration", "text": "Faith marks the dead. But the dead don't notice."},
		],
		"high_truth": [
			{"speaker": "Narration", "text": "A truth seeker left notes here: body count, cause estimates, time of burial."},
			{"speaker": "Narration", "text": "The data is thorough. The grief is absent. Facts and feelings occupy different graves."},
		],
	}

	# --- Lying Scene: The Memorial ---
	# This scene gives false information. It tells the player a god was merciful
	# when the god was actually violent. The world lies to the player.
	_narrations["lying_memorial"] = {
		"default": [
			{"speaker": "Narration", "text": "A stone memorial. The inscription reads: 'Here Verath showed mercy.'"},
			{"speaker": "Narration", "text": "'The Ash Mother spared the village below. Her warmth held back the fire.'"},
			{"speaker": "Narration", "text": "The stone is old. The words are confident. The village below is gone."},
		],
		"high_truth": [
			{"speaker": "Narration", "text": "A stone memorial. The inscription reads: 'Here Verath showed mercy.'"},
			{"speaker": "Narration", "text": "But the ground tells a different story. Blast patterns. Char lines radiating from this exact spot."},
			{"speaker": "Narration", "text": "The memorial lies. Someone wanted to remember it differently."},
		],
	}

	# --- Unreachable Landmark: The Distant Spire ---
	# Visible from the test zone but never reachable. Creates longing.
	_narrations["distant_spire"] = {
		"default": [
			{"speaker": "Narration", "text": "A spire rises from the ash wastes, impossibly far away."},
			{"speaker": "Narration", "text": "It glimmers — stone or metal or something else entirely. You can't tell from here."},
			{"speaker": "Narration", "text": "You will never reach it. That is not a challenge. It is a fact."},
		],
	}

	# --- Witness-Only Interaction: The Door That Was Never There ---
	# Only appears/responds in witness mode. An unreachable interaction.
	_narrations["witness_door"] = {
		"default": [
			{"speaker": "Narration", "text": "There is nothing here."},
		],
		"witness": [
			{"speaker": "...", "text": "A door stands in the ruins. You don't remember it being here before."},
			{"speaker": "...", "text": "It's made of ash-grey wood. The handle is warm."},
			{"speaker": "...", "text": "You try to open it. It doesn't move."},
			{"speaker": "...", "text": "You try again. Nothing."},
			{"speaker": "...", "text": "It was never meant to open. It was only ever meant to be here, after everything else was gone."},
		],
	}


func _on_interact(_player: Node) -> void:
	if DialogueManager.is_active:
		return

	var narration := _get_narration()
	if narration.size() > 0:
		DialogueManager.start_dialogue(narration, "...")
		WorldMemory.record("examined_%s" % scene_id)


func _get_narration() -> Array:
	if not _narrations.has(scene_id):
		return [{"speaker": "Narration", "text": "Something is here. You're not sure what it means."}]

	var variants: Dictionary = _narrations[scene_id]

	# Witness mode: check for witness-specific variant
	if GameState.witness_mode and variants.has("witness"):
		return variants["witness"]

	# Check world state for variant selection
	if scene_type == SceneType.LYING_SCENE:
		# Lying scene: only reveals the truth at high truth values
		if GameState.truth >= 60.0 and variants.has("high_truth"):
			return variants["high_truth"]
		return variants.get("default", [])

	if scene_type == SceneType.UNREACHABLE:
		return variants.get("default", [])

	# Micro-scenes select variant based on dominant force
	var dominant := GameState.get_dominant_force()
	if dominant == "faith" and GameState.faith >= 50.0 and variants.has("high_faith"):
		return variants["high_faith"]
	elif dominant == "truth" and GameState.truth >= 50.0 and variants.has("high_truth"):
		return variants["high_truth"]
	elif dominant == "violence" and GameState.violence >= 50.0 and variants.has("high_violence"):
		return variants["high_violence"]

	return variants.get("default", [])
