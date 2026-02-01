## GodPersonality — Phase I: Gods as Threats.
## I1: God Personality Matrices (obsessions, punishments, lies, unforgiveables, secret admiration)
## I2: Non-Combat God Pressure (fake UI, dialogue rewriting, environmental edits, NPC misquotes)
## I3: God-on-God Interference (sabotage, conflicting cues, lies canceling truths)
extends Node

# --- I1: God Personality Matrices ---

var god_personalities: Dictionary = {}

signal god_pressure_event(god_id: String, pressure_type: String, data: Dictionary)
signal god_interference(aggressor_id: String, victim_id: String, interference_type: String)
signal dialogue_rewritten(original: String, rewritten: String, god_id: String)
signal fake_quest_update(quest_title: String, fake_text: String, god_id: String)

var _pressure_timer: float = 0.0
const PRESSURE_CHECK_INTERVAL := 8.0

var _interference_timer: float = 0.0
const INTERFERENCE_CHECK_INTERVAL := 12.0


func _ready() -> void:
	_define_personalities()
	GodManager.god_attention_threshold.connect(_on_attention_threshold)


func _define_personalities() -> void:
	# --- VERATH, THE ASH MOTHER ---
	god_personalities["verath"] = {
		"obsession_triggers": [
			"player_heals_too_often",       # She notices you fighting her cycle
			"player_avoids_death_zones",     # Cowardice offends her
			"high_faith_sustained",          # Devotion feeds her hunger
		],
		"preferred_punishments": [
			"health_oscillation",            # Health flickers between values
			"forced_healing",                # Heals you when you don't want it (with cost)
			"corpse_highlighting",           # Dead enemies glow, drawing attention
		],
		"favorite_lies": [
			"This wound will heal on its own.",
			"The ash is nourishing.",
			"Death here is temporary. It always was.",
			"She loves you. That's why it hurts.",
		],
		"never_forgives": "abandoning_a_prayer_mid_ritual",
		"secretly_admires": "choosing_to_die_rather_than_submit",
		"dialogue_rewrites": {
			"help": "accept what comes",
			"save": "release",
			"protect": "recycle",
			"alive": "waiting to return",
			"dead": "composting",
		},
		"npc_misquotes": [
			"The Ash Mother said: 'Let go.' ...I think those were her words.",
			"Verath whispers that everything returns. But she never said it would return as you.",
			"I heard her say: 'You are beloved.' But the word she used was closer to 'consumed.'",
		],
	}

	# --- KAEL, THE BLIND SUN ---
	god_personalities["kael"] = {
		"obsession_triggers": [
			"player_lies_in_dialogue",       # He sees deception
			"player_avoids_truth_shrines",   # Willful ignorance
			"high_truth_sustained",          # He watches those who seek too hard
		],
		"preferred_punishments": [
			"forced_revelation",             # UI shows hidden info you don't want
			"truth_about_npcs",              # Reveals NPC lies/secrets in real-time
			"judgment_flash",                # Brief blinding light — screen whiteout
		],
		"favorite_lies": [
			"You wanted to know. This is what knowing costs.",
			"The light does not judge. It only shows.",
			"Every secret you found was one I allowed.",
			"Blindness was not my punishment. It was my gift to myself.",
		],
		"never_forgives": "destroying_knowledge_or_truth_artifacts",
		"secretly_admires": "acknowledging_an_uncomfortable_truth_in_dialogue",
		"dialogue_rewrites": {
			"believe": "verify",
			"trust": "inspect",
			"faith": "hypothesis",
			"hope": "expectation",
			"pray": "report",
		},
		"npc_misquotes": [
			"Kael said: 'See clearly.' But I'm not sure he meant with eyes.",
			"The Blind Sun doesn't judge? Then why do I feel measured?",
			"He told me: 'The truth will free you.' He didn't say you'd want to be free.",
		],
	}

	# --- THE NULL THRONE ---
	god_personalities["null_throne"] = {
		"obsession_triggers": [
			"player_spends_time_alone",      # Isolation feeds it
			"player_ignores_all_gods",       # Neglect is its language
			"low_total_force",               # Emptiness attracts emptiness
		],
		"preferred_punishments": [
			"ui_element_erasure",            # HUD components vanish
			"sound_subtraction",             # Sounds drop out one by one
			"memory_erasure",                # WorldMemory flags quietly removed
		],
		"favorite_lies": [
			"",                              # The Null Throne's favorite lie is silence itself
			"Nothing was here. Nothing was ever here.",
			"You remember something. But you don't. You never did.",
			"The throne is empty. You checked. You always check.",
		],
		"never_forgives": "filling_the_void_with_devotion_to_another_god",
		"secretly_admires": "choosing_to_sit_with_emptiness_without_filling_it",
		"dialogue_rewrites": {
			"someone": "no one",
			"here": "nowhere",
			"remember": "forget",
			"name": "absence",
			"voice": "silence",
		},
		"npc_misquotes": [
			"The Null Throne said... actually, I don't remember what it said.",
			"I felt something from the Throne. Like a word being un-said.",
			"It doesn't speak. But sometimes words just... aren't there anymore.",
		],
	}


