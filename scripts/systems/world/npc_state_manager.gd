extends Node
## NPCStateManager - Tracks NPC life states and absence weighting
##
## PRIORITY #12
## "Absence should sometimes hurt more than death."
##
## States: Alive / Dead / Missing / Witness-only
##
## Requirements:
## - How often is death mentioned?
## - How often is absence felt?
## - Which gods react to which state?
## - Do zones remember missing NPCs differently?

signal npc_state_changed(npc_id: String, old_state: NPCState, new_state: NPCState)
signal death_mentioned(npc_id: String, by_npc: String)
signal absence_felt(npc_id: String, zone: String, intensity: float)
signal god_reacted(npc_id: String, god_id: String, state: NPCState)

## NPC life states
enum NPCState {
	ALIVE,        # Normal, present in world
	DEAD,         # Confirmed dead, body exists/existed
	MISSING,      # Disappeared, fate unknown
	WITNESS_ONLY, # Exists only in witness mode perception
}

## NPC data
class NPCData:
	var id: String
	var name: String
	var state: int  # NPCState
	var home_zone: String
	var related_npcs: Array[String]
	var related_gods: Array[String]

	## State change tracking
	var state_changed_time: float = 0.0
	var previous_state: int = NPCState.ALIVE

	## Mention/absence tracking
	var death_mention_count: int = 0
	var absence_felt_count: int = 0
	var last_mentioned_time: float = 0.0


## All NPCs
var npcs: Dictionary = {}  # npc_id -> NPCData

## Zone memories of NPCs
var zone_memories: Dictionary = {}  # zone_id -> { npc_id -> memory_data }

## Weighting configuration
@export var death_mention_cooldown: float = 60.0  # Minimum seconds between mentions
@export var absence_felt_cooldown: float = 120.0
@export var absence_intensity_growth: float = 0.1  # How much absence hurts more over time


func _ready() -> void:
	pass


func register_npc(npc_id: String, display_name: String, home_zone: String, related_npcs: Array[String] = [], related_gods: Array[String] = []) -> void:
	var npc := NPCData.new()
	npc.id = npc_id
	npc.name = display_name
	npc.state = NPCState.ALIVE
	npc.home_zone = home_zone
	npc.related_npcs = related_npcs
	npc.related_gods = related_gods

	npcs[npc_id] = npc

	# Initialize zone memory
	if not home_zone in zone_memories:
		zone_memories[home_zone] = {}

	zone_memories[home_zone][npc_id] = {
		"knew_alive": true,
		"last_seen_state": NPCState.ALIVE,
		"memory_strength": 1.0,
	}


func set_npc_state(npc_id: String, new_state: NPCState) -> void:
	if not npc_id in npcs:
		return

	var npc: NPCData = npcs[npc_id]
	var old_state := npc.state

	if old_state == new_state:
		return

	npc.previous_state = old_state
	npc.state = new_state
	npc.state_changed_time = Time.get_ticks_msec() / 1000.0

	npc_state_changed.emit(npc_id, old_state, new_state)

	# Notify gods
	_notify_gods(npc)

	# Update zone memories
	_update_zone_memories(npc, new_state)


func _notify_gods(npc: NPCData) -> void:
	## Different gods react to different states

	for god_id in npc.related_gods:
		# TODO: Define which gods care about which states
		god_reacted.emit(npc.id, god_id, npc.state)

		# Request god interference based on state
		match npc.state:
			NPCState.DEAD:
				GodInterference.request_interference(
					god_id,
					"death_response",
					npc.home_zone,
					false,
					false
				)
			NPCState.MISSING:
				GodInterference.request_interference(
					god_id,
					"missing_response",
					npc.home_zone,
					false,
					false
				)


func _update_zone_memories(npc: NPCData, new_state: NPCState) -> void:
	## Zones remember missing NPCs differently

	for zone_id in zone_memories:
		if npc.id in zone_memories[zone_id]:
			var memory: Dictionary = zone_memories[zone_id][npc.id]

			memory["last_seen_state"] = new_state

			# Missing NPCs have different memory treatment
			if new_state == NPCState.MISSING:
				memory["memory_strength"] *= 1.2  # Absence makes memory stronger
			elif new_state == NPCState.DEAD:
				memory["memory_strength"] *= 0.9  # Death allows closure, memory fades


