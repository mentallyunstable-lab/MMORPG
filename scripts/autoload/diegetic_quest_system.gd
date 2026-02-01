## DiegeticQuestSystem — Phase J: Quest Design Upgrade.
## J1: Remove explicit quest notifications. Replace with environmental triggers,
##     NPC avoidance, sudden silence where sound existed.
## J2: Failure is canon. Every quest supports: ignored, half-completed,
##     completed incorrectly. Failure produces rumors, lies, world edits, god commentary.
extends Node

signal quest_hint_environmental(quest_id: String, hint_type: String, data: Dictionary)
signal quest_failure_consequence(quest_id: String, consequence_type: String, data: Dictionary)
signal quest_ignored_consequence(quest_id: String, consequence_type: String)

# Tracks which quests have been hinted at through environmental means
var _environmentally_hinted: Dictionary = {}  # quest_id -> bool

# Tracks ignored quests (available but never accepted after threshold time)
var _ignore_timers: Dictionary = {}  # quest_id -> float (seconds since available)
const IGNORE_THRESHOLD := 300.0  # 5 minutes before "ignored" consequences begin

# Quest failure consequence definitions
var _failure_consequences: Dictionary = {}

# Half-completion tracking
var _partial_completion: Dictionary = {}  # quest_id -> completion_ratio (0.0-1.0)

var _check_timer: float = 0.0
const CHECK_INTERVAL := 5.0


func _ready() -> void:
	QuestManager.quest_accepted.connect(_on_quest_accepted)
	QuestManager.quest_completed.connect(_on_quest_completed)
	QuestManager.quest_failed.connect(_on_quest_failed)
	_define_failure_consequences()


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	_check_environmental_triggers()
	_check_ignored_quests(delta * CHECK_INTERVAL)  # Approximate accumulated time
	_check_partial_completions()


# --- J1: Environmental Quest Triggers ---
# No "Quest Started!" notifications. The world changes to hint at opportunities.

func _check_environmental_triggers() -> void:
	for quest_id in QuestManager.quests:
		var q: Dictionary = QuestManager.quests[quest_id]
		if q["state"] != QuestManager.QuestState.AVAILABLE:
			continue
		if _environmentally_hinted.has(quest_id):
			continue

		# Generate environmental hints based on quest type
		_generate_environmental_hint(quest_id, q)


func _generate_environmental_hint(quest_id: String, quest_data: Dictionary) -> void:
	var affinity: String = quest_data.get("force_affinity", "neutral")
	var hint_type := ""
	var hint_data := {}

	match affinity:
		"faith":
			# Environmental trigger: sudden warmth, candles flicker, prayer sounds
			hint_type = "atmosphere_shift"
			hint_data = {
				"description": "The air warms near the shrine. Candle flames lean toward you.",
				"force_cue": "faith",
			}
		"truth":
			# Environmental trigger: machinery hums, inscriptions glow, silence pockets
			hint_type = "detail_emergence"
			hint_data = {
				"description": "Text appears on a surface you've walked past before. It wasn't there yesterday.",
				"force_cue": "truth",
			}
		"violence":
			# Environmental trigger: blood trails appear, weapons hum, enemies avoid an area
			hint_type = "threat_avoidance"
			hint_data = {
				"description": "Enemies give a wide berth to the eastern corridor. Something is there.",
				"force_cue": "violence",
			}
		_:
			# NPC avoidance — an NPC that used to be somewhere is now somewhere else
			hint_type = "npc_behavior_shift"
			hint_data = {
				"description": "Someone who was here has moved. Their absence leaves a shape.",
			}

	# Silence cue: where there was ambient sound, now there's a gap
	if randf() < 0.3:
		hint_type = "sudden_silence"
		hint_data = {
			"description": "A sound you didn't notice stops. The silence is louder than what it replaced.",
		}

	_environmentally_hinted[quest_id] = true
	quest_hint_environmental.emit(quest_id, hint_type, hint_data)

	# Subtle world notification — NOT a quest alert
	WorldEventManager.event_notification.emit("", hint_data.get("description", ""))
	WorldMemory.record_ambient("Environmental hint: %s" % hint_data.get("description", ""))


# --- J2: Failure Is Canon ---

