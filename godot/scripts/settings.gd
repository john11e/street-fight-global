# settings.gd
# Attach to: res://scenes/ui/Settings.tscn (Control/Modal)

extends Control

@onready var sfx_slider     : HSlider    = $Panel/VBox/SFXRow/Slider
@onready var music_slider   : HSlider    = $Panel/VBox/MusicRow/Slider
@onready var fps_toggle     : CheckBox   = $Panel/VBox/FPSRow/Toggle
@onready var quality_select : OptionButton = $Panel/VBox/QualityRow/Select
@onready var btn_close      : Button     = $Panel/BtnClose
@onready var btn_logout     : Button     = $Panel/VBox/BtnLogout

func _ready() -> void:
	btn_close.pressed.connect(_on_close)
	btn_logout.pressed.connect(_on_logout)
	sfx_slider.value_changed.connect(func(v): GameState.sfx_volume = v; _apply_audio())
	music_slider.value_changed.connect(func(v): GameState.music_volume = v; _apply_audio())
	fps_toggle.toggled.connect(func(v): GameState.show_fps = v)
	quality_select.item_selected.connect(func(i): GameState.graphics_quality = i; _apply_quality())

	# Load current settings
	sfx_slider.value    = GameState.sfx_volume
	music_slider.value  = GameState.music_volume
	fps_toggle.button_pressed = GameState.show_fps
	quality_select.select(GameState.graphics_quality)

func _apply_audio() -> void:
	var sfx_bus   := AudioServer.get_bus_index("SFX")
	var music_bus := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(sfx_bus,   linear_to_db(GameState.sfx_volume))
	AudioServer.set_bus_volume_db(music_bus, linear_to_db(GameState.music_volume))

func _apply_quality() -> void:
	match GameState.graphics_quality:
		0:  # Low — mobile
			RenderingServer.viewport_set_msaa_3d(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_MSAA_DISABLED)
		1:  # Medium
			RenderingServer.viewport_set_msaa_3d(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_MSAA_2X)
		2:  # High
			RenderingServer.viewport_set_msaa_3d(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_MSAA_4X)

func _on_close() -> void:
	GameState.save_settings()
	UIManager.close_modal()

func _on_logout() -> void:
	AuthManager.logout()
	UIManager.close_modal()
	UIManager.goto_scene("main_menu")
