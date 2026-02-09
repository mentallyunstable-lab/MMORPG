## AnchorAbsenceLegacy — Even absence should leave structure.
## In late Witness mode:
##   - NPCs echo Keeper phrasing unconsciously
##   - World retains patterns of truth without source
##   - Implies the anchor changed the world, not ruled it
##
## The Keeper's influence persists as a structural echo — not authority,
## but a pattern of clarity that the world absorbed during its life.
##
## C2 Extensions — Anchor Absence Legacy Expansion:
##   - NPCs misquote the Keeper incorrectly but confidently
##   - Truth zones decay slowly instead of disappearing
##   - One zone persists too long and causes harm (over-truth effect)
extends Node

signal legacy_phrase_generated(phrase: String)
signal keeper_misquoted(original: String, misquote: String)
signal truth_zone_decayed(zone_id: String, new_reliability: float)
signal harmful_zone_detected(zone_id: String, harm_type: String)

# --- Legacy State ---
# The Keeper's influence score: how much the anchor shaped the world before ending.
var anchor_influence: float = 0.0
const INFLUENCE_PER_INTERACTION := 2.0
const INFLUENCE_PER_TRUTH_TOLD := 0.5
const INFLUENCE_MAX := 100.0

# --- Keeper Phrasing Templates ---
# Patterns the Keeper uses that NPCs might unconsciously echo.
const KEEPER_PHRASES := [
	"I am here.",
	"That is what I see.",
	"I cannot see clearly right now.",
	"Ask me later.",
	"That is enough.",
	"I will be here.",
	"The world strains.",
	"Be careful what you believe.",
]

# Adapted versions that NPCs echo without knowing why.
const ECHO_PHRASES := [
	"...I don't know why I said that. It felt right.",
	"Something about those words. Like I've heard them before.",
	"I spoke without thinking. The phrasing came from nowhere.",
	"There's a shape to the truth here. I can't explain it.",
	"The words arrange themselves. Like they remember being spoken clearly once.",
]

# --- Truth Patterns ---
# In Witness mode, the world retains pockets of reliability
# where the Keeper's influence was strongest.
var _truth_zones: Array[String] = []  # Zone IDs where truth persists

const CHECK_INTERVAL := 5.0
var _check_timer: float = 0.0

# --- C2: NPC Misquotes ---
# NPCs remember Keeper phrases... wrong. But they say it with full confidence.
# The misquotes are close enough to feel right, wrong enough to mislead.
const KEEPER_MISQUOTES := {
	"I am here.": [
		"The Keeper said 'I was here.' Past tense. Like it knew it would leave.",
		"The Keeper always says 'I am here.' But it means 'I am all that's here.'",
		"'I am here' — that's what it said. I think it was asking, not telling.",
	],
	"That is what I see.": [
		"The Keeper told me 'That is all I see.' It sounded... limited.",
		"'What I see is what matters.' That's the Keeper's line. Word for word.",
		"The Keeper said 'That is what I choose to see.' Interesting distinction.",
	],
	"The world strains.": [
		"The Keeper warned us: 'The world is breaking.' Its exact words.",
		"'The world strains against itself.' That's what the Keeper said. Or close enough.",
		"The Keeper said the world was fine. Well — that it was straining. Same thing.",
	],
	"Be careful what you believe.": [
		"The Keeper said 'Don't believe anything.' Clear enough.",
		"'Be careful what you believe' — the Keeper told me that. Then it went silent.",
		"The Keeper warned me: 'Believe nothing you hear.' Direct quote.",
	],
}

# --- C2: Truth Zone Decay ---
# Truth zones don't disappear when the Keeper leaves — they DECAY.
# Reliability drops slowly from the Keeper's bonus toward zero.
var _zone_reliability: Dictionary = {}  # zone_id -> float (0.0-1.0)
const ZONE_DECAY_RATE := 0.001          # Per tick — very slow
const ZONE_MINIMUM_RELIABILITY := 0.05  # Never fully zero — trace of truth remains

# --- C2: Harmful Persistent Zone ---
# One truth zone persists too long. Truth without context becomes dogma.
# The zone's reliability stays high but the information is OUTDATED.
var _harmful_zone_id: String = ""
var _harmful_zone_stale_time: float = 0.0
const HARMFUL_ZONE_STALE_THRESHOLD := 600.0  # 10 minutes stale = harmful
var _harmful_zone_triggered: bool = false


func _ready() -> void:
	AnchorManager.anchor_spoke.connect(_on_keeper_spoke)


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	if GameState.witness_mode:
		_update_witness_legacy()
	_decay_truth_zones()
	_check_harmful_zone()


## Track Keeper influence accumulation.
func _on_keeper_spoke(_topic: String) -> void:
	anchor_influence = clampf(anchor_influence + INFLUENCE_PER_INTERACTION, 0.0, INFLUENCE_MAX)

	# Track which zones the Keeper has spoken in
	var current_zone := AnchorManager._current_zone
	if current_zone != "" and current_zone not in _truth_zones:
		_truth_zones.append(current_zone)
		_zone_reliability[current_zone] = 1.0  # Full reliability when Keeper is present

	# Refresh reliability for zones the Keeper speaks in
	if current_zone in _zone_reliability:
		_zone_reliability[current_zone] = 1.0


## In Witness mode, check if NPCs should echo Keeper phrasing.
func _update_witness_legacy() -> void:
	# Influence determines how much the Keeper's patterns persist
	# Low influence = rare echoes, high influence = frequent echoes
	pass  # The actual echoing happens when NPCs query this system


