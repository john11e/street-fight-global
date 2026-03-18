# economy_manager.gd
# Autoload: EconomyManager
# Handles the full payment pipeline:
#   KES (M-Pesa) → Stellar Anchor → XLM/USDC → Soroban Escrow
#   Bank/Card (Stripe) → XLM/USDC → Soroban Escrow

extends Node

# ─────────────────────────────────────────────
#  SIGNALS
# ─────────────────────────────────────────────
signal bet_confirmed(fight_id: String, amount_xlm: float)
signal bet_failed(reason: String)
signal payout_received(amount_xlm: float, fiat_equiv: String)
signal wallet_balance_updated(xlm: float, usdc: float)

# ─────────────────────────────────────────────
#  CONSTANTS — Replace with real endpoints
# ─────────────────────────────────────────────
const ECONOMY_API     := "https://api.sfg.yourdomain.com/v1"
const HORIZON_URL     := "https://horizon.stellar.org"          # Testnet: horizon-testnet.stellar.org
const SOROBAN_RPC     := "https://soroban-testnet.stellar.org"
const CONTRACT_ID     := "CXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"  # Deploy ID
const ANCHOR_SEP24    := "https://your-anchor.com/.well-known/stellar.toml"    # SEP-24 anchor
const PLATFORM_FEE_BP := 200   # 2% — must match contract fee_bps

# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var _jwt_token      : String = ""
var _stellar_pubkey : String = ""
var _xlm_balance    : float  = 0.0
var _usdc_balance   : float  = 0.0
var _active_bets    : Dictionary = {}   # fight_id → bet_info

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	AuthManager.authenticated.connect(_on_authenticated)

func _on_authenticated(jwt: String, pubkey: String) -> void:
	_jwt_token      = jwt
	_stellar_pubkey = pubkey
	refresh_balances()

# ─────────────────────────────────────────────
#  WALLET BALANCE
# ─────────────────────────────────────────────
func refresh_balances() -> void:
	var url := "%s/accounts/%s" % [HORIZON_URL, _stellar_pubkey]
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_balance_response.bind(req))
	req.request(url, [], HTTPClient.METHOD_GET)

func _on_balance_response(result, code, _headers, body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	if code != 200:
		push_error("EconomyManager: Balance fetch failed — HTTP %d" % code)
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json:
		return
	for balance in json.get("balances", []):
		var asset  : String = balance.get("asset_type", "")
		var amount : float  = float(balance.get("balance", "0"))
		if asset == "native":
			_xlm_balance = amount
		elif balance.get("asset_code","") == "USDC":
			_usdc_balance = amount
	emit_signal("wallet_balance_updated", _xlm_balance, _usdc_balance)

# ─────────────────────────────────────────────
#  M-PESA → STELLAR PIPELINE
# ─────────────────────────────────────────────
##
## PIPELINE OVERVIEW (SEP-24 Deposit Flow):
##
##  [1] Player initiates M-Pesa deposit in-app
##  [2] App calls anchor's /transactions/deposit/interactive (SEP-24)
##  [3] Anchor returns a URL → WebView opens Safaricom payment page
##  [4] Player pays KES via M-Pesa STK Push on their phone
##  [5] Anchor confirms M-Pesa receipt → converts KES→USDC at spot rate
##  [6] Anchor sends USDC to player's Stellar account (player_pubkey)
##  [7] App polls Horizon: confirms USDC received
##  [8] App calls place_bet_usdc() → signs Soroban tx → submits
##  [9] Soroban contract locks USDC in escrow
## [10] Fight ends → contract auto-distributes winnings in USDC
## [11] Winner calls withdraw → anchor converts USDC→KES → M-Pesa sends KES
##

func initiate_mpesa_deposit(amount_kes: float, callback_url: String) -> void:
	## Step 2-3: SEP-24 interactive deposit
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + _jwt_token
	]
	var body := JSON.stringify({
		"asset_code":   "USDC",
		"asset_issuer": "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN",
		"account":      _stellar_pubkey,
		"amount":       amount_kes,
		"currency":     "KES",
		"email":        AuthManager.get_user_email(),
	})
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_sep24_response.bind(req, amount_kes))
	req.request(ECONOMY_API + "/anchor/deposit", headers, HTTPClient.METHOD_POST, body)

func _on_sep24_response(result, code, _h, body: PackedByteArray, req: HTTPRequest, amount_kes: float) -> void:
	req.queue_free()
	if code != 200:
		emit_signal("bet_failed", "Anchor unreachable")
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	# Open WebView with anchor URL for M-Pesa STK Push
	var interactive_url : String = json.get("url", "")
	if interactive_url.is_empty():
		emit_signal("bet_failed", "No anchor URL returned")
		return
	UIManager.open_webview(interactive_url)
	# Poll for USDC credit arrival
	_poll_for_deposit(json.get("id",""), amount_kes)

