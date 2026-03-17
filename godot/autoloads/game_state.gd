# game_state.gd
# Autoload: GameState
# Simple global state bus — holds values that must survive scene transitions.

extends Node

# Match setup
var vs_cpu            : bool   = false
var local_fighter_id  : String = ""
var selected_level_id : String = "african_village"
var room_id           : String = ""
var fight_id          : String = ""   # Matches Soroban contract fight ID

# Match results (populated by ArenaManager.match_ended)
var last_winner_id    : int    = -1
var last_scores       : Dictionary = {}
var last_round_count  : int    = 0

# Settings
var sfx_volume        : float  = 0.8
var music_volume      : float  = 0.6
var show_fps          : bool   = false
var graphics_quality  : int    = 1    # 0=low, 1=medium, 2=high

func _ready() -> void:
	_load_settings()

func reset_match() -> void:
	vs_cpu           = false
	local_fighter_id = ""
	room_id          = ""
	fight_id         = ""
	last_winner_id   = -1
	last_scores      = {}
	last_round_count = 0

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return
	sfx_volume       = cfg.get_value("audio",    "sfx_vol",   0.8)
	music_volume     = cfg.get_value("audio",    "music_vol", 0.6)
	show_fps         = cfg.get_value("graphics", "show_fps",  false)
	graphics_quality = cfg.get_value("graphics", "quality",   1)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio",    "sfx_vol",   sfx_volume)
	cfg.set_value("audio",    "music_vol", music_volume)
	cfg.set_value("graphics", "show_fps",  show_fps)
	cfg.set_value("graphics", "quality",   graphics_quality)
	cfg.save("user://settings.cfg")