func _define_failure_consequences() -> void:
	# For each quest: what happens when ignored, half-completed, or completed incorrectly
	_failure_consequences["ashes_of_forgotten"] = {
		"ignored": {
			"rumors": [
				"The Ash Walker stopped waiting. She walks alone now.",
				"The relic was found by someone else. They didn't treat it gently.",
			],
			"world_edits": [
				{"type": "force_shift", "force": "faith", "amount": -5.0},
				{"type": "npc_behavior", "npc_id": "npc_ashwalker", "behavior": "wandering"},
			],
			"god_commentary": {
				"verath": "The Ash Mother sighs. Another pilgrim lost to indifference.",
			},
		},
		"half_completed": {
			"rumors": [
				"Someone found the relic but never returned it. It sits in their pack, inert.",
				"The Ash Walker asks about you. Specifically about what you promised and didn't deliver.",
			],
			"world_edits": [
				{"type": "faction_shift", "faction": "ashwalkers", "amount": -15.0},
			],
			"god_commentary": {
				"verath": "Verath remembers half-promises. She completes them her own way.",
			},
		},
		"failed": {
			"rumors": [
				"The relic was lost. The Ash Walker hasn't spoken since.",
				"Some say the relic crumbled. Others say it was never real.",
			],
			"lies": [
				"The relic was returned safely. (This is a lie. You can tell because the Ash Walker won't meet your eyes.)",
			],
			"world_edits": [
				{"type": "force_shift", "force": "faith", "amount": -8.0},
				{"type": "corruption", "zone": "test_zone", "amount": 5.0},
			],
			"god_commentary": {
				"verath": "The cycle breaks. Verath is quiet. That is worse than her anger.",
				"kael": "Kael records the failure. It will not be forgotten.",
			},
		},
	}

	_failure_consequences["void_fragment"] = {
		"ignored": {
			"rumors": [
				"The Scholar's experiment ran without oversight. The results are spreading.",
				"No one collected the void fragment. It's still there, humming.",
			],
			"world_edits": [
				{"type": "force_shift", "force": "truth", "amount": -5.0},
			],
			"god_commentary": {
				"null_throne": "",  # The Null Throne says nothing. That IS the commentary.
			},
		},
		"half_completed": {
			"rumors": [
				"The fragment was found but not delivered. It vibrates in someone's pocket.",
				"The Scholar's deadline passed. She doesn't mention it. That's how you know it mattered.",
			],
			"world_edits": [
				{"type": "faction_shift", "faction": "truthseekers", "amount": -12.0},
			],
		},
		"failed": {
			"rumors": [
				"The void fragment destabilized. A small area near the Scholar's lab is... quieter now.",
				"The Shattered Lens blames outsiders. They're not wrong.",
			],
			"lies": [
				"The fragment was safely contained. (The Scholar's hands shake when she says this.)",
			],
			"world_edits": [
				{"type": "force_shift", "force": "truth", "amount": -10.0},
				{"type": "corruption", "zone": "test_zone", "amount": 8.0},
			],
			"god_commentary": {
				"kael": "Truth sought and abandoned. Kael's light dims over the research district.",
				"null_throne": "The void fragment returns to the void. The Null Throne does not say 'I told you so.' It doesn't need to.",
			},
		},
	}

	# Generic consequences for undefined quests
	_failure_consequences["_default"] = {
		"ignored": {
			"rumors": [
				"Something was needed. No one came.",
				"The opportunity passed. The world adjusted. It always does.",
			],
			"world_edits": [],
			"god_commentary": {},
		},
		"half_completed": {
			"rumors": [
				"Half-done work is worse than none. The wound was opened but not cleaned.",
			],
			"world_edits": [],
		},
		"failed": {
			"rumors": [
				"It failed. The details don't matter to anyone except the people who were counting on it.",
			],
			"world_edits": [],
		},
	}


func _check_ignored_quests(accumulated_delta: float) -> void:
	for quest_id in QuestManager.quests:
		var q: Dictionary = QuestManager.quests[quest_id]
		if q["state"] != QuestManager.QuestState.AVAILABLE:
			continue

		_ignore_timers[quest_id] = _ignore_timers.get(quest_id, 0.0) + accumulated_delta

		if _ignore_timers[quest_id] >= IGNORE_THRESHOLD:
			if not WorldMemory.has_memory("quest_ignored_%s" % quest_id):
				_apply_ignored_consequences(quest_id)


