## NPCRegistry — Phase G3: NPC Death & Absence Matrix.
## For every named NPC: alive, dead, missing, witness-only.
## Ensures no hard quest locks, dialogue gracefully degrades,
## and the world reacts to NPC absence (silence, rumors, lies).
extends Node

signal npc_state_changed(npc_id: String, old_state: String, new_state: String)
signal npc_rumor_generated(npc_id: String, rumor: String)

# NPC states
enum NPCState { ALIVE, DEAD, MISSING, WITNESS_ONLY }

# Registry: npc_id -> data
var _registry: Dictionary = {}

# Rumors about NPCs — ambient dialogue snippets generated when NPCs die or vanish
var _active_rumors: Array[Dictionary] = []  # {npc_id, text, type, timestamp}
const MAX_RUMORS := 10


func _ready() -> void:
	_register_default_npcs()
	WorldEventManager.witness_mode_entered.connect(_on_witness_mode)


func _register_default_npcs() -> void:
	register_npc("npc_ashwalker", {
		"name": "The Ash Walker",
		"force_affinity": "faith",
		"faction": "ashwalkers",
		"quests": ["ashes_of_forgotten"],
		"death_rumors": [
			"They say the Ash Walker collapsed mid-prayer. No wound. Just silence.",
			"Someone found prayer beads in the dust. No body.",
			"The pilgrims have no guide now. They wander in circles.",
		],
		"missing_rumors": [
			"The Ash Walker hasn't been seen. The shrine gathers dust.",
			"Footprints lead into the ash wastes. No return trail.",
			"Some say the Ash Walker left. Others say she was taken.",
		],
		"absence_world_effects": [
			{"type": "force_shift", "force": "faith", "amount": -3.0},
			{"type": "faction_shift", "faction": "ashwalkers", "amount": -10.0},
		],
		"dialogue_degradation": {
			"dead": [
				{"speaker": "...", "text": "A pile of ash where %s once stood. Still warm." % "the Ash Walker"},
				{"speaker": "...", "text": "The prayer beads are scattered. No one will collect them."},
			],
			"missing": [
				{"speaker": "Rumor", "text": "The Ash Walker left without a word. Or was taken without a chance to speak."},
				{"speaker": "Rumor", "text": "Her shrine still hums faintly. Devotion outlasts the devout."},
			],
		},
	})

	register_npc("npc_scholar", {
		"name": "The Shattered Scholar",
		"force_affinity": "truth",
		"faction": "truthseekers",
		"quests": ["void_fragment", "decaying_sample", "observe_pattern"],
		"death_rumors": [
			"The Scholar's notes were found scattered. The last page was blank.",
			"They say she saw something in the data that stopped her heart.",
			"The Shattered Lens lost their best mind. They blame faith.",
		],
		"missing_rumors": [
			"The Scholar stopped attending meetings. Her lab is locked.",
			"Her research notes are incomplete. The last entry: 'I was wrong about everything.'",
			"No one has seen her. The machines she studied are silent.",
		],
		"absence_world_effects": [
			{"type": "force_shift", "force": "truth", "amount": -3.0},
			{"type": "faction_shift", "faction": "truthseekers", "amount": -10.0},
		],
		"dialogue_degradation": {
			"dead": [
				{"speaker": "...", "text": "The Scholar's body lies among her notes. Knowledge preserved. The knower, not."},
				{"speaker": "...", "text": "Her last experiment is still running. It will never be read."},
			],
			"missing": [
				{"speaker": "Rumor", "text": "The Scholar vanished. Her instruments keep recording data no one will interpret."},
				{"speaker": "Rumor", "text": "Some say she found what she was looking for. That's why she left."},
			],
		},
	})

	register_npc("npc_survivor", {
		"name": "The Local Survivor",
		"force_affinity": "neutral",
		"faction": "",
		"quests": [],
		"death_rumors": [
			"Another survivor down. This one had no faction, no god, no use. Just a person.",
			"The body is unremarkable. That's the worst part.",
		],
		"missing_rumors": [
			"The survivor moved on. Or didn't. No one was watching.",
		],
		"absence_world_effects": [],
		"dialogue_degradation": {
			"dead": [
				{"speaker": "...", "text": "A body. No name you remember. The ash doesn't care."},
			],
			"missing": [
				{"speaker": "...", "text": "Someone was here. Now they're not. The world filled the space."},
			],
		},
	})

	register_npc("npc_iron_deacon", {
		"name": "The Iron Deacon",
		"force_affinity": "violence",
		"faction": "ironvow",
		"quests": ["blood_tithe"],
		"death_rumors": [
			"The Iron Deacon was found with his own blade in his chest. Self-inflicted or forced — no one can tell.",
			"The Iron Vow is leaderless. They fight harder now. Or maybe just angrier.",
			"His last words: 'Strength doesn't protect. It just delays.'",
		],
		"missing_rumors": [
			"The Deacon walked into the ash wastes. Fully armed. No provisions.",
			"Some say he's testing himself. Others say he's running.",
		],
		"absence_world_effects": [
			{"type": "force_shift", "force": "violence", "amount": 5.0},
			{"type": "faction_shift", "faction": "ironvow", "amount": -15.0},
		],
		"dialogue_degradation": {
			"dead": [
				{"speaker": "...", "text": "The Deacon's armor stands empty. Someone propped it up like a scarecrow."},
				{"speaker": "...", "text": "Blood stains the ground. His or someone else's. Does it matter?"},
			],
			"missing": [
				{"speaker": "Rumor", "text": "The Deacon left. The Iron Vow pretends he's on a mission."},
				{"speaker": "Rumor", "text": "His quarters are empty. His weapons are gone. His debts remain."},
			],
		},
	})

	register_npc("npc_hollow_priest", {
		"name": "The Hollow Priest",
		"force_affinity": "faith",
		"faction": "hollow_church",
		"quests": ["empty_sermon"],
		"death_rumors": [
			"The Hollow Priest died mid-sermon. The congregation didn't notice for ten minutes.",
			"Her prayers went unanswered to the end. Consistency, at least.",
		],
		"missing_rumors": [
			"The Priest stopped coming to the chapel. The candles still light themselves.",
			"Someone heard singing from the empty chapel. When they looked, no one was there.",
		],
		"absence_world_effects": [
			{"type": "force_shift", "force": "faith", "amount": -5.0},
			{"type": "faction_shift", "faction": "hollow_church", "amount": -20.0},
		],
		"dialogue_degradation": {
			"dead": [
				{"speaker": "...", "text": "The Priest lies at the altar. Her hands are folded. No one folded them."},
				{"speaker": "...", "text": "The chapel bell rings once. Then stops. Then rings again. It shouldn't."},
			],
			"missing": [
				{"speaker": "Rumor", "text": "The Priest left her robes behind. Folded neatly. A resignation letter, written in fabric."},
			],
		},
	})


