# results.gd
# Attach to: res://scenes/ui/Results.tscn (Control)
# Displays match winner, scores, payout info, and rematch/menu options.

extends Control

@onready var winner_label    : Label  = $VBox/WinnerName
@onready var reason_label    : Label  = $VBox/Reason
@onready var scores_container: VBoxContainer = $VBox/Scores
@onready var payout_label    : Label  = $VBox/Payout
@onready var btn_rematch     : Button = $Buttons/BtnRematch
@onready var btn_menu        : Button = $Buttons/BtnMenu
@onready var btn_share       : Button = $Buttons/BtnShare

func _ready() -> void:
	btn_rematch.pressed.connect(_on_rematch)
	btn_menu.pressed.connect(_on_menu)
	btn_share.pressed.connect(_on_share)

	EconomyManager.payout_received.connect(_on_payout)

	_populate_results()

func _populate_results() -> void:
	var winner_id := GameState.last_winner_id
	var scores    := GameState.last_scores

	if winner_id >= 0:
		winner_label.text = "WINNER: " + NetworkManager.get_session_id()
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.0))
	else:
		winner_label.text = "DRAW"
		winner_label.add_theme_color_override("font_color", Color.GRAY)

	reason_label.text = "Rounds played: %d" % GameState.last_round_count

	# Build score rows
	for peer_id in scores:
		var row   := HBoxContainer.new()
		var label := Label.new()
		label.text = "Player %s: %d wins" % [str(peer_id).substr(0, 6), scores[peer_id]]
		row.add_child(label)
		scores_container.add_child(row)

	payout_label.text = "Calculating payout..."

func _on_payout(amount_usdc: float, fiat_equiv: String) -> void:
	if amount_usdc > 0:
		payout_label.text = "You won: %.2f USDC (%s)" % [amount_usdc, fiat_equiv]
		payout_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		payout_label.text = "Better luck next time."
		payout_label.add_theme_color_override("font_color", Color.GRAY)

func _on_rematch() -> void:
	GameState.reset_match()
	UIManager.goto_scene("char_select")

func _on_menu() -> void:
	GameState.reset_match()
	UIManager.goto_scene("main_menu")

func _on_share() -> void:
	var msg := "I just played Street Fight Global! Winner: %s — %d USDC prize pool" % [
		winner_label.text, int(EconomyManager.get_usdc_balance())
	]
	DisplayServer.clipboard_set(msg)
	UIManager.toast("Result copied to clipboard!", Color.CYAN)
