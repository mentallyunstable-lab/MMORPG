extends Node
## QuestManager - Handles quests with failure taxonomy
##
## PRIORITY #6
## "No two failures should feel identical."
##
## Failure types:
## - Ignored
## - Misinterpreted
## - Half-completed
## - Actively defied
## - Accidentally completed
##
## Each must:
## - Produce a different rumor flavor
## - Trigger different god commentary tone
## - Modify world state differently

signal quest_started(quest_id: String)
signal quest_updated(quest_id: String, state: String)
signal quest_resolved(quest_id: String, resolution: QuestResolution)
signal rumor_generated(quest_id: String, rumor: Dictionary)
signal god_commentary_triggered(quest_id: String, god_id: String, tone: String)

## Quest resolution types
enum QuestResolution {
	COMPLETED,              # Standard success
	IGNORED,                # Player never engaged
	MISINTERPRETED,         # Player tried but misunderstood
	HALF_COMPLETED,         # Partial completion
	ACTIVELY_DEFIED,        # Player deliberately did opposite
	ACCIDENTALLY_COMPLETED, # Completed without intent
}

## Quest data
var active_quests: Dictionary = {}   # quest_id -> QuestData
var resolved_quests: Dictionary = {} # quest_id -> ResolutionData


class QuestData:
	var id: String
	var title: String
	var objectives: Array[ObjectiveData]
	var started_time: float
	var last_interaction_time: float
	var interaction_count: int = 0
	var player_interpretation: String = ""  # What player seems to think this quest is


class ObjectiveData:
	var id: String
	var description: String
	var is_complete: bool = false
	var completion_was_intentional: bool = true
	var opposite_action_taken: bool = false


class ResolutionData:
	var quest_id: String
	var resolution: int  # QuestResolution
	var resolved_time: float
	var rumor_flavor: String
	var god_tone: String
	var world_state_changes: Array[String]


func _ready() -> void:
	pass


func start_quest(quest_id: String, title: String, objectives: Array[Dictionary]) -> void:
	var quest := QuestData.new()
	quest.id = quest_id
	quest.title = title
	quest.started_time = Time.get_ticks_msec() / 1000.0
	quest.last_interaction_time = quest.started_time

	for obj_data in objectives:
		var objective := ObjectiveData.new()
		objective.id = obj_data.get("id", "")
		objective.description = obj_data.get("description", "")
		quest.objectives.append(objective)

	active_quests[quest_id] = quest
	quest_started.emit(quest_id)


func record_interaction(quest_id: String, interaction_type: String, context: Dictionary = {}) -> void:
	if not quest_id in active_quests:
		return

	var quest: QuestData = active_quests[quest_id]
	quest.last_interaction_time = Time.get_ticks_msec() / 1000.0
	quest.interaction_count += 1

	# Track player interpretation
	if "player_interpretation" in context:
		quest.player_interpretation = context["player_interpretation"]

	quest_updated.emit(quest_id, "interaction")


func complete_objective(quest_id: String, objective_id: String, was_intentional: bool = true) -> void:
	if not quest_id in active_quests:
		return

	var quest: QuestData = active_quests[quest_id]

	for objective: ObjectiveData in quest.objectives:
		if objective.id == objective_id:
			objective.is_complete = true
			objective.completion_was_intentional = was_intentional
			break

	quest_updated.emit(quest_id, "objective_complete")
	_check_quest_completion(quest_id)


func record_opposite_action(quest_id: String, objective_id: String) -> void:
	## Player did the opposite of what was asked
	if not quest_id in active_quests:
		return

	var quest: QuestData = active_quests[quest_id]

	for objective: ObjectiveData in quest.objectives:
		if objective.id == objective_id:
			objective.opposite_action_taken = true
			break

	quest_updated.emit(quest_id, "opposite_action")


func _check_quest_completion(quest_id: String) -> void:
	if not quest_id in active_quests:
		return

	var quest: QuestData = active_quests[quest_id]
	var complete_count := 0
	var intentional_count := 0
	var opposite_count := 0

	for objective: ObjectiveData in quest.objectives:
		if objective.is_complete:
			complete_count += 1
			if objective.completion_was_intentional:
				intentional_count += 1
		if objective.opposite_action_taken:
			opposite_count += 1

	# Auto-resolve if all objectives are complete
	if complete_count == quest.objectives.size():
		if intentional_count == 0:
			resolve_quest(quest_id, QuestResolution.ACCIDENTALLY_COMPLETED)
		else:
			resolve_quest(quest_id, QuestResolution.COMPLETED)


func resolve_quest(quest_id: String, resolution: QuestResolution) -> void:
	if not quest_id in active_quests:
		return

	var quest: QuestData = active_quests[quest_id]

	var resolution_data := ResolutionData.new()
	resolution_data.quest_id = quest_id
	resolution_data.resolution = resolution
	resolution_data.resolved_time = Time.get_ticks_msec() / 1000.0
	resolution_data.rumor_flavor = _get_rumor_flavor(resolution, quest)
	resolution_data.god_tone = _get_god_tone(resolution, quest)
	resolution_data.world_state_changes = _get_world_changes(resolution, quest)

	resolved_quests[quest_id] = resolution_data
	active_quests.erase(quest_id)

	# Generate consequences
	_generate_rumor(quest_id, resolution_data)
	_trigger_god_commentary(quest_id, resolution_data)
	_apply_world_changes(resolution_data)

	quest_resolved.emit(quest_id, resolution)


