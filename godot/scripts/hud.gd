# hud.gd
# Attach to: res://scenes/ui/HUD.tscn (CanvasLayer)
# Manages all in-game heads-up display elements for up to 10 players.

extends CanvasLayer

# ─────────────────────────────────────────────
#  NODE REFS
# ─────────────────────────────────────────────
@onready var timer_label    : Label      = $TopBar/TimerLabel
@onready var round_label    : Label      = $TopBar/RoundLabel
@onready var round_banner   : Control    = $RoundBanner
@onready var banner_label   : Label      = $RoundBanner/Label
@onready var ko_banner      : Control    = $KOBanner
@onready var ko_label       : Label      = $KOBanner/Label
@onready var combo_label    : Label      = $ComboLabel
@onready var hp_bars_p1     : HBoxContainer = $HPBarsLeft
@onready var hp_bars_p2     : HBoxContainer = $HPBarsRight

# Dynamically created HP bar entries: peer_id → ProgressBar
var _hp_bars    : Dictionary = {}
var _score_dots : Dictionary = {}

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	UIManager.register_hud(self)
	round_banner.visible = false
	ko_banner.visible    = false
	combo_label.visible  = false

# ─────────────────────────────────────────────
#  ROUND BANNER
# ─────────────────────────────────────────────
func show_round_banner(round_num: int) -> void:
	banner_label.text = "ROUND %d" % round_num
	round_banner.visible = true
	round_banner.modulate.a = 1.0
	await get_tree().create_timer(1.8).timeout
	var tween := create_tween()
	tween.tween_property(round_banner, "modulate:a", 0.0, 0.5)
	await tween.finished
	round_banner.visible = false

# ─────────────────────────────────────────────
#  KO BANNER
# ─────────────────────────────────────────────
func show_ko_banner(winner_peer_id: int, reason: String) -> void:
	match reason:
		"KO":       ko_label.text = "K.O.!"
		"TIME_UP":  ko_label.text = "TIME!"
		"DOUBLE_KO":ko_label.text = "DRAW!"
		_:          ko_label.text = reason
	ko_banner.visible    = true
	ko_banner.modulate.a = 1.0
	ko_banner.scale      = Vector2(0.4, 0.4)
	var tween := create_tween()
	tween.tween_property(ko_banner, "scale",       Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(2.0)
	tween.tween_property(ko_banner, "modulate:a",  0.0,               0.4)
	await tween.finished
	ko_banner.visible = false

# ─────────────────────────────────────────────
#  TIMER
# ─────────────────────────────────────────────
func update_timer(seconds: float) -> void:
	var s := int(seconds)
	timer_label.text = "%02d" % s
	if s <= 10:
		timer_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	else:
		timer_label.add_theme_color_override("font_color", Color.WHITE)

# ─────────────────────────────────────────────
#  HP BARS — dynamically spawned per player
# ─────────────────────────────────────────────
func register_player(peer_id: int, fighter_name: String, is_p1_side: bool) -> void:
	var bar_root := VBoxContainer.new()
	var name_label := Label.new()
	name_label.text = fighter_name
	name_label.add_theme_font_size_override("font_size", 14)
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value     = 100
	bar.custom_minimum_size = Vector2(160, 12)
	bar.show_percentage = false
	bar_root.add_child(name_label)
	bar_root.add_child(bar)
	if is_p1_side:
		hp_bars_p1.add_child(bar_root)
	else:
		hp_bars_p2.add_child(bar_root)
	_hp_bars[peer_id] = bar

func update_hp_bar(peer_id: int, hp: float, max_hp: float) -> void:
	if not _hp_bars.has(peer_id): return
	var bar : ProgressBar = _hp_bars[peer_id]
	bar.max_value = max_hp
	var tween := create_tween()
	tween.tween_property(bar, "value", hp, 0.15)
	# Color shift: green → yellow → red
	var pct := hp / max_hp
	if pct > 0.5:
		bar.modulate = Color.GREEN
	elif pct > 0.25:
		bar.modulate = Color.YELLOW
	else:
		bar.modulate = Color.RED

# ─────────────────────────────────────────────
#  COMBO DISPLAY
# ─────────────────────────────────────────────
func show_combo(peer_id: int, count: int) -> void:
	if count < 3: return
	combo_label.text    = "%d HIT COMBO!" % count
	combo_label.visible = true
	combo_label.modulate.a = 1.0
	combo_label.scale      = Vector2(0.6, 0.6)
	var tween := create_tween()
	tween.tween_property(combo_label, "scale",      Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(0.8)
	tween.tween_property(combo_label, "modulate:a", 0.0,               0.3)
	await tween.finished
	combo_label.visible = false

# ─────────────────────────────────────────────
#  ROUND / SCORE UPDATE
# ─────────────────────────────────────────────
func set_round(round_num: int) -> void:
	round_label.text = "ROUND %d" % round_num
