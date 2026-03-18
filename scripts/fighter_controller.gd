# fighter_controller.gd
# Attach to: res://scenes/fighters/FighterBase.tscn (CharacterBody3D)
# Extend per fighter. Designed for 10-player concurrency at 60 FPS.

class_name FighterController
extends CharacterBody3D

# ─────────────────────────────────────────────
#  EXPORTED PARAMS (set per archetype)
# ─────────────────────────────────────────────
@export var fighter_id      : String  = "unknown"
@export var max_hp          : float   = 100.0
@export var move_speed      : float   = 5.5
@export var run_speed       : float   = 9.0
@export var jump_force      : float   = 6.0
@export var mass_kg         : float   = 80.0
@export var power_rating    : float   = 80.0   # 0–100
@export var stagger_resist  : float   = 65.0   # 0–100
@export var combo_depth     : int     = 5
@export var recovery_ms     : float   = 350.0

# ─────────────────────────────────────────────
#  NODE REFS
# ─────────────────────────────────────────────
@onready var anim_tree      : AnimationTree  = $AnimationTree
@onready var anim_state     : AnimationNodeStateMachinePlayback = \
								anim_tree["parameters/playback"]
@onready var hitbox_punch   : Area3D  = $HitBoxes/Punch
@onready var hitbox_kick    : Area3D  = $HitBoxes/Kick
@onready var hurtbox        : Area3D  = $HurtBox
@onready var sfx_player     : AudioStreamPlayer3D = $SFX
@onready var vfx_spawn      : Node3D  = $VFXSpawnPoint
@onready var ragdoll_rig    : Skeleton3D = $Armature/Skeleton3D

# ─────────────────────────────────────────────
#  COMBAT STATE MACHINE
# ─────────────────────────────────────────────
enum State {
	IDLE, WALK, RUN, JUMP, FALL,
	PUNCH_1, PUNCH_2, PUNCH_3,
	KICK_1, KICK_2,
	BLOCK, DODGE,
	STAGGER, KO, DEAD
}

var current_state   : State = State.IDLE
var current_hp      : float
var peer_id         : int   = -1
var is_local_player : bool  = false
var is_grounded     : bool  = true
var facing_dir      : Vector3 = Vector3.FORWARD

# Combat
var combo_count     : int   = 0
var combo_timer     : float = 0.0
var attack_queued   : String = ""
var recovery_timer  : float = 0.0
var block_active    : bool  = false
var invincible      : bool  = false     # During dodge roll

# Input snapshot (from local input OR server reconciliation)
var input_snapshot  : Dictionary = {
	"move":    Vector2.ZERO,
	"punch":   false,
	"kick":    false,
	"block":   false,
	"dodge":   false,
	"jump":    false,
}

# Physics
const GRAVITY := -20.0
var _velocity_y : float = 0.0

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	current_hp = max_hp
	set_meta("peer_id", peer_id)
	add_to_group("fighters")
	hitbox_punch.monitoring = false
	hitbox_kick.monitoring  = false
	hurtbox.area_entered.connect(_on_hurtbox_hit)

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return
	if is_local_player:
		_read_local_input()
		_send_input_to_server()
	_update_timers(delta)
	_state_machine(delta)
	_apply_movement(delta)
	_update_animation()
	move_and_slide()

# ─────────────────────────────────────────────
#  INPUT
# ─────────────────────────────────────────────
func _read_local_input() -> void:
	input_snapshot["move"]  = Input.get_vector("move_left","move_right","move_forward","move_back")
	input_snapshot["punch"] = Input.is_action_just_pressed("punch")
	input_snapshot["kick"]  = Input.is_action_just_pressed("kick")
	input_snapshot["block"] = Input.is_action_pressed("block")
	input_snapshot["dodge"] = Input.is_action_just_pressed("dodge")
	input_snapshot["jump"]  = Input.is_action_just_pressed("jump")

func apply_server_state(state_dict: Dictionary) -> void:
	# Called on remote players from Colyseus patch
	global_position        = _vec3_from_dict(state_dict.get("pos", {}))
	global_basis           = _basis_from_dict(state_dict.get("rot", {}))
	current_hp             = state_dict.get("hp",    current_hp)
	current_state          = state_dict.get("state", current_state) as State
	input_snapshot["move"] = _vec2_from_dict(state_dict.get("move", {}))

func _send_input_to_server() -> void:
	NetworkManager.send_input(input_snapshot.duplicate())