func _process(delta: float) -> void:
	_pressure_timer += delta
	if _pressure_timer >= PRESSURE_CHECK_INTERVAL:
		_pressure_timer = 0.0
		_check_non_combat_pressure()

	_interference_timer += delta
	if _interference_timer >= INTERFERENCE_CHECK_INTERVAL:
		_interference_timer = 0.0
		_check_god_on_god_interference()


# --- I2: Non-Combat God Pressure ---

func _check_non_combat_pressure() -> void:
	for god_id in god_personalities:
		var attention := GodManager.get_god_attention(god_id)
		if attention < GodManager.ATTENTION_WATCHING:
			continue
		if GodManager.get_god_state(god_id) == "dead":
			continue

		var gate := GodManager.get_phase_gate(0.0, 0.4, 1.0)
		if gate <= 0.0:
			continue

		# Non-combat pressure scales with attention
		var pressure_chance := 0.15 * (attention / 100.0) * gate

		if randf() < pressure_chance:
			_apply_non_combat_pressure(god_id)


func _apply_non_combat_pressure(god_id: String) -> void:
	var personality: Dictionary = god_personalities.get(god_id, {})
	var effect := randi() % 4

	match effect:
		0:
			# Fake quest update — UI shows a quest objective that doesn't exist
			_generate_fake_quest_update(god_id, personality)
		1:
			# Dialogue rewriting — next dialogue will have words replaced
			_prepare_dialogue_rewrite(god_id, personality)
		2:
			# Environmental edit that persists across saves
			_apply_environmental_edit(god_id)
		3:
			# NPC misquoting the god
			_trigger_npc_misquote(god_id, personality)


func _generate_fake_quest_update(god_id: String, personality: Dictionary) -> void:
	var fake_titles := {
		"verath": ["Return to Ash", "The Cycle Demands", "Accept the Composting"],
		"kael": ["See What You Hid", "Report for Judgment", "The Light Knows"],
		"null_throne": ["", "Forget", "The Task That Was Never Assigned"],
	}
	var fake_texts := {
		"verath": [
			"Objective: Stop resisting.",
			"Objective: Let the wound close on its own terms.",
			"Objective updated: You already completed this. You just don't accept it.",
		],
		"kael": [
			"Objective: Acknowledge what you saw in the ruins.",
			"Objective: The truth about the Ash Walker has been recorded. Review it.",
			"Objective updated: You lied. Kael noticed. Proceed honestly.",
		],
		"null_throne": [
			"Objective: .",
			"Objective: [This quest was never given to you.]",
			"Objective updated:                          ",
		],
	}

	var titles: Array = fake_titles.get(god_id, ["???"])
	var texts: Array = fake_texts.get(god_id, ["..."])
	var title: String = titles[randi() % titles.size()]
	var text: String = texts[randi() % texts.size()]

	fake_quest_update.emit(title, text, god_id)
	god_pressure_event.emit(god_id, "fake_quest", {"title": title, "text": text})
	WorldMemory.record("god_fake_quest_%s" % god_id)

	# Brief notification that looks like a real quest update
	WorldEventManager.event_notification.emit("Quest: %s" % title, text)


func _prepare_dialogue_rewrite(god_id: String, personality: Dictionary) -> void:
	# Store rewrite rules — DialogueManager will check these
	var rewrites: Dictionary = personality.get("dialogue_rewrites", {})
	if rewrites.size() > 0:
		god_pressure_event.emit(god_id, "dialogue_rewrite_prepared", rewrites)
		WorldMemory.record("god_dialogue_rewrite_%s" % god_id)


func _apply_environmental_edit(god_id: String) -> void:
	# Permanent world change — persists across saves
	match god_id:
		"verath":
			# Something grows where nothing should
			WorldMemory.record("env_edit_verath_growth_%d" % (randi() % 100))
			WorldEventManager.event_notification.emit(
				"", "Something sprouted from the corpse pile. It shouldn't be able to grow in ash.")
		"kael":
			# Hidden information becomes visible
			WorldMemory.record("env_edit_kael_reveal_%d" % (randi() % 100))
			WorldEventManager.event_notification.emit(
				"", "Text appeared on the wall. It wasn't there before. It reads: 'I saw what you did.'")
		"null_throne":
			# Something that existed is now missing
			WorldMemory.record("env_edit_null_erasure_%d" % (randi() % 100))
			WorldEventManager.event_notification.emit(
				"", "Something is missing. You can't remember what was here. But the space is wrong.")
	god_pressure_event.emit(god_id, "environmental_edit", {})


func _trigger_npc_misquote(god_id: String, personality: Dictionary) -> void:
	var misquotes: Array = personality.get("npc_misquotes", [])
	if misquotes.size() == 0:
		return

	var quote: String = misquotes[randi() % misquotes.size()]
	god_pressure_event.emit(god_id, "npc_misquote", {"quote": quote})
	WorldEventManager.event_notification.emit(
		"Overheard", quote)
	WorldMemory.record_ambient("NPC misquoted %s: %s" % [
		GodManager.get_god_name(god_id), quote])


