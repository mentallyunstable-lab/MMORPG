## ForceEffects — Processes world-wide consequences of Faith/Truth/Violence levels.
## Attached to the scene tree via autoload. Runs every tick, applying force effects.
## DO NOT WRITE INTO OTHER SINGLETONS DIRECTLY — use controlled APIs (add_force, set_god_stability, etc.)
extends Node

# --- Thresholds ---
const LOW_THRESHOLD := 20.0
const MID_THRESHOLD := 50.0
const HIGH_THRESHOLD := 70.0
const CRITICAL_THRESHOLD := 90.0

# --- Tick rate ---
const EFFECT_INTERVAL := 2.0  # seconds between effect ticks
var _timer: float = 0.0

# --- Cached dominant force (updated on change) ---
var dominant_force: String = ""
var force_tier: String = "none"  # "none", "low", "mid", "high", "critical"

# Minimum time between tier change signals to prevent oscillation spam
const TIER_CHANGE_COOLDOWN := 3.0
var _tier_cooldown: float = 0.0

signal force_tier_changed(force_name: String, tier: String)
signal world_effect_triggered(effect_id: String, data: Dictionary)

# Atmospheric callout cooldown — one callout per 15s max
const CALLOUT_COOLDOWN := 15.0
var _callout_timer: float = 0.0


func _ready() -> void:
	GameState.force_changed.connect(_on_force_changed)
	_recalculate()


func _process(delta: float) -> void:
	_timer += delta
	if _tier_cooldown > 0:
		_tier_cooldown -= delta
	if _callout_timer > 0:
		_callout_timer -= delta
	if _timer >= EFFECT_INTERVAL:
		_timer = 0.0
		_apply_passive_effects()
		_check_atmospheric_callouts()


func _on_force_changed(_force_name: String, _old: float, _new: float) -> void:
	_recalculate()


func _recalculate() -> void:
	var old_dominant := dominant_force
	dominant_force = GameState.get_dominant_force()

	var dom_value := GameState.get_force(dominant_force)
	var old_tier := force_tier

	if dom_value >= CRITICAL_THRESHOLD:
		force_tier = "critical"
	elif dom_value >= HIGH_THRESHOLD:
		force_tier = "high"
	elif dom_value >= MID_THRESHOLD:
		force_tier = "mid"
	elif dom_value >= LOW_THRESHOLD:
		force_tier = "low"
	else:
		force_tier = "none"

	if (old_tier != force_tier or old_dominant != dominant_force) and _tier_cooldown <= 0:
		_tier_cooldown = TIER_CHANGE_COOLDOWN
		force_tier_changed.emit(dominant_force, force_tier)


## Apply passive world effects based on current force levels.
## Called every EFFECT_INTERVAL seconds.
func _apply_passive_effects() -> void:
	# --- Faith effects ---
	if GameState.faith >= HIGH_THRESHOLD:
		# High faith slowly restores god stability
		for god_name in GameState.god_stability:
			var current: float = GameState.god_stability[god_name]
			GameState.set_god_stability(god_name, current + 0.5)
		# High faith slowly reduces violence
		if GameState.violence > 0:
			GameState.add_force("violence", -0.1)

	if GameState.faith >= CRITICAL_THRESHOLD:
		# Critical faith — miracles manifest, tech degrades
		world_effect_triggered.emit("miracle_pulse", {"intensity": GameState.faith / 100.0})

	# --- Truth effects ---
	if GameState.truth >= HIGH_THRESHOLD:
		# High truth slowly erodes god stability
		for god_name in GameState.god_stability:
			var current: float = GameState.god_stability[god_name]
			GameState.set_god_stability(god_name, current - 0.8)
		# High truth slowly reduces faith
		if GameState.faith > 0:
			GameState.add_force("faith", -0.15)

	if GameState.truth >= CRITICAL_THRESHOLD:
		# Critical truth — reality glitches
		world_effect_triggered.emit("reality_glitch", {"intensity": GameState.truth / 100.0})

	# --- Violence effects ---
	if GameState.violence >= HIGH_THRESHOLD:
		# High violence destabilizes all regions
		for zone_id in GameState.region_state:
			var region: Dictionary = GameState.get_region(zone_id)
			region["corruption"] = minf(region.get("corruption", 0.0) + 0.5, 100.0)

	if GameState.violence >= CRITICAL_THRESHOLD:
		# Critical violence — world destabilizes fast, factions hostile
		world_effect_triggered.emit("world_destabilize", {"intensity": GameState.violence / 100.0})
		for faction in GameState.factions:
			GameState.change_faction_reputation(faction, -0.3)

	# --- Pressure effects (combined) ---
	if GameState.world_pressure >= 80.0:
		# Extreme combined pressure — everything reacts
		world_effect_triggered.emit("pressure_overload", {"pressure": GameState.world_pressure})


## Atmospheric world reaction callouts — so the player understands what's happening.
func _check_atmospheric_callouts() -> void:
	if _callout_timer > 0:
		return

	var callout := ""
	if GameState.faith >= CRITICAL_THRESHOLD:
		callout = "The air hums with devotion. The gods stir."
	elif GameState.truth >= CRITICAL_THRESHOLD:
		callout = "Reality fractures slightly. Nothing is hidden."
	elif GameState.violence >= CRITICAL_THRESHOLD:
		callout = "The ground shakes. Blood calls to blood."
	elif GameState.world_pressure >= 80.0:
		callout = "The world groans under the weight of all three forces."
	elif GameState.faith >= HIGH_THRESHOLD:
		callout = "The air feels heavier... prayers linger."
	elif GameState.truth >= HIGH_THRESHOLD:
		callout = "Shadows sharpen. Details emerge unbidden."
	elif GameState.violence >= HIGH_THRESHOLD:
		callout = "Something feral stirs at the edge of hearing."

	if callout != "":
		_callout_timer = CALLOUT_COOLDOWN
		WorldEventManager.event_notification.emit("World", callout)


## Query: is a specific force dominant and above a threshold?
func is_force_dominant_at(force_name: String, min_tier: String = "mid") -> bool:
	if dominant_force != force_name:
		return false
	var tier_order := ["none", "low", "mid", "high", "critical"]
	return tier_order.find(force_tier) >= tier_order.find(min_tier)


## Get a modifier value (0.0 to 1.0+) for systems that scale with a force.
func get_force_modifier(force_name: String) -> float:
	return GameState.get_force(force_name) / 100.0
