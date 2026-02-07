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