func register_npc(npc_id: String, data: Dictionary) -> void:
	data["state"] = NPCState.ALIVE
	data["death_time"] = 0.0
	data["killer"] = ""
	_registry[npc_id] = data


## Kill an NPC. Triggers rumors, world effects, and quest graceful degradation.
func kill_npc(npc_id: String, killer: String = "unknown") -> void:
	if not _registry.has(npc_id):
		return
	var data: Dictionary = _registry[npc_id]
	if data["state"] == NPCState.DEAD:
		return

	var old_state := _state_to_string(data["state"])
	data["state"] = NPCState.DEAD
	data["death_time"] = Time.get_unix_time_from_system()
	data["killer"] = killer

	npc_state_changed.emit(npc_id, old_state, "dead")
	_apply_absence_effects(npc_id)
	_generate_rumors(npc_id, "death")
	_handle_quest_degradation(npc_id)

	WorldMemory.record("npc_killed_%s" % npc_id)
	WorldMemory.record_ambient("%s is dead" % data.get("name", npc_id))


## Mark NPC as missing. Similar to death but ambiguous.
func set_npc_missing(npc_id: String) -> void:
	if not _registry.has(npc_id):
		return
	var data: Dictionary = _registry[npc_id]
	if data["state"] != NPCState.ALIVE:
		return

	var old_state := _state_to_string(data["state"])
	data["state"] = NPCState.MISSING
	npc_state_changed.emit(npc_id, old_state, "missing")
	_apply_absence_effects(npc_id)
	_generate_rumors(npc_id, "missing")
	_handle_quest_degradation(npc_id)

	WorldMemory.record("npc_missing_%s" % npc_id)
	WorldMemory.record_ambient("%s has disappeared" % data.get("name", npc_id))


## Get NPC state
func get_npc_state(npc_id: String) -> String:
	if not _registry.has(npc_id):
		return "unknown"
	return _state_to_string(_registry[npc_id]["state"])


## Get dialogue for an absent NPC (dead or missing).
func get_absence_dialogue(npc_id: String) -> Array:
	if not _registry.has(npc_id):
		return [{"speaker": "...", "text": "No one is here."}]

	var data: Dictionary = _registry[npc_id]
	var state_str := _state_to_string(data["state"])
	var degradation: Dictionary = data.get("dialogue_degradation", {})

	if degradation.has(state_str):
		return degradation[state_str]

	# Generic fallback
	match data["state"]:
		NPCState.DEAD:
			return [{"speaker": "...", "text": "A body. It was someone."}]
		NPCState.MISSING:
			return [{"speaker": "...", "text": "Empty space. Someone should be here."}]
		NPCState.WITNESS_ONLY:
			return [{"speaker": "...", "text": "A shadow of someone you might have known."}]
	return []


