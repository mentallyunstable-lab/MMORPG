## GodEncounter — A location where the player can directly interact with a god's presence.
## The encounter changes based on the god's stability and the player's forces.
class_name GodEncounter
extends Interactable

@export var god_id: String = "verath"
@export var faith_cost: float = 5.0
@export var truth_cost: float = 5.0

var _encounter_triggered: bool = false


func _ready() -> void:
	super._ready()
	one_time = false
	interaction_text = "Approach the presence"


func _on_interact(player: Node) -> void:
	if DialogueManager.is_active:
		return

	var god_name := GodManager.get_god_name(god_id)
	var state := GodManager.get_god_state(god_id)
	var stability := GameState.get_god_stability(god_id)

	var dialogue := _build_encounter_dialogue(god_name, state, stability)
	DialogueManager.start_dialogue(dialogue, god_name)

	if not _encounter_triggered:
		_encounter_triggered = true
		WorldEventManager.event_notification.emit(
			"God Encounter",
			"You stand before %s." % god_name
		)


func _build_encounter_dialogue(god_name: String, state: String, stability: float) -> Array:
	match state:
		"dead":
			return _dialogue_dead(god_name)
		"fading":
			return _dialogue_fading(god_name, stability)
		"weakened":
			return _dialogue_weakened(god_name, stability)
		"manifest":
			return _dialogue_manifest(god_name, stability)
		"ascended":
			return _dialogue_ascended(god_name)
		_:
			return _dialogue_dormant(god_name, stability)


func _dialogue_dead(god_name: String) -> Array:
	return [
		{"speaker": "???", "text": "..."},
		{"speaker": "Narration", "text": "The presence is gone. Where %s once was, there is only cold ash." % god_name},
		{"speaker": "Narration", "text": "You feel nothing. That is the point.",
			"choices": [
				{"text": "Pray anyway.", "force": "faith", "amount": 3.0},
				{"text": "Acknowledge the absence.", "force": "truth", "amount": 2.0},
				{"text": "Good riddance.", "force": "violence", "amount": 2.0},
			]
		},
	]


func _dialogue_fading(god_name: String, stability: float) -> Array:
	return [
		{"speaker": god_name, "text": "...can you... hear..."},
		{"speaker": "Narration", "text": "The voice is barely a whisper. %s is fading. Stability: %.0f." % [god_name, stability]},
		{"speaker": god_name, "text": "...faith... I need...",
			"choices": [
				{"text": "Offer a prayer. (+Faith, stabilizes god)", "force": "faith", "amount": faith_cost, "next_id": "pray"},
				{"text": "Study the fading. (+Truth, erodes god)", "force": "truth", "amount": truth_cost, "next_id": "study"},
				{"text": "End it. (+Violence)", "force": "violence", "amount": 5.0, "next_id": "destroy"},
			]
		},
		{"id": "pray", "speaker": god_name, "text": "...warmth... thank you..."},
		{"id": "study", "speaker": "Narration", "text": "You observe the fading. Data is data, even when it hurts."},
		{"id": "destroy", "speaker": "Narration", "text": "You reach into the presence and tear. The whisper screams — then stops."},
	]


func _dialogue_weakened(god_name: String, stability: float) -> Array:
	return [
		{"speaker": god_name, "text": "You come to me... in this state. I am not what I was."},
		{"speaker": "Narration", "text": "%s speaks, but weakly. Stability: %.0f." % [god_name, stability]},
		{"speaker": god_name, "text": "What would you ask of me?",
			"choices": [
				{"text": "Grant me your blessing. (+Faith)", "force": "faith", "amount": faith_cost, "next_id": "bless"},
				{"text": "Tell me the truth of your existence. (+Truth)", "force": "truth", "amount": truth_cost, "next_id": "question"},
				{"text": "Give me power or I'll take it. (+Violence)", "force": "violence", "amount": 5.0, "next_id": "demand"},
			]
		},
		{"id": "bless", "speaker": god_name, "text": "...my blessing is ash. But it is yours."},
		{"id": "question", "speaker": god_name, "text": "I am... a pattern. Belief made manifest. Without faith, I dissolve."},
		{"id": "demand", "speaker": god_name, "text": "...then take it. I have little left to give, and less to defend."},
	]


func _dialogue_dormant(god_name: String, stability: float) -> Array:
	return [
		{"speaker": god_name, "text": "Traveler. You stand before me."},
		{"speaker": "Narration", "text": "%s is present but quiet. Stability: %.0f." % [god_name, stability]},
		{"speaker": god_name, "text": "Speak.",
			"choices": [
				{"text": "I come to worship. (+Faith)", "force": "faith", "amount": faith_cost, "next_id": "worship"},
				{"text": "I come to understand. (+Truth)", "force": "truth", "amount": truth_cost, "next_id": "understand"},
				{"text": "I come for power. (+Violence)", "force": "violence", "amount": 3.0, "next_id": "power"},
			]
		},
		{"id": "worship", "speaker": god_name, "text": "Your faith sustains me. I will remember you when the ash clears."},
		{"id": "understand", "speaker": god_name, "text": "Understanding is a knife. You may not like what you cut open."},
		{"id": "power", "speaker": god_name, "text": "Power given freely is no power at all. You must earn — or take."},
	]


func _dialogue_manifest(god_name: String, stability: float) -> Array:
	return [
		{"speaker": god_name, "text": "I AM HERE."},
		{"speaker": "Narration", "text": "%s is fully manifest. The air shimmers. Stability: %.0f." % [god_name, stability]},
		{"speaker": god_name, "text": "You have given me form. What is your desire?",
			"choices": [
				{"text": "Protect this world. (+Faith)", "force": "faith", "amount": faith_cost, "next_id": "protect"},
				{"text": "Show me the truth behind divinity. (+Truth)", "force": "truth", "amount": truth_cost, "next_id": "reveal"},
				{"text": "Destroy my enemies. (+Violence)", "force": "violence", "amount": 5.0, "next_id": "wrath"},
			]
		},
		{"id": "protect", "speaker": god_name, "text": "This world is ash and memory. I will protect what remains."},
		{"id": "reveal", "speaker": god_name, "text": "...you would unmake me to understand me. Very well. Look."},
		{"id": "wrath", "speaker": god_name, "text": "So be it. The ash will run red."},
	]


func _dialogue_ascended(god_name: String) -> Array:
	return [
		{"speaker": god_name, "text": "I HAVE TRANSCENDED."},
		{"speaker": "Narration", "text": "Reality bends around %s. This is no longer a conversation — it is an audience." % god_name},
		{"speaker": god_name, "text": "Kneel, question, or challenge. All paths lead to ash.",
			"choices": [
				{"text": "Kneel. (+Faith)", "force": "faith", "amount": 8.0},
				{"text": "I will not kneel to a pattern. (+Truth)", "force": "truth", "amount": 8.0},
				{"text": "Even gods can bleed. (+Violence)", "force": "violence", "amount": 8.0},
			]
		},
	]


func save_state() -> Dictionary:
	var base := super.save_state()
	base["encounter_triggered"] = _encounter_triggered
	return base


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	_encounter_triggered = data.get("encounter_triggered", false)
