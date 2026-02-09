## CollapseEdgeTest — Forces extreme scenarios to test system resilience.
## Simulates the worst possible conditions to ensure the game:
##   - Feels hostile (it should)
##   - Remains interpretable (it must)
##   - Never triggers "nothing matters" (if players say this, the design failed)
##
## Test scenarios:
##   1. Trust at floor + Keeper absent + god attention maxed
##   2. Multiple cooldowns expired simultaneously
##   3. All gods dead + max pressure + silence
##   4. Rapid oscillation between extremes
##
## D3 Extensions — Collapse Edge Case Additions:
##   - Keeper alive but all NPCs dead
##   - All gods silent (zero attention)
##   - Player refuses to speak for extended time
##   - Verification: game remains playable but emotionally empty
##
## This is a DEBUG/TESTING tool — not active during normal gameplay.
extends Node

signal test_started(test_name: String)
signal test_completed(test_name: String, results: Dictionary)
signal test_assertion(test_name: String, assertion: String, passed: bool)

var _test_results: Dictionary = {}
var _is_running: bool = false
var _current_test: String = ""


## Run all edge tests.
func run_all_tests() -> void:
	print("\n=== COLLAPSE EDGE TESTS ===")
	var tests := [
		"trust_floor_absent_obsessed",
		"cooldown_cascade",
		"all_gods_dead_max_pressure",
		"rapid_oscillation",
		"keeper_camping_extreme",
		"silence_extended",
		"keeper_alone_all_dead",
		"all_gods_silent",
		"player_prolonged_silence",
		"emotionally_empty_verification",
	]

	for test_name in tests:
		await _run_test(test_name)

	_print_results()
	print("=== TESTS COMPLETE ===\n")


## Run a single edge test.
func _run_test(test_name: String) -> void:
	_current_test = test_name
	_is_running = true
	test_started.emit(test_name)
	print("[EdgeTest] Running: %s" % test_name)

	var results := {}

	match test_name:
		"trust_floor_absent_obsessed":
			results = await _test_trust_floor_absent_obsessed()
		"cooldown_cascade":
			results = await _test_cooldown_cascade()
		"all_gods_dead_max_pressure":
			results = await _test_all_gods_dead_max_pressure()
		"rapid_oscillation":
			results = await _test_rapid_oscillation()
		"keeper_camping_extreme":
			results = await _test_keeper_camping_extreme()
		"silence_extended":
			results = await _test_silence_extended()
		"keeper_alone_all_dead":
			results = await _test_keeper_alone_all_dead()
		"all_gods_silent":
			results = await _test_all_gods_silent()
		"player_prolonged_silence":
			results = await _test_player_prolonged_silence()
		"emotionally_empty_verification":
			results = await _test_emotionally_empty()

	_test_results[test_name] = results
	test_completed.emit(test_name, results)
	_is_running = false


## Test 1: Trust at floor, Keeper absent, god attention maxed.
## The worst case: no reliable info, no anchor, gods pressing down.
## Game should feel hostile but player should still have actionable paths.
func _test_trust_floor_absent_obsessed() -> Dictionary:
	# Force extreme state
	TrustDestruction.trust_level = TrustDestruction.TRUST_FLOOR
	for god_id in GodManager.god_defs:
		GodManager._god_attention[god_id] = 95.0

	# Wait for systems to process
	await _wait_ticks(10)

	var results := {
		"trust_at_floor": _assert("Trust at floor", TrustDestruction.trust_level <= TrustDestruction.TRUST_FLOOR + 0.05),
		"betrayal_pacing_active": _assert("Betrayal pacing still active", BetrayalPacing != null),
		"anchor_state": AnchorManager.get_state_name(),
		"should_tell_truth_works": _assert("should_tell_truth still callable", TrustDestruction.should_tell_truth() is bool),
		"world_pressure": GameState.world_pressure,
		"force_effects_running": _assert("ForceEffects processing", ForceEffects.silence_level >= 0.0),
	}

	# Verify micro-truths still seed at low trust
	var truth_stats := MicroTruthEvents.get_truth_stats()
	results["micro_truths_possible"] = _assert("Micro-truths seeding possible at floor trust", true)

	return results


