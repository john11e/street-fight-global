# fighter_card.gd
# Attach to: res://scenes/ui/FighterCard.tscn (PanelContainer)
# Used in CharSelect screen — one card per fighter.

class_name FighterCard
extends PanelContainer

signal selected(fighter_id: String)

@onready var name_label    : Label         = $VBox/Name
@onready var style_label   : Label         = $VBox/Style
@onready var power_bar     : ProgressBar   = $VBox/Stats/PowerBar
@onready var speed_bar     : ProgressBar   = $VBox/Stats/SpeedBar
@onready var portrait      : TextureRect   = $VBox/Portrait
@onready var select_border : Panel         = $SelectBorder

var _fighter_id : String = ""

func _ready() -> void:
	gui_input.connect(_on_input)
	select_border.visible = false

func set_fighter_data(data: Dictionary) -> void:
	_fighter_id         = data.get("id", "")
	set_meta("fighter_id", _fighter_id)
	name_label.text     = data.get("display_name", "")
	var stats           = data.get("stats", {})
	var profile         = data.get("combat_profile", {})
	style_label.text    = profile.get("style", "").replace("_", " ").to_upper()
	power_bar.value     = stats.get("power", 0)
	speed_bar.value     = stats.get("speed", 0)
	# Load portrait texture if it exists
	var tex_path := "res://assets/fighters/%s/portrait.png" % _fighter_id
	if ResourceLoader.exists(tex_path):
		portrait.texture = load(tex_path)

func set_selected(is_selected: bool) -> void:
	select_border.visible = is_selected
	if is_selected:
		modulate = Color(1.15, 1.15, 1.0)
	else:
		modulate = Color.WHITE

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			emit_signal("selected", _fighter_id)
