## MicroTruthEvents — Prevents "everyone lies except Keeper" conclusion.
## Seeds mundane, low-stakes truths from regular NPCs even at low trust.
## These truths are:
##   - Verifiable later (player can check directions, count guards, etc.)
##   - Unrewarded (no loot, no quest flags, no XP)
##   - Mundane (directions, names, weather, counts)
##
## Probability of micro-truths INCREASES as trust approaches the floor.
## This is the anti-nihilism valve: even when the world is deeply unreliable,
## some small things remain true. Not everything is a lie.
extends Node

signal micro_truth_seeded(truth_type: String, content: String)

# --- Truth Seeding ---
# As trust_level drops toward TRUST_FLOOR, micro-truths become more common.
# This creates a paradox for the player: the worse things get, the more
# tiny true things appear. It prevents complete epistemic collapse.

const SEED_CHECK_INTERVAL := 20.0  # Check every 20 seconds
var _seed_timer: float = 0.0

# Base probability of a micro-truth being seeded per check.
# Scales inversely with trust: lower trust = more micro-truths.
const BASE_SEED_CHANCE := 0.05
const LOW_TRUST_SEED_BOOST := 0.35  # At trust floor, chance is BASE + BOOST

# --- Active Micro-Truths ---
# These are truths currently "in play" — NPCs have said them,
# and the world state should eventually confirm them.
var _active_truths: Array[Dictionary] = []
const MAX_ACTIVE_TRUTHS := 8

# --- Verified Truths ---
# Truths the player has had the opportunity to verify.
var _verified_count: int = 0
var _total_seeded: int = 0

# --- Truth Templates ---
# Mundane facts about the world that can be independently verified.
const TRUTH_TYPES := ["direction", "count", "weather", "name", "state"]


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	_seed_timer += delta
	if _seed_timer < SEED_CHECK_INTERVAL:
		return
	_seed_timer = 0.0

	if GameState.witness_mode:
		return

	_try_seed_truth()
	_check_verifications()


## Attempt to seed a micro-truth into the world.
func _try_seed_truth() -> void:
	if _active_truths.size() >= MAX_ACTIVE_TRUTHS:
		return

	# Calculate seed probability — inversely proportional to trust
	var trust := TrustDestruction.trust_level
	var trust_factor := 1.0 - clampf((trust - TrustDestruction.TRUST_FLOOR) / (1.0 - TrustDestruction.TRUST_FLOOR), 0.0, 1.0)
	var chance := BASE_SEED_CHANCE + trust_factor * LOW_TRUST_SEED_BOOST

	if randf() >= chance:
		return

	# Generate a micro-truth based on current world state
	var truth := _generate_micro_truth()
	if truth.is_empty():
		return

	_active_truths.append(truth)
	_total_seeded += 1
	micro_truth_seeded.emit(truth.get("type", ""), truth.get("text", ""))