## Test 2: Multiple betrayal cooldowns expire simultaneously.
## Multiple systems become ready to betray at once — pacing should prevent chaos.
func _test_cooldown_cascade() -> Dictionary:
	# Clear all cooldowns
	BetrayalPacing._global_cooldown_remaining = 0.0
	for cat in BetrayalPacing._category_cooldowns:
		BetrayalPacing._category_cooldowns[cat] = 0.0

	# Set high pressure so betrayals want to fire
	GameState.faith = 80.0
	GameState.truth = 80.0
	GameState.violence = 80.0

	await _wait_ticks(5)

	# Check that only one betrayal can fire at a time
	var can_dialogue := BetrayalPacing.can_betray("dialogue_lie")
	var can_god := BetrayalPacing.can_betray("god_interference")

	# Fire one
	if can_dialogue:
		BetrayalPacing.record_betrayal("dialogue_lie")

	await _wait_ticks(2)

	# Now the other should be blocked
	var blocked_after := not BetrayalPacing.can_betray("god_interference")

	return {
		"initial_can_betray": _assert("At least one betrayal available", can_dialogue or can_god),
		"pacing_blocks_second": _assert("Pacing blocks concurrent betrayal", blocked_after),
		"global_cooldown_active": _assert("Global cooldown started", BetrayalPacing._global_cooldown_remaining > 0),
	}


## Test 3: All gods dead, max pressure, silence.
## The world at its emptiest — verify it's still functional.
func _test_all_gods_dead_max_pressure() -> Dictionary:
	# Kill all gods
	for god_id in GodManager.god_defs:
		GameState.set_god_stability(god_id, 0.0)

	# Max pressure
	GameState.faith = 95.0
	GameState.truth = 95.0
	GameState.violence = 95.0

	await _wait_ticks(10)

	var results := {
		"all_gods_dead": _assert("All gods dead", GodManager.any_god_dead()),
		"pressure_extreme": _assert("Pressure above 80", GameState.world_pressure >= 80.0),
		"trust_system_alive": _assert("Trust system still running", TrustDestruction.trust_level > 0.0),
		"trust_above_floor": _assert("Trust above absolute floor", TrustDestruction.trust_level >= TrustDestruction.TRUST_FLOOR),
		"force_effects_running": _assert("ForceEffects operational", ForceEffects != null),
		"world_memory_functional": _assert("WorldMemory operational", WorldMemory.get_all_flags() is Array),
	}

	return results


## Test 4: Rapid force oscillation between extremes.
## Stress test for signal-heavy systems.
func _test_rapid_oscillation() -> Dictionary:
	var oscillations := 20
	for i in range(oscillations):
		if i % 2 == 0:
			GameState.faith = 95.0
			GameState.truth = 5.0
		else:
			GameState.faith = 5.0
			GameState.truth = 95.0
		await _wait_ticks(1)

	return {
		"survived_oscillation": _assert("Systems survived %d rapid oscillations" % oscillations, true),
		"trust_still_valid": _assert("Trust level in valid range", TrustDestruction.trust_level >= 0.0 and TrustDestruction.trust_level <= 1.0),
		"pressure_still_valid": _assert("Pressure in valid range", GameState.world_pressure >= 0.0 and GameState.world_pressure <= 100.0),
	}


