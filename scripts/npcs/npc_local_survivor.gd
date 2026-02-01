## NPC: Local Survivor — Represents the third faction interest (locals who want survival).
## Not aligned to any force. Offers a timed quest with no good outcome.
## Can enter a silent state (refuses all dialogue) or die offscreen.
extends NPCBase

# Silent state: Maren stops talking after witnessing too much violence
var _silent: bool = false
# Offscreen death: Maren can die between visits if conditions are met
var _dead_offscreen: bool = false


func _ready() -> void:
	npc_name = "Maren"
	force_affinity = "neutral"
	super._ready()

	# Check for offscreen death conditions on load
	_check_offscreen_death()

	# Listen for violence spikes that might trigger silent state
	GameState.force_changed.connect(_on_maren_force_changed)

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


## Check if Maren has died offscreen — conditions checked at load or on re-enter.
func _check_offscreen_death() -> void:
	if WorldMemory.has_memory("maren_dead_offscreen"):
		_dead_offscreen = true
		return
	# Maren dies offscreen if: violence >= 80 AND camp fell AND player hasn't visited in a while
	if WorldMemory.has_memory("maren_camp_fell") and GameState.violence >= 80.0:
		_dead_offscreen = true
		WorldMemory.record("maren_dead_offscreen")
		WorldMemory.record_ambient("Maren died — camp fell, violence consumed the borderland")


## Violence spikes can push Maren into silent state.
func _on_maren_force_changed(force_name: String, _old: float, new_value: float) -> void:
	if force_name != "violence":
		return
	# Maren goes silent if violence exceeds 70 and she has spoken before
	if new_value >= 70.0 and has_spoken and not _silent:
		_silent = true
		WorldMemory.record("maren_silent")
		WorldMemory.record_ambient("Maren stopped talking — too much violence")


func _get_dialogue() -> Array:
	if GameState.witness_mode:
		return _dialogue_witness()

	# Offscreen death — Maren is gone
	if _dead_offscreen:
		return _dialogue_offscreen_death()

	# Silent state — refuses all dialogue
	if _silent:
		return _dialogue_silent()

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
	var dominant := GameState.get_dominant_force()

	# Force-based dialogue trees — Maren reacts to the dominant force
	match dominant:
		"faith":
			return _dialogue_offer_faith_dominant()
		"truth":
			return _dialogue_offer_truth_dominant()
		"violence":
			return _dialogue_offer_violence_dominant()

	return _dialogue_offer_neutral()


func _dialogue_offer_faith_dominant() -> Array:
	return [
		{"speaker": npc_name, "text": "Everyone keeps praying. Praying for food. Praying for safety. Prayers don't fill stomachs."},
		{"speaker": npc_name, "text": "I need someone who does things, not someone who believes them into existence."},
		{"speaker": npc_name, "text": "There are supplies in the machine hall. Will you get them?",
			"choices": [
				{"text": "Faith sustains more than food.", "force": "faith", "amount": 2.0, "next_id": "faith_response"},
				{"text": "I'll get your supplies.", "force": "truth", "amount": 1.0, "next_id": "accept"},
				{"text": "What's in it for me?", "force": "violence", "amount": 1.0, "next_id": "negotiate"},
			]
		},
		{"id": "faith_response", "speaker": npc_name, "text": "Tell that to the children who haven't eaten since yesterday. ...Fine. The hall is to the east. Second floor."},
		{"id": "accept", "speaker": npc_name, "text": "Thank you. Hurry — we don't have long."},
		{"id": "negotiate", "speaker": npc_name, "text": "Survival. The camp feeds anyone who helps. That's the deal."},
	]


func _dialogue_offer_truth_dominant() -> Array:
	return [
		{"speaker": npc_name, "text": "The scholars keep measuring things. Measuring the ash, measuring the decay. They don't measure hunger."},
		{"speaker": npc_name, "text": "I don't need data. I need supplies from the machine hall to the east."},
		{"speaker": npc_name, "text": "Will you help?",
			"choices": [
				{"text": "Knowledge won't save your camp.", "force": "truth", "amount": 2.0, "next_id": "truth_response"},
				{"text": "I'll get your supplies.", "force": "faith", "amount": 1.0, "next_id": "accept"},
				{"text": "Sounds dangerous.", "force": "violence", "amount": 1.0, "next_id": "negotiate"},
			]
		},
		{"id": "truth_response", "speaker": npc_name, "text": "No. It won't. But neither will standing here agreeing with me. The hall. East. Second floor."},
		{"id": "accept", "speaker": npc_name, "text": "Thank you. The supplies are near the old generators."},
		{"id": "negotiate", "speaker": npc_name, "text": "It is. That's why I'm asking you instead of going myself."},
	]


