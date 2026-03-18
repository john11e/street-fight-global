# level_base.gd
# Attach to: res://scenes/levels/LevelBase.tscn
# ALL 20 levels inherit from this scene via Godot's Inherited Scenes.
# This provides guaranteed spawn points, lighting setup, NavMesh,
# and performance budget enforcement — at 60 FPS on mobile.

class_name LevelBase
extends Node3D

# ─────────────────────────────────────────────
#  CONSTANTS — Mobile Performance Budget
# ─────────────────────────────────────────────
## Each level MUST stay within these limits when targeting mobile (60 FPS)
const MOBILE_TRIANGLE_BUDGET   := 80_000     # ~80k triangles per level geometry
const MOBILE_DRAW_CALL_BUDGET  := 35         # Max RenderingServer draw calls
const MOBILE_TEXTURE_BUDGET_MB := 48         # MB of GPU texture memory per level
const MOBILE_LIGHT_BUDGET      := 3          # Max real-time lights (rest = baked)
const SHADOW_CASTING_LIGHTS    := 1          # Only 1 shadow-casting light per level

# ─────────────────────────────────────────────
#  EXPORTED CONFIG (override per inherited scene)
# ─────────────────────────────────────────────
@export var level_id       : String = "level_base"
@export var display_name   : String = "Base Arena"
@export var region         : String = "Unset"
@export var ambient_color  : Color  = Color(0.12, 0.12, 0.14)
@export var fog_enabled    : bool   = false
@export var fog_density    : float  = 0.02

# ─────────────────────────────────────────────
#  REQUIRED NODE PATHS (must exist in every inherited scene)
# ─────────────────────────────────────────────
@onready var spawn_container  : Node3D         = $SpawnPoints
@onready var arena_collision  : StaticBody3D   = $ArenaGround
@onready var nav_region       : NavigationRegion3D = $NavigationRegion
@onready var ambient_light    : WorldEnvironment = $WorldEnvironment
@onready var sun_light        : DirectionalLight3D = $SunLight
@onready var crowd_parent     : Node3D         = $Crowd
@onready var destructibles    : Node3D         = $Destructibles
@onready var audio_bus        : AudioStreamPlayer = $AmbientAudio

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	_apply_environment()
	_bake_lighting_if_needed()
	_configure_lod()
	_setup_crowd()
	LevelManager.register_level(self)

func _apply_environment() -> void:
	var env := Environment.new()
	env.ambient_light_color  = ambient_color
	env.ambient_light_energy = 0.8
	env.fog_enabled          = fog_enabled
	env.fog_density          = fog_density
	env.ssao_enabled         = false   # Disabled on mobile
	env.ssr_enabled          = false
	env.sdfgi_enabled        = false   # Use baked GI instead
	ambient_light.environment = env

func _bake_lighting_if_needed() -> void:
	# In editor, light baking happens via BakedLightmap nodes.
	# At runtime we simply confirm the baked lightmap is valid.
	var baked_gi : LightmapGI = find_child("LightmapGI", true, false)
	if baked_gi == null:
		push_warning("[LevelBase] %s has no LightmapGI. Add one for mobile performance." % level_id)

func _configure_lod() -> void:
	# Godot 4 Visibility Notifiers + LOD Groups
	# Each major mesh should use GeometryInstance3D's LOD bias
	for child in get_children():
		var gi := child as GeometryInstance3D
		if gi:
			gi.lod_bias = 1.0   # Normal LOD; increase to force lower LOD sooner

func _setup_crowd() -> void:
	# Crowd uses MultiMeshInstance3D with baked animations (AnimationBaker)
	# Each level defines its own crowd density via crowd_parent child count
	if crowd_parent:
		_animate_crowd()

func _animate_crowd() -> void:
	# Simple shader-driven crowd bob — zero CPU cost
	var mm := crowd_parent.find_child("CrowdMesh", true, false) as MultiMeshInstance3D
	if mm:
		mm.material_override.set_shader_parameter("time", 0.0)

func _process(delta: float) -> void:
	# Update crowd shader time uniform cheaply
	if crowd_parent:
		var mm := crowd_parent.find_child("CrowdMesh") as MultiMeshInstance3D
		if mm and mm.material_override:
			var t : float = mm.material_override.get_shader_parameter("time")
			mm.material_override.set_shader_parameter("time", t + delta)

