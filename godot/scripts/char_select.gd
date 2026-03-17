# char_select.gd
# Attach to: res://scenes/ui/CharSelect.tscn (Control)

extends Control

# ─────────────────────────────────────────────
#  NODE REFS
# ─────────────────────────────────────────────
@onready var char_grid       : GridContainer = $CharGrid
@onready var preview_name    : Label         = $Preview/FighterName
@onready var preview_power   : Label         = $Preview/Stats/Power
@onready var preview_speed   : Label         = $Preview/Stats/Speed
@onready var preview_reach   : Label         = $Preview/Stats/Reach
@onready var preview_style   : Label         = $Preview/Style
@onready var btn_confirm     : Button        = $BtnConfirm
@onready var btn_back        : Button        = $BtnBack
@onready var waiting_label   : Label         = $WaitingLabel
@onready var room_code_label : Label         = $RoomCodeLabel

# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var _selected_fighter_id : String = ""
var _fighter_data        : Array  = []
var _confirmed           : bool   = false

const FIGHTER_CARD := preload("res://scenes/ui/FighterCard.tscn")

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	btn_confirm.pressed.connect(_on_confirm)
	btn_back.pressed.connect(_on_back)
	waiting_label.visible    = false

	# Show room code if online match
	var room_id := NetworkManager._room_id
	if not room_id.is_empty():
		room_code_label.text    = "ROOM: " + room_id
		room_code_label.visible = true
	else:
		room_code_label.visible = false

	_load_fighters()

	NetworkManager.room_joined.connect(_on_room_joined)

# ─────────────────────────────────────────────
#  FIGHTER LOADING
# ─────────────────────────────────────────────
func _load_fighters() -> void:
	var file := FileAccess.open("res://fighters.json", FileAccess.READ)
	if not file:
		push_error("CharSelect: fighters.json not found")
		return
	var json   = JSON.parse_string(file.get_as_text())
	_fighter_data = json.get("archetypes", [])
	file.close()

	for fighter in _fighter_data:
		var card := FIGHTER_CARD.instantiate()
		card.set_fighter_data(fighter)
		card.selected.connect(_on_fighter_selected.bind(fighter["id"]))
		char_grid.add_child(card)

	# Auto-select first fighter
	if not _fighter_data.is_empty():
		_on_fighter_selected(_fighter_data[0]["id"])

# ─────────────────────────────────────────────
#  SELECTION
# ─────────────────────────────────────────────
func _on_fighter_selected(fighter_id: String) -> void:
	_selected_fighter_id = fighter_id
	# Update preview panel
	for f in _fighter_data:
		if f["id"] == fighter_id:
			var stats = f["stats"]
			preview_name.text   = f["display_name"]
			preview_power.text  = "PWR: %d" % stats["power"]
			preview_speed.text  = "SPD: %d" % stats["speed"]
			preview_reach.text  = "RCH: %d cm" % stats["reach_cm"]
			preview_style.text  = f["combat_profile"]["style"].replace("_", " ").to_upper()
	# Highlight selected card
	for card in char_grid.get_children():
		if card.has_method("set_selected"):
			card.set_selected(card.get_meta("fighter_id","") == fighter_id)

# ─────────────────────────────────────────────
#  CONFIRM
# ─────────────────────────────────────────────
func _on_confirm() -> void:
	if _selected_fighter_id.is_empty() or _confirmed:
		return
	_confirmed = true
	btn_confirm.disabled = true

	# Store selection globally
	GameState.local_fighter_id = _selected_fighter_id

	if GameState.vs_cpu:
		UIManager.goto_scene("game")
		return

	# Online: signal server our fighter choice
	NetworkManager.send_ready(_selected_fighter_id)
	waiting_label.visible = true
	waiting_label.text    = "Waiting for opponent..."

func _on_room_joined(room_id: String, session_id: String) -> void:
	room_code_label.text    = "ROOM: " + room_id
	room_code_label.visible = true

func _on_back() -> void:
	UIManager.goto_scene("main_menu")
