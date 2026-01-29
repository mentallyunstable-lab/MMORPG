## ForceEnvironment — Modifies the zone's visual and audio atmosphere based on
## the current Three Forces state. Attach to any zone root or sub-node.
## Reads the zone's Environment resource and adjusts fog, sky, lighting, etc.
class_name ForceEnvironment
extends Node3D

@export_node_path("WorldEnvironment") var world_env_path: NodePath
@export_node_path("DirectionalLight3D") var sun_light_path: NodePath

var world_env: WorldEnvironment = null
var sun_light: DirectionalLight3D = null

# Base values (captured at _ready)
var _base_fog_color: Color
var _base_fog_density: float
var _base_ambient_color: Color
var _base_ambient_energy: float
var _base_light_color: Color
var _base_light_energy: float
var _base_sky_top: Color
var _base_sky_horizon: Color

var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null


func _ready() -> void:
	# Resolve node paths
	if world_env_path:
		world_env = get_node_or_null(world_env_path) as WorldEnvironment
	if sun_light_path:
		sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D

	# Capture base values
	if world_env and world_env.environment:
		_env = world_env.environment
		_base_fog_color = _env.fog_light_color
		_base_fog_density = _env.fog_density
		_base_ambient_color = _env.ambient_light_color
		_base_ambient_energy = _env.ambient_light_energy

		if _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
			_base_sky_top = _sky_mat.sky_top_color
			_base_sky_horizon = _sky_mat.sky_horizon_color

	if sun_light:
		_base_light_color = sun_light.light_color
		_base_light_energy = sun_light.light_energy

	GameState.force_changed.connect(_on_force_changed)
	_update_environment()


func _on_force_changed(_f: String, _o: float, _n: float) -> void:
	_update_environment()


func _update_environment() -> void:
	if not _env:
		return

	var faith_t := GameState.faith / 100.0
	var truth_t := GameState.truth / 100.0
	var violence_t := GameState.violence / 100.0

	# --- Fog ---
	# Faith: clearer, golden tint
	# Truth: thin, sharp white-blue
	# Violence: thick, red-orange
	var fog_color := _base_fog_color
	fog_color = fog_color.lerp(Color(0.4, 0.35, 0.2), faith_t * 0.5)     # Golden
	fog_color = fog_color.lerp(Color(0.2, 0.25, 0.35), truth_t * 0.4)     # Cold blue
	fog_color = fog_color.lerp(Color(0.3, 0.08, 0.05), violence_t * 0.6)  # Blood red
	_env.fog_light_color = fog_color

	# Fog density: violence thickens, truth thins
	var density := _base_fog_density
	density += violence_t * 0.02   # Thicker
	density -= truth_t * 0.005     # Clearer
	density = maxf(density, 0.0)
	_env.fog_density = density

	# --- Ambient Light ---
	var ambient := _base_ambient_color
	ambient = ambient.lerp(Color(0.3, 0.25, 0.15), faith_t * 0.4)    # Warm
	ambient = ambient.lerp(Color(0.15, 0.2, 0.3), truth_t * 0.4)     # Cold
	ambient = ambient.lerp(Color(0.25, 0.05, 0.02), violence_t * 0.5) # Dark red
	_env.ambient_light_color = ambient

	var amb_energy := _base_ambient_energy
	amb_energy += faith_t * 0.2    # Brighter with faith
	amb_energy -= violence_t * 0.15 # Darker with violence
	_env.ambient_light_energy = maxf(amb_energy, 0.1)

	# --- Sky ---
	if _sky_mat:
		var top := _base_sky_top
		top = top.lerp(Color(0.1, 0.1, 0.25), faith_t * 0.4)     # Deep indigo
		top = top.lerp(Color(0.15, 0.2, 0.3), truth_t * 0.3)     # Clear dark blue
		top = top.lerp(Color(0.15, 0.02, 0.02), violence_t * 0.5) # Blood sky
		_sky_mat.sky_top_color = top

		var horizon := _base_sky_horizon
		horizon = horizon.lerp(Color(0.5, 0.35, 0.15), faith_t * 0.4) # Golden horizon
		horizon = horizon.lerp(Color(0.3, 0.35, 0.45), truth_t * 0.3) # Steel
		horizon = horizon.lerp(Color(0.4, 0.1, 0.05), violence_t * 0.5) # Ember
		_sky_mat.sky_horizon_color = horizon

	# --- Sun/Directional Light ---
	if sun_light:
		var light_color := _base_light_color
		light_color = light_color.lerp(Color(1.0, 0.85, 0.5), faith_t * 0.3)   # Warm gold
		light_color = light_color.lerp(Color(0.8, 0.85, 1.0), truth_t * 0.3)   # Cool white
		light_color = light_color.lerp(Color(0.9, 0.3, 0.15), violence_t * 0.4) # Angry orange
		sun_light.light_color = light_color

		var energy := _base_light_energy
		energy += faith_t * 0.3
		energy -= violence_t * 0.2
		sun_light.light_energy = maxf(energy, 0.15)
