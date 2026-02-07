## KeeperAccessCost — Diegetic pressure system that prevents Keeper camping.
## Cost increases with visit frequency, time since last major betrayal, and god attention.
## Costs are NEVER hard blocks — they manifest as hostile routes, environmental instability,
## and NPCs refusing to guide the player toward the Keeper.
##
## The Keeper remains accessible. The WORLD pushes back against over-reliance.
## This preserves player agency while creating friction that rewards independence.
##
## A1 Extensions:
##   - Post-betrayal visit: hostility displaces ELSEWHERE (not near Keeper)
##   - NPC unrelated-help refusal: "you already asked the Keeper"
##   - Access streak tracking: 3+ visits in window → pathing worsens
##   - False relief cycle: first visit after streak feels cheaper, next spikes harder
extends Node

signal access_cost_changed(new_cost: float)
signal route_hostility_changed(hostility: float)
signal remote_hostility_spike(amount: float)
signal access_streak_detected(count: int)

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

# --- A1: Post-Betrayal Hostility Displacement ---
# Visiting Keeper right after betrayal makes the REST of the world hostile, not the Keeper area.
var _recent_betrayal: bool = false
var _recent_betrayal_timer: float = 0.0
const POST_BETRAYAL_WINDOW := 60.0  # 60 seconds after betrayal
var remote_hostility: float = 0.0   # Hostility in zones AWAY from Keeper
const REMOTE_HOSTILITY_DECAY := 0.01  # Per second

# --- A1: NPC Unrelated-Help Refusal ---
# If player has been visiting Keeper frequently, NPCs refuse unrelated help.
var _last_visit_time: float = 0.0
const UNRELATED_REFUSAL_VISIT_THRESHOLD := 2  # visits in last hour
const UNRELATED_REFUSAL_RECENCY := 300.0      # last visit within 5 minutes

# --- A1: Access Streak Tracking ---
# 3+ visits in a short window → world pathing subtly worsens.
var _streak_count: int = 0
const STREAK_WINDOW := 300.0  # 5-minute window for streak detection
const STREAK_THRESHOLD := 3   # Visits needed to trigger streak
var pathing_penalty: float = 0.0  # 0.0–1.0, queried by pathing systems
const PATHING_PENALTY_DECAY := 0.005  # Per second

# --- A1: False Relief Cycle ---
# First visit after a streak feels cheaper. Second spikes harder.
# The player learns the wrong lesson first.
var _relief_cycle_count: int = 0  # 0=normal, 1=relief, 2=spike
var _relief_cycle_timer: float = 0.0
const RELIEF_CYCLE_RESET := 600.0  # Reset after 10 minutes of no visits
const RELIEF_DISCOUNT := 0.6       # Raw cost multiplied by this during relief
const RELIEF_SPIKE := 1.4          # Raw cost multiplied by this during spike


func _ready() -> void:
	AnchorManager.anchor_spoke.connect(_on_keeper_visited)
	BetrayalPacing.betrayal_occurred.connect(_on_betrayal_occurred)


