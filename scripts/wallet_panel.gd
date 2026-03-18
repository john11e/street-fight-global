# wallet_panel.gd
# Attach to: res://scenes/ui/WalletPanel.tscn (Control/Modal)
# Shows balances, deposit options, and withdraw flow.

extends Control

@onready var xlm_label      : Label    = $Panel/VBox/XLMBalance
@onready var usdc_label     : Label    = $Panel/VBox/USDCBalance
@onready var pubkey_label   : Label    = $Panel/VBox/Pubkey
@onready var deposit_amount : SpinBox  = $Panel/VBox/DepositRow/Amount
@onready var btn_mpesa      : Button   = $Panel/VBox/DepositRow/BtnMPesa
@onready var btn_card       : Button   = $Panel/VBox/DepositRow/BtnCard
@onready var btn_close      : Button   = $Panel/BtnClose
@onready var status_label   : Label    = $Panel/VBox/Status
@onready var qr_texture     : TextureRect = $Panel/VBox/QRCode

func _ready() -> void:
	btn_mpesa.pressed.connect(_on_mpesa)
	btn_card.pressed.connect(_on_card)
	btn_close.pressed.connect(UIManager.close_modal)

	EconomyManager.wallet_balance_updated.connect(_on_balance_updated)
	EconomyManager.bet_confirmed.connect(func(_f, _a): status_label.text = "Deposit confirmed!")

	_show_wallet_info()
	EconomyManager.refresh_balances()

func _show_wallet_info() -> void:
	var pubkey := AuthManager.get_stellar_pubkey()
	if pubkey.length() > 10:
		pubkey_label.text = pubkey.substr(0, 6) + "..." + pubkey.substr(-6)
	else:
		pubkey_label.text = "Not connected"

func _on_balance_updated(xlm: float, usdc: float) -> void:
	xlm_label.text  = "XLM:  %.4f" % xlm
	usdc_label.text = "USDC: %.4f" % usdc

func _on_mpesa() -> void:
	var kes_amount := deposit_amount.value * 148.0
	status_label.text = "Opening M-Pesa..."
	EconomyManager.initiate_mpesa_deposit(kes_amount, "sfg://wallet_callback")

func _on_card() -> void:
	# Opens Ramp.network widget in WebView
	var ramp_url := "https://app.ramp.network/?userAddress=%s&swapAsset=STELLAR_USDC&fiatCurrency=USD" % AuthManager.get_stellar_pubkey()
	UIManager.open_webview(ramp_url)
	status_label.text = "Opening card payment..."
