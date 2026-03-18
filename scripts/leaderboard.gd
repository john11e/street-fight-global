# leaderboard.gd
# Attach to: res://scenes/ui/Leaderboard.tscn (Control/Modal)

extends Control

@onready var list_container : VBoxContainer = $Panel/Scroll/List
@onready var btn_close      : Button        = $Panel/BtnClose
@onready var tab_bar        : TabBar        = $Panel/TabBar
@onready var loading_label  : Label         = $Panel/Loading

const ROW_SCENE := preload("res://scenes/ui/LeaderboardRow.tscn")

func _ready() -> void:
	btn_close.pressed.connect(UIManager.close_modal)
	tab_bar.tab_changed.connect(_on_tab_changed)
	_fetch_leaderboard("wins")

func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _fetch_leaderboard("wins")
		1: _fetch_leaderboard("earnings")
		2: _fetch_leaderboard("combo")

func _fetch_leaderboard(metric: String) -> void:
	loading_label.visible = true
	for child in list_container.get_children():
		child.queue_free()

	var headers := ["Authorization: Bearer " + AuthManager.get_current_jwt()]
	var url     := "https://api.sfg.yourdomain.com/v1/leaderboard?metric=%s&limit=20" % metric
	var req     := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_data.bind(req))
	req.request(url, headers, HTTPClient.METHOD_GET)

func _on_data(result: int, code: int, _h, body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	loading_label.visible = false
	if code != 200:
		loading_label.text    = "Failed to load leaderboard"
		loading_label.visible = true
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	var entries : Array = json.get("entries", [])
	for i in range(entries.size()):
		var entry : Dictionary = entries[i]
		var row   := ROW_SCENE.instantiate()
		if row.has_method("set_entry"):
			row.set_entry(i + 1, entry.get("display_name","?"), entry.get("value", 0))
		list_container.add_child(row)
