## NPC: The Keeper — The single point of truth in a world of lies.
## No faction. No force affinity. Neutral observer who reports the actual state of the world.
##
## RULES (these are absolute, not suggestions):
##   1. NEVER lies. Every line of dialogue reflects real GameState values.
##   2. NEVER contradicts itself. If it said something before, it was true then.
##   3. Can DISAPPEAR (go silent, be absent) but never DECEIVES.
##   4. Immune to god interference — gods cannot warp the Keeper's words.
##   5. Immune to trust destruction — the Keeper always tells truth.
##
## The Keeper speaks in plain, unadorned language. No manipulation, no emotional coloring.
## When silent: acknowledges the player but refuses to speak about the world.
## When absent: simply not there. No body, no trace. Just absence.
## In witness mode: the only NPC that might still be "present". Not alive — just... still there.
##
## Visual identity: stable. No glow oscillation, no force-reactive pulse.
## The Keeper looks the same at force 0 and force 100. That IS the tell.
extends NPCBase


func _ready() -> void:
	npc_name = "The Keeper"
	force_affinity = "neutral"
	super._ready()

	# Register with the anchor system
	AnchorManager.register_anchor(self)

	# Override: remove force-change visual reaction (the Keeper doesn't react to forces)
	if GameState.force_changed.is_connected(_on_force_changed):
		GameState.force_changed.disconnect(_on_force_changed)


func _exit_tree() -> void:
	AnchorManager.unregister_anchor(self)
	super._exit_tree()


## The Keeper's interaction — always truthful, never manipulative.
## Now integrates with KeeperOverreliance for dependency-aware dialogue.
func interact(player: Node) -> void:
	if DialogueManager.is_active:
		return

	# Witness mode — The Keeper is still here. The only one.
	# Now with reflection variants based on player history (Phase 7.13).
	if GameState.witness_mode:
		var witness_dialogue := _get_witness_dialogue()
		DialogueManager.start_dialogue(witness_dialogue, npc_name)
		AnchorManager.record_interaction("witness")
		return

	# Check anchor state — silent means present but won't speak about the world
	if AnchorManager.current_state == AnchorManager.AnchorState.SILENT:
		var silence_dialogue := _get_silence_dialogue()
		DialogueManager.start_dialogue(silence_dialogue, npc_name)
		AnchorManager.record_interaction("silence")
		return

	# Overreliance warning — if dependency is HIGH, warn before giving info.
	# No mechanical punishment. Only psychological. (Phase 1.2)
	if KeeperOverreliance.should_warn_player():
		var warning := KeeperOverreliance.get_warning_dialogue()
		# Still give info after warning — Keeper never withholds truth
		var dialogue := _get_dialogue()
		warning.append_array(dialogue)
		DialogueManager.start_dialogue(warning, npc_name)
		has_spoken = true
		AnchorManager.record_interaction("world_state")
		return

	# Normal interaction — truthful world state report
	# Brevity scales with dependency (Phase 1.2)
	var dialogue := _get_dialogue()
	if dialogue.size() > 0:
		DialogueManager.start_dialogue(dialogue, npc_name)
		has_spoken = true
		AnchorManager.record_interaction("world_state")


