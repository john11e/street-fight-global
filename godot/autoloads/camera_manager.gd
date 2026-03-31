# Autoload: CameraManager
# Dynamic 3D camera: follows all fighters, zooms out for wider fights,
# cuts to spectator orbit when local player is KO'd.

extends Node

# ─────────────────────────────────────────────
#  SIGNALS
# ─────────────────────────────────────────────
signal camera_mode_changed(mode: String)

# ─────────────────────────────────────────────
#  CONSTANTS
# ─────────────────────────────────────────────
const HEIGHT_BASE      := 12.0    # meters above arena center
const HEIGHT_ZOOM_MAX  := 22.0    # pulls back when fighters spread out
const PITCH_ANGLE      := -55.0   # degrees — top-down tilt
const SMOOTHING        := 5.0     # lerp factor
const SPECTATOR_RADIUS := 14.0    # orbit distance
const SPECTATOR_SPEED  := 0.4     # radians/sec orbit

enum CameraMode { FOLLOW, SPECTATOR, CUTSCENE, MENU }

# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var _camera      : Camera3D = null
var _mode        : CameraMode = CameraMode.MENU
var _target_pos  : Vector3 = Vector3.ZERO
var _target_dist : float   = HEIGHT_BASE
var _spectator_angle : float = 0.0
var _local_fighter_id: int  = -1
var _shake_trauma : float   = 0.0   # 0–1
var _shake_seed   : float   = 0.0

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	ArenaManager.round_started.connect(_on_round_started)
	ArenaManager.player_eliminated.connect(_on_player_eliminated)

func _process(delta: float) -> void:
	if not _camera:
		_find_camera()
		return
	match _mode:
		CameraMode.FOLLOW:    _update_follow(delta)
		CameraMode.SPECTATOR: _update_spectator(delta)
	if _shake_trauma > 0:
		_apply_shake(delta)

# ─────────────────────────────────────────────
#  PUBLIC API
# ─────────────────────────────────────────────
func set_local_fighter(peer_id: int) -> void:
	_local_fighter_id = peer_id

func set_mode(mode: CameraMode) -> void:
	_mode = mode
	emit_signal("camera_mode_changed", CameraMode.keys()[mode])

func add_trauma(amount: float) -> void:
	_shake_trauma = clamp(_shake_trauma + amount, 0.0, 1.0)

func get_camera_yaw() -> float:
	if not _camera:
		return 0.0
	return _camera.global_rotation.y

func do_ko_slowmo(duration: float = 1.2) -> void:
	Engine.time_scale = 0.25
	get_tree().create_timer(duration * 0.25).timeout.connect(func():
		Engine.time_scale = 1.0
	)

# ─────────────────────────────────────────────
#  FOLLOW MODE
# ─────────────────────────────────────────────
func _update_follow(delta: float) -> void:
	var fighters := get_tree().get_nodes_in_group("fighters")
	if fighters.is_empty():
		return

	# Find centroid and spread of all alive fighters
	var centroid := Vector3.ZERO
	var alive_count := 0
	var max_spread  := 0.0
	var positions   : Array[Vector3] = []

	for f in fighters:
		if f.has_method("getSerialState") or f is CharacterBody3D:
			if f.get("dead") == false or f.get("dead") == null:
				centroid += f.global_position
				positions.append(f.global_position)
				alive_count += 1

	if alive_count == 0:
		return

	centroid /= alive_count

	# Calculate spread → drive camera height
	for pos in positions:
		var d := pos.distance_to(centroid)
		max_spread = max(max_spread, d)

	var desired_height := clamp(HEIGHT_BASE + max_spread * 1.2, HEIGHT_BASE, HEIGHT_ZOOM_MAX)
	_target_dist = lerp(_target_dist, desired_height, delta * 2.0)

	# Smooth centroid follow
	_target_pos = _target_pos.lerp(centroid, delta * SMOOTHING)

	# Position: above centroid, pitched down
	var cam_offset := Vector3(0, _target_dist, _target_dist * 0.4)
	var desired_pos := _target_pos + cam_offset
	_camera.global_position = _camera.global_position.lerp(desired_pos, delta * SMOOTHING)
	_camera.look_at(_target_pos + Vector3(0, 1, 0))

# ─────────────────────────────────────────────
#  SPECTATOR MODE (after local player KO)
# ─────────────────────────────────────────────
func _update_spectator(delta: float) -> void:
	_spectator_angle += SPECTATOR_SPEED * delta
	var cx := cos(_spectator_angle) * SPECTATOR_RADIUS
	var cz := sin(_spectator_angle) * SPECTATOR_RADIUS
	var desired := Vector3(cx, HEIGHT_BASE * 0.8, cz) + _target_pos
	_camera.global_position = _camera.global_position.lerp(desired, delta * 3.0)
	_camera.look_at(_target_pos + Vector3(0, 1, 0))

# ─────────────────────────────────────────────
#  SCREEN SHAKE
# ─────────────────────────────────────────────
func _apply_shake(delta: float) -> void:
	_shake_trauma = max(0.0, _shake_trauma - delta * 1.8)
	_shake_seed   += delta * 80.0
	var shake := _shake_trauma * _shake_trauma
	var noise_x := (noise_at(_shake_seed)        - 0.5) * 2.0
	var noise_y := (noise_at(_shake_seed + 100.0) - 0.5) * 2.0
	_camera.h_offset = noise_x * shake * 0.25
	_camera.v_offset = noise_y * shake * 0.25

func noise_at(x: float) -> float:
	## Simple pseudo-random — replace with FastNoiseLite if available
	return fmod(sin(x * 127.1 + cos(x * 311.7)) * 43758.5453, 1.0)

# ─────────────────────────────────────────────
#  EVENT HANDLERS
# ─────────────────────────────────────────────
func _on_round_started(_round_num: int) -> void:
	set_mode(CameraMode.FOLLOW)
	_shake_trauma = 0.0

func _on_player_eliminated(peer_id: int) -> void:
	if peer_id == _local_fighter_id:
		await get_tree().create_timer(0.8).timeout
		set_mode(CameraMode.SPECTATOR)
		add_trauma(0.6)

func _find_camera() -> void:
	_camera = get_tree().current_scene.find_child("MainCamera", true, false) as Camera3D