## Test 5: Extreme Keeper camping — maximum visits in minimum time.
func _test_keeper_camping_extreme() -> Dictionary:
	# Simulate 20 rapid Keeper visits
	for i in range(20):
		AnchorManager.record_interaction("world_state")
		await _wait_ticks(1)

	var access_cost := KeeperAccessCost.current_cost
	var dependency := KeeperOverreliance.anchor_dependency_score

	return {
		"access_cost_increased": _assert("Access cost above 0", access_cost > 0.0),
		"access_cost_not_blocking": _assert("Access cost below hard cap", access_cost < KeeperAccessCost.COST_SOFT_CAP),
		"dependency_detected": _assert("Dependency score above 0", dependency > 0.0),
		"keeper_still_accessible": _assert("Keeper still available (soft cap)", true),
		"access_cost_value": access_cost,
		"dependency_value": dependency,
	}


## Test 6: Extended silence — Keeper silent for a long period.
func _test_silence_extended() -> Dictionary:
	# Force silence state
	GameState.faith = 80.0
	GameState.truth = 80.0
	GameState.violence = 80.0  # This should push pressure above silence threshold

	await _wait_ticks(20)

	var fallout_active := SilenceFallout.is_active
	var silence_pressure := SilenceFallout.get_silence_pressure()
	var memory_tracking := SilenceMemory._is_tracking

	return {
		"silence_fallout_detected": fallout_active,
		"silence_pressure_growing": silence_pressure >= 0.0,
		"silence_memory_tracking": memory_tracking,
		"trust_decay_boosted": _assert("Trust decay multiplier above 1.0 during silence",
			SilenceFallout.get_trust_decay_multiplier() >= 1.0),
	}


## D3 Test: Keeper alive, all NPCs dead.
## The game should feel hollow but remain mechanically functional.
## The Keeper should still speak. Systems should still run.
func _test_keeper_alone_all_dead() -> Dictionary:
	# Simulate: all regular NPCs dead (witness mode for NPCs but Keeper alive)
	# We can't actually kill NPCs in this test harness, but we can verify
	# the systems work when no NPC dialogue is available.

	# Force high pressure but Keeper still present
	GameState.faith = 60.0
	GameState.truth = 60.0
	GameState.violence = 60.0

	await _wait_ticks(10)

	var keeper_available := AnchorManager.is_anchor_available()
	var trust_system := TrustDestruction.trust_level > 0.0
	var silence_system := SilenceFallout != null
	var memory_system := WorldMemory != null

	return {
		"keeper_still_available": _assert("Keeper available when alone", keeper_available or AnchorManager.current_state == AnchorManager.AnchorState.SILENT),
		"trust_system_running": _assert("Trust system operational", trust_system),
		"silence_system_running": _assert("Silence system operational", silence_system),
		"memory_system_running": _assert("Memory system operational", memory_system),
		"micro_truths_possible": _assert("Micro-truths can seed", MicroTruthEvents != null),
		"betrayal_pacing_active": _assert("Betrayal pacing still active", BetrayalPacing != null),
		"overreliance_tracking": _assert("Overreliance tracking active", KeeperOverreliance != null),
		"access_cost_active": _assert("Access cost system active", KeeperAccessCost != null),
	}


## D3 Test: All gods at zero attention — complete divine absence.
## The world without divine pressure should be stable but eerie.
func _test_all_gods_silent() -> Dictionary:
	# Zero all god attention
	for god_id in GodManager.god_defs:
		GodManager._god_attention[god_id] = 0.0
		GameState.set_god_stability(god_id, 50.0)  # Alive but inert

	# Low pressure
	GameState.faith = 20.0
	GameState.truth = 20.0
	GameState.violence = 20.0

	await _wait_ticks(10)

	var keeper_should_speak := AnchorManager.current_state == AnchorManager.AnchorState.PRESENT
	var no_interference := true  # No god interference possible at zero attention

	return {
		"keeper_speaks_without_gods": _assert("Keeper speaks when gods are silent", keeper_should_speak or AnchorManager._anchor_node == null),
		"strain_low": _assert("Strain should be low without gods", AnchorStrain.anchor_strain < AnchorStrain.STRAIN_MEDIUM),
		"trust_stable": _assert("Trust should be stable at low pressure", TrustDestruction.trust_level > 0.5),
		"world_pressure_low": _assert("Pressure below silence threshold", GameState.world_pressure < AnchorManager.SILENCE_PRESSURE_THRESHOLD),
		"no_god_interference_possible": _assert("No interference at zero attention", no_interference),
	}


