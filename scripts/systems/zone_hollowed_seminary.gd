## ZoneHollowedSeminary — Phase H1: Second Major Zone.
## NOT symmetrical to Ashborn Depth. Design rules:
##   - No tutorial energy. The zone assumes you've been broken already.
##   - One dominant force (faith) is HOSTILE to its own followers here.
##   - Vertical/claustrophobic layout — tight corridors, false floors, inverted churches.
##   - One area lies about its boundaries (the Resonance Hall claims to be a dead end).
##   - One traversal mechanic that feels unsafe (faith bridges that crumble under doubt).
##   - One landmark visible early but reachable late or never (The Inverted Bell Tower).
##
## Zone identity: The Hollowed Seminary — a collapsed religious school where faith
## turned cancerous. The Hollow Church started here. Verath's influence rotted
## devotion into compulsion. Truth seekers came to study it. Violence followed.

class_name ZoneHollowedSeminary
extends Node3D

# --- Zone State ---
var zone_id: String = "hollowed_seminary"
var _faith_bridge_integrity: float = 1.0  # 1.0 = solid, 0.0 = collapsed
var _resonance_hall_revealed: bool = false  # The lying area
var _bell_tower_accessible: bool = false  # The unreachable landmark
var _seminary_corruption: float = 0.0
var _hostile_faith_active: bool = false  # Faith turns against its followers here

# Sub-areas within the zone
enum SubArea { ENTRANCE_CLOISTERS, SCRIPTURE_HALLS, RESONANCE_HALL, FAITH_BRIDGES, UNDERCROFT, BELL_TOWER_BASE }
var current_sub_area: SubArea = SubArea.ENTRANCE_CLOISTERS

signal sub_area_entered(area_name: String)
signal faith_bridge_state_changed(integrity: float)
signal resonance_hall_secret_revealed
signal bell_tower_glimpsed


func _ready() -> void:
	GameState.force_changed.connect(_on_force_changed)
	GameState.set_region_value(zone_id, "visited", true)
	_initialize_zone_state()


func _initialize_zone_state() -> void:
	# This zone starts with moderate corruption — it's already broken
	var region := GameState.get_region(zone_id)
	if region.get("corruption", 0.0) < 20.0:
		region["corruption"] = 20.0

	# Faith is hostile here by default — the Seminary's curse
	_hostile_faith_active = true

	# Cross-zone persistence: check what happened in Ashborn Depth
	_apply_cross_zone_effects()


func _process(delta: float) -> void:
	_update_faith_bridges(delta)
	_update_hostile_faith(delta)
	_update_seminary_corruption(delta)


# --- H1: Faith Bridge Mechanic (Feels Unsafe) ---
# Bridges made of crystallized prayer. They crumble when doubt is high.
# Truth erodes them. Violence shatters them. Faith... faith makes them grow
# but also makes them unstable (because faith is hostile here).

func _update_faith_bridges(delta: float) -> void:
	var faith := GameState.faith
	var truth := GameState.truth
	var violence := GameState.violence

	# Truth erodes bridges slowly
	if truth >= 40.0:
		_faith_bridge_integrity -= delta * 0.01 * (truth / 100.0)

	# Violence creates sudden cracks
	if violence >= 60.0 and randf() < delta * 0.05:
		_faith_bridge_integrity -= 0.05

	# Faith rebuilds bridges... but also makes them brittle (hostile faith)
	if faith >= 30.0 and _hostile_faith_active:
		# Faith adds material but adds instability — net effect is uncertain
		_faith_bridge_integrity += delta * 0.005 * (faith / 100.0)
		# But hostile faith means the bridges glow dangerously
		if randf() < delta * 0.02:
			_faith_bridge_integrity -= 0.03  # Sudden micro-collapse

	_faith_bridge_integrity = clampf(_faith_bridge_integrity, 0.0, 1.0)
	faith_bridge_state_changed.emit(_faith_bridge_integrity)

	# Bridge collapses at low integrity
	if _faith_bridge_integrity <= 0.1:
		WorldEventManager.event_notification.emit(
			"", "The prayer-bridge shudders. The faith that built it is eating itself.")
		WorldMemory.record("faith_bridge_critical_%s" % zone_id)


# --- H1: Hostile Faith ---
# In this zone, faith doesn't heal. It compels. High faith here increases
# god attention faster, drains player health slowly, and makes NPCs erratic.

func _update_hostile_faith(delta: float) -> void:
	if not _hostile_faith_active:
		return

	var faith := GameState.faith
	if faith < 40.0:
		return

	# Slow health drain — faith is hurting you here
	var drain := (faith - 40.0) / 100.0 * delta * 0.5
	if GameState.player_health > 20.0:  # Never kill outright
		GameState.player_health -= drain

	# God attention rises faster in this zone
	if randf() < delta * 0.1:
		for god_id in GodManager.god_defs:
			GodManager.add_god_attention(god_id, faith * 0.01)

	# Periodic hostile faith messages
	if randf() < delta * 0.02 and faith >= 60.0:
		var messages := [
			"The prayers here are sharp. They cut the mouth that speaks them.",
			"Faith built this place. Faith is why it fell.",
			"Your devotion feeds something in the walls. It is not grateful.",
			"The Seminary remembers every prayer. It uses them as weapons.",
		]
		WorldEventManager.event_notification.emit(
			"SEMINARY", messages[randi() % messages.size()])


# --- H1: Resonance Hall (The Lying Area) ---
# This sub-area claims to be a dead end through environmental cues.
# The corridor narrows, the light dims, NPCs warn you to turn back.
# But it actually leads to the Undercroft — the real heart of the zone.

