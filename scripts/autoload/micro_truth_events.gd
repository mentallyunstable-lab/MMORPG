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
## B1 Extensions — Micro-Truth Weaponization:
##   - Truth contradictions: two truths, both correct, lead to incompatible actions
##   - Too-late truths: truths that are useful only after the window for acting has passed
##   - NPC-helping truths: truths that help NPCs but harm the player
extends Node

signal micro_truth_seeded(truth_type: String, content: String)
signal truth_contradiction_seeded(truth_a: String, truth_b: String)
signal too_late_truth_revealed(truth: String, missed_window: float)

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

# --- B1: Truth Contradictions ---
# Two truths, both verifiably correct, that lead to incompatible actions.
# The player must choose which truth to act on. Both are right. Both can't be followed.
var _active_contradictions: Array[Dictionary] = []
const MAX_ACTIVE_CONTRADICTIONS := 3
const CONTRADICTION_CHECK_INTERVAL := 45.0
var _contradiction_timer: float = 0.0

# --- B1: Too-Late Truths ---
# Truths that WERE useful but are revealed after the window has closed.
# The player learns they could have acted differently — but the moment is gone.
var _deferred_truths: Array[Dictionary] = []
const MAX_DEFERRED_TRUTHS := 5
const DEFERRED_TRUTH_DELAY_MIN := 120.0  # 2 minutes minimum delay
const DEFERRED_TRUTH_DELAY_MAX := 300.0  # 5 minutes max

# --- B1: NPC-Helping Truths ---
# Truths that are accurate and help an NPC — but the help comes at the player's expense.
const NPC_HELP_TRUTH_LINES := [
	"The outsider came from the %s. They carry %s weapons.",
	"I saw them near the shrine. They were alone. Vulnerable.",
	"They asked about %s. That tells you what they fear.",
	"Watch their pattern — they always return to the Keeper when uncertain.",
	"They trust too easily. Or not enough. Either way, predictable.",
]


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

	_contradiction_timer += SEED_CHECK_INTERVAL
	if _contradiction_timer >= CONTRADICTION_CHECK_INTERVAL:
		_contradiction_timer = 0.0
		_try_seed_contradiction()
	_check_deferred_truths()


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


# --- B1: Truth Contradictions ---

## Try to seed a contradiction: two truths that are both correct but incompatible.
func _try_seed_contradiction() -> void:
	if _active_contradictions.size() >= MAX_ACTIVE_CONTRADICTIONS:
		return
	# Only seed contradictions when trust is below 0.7 — the world is already confused
	if TrustDestruction.trust_level > 0.7:
		return
	if randf() >= 0.2:  # 20% chance per check
		return

	var contradiction := _generate_contradiction()
	if contradiction.is_empty():
		return
	_active_contradictions.append(contradiction)
	truth_contradiction_seeded.emit(
		contradiction.get("truth_a", ""),
		contradiction.get("truth_b", "")
	)


## Generate a pair of truths that are both correct but suggest opposite actions.
func _generate_contradiction() -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var dominant := GameState.get_dominant_force()
	var pressure := GameState.world_pressure

	# Type 1: Force balance contradiction
	# "Violence is rising" (true) + "The Ironvow respect strength" (also true)
	# Acting on the first means reducing violence; acting on the second means using it.
	if dominant == "violence" and GameState.violence > 50.0:
		return {
			"truth_a": "Violence is rising. If it continues, the region will destabilize.",
			"truth_b": "The Ironvow respond to displays of strength. They'll listen if you show force.",
			"action_a": "reduce_violence",
			"action_b": "increase_violence",
			"timestamp": now,
		}

	# Type 2: God state contradiction
	# "Verath is weakening" (true) + "Weakened gods are more dangerous" (also true)
	# Help the god or let it die? Both truths suggest different responses.
	for god_id in GodManager.god_defs:
		var state := GodManager.get_god_state(god_id)
		var name := GodManager.get_god_name(god_id)
		if state in ["weakened", "fading"]:
			return {
				"truth_a": "%s is %s. Without intervention, it will die." % [name, state],
				"truth_b": "A %s god lashes out. Its desperation makes it more dangerous, not less." % state,
				"action_a": "help_god",
				"action_b": "avoid_god",
				"timestamp": now,
			}

	# Type 3: Faction contradiction
	# Two factions both have legitimate claims, player can only support one.
	if pressure > 40.0:
		return {
			"truth_a": "The Ashwalkers are protecting civilians in the eastern ruins. They need support.",
			"truth_b": "The Truthseekers have information that could save lives — but they won't share it without trust.",
			"action_a": "support_ashwalkers",
			"action_b": "support_truthseekers",
			"timestamp": now,
		}

	return {}


# --- B1: Too-Late Truths ---

## Snapshot a truth that will be revealed too late to act on.
## Called when world state changes significantly — records what WAS true.
func record_deferred_truth(truth_text: String, relevance_window: float) -> void:
	if _deferred_truths.size() >= MAX_DEFERRED_TRUTHS:
		_deferred_truths.pop_front()
	_deferred_truths.append({
		"text": truth_text,
		"recorded_at": Time.get_unix_time_from_system(),
		"reveal_delay": randf_range(DEFERRED_TRUTH_DELAY_MIN, DEFERRED_TRUTH_DELAY_MAX),
		"relevance_window": relevance_window,
		"revealed": false,
	})


## Check if any deferred truths should be revealed now.
func _check_deferred_truths() -> void:
	var now := Time.get_unix_time_from_system()
	var to_remove: Array[int] = []
	for i in range(_deferred_truths.size()):
		var dt: Dictionary = _deferred_truths[i]
		if dt.get("revealed", false):
			to_remove.append(i)
			continue
		var age: float = now - dt.get("recorded_at", 0.0)
		if age >= dt.get("reveal_delay", 300.0):
			dt["revealed"] = true
			var missed: float = age - dt.get("relevance_window", 60.0)
			too_late_truth_revealed.emit(dt.get("text", ""), missed)
			WorldMemory.record_ambient("A truth arrived too late to matter")
	to_remove.reverse()
	for idx in to_remove:
		if idx < _deferred_truths.size():
			_deferred_truths.remove_at(idx)


# --- B1: NPC-Helping Truths ---

## Get a truth that helps an NPC but exposes the player.
## Called by NPC dialogue systems when an NPC wants to share "helpful" info
## that actually weakens the player's position.
func get_npc_helping_truth() -> String:
	var dominant := GameState.get_dominant_force()
	var template: String = NPC_HELP_TRUTH_LINES[randi() % NPC_HELP_TRUTH_LINES.size()]
	# Fill in dynamic values
	var zones := AnchorManager.keeper_zones
	var zone_name: String = zones[randi() % zones.size()].replace("_", " ") if zones.size() > 0 else "the ruins"
	var force_word := dominant.capitalize()
	return template % [zone_name, force_word] if template.count("%s") == 2 else template % force_word if template.count("%s") == 1 else template


## Get a contradiction pair for NPC dialogue.
func get_active_contradiction() -> Dictionary:
	if _active_contradictions.is_empty():
		return {}
	return _active_contradictions[randi() % _active_contradictions.size()]


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
		"active_contradictions": _active_contradictions.size(),
		"deferred_truths_pending": _deferred_truths.size(),
	}


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return get_truth_stats()


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"total_seeded": _total_seeded,
		"verified_count": _verified_count,
		"contradiction_count": _active_contradictions.size(),
	}


func load_state(data: Dictionary) -> void:
	_total_seeded = data.get("total_seeded", 0)
	_verified_count = data.get("verified_count", 0)
