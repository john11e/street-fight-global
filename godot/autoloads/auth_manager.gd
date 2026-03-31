
extends Node

# ─────────────────────────────────────────────
#  SIGNALS
# ─────────────────────────────────────────────
signal authenticated(jwt: String, stellar_pubkey: String)
signal auth_failed(reason: String)
signal logged_out

# ─────────────────────────────────────────────
#  CONSTANTS
# ─────────────────────────────────────────────
const AUTH_API        := "https://api.sfg.yourdomain.com/v1/auth"
const STORAGE_KEY_JWT := "sfg_jwt"
const STORAGE_KEY_PUB := "sfg_stellar_pubkey"
const TOKEN_REFRESH_S := 3600.0   # Refresh JWT every hour

# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var _jwt          : String = ""
var _pubkey       : String = ""
var _user_id      : String = ""
var _user_email   : String = ""
var _display_name : String = ""
var _refresh_timer: float  = 0.0
var _is_authed    : bool   = false

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	_load_stored_session()

func _process(delta: float) -> void:
	if not _is_authed:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_jwt()

# ─────────────────────────────────────────────
#  PUBLIC API
# ─────────────────────────────────────────────
func login(email: String, password: String) -> void:
	var headers := ["Content-Type: application/json"]
	var body    := JSON.stringify({ "email": email, "password": password })
	var req     := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_login_response.bind(req))
	req.request(AUTH_API + "/login", headers, HTTPClient.METHOD_POST, body)

func login_wallet(stellar_pubkey: String, signed_challenge: String) -> void:
	## Walletless flow: sign a server challenge with Stellar keypair
	var headers := ["Content-Type: application/json"]
	var body    := JSON.stringify({
		"pubkey":    stellar_pubkey,
		"signature": signed_challenge,
		"challenge": _current_challenge
	})
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_login_response.bind(req))
	req.request(AUTH_API + "/login_wallet", headers, HTTPClient.METHOD_POST, body)

func logout() -> void:
	_jwt          = ""
	_pubkey       = ""
	_user_id      = ""
	_is_authed    = false
	_save_session("", "")
	emit_signal("logged_out")

func get_current_jwt() -> String:
	return _jwt

func get_stellar_pubkey() -> String:
	return _pubkey

func get_user_email() -> String:
	return _user_email

func get_display_name() -> String:
	return _display_name

func is_authenticated() -> bool:
	return _is_authed and not _jwt.is_empty()

# ─────────────────────────────────────────────
#  CHALLENGE (for wallet login)
# ─────────────────────────────────────────────
var _current_challenge: String = ""

func request_wallet_challenge(pubkey: String) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body: PackedByteArray):
		req.queue_free()
		if code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			_current_challenge = json.get("challenge", "")
			# UIManager opens wallet signing flow
			UIManager.prompt_wallet_sign(_current_challenge, pubkey)
	)
	req.request(AUTH_API + "/challenge?pubkey=" + pubkey, [], HTTPClient.METHOD_GET)

# ─────────────────────────────────────────────
#  RESPONSE HANDLERS
# ─────────────────────────────────────────────
func _on_login_response(result: int, code: int, _headers: PackedStringArray,
						body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	if code != 200:
		var msg := "Login failed (HTTP %d)" % code
		emit_signal("auth_failed", msg)
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json:
		emit_signal("auth_failed", "Invalid server response")
		return

	_jwt          = json.get("token",        "")
	_pubkey       = json.get("stellar_pubkey","")
	_user_id      = json.get("user_id",      "")
	_user_email   = json.get("email",        "")
	_display_name = json.get("display_name", "Player")
	_is_authed    = true
	_refresh_timer = TOKEN_REFRESH_S

	_save_session(_jwt, _pubkey)
	emit_signal("authenticated", _jwt, _pubkey)

func _refresh_jwt() -> void:
	_refresh_timer = TOKEN_REFRESH_S
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + _jwt
	]
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body: PackedByteArray):
		req.queue_free()
		if code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			_jwt = json.get("token", _jwt)
			_save_session(_jwt, _pubkey)
		else:
			logout()   # Force re-login on refresh failure
	)
	req.request(AUTH_API + "/refresh", headers, HTTPClient.METHOD_POST, "")

# ─────────────────────────────────────────────
#  PERSISTENT SESSION
# ─────────────────────────────────────────────
func _save_session(jwt: String, pubkey: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "jwt",    jwt)
	cfg.set_value("session", "pubkey", pubkey)
	cfg.save("user://session.cfg")

func _load_stored_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		return
	_jwt    = cfg.get_value("session", "jwt",    "")
	_pubkey = cfg.get_value("session", "pubkey", "")
	if not _jwt.is_empty():
		# Validate stored token
		_validate_stored_jwt()

func _validate_stored_jwt() -> void:
	var headers := ["Authorization: Bearer " + _jwt]
	var req     := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body: PackedByteArray):
		req.queue_free()
		if code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			_user_id      = json.get("user_id",      "")
			_user_email   = json.get("email",        "")
			_display_name = json.get("display_name", "Player")
			_is_authed    = true
			_refresh_timer = TOKEN_REFRESH_S
			emit_signal("authenticated", _jwt, _pubkey)
		else:
			_save_session("", "")   # Clear stale token
	)
	req.request(AUTH_API + "/validate", headers, HTTPClient.METHOD_GET)
