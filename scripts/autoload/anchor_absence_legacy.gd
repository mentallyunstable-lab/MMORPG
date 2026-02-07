## AnchorAbsenceLegacy — Even absence should leave structure.
## In late Witness mode:
##   - NPCs echo Keeper phrasing unconsciously
##   - World retains patterns of truth without source
##   - Implies the anchor changed the world, not ruled it
##
## The Keeper's influence persists as a structural echo — not authority,
## but a pattern of clarity that the world absorbed during its life.
extends Node

signal legacy_phrase_generated(phrase: String)

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


func _ready() -> void:
	AnchorManager.anchor_spoke.connect(_on_keeper_spoke)


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	if GameState.witness_mode:
		_update_witness_legacy()


## Track Keeper influence accumulation.
func _on_keeper_spoke(_topic: String) -> void:
	anchor_influence = clampf(anchor_influence + INFLUENCE_PER_INTERACTION, 0.0, INFLUENCE_MAX)

	# Track which zones the Keeper has spoken in
	var current_zone := AnchorManager._current_zone
	if current_zone != "" and current_zone not in _truth_zones:
		_truth_zones.append(current_zone)


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
	if not GameState.witness_mode:
		return 0.0
	if zone_id in _truth_zones:
		return clampf(anchor_influence / INFLUENCE_MAX * 0.3, 0.0, 0.3)
	return 0.0


## Get how strongly the Keeper's legacy persists (0.0 to 1.0).
func get_legacy_strength() -> float:
	return clampf(anchor_influence / INFLUENCE_MAX, 0.0, 1.0)


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"anchor_influence": anchor_influence,
		"legacy_strength": get_legacy_strength(),
		"truth_zones": _truth_zones.duplicate(),
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"anchor_influence": anchor_influence,
		"truth_zones": _truth_zones.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	anchor_influence = data.get("anchor_influence", 0.0)
	var loaded_zones = data.get("truth_zones", [])
	_truth_zones.clear()
	for z in loaded_zones:
		_truth_zones.append(str(z))
