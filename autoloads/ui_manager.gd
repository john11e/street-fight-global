# ui_manager.gd
# Autoload: UIManager
# Central controller for all UI: scene transitions, HUD, modals, WebView (M-Pesa), notifications.

extends Node

# ─────────────────────────────────────────────
#  SIGNALS
# ─────────────────────────────────────────────
signal scene_transition_started(to_scene: String)
signal scene_transition_finished(scene_name: String)
signal modal_closed(modal_id: String)

# ─────────────────────────────────────────────
#  SCENE PATHS
# ─────────────────────────────────────────────
const SCENES := {
	"main_menu":   "res://scenes/ui/MainMenu.tscn",
	"char_select": "res://scenes/ui/CharSelect.tscn",
	"game":        "res://scenes/main.tscn",
	"results":     "res://scenes/ui/Results.tscn",
}

# ─────────────────────────────────────────────
#  NODE REFS (set after scene load)
# ─────────────────────────────────────────────
var _hud           : CanvasLayer = null
var _active_modal  : Control     = null
var _webview       : Node        = null   # WebViewPlugin (Android/iOS)
var _toast_queue   : Array[Dictionary] = []
var _toast_active  : bool = false

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	ArenaManager.round_started.connect(_on_round_started)
	ArenaManager.round_ended.connect(_on_round_ended)
	ArenaManager.match_ended.connect(_on_match_ended)
	ArenaManager.combo_detected.connect(_on_combo_detected)
	ArenaManager.player_eliminated.connect(_on_player_eliminated)

# ─────────────────────────────────────────────
#  SCENE MANAGEMENT
# ─────────────────────────────────────────────
func goto_scene(key: String) -> void:
	assert(SCENES.has(key), "UIManager: Unknown scene key '%s'" % key)
	emit_signal("scene_transition_started", key)
	var path : String = SCENES[key]
	# Fade transition
	await _fade_out()
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	_hud = null   # Reset HUD ref after scene change
	await _fade_in()
	emit_signal("scene_transition_finished", key)

func register_hud(hud: CanvasLayer) -> void:
	_hud = hud
	ArenaManager.register_hud(hud)

# ─────────────────────────────────────────────
#  HUD CONTROL
# ─────────────────────────────────────────────
func show_round_banner(round_num: int) -> void:
	if _hud and _hud.has_method("show_round_banner"):
		_hud.show_round_banner(round_num)

func show_ko_banner(winner_id: int, reason: String) -> void:
	if _hud and _hud.has_method("show_ko_banner"):
		_hud.show_ko_banner(winner_id, reason)
	if reason == "KO":
		CameraManager.do_ko_slowmo()
		CameraManager.add_trauma(0.8)

func update_hp_bar(peer_id: int, hp: float, max_hp: float) -> void:
	if _hud and _hud.has_method("update_hp_bar"):
		_hud.update_hp_bar(peer_id, hp, max_hp)

func update_timer(seconds: float) -> void:
	if _hud and _hud.has_method("update_timer"):
		_hud.update_timer(seconds)

func show_combo(peer_id: int, count: int) -> void:
	if count >= 3 and _hud and _hud.has_method("show_combo"):
		_hud.show_combo(peer_id, count)

# ─────────────────────────────────────────────
#  MODAL SYSTEM
# ─────────────────────────────────────────────
func open_modal(scene_path: String, modal_id: String = "") -> void:
	close_modal()
	var packed := load(scene_path) as PackedScene
	_active_modal = packed.instantiate() as Control
	_active_modal.set_meta("modal_id", modal_id)
	get_tree().current_scene.add_child(_active_modal)

func close_modal() -> void:
	if _active_modal:
		var id : String = _active_modal.get_meta("modal_id", "")
		_active_modal.queue_free()
		_active_modal = null
		emit_signal("modal_closed", id)

# ─────────────────────────────────────────────
#  WEBVIEW — M-Pesa / Anchor Interactive
# ─────────────────────────────────────────────
func open_webview(url: String) -> void:
	## Requires WebView plugin: https://github.com/Decapitated/Godot-WebView
	## On desktop (dev): opens default browser
	if OS.has_feature("mobile"):
		if Engine.has_singleton("WebView"):
			_webview = Engine.get_singleton("WebView")
			_webview.call("open", url)
		else:
			push_warning("UIManager: WebView singleton not found — install Godot WebView plugin")
	else:
		OS.shell_open(url)

func close_webview() -> void:
	if _webview:
		_webview.call("close")
		_webview = null

func prompt_wallet_sign(challenge: String, pubkey: String) -> void:
	## Opens Freighter (browser) or Albedo (mobile) for Stellar tx signing
	var sign_url := "https://albedo.link/sign?challenge=%s&pubkey=%s" % [challenge, pubkey]
	open_webview(sign_url)

# ─────────────────────────────────────────────
#  TOAST NOTIFICATIONS
# ─────────────────────────────────────────────
func toast(message: String, color: Color = Color.WHITE, duration: float = 2.5) -> void:
	_toast_queue.append({ "msg": message, "color": color, "dur": duration })
	if not _toast_active:
		_show_next_toast()

func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_active = false
		return
	_toast_active = true
	var data       := _toast_queue.pop_front() as Dictionary
	var label      := Label.new()
	label.text     = data["msg"]
	label.add_theme_color_override("font_color", data["color"])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Position at top of screen
	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 200
	toast_layer.add_child(label)
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.offset_top = 60
	get_tree().current_scene.add_child(toast_layer)
	await get_tree().create_timer(data["dur"]).timeout
	toast_layer.queue_free()
	_show_next_toast()

# ─────────────────────────────────────────────
#  TRANSITIONS
# ─────────────────────────────────────────────
func _fade_out() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 999
	fade_layer.add_child(overlay)
	get_tree().current_scene.add_child(fade_layer)
	var tween := get_tree().create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 0.3)
	await tween.finished
	fade_layer.queue_free()

func _fade_in() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 1)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 999
	fade_layer.add_child(overlay)
	get_tree().current_scene.add_child(fade_layer)
	var tween := get_tree().create_tween()
	tween.tween_property(overlay, "color:a", 0.0, 0.3)
	await tween.finished
	fade_layer.queue_free()

# ─────────────────────────────────────────────
#  ARENA EVENT HANDLERS
# ─────────────────────────────────────────────
func _on_round_started(round_num: int) -> void:
	show_round_banner(round_num)

func _on_round_ended(winner_id: int, reason: String) -> void:
	show_ko_banner(winner_id, reason)

func _on_match_ended(results: Dictionary) -> void:
	await get_tree().create_timer(3.0).timeout
	goto_scene("results")

func _on_combo_detected(peer_id: int, count: int) -> void:
	show_combo(peer_id, count)

func _on_player_eliminated(peer_id: int) -> void:
	toast("ELIMINATED!", Color(1, 0.2, 0.2), 2.0)