func _check_partial_completions() -> void:
	for quest_id in QuestManager.quests:
		var q: Dictionary = QuestManager.quests[quest_id]
		if q["state"] != QuestManager.QuestState.ACTIVE:
			continue

		# Calculate completion ratio
		var objectives: Array = q.get("objectives", [])
		if objectives.size() == 0:
			continue

		var completed_count := 0
		for obj in objectives:
			if obj.get("completed", false):
				completed_count += 1

		var ratio := float(completed_count) / float(objectives.size())
		_partial_completion[quest_id] = ratio


func _apply_ignored_consequences(quest_id: String) -> void:
	WorldMemory.record("quest_ignored_%s" % quest_id)

	var consequences: Dictionary = _failure_consequences.get(
		quest_id, _failure_consequences["_default"]).get("ignored", {})

	# Spread rumors
	var rumors: Array = consequences.get("rumors", [])
	for rumor in rumors:
		WorldEventManager.event_notification.emit("Rumor", rumor)
		WorldMemory.record_ambient("Rumor (ignored quest): %s" % rumor)

	# Apply world edits
	_apply_world_edits(consequences.get("world_edits", []))

	# God commentary
	_apply_god_commentary(consequences.get("god_commentary", {}))

	quest_ignored_consequence.emit(quest_id, "ignored")


func _on_quest_accepted(quest_id: String) -> void:
	# Remove from ignore tracking
	_ignore_timers.erase(quest_id)


func _on_quest_completed(quest_id: String) -> void:
	_ignore_timers.erase(quest_id)
	_partial_completion.erase(quest_id)


func _on_quest_failed(quest_id: String) -> void:
	_apply_failure_consequences(quest_id)


func _apply_failure_consequences(quest_id: String) -> void:
	# Determine failure type: full failure or half-completion
	var ratio: float = _partial_completion.get(quest_id, 0.0)
	var failure_type := "failed"
	if ratio > 0.0 and ratio < 1.0:
		failure_type = "half_completed"

	var consequences: Dictionary = _failure_consequences.get(
		quest_id, _failure_consequences["_default"]).get(failure_type, {})

	# Spread rumors
	var rumors: Array = consequences.get("rumors", [])
	for rumor in rumors:
		WorldEventManager.event_notification.emit("Rumor", rumor)
		WorldMemory.record_ambient("Rumor (%s): %s" % [failure_type, rumor])

	# Spread lies (failure only)
	var lies: Array = consequences.get("lies", [])
	for lie in lies:
		WorldEventManager.event_notification.emit("...", lie)
		WorldMemory.record_ambient("Lie: %s" % lie)
		WorldMemory.record("quest_lie_%s" % quest_id)

	# Apply world edits
	_apply_world_edits(consequences.get("world_edits", []))

	# God commentary
	_apply_god_commentary(consequences.get("god_commentary", {}))

	quest_failure_consequence.emit(quest_id, failure_type, consequences)
	WorldMemory.record("quest_%s_%s" % [failure_type, quest_id])


func _apply_world_edits(edits: Array) -> void:
	for edit in edits:
		match edit.get("type", ""):
			"force_shift":
				GameState.add_force(edit["force"], edit["amount"])
			"faction_shift":
				GameState.change_faction_reputation(edit["faction"], edit["amount"])
			"corruption":
				var region: Dictionary = GameState.get_region(edit.get("zone", "test_zone"))
				region["corruption"] = minf(
					region.get("corruption", 0.0) + edit.get("amount", 0.0), 100.0)
			"npc_behavior":
				WorldMemory.record("npc_behavior_%s_%s" % [
					edit.get("npc_id", ""), edit.get("behavior", "")])


func _apply_god_commentary(commentary: Dictionary) -> void:
	for god_id in commentary:
		var comment: String = commentary[god_id]
		if comment == "":
			# Empty commentary IS the commentary (Null Throne style)
			ForceEffects.trigger_silence(2.0, 0.7)
			continue
		if GodManager.get_god_state(god_id) != "dead":
			WorldEventManager.event_notification.emit(
				GodManager.get_god_name(god_id), comment)