## Truthful dialogue — reads REAL values from GameState and reports them plainly.
## Brevity scales with KeeperOverreliance: high dependency = fewer volunteered details.
## The Keeper NEVER withholds truth when asked directly — but volunteers less at high dependency.
func _get_dialogue() -> Array:
	var lines: Array = []
	var max_details := KeeperOverreliance.get_max_detail_lines()

	# Greeting — always the same. Stable. Recognizable.
	lines.append({"speaker": npc_name, "text": "I am here."})

	var detail_count := 0

	# Report the dominant force — truthfully (always included)
	var dominant := GameState.get_dominant_force()
	var dom_value := GameState.get_force(dominant)
	lines.append({"speaker": npc_name, "text": _describe_force_state(dominant, dom_value)})
	detail_count += 1

	# Report god states — truthfully (brevity-gated)
	if detail_count < max_details:
		var god_report := _describe_god_states()
		if god_report != "":
			lines.append({"speaker": npc_name, "text": god_report})
			detail_count += 1

	# Report world pressure (brevity-gated)
	if detail_count < max_details:
		var pressure := GameState.world_pressure
		if pressure >= 70.0:
			lines.append({"speaker": npc_name, "text": "The world strains under combined pressure. This is not sustainable."})
			detail_count += 1
		elif pressure >= 40.0:
			lines.append({"speaker": npc_name, "text": "The forces are building. The world notices."})
			detail_count += 1

	# Report trust level — the Keeper is aware the world lies (brevity-gated)
	if detail_count < max_details:
		var trust_desc := TrustDestruction.get_trust_description()
		if TrustDestruction.trust_level < 0.7:
			lines.append({"speaker": npc_name, "text": "The world's voice is %s. Be careful what you believe." % trust_desc})
			detail_count += 1

	# Offer choice — but no force manipulation. The Keeper doesn't push.
	# Choices are ALWAYS available — the Keeper never refuses to answer direct questions.
	lines.append({"speaker": npc_name, "text": "What would you know?",
		"choices": [
			{"text": "Tell me about the forces.", "next_id": "forces_detail"},
			{"text": "Tell me about the gods.", "next_id": "gods_detail"},
			{"text": "Tell me about this place.", "next_id": "zone_detail"},
			{"text": "Nothing. I just needed to see you.", "next_id": "farewell"},
		]
	})

	# --- Detail branches (all truthful, no force rewards) ---

	lines.append({"id": "forces_detail", "speaker": npc_name, "text": _describe_all_forces()})
	lines.append({"id": "gods_detail", "speaker": npc_name, "text": _describe_all_gods()})
	lines.append({"id": "zone_detail", "speaker": npc_name, "text": _describe_current_zone()})
	lines.append({"id": "farewell", "speaker": npc_name, "text": "That is enough. I will be here."})

	return lines


## Silence dialogue — present but won't report world state.
## This is honest: "I cannot see clearly" is true, not a lie.
func _get_silence_dialogue() -> Array:
	var reason := ""
	if GameState.world_pressure >= AnchorManager.SILENCE_PRESSURE_THRESHOLD:
		reason = "The noise is too great. I cannot separate what is from what seems to be."
	elif AnchorManager._get_max_god_attention() >= AnchorManager.SILENCE_ATTENTION_THRESHOLD:
		reason = "Something divine presses close. I will not speak while it listens."
	else:
		reason = "I cannot see clearly right now."

	return [
		{"speaker": npc_name, "text": "I am here."},
		{"speaker": npc_name, "text": reason},
		{"speaker": npc_name, "text": "Ask me later."},
	]


## Witness mode — The Keeper is the only NPC that persists. Not alive. Just... still here.
## Phase 7.13: Reflection variants based on player history:
##   - Dependency score (how much they relied on the Keeper)
##   - Silence exposure (how much silence they endured)
##   - Truth misuse events (whether they misapplied truth)
func _get_witness_dialogue() -> Array:
	var ending := GameState.ending_type

	var reflection := ""
	match ending:
		"god_death":
			reflection = "A god died. The world followed. I watched."
		"god_ascension":
			reflection = "A god rose beyond itself. The world could not contain it. I watched."
		"ashfall":
			reflection = "The forces exceeded what reality could hold. Ash fell. I watched."
		_:
			reflection = "It ended. I watched."

	var lines: Array = [
		{"speaker": npc_name, "text": "I am still here."},
		{"speaker": npc_name, "text": reflection},
	]

	# --- Anchor Reflection Variants (Phase 7.13) ---
	# The Keeper's final words change based on how the player related to truth.

	var dependency_tier := KeeperOverreliance.get_dependency_tier()
	var silence_time := SilenceMemory.get_total_silence_time()
	var truth_misused := TruthMisuse.has_misuse_history()

	# Dependency reflection
	match dependency_tier:
		"high":
			lines.append({"speaker": npc_name, "text": "You sought certainty. You came to me when the world was unclear."})
			lines.append({"speaker": npc_name, "text": "I gave you what I could. But certainty was never mine to grant."})
		"medium":
			lines.append({"speaker": npc_name, "text": "You returned when you needed to. Not always. Not never."})
		"low":
			lines.append({"speaker": npc_name, "text": "You endured uncertainty. You chose without me more often than not."})
			lines.append({"speaker": npc_name, "text": "That is harder than it sounds."})

	# Silence exposure reflection
	if silence_time > 300.0:  # More than 5 minutes total
		lines.append({"speaker": npc_name, "text": "There were times I could not speak. You moved through them."})
		if SilenceMemory.get_total_silence_decisions() > 5:
			lines.append({"speaker": npc_name, "text": "You made decisions in my silence. That required something I cannot name."})

	# Truth misuse reflection
	if truth_misused:
		lines.append({"speaker": npc_name, "text": "You mistook truth for safety. They are not the same."})
		lines.append({"speaker": npc_name, "text": "I told you what was real. What you built from it was yours."})

	# God interference reflection
	if GodInterferenceEvents.has_interference_history():
		lines.append({"speaker": npc_name, "text": "The gods reached for this place. They could not take it."})
		lines.append({"speaker": npc_name, "text": "That cost something. I felt it."})

	# Final line — always the same
	lines.append({"speaker": npc_name, "text": "You are still here too. That is something."})

	return lines


