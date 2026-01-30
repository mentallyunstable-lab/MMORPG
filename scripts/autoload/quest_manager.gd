## QuestManager — Tracks quests, objectives, completion, and force-reactive rewards.
## Quests are data-driven dictionaries. Systems call into this manager to update progress.
extends Node

signal quest_accepted(quest_id: String)
signal quest_updated(quest_id: String, objective_id: String)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)

# Quest state: quest_id -> quest data
var quests: Dictionary = {}

# Quest states
enum QuestState { AVAILABLE, ACTIVE, COMPLETED, FAILED }


## Register a quest definition. Call this from NPCs or zone scripts.
## quest_data format:
## {
##   "id": "find_the_relic",
##   "title": "Find the Relic",
##   "description": "Recover the ash relic from the ruins.",
##   "giver": "Ash Walker",
##   "force_affinity": "faith",
##   "objectives": [
##     { "id": "find_relic", "description": "Find the relic", "type": "interact", "target": "ash_relic", "completed": false },
##     { "id": "return_relic", "description": "Return to Ash Walker", "type": "talk", "target": "npc_ashwalker", "completed": false },
##   ],
##   "rewards": {
##     "force": "faith", "force_amount": 8.0,
##     "faction": "ashwalkers", "faction_amount": 10.0,
##     "items": ["health_potion"],
##   },
## }
func register_quest(quest_data: Dictionary) -> void:
	var qid: String = quest_data.get("id", "")
	if qid == "":
		push_warning("QuestManager: quest has no id.")
		return
	if quests.has(qid):
		return  # Already registered
	quest_data["state"] = QuestState.AVAILABLE
	quests[qid] = quest_data


## Accept a quest — moves it from AVAILABLE to ACTIVE.
func accept_quest(quest_id: String) -> bool:
	if not quests.has(quest_id):
		return false
	var q: Dictionary = quests[quest_id]
	if q["state"] != QuestState.AVAILABLE:
		return false

	# Check force requirements
	if q.has("requires_force"):
		if GameState.get_force(q["requires_force"]) < q.get("requires_min", 0.0):
			return false

	q["state"] = QuestState.ACTIVE
	quest_accepted.emit(quest_id)
	return true


## Update an objective. Called when something happens in the world.
## event_type: "kill", "interact", "talk", "collect", "reach"
## target_id: the entity or object involved.
func notify_event(event_type: String, target_id: String) -> void:
	for qid in quests:
		var q: Dictionary = quests[qid]
		if q["state"] != QuestState.ACTIVE:
			continue

		var objectives: Array = q.get("objectives", [])
		for obj in objectives:
			if obj.get("completed", false):
				continue
			if obj.get("type", "") == event_type and obj.get("target", "") == target_id:
				obj["completed"] = true
				quest_updated.emit(qid, obj.get("id", ""))
				_check_quest_completion(qid)
				return  # One event per call


func _check_quest_completion(quest_id: String) -> void:
	var q: Dictionary = quests[quest_id]
	var objectives: Array = q.get("objectives", [])

	for obj in objectives:
		if not obj.get("completed", false):
			return  # Not all objectives complete

	# All done
	q["state"] = QuestState.COMPLETED
	_grant_rewards(q)
	quest_completed.emit(quest_id)


func _grant_rewards(quest_data: Dictionary) -> void:
	var rewards: Dictionary = quest_data.get("rewards", {})

	if rewards.has("force") and rewards.has("force_amount"):
		GameState.add_force(rewards["force"], rewards["force_amount"])

	if rewards.has("faction") and rewards.has("faction_amount"):
		GameState.change_faction_reputation(rewards["faction"], rewards["faction_amount"])

	if rewards.has("items"):
		for item_id in rewards["items"]:
			ItemManager.add_item(item_id)

	# Notify
	WorldEventManager.event_notification.emit(
		"Quest Complete",
		quest_data.get("title", "Unknown quest")
	)


## Get all active quests.
func get_active_quests() -> Array:
	var result: Array = []
	for qid in quests:
		if quests[qid]["state"] == QuestState.ACTIVE:
			result.append(quests[qid])
	return result


## Get all available quests.
func get_available_quests() -> Array:
	var result: Array = []
	for qid in quests:
		if quests[qid]["state"] == QuestState.AVAILABLE:
			result.append(quests[qid])
	return result


## Check if a quest is completed.
func is_quest_completed(quest_id: String) -> bool:
	return quests.has(quest_id) and quests[quest_id]["state"] == QuestState.COMPLETED


## Check if a quest is active.
func is_quest_active(quest_id: String) -> bool:
	return quests.has(quest_id) and quests[quest_id]["state"] == QuestState.ACTIVE


## Fail a quest.
func fail_quest(quest_id: String) -> void:
	if quests.has(quest_id) and quests[quest_id]["state"] == QuestState.ACTIVE:
		quests[quest_id]["state"] = QuestState.FAILED
		quest_failed.emit(quest_id)
		WorldEventManager.event_notification.emit(
			"Quest Failed", quests[quest_id].get("title", quest_id))
		WorldMemory.record("quest_failed_%s" % quest_id)


# --- Timed Quests ---
# Quests with "time_limit" (seconds) auto-fail when time runs out.
# Quests with "inaction_reward_time" succeed if the player does NOTHING for that long.

func _process(delta: float) -> void:
	for qid in quests:
		var q: Dictionary = quests[qid]
		if q["state"] != QuestState.ACTIVE:
			continue

		# Tick elapsed time
		q["_elapsed"] = q.get("_elapsed", 0.0) + delta

		# Auto-fail: time ran out
		if q.has("time_limit"):
			if q["_elapsed"] >= q["time_limit"]:
				fail_quest(qid)

		# Inaction success: player did nothing for long enough
		if q.has("inaction_reward_time"):
			var inaction: float = q.get("_inaction_timer", 0.0) + delta
			q["_inaction_timer"] = inaction
			if inaction >= q["inaction_reward_time"]:
				# Complete by doing nothing
				for obj in q.get("objectives", []):
					obj["completed"] = true
				q["state"] = QuestState.COMPLETED
				_grant_rewards(q)
				quest_completed.emit(qid)
				WorldMemory.record("quest_inaction_success_%s" % qid)


## Reset inaction timer — called when the player takes any quest-related action.
func reset_inaction(quest_id: String) -> void:
	if quests.has(quest_id):
		quests[quest_id]["_inaction_timer"] = 0.0


## Get remaining time for a timed quest (or -1 if untimed).
func get_time_remaining(quest_id: String) -> float:
	if not quests.has(quest_id):
		return -1.0
	var q: Dictionary = quests[quest_id]
	if not q.has("time_limit"):
		return -1.0
	return maxf(q["time_limit"] - q.get("_elapsed", 0.0), 0.0)


# --- Persistence ---

func save_state() -> Dictionary:
	return {"quests": quests.duplicate(true)}


func load_state(data: Dictionary) -> void:
	quests = data.get("quests", {})
