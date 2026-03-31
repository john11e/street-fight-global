
# Manages the top-level 10-player arena lifecycle.
# Attach to: Project Settings → Autoload → ArenaManager

extends Node

# ─────────────────────────────────────────────
#  SIGNALS
# ─────────────────────────────────────────────
signal round_started(round_number: int)
signal round_ended(winner_id: int, reason: String)
signal match_ended(results: Dictionary)
signal player_eliminated(player_id: int)
signal combo_detected(player_id: int, combo_count: int)

# ─────────────────────────────────────────────
#  CONSTANTS
# ─────────────────────────────────────────────
const MAX_PLAYERS        := 10
const ROUNDS_TO_WIN      := 2
const ROUND_DURATION_SEC := 90
const RESPAWN_DELAY_SEC  := 3.0
const ARENA_RADIUS_M     := 18.0     # meters — used by clamp logic

# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var current_round     : int = 0
var scores            : Dictionary = {}   # peer_id → wins
var round_timer       : float = 0.0
var match_active      : bool = false
var round_active      : bool = false
var players_alive     : Array[int] = []   # peer ids still in the round
var level_scene_path  : String = ""

# ─────────────────────────────────────────────
#  SCENE REFS (populated at runtime)
# ─────────────────────────────────────────────
@onready var _hud       : CanvasLayer = null
@onready var _level     : Node3D      = null

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)

func _process(delta: float) -> void:
	if not round_active:
		return
	round_timer -= delta
	if _hud:
		_hud.update_timer(round_timer)
	if round_timer <= 0.0:
		_evaluate_time_up()

# ─────────────────────────────────────────────
#  PUBLIC API
# ─────────────────────────────────────────────
func load_level(scene_path: String) -> void:
	level_scene_path = scene_path
	var packed : PackedScene = load(scene_path)
	assert(packed != null, "ArenaManager: Level scene not found at %s" % scene_path)
	_level = packed.instantiate() as Node3D
	get_tree().current_scene.add_child(_level)

func start_match(peer_ids: Array[int]) -> void:
	assert(peer_ids.size() >= 2, "Need at least 2 players")
	assert(peer_ids.size() <= MAX_PLAYERS, "Cannot exceed %d players" % MAX_PLAYERS)
	scores.clear()
	for id in peer_ids:
		scores[id] = 0
	current_round = 0
	match_active  = true
	_start_round()

func register_hud(hud: CanvasLayer) -> void:
	_hud = hud

# ─────────────────────────────────────────────
#  ROUND MANAGEMENT
# ─────────────────────────────────────────────
func _start_round() -> void:
	current_round += 1
	round_timer = ROUND_DURATION_SEC
	players_alive = scores.keys()
	round_active = true
	_reset_all_fighters()
	emit_signal("round_started", current_round)
	if _hud:
		_hud.show_round_banner(current_round)

func _end_round(winner_id: int, reason: String) -> void:
	round_active = false
	if winner_id >= 0:
		scores[winner_id] = scores.get(winner_id, 0) + 1
	emit_signal("round_ended", winner_id, reason)
	if _hud:
		_hud.show_ko_banner(winner_id, reason)
	await get_tree().create_timer(2.5).timeout
	_check_match_winner()

func _evaluate_time_up() -> void:
	# Highest HP wins on time; ties go to more aggressive player (more hits landed)
	var best_id  : int   = -1
	var best_hp  : float = -1.0
	for peer_id in players_alive:
		var fighter := _get_fighter(peer_id)
		if fighter and fighter.current_hp > best_hp:
			best_hp = fighter.current_hp
			best_id = peer_id
	_end_round(best_id, "TIME_UP")

func _check_match_winner() -> void:
	for peer_id in scores:
		if scores[peer_id] >= ROUNDS_TO_WIN:
			match_active = false
			var results := {
				"winner_id": peer_id,
				"scores":    scores.duplicate(),
				"round_count": current_round
			}
			emit_signal("match_ended", results)
			EconomyManager.settle_bets(peer_id, results)
			return
	if match_active:
		_start_round()

# ─────────────────────────────────────────────
#  FIGHTER QUERIES
# ─────────────────────────────────────────────
func register_player_eliminated(peer_id: int) -> void:
	players_alive.erase(peer_id)
	emit_signal("player_eliminated", peer_id)
	if players_alive.size() == 1:
		_end_round(players_alive[0], "KO")
	elif players_alive.is_empty():
		_end_round(-1, "DOUBLE_KO")

func notify_combo(peer_id: int, count: int) -> void:
	emit_signal("combo_detected", peer_id, count)
	if _hud:
		_hud.show_combo(peer_id, count)

# ─────────────────────────────────────────────
#  INTERNAL HELPERS
# ─────────────────────────────────────────────
func _reset_all_fighters() -> void:
	var spawn_points := _level.get_spawn_points() if _level else []
	var i := 0
	for peer_id in players_alive:
		var fighter := _get_fighter(peer_id)
		if fighter:
			fighter.full_reset()
			if i < spawn_points.size():
				fighter.global_position = spawn_points[i].global_position
		i += 1

func _get_fighter(peer_id: int) -> Node:
	# Fighters are children of the level under a group "fighters"
	var group := get_tree().get_nodes_in_group("fighters")
	for node in group:
		if node.has_meta("peer_id") and node.get_meta("peer_id") == peer_id:
			return node
	return null

func _on_player_joined(peer_id: int) -> void:
	scores[peer_id] = 0

func _on_player_left(peer_id: int) -> void:
	scores.erase(peer_id)
	if match_active:
		register_player_eliminated(peer_id)