func mention_death(dead_npc_id: String, mentioning_npc_id: String) -> bool:
	## An NPC mentions a dead NPC
	## Returns false if on cooldown

	if not dead_npc_id in npcs:
		return false

	var npc: NPCData = npcs[dead_npc_id]

	if npc.state != NPCState.DEAD:
		return false

	var current_time := Time.get_ticks_msec() / 1000.0
	var time_since_mention := current_time - npc.last_mentioned_time

	if time_since_mention < death_mention_cooldown:
		return false

	npc.death_mention_count += 1
	npc.last_mentioned_time = current_time

	death_mentioned.emit(dead_npc_id, mentioning_npc_id)
	return true


func trigger_absence_felt(npc_id: String, zone: String) -> float:
	## Trigger the feeling of an NPC's absence in a zone
	## Returns the intensity of the absence feeling

	if not npc_id in npcs:
		return 0.0

	var npc: NPCData = npcs[npc_id]

	if npc.state != NPCState.MISSING:
		return 0.0

	var current_time := Time.get_ticks_msec() / 1000.0
	var time_missing := current_time - npc.state_changed_time

	# Absence intensity grows over time
	var intensity := min(1.0, 0.3 + (time_missing * absence_intensity_growth / 60.0))

	# Zone-specific intensity
	if zone == npc.home_zone:
		intensity *= 1.5  # Absence felt stronger in home zone

	intensity = min(1.0, intensity)

	npc.absence_felt_count += 1
	absence_felt.emit(npc_id, zone, intensity)

	return intensity


func get_npc_state(npc_id: String) -> Dictionary:
	if not npc_id in npcs:
		return {}

	var npc: NPCData = npcs[npc_id]

	return {
		"id": npc.id,
		"name": npc.name,
		"state": NPCState.keys()[npc.state],
		"home_zone": npc.home_zone,
		"death_mentions": npc.death_mention_count,
		"absence_felt_count": npc.absence_felt_count,
		"time_in_state": (Time.get_ticks_msec() / 1000.0) - npc.state_changed_time if npc.state_changed_time > 0 else 0,
	}


func get_zone_npc_memories(zone_id: String) -> Array[Dictionary]:
	if not zone_id in zone_memories:
		return []

	var result: Array[Dictionary] = []

	for npc_id in zone_memories[zone_id]:
		var memory: Dictionary = zone_memories[zone_id][npc_id]
		var npc: NPCData = npcs.get(npc_id)

		if npc:
			result.append({
				"npc_id": npc_id,
				"npc_name": npc.name,
				"current_state": NPCState.keys()[npc.state],
				"memory_strength": memory["memory_strength"],
				"last_seen_state": NPCState.keys()[memory["last_seen_state"]],
			})

	return result


func get_state_statistics() -> Dictionary:
	var alive := 0
	var dead := 0
	var missing := 0
	var witness_only := 0
	var total_death_mentions := 0
	var total_absence_felt := 0

	for npc_id in npcs:
		var npc: NPCData = npcs[npc_id]

		match npc.state:
			NPCState.ALIVE:
				alive += 1
			NPCState.DEAD:
				dead += 1
				total_death_mentions += npc.death_mention_count
			NPCState.MISSING:
				missing += 1
				total_absence_felt += npc.absence_felt_count
			NPCState.WITNESS_ONLY:
				witness_only += 1

	return {
		"total_npcs": npcs.size(),
		"alive": alive,
		"dead": dead,
		"missing": missing,
		"witness_only": witness_only,
		"total_death_mentions": total_death_mentions,
		"total_absence_felt": total_absence_felt,
		"death_mention_rate": float(total_death_mentions) / max(dead, 1),
		"absence_felt_rate": float(total_absence_felt) / max(missing, 1),
	}


func compare_death_vs_absence_impact() -> Dictionary:
	## Analyze whether absence is hurting more than death
	## "Absence should sometimes hurt more than death"

	var death_impact := 0.0
	var absence_impact := 0.0

	for npc_id in npcs:
		var npc: NPCData = npcs[npc_id]

		if npc.state == NPCState.DEAD:
			# Death impact based on mentions
			death_impact += npc.death_mention_count * 0.5

		if npc.state == NPCState.MISSING:
			# Absence impact grows over time
			var time_missing := (Time.get_ticks_msec() / 1000.0) - npc.state_changed_time
			absence_impact += npc.absence_felt_count * (1.0 + time_missing / 600.0)

	return {
		"death_impact": death_impact,
		"absence_impact": absence_impact,
		"absence_hurts_more": absence_impact > death_impact,
		"ratio": absence_impact / max(death_impact, 0.1),
	}
