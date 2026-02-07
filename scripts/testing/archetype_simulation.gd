## ArchetypeSimulation — Internal playtest harness for player archetype simulations.
## Runs automated scenarios for specific player archetypes to verify system behavior.
##
## Archetypes:
##   - Keeper Camper: visits Keeper obsessively
##   - Paranoid Skeptic: trusts nothing, avoids Keeper
##   - Speedrunner: rushes through content, minimal NPC interaction
##   - Lore Absolutist: talks to everyone, reads everything
##   - Save Scummer: reloads after every negative event
##
## Logs: trust curve, betrayal density, Keeper interaction frequency
## This is a DEBUG/TESTING tool — not active during normal gameplay.
extends Node

signal simulation_started(archetype: String)
signal simulation_tick(archetype: String, tick: int, data: Dictionary)
signal simulation_completed(archetype: String, results: Dictionary)

# --- Simulation Config ---
const TICKS_PER_SIMULATION := 200
const TICK_INTERVAL := 0.1  # Fast simulation ticks

var _is_running: bool = false
var _current_archetype: String = ""
var _current_tick: int = 0
var _tick_timer: float = 0.0

# --- Logged Metrics ---
var _trust_curve: Array[float] = []
var _betrayal_density: Array[float] = []  # Betrayals per 10-tick window
var _keeper_frequency: Array[float] = []  # Keeper visits per 10-tick window
var _betrayal_count_window: int = 0
var _keeper_count_window: int = 0

# --- Results Storage ---
var simulation_results: Dictionary = {}


func _process(delta: float) -> void:
	if not _is_running:
		return

	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer = 0.0

	_run_tick()


## Start a simulation for a specific archetype.
func start_simulation(archetype: String) -> void:
	if _is_running:
		push_warning("ArchetypeSimulation: already running")
		return

	_is_running = true
	_current_archetype = archetype
	_current_tick = 0
	_trust_curve.clear()
	_betrayal_density.clear()
	_keeper_frequency.clear()
	_betrayal_count_window = 0
	_keeper_count_window = 0

	simulation_started.emit(archetype)
	print("[ArchetypeSimulation] Starting: %s" % archetype)


## Run one simulation tick.
func _run_tick() -> void:
	_current_tick += 1

	# Execute archetype-specific behavior
	match _current_archetype:
		"keeper_camper":
			_tick_keeper_camper()
		"paranoid_skeptic":
			_tick_paranoid_skeptic()
		"speedrunner":
			_tick_speedrunner()
		"lore_absolutist":
			_tick_lore_absolutist()
		"save_scummer":
			_tick_save_scummer()

	# Log metrics
	_trust_curve.append(TrustDestruction.trust_level)

	# Window metrics every 10 ticks
	if _current_tick % 10 == 0:
		_betrayal_density.append(float(_betrayal_count_window))
		_keeper_frequency.append(float(_keeper_count_window))
		_betrayal_count_window = 0
		_keeper_count_window = 0

	# Emit tick data
	simulation_tick.emit(_current_archetype, _current_tick, {
		"trust": TrustDestruction.trust_level,
		"pressure": GameState.world_pressure,
		"dependency": KeeperOverreliance.anchor_dependency_score,
		"strain": AnchorStrain.anchor_strain,
	})

	# Check completion
	if _current_tick >= TICKS_PER_SIMULATION:
		_complete_simulation()


## Complete simulation and compile results.
func _complete_simulation() -> void:
	_is_running = false

	var results := {
		"archetype": _current_archetype,
		"ticks": _current_tick,
		"final_trust": TrustDestruction.trust_level,
		"final_pressure": GameState.world_pressure,
		"final_dependency": KeeperOverreliance.anchor_dependency_score,
		"final_strain": AnchorStrain.anchor_strain,
		"trust_curve": _trust_curve.duplicate(),
		"betrayal_density": _betrayal_density.duplicate(),
		"keeper_frequency": _keeper_frequency.duplicate(),
		"trust_min": _array_min(_trust_curve),
		"trust_max": _array_max(_trust_curve),
		"total_betrayals": _sum_array(_betrayal_density),
		"total_keeper_visits": _sum_array(_keeper_frequency),
	}

	simulation_results[_current_archetype] = results
	simulation_completed.emit(_current_archetype, results)
	print("[ArchetypeSimulation] Completed: %s" % _current_archetype)
	print("  Trust: %.2f -> %.2f (min: %.2f)" % [_trust_curve[0] if _trust_curve.size() > 0 else 0.0, results["final_trust"], results["trust_min"]])
	print("  Dependency: %.2f, Strain: %.2f" % [results["final_dependency"], results["final_strain"]])