func check_for_ignored_quests() -> void:
	## Call periodically to detect ignored quests
	var current_time := Time.get_ticks_msec() / 1000.0
	var ignore_threshold := 600.0  # 10 minutes of no interaction

	for quest_id in active_quests:
		var quest: QuestData = active_quests[quest_id]
		var time_since_interaction := current_time - quest.last_interaction_time

		if time_since_interaction > ignore_threshold and quest.interaction_count < 2:
			resolve_quest(quest_id, QuestResolution.IGNORED)


func check_for_half_completed(quest_id: String) -> bool:
	## Check if quest should be marked half-completed
	if not quest_id in active_quests:
		return false

	var quest: QuestData = active_quests[quest_id]
	var complete_count := 0

	for objective: ObjectiveData in quest.objectives:
		if objective.is_complete:
			complete_count += 1

	# Half-completed: more than 0 but not all
	return complete_count > 0 and complete_count < quest.objectives.size()


func force_half_completion(quest_id: String) -> void:
	## Force a quest to resolve as half-completed
	if check_for_half_completed(quest_id):
		resolve_quest(quest_id, QuestResolution.HALF_COMPLETED)


## Rumor flavors - each resolution produces different flavor
func _get_rumor_flavor(resolution: QuestResolution, quest: QuestData) -> String:
	match resolution:
		QuestResolution.COMPLETED:
			return "accomplished"      # Respectful, matter-of-fact
		QuestResolution.IGNORED:
			return "forgotten"         # Sad, disappointed
		QuestResolution.MISINTERPRETED:
			return "confused"          # Bemused, uncertain
		QuestResolution.HALF_COMPLETED:
			return "incomplete"        # Frustrated, wondering
		QuestResolution.ACTIVELY_DEFIED:
			return "rebellious"        # Shocked, fearful, or admiring
		QuestResolution.ACCIDENTALLY_COMPLETED:
			return "lucky"             # Disbelieving, amused

	return "neutral"


## God commentary tones - each resolution triggers different tone
func _get_god_tone(resolution: QuestResolution, quest: QuestData) -> String:
	match resolution:
		QuestResolution.COMPLETED:
			return "approving"         # Satisfied, perhaps smug
		QuestResolution.IGNORED:
			return "disappointed"      # Cold, withdrawing
		QuestResolution.MISINTERPRETED:
			return "amused"            # Patronizing, entertained
		QuestResolution.HALF_COMPLETED:
			return "impatient"         # Frustrated, urging
		QuestResolution.ACTIVELY_DEFIED:
			return "wrathful"          # Angry, threatening
		QuestResolution.ACCIDENTALLY_COMPLETED:
			return "suspicious"        # Uncertain, watching closely

	return "neutral"


## World state changes - each resolution modifies differently
func _get_world_changes(resolution: QuestResolution, quest: QuestData) -> Array[String]:
	var changes: Array[String] = []

	match resolution:
		QuestResolution.COMPLETED:
			changes.append("quest_area_peaceful")
			changes.append("related_npcs_grateful")
		QuestResolution.IGNORED:
			changes.append("quest_area_decayed")
			changes.append("related_npcs_resentful")
		QuestResolution.MISINTERPRETED:
			changes.append("quest_area_confused")
			changes.append("unintended_side_effects")
		QuestResolution.HALF_COMPLETED:
			changes.append("quest_area_unstable")
			changes.append("related_npcs_anxious")
		QuestResolution.ACTIVELY_DEFIED:
			changes.append("quest_area_hostile")
			changes.append("god_attention_increased")
		QuestResolution.ACCIDENTALLY_COMPLETED:
			changes.append("quest_area_neutral")
			changes.append("related_npcs_confused")

	return changes


func _generate_rumor(quest_id: String, resolution_data: ResolutionData) -> void:
	var rumor := {
		"source_quest": quest_id,
		"flavor": resolution_data.rumor_flavor,
		"generated_time": resolution_data.resolved_time,
		"content": _compose_rumor_text(quest_id, resolution_data),
	}

	rumor_generated.emit(quest_id, rumor)

	# Send to rumor system
	if RumorSystem:
		RumorSystem.inject_rumor(rumor)


func _compose_rumor_text(quest_id: String, resolution_data: ResolutionData) -> String:
	## TODO: Generate actual rumor text based on quest details and resolution
	return "A rumor about %s (flavor: %s)" % [quest_id, resolution_data.rumor_flavor]


func _trigger_god_commentary(quest_id: String, resolution_data: ResolutionData) -> void:
	## Find relevant god and trigger commentary
	## TODO: Determine which god cares about this quest
	var relevant_god := "default_god"

	god_commentary_triggered.emit(quest_id, relevant_god, resolution_data.god_tone)


func _apply_world_changes(resolution_data: ResolutionData) -> void:
	## Apply world state changes
	for change in resolution_data.world_state_changes:
		# TODO: Implement actual world state modifications
		print("[QuestManager] World change: %s" % change)


func get_quest_status(quest_id: String) -> Dictionary:
	if quest_id in active_quests:
		var quest: QuestData = active_quests[quest_id]
		return {
			"status": "active",
			"title": quest.title,
			"started": quest.started_time,
			"interactions": quest.interaction_count,
			"objectives_complete": quest.objectives.filter(func(o): return o.is_complete).size(),
			"objectives_total": quest.objectives.size(),
		}
	elif quest_id in resolved_quests:
		var res: ResolutionData = resolved_quests[quest_id]
		return {
			"status": "resolved",
			"resolution": QuestResolution.keys()[res.resolution],
			"rumor_flavor": res.rumor_flavor,
			"god_tone": res.god_tone,
		}

	return {"status": "unknown"}