func _process(delta: float) -> void:
	_recalc_timer += delta
	_time_since_last_betrayal += delta
	_relief_cycle_timer += delta

	# Decay post-betrayal state
	if _recent_betrayal:
		_recent_betrayal_timer += delta
		if _recent_betrayal_timer >= POST_BETRAYAL_WINDOW:
			_recent_betrayal = false
			_recent_betrayal_timer = 0.0

	# Decay remote hostility
	if remote_hostility > 0.0:
		remote_hostility = maxf(remote_hostility - REMOTE_HOSTILITY_DECAY * delta, 0.0)

	# Decay pathing penalty
	if pathing_penalty > 0.0:
		pathing_penalty = maxf(pathing_penalty - PATHING_PENALTY_DECAY * delta, 0.0)

	# Reset relief cycle after long absence
	if _relief_cycle_timer >= RELIEF_CYCLE_RESET and _relief_cycle_count > 0:
		_relief_cycle_count = 0

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
	_last_visit_time = now
	_relief_cycle_timer = 0.0

	WorldMemory.record_ambient("Player sought the Keeper")

	# Log overreliance events at high frequency
	if keeper_visits_last_hour >= 4:
		WorldMemory.record("player_relied_on_anchor_%d" % keeper_visits_total)
		WorldMemory.record_ambient("Player relied on anchor (visit %d this hour)" % keeper_visits_last_hour)

	# --- A1: Post-betrayal displacement ---
	if _recent_betrayal:
		var spike := clampf(current_cost / COST_SOFT_CAP * 0.6, 0.1, 0.6)
		remote_hostility = clampf(remote_hostility + spike, 0.0, 1.0)
		remote_hostility_spike.emit(spike)
		WorldMemory.record_ambient("Seeking the Keeper after betrayal unsettled the world elsewhere")

	# --- A1: Streak detection ---
	var streak_visits := 0
	for ts in _visit_timestamps:
		if now - ts < STREAK_WINDOW:
			streak_visits += 1
	if streak_visits >= STREAK_THRESHOLD:
		_streak_count = streak_visits
		pathing_penalty = clampf(float(streak_visits - STREAK_THRESHOLD + 1) / 5.0, 0.0, 1.0)
		access_streak_detected.emit(streak_visits)
		WorldMemory.record_ambient("Repeated Keeper visits worsened the world's paths")

	# --- A1: False relief cycle progression ---
	if _streak_count >= STREAK_THRESHOLD:
		# After a streak, start the relief cycle
		if _relief_cycle_count == 0:
			_relief_cycle_count = 1  # Next recalc will apply relief discount
	else:
		# Advance cycle: relief → spike → normal
		if _relief_cycle_count == 1:
			_relief_cycle_count = 2  # Next visit after relief will spike
		elif _relief_cycle_count == 2:
			_relief_cycle_count = 0  # Cycle complete


## Reset betrayal timer when a betrayal occurs.
func _on_betrayal_occurred(_type: String, _timestamp: float) -> void:
	_time_since_last_betrayal = 0.0
	_recent_betrayal = true
	_recent_betrayal_timer = 0.0


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

	# --- A1: False relief cycle modifier ---
	if _relief_cycle_count == 1:
		raw_cost *= RELIEF_DISCOUNT  # Feels cheaper — false lesson
	elif _relief_cycle_count == 2:
		raw_cost *= RELIEF_SPIKE     # Spikes harder — correction

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


## Query: should an NPC refuse unrelated help because "you already asked the Keeper"?
## Returns true when player has visited Keeper recently and frequently enough
## that NPCs resent the player's reliance on the anchor.
func should_refuse_unrelated_help() -> bool:
	if keeper_visits_last_hour < UNRELATED_REFUSAL_VISIT_THRESHOLD:
		return false
	var now := Time.get_unix_time_from_system()
	if now - _last_visit_time > UNRELATED_REFUSAL_RECENCY:
		return false
	return randf() < 0.4  # 40% chance when conditions met


## Query: get the current route hostility for spawner/environment systems.
func get_route_hostility() -> float:
	return route_hostility


## Query: get remote hostility (zones AWAY from Keeper after post-betrayal visit).
func get_remote_hostility() -> float:
	return remote_hostility


## Query: get the pathing penalty from access streaks.
func get_pathing_penalty() -> float:
	return pathing_penalty


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
		"remote_hostility": remote_hostility,
		"npc_guidance_refusal": npc_guidance_refusal,
		"environmental_instability": environmental_instability,
		"streak_count": _streak_count,
		"pathing_penalty": pathing_penalty,
		"relief_cycle": _relief_cycle_count,
	}


# --- Persistence ---

func save_state() -> Dictionary:
	return {
		"visits_total": keeper_visits_total,
		"visit_timestamps": _visit_timestamps.duplicate(),
		"time_since_last_betrayal": _time_since_last_betrayal,
		"streak_count": _streak_count,
		"relief_cycle_count": _relief_cycle_count,
	}


func load_state(data: Dictionary) -> void:
	keeper_visits_total = data.get("visits_total", 0)
	var loaded_ts = data.get("visit_timestamps", [])
	_visit_timestamps.clear()
	for ts in loaded_ts:
		_visit_timestamps.append(float(ts))
	_time_since_last_betrayal = data.get("time_since_last_betrayal", 0.0)
	_streak_count = data.get("streak_count", 0)
	_relief_cycle_count = data.get("relief_cycle_count", 0)
	_prune_old_visits()
	_recalculate_cost()
	_update_diegetic_effects()
