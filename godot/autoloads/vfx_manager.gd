# vfx_manager.gd
# Autoload: VFXManager
# Object-pooled VFX system. Pre-spawns particles at boot to avoid runtime allocation.
# All effects are fire-and-forget: call spawn_* and forget about cleanup.

extends Node

# ─────────────────────────────────────────────
#  POOL CONFIG
# ─────────────────────────────────────────────
const POOL_SIZE_HIT      := 20
const POOL_SIZE_BLOOD    := 20
const POOL_SIZE_SWEAT    := 10
const POOL_SIZE_KO       := 5
const POOL_SIZE_COMBO    := 15
const POOL_SIZE_SPARK    := 10

# ─────────────────────────────────────────────
#  PRELOADED SCENES
# ─────────────────────────────────────────────
const VFX_HIT_SPARK  := preload("res://scenes/vfx/HitSpark.tscn")   as PackedScene
const VFX_BLOOD      := preload("res://scenes/vfx/BloodBurst.tscn") as PackedScene
const VFX_SWEAT      := preload("res://scenes/vfx/SweatDrops.tscn") as PackedScene
const VFX_KO_STARS   := preload("res://scenes/vfx/KOStars.tscn")    as PackedScene
const VFX_COMBO_TEXT := preload("res://scenes/vfx/ComboText.tscn")  as PackedScene
const VFX_DUST       := preload("res://scenes/vfx/DustPuff.tscn")   as PackedScene

# ─────────────────────────────────────────────
#  POOL STORAGE
# ─────────────────────────────────────────────
var _pools: Dictionary = {}   # effect_id (String) → Array[Node]
var _root : Node3D

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	_root = Node3D.new()
	_root.name = "VFXPool"
	get_tree().current_scene.add_child(_root)
	_build_pools()

func _build_pools() -> void:
	_fill_pool("hit_spark",  VFX_HIT_SPARK,  POOL_SIZE_HIT)
	_fill_pool("blood",      VFX_BLOOD,      POOL_SIZE_BLOOD)
	_fill_pool("sweat",      VFX_SWEAT,      POOL_SIZE_SWEAT)
	_fill_pool("ko_stars",   VFX_KO_STARS,   POOL_SIZE_KO)
	_fill_pool("combo_text", VFX_COMBO_TEXT, POOL_SIZE_COMBO)
	_fill_pool("dust",       VFX_DUST,       POOL_SIZE_SPARK)

func _fill_pool(id: String, scene: PackedScene, count: int) -> void:
	_pools[id] = []
	for i in range(count):
		var node := scene.instantiate()
		node.visible = false
		_root.add_child(node)
		_pools[id].append(node)

# ─────────────────────────────────────────────
#  PUBLIC SPAWN API
# ─────────────────────────────────────────────
func spawn_hit_effect(world_pos: Vector3, direction: Vector3) -> void:
	var node := _get_pooled("hit_spark")
	if not node: return
	node.global_position = world_pos
	node.look_at(world_pos + direction)
	_play(node)

func spawn_blood(world_pos: Vector3, impact_normal: Vector3) -> void:
	var node := _get_pooled("blood")
	if not node: return
	node.global_position = world_pos
	node.global_basis    = Basis.looking_at(impact_normal)
	_play(node)

func spawn_sweat(fighter_pos: Vector3) -> void:
	var node := _get_pooled("sweat")
	if not node: return
	node.global_position = fighter_pos + Vector3(0, 1.6, 0)
	_play(node)

func spawn_ko_stars(fighter_pos: Vector3) -> void:
	var node := _get_pooled("ko_stars")
	if not node: return
	node.global_position = fighter_pos + Vector3(0, 2.2, 0)
	_play(node)

func spawn_combo_text(world_pos: Vector3, combo_count: int) -> void:
	var node := _get_pooled("combo_text")
	if not node: return
	node.global_position = world_pos + Vector3(0, 2.0, 0)
	if node.has_method("set_combo"):
		node.set_combo(combo_count)
	_play(node)

func spawn_dust(world_pos: Vector3) -> void:
	var node := _get_pooled("dust")
	if not node: return
	node.global_position = world_pos
	_play(node)

func spawn_impact_decal(world_pos: Vector3, normal: Vector3, type: String) -> void:
	## Blood smear on floor/wall — uses Decal node, max 8 active at once
	var decal := Decal.new()
	decal.global_position = world_pos + normal * 0.02
	decal.global_basis    = Basis.looking_at(normal)
	decal.size            = Vector3(0.6, 0.6, 0.1)
	match type:
		"blood": decal.texture_albedo = preload("res://assets/vfx/decal_blood.png")
		"scuff": decal.texture_albedo = preload("res://assets/vfx/decal_scuff.png")
	_root.add_child(decal)
	# Auto-clean old decals to stay within budget
	_prune_decals()

# ─────────────────────────────────────────────
#  POOL INTERNALS
# ─────────────────────────────────────────────
func _get_pooled(id: String) -> Node:
	var pool : Array = _pools.get(id, [])
	for node in pool:
		if not node.visible:
			return node
	push_warning("VFXManager: pool exhausted for '%s'" % id)
	return null

func _play(node: Node) -> void:
	node.visible = true
	# GPUParticles3D: restart emission
	if node is GPUParticles3D:
		node.restart()
	elif node.has_method("play"):
		node.play()
	# Auto-return to pool after effect lifetime
	var lifetime : float = 2.0
	if node is GPUParticles3D:
		lifetime = node.lifetime + 0.1
	get_tree().create_timer(lifetime).timeout.connect(func(): node.visible = false)

func _prune_decals() -> void:
	var decals : Array = []
	for child in _root.get_children():
		if child is Decal:
			decals.append(child)
	while decals.size() > 8:
		decals[0].queue_free()
		decals.remove_at(0)