# ─────────────────────────────────────────────
#  STATE MACHINE
# ─────────────────────────────────────────────
func _state_machine(delta: float) -> void:
	match current_state:
		State.IDLE, State.WALK, State.RUN:
			_handle_locomotion()
			_handle_combat_input()
		State.JUMP, State.FALL:
			_handle_air()
		State.PUNCH_1, State.PUNCH_2, State.PUNCH_3, State.KICK_1, State.KICK_2:
			_handle_attack_active()
		State.BLOCK:
			_handle_block()
		State.DODGE:
			_handle_dodge(delta)
		State.STAGGER:
			if recovery_timer <= 0:
				_transition(State.IDLE)
		State.KO:
			if recovery_timer <= 0:
				_trigger_ragdoll()

func _handle_locomotion() -> void:
	var move := input_snapshot["move"] as Vector2
	if move.length_squared() > 0.01:
		var run := move.length() > 0.7
		_transition(State.RUN if run else State.WALK)
	else:
		_transition(State.IDLE)

	if input_snapshot["jump"] and is_grounded:
		_velocity_y = jump_force
		_transition(State.JUMP)

func _handle_combat_input() -> void:
	if recovery_timer > 0:
		return

	if input_snapshot["dodge"]:
		_start_dodge()
		return

	if input_snapshot["punch"]:
		_start_attack("punch")
	elif input_snapshot["kick"]:
		_start_attack("kick")

	block_active = input_snapshot["block"]
	if block_active:
		_transition(State.BLOCK)

func _handle_attack_active() -> void:
	# Animation tree drives timing; hitbox activation is via animation callbacks
	if recovery_timer <= 0:
		_end_attack()

func _handle_block() -> void:
	if not input_snapshot["block"]:
		block_active = false
		_transition(State.IDLE)

func _handle_air() -> void:
	if is_grounded:
		_transition(State.IDLE)

func _handle_dodge(delta: float) -> void:
	if recovery_timer <= 0:
		invincible = false
		_transition(State.IDLE)
	else:
		var dir := _get_move_dir()
		velocity = dir * move_speed * 2.2

# ─────────────────────────────────────────────
#  ATTACK LOGIC
# ─────────────────────────────────────────────
func _start_attack(type: String) -> void:
	combo_timer = recovery_ms / 1000.0 * 1.8   # window to chain
	match type:
		"punch":
			match combo_count % 3:
				0: _transition(State.PUNCH_1)
				1: _transition(State.PUNCH_2)
				2: _transition(State.PUNCH_3)
		"kick":
			match combo_count % 2:
				0: _transition(State.KICK_1)
				1: _transition(State.KICK_2)
	combo_count = min(combo_count + 1, combo_depth)
	recovery_timer = recovery_ms / 1000.0
	ArenaManager.notify_combo(peer_id, combo_count)

func _end_attack() -> void:
	combo_timer -= get_physics_process_delta_time()
	if combo_timer <= 0:
		combo_count = 0
	hitbox_punch.monitoring = false
	hitbox_kick.monitoring  = false
	_transition(State.IDLE)

func activate_hitbox(type: String) -> void:
	# Called from AnimationTree via AnimationCallbackTrack
	match type:
		"punch": hitbox_punch.monitoring = true
		"kick":  hitbox_kick.monitoring  = true

func deactivate_hitbox(type: String) -> void:
	match type:
		"punch": hitbox_punch.monitoring = false
		"kick":  hitbox_kick.monitoring  = false

func _start_dodge() -> void:
	invincible     = true
	recovery_timer = 0.45
	_transition(State.DODGE)

# ─────────────────────────────────────────────
#  DAMAGE RECEPTION
# ─────────────────────────────────────────────
func _on_hurtbox_hit(area: Area3D) -> void:
	if invincible or current_state == State.DEAD:
		return

	var attacker := area.get_parent() as FighterController
	if attacker == null or attacker == self:
		return

	# Server is authoritative — local client only plays VFX/SFX immediately
	_play_hit_effect(area.global_position)

func receive_damage(amount: float, knockback: Vector3, attacker_id: int) -> void:
	# Called by server reconciliation packet
	if current_state == State.DEAD:
		return

	var resist_factor := stagger_resist / 100.0
	var effective := amount

	if block_active:
		effective *= 0.15
		anim_state.travel("block_impact")
	else:
		# Stagger chance inversely proportional to resist
		if randf() > resist_factor:
			_transition(State.STAGGER)
			recovery_timer = 0.5 + (amount / 100.0) * 0.8
		velocity += knockback * (mass_kg / 80.0)

	current_hp -= effective
	if current_hp <= 0.0:
		current_hp = 0.0
		_enter_ko()

