# betting_panel.gd
# Attach to: res://scenes/ui/BettingPanel.tscn (CanvasLayer)
# Shown during match lobby / countdown. Hidden once round starts.

extends CanvasLayer

# ─────────────────────────────────────────────
#  NODE REFS
# ─────────────────────────────────────────────
@onready var fighter_list    : VBoxContainer = $Panel/FighterList
@onready var bet_amount_spin : SpinBox       = $Panel/BetAmount
@onready var currency_select : OptionButton  = $Panel/CurrencySelect
@onready var btn_confirm_bet : Button        = $Panel/BtnConfirmBet
@onready var btn_mpesa       : Button        = $Panel/BtnMPesa
@onready var balance_label   : Label         = $Panel/BalanceLabel
@onready var odds_labels     : Dictionary    = {}  # fighter_id → Label
@onready var status_label    : Label         = $Panel/StatusLabel

# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var _fight_id         : String  = ""
var _selected_fighter : String  = ""
var _fighter_data     : Array   = []
var _bet_confirmed    : bool    = false

const FIGHT_CARD := preload("res://scenes/ui/FighterOddsCard.tscn")

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	btn_confirm_bet.pressed.connect(_on_confirm_bet)
	btn_mpesa.pressed.connect(_on_mpesa_deposit)
	currency_select.add_item("USDC",  0)
	currency_select.add_item("XLM",   1)

	EconomyManager.wallet_balance_updated.connect(_on_balance_updated)
	EconomyManager.bet_confirmed.connect(_on_bet_confirmed)
	EconomyManager.bet_failed.connect(_on_bet_failed)
	ArenaManager.round_started.connect(_on_round_started)

	EconomyManager.refresh_balances()
	_load_fighters()
	_start_odds_refresh()

func _load_fighters() -> void:
	var file := FileAccess.open("res://fighters.json", FileAccess.READ)
	if not file: return
	var json      = JSON.parse_string(file.get_as_text())
	_fighter_data = json.get("archetypes", [])
	file.close()

	for f in _fighter_data:
		var card := FIGHT_CARD.instantiate()
		card.set_fighter(f["id"], f["display_name"])
		card.fighter_selected.connect(_on_fighter_selected.bind(f["id"]))
		fighter_list.add_child(card)
		odds_labels[f["id"]] = card.get_odds_label()

# ─────────────────────────────────────────────
#  ODDS REFRESH (poll contract every 8s)
# ─────────────────────────────────────────────
func _start_odds_refresh() -> void:
	var timer := Timer.new()
	add_child(timer)
	timer.wait_time = 8.0
	timer.timeout.connect(_refresh_odds)
	timer.start()
	_refresh_odds()

func _refresh_odds() -> void:
	if _fight_id.is_empty(): return
	for f in _fighter_data:
		var fid : String = f["id"]
		_fetch_odds_for(fid)

func _fetch_odds_for(fighter_id: String) -> void:
	var headers := ["Authorization: Bearer " + AuthManager.get_current_jwt()]
	var url     := "https://api.sfg.yourdomain.com/v1/bets/odds?fight_id=%s&fighter=%s" % [_fight_id, fighter_id]
	var req     := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body: PackedByteArray):
		req.queue_free()
		if code != 200: return
		var json       = JSON.parse_string(body.get_string_from_utf8())
		var fighter_p  : int = json.get("fighter_pool", 0)
		var total_p    : int = json.get("total_pool",   1)
		var pct        := float(fighter_p) / float(max(total_p, 1)) * 100.0
		var odds_text  := "%.1f%% (%.1fx)" % [pct, float(total_p) / float(max(fighter_p, 1))]
		if odds_labels.has(fighter_id):
			odds_labels[fighter_id].text = odds_text
	)
	req.request(url, headers, HTTPClient.METHOD_GET)

# ─────────────────────────────────────────────
#  BET PLACEMENT
# ─────────────────────────────────────────────
func _on_fighter_selected(fighter_id: String) -> void:
	_selected_fighter = fighter_id
	btn_confirm_bet.disabled = false

func _on_confirm_bet() -> void:
	if _selected_fighter.is_empty() or _bet_confirmed:
		return
	var amount : float = bet_amount_spin.value
	if amount <= 0:
		UIManager.toast("Enter a bet amount", Color.YELLOW)
		return
	status_label.text = "Placing bet..."
	btn_confirm_bet.disabled = true
	EconomyManager.place_bet(_fight_id, _selected_fighter, amount)

func _on_mpesa_deposit() -> void:
	var amount_kes : float = bet_amount_spin.value * 148.0   # Approx USDC → KES
	EconomyManager.initiate_mpesa_deposit(amount_kes, "sfg://mpesa_callback")

func _on_bet_confirmed(fight_id: String, amount: float) -> void:
	_bet_confirmed  = true
	status_label.text = "Bet locked! ✓ %.2f USDC on %s" % [amount, _selected_fighter]
	status_label.add_theme_color_override("font_color", Color.GREEN)
	UIManager.toast("Bet placed successfully!", Color.GREEN)

func _on_bet_failed(reason: String) -> void:
	btn_confirm_bet.disabled = false
	status_label.text = "Bet failed: " + reason
	status_label.add_theme_color_override("font_color", Color.RED)

func _on_balance_updated(xlm: float, usdc: float) -> void:
	balance_label.text = "%.2f USDC  |  %.2f XLM" % [usdc, xlm]

func _on_round_started(_round: int) -> void:
	# Hide betting during active round
	visible = false

func set_fight_id(fight_id: String) -> void:
	_fight_id = fight_id