## Get a Keeper-echo phrase for NPC dialogue in Witness mode.
## Returns empty string if no echo should occur.
func get_witness_echo() -> String:
	if not GameState.witness_mode:
		return ""

	# Probability based on anchor influence
	var echo_chance := clampf(anchor_influence / INFLUENCE_MAX * 0.4, 0.0, 0.4)
	if randf() >= echo_chance:
		return ""

	var keeper_phrase: String = KEEPER_PHRASES[randi() % KEEPER_PHRASES.size()]
	var echo_comment: String = ECHO_PHRASES[randi() % ECHO_PHRASES.size()]

	var phrase := "\"%s\" %s" % [keeper_phrase, echo_comment]
	legacy_phrase_generated.emit(phrase)
	return phrase


## Check if a zone retains truth patterns (Keeper influence lingers).
func is_truth_zone(zone_id: String) -> bool:
	return zone_id in _truth_zones


## Get the truth reliability bonus for a zone.
## In zones where the Keeper spoke often, even post-ending truth persists.
func get_zone_truth_bonus(zone_id: String) -> float:
	if zone_id in _zone_reliability:
		return clampf(_zone_reliability[zone_id] * 0.3, 0.0, 0.3)
	if not GameState.witness_mode:
		return 0.0
	if zone_id in _truth_zones:
		return clampf(anchor_influence / INFLUENCE_MAX * 0.3, 0.0, 0.3)
	return 0.0


## Get how strongly the Keeper's legacy persists (0.0 to 1.0).
func get_legacy_strength() -> float:
	return clampf(anchor_influence / INFLUENCE_MAX, 0.0, 1.0)


# --- C2: NPC Misquotes ---

## Get a confident misquote of a Keeper phrase for NPC dialogue.
## NPCs remember the Keeper's words wrong — but say them with certainty.
func get_keeper_misquote() -> String:
	if anchor_influence < 20.0:
		return ""  # Not enough influence for NPCs to remember
	var originals := KEEPER_MISQUOTES.keys()
	var original: String = originals[randi() % originals.size()]
	var misquotes: Array = KEEPER_MISQUOTES[original]
	var misquote: String = misquotes[randi() % misquotes.size()]
	keeper_misquoted.emit(original, misquote)
	return misquote


# --- C2: Truth Zone Decay ---

## Decay truth zone reliability over time.
func _decay_truth_zones() -> void:
	for zone_id in _zone_reliability.keys():
		# Don't decay if Keeper is currently in this zone
		if AnchorManager._current_zone == zone_id and AnchorManager.current_state == AnchorManager.AnchorState.PRESENT:
			continue
		var old_val: float = _zone_reliability[zone_id]
		_zone_reliability[zone_id] = maxf(old_val - ZONE_DECAY_RATE * CHECK_INTERVAL, ZONE_MINIMUM_RELIABILITY)
		if old_val > 0.5 and _zone_reliability[zone_id] <= 0.5:
			truth_zone_decayed.emit(zone_id, _zone_reliability[zone_id])


## Get the current reliability of a truth zone.
func get_zone_reliability(zone_id: String) -> float:
	return _zone_reliability.get(zone_id, 0.0)


# --- C2: Harmful Persistent Zone ---

## Check if any truth zone has persisted too long and become harmful.
func _check_harmful_zone() -> void:
	if _harmful_zone_triggered:
		return
	# Find the zone with highest reliability that the Keeper is NOT in
	for zone_id in _zone_reliability:
		if AnchorManager._current_zone == zone_id:
			continue
		var reliability: float = _zone_reliability[zone_id]
		if reliability > 0.7:
			# This zone still feels very reliable — track staleness
			if _harmful_zone_id != zone_id:
				_harmful_zone_id = zone_id
				_harmful_zone_stale_time = 0.0
			_harmful_zone_stale_time += CHECK_INTERVAL
			if _harmful_zone_stale_time >= HARMFUL_ZONE_STALE_THRESHOLD:
				_harmful_zone_triggered = true
				harmful_zone_detected.emit(zone_id, "outdated_truth")
				WorldMemory.record("harmful_truth_zone_%s" % zone_id)
				WorldMemory.record_ambient("A place that once held truth now holds certainty. That is worse.")
			return
	# No harmful zone candidate
	_harmful_zone_stale_time = 0.0


## Is a specific zone harmfully persistent?
func is_harmful_zone(zone_id: String) -> bool:
	return _harmful_zone_triggered and _harmful_zone_id == zone_id


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"anchor_influence": anchor_influence,
		"legacy_strength": get_legacy_strength(),
		"truth_zones": _truth_zones.duplicate(),
		"zone_reliability": _zone_reliability.duplicate(),
		"harmful_zone": _harmful_zone_id,
		"harmful_zone_stale": _harmful_zone_stale_time,
		"harmful_zone_triggered": _harmful_zone_triggered,
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"anchor_influence": anchor_influence,
		"truth_zones": _truth_zones.duplicate(),
		"zone_reliability": _zone_reliability.duplicate(),
		"harmful_zone_id": _harmful_zone_id,
		"harmful_zone_triggered": _harmful_zone_triggered,
	}


func load_state(data: Dictionary) -> void:
	anchor_influence = data.get("anchor_influence", 0.0)
	var loaded_zones = data.get("truth_zones", [])
	_truth_zones.clear()
	for z in loaded_zones:
		_truth_zones.append(str(z))
	_zone_reliability = data.get("zone_reliability", {})
	_harmful_zone_id = data.get("harmful_zone_id", "")
	_harmful_zone_triggered = data.get("harmful_zone_triggered", false)
