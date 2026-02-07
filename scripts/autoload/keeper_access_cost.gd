## KeeperAccessCost — Diegetic pressure system that prevents Keeper camping.
## Cost increases with visit frequency, time since last major betrayal, and god attention.
## Costs are NEVER hard blocks — they manifest as hostile routes, environmental instability,
## and NPCs refusing to guide the player toward the Keeper.
##
## The Keeper remains accessible. The WORLD pushes back against over-reliance.
## This preserves player agency while creating friction that rewards independence.
extends Node

signal access_cost_changed(new_cost: float)
signal route_hostility_changed(hostility: float)

# --- Visit Tracking ---
var keeper_visits_last_hour: int = 0
var keeper_visits_total: int = 0
var _visit_timestamps: Array[float] = []  # Unix timestamps of recent visits
const VISIT_WINDOW := 3600.0  # 1 hour window for frequency tracking

# --- Cost Calculation ---
# Soft cap: cost asymptotically approaches MAX but never reaches it.
# This means the player CAN always reach the Keeper — it just gets harder.
var current_cost: float = 0.0
const BASE_COST := 0.0
const COST_PER_RECENT_VISIT := 8.0     # +8 per visit in the last hour
const COST_PER_TOTAL_VISIT := 0.5      # +0.5 per lifetime visit (slow ramp)
const COST_BETRAYAL_DECAY := 15.0      # +15 if no major betrayal recently (safety-seeking)
const COST_GOD_ATTENTION_SCALE := 0.2  # +0.2 per point of max god attention
const COST_SOFT_CAP := 85.0            # Asymptotic ceiling — never truly blocks
const COST_RECALC_INTERVAL := 5.0

var _recalc_timer: float = 0.0
var _time_since_last_betrayal: float = 0.0

# --- Diegetic Effects ---
# These are what the player EXPERIENCES, not numbers they see.

# Route hostility: how dangerous the path to the Keeper feels.
# 0.0 = clear path, 1.0 = enemies everywhere, environment hostile.
var route_hostility: float = 0.0

# NPC guidance refusal: probability that NPCs won't point toward the Keeper.
# 0.0 = NPCs help freely, 1.0 = no NPC will mention the Keeper's location.
var npc_guidance_refusal: float = 0.0

# Environmental instability: visual/audio disruption near Keeper zones.
# Scales with cost. High cost = world resists the player's path to certainty.
var environmental_instability: float = 0.0

# --- Thresholds for diegetic effects ---
const HOSTILITY_ONSET := 20.0       # Route hostility begins at cost 20
const GUIDANCE_REFUSAL_ONSET := 35.0 # NPCs stop helping at cost 35
const INSTABILITY_ONSET := 50.0      # Environment destabilizes at cost 50


func _ready() -> void:
	AnchorManager.anchor_spoke.connect(_on_keeper_visited)
	BetrayalPacing.betrayal_occurred.connect(_on_betrayal_occurred)


func _process(delta: float) -> void:
	_recalc_timer += delta
	_time_since_last_betrayal += delta

	if _recalc_timer >= COST_RECALC_INTERVAL:
		_recalc_timer = 0.0
		_prune_old_visits()
		_recalculate_cost()
		_update_diegetic_effects()


## Called when the player speaks to the Keeper.
func _on_keeper_visited(_topic: String) -> void:
	var now := Time.get_unix_time_from_system()
	_visit_timestamps.append(now)
	keeper_visits_total += 1

	WorldMemory.record_ambient("Player sought the Keeper")

	# Log overreliance events at high frequency
	if keeper_visits_last_hour >= 4:
		WorldMemory.record("player_relied_on_anchor_%d" % keeper_visits_total)
		WorldMemory.record_ambient("Player relied on anchor (visit %d this hour)" % keeper_visits_last_hour)


## Reset betrayal timer when a betrayal occurs.
func _on_betrayal_occurred(_type: String, _timestamp: float) -> void:
	_time_since_last_betrayal = 0.0


## Remove visit timestamps older than the tracking window.
func _prune_old_visits() -> void:
	var now := Time.get_unix_time_from_system()
	var cutoff := now - VISIT_WINDOW
	while _visit_timestamps.size() > 0 and _visit_timestamps[0] < cutoff:
		_visit_timestamps.pop_front()
	keeper_visits_last_hour = _visit_timestamps.size()