func _enter_ko() -> void:
	_transition(State.KO)
	recovery_timer = 3.0
	ArenaManager.register_player_eliminated(peer_id)

func _trigger_ragdoll() -> void:
	_transition(State.DEAD)
	# Hand over control to physics skeleton
	ragdoll_rig.physical_bones_start_simulation()

# ─────────────────────────────────────────────
#  MOVEMENT
# ─────────────────────────────────────────────
func _apply_movement(delta: float) -> void:
	if current_state in [State.DODGE]:
		return   # Dodge handles its own velocity

	is_grounded = is_on_floor()
	if not is_grounded:
		_velocity_y += GRAVITY * delta
	else:
		_velocity_y = max(_velocity_y, 0.0)

	if current_state in [State.WALK, State.RUN]:
		var dir   := _get_move_dir()
		var speed := run_speed if current_state == State.RUN else move_speed
		velocity   = dir * speed
		if dir != Vector3.ZERO:
			facing_dir = dir
			var target_basis := Basis.looking_at(dir)
			global_basis = global_basis.slerp(target_basis, 0.2)
	elif current_state in [State.IDLE, State.PUNCH_1, State.PUNCH_2,
						   State.PUNCH_3, State.KICK_1, State.KICK_2, State.BLOCK]:
		velocity = velocity.lerp(Vector3.ZERO, 0.35)

	velocity.y = _velocity_y

func _get_move_dir() -> Vector3:
	var mv := input_snapshot["move"] as Vector2
	# Camera-relative movement: rotate by camera yaw
	var cam_yaw := CameraManager.get_camera_yaw()
	var dir := Vector3(mv.x, 0, mv.y).rotated(Vector3.UP, cam_yaw).normalized()
	return dir

# ─────────────────────────────────────────────
#  ANIMATION
# ─────────────────────────────────────────────
func _update_animation() -> void:
	match current_state:
		State.IDLE:       anim_state.travel("idle")
		State.WALK:       anim_state.travel("walk")
		State.RUN:        anim_state.travel("run")
		State.JUMP:       anim_state.travel("jump_up")
		State.FALL:       anim_state.travel("fall")
		State.PUNCH_1:    anim_state.travel("punch_jab")
		State.PUNCH_2:    anim_state.travel("punch_cross")
		State.PUNCH_3:    anim_state.travel("punch_uppercut")
		State.KICK_1:     anim_state.travel("kick_front")
		State.KICK_2:     anim_state.travel("kick_roundhouse")
		State.BLOCK:      anim_state.travel("block")
		State.DODGE:      anim_state.travel("dodge_roll")
		State.STAGGER:    anim_state.travel("stagger")
		State.KO:         anim_state.travel("ko")

# ─────────────────────────────────────────────
#  VFX / SFX
# ─────────────────────────────────────────────
func _play_hit_effect(world_pos: Vector3) -> void:
	VFXManager.spawn_hit_effect(world_pos, facing_dir)
	sfx_player.stream = preload("res://audio/sfx/hit_generic.ogg")
	sfx_player.play()

# ─────────────────────────────────────────────
#  UTILITIES
# ─────────────────────────────────────────────
func _transition(new_state: State) -> void:
	if current_state == new_state:
		return
	current_state = new_state

func _update_timers(delta: float) -> void:
	if recovery_timer > 0:  recovery_timer -= delta
	if combo_timer    > 0:  combo_timer    -= delta

func full_reset() -> void:
	current_hp      = max_hp
	current_state   = State.IDLE
	combo_count     = 0
	block_active    = false
	invincible      = false
	recovery_timer  = 0.0
	velocity        = Vector3.ZERO

# ─────────────────────────────────────────────
#  SERIALIZATION HELPERS
# ─────────────────────────────────────────────
func _vec3_from_dict(d: Dictionary) -> Vector3:
	return Vector3(d.get("x",0.0), d.get("y",0.0), d.get("z",0.0))

func _vec2_from_dict(d: Dictionary) -> Vector2:
	return Vector2(d.get("x",0.0), d.get("y",0.0))

func _basis_from_dict(d: Dictionary) -> Basis:
	var euler := Vector3(d.get("x",0.0), d.get("y",0.0), d.get("z",0.0))
	return Basis.from_euler(euler)
