# main_menu.gd
# Attach to: res://scenes/ui/MainMenu.tscn (Control)

extends Control

# ─────────────────────────────────────────────
#  NODE REFS
# ─────────────────────────────────────────────
@onready var btn_play_online  : Button = $VBox/BtnPlayOnline
@onready var btn_vs_cpu       : Button = $VBox/BtnVsCPU
@onready var btn_leaderboard  : Button = $VBox/BtnLeaderboard
@onready var btn_wallet       : Button = $VBox/BtnWallet
@onready var btn_settings     : Button = $VBox/BtnSettings
@onready var label_player     : Label  = $Header/PlayerName
@onready var label_balance    : Label  = $Header/Balance
@onready var login_panel      : Control = $LoginPanel
@onready var join_panel       : Control = $JoinPanel
@onready var room_code_input  : LineEdit = $JoinPanel/RoomCodeInput

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	btn_play_online.pressed.connect(_on_play_online)
	btn_vs_cpu.pressed.connect(_on_vs_cpu)
	btn_leaderboard.pressed.connect(_on_leaderboard)
	btn_wallet.pressed.connect(_on_wallet)
	btn_settings.pressed.connect(_on_settings)

	if AuthManager.is_authenticated():
		_show_logged_in()
	else:
		_show_login_prompt()
		AuthManager.authenticated.connect(_on_authenticated)

	EconomyManager.wallet_balance_updated.connect(_on_balance_updated)

# ─────────────────────────────────────────────
#  BUTTON HANDLERS
# ─────────────────────────────────────────────
func _on_play_online() -> void:
	if not AuthManager.is_authenticated():
		UIManager.toast("Please log in to play online", Color.YELLOW)
		return
	join_panel.visible = not join_panel.visible

func _on_join_with_code() -> void:
	var code : String = room_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		# Create a new room
		NetworkManager.join_room({ "create": true })
	else:
		NetworkManager.join_room({ "roomId": code })
	UIManager.goto_scene("char_select")

func _on_vs_cpu() -> void:
	GameState.vs_cpu = true
	UIManager.goto_scene("char_select")

func _on_leaderboard() -> void:
	UIManager.open_modal("res://scenes/ui/Leaderboard.tscn", "leaderboard")

func _on_wallet() -> void:
	UIManager.open_modal("res://scenes/ui/WalletPanel.tscn", "wallet")

func _on_settings() -> void:
	UIManager.open_modal("res://scenes/ui/Settings.tscn", "settings")

# ─────────────────────────────────────────────
#  STATE DISPLAY
# ─────────────────────────────────────────────
func _show_logged_in() -> void:
	login_panel.visible = false
	label_player.text   = AuthManager.get_display_name()
	EconomyManager.refresh_balances()

func _show_login_prompt() -> void:
	login_panel.visible = true

func _on_authenticated(_jwt: String, _pubkey: String) -> void:
	_show_logged_in()

func _on_balance_updated(xlm: float, usdc: float) -> void:
	label_balance.text = "%.2f USDC  |  %.2f XLM" % [usdc, xlm]
