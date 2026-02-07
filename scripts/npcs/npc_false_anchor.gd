## NPC: False Anchor — Tests whether the player has learned what trust means.
## An NPC who:
##   - Sounds calm
##   - Speaks confidently
##   - Is wrong in subtle ways
##   - Never claims to be truthful
##   - Lets players PROJECT anchor-status onto them
##
## Consequences escalate slowly. No "gotcha." Let players indict themselves.
## This NPC exists to test the player's epistemic maturity.
## If they've learned from the Keeper, they'll notice the difference.
## If they haven't, they'll trust this NPC and pay for it gradually.
extends NPCBase

# --- False Anchor Configuration ---
# Corruption intensity: how far off the false anchor's claims are.
# Starts subtle, escalates if the player keeps returning.
var _interactions_count: int = 0
var _corruption_intensity: float = 0.1  # 0.0 = almost true, 1.0 = completely wrong
const CORRUPTION_ESCALATION := 0.05     # Per interaction

# --- Tracking ---
var _player_trusted_count: int = 0  # Times player acted on false info
var _last_claims: Array[Dictionary] = []  # What this NPC claimed last time
const MAX_CLAIMS := 5


func _ready() -> void:
	npc_name = "The Stillwater"
	force_affinity = "neutral"
	super._ready()

	# Override: remove force-change visual reaction (mimics Keeper stability)
	if GameState.force_changed.is_connected(_on_force_changed):
		GameState.force_changed.disconnect(_on_force_changed)


func interact(player: Node) -> void:
	if DialogueManager.is_active:
		return

	if GameState.witness_mode:
		var witness := _get_witness_dialogue()
		if witness.size() > 0:
			DialogueManager.start_dialogue(witness, "...")
		return

	_interactions_count += 1
	_corruption_intensity = clampf(_corruption_intensity + CORRUPTION_ESCALATION, 0.1, 0.8)

	var dialogue := _get_dialogue()
	if dialogue.size() > 0:
		DialogueManager.start_dialogue(dialogue, npc_name)
		has_spoken = true


## False Anchor dialogue — calm, confident, subtly WRONG.
func _get_dialogue() -> Array:
	var lines: Array = []

	# Greeting — deliberately calm and stable-sounding
	lines.append({"speaker": npc_name, "text": "I am here. The noise has not reached me."})

	# False report — reads real values, then corrupts them subtly
	var dominant := GameState.get_dominant_force()
	var dom_value := GameState.get_force(dominant)

	# Corrupt the dominant force report
	var false_dom := _corrupt_subtle(dominant)
	var false_value := _corrupt_value(dom_value)
	lines.append({"speaker": npc_name, "text": _describe_false_force(false_dom, false_value)})

	# False god report — shifted by 1 state
	var god_report := _describe_false_gods()
	if god_report != "":
		lines.append({"speaker": npc_name, "text": god_report})

	# Pressure assessment — always slightly optimistic or slightly pessimistic
	var pressure := GameState.world_pressure
	if pressure >= 60.0:
		lines.append({"speaker": npc_name, "text": "The world steadies itself. I can feel it calming."})
	elif pressure >= 30.0:
		lines.append({"speaker": npc_name, "text": "There is tension, but nothing beyond the ordinary."})
	else:
		lines.append({"speaker": npc_name, "text": "A storm gathers just beyond perception. Be wary."})

	# Never claims truthfulness — but implies reliability through tone
	lines.append({"speaker": npc_name, "text": "Is there more you would know?",
		"choices": [
			{"text": "Tell me about the forces.", "next_id": "false_forces"},
			{"text": "Tell me about the gods.", "next_id": "false_gods"},
			{"text": "Something about you feels... familiar.", "next_id": "familiarity"},
			{"text": "No. I should go.", "next_id": "farewell"},
		]
	})

	# Detail branches — all subtly wrong
	lines.append({"id": "false_forces", "speaker": npc_name, "text": _describe_false_all_forces()})
	lines.append({"id": "false_gods", "speaker": npc_name, "text": _describe_false_all_gods()})
	lines.append({"id": "familiarity", "speaker": npc_name, "text": "I am simply someone who pays attention. Nothing more."})
	lines.append({"id": "farewell", "speaker": npc_name, "text": "Go carefully. The world is less stable than it appears."})

	# Record claims for delayed validation checking
	_record_claims()

	return lines


