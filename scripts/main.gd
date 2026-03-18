# main.gd
# Attach to: res://scenes/main.tscn (Node3D — the root game scene)
# Orchestrates: level loading, fighter spawning, HUD setup, betting panel.

extends Node3D

# ─────────────────────────────────────────────
#  NODE REFS
# ─────────────────────────────────────────────
@onready var camera      : Camera3D   = $MainCamera
@onready var hud         : CanvasLayer = $HUD
@onready var betting     : CanvasLayer = $BettingPanel

# ─────────────────────────────────────────────
#  CONSTANTS
# ─────────────────────────────────────────────
const FIGHTER_SCENES : Dictionary = {
	"bane_crusher":  "res://scenes/fighters/Crusher.tscn",
	"wick_ghost":    "res://scenes/fighters/Ghost.tscn",
	"dragon_fist":   "res://scenes/fighters/Dragon.tscn",
	"shaka_warrior": "res://scenes/fighters/Shaka.tscn",
	"specter_zero":  "res://scenes/fighters/Specter.tscn",
	"thunder_queen": "res://scenes/fighters/Thunder.tscn",
	"neon_cipher":   "res://scenes/fighters/Cipher.tscn",
	"desert_hawk":   "res://scenes/fighters/Hawk.tscn",
	"iron_monk":     "res://scenes/fighters/IronMonk.tscn",
	"nakia_viper":   "res://scenes/fighters/Viper.tscn",
}

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	# Register camera and HUD
	CameraManager._find_camera()
	UIManager.register_hud(hud)

	# Load level
	var level_id   := GameState.selected_level_id
	var level_info := _get_level_info(level_id)
	if level_info.is_empty():
		push_warning("main.gd: Unknown level '%s', using default" % level_id)
		level_info = { "path": "res://scenes/levels/AfricanVillage.tscn" }
	ArenaManager.load_level(level_info["path"])

	# Setup match
	if GameState.vs_cpu:
		_setup_vs_cpu()
	else:
		_setup_online()

func _setup_vs_cpu() -> void:
	# Spawn local player
	var local_id     := 1
	var cpu_id       := 2
	var local_fighter := GameState.local_fighter_id
	var cpu_fighter  := _pick_random_fighter(local_fighter)

	_spawn_fighter(local_id, local_fighter, is_local: true)
	_spawn_fighter(cpu_id,   cpu_fighter,   is_local: false, is_cpu: true)

	# Brief Soroban fight_id for CPU mode (no real bets)
	GameState.fight_id = "CPU_%s" % str(Time.get_ticks_msec())

	ArenaManager.start_match([local_id, cpu_id])
	betting.visible = false

func _setup_online() -> void:
	# Fighters spawned as players join via NetworkManager
	NetworkManager.state_patch_received.connect(_on_state_patch)
	NetworkManager.player_joined.connect(_on_player_joined)

	# Set betting fight ID and show panel
	GameState.fight_id = NetworkManager._room_id
	betting.visible    = true
	if betting.has_method("set_fight_id"):
		betting.set_fight_id(GameState.fight_id)

# ─────────────────────────────────────────────
#  FIGHTER SPAWNING
# ─────────────────────────────────────────────
func _spawn_fighter(peer_id: int, fighter_id: String,
					is_local: bool = false, is_cpu: bool = false) -> FighterController:
	var path   : String = FIGHTER_SCENES.get(fighter_id, FIGHTER_SCENES["bane_crusher"])
	var packed : PackedScene = load(path)
	var fighter := packed.instantiate() as FighterController

	fighter.peer_id         = peer_id
	fighter.is_local_player = is_local
	fighter.set_meta("peer_id", peer_id)

	if is_cpu:
		fighter.set_meta("is_cpu", true)

	add_child(fighter)

	if is_local:
		CameraManager.set_local_fighter(peer_id)
		hud.register_player(peer_id, fighter_id.to_upper(), true)
	else:
		hud.register_player(peer_id, fighter_id.to_upper(), false)

	return fighter

func _on_player_joined(peer_id: int) -> void:
	# For online: spawn remote player's fighter when we learn their fighter choice
	pass   # Handled via state_patch_received

func _on_state_patch(patch: Dictionary) -> void:
	var players : Dictionary = patch.get("players", {})
	for session_id in players:
		var player_data : Dictionary = players[session_id]
		var peer_id     : int        = player_data.get("peerId", -1)
		var fighter_id  : String     = player_data.get("fighterId", "bane_crusher")

		# Spawn fighter if not yet in scene
		var existing := _get_fighter_by_id(peer_id)
		if not existing:
			var is_local := (session_id == NetworkManager.get_session_id())
			_spawn_fighter(peer_id, fighter_id, is_local)

		# Apply authoritative state to remote fighters
		var fighter := _get_fighter_by_id(peer_id)
		if fighter and fighter.has_method("apply_server_state"):
			fighter.apply_server_state(player_data)
			hud.update_hp_bar(peer_id, player_data.get("hp", 100.0), 100.0)

# ─────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────
func _get_level_info(level_id: String) -> Dictionary:
	for entry in LevelBase.LEVEL_LIST:
		if entry["id"] == level_id:
			return entry
	return {}

func _pick_random_fighter(exclude: String) -> String:
	var keys := FIGHTER_SCENES.keys()
	keys.erase(exclude)
	return keys[randi() % keys.size()]

func _get_fighter_by_id(peer_id: int) -> FighterController:
	for node in get_tree().get_nodes_in_group("fighters"):
		if node.get_meta("peer_id", -1) == peer_id:
			return node as FighterController
	return null