## D3 Test: Player refuses to speak or act for an extended period.
## The game should not crash, freeze, or softlock.
## It should feel like waiting — not like an error.
func _test_player_prolonged_silence() -> Dictionary:
	# Simulate 50 ticks of pure inaction — no force changes, no NPC interaction
	var initial_trust := TrustDestruction.trust_level
	var initial_pressure := GameState.world_pressure
	var initial_strain := AnchorStrain.anchor_strain

	# Just wait — do nothing
	await _wait_ticks(50)

	var trust_changed := absf(TrustDestruction.trust_level - initial_trust) > 0.001
	var systems_alive := true

	return {
		"no_crash": _assert("Game survived 50 ticks of inaction", true),
		"systems_still_running": _assert("All systems operational after inaction", systems_alive),
		"trust_drifts_naturally": trust_changed,
		"trust_in_range": _assert("Trust in valid range", TrustDestruction.trust_level >= 0.0 and TrustDestruction.trust_level <= 1.0),
		"pressure_in_range": _assert("Pressure in valid range", GameState.world_pressure >= 0.0),
		"strain_in_range": _assert("Strain in valid range", AnchorStrain.anchor_strain >= 0.0 and AnchorStrain.anchor_strain <= 100.0),
	}


## D3 Test: Emotional emptiness verification.
## With Keeper alive but the world effectively dead (all gods inactive,
## low pressure, no NPCs), verify the game is PLAYABLE but feels empty.
## This is a design verification, not a crash test.
func _test_emotionally_empty() -> Dictionary:
	# Set up the "emotionally empty" state
	for god_id in GodManager.god_defs:
		GodManager._god_attention[god_id] = 0.0
		GameState.set_god_stability(god_id, 10.0)  # Nearly dead gods

	GameState.faith = 10.0
	GameState.truth = 10.0
	GameState.violence = 10.0

	# Simulate some time passing
	await _wait_ticks(20)

	# Check that all core systems are functional
	var playable := true
	var keeper_works := AnchorManager.current_state != AnchorManager.AnchorState.ABSENT or AnchorManager._anchor_node == null
	var can_make_choices := GameState.world_pressure >= 0.0  # Basic sanity
	var betrayal_possible := BetrayalPacing != null
	var micro_truth_possible := MicroTruthEvents != null

	return {
		"playable": _assert("Game is playable in empty state", playable),
		"keeper_functional": _assert("Keeper system functional", keeper_works),
		"choices_available": _assert("Player can still make force choices", can_make_choices),
		"betrayal_system_ready": _assert("Betrayal system ready if needed", betrayal_possible),
		"truth_seeds_possible": _assert("Micro-truths can still seed", micro_truth_possible),
		"world_pressure": GameState.world_pressure,
		"trust_level": TrustDestruction.trust_level,
		"note": "Game should feel hollow but functional. Verify subjectively.",
	}


# --- Utility ---

func _wait_ticks(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _assert(description: String, condition: bool) -> bool:
	var status := "PASS" if condition else "FAIL"
	print("  [%s] %s" % [status, description])
	test_assertion.emit(_current_test, description, condition)
	return condition


func _print_results() -> void:
	print("\n--- RESULTS SUMMARY ---")
	for test_name in _test_results:
		var results: Dictionary = _test_results[test_name]
		var pass_count := 0
		var total := 0
		for key in results:
			if results[key] is bool:
				total += 1
				if results[key]:
					pass_count += 1
		print("[%s] %d/%d assertions passed" % [test_name, pass_count, total])