## Record what this NPC claimed for tracking purposes.
func _record_claims() -> void:
	var claim := {
		"dominant_force": GameState.get_dominant_force(),
		"false_dominant": _corrupt_subtle(GameState.get_dominant_force()),
		"timestamp": Time.get_unix_time_from_system(),
		"interaction": _interactions_count,
	}
	_last_claims.append(claim)
	if _last_claims.size() > MAX_CLAIMS:
		_last_claims.pop_front()

	# Register claim with DelayedValidation — this one will FAIL to validate
	DelayedValidation.record_claim(npc_name, "force_prediction", {
		"force": _corrupt_subtle(GameState.get_dominant_force()),
		"direction": "rise" if randf() > 0.5 else "fall",
		"original_value": _corrupt_value(GameState.get_force(GameState.get_dominant_force())),
	})


## Subtly corrupt a force name — sometimes reports the wrong dominant force.
func _corrupt_subtle(real_force: String) -> String:
	if randf() > _corruption_intensity:
		return real_force
	var forces := ["faith", "truth", "violence"]
	forces.erase(real_force)
	return forces[randi() % forces.size()]


## Corrupt a value — shift it plausibly.
func _corrupt_value(real_value: float) -> float:
	var offset := randf_range(-10.0, 10.0) * _corruption_intensity
	return clampf(real_value + offset, 0.0, 100.0)


func _describe_false_force(force_name: String, value: float) -> String:
	var intensity := ""
	if value >= 80.0:
		intensity = "dominant"
	elif value >= 60.0:
		intensity = "strong"
	elif value >= 40.0:
		intensity = "present"
	elif value >= 20.0:
		intensity = "stirring"
	else:
		intensity = "quiet"
	return "%s is %s in this world." % [force_name.capitalize(), intensity]


func _describe_false_all_forces() -> String:
	var faith_val := _corrupt_value(GameState.faith)
	var truth_val := _corrupt_value(GameState.truth)
	var violence_val := _corrupt_value(GameState.violence)
	return "Faith is %s. Truth is %s. Violence is %s. That is what I observe." % [
		_intensity_word(faith_val), _intensity_word(truth_val), _intensity_word(violence_val)]


func _describe_false_gods() -> String:
	var parts: Array[String] = []
	for god_id in GodManager.god_defs:
		var real_state := GodManager.get_god_state(god_id)
		var name := GodManager.get_god_name(god_id)

		# Corrupt the state subtly
		var false_state := real_state
		if randf() < _corruption_intensity:
			false_state = TrustDestruction.corrupt_god_state(real_state)

		match false_state:
			"dead":
				parts.append("%s is gone." % name)
			"fading":
				parts.append("%s fades." % name)
			"weakened":
				parts.append("%s is diminished." % name)
			"dormant":
				parts.append("%s rests." % name)
			"manifest":
				parts.append("%s is active." % name)
			"ascended":
				parts.append("%s has risen." % name)

	if parts.is_empty():
		return ""
	return " ".join(parts)


func _describe_false_all_gods() -> String:
	var lines: Array[String] = []
	for god_id in GodManager.god_defs:
		var real_state := GodManager.get_god_state(god_id)
		var name := GodManager.get_god_name(god_id)
		var false_state := real_state
		if randf() < _corruption_intensity * 1.5:
			false_state = TrustDestruction.corrupt_god_state(real_state)
		lines.append("%s is %s." % [name, false_state])
	return " ".join(lines)


func _intensity_word(value: float) -> String:
	if value >= 80.0:
		return "overwhelming"
	elif value >= 60.0:
		return "strong"
	elif value >= 40.0:
		return "building"
	elif value >= 20.0:
		return "stirring"
	return "still"


## Witness mode — the False Anchor is exposed.
func _get_witness_dialogue() -> Array:
	if has_spoken:
		return [
			{"speaker": "...", "text": "The Stillwater lies here. Their face is calm even in death."},
			{"speaker": "...", "text": "You wonder how much of what they said was true. Not all of it. Not none of it."},
		]
	return [
		{"speaker": "...", "text": "Someone you never spoke to. They look like they knew things."},
	]


# No faction — like the Keeper
func _is_faction_hostile() -> bool:
	return false

func _get_faction_id() -> String:
	return ""


# --- Persistence ---

func save_state() -> Dictionary:
	var base := super.save_state()
	base["interactions_count"] = _interactions_count
	base["corruption_intensity"] = _corruption_intensity
	base["player_trusted_count"] = _player_trusted_count
	return base


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	_interactions_count = data.get("interactions_count", 0)
	_corruption_intensity = data.get("corruption_intensity", 0.1)
	_player_trusted_count = data.get("player_trusted_count", 0)
