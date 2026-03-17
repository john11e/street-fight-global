# fighter_odds_card.gd
# Attach to: res://scenes/ui/FighterOddsCard.tscn (PanelContainer)
# Used in BettingPanel — shows fighter + live odds, clickable to select as bet target.

class_name FighterOddsCard
extends PanelContainer

signal fighter_selected(fighter_id: String)

@onready var name_label   : Label = $VBox/Name
@onready var odds_label   : Label = $VBox/Odds
@onready var pool_label   : Label = $VBox/Pool
@onready var portrait     : TextureRect = $VBox/Portrait
@onready var highlight    : Panel = $Highlight

var _fighter_id : String = ""

func _ready() -> void:
	gui_input.connect(_on_input)
	highlight.visible = false

func set_fighter(fighter_id: String, display_name: String) -> void:
	_fighter_id      = fighter_id
	name_label.text  = display_name
	odds_label.text  = "---"
	pool_label.text  = "Pool: 0 USDC"
	var tex_path := "res://assets/fighters/%s/portrait.png" % fighter_id
	if ResourceLoader.exists(tex_path):
		portrait.texture = load(tex_path)

func get_odds_label() -> Label:
	return odds_label

func update_odds(fighter_pool: int, total_pool: int) -> void:
	if total_pool <= 0:
		odds_label.text = "No bets yet"
		pool_label.text = "Pool: 0 USDC"
		return
	var pct      := float(fighter_pool) / float(total_pool) * 100.0
	var multiplier := float(total_pool) / float(max(fighter_pool, 1))
	odds_label.text = "%.1f%% · %.2fx payout" % [pct, multiplier]
	pool_label.text = "Pool: %d USDC" % (fighter_pool / 10_000_000)

func set_selected(is_selected: bool) -> void:
	highlight.visible = is_selected
	modulate = Color(1.15, 1.1, 0.9) if is_selected else Color.WHITE

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			emit_signal("fighter_selected", _fighter_id)
