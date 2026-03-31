# Autoload: NetworkManager
# Bridges Godot 4 to the Colyseus authoritative server.
# Uses WebSocketPeer — no third-party addon required.

extends Node

# ─────────────────────────────────────────────
#  SIGNALS
# ─────────────────────────────────────────────
signal connected_to_server
signal disconnected_from_server
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal state_patch_received(patch: Dictionary)
signal room_joined(room_id: String, session_id: String)
signal room_error(code: int, message: String)

# ─────────────────────────────────────────────
#  CONSTANTS
# ─────────────────────────────────────────────
const SERVER_URL    := "wss://sfg-colyseus.yourserver.com"   # Replace with real URL
const ROOM_NAME     := "arena"
const RECONNECT_MAX := 5
const HEARTBEAT_S   := 5.0
const MSG = {
	JOIN_ROOM     = 0x01,
	LEAVE_ROOM    = 0x02,
	INPUT_STATE   = 0x03,
	CHAT          = 0x04,
	READY         = 0x05,
	SPECTATE      = 0x06,
}

# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var _socket        : WebSocketPeer = WebSocketPeer.new()
var _session_id    : String        = ""
var _room_id       : String        = ""
var _connected     : bool          = false
var _reconnects    : int           = 0
var _hb_timer      : float         = 0.0
var _input_buffer  : Array[Dictionary] = []   # Queued inputs for the server
var _last_seq      : int           = 0        # For input sequence ordering

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			_hb_timer -= delta
			if _hb_timer <= 0.0:
				_send_heartbeat()
				_hb_timer = HEARTBEAT_S
			_flush_input_buffer()
			_receive_messages()
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				emit_signal("disconnected_from_server")
				_try_reconnect()

# ─────────────────────────────────────────────
#  PUBLIC API
# ─────────────────────────────────────────────
func connect_to_server(jwt_token: String) -> void:
	var url := "%s/?token=%s" % [SERVER_URL, jwt_token]
	var err := _socket.connect_to_url(url)
	if err != OK:
		push_error("NetworkManager: WebSocket connect failed — %s" % err)
		return
	await _wait_for_connection()

func join_room(options: Dictionary = {}) -> void:
	_send({
		"type": MSG.JOIN_ROOM,
		"room": ROOM_NAME,
		"options": options
	})

func send_input(input: Dictionary) -> void:
	_last_seq += 1
	var packet := input.duplicate()
	packet["seq"] = _last_seq
	packet["ts"]  = Time.get_ticks_msec()
	_input_buffer.append(packet)

func send_ready(fighter_id: String) -> void:
	_send({ "type": MSG.READY, "fighter_id": fighter_id })

func disconnect_gracefully() -> void:
	_send({ "type": MSG.LEAVE_ROOM })
	await get_tree().create_timer(0.3).timeout
	_socket.close(1000, "client_quit")

# ─────────────────────────────────────────────
#  SENDING
# ─────────────────────────────────────────────
func _send(data: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_warning("NetworkManager: Attempted send while disconnected")
		return
	var json := JSON.stringify(data)
	_socket.send_text(json)

func _flush_input_buffer() -> void:
	# Send all queued inputs in one frame to reduce round trips
	if _input_buffer.is_empty():
		return
	_send({ "type": MSG.INPUT_STATE, "inputs": _input_buffer })
	_input_buffer.clear()

func _send_heartbeat() -> void:
	_send({ "type": "ping", "ts": Time.get_ticks_msec() })

# ─────────────────────────────────────────────
#  RECEIVING
# ─────────────────────────────────────────────
func _receive_messages() -> void:
	while _socket.get_available_packet_count() > 0:
		var raw   : PackedByteArray = _socket.get_packet()
		var text  : String          = raw.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_dispatch(parsed as Dictionary)

func _dispatch(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"room_joined":
			_room_id    = msg.get("roomId",    "")
			_session_id = msg.get("sessionId", "")
			emit_signal("room_joined", _room_id, _session_id)
		"room_error":
			emit_signal("room_error", msg.get("code", 0), msg.get("message", ""))
		"state_patch":
			emit_signal("state_patch_received", msg.get("patch", {}))
		"player_joined":
			emit_signal("player_joined", msg.get("peerId", -1))
		"player_left":
			emit_signal("player_left", msg.get("peerId", -1))
		"pong":
			var latency := Time.get_ticks_msec() - msg.get("ts", 0)
			if OS.is_debug_build():
				print("[NetworkManager] RTT: %dms" % latency)
		_:
			push_warning("NetworkManager: Unknown message type — %s" % msg.get("type", "?"))

# ─────────────────────────────────────────────
#  RECONNECTION
# ─────────────────────────────────────────────
func _try_reconnect() -> void:
	if _reconnects >= RECONNECT_MAX:
		push_error("NetworkManager: Max reconnect attempts reached")
		return
	_reconnects += 1
	var delay := pow(2, _reconnects)   # Exponential back-off
	await get_tree().create_timer(delay).timeout
	connect_to_server(AuthManager.get_current_jwt())

# ─────────────────────────────────────────────
#  UTILITIES
# ─────────────────────────────────────────────
func _wait_for_connection() -> void:
	for _i in range(50):            # 5s timeout at 100ms steps
		await get_tree().create_timer(0.1).timeout
		if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_connected = true
			_reconnects = 0
			emit_signal("connected_to_server")
			return
	push_error("NetworkManager: Connection timeout")

func get_session_id() -> String:
	return _session_id

func is_connected_to_server() -> bool:
	return _connected
