## NPC: Ash Walker — First faction encounter. Offers a quest to recover a relic.
## Force affinity: Faith. Reacts to truth/violence with hostility.
extends NPCBase


func _ready() -> void:
	npc_name = "Ash Walker"
	force_affinity = "faith"
	super._ready()

	# Register the relic quest
	QuestManager.register_quest({
		"id": "ash_relic",
		"title": "Ashes of the Forgotten",
		"description": "The Ash Walker asks you to recover a relic from the nearby ruins. It belonged to Verath before the ashfall.",
		"giver": "Ash Walker",
		"force_affinity": "faith",
		"objectives": [
			{"id": "find_relic", "description": "Find the Ash Relic in the ruins", "type": "collect", "target": "ash_relic", "completed": false},
			{"id": "return_relic", "description": "Return the Ash Relic to the Ash Walker", "type": "talk", "target": "npc_ashwalker", "completed": false},
		],
		"rewards": {
			"force": "faith", "force_amount": 10.0,
			"faction": "ashwalkers", "faction_amount": 15.0,
			"items": ["health_potion"],
		},
	})


func _get_dialogue() -> Array:
	# Ending reached — acknowledge the final state
	if WorldEventManager._ending_triggered:
		return _dialogue_post_ending()

	# Quest complete
	if QuestManager.is_quest_completed("ash_relic"):
		return _dialogue_post_quest()

	# Quest active, player has relic
	if QuestManager.is_quest_active("ash_relic") and ItemManager.has_item("ash_relic"):
		QuestManager.notify_event("talk", "npc_ashwalker")
		ItemManager.remove_item("ash_relic")
		return _dialogue_deliver_relic()

	# Quest active, no relic yet
	if QuestManager.is_quest_active("ash_relic"):
		return _dialogue_quest_reminder()

	# Quest not started — offer it
	return _dialogue_offer_quest()


func _dialogue_offer_quest() -> Array:
	var greeting := "..."
	var dominant := GameState.get_dominant_force()

	if dominant == "violence" and GameState.violence > 50:
		greeting = "You reek of blood. I should not trust you... but I have no one else."
	elif dominant == "truth" and GameState.truth > 50:
		greeting = "A seeker of truth. The gods do not appreciate your kind. But perhaps you can help regardless."
	else:
		greeting = "Traveler. The ash remembers those who walk with purpose."

	return [
		{"speaker": npc_name, "text": greeting},
		{"speaker": npc_name, "text": "I am searching for a relic — an artifact of Verath, the Ash Mother. It was lost when the ashfall came."},
		{"speaker": npc_name, "text": "Will you help me find it?",
			"choices": [
				{"text": "I'll find your relic. (Accept quest)", "force": "faith", "amount": 2.0, "next_id": "accept"},
				{"text": "What's in it for me?", "force": "truth", "amount": 1.0, "next_id": "negotiate"},
				{"text": "Give me a reason not to take it myself.", "force": "violence", "amount": 2.0, "next_id": "threaten"},
			]
		},
		{"id": "accept", "speaker": npc_name, "text": "Thank you. The relic should be somewhere in the ruins to the north. It hums with warmth — you'll know it."},
		{"id": "negotiate", "speaker": npc_name, "text": "You'd weigh faith against profit? ...Fine. I can offer healing supplies. But the relic comes to me."},
		{"id": "threaten", "speaker": npc_name, "text": "...I see. Then take it. But know this — Verath does not forget those who steal from her children."},
	]


func interact(player: Node) -> void:
	if DialogueManager.is_active:
		return

	var dialogue := _get_dialogue()
	if dialogue.size() > 0:
		DialogueManager.start_dialogue(dialogue, npc_name)
		has_spoken = true

		# Accept quest after dialogue if not already active
		if not QuestManager.is_quest_active("ash_relic") and not QuestManager.is_quest_completed("ash_relic"):
			# Quest gets accepted when dialogue ends
			DialogueManager.dialogue_ended.connect(_on_offer_dialogue_ended, CONNECT_ONE_SHOT)


func _on_offer_dialogue_ended() -> void:
	QuestManager.accept_quest("ash_relic")


func _dialogue_deliver_relic() -> Array:
	return [
		{"speaker": npc_name, "text": "You found it... I can feel Verath's warmth even now."},
		{"speaker": npc_name, "text": "Thank you, traveler. The Ash Walkers will remember this.",
			"choices": [
				{"text": "The rites must continue.", "force": "faith", "amount": 3.0},
				{"text": "It belonged somewhere. Now it does.", "force": "truth", "amount": 1.0},
				{"text": "You owe me.", "force": "violence", "amount": 2.0},
			]
		},
	]


func _dialogue_quest_reminder() -> Array:
	return [
		{"speaker": npc_name, "text": "The relic... have you found it? It should be in the ruins to the north."},
		{"speaker": npc_name, "text": "It hums with warmth. Verath's warmth. You'll know it when you're close."},
	]


func _dialogue_post_ending() -> Array:
	return [
		{"speaker": npc_name, "text": "...It's over, isn't it. I can feel it in the ash — the world has chosen its shape."},
		{"speaker": npc_name, "text": "Whatever comes next... the Ash Walkers will endure. We always have."},
	]


func _dialogue_post_quest() -> Array:
	var dominant := GameState.get_dominant_force()
	var stability := GameState.get_god_stability("verath")

	if stability < 25:
		return [
			{"speaker": npc_name, "text": "Verath grows dim... even with the relic returned. The truth-seekers erode what's left."},
		]
	elif stability > 75:
		return [
			{"speaker": npc_name, "text": "Can you feel it? Verath stirs. The ash carries her warmth again."},
		]
	else:
		return [
			{"speaker": npc_name, "text": "The relic is safe. The Ash Walkers thank you, traveler."},
		]