## Generate a verifiable micro-truth from current world state.
func _generate_micro_truth() -> Dictionary:
	var truth_type: String = TRUTH_TYPES[randi() % TRUTH_TYPES.size()]
	var now := Time.get_unix_time_from_system()

	match truth_type:
		"direction":
			# A true statement about zone connectivity or Keeper location
			var keeper_zones := AnchorManager.keeper_zones
			if keeper_zones.size() > 0:
				var zone: String = keeper_zones[randi() % keeper_zones.size()]
				return {
					"type": "direction",
					"text": "I heard there's shelter in the %s." % zone.replace("_", " "),
					"verifiable_key": "zone_exists_%s" % zone,
					"verifiable_value": true,
					"timestamp": now,
				}

		"count":
			# A true count of something in the world
			var god_count := 0
			for god_id in GodManager.god_defs:
				if GodManager.get_god_state(god_id) != "dead":
					god_count += 1
			return {
				"type": "count",
				"text": "There are %d gods still living." % god_count if god_count > 0 else "The gods are all dead.",
				"verifiable_key": "living_gods",
				"verifiable_value": god_count,
				"timestamp": now,
			}

		"weather":
			# A true statement about world pressure / atmosphere
			var pressure := GameState.world_pressure
			var desc := ""
			if pressure >= 70.0:
				desc = "The ash falls heavier today. The world strains."
			elif pressure >= 40.0:
				desc = "There's tension in the air. Can you feel it?"
			else:
				desc = "It's quiet. The kind of quiet that means something."
			return {
				"type": "weather",
				"text": desc,
				"verifiable_key": "world_pressure_range",
				"verifiable_value": _pressure_range(pressure),
				"timestamp": now,
			}

		"name":
			# A true name of a god or faction
			var gods := GodManager.god_defs.keys()
			if gods.size() > 0:
				var god_id: String = gods[randi() % gods.size()]
				var name := GodManager.get_god_name(god_id)
				return {
					"type": "name",
					"text": "They call it %s. That much is certain." % name,
					"verifiable_key": "god_name_%s" % god_id,
					"verifiable_value": name,
					"timestamp": now,
				}

		"state":
			# A true statement about a faction's attitude
			var factions := FactionManager.faction_defs.keys()
			if factions.size() > 0:
				var fid: String = factions[randi() % factions.size()]
				var attitude := FactionManager.get_attitude(fid)
				var fname := FactionManager.get_faction_name(fid)
				return {
					"type": "state",
					"text": "%s is %s toward outsiders." % [fname, attitude],
					"verifiable_key": "faction_attitude_%s" % fid,
					"verifiable_value": attitude,
					"timestamp": now,
				}

	return {}


func _pressure_range(pressure: float) -> String:
	if pressure >= 70.0:
		return "high"
	elif pressure >= 40.0:
		return "medium"
	return "low"


## Check if any active truths can be verified (world state still matches).
func _check_verifications() -> void:
	var now := Time.get_unix_time_from_system()
	var to_remove: Array[int] = []

	for i in range(_active_truths.size()):
		var truth: Dictionary = _active_truths[i]
		var age: float = now - truth.get("timestamp", 0.0)

		# Truths expire after 10 minutes
		if age > 600.0:
			to_remove.append(i)
			continue

		# Check if truth is still valid (world hasn't changed)
		if _is_still_true(truth):
			# Truth remains verifiable — player could check it
			if age > 120.0:
				# After 2 minutes, count as a verification opportunity
				_verified_count += 1
				to_remove.append(i)

	# Remove in reverse order to preserve indices
	to_remove.reverse()
	for idx in to_remove:
		if idx < _active_truths.size():
			_active_truths.remove_at(idx)


## Check if a micro-truth is still accurate.
func _is_still_true(truth: Dictionary) -> bool:
	var key: String = truth.get("verifiable_key", "")
	var expected = truth.get("verifiable_value")

	if key.begins_with("living_gods"):
		var count := 0
		for god_id in GodManager.god_defs:
			if GodManager.get_god_state(god_id) != "dead":
				count += 1
		return count == expected

	elif key.begins_with("world_pressure_range"):
		return _pressure_range(GameState.world_pressure) == expected

	elif key.begins_with("faction_attitude_"):
		var fid := key.replace("faction_attitude_", "")
		return FactionManager.get_attitude(fid) == expected

	elif key.begins_with("zone_exists_"):
		return true  # Zones always exist

	elif key.begins_with("god_name_"):
		var god_id := key.replace("god_name_", "")
		return GodManager.get_god_name(god_id) == expected

	return true


## Get a random active micro-truth for NPC dialogue injection.
## Returns empty dict if none available.
func get_random_truth_for_npc() -> Dictionary:
	if _active_truths.is_empty():
		return {}
	return _active_truths[randi() % _active_truths.size()]


## Get stats for debug/metrics.
func get_truth_stats() -> Dictionary:
	return {
		"active_truths": _active_truths.size(),
		"total_seeded": _total_seeded,
		"verified_count": _verified_count,
		"current_trust": TrustDestruction.trust_level,
	}


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return get_truth_stats()


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"total_seeded": _total_seeded,
		"verified_count": _verified_count,
	}


func load_state(data: Dictionary) -> void:
	_total_seeded = data.get("total_seeded", 0)
	_verified_count = data.get("verified_count", 0)