func _poll_for_deposit(tx_id: String, amount_kes: float) -> void:
	## Poll anchor transaction status every 3 seconds (max 10 min)
	var attempts := 0
	var timer    := Timer.new()
	add_child(timer)
	timer.wait_time = 3.0
	timer.timeout.connect(func():
		attempts += 1
		if attempts > 200:  # 10 min timeout
			timer.queue_free()
			emit_signal("bet_failed", "Deposit timeout")
			return
		_check_anchor_tx(tx_id, amount_kes, timer)
	)
	timer.start()

func _check_anchor_tx(tx_id: String, amount_kes: float, timer: Timer) -> void:
	var url := ECONOMY_API + "/anchor/transaction/" + tx_id
	var req  := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body: PackedByteArray):
		req.queue_free()
		if code != 200: return
		var json = JSON.parse_string(body.get_string_from_utf8())
		var status : String = json.get("transaction", {}).get("status", "")
		if status == "completed":
			timer.queue_free()
			UIManager.close_webview()
			refresh_balances()
			emit_signal("bet_confirmed", "", json.get("usdc_credited", 0.0))
	)
	req.request(url, ["Authorization: Bearer " + _jwt_token], HTTPClient.METHOD_GET)

# ─────────────────────────────────────────────
#  PLACE BET (POST DEPOSIT)
# ─────────────────────────────────────────────
func place_bet(fight_id: String, fighter_id: String, amount_usdc: float) -> void:
	## Constructs and submits Soroban transaction via backend signing service.
	## The backend holds operator keypair for fee payment; player signs the bet tx.
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + _jwt_token
	]
	var body := JSON.stringify({
		"fight_id":   fight_id,
		"fighter_id": fighter_id,
		"amount":     int(amount_usdc * 10_000_000),   # Stellar uses stroops (7 decimals)
		"bettor":     _stellar_pubkey,
		"contract":   CONTRACT_ID,
	})
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_bet_tx_built.bind(req, fight_id, fighter_id, amount_usdc))
	req.request(ECONOMY_API + "/bets/build_tx", headers, HTTPClient.METHOD_POST, body)

func _on_bet_tx_built(result, code, _h, body: PackedByteArray, req: HTTPRequest,
					  fight_id: String, fighter_id: String, amount_usdc: float) -> void:
	req.queue_free()
	if code != 200:
		emit_signal("bet_failed", "Failed to build transaction")
		return
	var json       = JSON.parse_string(body.get_string_from_utf8())
	var xdr_tx     : String = json.get("xdr", "")
	## In production: use Freighter wallet (browser) or Albedo (mobile WebView)
	## to sign the XDR and submit. Here we call the platform signing proxy.
	_submit_signed_tx(xdr_tx, fight_id, fighter_id, amount_usdc)

func _submit_signed_tx(xdr: String, fight_id: String, fighter_id: String, amount_usdc: float) -> void:
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + _jwt_token
	]
	var body := JSON.stringify({ "xdr": xdr, "fight_id": fight_id })
	var req  := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, resp_body: PackedByteArray):
		req.queue_free()
		if code == 200:
			_active_bets[fight_id] = {
				"fighter_id": fighter_id,
				"amount":     amount_usdc,
				"status":     "locked"
			}
			emit_signal("bet_confirmed", fight_id, amount_usdc)
		else:
			emit_signal("bet_failed", "Transaction rejected by Soroban")
	)
	req.request(ECONOMY_API + "/bets/submit", headers, HTTPClient.METHOD_POST, body)

# ─────────────────────────────────────────────
#  SETTLE BETS (called by ArenaManager)
# ─────────────────────────────────────────────
func settle_bets(winner_peer_id: int, match_results: Dictionary) -> void:
	## Operator calls Soroban contract settle_fight() via backend.
	var winner_session : String = match_results.get("winner_session_id", "")
	var fight_id       : String = match_results.get("fight_id", "")
	var winner_fighter : String = match_results.get("winner_fighter_id", "")
	if fight_id.is_empty() or winner_fighter.is_empty():
		push_error("EconomyManager: settle_bets called with invalid data")
		return

	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + _jwt_token
	]
	var body := JSON.stringify({
		"fight_id":   fight_id,
		"winner_id":  winner_fighter,
	})
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, resp_body: PackedByteArray):
		req.queue_free()
		if code == 200:
			refresh_balances()
			var json   = JSON.parse_string(resp_body.get_string_from_utf8())
			var payout = json.get("payout_usdc", 0.0)
			var fiat   = json.get("fiat_equiv", "~%.2f KES" % (payout * 148.0))
			emit_signal("payout_received", payout, fiat)
		else:
			push_error("EconomyManager: Settle transaction failed")
	)
	req.request(ECONOMY_API + "/bets/settle", headers, HTTPClient.METHOD_POST, body)

# ─────────────────────────────────────────────
#  GETTERS
# ─────────────────────────────────────────────
func get_xlm_balance()  -> float: return _xlm_balance
func get_usdc_balance() -> float: return _usdc_balance
func get_active_bet(fight_id: String) -> Dictionary:
	return _active_bets.get(fight_id, {})