func enter_resonance_hall() -> void:
	current_sub_area = SubArea.RESONANCE_HALL
	sub_area_entered.emit("resonance_hall")

	if not _resonance_hall_revealed:
		# The lie: "This is a dead end"
		WorldEventManager.event_notification.emit(
			"", "The corridor narrows. The walls press in. There is nothing ahead.")
		WorldMemory.record_ambient("Resonance Hall appears to be a dead end")

		# But if truth is high enough, or if the player persists...
		if GameState.truth >= 50.0:
			_reveal_resonance_hall()


func _reveal_resonance_hall() -> void:
	_resonance_hall_revealed = true
	resonance_hall_secret_revealed.emit()
	WorldEventManager.event_notification.emit(
		"TRUTH", "The wall breathes. It was never solid. The Seminary lied about its own geometry.")
	WorldMemory.record("resonance_hall_revealed")
	WorldMemory.record_ambient("The Resonance Hall's dead end was a lie. The Undercroft opened.")


# --- H1: Inverted Bell Tower (Visible Early, Reachable Late or Never) ---
# The bell tower hangs inverted from the Seminary's ceiling — visible from
# the entrance, but accessing it requires conditions most players won't meet.

func glimpse_bell_tower() -> void:
	bell_tower_glimpsed.emit()
	WorldEventManager.event_notification.emit(
		"", "Above — or below? — a bell tower hangs inverted. Stone defies gravity. The bell is silent.")
	WorldMemory.record("bell_tower_glimpsed")


func check_bell_tower_access() -> bool:
	# Requirements: all three forces above 60, no god obsessed, faith bridge intact
	if GameState.faith < 60.0 or GameState.truth < 60.0 or GameState.violence < 60.0:
		return false
	for god_id in GodManager.god_defs:
		if GodManager.get_god_attention(god_id) >= GodManager.ATTENTION_OBSESSED:
			return false
	if _faith_bridge_integrity < 0.5:
		return false

	_bell_tower_accessible = true
	WorldMemory.record("bell_tower_accessed")
	WorldEventManager.event_notification.emit(
		"", "The inverted tower shudders. A path opens — downward, into the ceiling.")
	return true


# --- H2: Cross-Zone Persistence ---
# Decisions in Ashborn Depth change this zone. Not symmetrically. Not obviously.

func _apply_cross_zone_effects() -> void:
	# If Verath was killed in Ashborn Depth, the Seminary's faith corruption intensifies
	if WorldMemory.has_memory("god_killed_verath"):
		_hostile_faith_active = true
		_seminary_corruption += 20.0
		WorldMemory.record_ambient("Verath's death echoes in the Seminary walls")

	# If the player used extreme violence in Ashborn Depth, patrol routes shift
	if WorldMemory.has_memory("event_violence_world_crisis"):
		# Enemy spawners in this zone become more aggressive
		WorldMemory.record_ambient("Violence in Ashborn Depth changed the Seminary's patrols")

	# If truth was dominant in Ashborn Depth, the Resonance Hall is partially revealed
	if GameState.truth >= 60.0 and WorldMemory.has_memory("event_veil_torn"):
		_resonance_hall_revealed = true
		WorldMemory.record_ambient("Truth tore the veil — the Seminary can't hide its layout")

	# If the Ash Walker was killed in Ashborn Depth, Hollow Church NPCs react
	if WorldMemory.has_memory("npc_killed_npc_ashwalker"):
		WorldMemory.record_ambient("The Hollow Church mourns the Ash Walker. Or pretends to.")

	# Gods remember what you refused to do
	if not WorldMemory.has_memory("god_attention_verath_noticed"):
		# Player ignored Verath entirely — she is louder here
		GodManager.add_god_attention("verath", 15.0)
		WorldMemory.record_ambient("Verath noticed your silence. She speaks louder here.")

	if not WorldMemory.has_memory("god_attention_null_throne_noticed"):
		# The Null Throne finds the Seminary interesting — your neglect drew it
		GodManager.add_god_attention("null_throne", 10.0)


func _update_seminary_corruption(delta: float) -> void:
	_seminary_corruption += delta * 0.005  # Slow constant decay
	var region := GameState.get_region(zone_id)
	region["corruption"] = clampf(
		region.get("corruption", 0.0) + delta * 0.002, 0.0, 100.0)


func _on_force_changed(force_name: String, _old: float, new_value: float) -> void:
	# Faith spikes in the Seminary are dangerous
	if force_name == "faith" and new_value > 70.0 and _hostile_faith_active:
		if randf() < 0.15:
			WorldEventManager.event_notification.emit(
				"SEMINARY", "The walls pulse with devotion. It feels like a trap because it is.")
			# Corruption spike
			var region := GameState.get_region(zone_id)
			region["corruption"] = minf(region.get("corruption", 0.0) + 3.0, 100.0)


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"faith_bridge_integrity": _faith_bridge_integrity,
		"resonance_hall_revealed": _resonance_hall_revealed,
		"bell_tower_accessible": _bell_tower_accessible,
		"seminary_corruption": _seminary_corruption,
		"hostile_faith_active": _hostile_faith_active,
		"current_sub_area": current_sub_area,
	}


func load_state(data: Dictionary) -> void:
	_faith_bridge_integrity = data.get("faith_bridge_integrity", 1.0)
	_resonance_hall_revealed = data.get("resonance_hall_revealed", false)
	_bell_tower_accessible = data.get("bell_tower_accessible", false)
	_seminary_corruption = data.get("seminary_corruption", 0.0)
	_hostile_faith_active = data.get("hostile_faith_active", true)
	current_sub_area = data.get("current_sub_area", SubArea.ENTRANCE_CLOISTERS)