# --- Truthful Description Generators ---
# These read REAL values from GameState and convert them to natural language.
# No corruption. No embellishment. Just what IS.

func _describe_force_state(force_name: String, value: float) -> String:
	var intensity := ""
	if value >= 90.0:
		intensity = "overwhelming"
	elif value >= 70.0:
		intensity = "strong"
	elif value >= 50.0:
		intensity = "rising"
	elif value >= 30.0:
		intensity = "present"
	elif value >= 10.0:
		intensity = "faint"
	else:
		intensity = "absent"

	var force_word := force_name.capitalize()
	return "%s is %s in this world." % [force_word, intensity]


func _describe_all_forces() -> String:
	var faith_desc := _force_intensity_word(GameState.faith)
	var truth_desc := _force_intensity_word(GameState.truth)
	var violence_desc := _force_intensity_word(GameState.violence)
	return "Faith is %s. Truth is %s. Violence is %s. That is what I see." % [faith_desc, truth_desc, violence_desc]


func _force_intensity_word(value: float) -> String:
	if value >= 90.0:
		return "overwhelming"
	elif value >= 70.0:
		return "strong"
	elif value >= 50.0:
		return "building"
	elif value >= 30.0:
		return "stirring"
	elif value >= 10.0:
		return "faint"
	return "still"


func _describe_god_states() -> String:
	var parts: Array[String] = []
	for god_id in GodManager.god_defs:
		var state := GodManager.get_god_state(god_id)
		var name := GodManager.get_god_name(god_id)

		match state:
			"dead":
				parts.append("%s is dead." % name)
			"fading":
				parts.append("%s is fading." % name)
			"weakened":
				parts.append("%s is weak." % name)
			"dormant":
				parts.append("%s sleeps." % name)
			"manifest":
				parts.append("%s is present." % name)
			"ascended":
				parts.append("%s has transcended." % name)

	if parts.is_empty():
		return ""
	return " ".join(parts)


func _describe_all_gods() -> String:
	var lines: Array[String] = []
	for god_id in GodManager.god_defs:
		var state := GodManager.get_god_state(god_id)
		var name := GodManager.get_god_name(god_id)
		var stability := GameState.get_god_stability(god_id)
		var attention := GodManager.get_god_attention(god_id)

		var desc := "%s is %s." % [name, state]
		if attention >= GodManager.ATTENTION_OBSESSED:
			desc += " It is fixated on you."
		elif attention >= GodManager.ATTENTION_WATCHING:
			desc += " It is aware of you."
		elif attention >= GodManager.ATTENTION_NOTICED:
			desc += " It has noticed you."
		lines.append(desc)

	return " ".join(lines)


func _describe_current_zone() -> String:
	# Find current zone from region state
	var zones := GameState.region_state.keys()
	if zones.is_empty():
		return "I have nothing to say about this place."

	var worst_corruption := 0.0
	var worst_zone := ""
	for zone_id in zones:
		var region: Dictionary = GameState.get_region(zone_id)
		var corruption: float = region.get("corruption", 0.0)
		if corruption > worst_corruption:
			worst_corruption = corruption
			worst_zone = zone_id

	if worst_corruption >= 75.0:
		return "This region is deeply corrupted. The instability has taken root."
	elif worst_corruption >= 50.0:
		return "Corruption spreads here. The land remembers violence done to it."
	elif worst_corruption >= 25.0:
		return "There are signs of decay. Faint, but real."
	else:
		return "This place is stable. For now."


# --- Visual Identity Override ---
# The Keeper does NOT react to force changes visually.
# No glow, no pulse, no scale changes. Stability IS the visual cue.
# This is intentionally empty — the base class _on_force_changed is disconnected in _ready().

# --- Faction Override ---
# The Keeper has no faction. Can never be hostile.
func _is_faction_hostile() -> bool:
	return false


func _get_faction_id() -> String:
	return ""


# --- Persistence ---

func save_state() -> Dictionary:
	var base := super.save_state()
	base["is_keeper"] = true
	return base


func load_state(data: Dictionary) -> void:
	super.load_state(data)