## Recalculate the abstract cost of reaching the Keeper.
func _recalculate_cost() -> void:
	var old_cost := current_cost

	# Frequency component: recent visits
	var freq_cost := keeper_visits_last_hour * COST_PER_RECENT_VISIT

	# Lifetime component: total visits (slow pressure)
	var lifetime_cost := keeper_visits_total * COST_PER_TOTAL_VISIT

	# Betrayal safety-seeking: if it's been a long time since a betrayal,
	# the player may be using the Keeper as a crutch out of anxiety.
	var betrayal_cost := 0.0
	if _time_since_last_betrayal > 300.0:  # 5 minutes without betrayal
		betrayal_cost = COST_BETRAYAL_DECAY * clampf((_time_since_last_betrayal - 300.0) / 600.0, 0.0, 1.0)

	# God attention component: seeking shelter from divine pressure
	var max_attention := 0.0
	for god_id in GodManager.god_defs:
		max_attention = maxf(max_attention, GodManager.get_god_attention(god_id))
	var attention_cost := max_attention * COST_GOD_ATTENTION_SCALE

	# Sum all components
	var raw_cost := BASE_COST + freq_cost + lifetime_cost + betrayal_cost + attention_cost

	# Soft cap: asymptotic approach to COST_SOFT_CAP
	# Formula: cap * (1 - e^(-raw/cap)) — smoothly approaches cap
	current_cost = COST_SOFT_CAP * (1.0 - exp(-raw_cost / COST_SOFT_CAP))

	if absf(old_cost - current_cost) > 0.5:
		access_cost_changed.emit(current_cost)


## Update the diegetic manifestations of access cost.
func _update_diegetic_effects() -> void:
	# Route hostility: scales from 0 to 1 above the onset threshold
	if current_cost > HOSTILITY_ONSET:
		route_hostility = clampf((current_cost - HOSTILITY_ONSET) / (COST_SOFT_CAP - HOSTILITY_ONSET), 0.0, 1.0)
	else:
		route_hostility = 0.0

	# NPC guidance refusal: probability NPCs won't mention the Keeper
	if current_cost > GUIDANCE_REFUSAL_ONSET:
		npc_guidance_refusal = clampf((current_cost - GUIDANCE_REFUSAL_ONSET) / (COST_SOFT_CAP - GUIDANCE_REFUSAL_ONSET), 0.0, 0.9)
	else:
		npc_guidance_refusal = 0.0

	# Environmental instability near Keeper zones
	if current_cost > INSTABILITY_ONSET:
		environmental_instability = clampf((current_cost - INSTABILITY_ONSET) / (COST_SOFT_CAP - INSTABILITY_ONSET), 0.0, 0.8)
	else:
		environmental_instability = 0.0

	route_hostility_changed.emit(route_hostility)


## Query: should an NPC refuse to guide the player to the Keeper?
func should_refuse_guidance() -> bool:
	return randf() < npc_guidance_refusal


## Query: get the current route hostility for spawner/environment systems.
func get_route_hostility() -> float:
	return route_hostility


## Query: get environmental instability for visual/audio systems.
func get_instability() -> float:
	return environmental_instability


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"current_cost": current_cost,
		"visits_last_hour": keeper_visits_last_hour,
		"visits_total": keeper_visits_total,
		"time_since_betrayal": _time_since_last_betrayal,
		"route_hostility": route_hostility,
		"npc_guidance_refusal": npc_guidance_refusal,
		"environmental_instability": environmental_instability,
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"visits_total": keeper_visits_total,
		"visit_timestamps": _visit_timestamps.duplicate(),
		"time_since_last_betrayal": _time_since_last_betrayal,
	}


func load_state(data: Dictionary) -> void:
	keeper_visits_total = data.get("visits_total", 0)
	var loaded_ts = data.get("visit_timestamps", [])
	_visit_timestamps.clear()
	for ts in loaded_ts:
		_visit_timestamps.append(float(ts))
	_time_since_last_betrayal = data.get("time_since_last_betrayal", 0.0)
	_prune_old_visits()
	_recalculate_cost()
	_update_diegetic_effects()