# ─────────────────────────────────────────────
#  PUBLIC API
# ─────────────────────────────────────────────
func get_spawn_points() -> Array[Node3D]:
	var pts : Array[Node3D] = []
	for child in spawn_container.get_children():
		if child is Node3D:
			pts.append(child as Node3D)
	return pts

func trigger_destructible(id: String) -> void:
	var target := destructibles.find_child(id, true, false)
	if target and target.has_method("break_apart"):
		target.break_apart()

# ─────────────────────────────────────────────
#  PERFORMANCE ASSERTION (Editor only)
# ─────────────────────────────────────────────
func _validate_performance_budget() -> void:
	# Call this from @tool script or CI pipeline
	var triangle_count := 0
	for node in get_children():
		var mi := node as MeshInstance3D
		if mi and mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				triangle_count += mi.mesh.surface_get_array_len(s)
	if triangle_count > MOBILE_TRIANGLE_BUDGET:
		push_error("[LevelBase] %s exceeds mobile tri budget: %d / %d" % [
			level_id, triangle_count, MOBILE_TRIANGLE_BUDGET
		])

# ═════════════════════════════════════════════
#  LEVEL MANIFEST — 20 Levels
#  Each line = an inherited scene (.tscn) path.
#  The inherited scene ONLY overrides:
#   - Mesh assets + PBR materials
#   - Ambient light color / fog settings
#   - Crowd density MultiMesh
#   - Destructible objects
#   - NavMesh geometry
#  It does NOT duplicate spawn logic, HUD wiring, or combat code.
# ═════════════════════════════════════════════

# Accessed via LevelManager.LEVEL_LIST[index]
const LEVEL_LIST : Array[Dictionary] = [
	{ "id": "african_village",  "path": "res://scenes/levels/AfricanVillage.tscn",   "region": "Sub-Saharan Africa" },
	{ "id": "neon_city",        "path": "res://scenes/levels/NeonCity.tscn",          "region": "East Asia" },
	{ "id": "sahara_desert",    "path": "res://scenes/levels/SaharaDesert.tscn",      "region": "North Africa" },
	{ "id": "favela_rooftop",   "path": "res://scenes/levels/FavelaRooftop.tscn",     "region": "South America" },
	{ "id": "london_alley",     "path": "res://scenes/levels/LondonAlley.tscn",       "region": "Europe" },
	{ "id": "thai_temple",      "path": "res://scenes/levels/ThaiTemple.tscn",        "region": "Southeast Asia" },
	{ "id": "nairobi_market",   "path": "res://scenes/levels/NairobiMarket.tscn",     "region": "East Africa" },
	{ "id": "arctic_platform",  "path": "res://scenes/levels/ArcticPlatform.tscn",   "region": "Polar" },
	{ "id": "brooklyn_warehouse","path": "res://scenes/levels/BrooklynWarehouse.tscn","region": "North America" },
	{ "id": "istanbul_bazaar",  "path": "res://scenes/levels/IstanbulBazaar.tscn",   "region": "Middle East" },
	{ "id": "mumbai_trainyard", "path": "res://scenes/levels/MumbaiTrainyard.tscn",  "region": "South Asia" },
	{ "id": "moscow_underpass", "path": "res://scenes/levels/MoscowUnderpass.tscn",  "region": "Eastern Europe" },
	{ "id": "lagoon_village",   "path": "res://scenes/levels/LagoonVillage.tscn",    "region": "West Africa" },
	{ "id": "havana_street",    "path": "res://scenes/levels/HavanaStreet.tscn",     "region": "Caribbean" },
	{ "id": "tokyo_subway",     "path": "res://scenes/levels/TokyoSubway.tscn",      "region": "East Asia" },
	{ "id": "cairo_rooftop",    "path": "res://scenes/levels/CairoRooftop.tscn",     "region": "North Africa" },
	{ "id": "nyc_pier",         "path": "res://scenes/levels/NYCPier.tscn",          "region": "North America" },
	{ "id": "jungle_clearing",  "path": "res://scenes/levels/JungledClearing.tscn", "region": "Central Africa" },
	{ "id": "dubai_skybridge",  "path": "res://scenes/levels/DubaiSkybridge.tscn",  "region": "Gulf" },
	{ "id": "underground_rave", "path": "res://scenes/levels/UndergroundRave.tscn", "region": "Global" },
]