# --- I2: Dialogue Rewriting System ---
# When a god is watching+, some words in dialogue get replaced mid-conversation.

## Rewrite a dialogue line based on active god pressure.
## Called by DialogueManager before displaying text.
func rewrite_dialogue_line(text: String) -> String:
	var rewritten := text
	var any_rewrite := false

	for god_id in god_personalities:
		var attention := GodManager.get_god_attention(god_id)
		if attention < GodManager.ATTENTION_WATCHING:
			continue
		if GodManager.get_god_state(god_id) == "dead":
			continue

		var personality: Dictionary = god_personalities[god_id]
		var rewrites: Dictionary = personality.get("dialogue_rewrites", {})

		# Only rewrite with a probability — not every line
		if randf() > 0.3:
			continue

		for original_word in rewrites:
			var replacement: String = rewrites[original_word]
			if rewritten.containsn(original_word):
				rewritten = rewritten.replacen(original_word, replacement)
				any_rewrite = true
				break  # One rewrite per god per line

	if any_rewrite and rewritten != text:
		dialogue_rewritten.emit(text, rewritten, "")
	return rewritten


# --- I3: God-on-God Interference ---
# When two gods are both active (attention >= noticed), they sabotage each other.

func _check_god_on_god_interference() -> void:
	var active_gods: Array = []
	for god_id in GodManager.god_defs:
		if GodManager.get_god_attention(god_id) >= GodManager.ATTENTION_NOTICED:
			if GodManager.get_god_state(god_id) != "dead":
				active_gods.append(god_id)

	if active_gods.size() < 2:
		return

	var gate := GodManager.get_phase_gate(0.0, 0.3, 1.0)
	if gate <= 0.0:
		return

	if randf() > 0.25 * gate:
		return

	# Pick two active gods
	var god_a: String = active_gods[randi() % active_gods.size()]
	var god_b: String = active_gods[randi() % active_gods.size()]
	while god_b == god_a and active_gods.size() > 1:
		god_b = active_gods[randi() % active_gods.size()]

	if god_a == god_b:
		return

	var interference_type := randi() % 3
	var god_a_name := GodManager.get_god_name(god_a)
	var god_b_name := GodManager.get_god_name(god_b)

	match interference_type:
		0:
			# Signal sabotage — one god corrupts the other's notifications
			WorldEventManager.event_notification.emit(
				god_a_name,
				"[This message was not from %s. %s intercepted it.]" % [god_a_name, god_b_name])
			god_interference.emit(god_b, god_a, "signal_sabotage")
			WorldMemory.record_ambient("%s sabotaged %s's signal" % [god_b_name, god_a_name])

		1:
			# Conflicting force cues — gods push forces in opposite directions
			var forces := ["faith", "truth", "violence"]
			var target_force: String = forces[randi() % forces.size()]
			GameState.add_force(target_force, randf_range(-3.0, 3.0))
			WorldEventManager.event_notification.emit(
				"???",
				"The forces shift erratically. %s and %s cannot agree on what should happen to you." % [
					god_a_name, god_b_name])
			god_interference.emit(god_a, god_b, "conflicting_cues")

		2:
			# Lies cancel truths — truth-based information becomes unreliable
			if god_a == "kael" or god_b == "kael":
				# Kael's truths get inverted
				WorldEventManager.event_notification.emit(
					"THE BLIND SUN",
					"Kael showed you something. But %s twisted it. What you saw was the opposite of true." % [
						god_a_name if god_a != "kael" else god_b_name])
			else:
				# Meaning inverts
				WorldEventManager.event_notification.emit(
					"???",
					"Two divine voices overlap. The meaning cancels. You heard everything and understood nothing.")
			god_interference.emit(god_a, god_b, "meaning_inversion")

	WorldMemory.record("god_interference_%s_%s" % [god_a, god_b])


## Get a god's favorite lie for use in environmental storytelling.
func get_god_lie(god_id: String) -> String:
	var personality: Dictionary = god_personalities.get(god_id, {})
	var lies: Array = personality.get("favorite_lies", [])
	if lies.size() == 0:
		return "..."
	return lies[randi() % lies.size()]


## Check if a god would forgive a specific action.
func would_god_forgive(god_id: String, action: String) -> bool:
	var personality: Dictionary = god_personalities.get(god_id, {})
	return action != personality.get("never_forgives", "")


## Check if a god secretly admires an action.
func does_god_admire(god_id: String, action: String) -> bool:
	var personality: Dictionary = god_personalities.get(god_id, {})
	return action == personality.get("secretly_admires", "")


func _on_attention_threshold(god_id: String, level: String) -> void:
	if level == "obsessed":
		var personality: Dictionary = god_personalities.get(god_id, {})
		var lies: Array = personality.get("favorite_lies", [])
		if lies.size() > 0:
			var lie: String = lies[randi() % lies.size()]
			if lie != "":
				WorldEventManager.event_notification.emit(
					GodManager.get_god_name(god_id), lie)
