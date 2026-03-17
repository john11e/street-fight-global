# ko_stars.gd
# Attach to: res://scenes/vfx/KOStars.tscn (Node3D)
# Orbiting yellow stars above a KO'd fighter's head.
# VFXManager pools and reuses this node.

extends Node3D

const STAR_COUNT   := 5
const ORBIT_RADIUS := 0.35
const ORBIT_SPEED  := 3.2
const BOB_SPEED    := 2.0
const BOB_HEIGHT   := 0.08

var _stars  : Array[Node3D] = []
var _t      : float         = 0.0

func _ready() -> void:
	_build_stars()

func _build_stars() -> void:
	for child in get_children():
		child.queue_free()
	_stars.clear()
	for i in range(STAR_COUNT):
		var star    := MeshInstance3D.new()
		var mesh    := SphereMesh.new()
		mesh.radius  = 0.042
		mesh.height  = 0.09
		star.mesh    = mesh
		var mat                         := StandardMaterial3D.new()
		mat.albedo_color                 = Color(1.0, 0.92, 0.1)
		mat.emission_enabled             = true
		mat.emission                     = Color(1.0, 0.85, 0.0)
		mat.emission_energy_multiplier   = 3.0
		mat.shading_mode                 = BaseMaterial3D.SHADING_MODE_UNSHADED
		star.material_override           = mat
		add_child(star)
		_stars.append(star)

func play() -> void:
	visible = true
	_t      = 0.0
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	for i in range(_stars.size()):
		var angle    := _t * ORBIT_SPEED + (TAU / _stars.size()) * i
		var bob      := sin(_t * BOB_SPEED + i) * BOB_HEIGHT
		_stars[i].position = Vector3(cos(angle) * ORBIT_RADIUS, bob, sin(angle) * ORBIT_RADIUS)
