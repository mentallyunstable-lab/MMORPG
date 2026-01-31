## AshfallBorderland — Zone controller for the first vertical slice.
## Manages environmental changes, force-reactive candles/machines, and escalation.
## Attached to the zone root node.
extends Node3D

# --- Environmental Reactivity ---
# Candles relight when faith rises. Machines fail when faith dominates.
# Silence pockets form near god encounter areas.

var _env_tick_timer: float = 0.0
const ENV_TICK_INTERVAL := 3.0

# Track escalation within this zone
var _entered_mid_phase: bool = false

# Node references (populated in _ready)
var _candle_lights: Array[Node] = []
var _machine_sparks: Array[Node] = []


func _ready() -> void:
	# Register this zone in GameState
	GameState.get_region("ashfall_borderland")
	GameState.set_region_value("ashfall_borderland", "visited", true)

	# Find environmental props
	_candle_lights = _find_nodes_in_group("zone_candles")
	_machine_sparks = _find_nodes_in_group("zone_machines")

	# Connect to phase changes for escalation jump
	GodManager.phase_changed.connect(_on_phase_changed)
	ForceEffects.atmosphere_changed.connect(_on_atmosphere_changed)


func _process(delta: float) -> void:
	_env_tick_timer += delta
	if _env_tick_timer < ENV_TICK_INTERVAL:
		return
	_env_tick_timer = 0.0

	_update_zone_reactivity()


## Environmental reactivity — candles, machines, silence pockets.
func _update_zone_reactivity() -> void:
	var faith_t := GameState.faith / 100.0
	var truth_t := GameState.truth / 100.0
	var violence_t := GameState.violence / 100.0

	# Candles relight with faith — go dark with truth
	for candle in _candle_lights:
		if not is_instance_valid(candle):
			continue
		if candle is Light3D:
			if faith_t > 0.4:
				candle.visible = true
				candle.light_energy = lerpf(0.2, 1.5, faith_t)
			elif truth_t > 0.6:
				candle.visible = false
			else:
				candle.visible = faith_t > 0.2
				candle.light_energy = 0.5

	# Machines spark and hum with truth — go silent with faith
	for machine in _machine_sparks:
		if not is_instance_valid(machine):
			continue
		if machine is GPUParticles3D:
			if truth_t > 0.4:
				machine.emitting = true
				machine.speed_scale = lerpf(0.5, 2.0, truth_t)
			elif faith_t > 0.6:
				machine.emitting = false
			else:
				machine.emitting = truth_t > 0.2

	# Zone corruption rises with violence
	if violence_t > 0.5:
		var region := GameState.get_region("ashfall_borderland")
		var corruption: float = region.get("corruption", 0.0)
		region["corruption"] = minf(corruption + violence_t * 0.3, 100.0)


## Handle escalation jump — EARLY → MID phase triggers zone event.
func _on_phase_changed(new_phase: int) -> void:
	if new_phase == GodManager.GamePhase.MID and not _entered_mid_phase:
		_entered_mid_phase = true
		_trigger_escalation_jump()


func _trigger_escalation_jump() -> void:
	# The world reacts to rising pressure — one-time zone event
	WorldEventManager.event_notification.emit(
		"Ashfall Borderland",
		"The ground trembles. The ash thickens. Something in this zone has shifted.")

	# Enemies in the zone get more aggressive
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and "detection_range" in enemy:
			enemy.detection_range *= 1.3
			enemy.chase_speed *= 1.15

	# Force a brief silence moment — the world holding its breath
	ForceEffects.trigger_silence(3.0, 0.5)

	# Record in memory
	WorldMemory.record("ashfall_borderland_escalation")
	WorldMemory.record_ambient("The borderland shifted to a higher tension")


## Atmosphere shifts affect the zone environment directly.
func _on_atmosphere_changed(silence: float, decay: float) -> void:
	# Could drive ambient sound/particles — for now, visual only
	pass


func _find_nodes_in_group(group_name: String) -> Array[Node]:
	var result: Array[Node] = []
	for child in get_tree().get_nodes_in_group(group_name):
		if is_ancestor_of(child) or child == self:
			result.append(child)
	return result


func _exit_tree() -> void:
	if GodManager and GodManager.phase_changed.is_connected(_on_phase_changed):
		GodManager.phase_changed.disconnect(_on_phase_changed)
	if ForceEffects and ForceEffects.atmosphere_changed.is_connected(_on_atmosphere_changed):
		ForceEffects.atmosphere_changed.disconnect(_on_atmosphere_changed)