## Get active rumors about NPCs.
func get_active_rumors() -> Array[Dictionary]:
	return _active_rumors


## Check if an NPC is available for quest interaction.
func is_npc_available(npc_id: String) -> bool:
	if not _registry.has(npc_id):
		return false
	return _registry[npc_id]["state"] == NPCState.ALIVE


func _apply_absence_effects(npc_id: String) -> void:
	var data: Dictionary = _registry[npc_id]
	for effect in data.get("absence_world_effects", []):
		match effect.get("type", ""):
			"force_shift":
				GameState.add_force(effect["force"], effect["amount"])
			"faction_shift":
				GameState.change_faction_reputation(effect["faction"], effect["amount"])


func _generate_rumors(npc_id: String, rumor_type: String) -> void:
	var data: Dictionary = _registry[npc_id]
	var rumor_pool: Array = []

	match rumor_type:
		"death":
			rumor_pool = data.get("death_rumors", [])
		"missing":
			rumor_pool = data.get("missing_rumors", [])

	if rumor_pool.size() == 0:
		return

	# Pick 1-2 rumors
	var count := mini(randi_range(1, 2), rumor_pool.size())
	var used_indices: Array = []
	for i in range(count):
		var idx := randi() % rumor_pool.size()
		while idx in used_indices and used_indices.size() < rumor_pool.size():
			idx = (idx + 1) % rumor_pool.size()
		used_indices.append(idx)

		var rumor_text: String = rumor_pool[idx]
		_active_rumors.append({
			"npc_id": npc_id,
			"text": rumor_text,
			"type": rumor_type,
			"timestamp": Time.get_unix_time_from_system(),
		})
		npc_rumor_generated.emit(npc_id, rumor_text)
		WorldMemory.record_ambient("Rumor: %s" % rumor_text)

	# Trim old rumors
	while _active_rumors.size() > MAX_RUMORS:
		_active_rumors.pop_front()


## Handle quest degradation when an NPC dies or goes missing.
## No hard quest locks — quests gracefully fail or redirect.
func _handle_quest_degradation(npc_id: String) -> void:
	var data: Dictionary = _registry[npc_id]
	var quest_ids: Array = data.get("quests", [])

	for quest_id in quest_ids:
		if QuestManager.is_quest_active(quest_id):
			# Active quest with dead/missing giver — fail gracefully
			QuestManager.fail_quest(quest_id)
			WorldEventManager.event_notification.emit(
				"Quest Lost",
				"'%s' can no longer be completed. %s is gone." % [
					quest_id, data.get("name", "Someone")])
			WorldMemory.record("quest_lost_npc_absence_%s" % quest_id)

		elif not QuestManager.is_quest_completed(quest_id):
			# Available quest that can never be accepted now
			WorldMemory.record("quest_unavailable_%s" % quest_id)


func _on_witness_mode() -> void:
	# All surviving NPCs become witness-only
	for npc_id in _registry:
		var data: Dictionary = _registry[npc_id]
		if data["state"] == NPCState.ALIVE:
			data["state"] = NPCState.WITNESS_ONLY
			npc_state_changed.emit(npc_id, "alive", "witness_only")


func _state_to_string(state: int) -> String:
	match state:
		NPCState.ALIVE: return "alive"
		NPCState.DEAD: return "dead"
		NPCState.MISSING: return "missing"
		NPCState.WITNESS_ONLY: return "witness_only"
	return "unknown"


# --- Persistence ---

func save_state() -> Dictionary:
	var states := {}
	for npc_id in _registry:
		states[npc_id] = {
			"state": _registry[npc_id]["state"],
			"death_time": _registry[npc_id]["death_time"],
			"killer": _registry[npc_id]["killer"],
		}
	return {"npc_states": states, "rumors": _active_rumors.duplicate(true)}


func load_state(data: Dictionary) -> void:
	var states: Dictionary = data.get("npc_states", {})
	for npc_id in states:
		if _registry.has(npc_id):
			_registry[npc_id]["state"] = states[npc_id].get("state", NPCState.ALIVE)
			_registry[npc_id]["death_time"] = states[npc_id].get("death_time", 0.0)
			_registry[npc_id]["killer"] = states[npc_id].get("killer", "")
	var loaded_rumors = data.get("rumors", [])
	_active_rumors.clear()
	for r in loaded_rumors:
		_active_rumors.append(r)
