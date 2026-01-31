## NPC: Local Survivor — Represents the third faction interest (locals who want survival).
## Not aligned to any force. Offers a timed quest with no good outcome.
extends NPCBase


func _ready() -> void:
	npc_name = "Maren"
	force_affinity = "neutral"
	super._ready()

	# Timed quest — Maren needs supplies from a dangerous area.
	# Time pressure creates escalation. Completing it adds violence (dangerous trip).
	# Failing it means Maren's camp collapses.
	QuestManager.register_quest({
		"id": "borderland_supplies",
		"title": "What the Living Need",
		"description": "Maren's camp is running low. Supplies are scattered in the machine hall — but something watches from the ruins.",
		"giver": "Maren",
		"force_affinity": "neutral",
		"time_limit": 120.0,
		"objectives": [
			{"id": "get_supplies", "description": "Find supplies in the machine hall", "type": "collect", "target": "camp_supplies", "completed": false},
			{"id": "return_supplies", "description": "Bring supplies to Maren", "type": "talk", "target": "npc_local_survivor", "completed": false},
		],
		"rewards": {
			"force": "violence", "force_amount": 3.0,
			"faction": "ashwalkers", "faction_amount": -5.0,
		},
	})


func _get_dialogue() -> Array:
	if GameState.witness_mode:
		return _dialogue_witness()

	if WorldEventManager._ending_triggered:
		return _dialogue_post_ending()

	if WorldMemory.has_memory("maren_camp_fell"):
		return [
			{"speaker": npc_name, "text": "The camp is gone. We couldn't hold. There's nothing left to save here."},
		]

	if QuestManager.is_quest_completed("borderland_supplies"):
		return _dialogue_post_quest()

	if QuestManager.is_quest_active("borderland_supplies") and ItemManager.has_item("camp_supplies"):
		QuestManager.notify_event("talk", "npc_local_survivor")
		ItemManager.remove_item("camp_supplies")
		return _dialogue_deliver_supplies()

	if QuestManager.is_quest_active("borderland_supplies"):
		return _dialogue_quest_reminder()

	# Quest failed by timeout
	if QuestManager.quests.has("borderland_supplies"):
		var q: Dictionary = QuestManager.quests["borderland_supplies"]
		if q.get("state", 0) == QuestManager.QuestState.FAILED:
			WorldMemory.record("maren_camp_fell")
			return [
				{"speaker": npc_name, "text": "Too late. The camp is already breaking apart."},
				{"speaker": npc_name, "text": "People don't wait for heroes. They just... leave."},
			]

	return _dialogue_offer_quest()


func _dialogue_offer_quest() -> Array:
	var pressure := GameState.world_pressure
	var greeting := ""

	if pressure > 60:
		greeting = "Please. I know the world is coming apart. But people are still alive. That has to count for something."
	elif GameState.violence > 40:
		greeting = "I can hear the fighting from here. My camp is falling apart. We need supplies — not sermons, not data. Supplies."
	else:
		greeting = "Traveler. I don't care about your gods or your theories. I care about the people in that camp."

	return [
		{"speaker": npc_name, "text": greeting},
		{"speaker": npc_name, "text": "There are supplies in the machine hall to the east. Food, medicine, tools. But something's in there — the ash walkers won't go near it."},
		{"speaker": npc_name, "text": "Will you help?",
			"choices": [
				{"text": "I'll get your supplies.", "force": "faith", "amount": 1.0, "next_id": "accept"},
				{"text": "What's in the machine hall?", "force": "truth", "amount": 1.0, "next_id": "ask"},
				{"text": "What do I get out of it?", "force": "violence", "amount": 1.0, "next_id": "negotiate"},
			]
		},
		{"id": "accept", "speaker": npc_name, "text": "Thank you. Hurry — we don't have long. The supplies are on the second floor, near the old generators."},
		{"id": "ask", "speaker": npc_name, "text": "I don't know. The Ash Walkers say it's a god's territory. The scholars say it's unstable infrastructure. Either way, people die in there."},
		{"id": "negotiate", "speaker": npc_name, "text": "Survival. That's what you get. The camp feeds anyone who helps. Including you."},
	]


func interact(player: Node) -> void:
	if DialogueManager.is_active:
		return

	var dialogue := _get_dialogue()
	if dialogue.size() > 0:
		DialogueManager.start_dialogue(dialogue, npc_name)
		has_spoken = true

		if not QuestManager.is_quest_active("borderland_supplies") and not QuestManager.is_quest_completed("borderland_supplies"):
			var q = QuestManager.quests.get("borderland_supplies", {})
			if q.get("state", 0) == QuestManager.QuestState.AVAILABLE:
				DialogueManager.dialogue_ended.connect(_on_offer_ended, CONNECT_ONE_SHOT)


func _on_offer_ended() -> void:
	QuestManager.accept_quest("borderland_supplies")


func _dialogue_deliver_supplies() -> Array:
	return [
		{"speaker": npc_name, "text": "You made it. I can see the relief on their faces already."},
		{"speaker": npc_name, "text": "The Ash Walkers won't be happy — they think that hall belongs to Verath. But people needed this more than any god does.",
			"choices": [
				{"text": "Verath would want her people fed.", "force": "faith", "amount": 2.0},
				{"text": "Resources go where they're needed.", "force": "truth", "amount": 2.0},
				{"text": "I had to fight my way through.", "force": "violence", "amount": 2.0},
			]
		},
	]


func _dialogue_quest_reminder() -> Array:
	var remaining := QuestManager.get_time_remaining("borderland_supplies")
	if remaining < 30.0:
		return [
			{"speaker": npc_name, "text": "Please hurry. I can hear the camp arguing about leaving. There's no time."},
		]
	return [
		{"speaker": npc_name, "text": "The machine hall. East of here. Second floor near the generators. Please — don't forget about us."},
	]


func _dialogue_post_quest() -> Array:
	return [
		{"speaker": npc_name, "text": "The camp is stable. For now. That's all anyone can ask for."},
		{"speaker": npc_name, "text": "The gods fight their wars. We just try to survive between the footsteps."},
	]


func _dialogue_post_ending() -> Array:
	return [
		{"speaker": npc_name, "text": "...So this is how it ends. Not with a prayer or a theorem. Just... silence."},
		{"speaker": npc_name, "text": "The camp is empty. Everyone left — or stopped. I'm still here. I don't know why."},
	]


func _dialogue_witness() -> Array:
	return [
		{"speaker": "...", "text": "Maren's camp is empty. Bedrolls still arranged in a circle. A pot hangs over cold ashes."},
		{"speaker": "...", "text": "Someone scratched words into the ground: 'We waited.'"},
	]