func _dialogue_offer_violence_dominant() -> Array:
	return [
		{"speaker": npc_name, "text": "..."},
		{"speaker": npc_name, "text": "I can see the blood on you. I don't care. The camp needs supplies."},
		{"speaker": npc_name, "text": "Machine hall. East. Will you do this or not?",
			"choices": [
				{"text": "I'll do it.", "force": "faith", "amount": 1.0, "next_id": "accept"},
				{"text": "Why should I help?", "force": "truth", "amount": 1.0, "next_id": "why"},
				{"text": "I'll clear the path my way.", "force": "violence", "amount": 2.0, "next_id": "violence_response"},
			]
		},
		{"id": "accept", "speaker": npc_name, "text": "Good. Second floor. Near the generators. Don't... don't break anything else."},
		{"id": "why", "speaker": npc_name, "text": "Because there are people who haven't done anything to anyone. That should be reason enough."},
		{"id": "violence_response", "speaker": npc_name, "text": "That's what everyone says. Then the path is clear and the people behind it are dead. Just get the supplies."},
	]


func _dialogue_offer_neutral() -> Array:
	return [
		{"speaker": npc_name, "text": "Traveler. I don't care about your gods or your theories. I care about the people in that camp."},
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


## Silent state dialogue — Maren won't talk anymore.
func _dialogue_silent() -> Array:
	return [
		{"speaker": npc_name, "text": "..."},
		{"speaker": "Narration", "text": "Maren looks at you. Her mouth opens, then closes. She turns away."},
		{"speaker": "Narration", "text": "There is nothing left to say. The violence took the words."},
	]


## Offscreen death — Maren is gone. Only traces remain.
func _dialogue_offscreen_death() -> Array:
	return [
		{"speaker": "...", "text": "Maren's bedroll is here. It's cold. The camp's fire pit is full of ash."},
		{"speaker": "...", "text": "A trail of footprints leads away from camp. They stop halfway to the machine hall."},
		{"speaker": "...", "text": "There is no body. Just an absence where someone used to be."},
	]


func interact(player: Node) -> void:
	if DialogueManager.is_active:
		return

	var dialogue := _get_dialogue()
	if dialogue.size() > 0:
		DialogueManager.start_dialogue(dialogue, npc_name)
		has_spoken = true

		if not _silent and not _dead_offscreen:
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
	var dominant := GameState.get_dominant_force()
	# Force-reactive post-quest dialogue
	match dominant:
		"faith":
			return [
				{"speaker": npc_name, "text": "The camp is stable. People are praying more now."},
				{"speaker": npc_name, "text": "I don't know if the gods hear them. But it keeps them from giving up. That's something."},
			]
		"truth":
			return [
				{"speaker": npc_name, "text": "The camp is stable. The scholars offered to study our water supply."},
				{"speaker": npc_name, "text": "Data won't warm them at night. But clean water might keep them alive another week."},
			]
		"violence":
			return [
				{"speaker": npc_name, "text": "The camp is stable. For now. But people sleep with weapons now."},
				{"speaker": npc_name, "text": "That's not stability. That's just a slower kind of falling apart."},
			]
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
	if _dead_offscreen or WorldMemory.has_memory("maren_dead_offscreen"):
		return [
			{"speaker": "...", "text": "The camp is gone. Maren is gone. Only the scratched words remain: 'We waited.'"},
			{"speaker": "...", "text": "The pot still hangs over cold ashes. No one came back for it."},
		]
	return [
		{"speaker": "...", "text": "Maren's camp is empty. Bedrolls still arranged in a circle. A pot hangs over cold ashes."},
		{"speaker": "...", "text": "Someone scratched words into the ground: 'We waited.'"},
	]


func _exit_tree() -> void:
	super._exit_tree()
	if GameState and GameState.force_changed.is_connected(_on_maren_force_changed):
		GameState.force_changed.disconnect(_on_maren_force_changed)


# --- Persistence ---

func save_state() -> Dictionary:
	var base := super.save_state()
	base["silent"] = _silent
	base["dead_offscreen"] = _dead_offscreen
	return base


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	_silent = data.get("silent", false)
	_dead_offscreen = data.get("dead_offscreen", false)
