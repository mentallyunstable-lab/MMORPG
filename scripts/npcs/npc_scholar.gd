## NPC: Shattered Scholar — Truth faction. Offers a quest to find a Void Fragment.
## Opposes faith, values observation over belief.
extends NPCBase


func _ready() -> void:
	npc_name = "Shattered Scholar"
	force_affinity = "truth"
	super._ready()

	QuestManager.register_quest({
		"id": "void_fragment",
		"title": "What the Throne Left Behind",
		"description": "The Scholar believes the Null Throne left fragments of itself across the ash wastes. One may be nearby.",
		"giver": "Shattered Scholar",
		"force_affinity": "truth",
		"objectives": [
			{"id": "find_fragment", "description": "Find the Void Fragment", "type": "collect", "target": "void_fragment", "completed": false},
			{"id": "return_fragment", "description": "Bring it to the Scholar", "type": "talk", "target": "npc_scholar", "completed": false},
		],
		"rewards": {
			"force": "truth", "force_amount": 10.0,
			"faction": "truthseekers", "faction_amount": 15.0,
			"items": ["truth_lens"],
		},
	})


func _get_dialogue() -> Array:
	# Ending reached — acknowledge the final state
	if WorldEventManager._ending_triggered:
		return _dialogue_post_ending()

	if QuestManager.is_quest_completed("void_fragment"):
		return _dialogue_post_quest()

	if QuestManager.is_quest_active("void_fragment") and ItemManager.has_item("void_fragment"):
		QuestManager.notify_event("talk", "npc_scholar")
		ItemManager.remove_item("void_fragment")
		return _dialogue_deliver_fragment()

	if QuestManager.is_quest_active("void_fragment"):
		return _dialogue_quest_reminder()

	return _dialogue_offer_quest()


func _dialogue_offer_quest() -> Array:
	var dominant := GameState.get_dominant_force()

	var greeting := ""
	if dominant == "faith" and GameState.faith > 50:
		greeting = "The air is thick with devotion. Hard to see through it. I need something tangible."
	elif dominant == "violence" and GameState.violence > 50:
		greeting = "The world shakes with violence. Hard to study anything when the ground bleeds."
	else:
		greeting = "You. You look like someone who notices things."

	return [
		{"speaker": npc_name, "text": greeting},
		{"speaker": npc_name, "text": "The Null Throne — the god-shaped hole in reality. It left fragments. I need one."},
		{"speaker": npc_name, "text": "Will you search for it?",
			"choices": [
				{"text": "I'll look for it. (Accept quest)", "force": "truth", "amount": 2.0, "next_id": "accept"},
				{"text": "What does it do?", "force": "truth", "amount": 1.0, "next_id": "ask"},
				{"text": "Sounds dangerous. What's the pay?", "force": "violence", "amount": 1.0, "next_id": "pay"},
			]
		},
		{"id": "accept", "speaker": npc_name, "text": "Good. It should be near the eastern edge of the zone. It looks like... nothing. Literally. A hole in an object."},
		{"id": "ask", "speaker": npc_name, "text": "It proves the Null Throne exists — or existed. Evidence that absence can have presence. The Shattered Lens needs this."},
		{"id": "pay", "speaker": npc_name, "text": "Knowledge. Understanding. Also, I have a lens that lets you see the world differently. It's yours if you bring the fragment."},
	]


func interact(player: Node) -> void:
	if DialogueManager.is_active:
		return

	var dialogue := _get_dialogue()
	if dialogue.size() > 0:
		DialogueManager.start_dialogue(dialogue, npc_name)
		has_spoken = true

		if not QuestManager.is_quest_active("void_fragment") and not QuestManager.is_quest_completed("void_fragment"):
			DialogueManager.dialogue_ended.connect(_on_offer_dialogue_ended, CONNECT_ONE_SHOT)


func _on_offer_dialogue_ended() -> void:
	QuestManager.accept_quest("void_fragment")


func _dialogue_deliver_fragment() -> Array:
	return [
		{"speaker": npc_name, "text": "This... this is it. A fragment of absence. It's heavier than it should be."},
		{"speaker": npc_name, "text": "The Null Throne was real. Or rather — it was real in its unreality.",
			"choices": [
				{"text": "What does this mean for the gods?", "force": "truth", "amount": 3.0},
				{"text": "Take it. I don't want to hold absence.", "force": "faith", "amount": 1.0},
				{"text": "This could be a weapon.", "force": "violence", "amount": 2.0},
			]
		},
	]


func _dialogue_quest_reminder() -> Array:
	return [
		{"speaker": npc_name, "text": "The fragment should be near the eastern ruins. Look for something that looks like... nothing at all."},
	]


func _dialogue_post_ending() -> Array:
	return [
		{"speaker": npc_name, "text": "...The data is conclusive. Something fundamental has shifted."},
		{"speaker": npc_name, "text": "Whatever was measured before — none of it applies now. We start from zero."},
	]


func _dialogue_post_quest() -> Array:
	var null_stability := GameState.get_god_stability("null_throne")

	if null_stability < 10:
		return [
			{"speaker": npc_name, "text": "The Null Throne... it's almost gone. Even absence can die, it seems."},
		]
	else:
		return [
			{"speaker": npc_name, "text": "I'm studying the fragment. The implications are... unsettling. Thank you, traveler."},
		]