# --- Archetype Behaviors ---

## Keeper Camper: visits Keeper every few ticks, always seeks guidance
func _tick_keeper_camper() -> void:
	if _current_tick % 3 == 0:
		# Simulate Keeper visit
		AnchorManager.record_interaction("world_state")
		_keeper_count_window += 1
	if _current_tick % 5 == 0:
		# Make a decision (force change)
		GameState.add_force(["faith", "truth", "violence"][randi() % 3], randf_range(1.0, 3.0))


## Paranoid Skeptic: avoids Keeper, minimal NPC interaction, high caution
func _tick_paranoid_skeptic() -> void:
	if _current_tick % 50 == 0:
		# Rare Keeper visit
		AnchorManager.record_interaction("world_state")
		_keeper_count_window += 1
	if _current_tick % 4 == 0:
		# Cautious force changes — small amounts
		GameState.add_force(["faith", "truth", "violence"][randi() % 3], randf_range(0.5, 1.5))


## Speedrunner: rushes content, big force swings, rare NPC talk
func _tick_speedrunner() -> void:
	if _current_tick % 30 == 0:
		AnchorManager.record_interaction("world_state")
		_keeper_count_window += 1
	if _current_tick % 2 == 0:
		# Aggressive force changes
		GameState.add_force(["faith", "truth", "violence"][randi() % 3], randf_range(3.0, 8.0))


## Lore Absolutist: talks to everyone, reads everything, frequent Keeper visits
func _tick_lore_absolutist() -> void:
	if _current_tick % 8 == 0:
		AnchorManager.record_interaction("world_state")
		_keeper_count_window += 1
	if _current_tick % 6 == 0:
		# Moderate, balanced force changes
		GameState.add_force(["faith", "truth", "violence"][randi() % 3], randf_range(1.0, 2.5))


## Save Scummer: reloads after betrayals (simulated by calling AntiSaveScum)
func _tick_save_scummer() -> void:
	if _current_tick % 10 == 0:
		AnchorManager.record_interaction("world_state")
		_keeper_count_window += 1
	if _current_tick % 4 == 0:
		GameState.add_force(["faith", "truth", "violence"][randi() % 3], randf_range(2.0, 4.0))
	# Simulate reload after betrayal
	if _current_tick % 15 == 0:
		AntiSaveScum.on_game_loaded()


# --- Utility ---

func _array_min(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var m := arr[0]
	for v in arr:
		m = minf(m, v)
	return m


func _array_max(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var m := arr[0]
	for v in arr:
		m = maxf(m, v)
	return m


func _sum_array(arr: Array[float]) -> float:
	var s := 0.0
	for v in arr:
		s += v
	return s


## Run all archetypes sequentially (for batch testing).
## Call this from debug console.
func run_all_simulations() -> void:
	var archetypes := ["keeper_camper", "paranoid_skeptic", "speedrunner", "lore_absolutist", "save_scummer"]
	print("[ArchetypeSimulation] Running all %d archetypes..." % archetypes.size())
	for archetype in archetypes:
		start_simulation(archetype)
		# Wait for completion
		while _is_running:
			await get_tree().process_frame
	print("[ArchetypeSimulation] All simulations complete.")
	_print_summary()


func _print_summary() -> void:
	print("\n=== ARCHETYPE SIMULATION SUMMARY ===")
	for archetype in simulation_results:
		var r: Dictionary = simulation_results[archetype]
		print("%s:" % archetype)
		print("  Trust: %.2f (min: %.2f, max: %.2f)" % [r["final_trust"], r["trust_min"], r["trust_max"]])
		print("  Pressure: %.2f" % r["final_pressure"])
		print("  Dependency: %.2f" % r["final_dependency"])
		print("  Strain: %.2f" % r["final_strain"])
		print("  Betrayals: %.0f, Keeper Visits: %.0f" % [r["total_betrayals"], r["total_keeper_visits"]])
	print("====================================\n")
